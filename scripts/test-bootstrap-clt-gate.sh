#!/usr/bin/env bash
# Fresh bootstrap must stop after launching the asynchronous CLT installer.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fixture="$(mktemp -d)"
fixture="$(cd "$fixture" && pwd -P)"
trap 'rm -rf "$fixture"' EXIT

mkdir -p "$fixture/bin" "$fixture/home" "$fixture/repo/scripts" "$fixture/tmp"
# Even if bootstrap bypasses the just mock, its Justfile must be inert.
cp "$repo_root/bootstrap.sh" "$fixture/repo/bootstrap.sh"
cp "$repo_root/scripts/host-detect.sh" "$fixture/repo/scripts/host-detect.sh"
cat >"$fixture/repo/Justfile" <<'EOF'
sync-side-channels:
    @echo "bootstrap test bypassed the just mock" >&2
    @exit 99
EOF

run_bootstrap() {
  local test_home="$1" command_log="$2" brew_bin="$3"
  shift 3
  env -i \
    HOME="$test_home" \
    XDG_CONFIG_HOME="$test_home/.config" \
    XDG_DATA_HOME="$test_home/.local/share" \
    XDG_CACHE_HOME="$test_home/.cache" \
    XDG_STATE_HOME="$test_home/.local/state" \
    TMPDIR="$fixture/tmp" \
    PATH="$fixture/bin:/usr/bin:/bin" \
    TEST_COMMAND_LOG="$command_log" \
    DOTFILES_BREW_BIN="$brew_bin" \
    DOTFILES_JUST_BIN="$fixture/bin/just" \
    /bin/bash "$fixture/repo/bootstrap.sh" "$@"
}

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
run_bootstrap "$fixture/home" "$fixture/commands.log" "$fixture/bin/brew" \
  >"$fixture/stdout" 2>"$fixture/stderr"
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

# Once CLT is present, bootstrap must run through without ever fetching an age
# identity. The `op` mock below still answers the retired age-key read so this
# harness can prove bootstrap does not call it (see the negative assertion
# after the loop).
cat >"$fixture/bin/xcode-select" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
[ "${1:-}" = "-p" ] && exit 0
exit 2
EOF

cat >"$fixture/bin/nix" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF

cat >"$fixture/bin/rustup" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF

cat >"$fixture/bin/op" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf 'op %s\n' "$*" >>"$TEST_COMMAND_LOG"
if [ "$*" = "read op://Private/dotfiles-age-key/notesPlain" ]; then
  printf '%s\n' test-age-key
  exit 0
fi
exit 2
EOF

cat >"$fixture/bin/sudo" <<'EOF'
#!/usr/bin/env bash
printf 'sudo %s\n' "$*" >>"$TEST_COMMAND_LOG"
exit 0
EOF

# Homebrew lives at an absolute path, which PATH stubbing cannot reach, hence
# bootstrap's DOTFILES_BREW_BIN seam. Without it the install branch fires on
# every host lacking /opt/homebrew (all Linux CI runners) and this test would
# download and execute the real Homebrew installer.
cat >"$fixture/bin/brew" <<'EOF'
#!/usr/bin/env bash
printf 'brew %s\n' "$*" >>"$TEST_COMMAND_LOG"
[ "${1:-}" = "--version" ] && printf 'Homebrew 4.0.0-test\n'
exit 0
EOF

cat >"$fixture/bin/just" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
for name in XDG_CONFIG_HOME XDG_DATA_HOME XDG_CACHE_HOME XDG_STATE_HOME; do
  case "${!name}" in
    "$HOME"/*) ;;
    *) echo "bootstrap test leaked $name outside its home" >&2; exit 1 ;;
  esac
done
printf 'just %s\n' "$*" >>"$TEST_COMMAND_LOG"
exit 0
EOF

# A curl that never leaves the machine: it writes a marker script to the -o
# target so the brew-absent case below runs end to end offline.
cat >"$fixture/bin/curl" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf 'curl %s\n' "$*" >>"$TEST_COMMAND_LOG"
dest=""
while [ "$#" -gt 0 ]; do
  if [ "$1" = "-o" ]; then
    dest="${2:-}"
    shift
  fi
  shift
done
[ -n "$dest" ] || exit 1
printf '#!/usr/bin/env bash\nprintf "homebrew-install-ran\\n" >>"$TEST_COMMAND_LOG"\n' >"$dest"
EOF

  chmod +x "$fixture/bin/xcode-select" "$fixture/bin/nix" \
  "$fixture/bin/rustup" "$fixture/bin/op" "$fixture/bin/sudo" \
  "$fixture/bin/brew" "$fixture/bin/curl" "$fixture/bin/just"

for host in fixture-host; do
  host_home="$fixture/$host-home"
  command_log="$fixture/$host-commands.log"
  mkdir -p "$host_home"
  set +e
  run_bootstrap "$host_home" "$command_log" "$fixture/bin/brew" "$host" \
    >"$fixture/$host-stdout" 2>"$fixture/$host-stderr"
  status=$?
  set -e
  # Dump the captured streams: set -e would otherwise abort the loop with a
  # bare exit 1 and the diagnostics still sitting in files the EXIT trap wipes.
  if [ "$status" -ne 0 ]; then
    echo "bootstrap failed for $host (exit $status)" >&2
    cat "$fixture/$host-stdout" "$fixture/$host-stderr" >&2
    exit 1
  fi
  if rg -Fxq homebrew-install-ran "$command_log"; then
    echo "bootstrap reinstalled Homebrew on $host despite brew being present" >&2
    exit 1
  fi
  if ! rg -Fxq "just --justfile $fixture/repo/Justfile sync-side-channels" "$command_log"; then
    echo "bootstrap did not use the isolated just mock for $host" >&2
    cat "$fixture/$host-stdout" "$fixture/$host-stderr" >&2
    exit 1
  fi
done

# No host may fetch or create an age identity.
#
# This assertion used to be asymmetric: personal must never read the key, work
# must always read it. The age bridge is gone: this repo declares zero
# age.secrets on every identity, so the invariant is now symmetric and
# strictly negative for every host bootstrap can build.
#
# `op read` specifically, not any `op` call: bootstrap legitimately reaches
# op-render (which probes `op whoami`, and signs in when it has a TTY). The
# thing no host may do is READ an age identity out of 1Password.
for host in fixture-host; do
  if rg -q '^op read' "$fixture/$host-commands.log" 2>/dev/null; then
    echo "$host bootstrap fetched an age identity; the age bridge is gone" >&2
    exit 1
  fi
  if [ -e "$fixture/$host-home/.config/age/keys.txt" ]; then
    echo "$host bootstrap created an age identity; the age bridge is gone" >&2
    exit 1
  fi
done

echo "bootstrap fetches no age identity on any host"

# The mirror case: with brew absent, bootstrap must install it, and must do so
# through the download-to-a-file path so a failed fetch aborts under set -e
# rather than continuing on to a switch that has no brew to bundle with.
missing_home="$fixture/nobrew-home"
missing_log="$fixture/nobrew-commands.log"
mkdir -p "$missing_home"
set +e
run_bootstrap "$missing_home" "$missing_log" "$fixture/absent/brew" fixture-host \
  >"$fixture/nobrew-stdout" 2>"$fixture/nobrew-stderr"
status=$?
set -e
if [ "$status" -ne 0 ]; then
  echo "bootstrap failed while installing Homebrew (exit $status)" >&2
  cat "$fixture/nobrew-stdout" "$fixture/nobrew-stderr" >&2
  exit 1
fi
if ! rg -Fxq homebrew-install-ran "$missing_log"; then
  echo "bootstrap did not install Homebrew when brew was absent" >&2
  exit 1
fi
if ! rg -Fxq "just --justfile $fixture/repo/Justfile sync-side-channels" "$missing_log"; then
  echo "bootstrap did not use the isolated just mock when Homebrew was absent" >&2
  cat "$fixture/nobrew-stdout" "$fixture/nobrew-stderr" >&2
  exit 1
fi

echo "bootstrap installs Homebrew only when it is absent"
