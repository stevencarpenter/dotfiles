#!/usr/bin/env bash
# Report Homebrew drift without invoking any cleanup or uninstall operation.
set -euo pipefail

brew_bin="${BREW_BIN:-brew}"
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
brewfile="${HOMEBREW_BUNDLE_FILE:-$repo_root/Brewfile}"

if ! command -v "$brew_bin" >/dev/null 2>&1; then
  echo "error: brew is required for the Homebrew inventory audit" >&2
  exit 1
fi
if [ -z "$brewfile" ] || [ ! -f "$brewfile" ]; then
  echo "error: no Brewfile at $brewfile; set HOMEBREW_BUNDLE_FILE to the active one" >&2
  exit 1
fi
brewfiles=("$brewfile")
# The identity's Brewfile is declared inventory too, unless HOMEBREW_BUNDLE_FILE names one file.
if [ -z "${HOMEBREW_BUNDLE_FILE:-}" ]; then
  identity="$("$repo_root/scripts/host-capability.sh" --identity || true)"
  if [ -n "$identity" ] && [ -f "$repo_root/Brewfile.$identity" ]; then
    brewfiles+=("$repo_root/Brewfile.$identity")
  fi
fi

export HOMEBREW_NO_AUTO_UPDATE=1
export HOMEBREW_NO_ANALYTICS=1
export HOMEBREW_NO_ENV_HINTS=1

audit_dir="$(mktemp -d "${TMPDIR:-/tmp}/homebrew-audit.XXXXXX")"
trap 'rm -rf "$audit_dir"' EXIT

declared() { # declared <formula|cask|tap>: the union over every Brewfile
  local file
  for file in "${brewfiles[@]}"; do
    "$brew_bin" bundle list --file="$file" "--$1"
  done | sort -u
}

declared formula >"$audit_dir/declared-formulae"
declared cask >"$audit_dir/declared-casks"
declared tap >"$audit_dir/declared-taps"
"$brew_bin" list --formula --full-name | sort -u >"$audit_dir/installed-formulae"
"$brew_bin" leaves | sort -u >"$audit_dir/top-level-formulae"
"$brew_bin" list --cask | sort -u >"$audit_dir/installed-casks"
"$brew_bin" tap | sort -u >"$audit_dir/installed-taps"

report_diff() {
  local heading="$1"
  local left="$2"
  local right="$3"
  local result

  result="$(comm -23 "$left" "$right")"
  printf '\n%s\n' "$heading"
  if [ -n "$result" ]; then
    printf '%s\n' "$result"
  else
    printf '(none)\n'
  fi
}

printf 'Homebrew inventory audit for %s\n' "${brewfiles[*]}"
report_diff "Declared formulae that are missing:" \
  "$audit_dir/declared-formulae" "$audit_dir/installed-formulae"
report_diff "Unmanaged top-level formulae:" \
  "$audit_dir/top-level-formulae" "$audit_dir/declared-formulae"
report_diff "Declared casks that are missing:" \
  "$audit_dir/declared-casks" "$audit_dir/installed-casks"
report_diff "Unmanaged casks:" \
  "$audit_dir/installed-casks" "$audit_dir/declared-casks"
report_diff "Declared taps that are missing:" \
  "$audit_dir/declared-taps" "$audit_dir/installed-taps"
report_diff "Unmanaged taps:" \
  "$audit_dir/installed-taps" "$audit_dir/declared-taps"

printf '\nAudit complete. No packages, casks, taps, caches, or files were changed.\n'
