# Shell ownership declaration.
#
# zsh4humans (z4h) owns the ENTIRE zsh lifecycle. ~/.zshenv bootstraps z4h,
# ~/.zshrc runs `z4h init` and does all real work post-init, and the prompt is
# powerlevel10k configured by ~/.config/zsh/.p10k.zsh. All of these ship as raw
# out-of-store symlinks from dotfiles.nix.
#
# home-manager's programs.zsh generates its OWN ~/.zshrc / ~/.zshenv, which
# would collide with and clobber the z4h bootstrap. So it is disabled here — we
# want home-manager to install zsh-adjacent *packages* (in packages.nix) but
# never to manage the rc files.
#
# The interactive login shell itself (chsh / /etc/shells) is handled at the
# system level in modules/darwin/core.nix (environment.shells + the user's
# shell). Do not duplicate that here.
{ ... }:

{
  # Let z4h own ~/.zshrc and ~/.zshenv entirely (see dotfiles.nix raw symlinks).
  programs.zsh.enable = false;

  # No home.sessionVariables: z4h's ~/.zshenv already exports XDG_* and ZDOTDIR,
  # and z4h runs `setopt no_global_rcs`, so anything home-manager wrote to its
  # own session-vars file would either be ignored or fight the z4h bootstrap.
  # Keep environment ownership in the raw zsh files + darwin core.
}
