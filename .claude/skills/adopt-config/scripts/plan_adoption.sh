#!/usr/bin/env bash
# Deterministically plan the adoption of a tool's config into the dotfiles.
#
# Given the path to a config the tool wrote under $HOME (a file OR a directory),
# print: the repo target path, a file-vs-directory link recommendation (by
# scanning for tool-written state), a collision check, and the exact
# dotfiles.nix `mkLinks` line to add. Judgment calls it CANNOT make (which
# machine gate, which package source) are surfaced as TODOs, not guessed.
#
# Usage:  plan_adoption.sh <path-under-$HOME>
# Output: human-readable plan on stdout. Exits non-zero only on bad input.
set -euo pipefail

DOTFILES="${DOTFILES:-$HOME/.dotfiles}"

die() { printf 'plan_adoption: %s\n' "$1" >&2; exit 2; }

[ $# -eq 1 ] || die "expected exactly one argument (a path under \$HOME)"
raw="$1"

# Resolve to an absolute path without requiring the target to still exist as a
# real file (it may already be a symlink we want to inspect).
case "$raw" in
  /*) abs="$raw" ;;
  "~/"*) abs="$HOME/${raw#"~/"}" ;;
  *) abs="$PWD/$raw" ;;
esac
# Normalize a trailing slash.
abs="${abs%/}"

case "$abs" in
  "$HOME"/*) : ;;
  *) die "path must live under \$HOME ($HOME); got: $abs" ;;
esac

rel="${abs#"$HOME"/}"          # e.g. .config/foo/config
repo_target="$DOTFILES/home/$rel"

echo "== Adoption plan for: $abs =="
echo

# --- Already adopted? ------------------------------------------------------
if [ -L "$abs" ]; then
  link_dest="$(readlink "$abs")"
  resolved="$(cd "$(dirname "$abs")" 2>/dev/null && realpath "$abs" 2>/dev/null || true)"
  case "$resolved" in
    "$DOTFILES"/*)
      echo "ALREADY ADOPTED: $abs is a symlink resolving into the repo:"
      echo "  -> $resolved"
      echo "Nothing to do (edit that repo file directly; it's live)."
      exit 0
      ;;
    *)
      echo "NOTE: $abs is already a symlink (-> $link_dest) but NOT into the repo."
      echo "      Investigate before adopting; this script assumes a real file/dir."
      echo
      ;;
  esac
fi

[ -e "$abs" ] || die "no such file or directory: $abs"

# --- File vs directory recommendation --------------------------------------
# State markers a tool commonly writes NEXT TO its config. Presence in a
# directory means: link the individual config file, not the whole dir.
state_glob_regex='\.(log|db|sqlite3?|lock|sock|pid|tmp)$|(^|/)(cache|caches|state|logs|history|sessions|repos|tmp)(/|$)|(^|/)\.git(/|$)'

if [ -f "$abs" ]; then
  echo "SOURCE TYPE : single file"
  echo "RECOMMEND   : file-level link (link the file itself)"
  link_rel="$rel"
else
  echo "SOURCE TYPE : directory"
  # Scan directory contents (one level is enough to spot state siblings; also
  # check nested for the common cache/state/repos dirs).
  state_hits="$(find "$abs" -mindepth 1 -maxdepth 2 2>/dev/null \
    | sed "s#^$abs/##" \
    | grep -Ei "$state_glob_regex" || true)"
  if [ -n "$state_hits" ]; then
    echo "RECOMMEND   : FILE-level link — tool writes state in this dir:"
    printf '%s\n' "$state_hits" | sed 's/^/                - /' | head -8
    echo "              Link only the config file(s) below, NOT the directory."
    # Best guess at the config file to link: a top-level config.* / *.toml/json/yaml.
    cfg="$(find "$abs" -maxdepth 1 -type f \
             \( -name 'config*' -o -name '*.toml' -o -name '*.json' \
                -o -name '*.yaml' -o -name '*.yml' -o -name '*.conf' -o -name '*.ini' \) \
             2>/dev/null | sed "s#^$abs/##" | head -1 || true)"
    if [ -n "$cfg" ]; then
      link_rel="$rel/$cfg"
      echo "              Likely config file: $cfg"
    else
      link_rel="$rel/<config-file>"
      echo "              (couldn't auto-detect the config file — fill in <config-file>)"
    fi
  else
    echo "RECOMMEND   : directory-level link is SAFE — no tool state detected."
    echo "              (Re-check after real use; tools may write state later.)"
    link_rel="$rel"
  fi
fi
echo

# --- Collision check -------------------------------------------------------
echo "REPO TARGET : home/$link_rel"
if [ -e "$repo_target" ] || [ -L "$repo_target" ]; then
  echo "             (already present in repo — you may be re-adopting)"
fi
echo "COLLISION   : after linking, a real '$abs' would block the symlink."
echo "             -> \`rm\` it after copying into the repo, or let"
echo "                home-manager move it to *.chezmoi-bak on switch."
echo

# --- The dotfiles.nix edit -------------------------------------------------
echo "ADD TO modules/home/dotfiles.nix (in the correct mkLinks list):"
echo "             \"$link_rel\""
echo

# --- Judgment calls this script will NOT guess -----------------------------
cat <<'EOF'
DECIDE (not auto-detectable):
  [ ] Package source: modules/home/packages.nix (nixpkgs) OR
      modules/darwin/homebrew.nix (cask / not-in-nixpkgs). Gate if machine-specific.
  [ ] Which machines: base list (all) / identity == personal|work / caps.<x>.

THEN:
  1) cp the config into home/<path>   2) add the link line above
  3) rm the original from ~           4) ./rebuild.sh
  5) realpath the deployed path -> must land in ~/.dotfiles

Full runbook: docs/adopting-a-config.md
EOF
