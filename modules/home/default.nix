# Home-manager modules gate on caps and identity from lib/machines.nix.
# Personal secrets use op-render; external wrappers own work secrets.
{
  user,
  ...
}:
{
  imports = [
    ./dotfiles.nix # out-of-store raw-dotfile symlinks (mkOutOfStoreSymlink)
    ./raw-dotfiles.nix # reusable out-of-store symlink machinery (homeModules.rawDotfiles)
    ./shell.nix # zsh/z4h ownership
    ./packages.nix # home.packages (core CLI + fonts)
    ./tiling.nix # aerospace + sketchybar + borders (caps.tiling)
    ./dev-tools.nix # mise dev and infra config
    ./ai-stack.nix # Claude settings merge
    ./sync-hooks.nix # MCP/skills sync and secret-render age check
  ];

  # Home baseline: not owned by any domain module.
  home = {
    username = user;
    homeDirectory = "/Users/${user}";
    # Compatibility baseline, not the input release. Review migrations before changing it.
    stateVersion = "26.05";
  };

  programs.home-manager.enable = true;
}
