#!/usr/bin/env bash
# Work-host side-channel sync must never contact the personal agent registry.
#
# Never invoke real 1Password: keep OP_BIN pointed at the fixture mock and
# PATH restricted to "$fixture/bin:/usr/bin:/bin".
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fixture="$(mktemp -d)"
trap 'rm -rf "$fixture"' EXIT

if [ ! -x "$repo_root/scripts/sync-side-channels.sh" ]; then
  echo "missing executable scripts/sync-side-channels.sh" >&2
  exit 1
fi

mkdir -p "$fixture/bin" "$fixture/home"

cat >"$fixture/bin/git" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf 'git %s\n' "$*" >>"$TEST_COMMAND_LOG"
if [ "${1:-}" = "clone" ]; then
  target="${@: -1}"
  mkdir -p "$target/.git"
  if [[ "$target" == */agent-registry ]]; then
    touch "$target/pyproject.toml"
  fi
fi
EOF

cat >"$fixture/bin/uv" <<'EOF'
#!/usr/bin/env bash
printf 'uv %s\n' "$*" >>"$TEST_COMMAND_LOG"
exit "${TEST_UV_STATUS:-0}"
EOF

cat >"$fixture/bin/mise" <<'EOF'
#!/usr/bin/env bash
printf 'mise %s\n' "$*" >>"$TEST_COMMAND_LOG"
EOF

cat >"$fixture/bin/npx" <<'EOF'
#!/usr/bin/env bash
printf 'npx %s\n' "$*" >>"$TEST_COMMAND_LOG"
exit "${TEST_SKILLS_STATUS:-0}"
EOF

# Mock host-capability.sh because work identities live in an external overlay
# and have no profile under dfm/profiles.
cat >"$fixture/bin/host-capability" <<'EOF'
#!/usr/bin/env bash
case "${1:-}" in
  --identity) printf '%s' "${MOCK_IDENTITY:?}" ;;
  agents) printf '%s' "${MOCK_AGENTS:?}" ;;
  mcp) printf '%s' "${MOCK_MCP:-1}" ;;
  skills) printf '%s' "${MOCK_SKILLS:-1}" ;;
  *) exit 2 ;;
esac
EOF

cat >"$fixture/bin/op-render" <<'EOF'
#!/usr/bin/env bash
printf 'op-render session=%s\n' "${OP_SESSION_test:-none}" >>"$TEST_COMMAND_LOG"
EOF

# Emit op's export format to verify the session reaches op-render's environment.
cat >"$fixture/bin/op" <<'EOF'
#!/usr/bin/env bash
printf 'op %s\n' "$*" >>"$TEST_COMMAND_LOG"
[ "${1:-}" = "signin" ] && printf 'export OP_SESSION_test="tok"\n'
exit 0
EOF

chmod +x "$fixture/bin/git" "$fixture/bin/uv" "$fixture/bin/mise" "$fixture/bin/host-capability" \
  "$fixture/bin/op-render" "$fixture/bin/op" "$fixture/bin/npx"

# run_sync <identity> <agents-capability> [run-name]
run_sync() {
  local identity="$1"
  local agents="$2"
  local run_name="${3:-$identity}"
  local run_root="$fixture/$run_name"
  mkdir -p "$run_root/home"
  : >"$run_root/commands.log"
  TEST_COMMAND_LOG="$run_root/commands.log" \
    MOCK_IDENTITY="$identity" \
    MOCK_AGENTS="$agents" \
    HOST_CAPABILITY_BIN="$fixture/bin/host-capability" \
    HOME="$run_root/home" \
    PATH="$fixture/bin:/usr/bin:/bin" \
    GIT_BIN="$fixture/bin/git" \
    UV_BIN="$fixture/bin/uv" \
    MISE_BIN="$fixture/bin/mise" \
    NPX_BIN="${TEST_NPX_BIN:-$fixture/bin/npx}" \
    OP_RENDER_BIN="$fixture/bin/op-render" \
    OP_BIN="$fixture/bin/op" \
    "$repo_root/scripts/sync-side-channels.sh" >/dev/null
}

run_sync work 0
if ! rg -Fxq 'npx --yes skills@latest add https://github.com/kunchenguid/gh-axi/tree/main/skills/gh-axi --skill gh-axi --global --yes --agent claude-code codex pi junie' "$fixture/work/commands.log"; then
  echo "sync did not refresh the declared upstream skill noninteractively" >&2
  exit 1
fi
if rg -q '^mise (install|upgrade)' "$fixture/work/commands.log"; then
  echo "sync ran a mise install or upgrade that dfm's gated mise updater owns" >&2
  exit 1
fi
if rg -q '^git clone .* /[^ ]*/agent-registry$' "$fixture/work/commands.log"; then
  echo "work sync contacted the personal agent registry" >&2
  exit 1
fi

run_sync personal 1
if ! rg -Fxq 'npx --yes skills@latest add https://github.com/kunchenguid/gh-axi/tree/main/skills/gh-axi --skill gh-axi --global --yes --agent claude-code codex pi junie' "$fixture/personal/commands.log"; then
  echo "personal sync did not refresh the declared upstream skill" >&2
  exit 1
fi
if rg -q '^git ' "$fixture/personal/commands.log"; then
  echo "personal sync ran git, but no side channel clones a repo" >&2
  exit 1
fi
# dfm owns these now: the op-template/v1 secrets (no op-render, no op signin), the tpm and
# agent-registry git-checkout/v1 resources with the checkouts updater, and the agents updater.
for run in personal work; do
  if rg -q 'op-render|op signin' "$fixture/$run/commands.log"; then
    echo "$run sync ran op-render or op signin, which dfm's secrets scope replaced" >&2
    exit 1
  fi
  if rg -q 'agent-registry|tmux-plugins/tpm|/plugins/tpm' "$fixture/$run/commands.log"; then
    echo "$run sync touched tpm or the agent registry, which dfm's checkouts own" >&2
    exit 1
  fi
done

if rg -q 'tool install' "$fixture/personal/commands.log"; then
  echo "sync installed a uv tool that dfm's uv-tool/v1 resources own" >&2
  exit 1
fi

# dfm owns these too: the duckdb-extension/v1 resources and the lefthook updater.
for run in personal work; do
  if rg -q 'duckdb|lefthook' "$fixture/$run/commands.log"; then
    echo "$run sync ran a DuckDB or lefthook step that dfm owns" >&2
    exit 1
  fi
done

MOCK_SKILLS=0 run_sync work 0 without-skills
if rg -q '^npx ' "$fixture/without-skills/commands.log"; then
  echo 'sync refreshed upstream skills with the skills capability disabled' >&2; exit 1
fi
if TEST_SKILLS_STATUS=1 run_sync work 0 skills-failed; then
  echo 'sync hid an upstream skill installation failure' >&2; exit 1
fi

# The gh-axi refresh needs npx. Its absence must fail with a repo-authored
# diagnostic instead of a bare 127 partway through provisioning.
mkdir -p "$fixture/without-npx"
if TEST_NPX_BIN="$fixture/bin/npx-missing" run_sync work 0 without-npx 2>"$fixture/without-npx/stderr"; then
  echo 'sync hid a missing npx dependency' >&2; exit 1
fi
if ! rg -Fq 'npx not found; cannot refresh the gh-axi skill' "$fixture/without-npx/stderr"; then
  echo 'sync did not explain the missing npx dependency' >&2; exit 1
fi

echo "side-channel sync honors the agents and skills capability boundaries"
