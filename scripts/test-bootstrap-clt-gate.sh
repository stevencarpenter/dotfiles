#!/usr/bin/env bash
# Fresh bootstrap must stop after launching the asynchronous CLT installer.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fixture="$(mktemp -d)"
trap 'rm -rf "$fixture"' EXIT

mkdir -p "$fixture/bin" "$fixture/home"

cat >"$fixture/bin/xcode-select" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
if [ "${1:-}" = "-p" ]; then
  exit 1
fi
if [ "${1:-}" = "--install" ]; then
  printf '%s\n' xcode-select-install >>"$TEST_COMMAND_LOG"
  exit 0
fi
exit 2
EOF

cat >"$fixture/bin/sudo" <<'EOF'
#!/usr/bin/env bash
printf 'sudo %s\n' "$*" >>"$TEST_COMMAND_LOG"
exit 99
EOF

chmod +x "$fixture/bin/xcode-select" "$fixture/bin/sudo"

set +e
TEST_COMMAND_LOG="$fixture/commands.log" \
  HOME="$fixture/home" \
  PATH="$fixture/bin:/usr/bin:/bin" \
  bash "$repo_root/bootstrap.sh" >"$fixture/stdout" 2>"$fixture/stderr"
status=$?
set -e

if [ "$status" -ne 0 ]; then
  echo "bootstrap did not stop successfully after launching CLT (exit $status)" >&2
  cat "$fixture/stdout" >&2
  cat "$fixture/stderr" >&2
  exit 1
fi

if ! rg -Fxq xcode-select-install "$fixture/commands.log"; then
  echo "bootstrap did not launch the CLT installer" >&2
  exit 1
fi

if rg -q '^sudo ' "$fixture/commands.log"; then
  echo "bootstrap continued into privileged work while CLT was pending" >&2
  exit 1
fi

echo "bootstrap stops cleanly while Command Line Tools installation is pending"
