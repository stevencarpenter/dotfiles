#!/usr/bin/env bash
# Prove the Homebrew audit only performs inventory reads.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fixture="$(mktemp -d "${TMPDIR:-/tmp}/homebrew-audit-test.XXXXXX")"
trap 'rm -rf "$fixture"' EXIT

touch "$fixture/Brewfile"

cat >"$fixture/brew" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >>"$BREW_COMMAND_LOG"

case "$*" in
  "bundle list --file=$HOMEBREW_BUNDLE_FILE --formula")
    printf 'declared-formula\n'
    ;;
  "bundle list --file=$HOMEBREW_BUNDLE_FILE --cask")
    printf 'declared-cask\n'
    ;;
  "bundle list --file=$HOMEBREW_BUNDLE_FILE --tap")
    printf 'declared/tap\n'
    ;;
  "list --formula --full-name")
    printf 'declared-formula\nextra-formula\n'
    ;;
  "leaves")
    printf 'declared-formula\nextra-formula\n'
    ;;
  "list --cask")
    printf 'declared-cask\nextra-cask\n'
    ;;
  "tap")
    printf 'declared/tap\nextra/tap\n'
    ;;
  *)
    echo "unexpected brew command: $*" >&2
    exit 1
    ;;
esac
EOF
chmod +x "$fixture/brew"

output="$(
  BREW_BIN="$fixture/brew" \
    BREW_COMMAND_LOG="$fixture/commands.log" \
    HOMEBREW_BUNDLE_FILE="$fixture/Brewfile" \
    "$repo_root/scripts/audit-homebrew.sh"
)"

for expected in \
  "extra-formula" \
  "extra-cask" \
  "extra/tap" \
  "No packages, casks, taps, caches, or files were changed"; do
  if ! printf '%s\n' "$output" | rg -Fq "$expected"; then
    echo "audit output omitted: $expected" >&2
    exit 1
  fi
done

if rg -iq 'cleanup|uninstall|untap|remove|zap' "$fixture/commands.log"; then
  echo "Homebrew audit invoked a mutating command:" >&2
  cat "$fixture/commands.log" >&2
  exit 1
fi

if ! rg -Fq 'scripts/audit-homebrew.sh' "$repo_root/Justfile"; then
  echo "brew-audit does not delegate to the guarded audit script" >&2
  exit 1
fi

echo "Homebrew audit is inventory-only"
