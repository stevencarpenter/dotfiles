# Shared modules select behavior from lib/machines.nix.
# Keep only declarations unique to this host here.
{ user, ... }:
{
  imports = [ ../modules/darwin ];

  home-manager.users.${user}.rawDotfiles.trees = [
    {
      root = "/Users/${user}/.dotfiles/home";
      paths = [
        ".config/agent-journal/config.toml"
        ".config/agent-journal/workstreams.toml"
      ];
    }
  ];
}
