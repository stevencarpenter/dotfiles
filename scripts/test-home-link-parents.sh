#!/usr/bin/env bash
# Reproduce the directory-to-file migration without touching the real home.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fixture="$(mktemp -d)"
trap 'rm -rf "$fixture"' EXIT
mkdir -p "$fixture/checkout/journal" "$fixture/home/.config" \
  "$fixture/new-files/.config/agent journal" "$fixture/generation" "$fixture/store"
printf 'machine = "fixture"\n' >"$fixture/checkout/journal/config.toml"
cp "$fixture/checkout/journal/config.toml" "$fixture/original"
ln -s "$fixture/checkout/journal" "$fixture/store/old-directory"
ln -s "$fixture/store/old-directory" "$fixture/home/.config/agent journal"
ln -s "$fixture/checkout/journal/config.toml" "$fixture/new-files/.config/agent journal/config.toml"
ln -s "$fixture/new-files" "$fixture/generation/home-files"

check() {
  bash "$repo_root/scripts/check-home-link-parents.sh" \
    "$fixture/generation/home-files" "$fixture/home"
}

# Even when backups are requested, refuse before modifying source files.
if HOME_MANAGER_BACKUP_EXT=chezmoi-bak check >"$fixture/error" 2>&1; then
  echo 'accepted a stale parent directory symlink' >&2
  exit 1
fi
rg -Fq "$fixture/home/.config/agent journal" "$fixture/error"
cmp "$fixture/original" "$fixture/checkout/journal/config.toml"
test ! -L "$fixture/checkout/journal/config.toml"
test ! -e "$fixture/checkout/journal/config.toml.chezmoi-bak"

# A dangling directory link must fail too, even when -e would return false.
mv "$fixture/checkout/journal" "$fixture/checkout/saved"
if check >/dev/null 2>&1; then
  echo 'accepted a dangling parent directory symlink' >&2
  exit 1
fi
mv "$fixture/checkout/saved" "$fixture/checkout/journal"

# Repair the parent and keep both file-level and directory-level leaf links.
rm "$fixture/home/.config/agent journal"
mkdir "$fixture/home/.config/agent journal"
ln -s "$fixture/checkout/journal/config.toml" "$fixture/home/.config/agent journal/config.toml"
ln -s "$fixture/checkout/journal" "$fixture/new-files/.config/whole-directory"
ln -s "$fixture/checkout/journal" "$fixture/home/.config/whole-directory"
check
check

# Missing parents are valid on first activation.
check_home="$fixture/empty-home"
mkdir "$check_home"
bash "$repo_root/scripts/check-home-link-parents.sh" "$fixture/generation/home-files" "$check_home"
echo 'home-link-parents: stale and dangling parents rejected; repaired, fresh, and leaf links accepted'
