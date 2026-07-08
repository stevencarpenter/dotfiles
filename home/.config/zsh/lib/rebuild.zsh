# nix-darwin rebuild helper (replaces the retired chezmoi-apply `ca()` wrapper).
#
# Under nix-darwin the raw dotfiles in ~/.dotfiles/home are out-of-store
# symlinks, so editing a config needs NO rebuild — the change is live. Only
# system/package/module changes (anything the flake evaluates) require a
# switch. This lib provides `rebuild`, a thin wrapper around
# `sudo darwin-rebuild switch --flake ~/.dotfiles#<host>`, and a transitional
# `ca()` shim that warns the old chezmoi verb is gone and forwards to it.

# Map this machine to its flake configuration name (personal-mac/work-mac/lab-mac).
# Resolution order:
#   1. $DOTFILES_HOST, if set (explicit override — always wins).
#   2. `scutil --get LocalHostName`, matched against the patterns below.
# Edit the case patterns to match your machines' actual LocalHostName values
# (see `scutil --get LocalHostName`); until then, set DOTFILES_HOST in your
# environment. Prints the resolved host on stdout, or nothing + nonzero on miss.
function _rebuild_detect_host() {
  emulate -L zsh

  if [[ -n "${DOTFILES_HOST:-}" ]]; then
    print -r -- "${DOTFILES_HOST}"
    return 0
  fi

  local local_host
  local_host="$(scutil --get LocalHostName 2>/dev/null)"

  case "${local_host:l}" in
    *work*)     print -r -- "work-mac" ;;
    *lab*)      print -r -- "lab-mac" ;;
    *personal*) print -r -- "personal-mac" ;;
    *) return 1 ;;
  esac
}

# darwin-rebuild switch for this machine's flake config.
# Extra args are passed through to darwin-rebuild (e.g. `rebuild --show-trace`).
function rebuild() {
  emulate -L zsh

  local host
  if ! host="$(_rebuild_detect_host)"; then
    print -r -- "rebuild: could not determine the flake host for this machine." >&2
    print -r -- "  LocalHostName = '$(scutil --get LocalHostName 2>/dev/null)'" >&2
    print -r -- "  Set DOTFILES_HOST to one of: personal-mac, work-mac, lab-mac" >&2
    print -r -- "  e.g.  DOTFILES_HOST=personal-mac rebuild" >&2
    return 1
  fi

  case "${host}" in
    personal-mac|work-mac|lab-mac) ;;
    *)
      print -r -- "rebuild: '${host}' is not a known flake host (personal-mac|work-mac|lab-mac)." >&2
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
