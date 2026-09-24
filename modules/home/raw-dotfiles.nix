# Public API (homeModules.rawDotfiles, contract v1.0): link ~/<path> to
# <root>/<path> out of store so external overlay config edits are live.
{
  config,
  lib,
  pkgs,
  ...
}:
{
  options.rawDotfiles.trees = lib.mkOption {
    type = lib.types.listOf (
      lib.types.submodule {
        options = {
          root = lib.mkOption { type = lib.types.str; };
          paths = lib.mkOption { type = lib.types.listOf lib.types.str; };
          force = lib.mkOption {
            type = lib.types.bool;
            default = false;
          };
        };
      }
    );
    default = [ ];
    description = "Out-of-store symlink trees: each path links ~/<path> -> <root>/<path>.";
  };

  config.home.file = lib.mkMerge (
    map (
      tree:
      lib.genAttrs tree.paths (p: {
        source = config.lib.file.mkOutOfStoreSymlink "${tree.root}/${p}";
        inherit (tree) force;
      })
    ) config.rawDotfiles.trees
  );

  # Check the realized tree, including recursive home.file entries and files
  # supplied by other modules. A former directory link can survive a switch to
  # individual files; writing through it would modify the source checkout.
  config.home.activation.checkLinkParents =
    lib.hm.dag.entryBefore
      [
        "checkLinkTargets"
        "writeBoundary"
      ]
      ''
        ${pkgs.bash}/bin/bash ${../../scripts/check-home-link-parents.sh} "$newGenPath/home-files" "$HOME"
      '';
}
