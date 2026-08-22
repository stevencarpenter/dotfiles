# Dev tooling: mise config assembly.
#
# Ports dot_config/mise/config.toml.tmpl. The template had an ungated base
# [tools] list plus two capability-gated blocks (dev, infra). Rather than
# render one per-host file into the store (which would lose the edit-without-
# rebuild property the rest of the raw home/ tree keeps), the base and the two
# gated blocks are split into separate raw files and symlinked out-of-store:
#   home/.config/mise/config.toml        — ungated base, linked on every host
#   home/.config/mise/conf.d/dev.toml    — linked only when caps.dev
#   home/.config/mise/conf.d/infra.toml  — linked only when caps.infra
# mise loads ~/.config/mise/conf.d/*.toml (alphabetical) as additional global
# config and merges their [tools] tables with config.toml. The three blocks are
# disjoint, so the merged tool set is exactly the template's per-host output.
#
# FALLBACK (if a future mise ever stops honoring conf.d/*.toml global merge):
# replace the conf.d split with three full per-host files
# (home/.config/mise/config.{personal,work,lab}.toml, each the complete tool
# list for that host) and select one by `identity` here — same shape as
# tiling.nix's aerospace.{personal,work}.toml selection. conf.d is the
# preferred form because it keeps the shared base in one place.
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
    # mkDefault: caps.infra tooling is corporate-access flavored (teleport-ent,
    # ops databases), so an external overlay may want to own the list. Same seam
    # pattern as the atuin/worktrunk/mcp/skills defaults in dotfiles.nix.
    (lib.mkIf caps.infra {
      ".config/mise/conf.d/infra.toml".source = lib.mkDefault (link ".config/mise/conf.d/infra.toml");
    })
  ];
}
