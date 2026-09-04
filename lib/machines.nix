# Machine capability table — 1:1 mirror of the retired .chezmoidata/machines.toml.
#
# Each attr maps a machine name to its platform, owning user, an `identity`
# string (replaces the old `hasPrefix work/personal/lab` gates), and a `caps`
# set of capability booleans. Modules gate on `caps.<x>` / `identity` threaded
# in through specialArgs — there are NO hostname checks inside modules.
#
# Adding a machine: copy a row, rename, flip the capabilities you don't want,
# then add its name to the prompt hint in bootstrap.sh's detect map.
# Adding a capability: add the key to EVERY row below (flake.nix asserts each
# row carries at least the canonical key set, all booleans — external wrapper
# rows may add extra caps) and gate the owning module on `caps.<capability>`.
# Full per-capability rationale is in README.md; brief reminders inline:
#   tiling — WM stack; off for headless / Screen Share boxes.
#   sketchybar_workspace_badges — off where LaunchServices is under triage.
#   atuin — selects sync vs local config variant (NOT whether atuin deploys).
#   mcp — MCP master config + per-tool sync hook.
#   skills — skill manifest + ~/.claude/skills and ~/.pi/agent/skills fan-out hook.
#   gui — GUI casks + display fonts.
#   dev — dev LSP plugins, dev-flavored brews, copilot trusted folders.
#   infra — ops tooling via mise (Kubernetes, teleport, ops databases).
#   agent_journal — personal Obsidian journal + Claude lifecycle hook.
#   agents — personal agent-registry clone + install.
# No `token_auditor` cap: `just sync` installs that tool unconditionally
# on every machine (it's inert without its own backend). No `wireguard` cap:
# the home network uses Tailscale (WG under the hood); add only with a real
# consumer in tree.
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
