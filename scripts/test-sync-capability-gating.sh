#!/usr/bin/env bash
# Work-host side-channel sync must never contact the personal agent registry.
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
  if [[ "$*" == *"stevencarpenter/agents.git"* ]]; then
    touch "$target/pyproject.toml"
  fi
fi
EOF

cat >"$fixture/bin/uv" <<'EOF'
#!/usr/bin/env bash
printf 'uv %s\n' "$*" >>"$TEST_COMMAND_LOG"
EOF

# Two eval shapes now: a 0/1 capability and the identity string. Match the
# identity expression FIRST — it also names the host, so the capability arms
# would otherwise swallow it and hand back "1", silently skipping the
# personal-only op-render block instead of exercising it.
cat >"$fixture/bin/nix" <<'EOF'
#!/usr/bin/env bash
case " $* " in
  *.identity*)
    case " $* " in
      *work-mac*) printf 'work' ;;
      *personal-mac*) printf 'personal' ;;
      *) exit 2 ;;
    esac
    ;;
  *work-mac*) printf '0' ;;
  *personal-mac*) printf '1' ;;
  *) exit 2 ;;
esac
EOF

cat >"$fixture/bin/op-render" <<'EOF'
#!/usr/bin/env bash
printf 'op-render session=%s\n' "${OP_SESSION_test:-none}" >>"$TEST_COMMAND_LOG"
EOF

# Mock `op signin`: emits the export line real op emits, so the test can prove
# the session actually reaches op-render's environment rather than merely that
# signin was called.
cat >"$fixture/bin/op" <<'EOF'
#!/usr/bin/env bash
printf 'op %s\n' "$*" >>"$TEST_COMMAND_LOG"
[ "${1:-}" = "signin" ] && printf 'export OP_SESSION_test="tok"\n'
exit 0
EOF

chmod +x "$fixture/bin/git" "$fixture/bin/uv" "$fixture/bin/nix" \
  "$fixture/bin/op-render" "$fixture/bin/op"

run_sync() {
  local host="$1"
  local run_name="${2:-$host}"
  local run_root="$fixture/$run_name"
  mkdir -p "$run_root/home"
  TEST_COMMAND_LOG="$run_root/commands.log" \
    DOTFILES_HOST="$host" \
    HOME="$run_root/home" \
    PATH="$fixture/bin:/usr/bin:/bin" \
    NIX_BIN="$fixture/bin/nix" \
    GIT_BIN="$fixture/bin/git" \
    UV_BIN="$fixture/bin/uv" \
    OP_RENDER_BIN="$fixture/bin/op-render" \
    OP_BIN="$fixture/bin/op" \
    "$repo_root/scripts/sync-side-channels.sh" >/dev/null
}

run_sync work-mac
if rg -Fq 'git@github.com:stevencarpenter/agents.git' "$fixture/work-mac/commands.log"; then
  echo "work sync contacted the personal agent registry" >&2
  exit 1
fi

run_sync personal-mac
if ! rg -Fq 'git@github.com:stevencarpenter/agents.git' "$fixture/personal-mac/commands.log"; then
  echo "personal sync did not retain the agent registry clone" >&2
  exit 1
fi
if ! rg -Fq 'uv run --directory' "$fixture/personal-mac/commands.log"; then
  echo "personal sync did not install the agent registry" >&2
  exit 1
fi
if ! rg -Fq "uv run --directory $fixture/personal-mac/home/.local/share/agent-registry" \
  "$fixture/personal-mac/commands.log"; then
  echo "personal sync did not install from its freshly cloned registry" >&2
  exit 1
fi
if rg -Fq 'uv run --directory' "$fixture/work-mac/commands.log"; then
  echo "work sync attempted to install the personal agent registry" >&2
  exit 1
fi

# op-render renders personal 1Password content; a work host must never invoke
# it (work secrets come from agenix at activation). And on personal it must run
# BEFORE the agent-registry clone, which authenticates over SSH using the
# ~/.ssh/config op-render produces.
if rg -Fq 'op-render' "$fixture/work-mac/commands.log"; then
  echo "work sync invoked the personal op-render" >&2
  exit 1
fi
if ! rg -Fq 'op-render' "$fixture/personal-mac/commands.log"; then
  echo "personal sync did not render op:// secrets" >&2
  exit 1
fi
render_line="$(rg -n -Fm1 'op-render' "$fixture/personal-mac/commands.log" | cut -d: -f1)"
clone_line="$(rg -n -Fm1 'stevencarpenter/agents.git' "$fixture/personal-mac/commands.log" | cut -d: -f1)"
if [ -z "$render_line" ] || [ -z "$clone_line" ] || [ "$render_line" -ge "$clone_line" ]; then
  echo "op-render must precede the SSH agent-registry clone (renders its ssh config)" >&2
  exit 1
fi

# `op signin` blocks on input, so it must only run with a TTY: bootstrap.sh and
# CI call this same script, where a hang beats every other failure mode.
if rg -Fq 'op signin' "$fixture/personal-mac/commands.log"; then
  echo "sync ran a blocking 'op signin' without a TTY" >&2
  exit 1
fi
if ! rg -Fq 'op-render session=none' "$fixture/personal-mac/commands.log"; then
  echo "non-TTY sync should still attempt the render, sessionless" >&2
  exit 1
fi

# With a TTY, signin must run AND its exported session must reach op-render —
# each just recipe line is its own shell, so the export only propagates because
# signin happens inside this script rather than in the Justfile.
run_sync_tty() {
  local run_root="$fixture/personal-tty"
  mkdir -p "$run_root/home"
  local -a inner=(
    env "TEST_COMMAND_LOG=$run_root/commands.log" DOTFILES_HOST=personal-mac
    "HOME=$run_root/home" "PATH=$fixture/bin:/usr/bin:/bin"
    "NIX_BIN=$fixture/bin/nix" "GIT_BIN=$fixture/bin/git" "UV_BIN=$fixture/bin/uv"
    "OP_RENDER_BIN=$fixture/bin/op-render" "OP_BIN=$fixture/bin/op"
    "TOKEN_AUDITOR_VERSION=$token_auditor_version"
    "$repo_root/scripts/sync-side-channels.sh"
  )
  # BSD script (macOS): script [-q] file [command ...]. util-linux differs.
  if script -q /dev/null "${inner[@]}" >/dev/null 2>&1; then return 0; fi
  script -q -c "$(printf '%q ' "${inner[@]}")" /dev/null >/dev/null 2>&1
}

token_auditor_version="$(tr -d '\n' <"$repo_root/versions/token-auditor")"
if run_sync_tty && [ -s "$fixture/personal-tty/commands.log" ]; then
  if ! rg -Fq 'op signin' "$fixture/personal-tty/commands.log"; then
    echo "TTY sync did not establish an op session before rendering" >&2
    exit 1
  fi
  if ! rg -Fq 'op-render session=tok' "$fixture/personal-tty/commands.log"; then
    echo "op session did not propagate into op-render's environment" >&2
    exit 1
  fi
else
  echo "warning: no usable pty harness; TTY signin path NOT covered on this host" >&2
fi

mkdir -p "$fixture/personal-working/home/projects/agents"
touch "$fixture/personal-working/home/projects/agents/pyproject.toml"
run_sync personal-mac personal-working
if rg -Fq 'git@github.com:stevencarpenter/agents.git' \
  "$fixture/personal-working/commands.log"; then
  echo "personal sync cloned a redundant registry beside the working copy" >&2
  exit 1
fi
if ! rg -Fq "uv run --directory $fixture/personal-working/home/projects/agents" \
  "$fixture/personal-working/commands.log"; then
  echo "personal sync did not install from the existing working copy" >&2
  exit 1
fi

token_auditor_version="$(tr -d '\n' <"$repo_root/versions/token-auditor")"
if ! rg -Fq "token-auditor@${token_auditor_version}" "$fixture/personal-mac/commands.log"; then
  echo "direct sync did not use the pinned token-auditor release" >&2
  exit 1
fi
if TOKEN_AUDITOR_VERSION=latest \
  HOME="$fixture/home" \
  "$repo_root/scripts/sync-side-channels.sh" >/dev/null 2>&1; then
  echo "sync accepted the mutable token-auditor main branch" >&2
  exit 1
fi

echo "side-channel sync honors the agents capability boundary"
