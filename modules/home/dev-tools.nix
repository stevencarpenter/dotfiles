# mise merges config.toml with conf.d/*.toml in alphabetical order.
# Link the shared base and capability-selected fragments out of store so edits are live.
{
  config,
  lib,
  caps,
  ...
}:

let
  dotfiles = "${config.home.homeDirectory}/.dotfiles";
  link = path: config.lib.file.mkOutOfStoreSymlink "${dotfiles}/home/${path}";
in
{
  home.file = lib.mkMerge [
    {
      ".config/mise/config.toml".source = link ".config/mise/config.toml";
    }
    (lib.mkIf caps.dev {
      ".config/mise/conf.d/dev.toml".source = link ".config/mise/conf.d/dev.toml";
    })
    # External overlays can replace the infrastructure tool list.
    (lib.mkIf caps.infra {
      ".config/mise/conf.d/infra.toml".source = lib.mkDefault (link ".config/mise/conf.d/infra.toml");
    })
  ];
}
