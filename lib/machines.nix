# Modules select behavior by caps and identity, never by hostname.
# Add machines here and in scripts/host-detect.sh. Add capability keys to every
# row and gate the owning module; flake.nix checks that values are booleans.
# External rows may add capabilities consumed by their own modules.
# See README.md for the capability definitions.
{
  personal-mac = {
    system = "aarch64-darwin";
    user = "carpenter";
    identity = "personal";
    # Tiling stays enabled for the macOS 27 diagnostic path, but workspace
    # dock-badge queries are off to remove the lsappinfo/LaunchServices path
    # implicated in the beta crash logs.
    caps = {
      tiling = true;
      sketchybar_workspace_badges = false;
      atuin = true;
      mcp = true;
      skills = true;
      gui = true;
      dev = true;
      infra = false;
      agent_journal = true;
      agents = true;
    };
  };

}
