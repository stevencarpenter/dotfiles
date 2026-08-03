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

if [ "$(nix config show sandbox 2>/dev/null || true)" = "false" ]; then
  pass "Nix daemon uses the explicit macOS 27-compatible sandbox policy"
else
  fail "Nix daemon sandbox policy does not match the macOS 27 compatibility setting"
fi

for daemon in org.nixos.nix-gc org.nixos.nix-optimise; do
  if launchctl print "system/$daemon" >/dev/null 2>&1; then
    pass "$daemon maintenance daemon is loaded"
  else
    fail "$daemon maintenance daemon is not loaded"
  fi
done

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

# ~/.ssh/config is no longer a rendered secret — it is the tracked universal
# base (tier 1), a plain symlink with no op:// reference. Only the tier-2
# personal-host fragment is rendered, so that is what carries the 0600 contract.
for secret in "$home_dir/.config/zsh/.personal.env" "$home_dir/.ssh/config.d/10-homelab.conf"; do
  if [ -s "$secret" ] && [ "$(/usr/bin/stat -f '%Lp' "$secret" 2>/dev/null || true)" = "600" ] \
    && ! rg -q 'op://' "$secret"; then
    pass "$secret is populated, mode 0600, and has no unresolved references"
  else
    fail "$secret is missing, insecure, empty, or contains unresolved op refs"
  fi
done

env_template="$repo_root/home/.config/zsh/.personal.env.tpl"
live_env="$home_dir/.config/zsh/.personal.env"
if /usr/bin/diff -q \
  <(rg -o '^export [A-Z_][A-Z0-9_]*=' "$env_template" | /usr/bin/sed 's/^export //; s/=$//' | /usr/bin/sort) \
  <(rg -o '^export [A-Z_][A-Z0-9_]*=' "$live_env" | /usr/bin/sed 's/^export //; s/=$//' | /usr/bin/sort) \
  >/dev/null; then
  pass "personal environment variable set matches the 1Password template"
else
  fail "personal environment variable set is stale or incomplete"
fi

ssh_config="$home_dir/.ssh/config"
include_line="$(rg -n -m1 '^Include ~/.ssh/config.d/\*$' "$ssh_config" || true)"
first_host_line="$(rg -n -m1 '^Host([[:space:]]|$)' "$ssh_config" || true)"
include_line="${include_line%%:*}"
first_host_line="${first_host_line%%:*}"
if [ -n "$include_line" ] && [ -n "$first_host_line" ] \
  && [ "$include_line" -lt "$first_host_line" ]; then
  pass "SSH external-fragment include exists before every Host block"
else
  fail "SSH config is stale or the external-fragment include is misordered"
fi

# Tier 1 must be the tracked base, not a leftover rendered file: a real file
# here means an old op-rendered ~/.ssh/config survived and is now shadowing the
# universal base (agent, multiplexing, and the config.d seam would all be stale).
if [ -L "$ssh_config" ] && [ "$(/usr/bin/readlink "$ssh_config")" = "$repo_root/home/.ssh/config" ]; then
  pass "SSH universal base is the tracked out-of-store symlink"
else
  fail "~/.ssh/config is not the tracked base symlink (stale rendered file?)"
fi

last_render="$home_dir/.config/op/.last-render"
if [ -f "$last_render" ]; then
  last_render_age=$(( $(/bin/date +%s) - $(/usr/bin/stat -f '%m' "$last_render") ))
  if [ "$last_render_age" -le $((7 * 24 * 60 * 60)) ]; then
    pass "1Password render sentinel is present and fresh"
  else
    fail "1Password render sentinel is older than 7 days"
  fi
else
  fail "1Password render sentinel is missing"
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
