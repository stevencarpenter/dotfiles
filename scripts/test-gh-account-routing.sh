#!/usr/bin/env bash
# Assert that home/.local/bin/gh routes to the owner-mapped account, and — more
# importantly — that it declines to route in every case where routing would be
# wrong or surprising.
#
# Why this exists: the routing started life as a zsh function, which meant it
# silently did not apply to subprocesses. An agent running `gh pr create`
# through a non-interactive bash shell got the active (work) account in a
# personal repo and failed with:
#
#   GraphQL: <work-user> does not have the correct permissions to execute
#   `CreatePullRequest`
#
# Moving it onto PATH fixes that, but a PATH script shadows `gh` for EVERY
# caller on the machine — so the failure modes worth guarding are the
# fall-through cases, not the happy path. A wrapper that breaks `gh auth` or
# stomps a CI token is far worse than no wrapper.
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
cp "${wrapper}" "${tmp}/wrap/gh"

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
    echo "FAIL: ${label} — expected '${expected}', got '${actual}'" >&2
    failures=$((failures + 1))
  fi
}

token_for() { (cd "$1" && shift && gh "$@" 2>&1 | sed -n 's/^GH_TOKEN=//p'); }

set_remote() { git -C "${tmp}/repo" remote remove origin 2>/dev/null || true; git -C "${tmp}/repo" remote add origin "$1"; }

# --- routes for a mapped owner, across every remote spelling in use ----------
for url in \
  "git@github-dotfiles:stevencarpenter/dotfiles.git" \
  "git@github.com:stevencarpenter/dotfiles.git" \
  "https://github.com/stevencarpenter/dotfiles.git" \
  "ssh://git@github.com/stevencarpenter/dotfiles" \
  "git@github.com:stevencarpenter/dotfiles"; do
  set_remote "${url}"
  check "routes: ${url}" "tok-for-stevencarpenter" "$(token_for "${tmp}/repo" pr create)"
done

# --- declines to route where routing would be wrong --------------------------
set_remote "git@github.com:Lumin-Digital/la-dotfiles.git"
check "unmapped owner falls through" "<unset>" "$(token_for "${tmp}/repo" pr create)"

set_remote "git@github-dotfiles:stevencarpenter/dotfiles.git"

# `gh auth switch`/`auth login` refuse to run with GH_TOKEN set, and `auth
# status` would report the injected token instead of real account state.
check "gh auth is never routed" "<unset>" "$(token_for "${tmp}/repo" auth status)"

# CI sets these deliberately; overriding them would be surprising and wrong.
check "caller GH_TOKEN wins" "caller-tok" \
  "$(cd "${tmp}/repo" && GH_TOKEN=caller-tok gh pr create 2>&1 | sed -n 's/^GH_TOKEN=//p')"
check "caller GITHUB_TOKEN wins" "<unset>" \
  "$(cd "${tmp}/repo" && GITHUB_TOKEN=ci-tok gh pr create 2>&1 | sed -n 's/^GH_TOKEN=//p')"

# Explicit repository selectors outrank the current checkout. This is how
# gh-axi and cross-repo gh commands target a repository, so routing from $PWD's
# origin here would authenticate the requested repository as the wrong actor.
check "-R work target overrides personal PWD" "<unset>" \
  "$(token_for "${tmp}/repo" pr list -R Lumin-Digital/private)"
check "--repo work target overrides personal PWD" "<unset>" \
  "$(token_for "${tmp}/repo" pr list --repo Lumin-Digital/private)"
check "--repo= work target overrides personal PWD" "<unset>" \
  "$(token_for "${tmp}/repo" pr list --repo=Lumin-Digital/private)"
check "GH_REPO work target overrides personal PWD" "<unset>" \
  "$(cd "${tmp}/repo" && GH_REPO=Lumin-Digital/private gh pr list 2>&1 | sed -n 's/^GH_TOKEN=//p')"

set_remote "git@github.com:Lumin-Digital/la-dotfiles.git"
check "-R personal target routes from work PWD" "tok-for-stevencarpenter" \
  "$(token_for "${tmp}/repo" pr list -R stevencarpenter/dotfiles)"
check "host-qualified github.com target routes" "tok-for-stevencarpenter" \
  "$(token_for "${tmp}/repo" pr list -R github.com/stevencarpenter/dotfiles)"
check "host-qualified enterprise target does not receive github.com token" "<unset>" \
  "$(token_for "${tmp}/repo" pr list -R github.example.com/stevencarpenter/dotfiles)"
check "command-line repo overrides GH_REPO" "<unset>" \
  "$(cd "${tmp}/repo" && GH_REPO=stevencarpenter/dotfiles gh pr list -R Lumin-Digital/private 2>&1 | sed -n 's/^GH_TOKEN=//p')"

set_remote "git@github-dotfiles:stevencarpenter/dotfiles.git"
check "non-github GH_HOST never receives github.com token" "<unset>" \
  "$(cd "${tmp}/repo" && GH_HOST=github.example.com gh pr list 2>&1 | sed -n 's/^GH_TOKEN=//p')"

set_remote "git@gitlab.com:stevencarpenter/dotfiles.git"
check "same owner on a non-GitHub remote does not route" "<unset>" \
  "$(token_for "${tmp}/repo" pr list)"

set_remote "git@github-dotfiles:stevencarpenter/dotfiles.git"

check "outside a git repo falls through" "<unset>" "$(token_for "${tmp}/norepo" pr list)"

# Not being logged into the mapped account is not worth failing a command over.
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
# command also exits 127 — which would make this check pass for the wrong
# reason. Use it only where it exists.
# Resolve to an ABSOLUTE path: the subshell below strips PATH down to the
# wrapper dir, so a bare `timeout` would not resolve there either.
if to_bin="$(command -v timeout 2>/dev/null)" && [ -n "${to_bin}" ]; then
  to=("${to_bin}" 10)
else
  to=()
fi
# /usr/bin:/bin so the `#!/usr/bin/env bash` shebang and `git` still resolve —
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

# --- a shim that defers to PATH must not ping-pong ---------------------------
# THE BUG THIS GUARDS: a mise shim whose tool is not active in the current
# directory does not error — it falls back to a PATH lookup, finds this wrapper
# again, and the two call each other forever. It hangs rather than failing, so
# without a bounded test it looks like a slow network call.
#
# Layout mirrors the real one: wrapper dir first, then a shim that re-execs
# whatever `gh` PATH offers next, then the genuine binary.
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
check "shim PATH-fallback still routes" "tok-for-stevencarpenter" \
  "$(printf '%s\n' "${out}" | sed -n 's/^GH_TOKEN=//p')"

if [ "${failures}" -ne 0 ]; then
  echo "${failures} check(s) failed" >&2
  exit 1
fi
echo "all gh routing checks passed"
