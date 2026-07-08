# Aggregate of the darwin (system) module set. Imported by every host shim.
# Each submodule self-gates on caps/identity from specialArgs.
{ ... }:
{
  imports = [
    ./core.nix # nix daemon settings, login shell, launchd agents, stateVersion
    ./macos-defaults.nix # system.defaults.* (ported from configure-macos-defaults)
    ./homebrew.nix # nix-homebrew taps/brews/casks, gated per caps
  ];
}
