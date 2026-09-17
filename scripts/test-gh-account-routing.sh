#!/usr/bin/env bash
# Verify owner-based gh account routing, auth-command passthrough, and CI tokens.
# The PATH wrapper must work in non-interactive subprocesses too.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
wrapper="${repo_root}/home/.local/bin/gh"

[ -x "${wrapper}" ] || {
  echo "FAIL: ${wrapper} is missing or not executable" >&2
  exit 1
}

tmp="$(mktemp -d)"
trap 'rm -rf "${tmp}"' EXIT
mkdir -p "${tmp}/wrap" "${tmp}/realbin" "${tmp}/repo" "${tmp}/norepo"
# Account choices are configuration. Replace only the mapping in the isolated
# copy so routing, precedence, and credential boundaries use synthetic owners.
awk '
  /^account_for_owner\(\)/ {
    print "account_for_owner() {"
    print "  case \"$1\" in fixture-owner) echo fixture-account ;; *) return 1 ;; esac"
    print "}"
    mapping = 1
    next
  }
  mapping && /^}/ { mapping = 0; next }
  !mapping { print }
' "${wrapper}" >"${tmp}/wrap/gh"
chmod +x "${tmp}/wrap/gh"

# Stand-in for the real gh: prints the token it was handed, and answers
# `auth token --user X` with a recognizable per-account value.
cat >"${tmp}/realbin/gh" <<'FAKE'
#!/usr/bin/env bash
if [ "${1:-}" = auth ] && [ "${2:-}" = token ]; then printf 'tok-for-%s\n' "$4"; exit 0; fi
echo "argv=$*"
echo "GH_TOKEN=${GH_TOKEN:-<unset>}"
FAKE
chmod +x "${tmp}/realbin/gh"

git -C "${tmp}/repo" init -q
export PATH="${tmp}/wrap:${tmp}/realbin:${PATH}"

failures=0
check() {
  local label="$1" expected="$2" actual="$3"
  if [ "${actual}" = "${expected}" ]; then
    echo "ok: ${label}"
  else
    echo "FAIL: ${label}: expected '${expected}', got '${actual}'" >&2
    failures=$((failures + 1))
  fi
}

token_for() { (cd "$1" && shift && gh "$@" 2>&1 | sed -n 's/^GH_TOKEN=//p'); }

set_remote() { git -C "${tmp}/repo" remote remove origin 2>/dev/null || true; git -C "${tmp}/repo" remote add origin "$1"; }

# --- routes for a mapped owner, across every remote spelling in use ----------
for url in \
  "git@github-dotfiles:fixture-owner/dotfiles.git" \
  "git@github.com:fixture-owner/dotfiles.git" \
  "https://github.com/fixture-owner/dotfiles.git" \
  "ssh://git@github.com/fixture-owner/dotfiles" \
  "git@github.com:fixture-owner/dotfiles"; do
  set_remote "${url}"
  check "routes: ${url}" "tok-for-fixture-account" "$(token_for "${tmp}/repo" pr create)"
done

# --- declines to route where routing would be wrong --------------------------
set_remote "git@github.com:unmapped-owner/la-dotfiles.git"
check "unmapped owner falls through" "<unset>" "$(token_for "${tmp}/repo" pr create)"

set_remote "git@github-dotfiles:fixture-owner/dotfiles.git"

# `gh auth switch`/`auth login` refuse to run with GH_TOKEN set, and `auth
# status` would report the injected token instead of real account state.
check "gh auth is never routed" "<unset>" "$(token_for "${tmp}/repo" auth status)"

# Preserve explicit CI authentication tokens.
check "caller GH_TOKEN wins" "caller-tok" \
  "$(cd "${tmp}/repo" && GH_TOKEN=caller-tok gh pr create 2>&1 | sed -n 's/^GH_TOKEN=//p')"
check "caller GITHUB_TOKEN wins" "<unset>" \
  "$(cd "${tmp}/repo" && GITHUB_TOKEN=ci-tok gh pr create 2>&1 | sed -n 's/^GH_TOKEN=//p')"

# Explicit repository selectors outrank the current checkout. This is how
# gh-axi and cross-repo gh commands target a repository, so routing from $PWD's
# origin here would authenticate the requested repository as the wrong actor.
check "-R work target overrides personal PWD" "<unset>" \
  "$(token_for "${tmp}/repo" pr list -R unmapped-owner/private)"
check "--repo work target overrides personal PWD" "<unset>" \
  "$(token_for "${tmp}/repo" pr list --repo unmapped-owner/private)"
check "--repo= work target overrides personal PWD" "<unset>" \
  "$(token_for "${tmp}/repo" pr list --repo=unmapped-owner/private)"
check "GH_REPO work target overrides personal PWD" "<unset>" \
  "$(cd "${tmp}/repo" && GH_REPO=unmapped-owner/private gh pr list 2>&1 | sed -n 's/^GH_TOKEN=//p')"

set_remote "git@github.com:unmapped-owner/la-dotfiles.git"
check "-R personal target routes from work PWD" "tok-for-fixture-account" \
  "$(token_for "${tmp}/repo" pr list -R fixture-owner/dotfiles)"
check "host-qualified github.com target routes" "tok-for-fixture-account" \
  "$(token_for "${tmp}/repo" pr list -R github.com/fixture-owner/dotfiles)"
check "host-qualified enterprise target does not receive github.com token" "<unset>" \
  "$(token_for "${tmp}/repo" pr list -R github.example.com/fixture-owner/dotfiles)"
check "command-line repo overrides GH_REPO" "<unset>" \
  "$(cd "${tmp}/repo" && GH_REPO=fixture-owner/dotfiles gh pr list -R unmapped-owner/private 2>&1 | sed -n 's/^GH_TOKEN=//p')"

set_remote "git@github-dotfiles:fixture-owner/dotfiles.git"
check "non-github GH_HOST never receives github.com token" "<unset>" \
  "$(cd "${tmp}/repo" && GH_HOST=github.example.com gh pr list 2>&1 | sed -n 's/^GH_TOKEN=//p')"

set_remote "git@gitlab.com:fixture-owner/dotfiles.git"
check "same owner on a non-GitHub remote does not route" "<unset>" \
  "$(token_for "${tmp}/repo" pr list)"

set_remote "git@github-dotfiles:fixture-owner/dotfiles.git"

check "outside a git repo falls through" "<unset>" "$(token_for "${tmp}/norepo" pr list)"

# Missing mapped credentials fall back to gh's active account.
cat >"${tmp}/realbin/gh" <<'FAKE'
#!/usr/bin/env bash
if [ "${1:-}" = auth ] && [ "${2:-}" = token ]; then exit 1; fi
echo "GH_TOKEN=${GH_TOKEN:-<unset>}"
FAKE
chmod +x "${tmp}/realbin/gh"
check "mapped account not logged in falls through" "<unset>" "$(token_for "${tmp}/repo" pr create)"

# --- the wrapper must not find itself ----------------------------------------
# If self-exclusion regressed, the wrapper would re-exec itself forever. Run it
# with ONLY the wrapper dir on PATH: it must fail fast with 127, not hang.
# macOS ships no `timeout` (it is gtimeout from coreutils), and a missing
# command also exits 127, which would make this check pass for the wrong
# reason. Use it only where it exists.
# Resolve to an ABSOLUTE path: the subshell below strips PATH down to the
# wrapper dir, so a bare `timeout` would not resolve there either.
if to_bin="$(command -v timeout 2>/dev/null)" && [ -n "${to_bin}" ]; then
  to=("${to_bin}" 10)
else
  to=()
fi
# /usr/bin:/bin so the `#!/usr/bin/env bash` shebang and `git` still resolve;
# neither ships a `gh`, which is the condition under test.
out="$(cd "${tmp}/repo" && PATH="${tmp}/wrap:/usr/bin:/bin" "${to[@]}" "${tmp}/wrap/gh" pr create 2>&1)" && rc=0 || rc=$?
check "no real gh on PATH exits 127" "127" "${rc}"
case "${out}" in
*"real gh binary not found"*) echo "ok: reports a usable error" ;;
*)
  echo "FAIL: expected a 'real gh binary not found' message, got: ${out}" >&2
  failures=$((failures + 1))
  ;;
esac

# A mise shim with an inactive tool falls back to PATH and can recurse into
# the wrapper. Test wrapper -> shim -> genuine binary with a timeout.
mkdir -p "${tmp}/shim" "${tmp}/realbin2"
cat >"${tmp}/shim/gh" <<'SHIM'
#!/usr/bin/env bash
# Stand-in for `mise shims/gh` with the tool inactive: defer to PATH.
exec gh "$@"
SHIM
chmod +x "${tmp}/shim/gh"
cat >"${tmp}/realbin2/gh" <<'FAKE'
#!/usr/bin/env bash
if [ "${1:-}" = auth ] && [ "${2:-}" = token ]; then printf 'tok-for-%s\n' "$4"; exit 0; fi
echo "GH_TOKEN=${GH_TOKEN:-<unset>}"
FAKE
chmod +x "${tmp}/realbin2/gh"

bounce_path="${tmp}/wrap:${tmp}/shim:${tmp}/realbin2:/usr/bin:/bin"
out="$(cd "${tmp}/repo" && PATH="${bounce_path}" "${to[@]}" gh pr create 2>&1)" && rc=0 || rc=$?
check "shim PATH-fallback terminates (no hang)" "0" "${rc}"
check "shim PATH-fallback still routes" "tok-for-fixture-account" \
  "$(printf '%s\n' "${out}" | sed -n 's/^GH_TOKEN=//p')"

if [ "${failures}" -ne 0 ]; then
  echo "${failures} check(s) failed" >&2
  exit 1
fi
echo "all gh routing checks passed"
