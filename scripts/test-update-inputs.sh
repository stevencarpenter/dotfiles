#!/usr/bin/env bash
# Approval must precede installed-package changes; previews must run first.
set -euo pipefail
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
fixture="$(mktemp -d)"
trap 'rm -rf "$fixture"' EXIT
mkdir -p "$fixture/scripts" "$fixture/bin"
cp "$repo_root/scripts/update-inputs.sh" "$fixture/scripts/"
cat >"$fixture/scripts/sync-side-channels.sh" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
printf 'side-channels\n' >>"$TEST_LOG"
[ "${FAIL_STAGE:-}" != sync ]
SH
cat >"$fixture/bin/just" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
printf 'just %s\n' "$*" >>"$TEST_LOG"
case "$*" in
  'brew-upgrade --dry-run') [ "${FAIL_STAGE:-}" != brew-preview ] ;;
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
chmod +x "$fixture/bin/"* "$fixture/scripts/"*.sh
export PATH="$fixture/bin:$PATH" TEST_LOG="$fixture/commands.log"

run_update() { : >"$TEST_LOG"; "$fixture/scripts/update-inputs.sh" "$@"; }
assert_not_applied() {
  if rg -q '^(brew upgrade --yes|side-channels)' "$TEST_LOG"; then
    echo 'applied without approval' >&2; exit 1
  fi
}

# No, empty input, and EOF all decline.
for answer in n ''; do
  printf '%s\n' "$answer" | run_update >"$fixture/output"
  assert_not_applied
  rg -Fq 'Update cancelled.' "$fixture/output"
done
run_update </dev/null >"$fixture/output"
assert_not_applied

# Explicit approval and -y/--yes preview first, then apply once.
cat >"$fixture/expected" <<'LOG'
just brew-upgrade --dry-run
mise install --dry-run
mise upgrade --dry-run --no-prune
brew upgrade --yes
side-channels
LOG
for approval in prompt -y --yes; do
  if [ "$approval" = prompt ]; then
    printf 'y\n' | run_update >"$fixture/output"
  else
    run_update "$approval" </dev/null >"$fixture/output"
  fi
  diff -u "$fixture/expected" "$TEST_LOG"
done

# Unknown arguments fail before any preview.
for bad in abc --bogus 14; do
  if run_update "$bad" >"$fixture/output" 2>&1; then
    echo "accepted invalid argument: $bad" >&2; exit 1
  fi
  [ ! -s "$TEST_LOG" ]
done

# Every preview failure stops before applying, even with -y.
for stage in brew-preview mise-preview; do
  if FAIL_STAGE="$stage" run_update -y >"$fixture/output" 2>&1; then
    echo "ignored failure: $stage" >&2; exit 1
  fi
  assert_not_applied
done

# Apply failures propagate.
for stage in brew-apply sync; do
  if FAIL_STAGE="$stage" run_update -y >"$fixture/output" 2>&1; then
    echo "ignored apply failure: $stage" >&2; exit 1
  fi
done

echo 'update previews before approval, declines cleanly, and runs the side channels after approval'
