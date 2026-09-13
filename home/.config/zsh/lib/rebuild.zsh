# Raw dotfile edits are live through symlinks. Rebuild only Nix-managed state.
# Resolve DOTFILES_HOST first, then the shared scripts/host-detect.sh matcher.
# Work hosts belong to an external flake and cannot be rebuilt by this wrapper.
function _rebuild_detect_host() {
  emulate -L zsh

  if [[ -n "${DOTFILES_HOST:-}" ]]; then
    print -r -- "${DOTFILES_HOST}"
    return 0
  fi

  # The shared matcher is valid zsh; a missing file is a detection failure.
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

# Deprecated chezmoi command alias retained for existing callers.
function ca() {
  emulate -L zsh
  print -r -- "ca() is deprecated: chezmoi is retired. Use 'rebuild' instead, forwarding now." >&2
  rebuild "$@"
}
