# Reusable out-of-store symlink machinery (public API: homeModules.rawDotfiles,
# LOCKED contract v1.0). Generalizes dotfiles.nix's link helper to ANY source
# root so an external overlay repo gets the same edit-live-without-rebuild
# property for its own files. The home-relative target path always equals the
# path under `root` (mirror-tree convention, same as home/).
{ config, lib, ... }:
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
        force = tree.force;
      })
    ) config.rawDotfiles.trees
  );
}
