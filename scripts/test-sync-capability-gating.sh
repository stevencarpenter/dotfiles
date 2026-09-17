#!/usr/bin/env bash
# Work-host side-channel sync must never contact the personal agent registry.
#
# Never invoke real 1Password: keep OP_BIN pointed at the fixture mock and
# PATH restricted to "$fixture/bin:/usr/bin:/bin".
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fixture="$(mktemp -d)"
token_auditor_version="$(tr -d '\n' <"$repo_root/versions/token-auditor")"
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
EOF

cat >"$fixture/bin/mise" <<'EOF'
#!/usr/bin/env bash
printf 'mise %s\n' "$*" >>"$TEST_COMMAND_LOG"
EOF

cat >"$fixture/bin/firstmate" <<'EOF'
#!/usr/bin/env bash
printf 'firstmate %s\n' "$*" >>"$TEST_COMMAND_LOG"
EOF

# Mock host-capability.sh because work identities live in an external wrapper
# and have no row in lib/machines.nix.
cat >"$fixture/bin/host-capability" <<'EOF'
#!/usr/bin/env bash
case "${1:-}" in
  --identity) printf '%s' "${MOCK_IDENTITY:?}" ;;
  agents) printf '%s' "${MOCK_AGENTS:?}" ;;
  mcp) printf '%s' "${MOCK_MCP:-1}" ;;
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
  "$fixture/bin/op-render" "$fixture/bin/op" "$fixture/bin/firstmate"

# run_sync <identity> <agents-capability> [run-name]
run_sync() {
  local identity="$1"
  local agents="$2"
  local run_name="${3:-$identity}"
  local run_root="$fixture/$run_name"
  mkdir -p "$run_root/home"
  TEST_COMMAND_LOG="$run_root/commands.log" \
    MOCK_IDENTITY="$identity" \
    MOCK_AGENTS="$agents" \
    HOST_CAPABILITY_BIN="$fixture/bin/host-capability" \
    HOME="$run_root/home" \
    PATH="$fixture/bin:/usr/bin:/bin" \
    GIT_BIN="$fixture/bin/git" \
    UV_BIN="$fixture/bin/uv" \
    MISE_BIN="$fixture/bin/mise" \
    FIRSTMATE_BIN="$fixture/bin/firstmate" \
    OP_RENDER_BIN="$fixture/bin/op-render" \
    OP_BIN="$fixture/bin/op" \
    "$repo_root/scripts/sync-side-channels.sh" >/dev/null
}

run_sync work 0
if ! rg -Fq 'mise install' "$fixture/work/commands.log"; then
  echo "sync did not reconcile mise-managed tools" >&2
  exit 1
fi
if ! rg -Fxq 'mise upgrade --no-prune' "$fixture/work/commands.log"; then
  echo "sync did not upgrade all mise tools within their configured version constraints" >&2
  exit 1
fi
if rg -q '^git clone .* /[^ ]*/agent-registry$' "$fixture/work/commands.log"; then
  echo "work sync contacted the personal agent registry" >&2
  exit 1
fi

run_sync personal 1
if ! rg -q '^git clone .* /[^ ]*/agent-registry$' "$fixture/personal/commands.log"; then
  echo "personal sync did not retain the agent registry clone" >&2
  exit 1
fi
if ! rg -Fq 'uv run --directory' "$fixture/personal/commands.log"; then
  echo "personal sync did not install the agent registry" >&2
  exit 1
fi
if ! rg -Fq "uv run --directory $fixture/personal/home/.local/share/agent-registry" \
  "$fixture/personal/commands.log"; then
  echo "personal sync did not install from its freshly cloned registry" >&2
  exit 1
fi
if rg -Fq 'uv run --directory' "$fixture/work/commands.log"; then
  echo "work sync attempted to install the personal agent registry" >&2
  exit 1
fi

# op-render renders personal 1Password content; a work host must never invoke
# it (work secrets are the external wrapper's custody). And on personal it must run
# BEFORE the agent-registry clone, which authenticates over SSH using the
# ~/.ssh/config op-render produces.
if rg -Fq 'op-render' "$fixture/work/commands.log"; then
  echo "work sync invoked the personal op-render" >&2
  exit 1
fi
if ! rg -Fq 'op-render' "$fixture/personal/commands.log"; then
  echo "personal sync did not render op:// secrets" >&2
  exit 1
fi
render_line="$(rg -n -Fm1 'op-render' "$fixture/personal/commands.log" | cut -d: -f1)"
clone_line="$(rg -n -m1 '^git clone .* /[^ ]*/agent-registry$' "$fixture/personal/commands.log" | cut -d: -f1)"
if [ -z "$render_line" ] || [ -z "$clone_line" ] || [ "$render_line" -ge "$clone_line" ]; then
  echo "op-render must precede the SSH agent-registry clone (renders its ssh config)" >&2
  exit 1
fi

# op signin requires a TTY so non-interactive callers cannot block on input.
if rg -Fq 'op signin' "$fixture/personal/commands.log"; then
  echo "sync ran a blocking 'op signin' without a TTY" >&2
  exit 1
fi
if ! rg -Fq 'op-render session=none' "$fixture/personal/commands.log"; then
  echo "non-TTY sync should still attempt the render, sessionless" >&2
  exit 1
fi

# With a TTY, signin must run AND its exported session must reach op-render:
# each just recipe line is its own shell, so the export only propagates because
# signin happens inside this script rather than in the Justfile.
run_sync_tty() {
  local run_root="$fixture/personal-tty"
  mkdir -p "$run_root/home"
  local -a inner=(
    env "TEST_COMMAND_LOG=$run_root/commands.log"
    MOCK_IDENTITY=personal MOCK_AGENTS=1
    "HOST_CAPABILITY_BIN=$fixture/bin/host-capability"
    "HOME=$run_root/home" "PATH=$fixture/bin:/usr/bin:/bin"
    "GIT_BIN=$fixture/bin/git" "UV_BIN=$fixture/bin/uv"
    "MISE_BIN=$fixture/bin/mise" "FIRSTMATE_BIN=$fixture/bin/firstmate"
    "OP_RENDER_BIN=$fixture/bin/op-render" "OP_BIN=$fixture/bin/op"
    "TOKEN_AUDITOR_VERSION=$token_auditor_version"
    "$repo_root/scripts/sync-side-channels.sh"
  )
  # pty.spawn waits for the child; BSD script can exit early on stdin EOF.
  # pty-spawn.py decodes the wait status so child failures propagate.
  "${repo_root}/scripts/pty-spawn.py" "${inner[@]}" >/dev/null 2>&1
}

# Python is required by this suite and installed by CI; absence must fail the test.
if ! run_sync_tty; then
  echo "pty harness failed to run sync under a TTY (python3 missing or pty denied)" >&2
  exit 1
fi
if [ ! -s "$fixture/personal-tty/commands.log" ]; then
  echo "TTY sync produced no command log: harness ran but exercised nothing" >&2
  exit 1
fi
if ! rg -Fq 'op signin' "$fixture/personal-tty/commands.log"; then
  echo "TTY sync did not establish an op session before rendering" >&2
  exit 1
fi
if ! rg -Fq 'op-render session=tok' "$fixture/personal-tty/commands.log"; then
  echo "op session did not propagate into op-render's environment" >&2
  exit 1
fi

mkdir -p "$fixture/personal-working/home/projects/agents"
touch "$fixture/personal-working/home/projects/agents/pyproject.toml"
run_sync personal 1 personal-working
if rg -q '^git clone .* /[^ ]*/agent-registry$' \
  "$fixture/personal-working/commands.log"; then
  echo "personal sync cloned a redundant registry beside the working copy" >&2
  exit 1
fi
if ! rg -Fq "uv run --directory $fixture/personal-working/home/projects/agents" \
  "$fixture/personal-working/commands.log"; then
  echo "personal sync did not install from the existing working copy" >&2
  exit 1
fi

if ! rg -Fq "token-auditor@${token_auditor_version}" "$fixture/personal/commands.log"; then
  echo "direct sync did not use the pinned token-auditor release" >&2
  exit 1
fi
if TOKEN_AUDITOR_VERSION=latest \
  HOME="$fixture/home" \
  "$repo_root/scripts/sync-side-channels.sh" >/dev/null 2>&1; then
  echo "sync accepted the mutable token-auditor main branch" >&2
  exit 1
fi

if ! rg -Fq 'firstmate --setup' "$fixture/work/commands.log"; then
  echo "sync did not ensure Firstmate for a Pi-enabled host" >&2
  exit 1
fi
MOCK_MCP=0 run_sync work 0 without-pi
if rg -Fq 'firstmate' "$fixture/without-pi/commands.log"; then
  echo "sync installed Firstmate with the Pi/MCP capability disabled" >&2
  exit 1
fi

echo "side-channel sync honors the agents and Pi/MCP capability boundaries"
