# Machine capability table — 1:1 mirror of the retired .chezmoidata/machines.toml.
#
# Each attr maps a machine name to its platform, owning user, an `identity`
# string (replaces the old `hasPrefix work/personal/lab` gates), and a `caps`
# set of capability booleans. Modules gate on `caps.<x>` / `identity` threaded
# in via specialArgs — there are NO hostname checks inside modules.
#
# Adding a machine: copy a row, rename, flip the capabilities you don't want,
# then add its name to the prompt hint in bootstrap.sh's detect map.
# Adding a capability: add the key to EVERY row below (flake.nix asserts the
# row shape) and gate the owning module on `caps.<capability>`.
#
# Capabilities
#   tiling — install/configure aerospace + sketchybar + borders (the tiling
#            window manager stack). Headless / Screen Share boxes set this
#            false because point-and-click + native macOS windowing is
#            preferred there.
#   sketchybar_workspace_badges — allow SketchyBar workspace app icons to query
#            LaunchServices via lsappinfo for dock notification dots. Keep this
#            off on machines where LaunchServices is under triage.
#   atuin  — deploy ~/.config/atuin/config.toml pointing at the self-hosted
#            atuin server. Off on work machines so corporate shells never sync
#            history to the home lab.
#   mcp    — deploy the MCP master config + run the post-apply sync hook that
#            generates per-tool MCP configs (codex, opencode, cursor, copilot,
#            …). Off on machines that don't run a constellation of AI dev tools.
#   skills — deploy ~/.config/skills/ (the skill manifest + machine overlays)
#            and run the post-apply sync-skills hook that populates
#            ~/.claude/skills/ from vendored + personal skills. Off on machines
#            that don't run Claude Code skills.
#   gui    — install GUI applications + display fonts. On for any machine with a
#            usable display, including lab-mac while reached via macOS Screen
#            Share. CLI tools that ship as a cask (e.g. 1password-cli) stay
#            outside this gate.
#   dev    — machine does language / web / mobile development. Gates the
#            dev-only language-LSP plugins, dev-flavored Brewfile entries, and
#            copilot trusted folders. Off on work (own dev curation) and lab
#            (home server, not a dev box).
#   aws_sso — machine runs the AWS SSO profile generator (aws_config_gen/) via
#            the post-apply hook. Work-only today; scoped narrower than a
#            generic `aws` capability.
#   infra  — install infrastructure / cluster-ops tooling via mise: Kubernetes
#            (kubectl, helm, k9s, kustomize), corporate access (teleport-ent),
#            ops databases (mysql, duckdb). IaC + build tooling live in the
#            global mise block and are not gated here. Work-only today; lab
#            flips it on once homelab cluster-ops moves there.
#   agent_journal — deploy the personal Obsidian agent-journal beta config,
#            CLI wrappers, and Claude lifecycle hook. Personal-only until the
#            workflow proves itself.
#   agents — clone the personal agent-registry (SSH) and run its installer,
#            which fans the canonical agents out to each tool's native format.
#            Personal-only: registry + agents are personal content.
#   token_auditor — install the standalone token-auditor uv tool (public repo)
#            so token-auditor / codax land on PATH for the codax/claade/opencade
#            shell wrappers. Public https repo. NOTE: this cap is currently an
#            ORPHAN — `just sync` installs token-auditor unconditionally and does
#            not read this flag, so it grants no opt-out yet. Either wire the
#            `sync` recipe to gate on it or drop the key (kept for now as a
#            reserved opt-out affordance across all rows).
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
      aws_sso = false;
      infra = false;
      agent_journal = true;
      agents = true;
      token_auditor = true;
    };
  };

  work-mac = {
    system = "aarch64-darwin";
    user = "carpenter";
    identity = "work";
    caps = {
      tiling = true;
      sketchybar_workspace_badges = true;
      atuin = false;
      mcp = true;
      skills = true;
      gui = true;
      dev = false;
      aws_sso = true;
      infra = true;
      agent_journal = false;
      agents = false;
      token_auditor = true;
    };
  };

  lab-mac = {
    system = "x86_64-darwin";
    user = "carpenter";
    identity = "lab";
    # 2019 i9 Intel MacBook Pro, accessed via macOS Screen Share. Home-server
    # de facto (adguard + Tailscale + self-hosted atuin sync server, so atuin
    # is also true here as a client). Claude Code + MCP fan-out on so the
    # assistant has local context. Flip `infra`/`gui` as stand-up completes.
    caps = {
      tiling = false;
      sketchybar_workspace_badges = false;
      atuin = true;
      mcp = true;
      skills = true;
      gui = true;
      dev = false;
      aws_sso = false;
      infra = false;
      agent_journal = false;
      agents = false;
      token_auditor = true;
    };
  };
}
