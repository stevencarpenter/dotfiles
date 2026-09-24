#!/usr/bin/env bash
# Reject directory symlinks that Home Manager would traverse while linking files.
set -euo pipefail

generation_files="$(cd "$1" && pwd -P)"
target_home="$2"

# Do not follow generation symlinks: directory-level managed links are leaves,
# while real directories are parents that activation will write through.
find "$generation_files" -mindepth 1 -type d -print0 |
  while IFS= read -r -d '' directory; do
    relative="${directory#"$generation_files/"}"
    target="$target_home/$relative"
    if [[ -L "$target" ]]; then
      printf 'Home Manager refuses to write through symlinked parent: %s\n' "$target" >&2
      printf 'Preserve its contents and replace this directory link with a real directory before rebuilding.\n' >&2
      exit 1
    fi
  done
