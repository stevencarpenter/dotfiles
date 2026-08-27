# nix-darwin rebuild helper (replaces the retired chezmoi-apply `ca()` wrapper).
#
# Under nix-darwin the raw dotfiles in ~/.dotfiles/home are out-of-store
# symlinks, so editing a config needs NO rebuild — the change is live. Only
# system/package/module changes (anything the flake evaluates) require a
# switch. This lib provides `rebuild`, a thin wrapper around
# `sudo darwin-rebuild switch --flake ~/.dotfiles#<host>`, and a transitional
# `ca()` shim that warns the old chezmoi verb is gone and forwards to it.

# Map this machine to its flake configuration name.
#
# Only `personal-mac` remains in lib/machines.nix. A work machine is built by its
# own external wrapper flake with its own host name, so it must NOT resolve here
# — it sets DOTFILES_HOST (or uses the wrapper's own command) instead. Resolving
# a name this flake does not declare would fail at `darwin-rebuild` with a
# confusing "does not provide attribute" error.
# Resolution order:
#   1. $DOTFILES_HOST, if set (explicit override — always wins).
#   2. `scutil --get LocalHostName` via the SHARED matcher in
#      scripts/host-detect.sh — the single place machine names are added. This
#      wrapper previously kept its own `*personal*` substring match, which
#      failed to resolve the `Stevens-MacBook-Pro` alias the bash side accepted.
# Prints the resolved host on stdout, or nothing + nonzero on miss.
function _rebuild_detect_host() {
  emulate -L zsh

  if [[ -n "${DOTFILES_HOST:-}" ]]; then
    print -r -- "${DOTFILES_HOST}"
    return 0
  fi

  # The host-detect.sh body (case/echo/return) is valid zsh, so source the
  # shared matcher rather than keep a second one. A missing file (a checkout
  # that predates it) reads as a detection miss, not a syntax error.
  source "${HOME}/.dotfiles/scripts/host-detect.sh" 2>/dev/null || return 1
  detect_host
}

# darwin-rebuild switch for this machine's flake config.
# Extra args are passed through to darwin-rebuild (e.g. `rebuild --show-trace`).
function rebuild() {
  emulate -L zsh

  local host
  if ! host="$(_rebuild_detect_host)"; then
    print -r -- "rebuild: could not determine the flake host for this machine." >&2
    print -r -- "  LocalHostName = '$(scutil --get LocalHostName 2>/dev/null)'" >&2
    print -r -- "  Set DOTFILES_HOST to one of: personal-mac" >&2
    print -r -- "  e.g.  DOTFILES_HOST=personal-mac rebuild" >&2
    return 1
  fi

  case "${host}" in
    personal-mac) ;;
    *)
      print -r -- "rebuild: '${host}' is not a known flake host (personal-mac)." >&2
      return 1
      ;;
  esac

  print -r -- "Rebuilding nix-darwin for ${host}..."
  sudo darwin-rebuild switch --flake "${HOME}/.dotfiles#${host}" "$@"
}

# Transitional shim: `ca` was the chezmoi-apply wrapper. It is retired under
# nix-darwin. Warn once and forward to `rebuild` so muscle memory still works.
function ca() {
  emulate -L zsh
  print -r -- "ca() is deprecated: chezmoi is retired. Use 'rebuild' instead — forwarding now." >&2
  rebuild "$@"
}
