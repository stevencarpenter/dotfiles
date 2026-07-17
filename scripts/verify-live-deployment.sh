#!/usr/bin/env bash
# Read-only verification for the live personal-mac Nix cutover.
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd -P)"
home_dir="${HOME:?}"
failures=0

pass() { printf '[ok] %s\n' "$*"; }
warn() { printf '[warn] %s\n' "$*" >&2; }
fail() { printf '[error] %s\n' "$*" >&2; failures=$((failures + 1)); }

if [ "$repo_root" = "$home_dir/.dotfiles" ] && [ -d "$repo_root/.git" ]; then
  pass "canonical dotfiles checkout is a standalone Git repository"
else
  fail "expected standalone repository at $home_dir/.dotfiles"
fi

current_system="$(readlink /run/current-system 2>/dev/null || true)"
expected_system="$(nix eval --raw "$repo_root#darwinConfigurations.personal-mac.system" 2>/dev/null || true)"
if [ -n "$current_system" ] && [ "$current_system" = "$expected_system" ]; then
  pass "running system matches the personal-mac flake output"
else
  fail "running system does not match the personal-mac flake output"
fi

revision="$(nix eval --raw "$repo_root#darwinConfigurations.personal-mac.config.system.configurationRevision" 2>/dev/null || true)"
if [ -n "$revision" ]; then
  pass "system configuration revision is recorded: $revision"
else
  fail "system configuration revision is empty"
fi

for path in \
  "$home_dir/.config/zsh/.zshrc" \
  "$home_dir/.config/nvim" \
  "$home_dir/.config/mcp/mcp-master.json" \
  "$home_dir/.config/aerospace/aerospace.toml"; do
  resolved="$(realpath "$path" 2>/dev/null || true)"
  case "$resolved" in
    "$repo_root"/*) pass "$path resolves into the canonical checkout" ;;
    *) fail "$path resolves outside the canonical checkout: ${resolved:-missing}" ;;
  esac
done

for path in \
  "$home_dir/.config/opencode/skills/use-railway" \
  "$home_dir/.codex/skills/playwright" \
  "$home_dir/.codex/skills/use-railway" \
  "$home_dir/.cursor/skills/use-railway" \
  "$home_dir/.copilot/skills/use-railway" \
  "$home_dir/.junie/skills/gh-axi"; do
  resolved="$(realpath "$path" 2>/dev/null || true)"
  case "$resolved" in
    "$repo_root"/skills/personal/*) pass "$path resolves into canonical personal skills" ;;
    *) fail "$path retains a legacy or missing skill target: ${resolved:-missing}" ;;
  esac
done

python_bin="/etc/profiles/per-user/$USER/bin/python3"
if [ ! -x "$python_bin" ]; then
  python_bin="$(command -v python3 || true)"
fi
if [ -x "$python_bin" ]; then
  if PYTHONNOUSERSITE=1 PYTHONPATH="$repo_root/mcp_sync/src" \
    "$python_bin" -m mcp_sync --check \
      --machine-config "$home_dir/.config/mcp/machine/personal.json"; then
    pass "all generated MCP targets are current"
  else
    fail "generated MCP targets are missing or drifted"
  fi
else
  fail "Python 3 is unavailable for MCP verification"
fi

skills_state="$home_dir/.local/state/mcp-sync/skills-state.json"
if [ -s "$skills_state" ] && jq -e --arg root "$repo_root/skills/personal/" \
  '[.deployed[] | select(.mode == "symlink") | .target | startswith($root)] | all' \
  "$skills_state" >/dev/null; then
  pass "managed personal skill state points into the canonical checkout"
else
  fail "managed personal skill state is absent or retains a legacy root"
fi

for secret in "$home_dir/.config/zsh/.personal.env" "$home_dir/.ssh/config"; do
  if [ -s "$secret" ] && [ "$(stat -f '%Lp' "$secret" 2>/dev/null || true)" = "600" ] \
    && ! rg -q 'op://' "$secret"; then
    pass "$secret is populated, mode 0600, and fully rendered"
  else
    fail "$secret is missing, insecure, empty, or contains unresolved op refs"
  fi
done

age_key="$home_dir/.config/age/keys.txt"
if [ -s "$age_key" ] && [ "$(stat -f '%Lp' "$age_key" 2>/dev/null || true)" = "600" ]; then
  pass "age identity is present outside the legacy chezmoi root"
else
  fail "age identity is missing or not mode 0600 at $age_key"
fi

if op whoami >/dev/null 2>&1; then
  pass "1Password CLI is authenticated for future secret refreshes"
else
  warn "1Password CLI is signed out; existing rendered secrets are valid but refreshes will skip"
fi

if [ "$(dscl . -read "/Users/$USER" UserShell 2>/dev/null | awk '{print $2}')" = "/bin/zsh" ]; then
  pass "login shell is /bin/zsh"
else
  fail "login shell is not /bin/zsh"
fi

for process in AeroSpace sketchybar borders; do
  if pgrep -f "$process" >/dev/null; then
    pass "$process is running"
  else
    fail "$process is not running"
  fi
done

if [ "$(defaults read com.apple.menuextra.clock ShowDate 2>/dev/null || true)" = "0" ] \
  && [ "$(defaults read com.apple.dock wvous-tr-corner 2>/dev/null || true)" = "13" ] \
  && [ "$(defaults read com.apple.dock wvous-br-corner 2>/dev/null || true)" = "14" ]; then
  pass "review-sensitive macOS defaults are applied"
else
  fail "review-sensitive macOS defaults do not match the declaration"
fi

if [ "$failures" -ne 0 ]; then
  printf '%s live deployment check(s) failed\n' "$failures" >&2
  exit 1
fi
pass "personal-mac is fully cut over"
