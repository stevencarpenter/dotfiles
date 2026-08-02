#!/usr/bin/env bash
# Fresh bootstrap must stop after launching the asynchronous CLT installer.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fixture="$(mktemp -d)"
trap 'rm -rf "$fixture"' EXIT

# GNU stat uses -c; BSD/macOS stat uses -f. Try GNU first because GNU's -f
# means "file system" and can otherwise exit successfully with unusable output.
perm() { /usr/bin/stat -c '%a' "$1" 2>/dev/null || /usr/bin/stat -f '%Lp' "$1"; }

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

# Once CLT is present, the age identity fetch must remain work-only. Personal
# hosts render their secrets directly from 1Password and must not retain the
# work bridge key merely because bootstrap was re-run.
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

# Homebrew lives at an absolute path, which PATH stubbing cannot reach — hence
# bootstrap's DOTFILES_BREW_BIN seam. Without it the install branch fires on
# every host lacking /opt/homebrew (all Linux CI runners) and this test would
# download and execute the real Homebrew installer.
cat >"$fixture/bin/brew" <<'EOF'
#!/usr/bin/env bash
printf 'brew %s\n' "$*" >>"$TEST_COMMAND_LOG"
[ "${1:-}" = "--version" ] && printf 'Homebrew 4.0.0-test\n'
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
  "$fixture/bin/brew" "$fixture/bin/curl"

for host in personal-mac work-mac; do
  host_home="$fixture/$host-home"
  command_log="$fixture/$host-commands.log"
  mkdir -p "$host_home"
  set +e
  TEST_COMMAND_LOG="$command_log" \
    HOME="$host_home" \
    PATH="$fixture/bin:/usr/bin:/bin" \
    DOTFILES_BREW_BIN="$fixture/bin/brew" \
    bash "$repo_root/bootstrap.sh" "$host" \
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
done

if rg -q '^op ' "$fixture/personal-mac-commands.log" 2>/dev/null; then
  echo "personal bootstrap fetched the work-only age identity" >&2
  exit 1
fi
if [ -e "$fixture/personal-mac-home/.config/age/keys.txt" ]; then
  echo "personal bootstrap created the work-only age identity" >&2
  exit 1
fi

if ! rg -Fxq \
  'op read op://Private/dotfiles-age-key/notesPlain' \
  "$fixture/work-mac-commands.log"; then
  echo "work bootstrap did not fetch the declared age identity" >&2
  exit 1
fi
if [ "$(perm "$fixture/work-mac-home/.config/age/keys.txt")" != 600 ]; then
  echo "work bootstrap age identity does not have mode 0600" >&2
  exit 1
fi

echo "bootstrap fetches the age identity on work-mac only"

# The mirror case: with brew absent, bootstrap must install it, and must do so
# through the download-to-a-file path so a failed fetch aborts under set -e
# rather than continuing on to a switch that has no brew to bundle with.
missing_home="$fixture/nobrew-home"
missing_log="$fixture/nobrew-commands.log"
mkdir -p "$missing_home"
set +e
TEST_COMMAND_LOG="$missing_log" \
  HOME="$missing_home" \
  PATH="$fixture/bin:/usr/bin:/bin" \
  DOTFILES_BREW_BIN="$fixture/absent/brew" \
  bash "$repo_root/bootstrap.sh" personal-mac \
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

echo "bootstrap installs Homebrew only when it is absent"
