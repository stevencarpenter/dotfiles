#!/usr/bin/env bash
# Report Homebrew drift without invoking any cleanup or uninstall operation.
set -euo pipefail

brew_bin="${BREW_BIN:-brew}"
brewfile="${HOMEBREW_BUNDLE_FILE:-}"

if ! command -v "$brew_bin" >/dev/null 2>&1; then
  echo "error: brew is required for the Homebrew inventory audit" >&2
  exit 1
fi
if [ -z "$brewfile" ] || [ ! -f "$brewfile" ]; then
  echo "error: HOMEBREW_BUNDLE_FILE must name the active nix-darwin Brewfile" >&2
  exit 1
fi

export HOMEBREW_NO_AUTO_UPDATE=1
export HOMEBREW_NO_ANALYTICS=1
export HOMEBREW_NO_ENV_HINTS=1

audit_dir="$(mktemp -d "${TMPDIR:-/tmp}/homebrew-audit.XXXXXX")"
trap 'rm -rf "$audit_dir"' EXIT

"$brew_bin" bundle list --file="$brewfile" --formula | sort -u >"$audit_dir/declared-formulae"
"$brew_bin" bundle list --file="$brewfile" --cask | sort -u >"$audit_dir/declared-casks"
"$brew_bin" bundle list --file="$brewfile" --tap | sort -u >"$audit_dir/declared-taps"
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

printf 'Homebrew inventory audit for %s\n' "$brewfile"
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
