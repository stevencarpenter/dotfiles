#!/usr/bin/env bash
# Assert that brew-sync.sh and audit-homebrew.sh add Brewfile.<identity> to the shared Brewfile.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fixture="$(mktemp -d)"
fixture="$(cd "$fixture" && pwd -P)"
trap 'rm -rf "$fixture"' EXIT

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

repo="$fixture/repo"
mkdir -p "$repo/scripts" "$repo/dfm/profiles" "$fixture/bin" "$fixture/prefix"
cp "$repo_root/scripts/brew-sync.sh" "$repo_root/scripts/audit-homebrew.sh" \
  "$repo_root/scripts/host-capability.sh" "$repo/scripts/"
cp "$repo_root/dfm-bundle.toml" "$repo/dfm-bundle.toml"
cp "$repo_root/dfm/profiles/personal-mac.toml" "$repo/dfm/profiles/personal-mac.toml"
# No machine name matches, so an unnamed host has no identity.
printf 'detect_host() { return 1; }\n' >"$repo/scripts/host-detect.sh"
printf 'brew "shared"\n' >"$repo/Brewfile"
printf 'brew "only-personal"\n' >"$repo/Brewfile.personal"

cat >"$fixture/bin/brew" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$BREW_LOG"
[ "$1" = --prefix ] && printf '%s\n' "$FAKE_PREFIX"
exit 0
EOF
cat >"$fixture/bin/dfm" <<'EOF'
#!/usr/bin/env bash
echo unbound
EOF
chmod +x "$fixture/bin/brew" "$fixture/bin/dfm"
export PATH="$fixture/bin:$PATH" FAKE_PREFIX="$fixture/prefix" DFM_BIN="$fixture/dfm"
unset HOMEBREW_BUNDLE_FILE

run() { # run <log> <command...>: run with an empty brew log
  local log="$1"
  shift
  : >"$log"
  BREW_LOG="$log" "$@"
}

run "$fixture/apply.log" env DOTFILES_HOST=personal-mac "$repo/scripts/brew-sync.sh"
rg -qxF "bundle --file $repo/Brewfile --no-upgrade" "$fixture/apply.log" || fail "shared Brewfile not applied"
rg -qxF "bundle --file $repo/Brewfile.personal --no-upgrade" "$fixture/apply.log" ||
  fail "Brewfile.personal not applied for the personal identity"

run "$fixture/check.log" env DOTFILES_HOST=personal-mac "$repo/scripts/brew-sync.sh" --check
[ "$(rg -c '^bundle check ' "$fixture/check.log")" = 2 ] || fail "--check should check both Brewfiles"

run "$fixture/none.log" "$repo/scripts/brew-sync.sh" 2>"$fixture/none.err"
rg -q 'Brewfile.personal' "$fixture/none.log" && fail "no identity should apply the shared Brewfile only"
rg -qF 'note: no host identity' "$fixture/none.err" || fail "no identity should print a note"

run "$fixture/audit.log" env DOTFILES_HOST=personal-mac BREW_BIN="$fixture/bin/brew" \
  "$repo/scripts/audit-homebrew.sh" >/dev/null
rg -qxF "bundle list --file=$repo/Brewfile.personal --formula" "$fixture/audit.log" ||
  fail "the audit should declare Brewfile.personal for the personal identity"

echo "ok: brew-sync.sh and audit-homebrew.sh add Brewfile.<identity> to the shared Brewfile"
