# Aggregate of the home-manager module set + the home baseline.
#
# The agenix home-manager module is imported here so secrets.nix can declare
# `age.identityPaths` / `age.secrets`. Each domain submodule self-gates on the
# caps/identity threaded in from lib/machines.nix via extraSpecialArgs.
{
  inputs,
  user,
  ...
}:
{
  imports = [
    inputs.agenix.homeManagerModules.default

    ./dotfiles.nix # out-of-store raw-dotfile symlinks (mkOutOfStoreSymlink)
    ./raw-dotfiles.nix # reusable out-of-store symlink machinery (homeModules.rawDotfiles)
    ./shell.nix # zsh/z4h ownership (programs.zsh.enable = false), atuin
    ./packages.nix # home.packages (core CLI + fonts)
    ./tiling.nix # aerospace + sketchybar + borders (caps.tiling)
    ./dev-tools.nix # dev-only tooling (caps.dev)
    ./ai-stack.nix # claude settings merge, mcp/skills, agents, agent-journal
    ./secrets.nix # agenix age.secrets — decrypts .age blobs, no plaintext here
    ./sync-hooks.nix # home.activation fan-out hooks (mcp/skills/aws/agents)
  ];

  # Home baseline — not owned by any domain module.
  home = {
    username = user;
    homeDirectory = "/Users/${user}";
    # Compatibility baseline from the first Home Manager deployment. This does
    # NOT track the Home Manager input release; only bump after reviewing every
    # intervening state-version migration.
    stateVersion = "26.05";
  };

  programs.home-manager.enable = true;
}
