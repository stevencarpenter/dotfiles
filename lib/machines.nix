# Machine capability table — 1:1 mirror of the retired .chezmoidata/machines.toml.
#
# Each attr maps a machine name to its platform, owning user, an `identity`
# string (replaces the old `hasPrefix work/personal/lab` gates), and a `caps`
# set of capability booleans. Modules gate on `caps.<x>` / `identity` threaded
# in via specialArgs — there are NO hostname checks inside modules.
#
# Adding a machine: copy a row, rename, flip the capabilities you don't want,
# then add its name to the prompt hint in bootstrap.sh's detect map.
# Adding a capability: add the key to EVERY row below (flake.nix asserts each
# row carries at least the canonical key set, all booleans — external wrapper
# rows may add extra caps) and gate the owning module on `caps.<capability>`.
#
# Capabilities
#   tiling — install/configure aerospace + sketchybar + borders (the tiling
#            window manager stack). Headless / Screen Share boxes set this
#            false because point-and-click + native macOS windowing is
#            preferred there.
#   sketchybar_workspace_badges — allow SketchyBar workspace app icons to query
#            LaunchServices via lsappinfo for dock notification dots. Keep this
#            off on machines where LaunchServices is under triage.
#   atuin  — sync shell history to the self-hosted atuin server. Selects WHICH
#            config variant deploys, not whether one does: true ->
#            home/.config/atuin/config.sync.toml (carries sync_address),
#            false -> config.local.toml (auto_sync = false, names no server).
#            BOTH carry history_filter and the tmux popup — those are not
#            sync concerns and belong everywhere. Leave it false anywhere
#            history should stay on the machine it was typed on.
#   mcp    — deploy the MCP master config + run the post-apply sync hook that
#            generates per-tool MCP configs (codex, opencode, cursor, copilot,
#            …). Off on machines that don't run a constellation of AI dev tools.
#   skills — deploy ~/.config/skills/ (the skill manifest + machine overlays)
#            and run the post-apply sync-skills hook that populates
#            ~/.claude/skills/ from vendored + personal skills. Off on machines
#            that don't run Claude Code skills.
#   gui    — install GUI applications + display fonts. On for any machine with a
#            usable display. CLI tools that ship as a cask (e.g. 1password-cli)
#            stay outside this gate.
#   dev    — machine does language / web / mobile development. Gates the
#            dev-only language-LSP plugins, dev-flavored Brewfile entries, and
#            copilot trusted folders. Off on work (own dev curation).
#   infra  — install infrastructure / cluster-ops tooling via mise: Kubernetes
#            (kubectl, helm, k9s, kustomize), corporate access (teleport-ent),
#            ops databases (mysql, duckdb). IaC + build tooling live in the
#            global mise block and are not gated here. Work-only today.
#   agent_journal — deploy the personal Obsidian agent-journal beta config,
#            CLI wrappers, and Claude lifecycle hook. Personal-only until the
#            workflow proves itself.
#   agents — clone the personal agent-registry (SSH) and run its installer,
#            which fans the canonical agents out to each tool's native format.
#            Personal-only: registry + agents are personal content.
# Note on token-auditor: there is intentionally no `token_auditor` capability.
# `just sync` installs the standalone token-auditor uv tool unconditionally on
# every machine; a former placeholder cap was dropped (2026-07-17) because no
# consumer read it. If a host ever needs an opt-out, re-add the cap and thread
# it to the sync recipe via a generated env file (see tiling.nix's machine.env
# pattern for the nix→shell precedent).
#
# Note on VPN: there is intentionally no `wireguard` capability. The home
# network uses Tailscale (WireGuard under the hood); add the capability with a
# real consumer in tree if a future device needs a raw WG tunnel.
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
