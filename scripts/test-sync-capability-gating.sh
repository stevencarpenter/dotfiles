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

cat >"$fixture/bin/nix" <<'EOF'
#!/usr/bin/env bash
case " $* " in
  *work-mac*) printf '0' ;;
  *personal-mac*) printf '1' ;;
  *) exit 2 ;;
esac
EOF

chmod +x "$fixture/bin/git" "$fixture/bin/uv" "$fixture/bin/nix"

run_sync() {
  local host="$1"
  local run_root="$fixture/$host"
  mkdir -p "$run_root/home"
  TEST_COMMAND_LOG="$run_root/commands.log" \
    DOTFILES_HOST="$host" \
    HOME="$run_root/home" \
    PATH="$fixture/bin:/usr/bin:/bin" \
    NIX_BIN="$fixture/bin/nix" \
    GIT_BIN="$fixture/bin/git" \
    UV_BIN="$fixture/bin/uv" \
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
if rg -Fq 'uv run --directory' "$fixture/work-mac/commands.log"; then
  echo "work sync attempted to install the personal agent registry" >&2
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
