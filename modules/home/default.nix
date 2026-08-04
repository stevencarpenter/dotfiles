# Aggregate of the home-manager module set + the home baseline.
#
# Each domain submodule self-gates on the caps/identity threaded in from
# lib/machines.nix via extraSpecialArgs.
#
# There is deliberately no secrets module here. Personal secrets render from
# 1Password via op-render (see secrets/README.md); work secrets are the
# external wrapper's custody. This repo declares no age secrets and does not
# depend on agenix.
{
  user,
  ...
}:
{
  imports = [
    ./dotfiles.nix # out-of-store raw-dotfile symlinks (mkOutOfStoreSymlink)
    ./raw-dotfiles.nix # reusable out-of-store symlink machinery (homeModules.rawDotfiles)
    ./shell.nix # zsh/z4h ownership (programs.zsh.enable = false), atuin
    ./packages.nix # home.packages (core CLI + fonts)
    ./tiling.nix # aerospace + sketchybar + borders (caps.tiling)
    ./dev-tools.nix # dev-only tooling (caps.dev)
    ./ai-stack.nix # claude settings merge, mcp/skills, agents, agent-journal
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
