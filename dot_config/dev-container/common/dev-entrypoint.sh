#!/usr/bin/env bash
set -e

DEV_UID="${DEV_UID:-1000}"
DEV_GID="${DEV_GID:-1000}"
DEV_USER="${DEV_USER:-dev}"
DEV_HOME="${DEV_HOME:-/home/${DEV_USER}}"
DEV_SHELL="${DEV_SHELL:-/bin/zsh}"

group_name="$DEV_USER"
if ! getent group "$DEV_GID" >/dev/null 2>&1; then
  if ! groupadd -g "$DEV_GID" "$group_name" 2>/dev/null; then
    group_name="devgroup"
    groupadd -g "$DEV_GID" "$group_name"
  fi
else
  # Group exists, get its name
  group_name=$(getent group "$DEV_GID" | cut -d: -f1)
fi

if id -u "$DEV_USER" >/dev/null 2>&1; then
  if ! usermod -u "$DEV_UID" -g "$group_name" -d "$DEV_HOME" "$DEV_USER"; then
    echo "Error: usermod failed to update user '$DEV_USER'. The user may have running processes or own files. Please resolve and retry." >&2
    exit 1
  fi
else
  useradd -m -d "$DEV_HOME" -s "$DEV_SHELL" -u "$DEV_UID" -g "$group_name" "$DEV_USER"
fi

# Validate that DEV_HOME is a subdirectory of /home before creating or chowning
if command -v realpath >/dev/null 2>&1; then
  DEV_HOME_ABS="$(realpath -m "$DEV_HOME")"
else
  DEV_HOME_ABS="$(readlink -m "$DEV_HOME")"
fi
# Ensure the resolved path still starts with /home/ to prevent path traversal
case "$DEV_HOME_ABS" in
  /home/*) ;;
  *)
    echo "Error: DEV_HOME ($DEV_HOME_ABS) is not a subdirectory of /home. Refusing to create or chown recursively for safety." >&2
    exit 1
esac
mkdir -p "$DEV_HOME" /work
chown -R "$DEV_UID":"$DEV_GID" "$DEV_HOME"
chown "$DEV_UID":"$DEV_GID" /work

export HOME="$DEV_HOME"
export USER="$DEV_USER"
exec gosu "$DEV_UID:$DEV_GID" "$@"
