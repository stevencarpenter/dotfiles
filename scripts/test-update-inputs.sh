#!/usr/bin/env bash
# Approval must precede installed-package changes; preparation must be reversible.
set -euo pipefail
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
fixture="$(mktemp -d)"
trap 'rm -rf "$fixture"' EXIT
mkdir -p "$fixture/scripts" "$fixture/versions" "$fixture/bin"
cp "$repo_root/scripts/update-inputs.sh" "$fixture/scripts/"
cat >"$fixture/scripts/host-detect.sh" <<'SH'
detect_host() { echo personal-mac; }
SH
cat >"$fixture/scripts/update-unstable.sh" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
printf 'unstable %s\n' "$*" >>"$TEST_LOG"
printf 'candidate-after\n' > versions/nixpkgs-unstable-candidate.json
[ "${FAIL_STAGE:-}" != unstable ]
SH
cat >"$fixture/bin/nix" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
printf 'nix %s\n' "$*" >>"$TEST_LOG"
case "$*" in
  'flake update nixpkgs nix-darwin home-manager') echo lock-after > flake.lock ;;
  'flake check --no-update-lock-file --no-build --all-systems')
    [ "${FAIL_STAGE:-}" != check ] ;;
  'build --no-link --print-out-paths --no-update-lock-file --option sandbox false .#darwinConfigurations.'*)
    [ "${FAIL_STAGE:-}" != build ]
    echo /nix/store/reviewed-system ;;
  'store diff-closures /run/current-system /nix/store/reviewed-system') echo 'package: 1.0 -> 1.1' ;;
  *) echo "unexpected nix command: $*" >&2; exit 1 ;;
esac
SH
cat >"$fixture/bin/just" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
printf 'just %s\n' "$*" >>"$TEST_LOG"
case "$*" in
  'brew-upgrade --dry-run') [ "${FAIL_STAGE:-}" != brew-preview ] ;;
  'sync '*) [ "${FAIL_STAGE:-}" != sync ] ;;
  *) echo "unexpected just command: $*" >&2; exit 1 ;;
esac
SH
cat >"$fixture/bin/brew" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
printf 'brew %s\n' "$*" >>"$TEST_LOG"
[ "$*" = 'upgrade --yes' ]
[ "$HOMEBREW_NO_AUTO_UPDATE" = 1 ]
[ "${FAIL_STAGE:-}" != brew-apply ]
SH
cat >"$fixture/bin/mise" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
printf 'mise %s\n' "$*" >>"$TEST_LOG"
case "$*" in
  'install --dry-run'|'upgrade --dry-run --no-prune') ;;
  *) exit 1 ;;
esac
[ "${FAIL_STAGE:-}" != mise-preview ]
SH
cat >"$fixture/scripts/update-firstmate.sh" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
printf 'firstmate %s\n' "$*" >>"$TEST_LOG"
stage=firstmate-preview
[ "$1" = --apply ] && stage=firstmate-apply
[ "${FAIL_STAGE:-}" != "$stage" ]
SH
chmod +x "$fixture/bin/"* "$fixture/scripts/"*.sh
export PATH="$fixture/bin:$PATH" TEST_LOG="$fixture/commands.log"
unset DOTFILES_HOST

reset_fixture() {
  echo flake-with-user-edits >"$fixture/flake.nix"
  echo lock-with-user-edits >"$fixture/flake.lock"
  echo candidate-before >"$fixture/versions/nixpkgs-unstable-candidate.json"
  : >"$TEST_LOG"
}
run_update() { "$fixture/scripts/update-inputs.sh" "$@"; }
assert_restored() {
  [ "$(cat "$fixture/flake.nix")" = flake-with-user-edits ]
  [ "$(cat "$fixture/flake.lock")" = lock-with-user-edits ]
  [ "$(cat "$fixture/versions/nixpkgs-unstable-candidate.json")" = candidate-before ]
  if rg -q '^(brew upgrade --yes|just sync)' "$TEST_LOG"; then
    echo 'applied without approval' >&2; exit 1
  fi
}

# No, empty input, and EOF all decline. Existing uncommitted edits survive.
for answer in n ''; do
  reset_fixture
  printf '%s\n' "$answer" | run_update >"$fixture/output"
  assert_restored
  rg -Fq 'Update cancelled.' "$fixture/output"
done
reset_fixture
run_update </dev/null >"$fixture/output"
assert_restored
rg -Fxq 'unstable 1 personal-mac' "$TEST_LOG"

# A newly created soak candidate is removed on cancellation.
reset_fixture
rm "$fixture/versions/nixpkgs-unstable-candidate.json"
run_update </dev/null >"$fixture/output"
[ ! -e "$fixture/versions/nixpkgs-unstable-candidate.json" ]

# Explicit approval and -y/--yes preserve the prepared inputs and apply once.
for approval in prompt -y --yes; do
  reset_fixture
  if [ "$approval" = prompt ]; then
    printf 'y\n' | run_update 14 personal-mac >"$fixture/output"
  else
    run_update "$approval" 14 personal-mac </dev/null >"$fixture/output"
  fi
  [ "$(cat "$fixture/flake.lock")" = lock-after ]
  [ "$(cat "$fixture/versions/nixpkgs-unstable-candidate.json")" = candidate-after ]
  cat >"$fixture/expected" <<'LOG'
nix flake update nixpkgs nix-darwin home-manager
unstable 14 personal-mac
nix flake check --no-update-lock-file --no-build --all-systems
nix build --no-link --print-out-paths --no-update-lock-file --option sandbox false .#darwinConfigurations.personal-mac.system
nix store diff-closures /run/current-system /nix/store/reviewed-system
just brew-upgrade --dry-run
mise install --dry-run
mise upgrade --dry-run --no-prune
firstmate personal-mac
brew upgrade --yes
firstmate --apply personal-mac
just sync personal-mac
LOG
  diff -u "$fixture/expected" "$TEST_LOG"
done

# Host forwarding and validation happen before preparation.
reset_fixture
DOTFILES_HOST=external-host run_update -y >"$fixture/output"
rg -Fxq 'just sync external-host' "$TEST_LOG"
for bad in abc 4000 -1 --bogus 18446744073709551616; do
  reset_fixture
  if run_update "$bad" >"$fixture/output" 2>&1; then
    echo "accepted invalid argument: $bad" >&2; exit 1
  fi
  [ ! -s "$TEST_LOG" ]
done
reset_fixture
if run_update -y 7 'invalid;host' >"$fixture/output" 2>&1; then
  echo 'accepted an invalid host' >&2; exit 1
fi
[ ! -s "$TEST_LOG" ]

# Every preparation failure restores inputs, even with -y.
for stage in unstable check build brew-preview mise-preview firstmate-preview; do
  reset_fixture
  if FAIL_STAGE="$stage" run_update -y >"$fixture/output" 2>&1; then
    echo "ignored failure: $stage" >&2; exit 1
  fi
  assert_restored
done

# After applying begins, do not imply installed packages were rolled back.
for stage in brew-apply firstmate-apply sync; do
  reset_fixture
  if FAIL_STAGE="$stage" run_update -y >"$fixture/output" 2>&1; then
    echo "ignored apply failure: $stage" >&2; exit 1
  fi
  [ "$(cat "$fixture/flake.lock")" = lock-after ]
  rg -Fq 'Some steps may have completed' "$fixture/output"
done

echo 'update previews before approval, restores declined/failed preparation, and reuses sync'
