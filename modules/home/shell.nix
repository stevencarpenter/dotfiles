# z4h owns shell initialization through raw symlinks in dotfiles.nix.
# core.nix selects the login shell; packages.nix installs shell tools.
_:

{
  # Home-manager-generated rc files would overwrite z4h's bootstrap.
  programs.zsh.enable = false;

  # Keep XDG_* and ZDOTDIR in z4h's .zshenv. Its no_global_rcs setting bypasses
  # home-manager's session-variable initialization.
}
