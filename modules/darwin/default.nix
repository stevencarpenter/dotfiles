# Aggregate of the darwin (system) module set. Imported by every host shim.
# Each submodule self-gates on caps/identity from specialArgs.
{ ... }:
{
  imports = [
    ./core.nix # nix daemon settings, login shell, launchd agents, stateVersion
    ./macos-defaults.nix # macOS preferences
    ./homebrew.nix # declarative taps/brews/casks against an independent brew install, gated per caps
  ];
}
