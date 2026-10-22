#!/usr/bin/env bash
# Assert that scripts/host-capability.sh reads dfm/profiles/<host>.toml, the bound profile and dfm-bundle.toml.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

export DOTFILES_HOST=personal-mac

[ "$(scripts/host-capability.sh --identity)" = personal ] || fail "identity"
[ "$(scripts/host-capability.sh mcp)" = 1 ] || fail "mcp should be 1"
[ "$(scripts/host-capability.sh infra)" = 0 ] || fail "infra should be 0"
[ "$(scripts/host-capability.sh agents)" = 1 ] || fail "agents should be 1"
[ "$(scripts/host-capability.sh skills)" = 1 ] || fail "skills should be 1"
[ "$(scripts/host-capability.sh agent_journal)" = 1 ] || fail "agent_journal should map to the agent-journal module"

if scripts/host-capability.sh bogus 2>/dev/null; then fail "bogus should exit 2"; fi
if scripts/host-capability.sh mcp no-such-host 2>/dev/null; then fail "unknown host should exit 2"; fi
if scripts/host-capability.sh 'bad name' 2>/dev/null; then fail "invalid name should exit 2"; fi

# Without a named host, the profile that `dfm binding` names wins, also outside this checkout.
fixture="$(mktemp -d)"
trap 'rm -rf "$fixture"' EXIT
printf 'modules = ["work", "mcp", "dev"]\n' >"$fixture/work-mac.toml"
cat >"$fixture/dfm" <<'EOF'
#!/usr/bin/env bash
[ "$1" = binding ] || exit 2
echo "bound profile=$FAKE_PROFILE machine_id=work-mac"
EOF
chmod +x "$fixture/dfm"
unset DOTFILES_HOST
export DFM_BIN="$fixture/dfm" FAKE_PROFILE="$fixture/work-mac.toml"

[ "$(scripts/host-capability.sh --identity)" = work ] || fail "bound identity should be work"
[ "$(scripts/host-capability.sh mcp)" = 1 ] || fail "bound mcp should be 1"
[ "$(scripts/host-capability.sh skills)" = 0 ] || fail "bound skills should be 0"
[ "$(scripts/host-capability.sh --identity personal-mac)" = personal ] || fail "a named host should win"
FAKE_PROFILE="$fixture/missing.toml"
if scripts/host-capability.sh mcp 2>/dev/null; then fail "a missing bound profile should exit 2"; fi
printf 'modules = [\n  "work",\n  "mcp",\n]\n' >"$fixture/multi-line.toml"
FAKE_PROFILE="$fixture/multi-line.toml"
if scripts/host-capability.sh mcp 2>/dev/null; then fail "a multi-line modules list should exit 2"; fi

echo "ok: host-capability.sh resolves personal-mac and a bound external profile"
