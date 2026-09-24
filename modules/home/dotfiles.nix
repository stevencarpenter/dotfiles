# Out-of-store symlinks through ~/.dotfiles make raw config edits live.
# Gate by identity and caps; link files separately when their gates differ.
# tiling.nix owns tiling configs; dev-tools.nix and ai-stack.nix generate mise
# and Claude settings. op-render owns personal secret targets; external
# overlays own work secrets. See home/.ssh/config for SSH fragment ownership.
{
  config,
  lib,
  pkgs,
  caps,
  identity,
  ...
}:

let
  dotfiles = "${config.home.homeDirectory}/.dotfiles";

  # Repo path == home-relative target path (the home/ tree mirrors ~), so a
  # single relative path names both the link source and its home.file key.
  link = path: config.lib.file.mkOutOfStoreSymlink "${dotfiles}/home/${path}";
  repoLink = path: config.lib.file.mkOutOfStoreSymlink "${dotfiles}/${path}";
  forcedRepoLink = path: {
    source = repoLink path;
    force = true;
  };

  # Turn a list of relative paths into { "<path>".source = link "<path>"; ... }.
  mkLinks =
    paths:
    lib.genAttrs paths (p: {
      source = link p;
    });

  # Machine-type overlay filename shared by mcp + skills (files are named
  # personal.json / work.json; identity is personal / work).
  overlay = "${identity}.json";
in
{
  home = {
    file = lib.mkMerge [
      # ---- all machines -----------------------------------------------------
      (mkLinks [
        # z4h shell stack (z4h owns lifecycle; keep every file raw: see shell.nix).
        ".zshenv"
        ".config/zsh/.zshenv"
        ".config/zsh/.zshrc"
        ".config/zsh/.zprofile"
        ".config/zsh/.p10k.zsh"
        ".config/zsh/lib"
        ".config/zsh/profile.d/worktrunk-aliases.zsh"
        ".config/zsh/profile.d/common-env.zsh" # non-secret flags

        # Editor / TUI / terminal configs.
        ".config/nvim" # stock LazyVim tree; LazyVim rewrites lazy-lock.json in place
        ".config/yazi"
        ".config/tmux"
        ".config/ghostty" # harmless everywhere; link always regardless of gui cap
        ".ideavimrc"

        # Dev tooling configs (mise config itself is generated in dev-tools.nix).
        ".config/git"
        # Link only the config: jj writes mutable repository metadata beneath
        # ~/.config/jj/repos, which must not land in the dotfiles checkout.
        ".config/jj/config.toml"
        ".config/dev-container"
        ".config/nushell/config.nu" # link the file, not the dir (nushell writes history/env.nu there)

        # Copilot IntelliJ instructions (single file; copilot writes runtime state in the dir).
        ".config/github-copilot/intellij/global-copilot-instructions.md"

        # Route accounts for subprocesses too; shell functions cannot intercept them.
        # ~/.local/bin precedes mise shims on PATH on every machine.
        ".local/bin/gh"

        # AeroSpace's Obsidian capture bindings call this by path. The personal
        # config supplies its known vault; the externally-consumed work config
        # intentionally follows the focused vault instead of naming personal data.
        ".local/bin/obsidian-capture"

        # Worktrunk commit generation is prompt-assisted but locally enforced:
        # invalid model output is retried once, then rejected before Git sees it.
        ".local/bin/worktrunk-commit-generator"

        # Re-seed the tmux server's frozen global env from a pristine login
        # shell without restarting the server (report-only; --apply executes).
        # Ungated like the tmux config itself: inert without a server.
        ".local/bin/tmux-refresh-env"

        # ai-stack.nix merges settings.json at activation to preserve in-tool edits.
        ".claude/statusline-command.sh"
        ".claude/CLAUDE.md"
        ".claude/hooks/agent-journal-stop.sh"
        ".claude/hooks/no-em-dash-commit.sh"
        ".claude/hooks/emit-routing-context.sh"
        ".claude/hooks/agent-reap-subagent-stop.sh"
        # Python bodies the reap hooks exec by path (parse + watchdog).
        # Linked as a directory: every member is ungated and shared by
        # both all-machines reap hooks (SubagentStop and SessionEnd).
        ".claude/hooks/lib"
        ".claude/hooks/wt-create.sh"
        ".claude/hooks/wt-remove.sh"

        # Codex shares Claude's worktree hooks. codexAgentsAssemble combines
        # the instruction body and ~/.codex/AGENTS.d/*.md at activation.
        ".codex/hooks/wt-create.sh"
        ".codex/hooks/wt-remove.sh"
      ])

      # ---- identity: personal ----------------------------------------------
      (lib.optionalAttrs (identity == "personal") (mkLinks [
        ".config/zsh/profile.d/personal-shell-functions.zsh"
        ".config/zsh/profile.d/personal-secrets.zsh" # sources ~/.config/zsh/.personal.env (op-rendered)
        ".config/op/render-manifest"
        ".config/op/adopt-policy.json" # exact allowlist for names-only reverse adoption
        ".local/bin/op-adopt" # guarded live secret -> 1Password adoption; dry-run by default
        ".config/hippo"
      ]))

      # The codebase-memory-mcp installer rewrites ~/.codex/hooks.json, so it
      # must remain writable. codexHooksMerge adds the personal hippo hook.

      # ---- NOT work (homelab access over Tailscale: personal only) ---------
      (lib.optionalAttrs (identity != "work") (mkLinks [
        ".config/zsh/profile.d/tailscale.zsh"
      ]))

      # ---- atuin ------------------------------------------------------------
      # Every machine needs history_filter and [tmux].enabled. Without a config,
      # Atuin defaults to a public sync server, no filter, and inline search.
      # caps.atuin selects sync or local; external overlays can override mkDefault.
      # Link only the file so history.db stays outside the checkout.
      {
        ".config/atuin/config.toml".source = lib.mkDefault (
          link ".config/atuin/config.${if caps.atuin then "sync" else "local"}.toml"
        );
      }

      # Allow whole-file overrides. Link only config.toml so Worktrunk's
      # approvals.toml and lock stay local: approvals contain repo identifiers
      # and exact commands trusted on this machine.
      {
        ".config/worktrunk/config.toml".source = lib.mkDefault (link ".config/worktrunk/config.toml");
      }

      # ---- caps.mcp ---------------------------------------------------------
      # Master config + this machine's overlay. sync-mcp-configs (sync-hooks.nix)
      # reads these at activation time and also consults ~/.config/mcp/overrides/
      # if present: so guarantee that dir exists via a store-linked .keep marker
      # (sync globs overrides/*.json, so .keep is ignored).
      (lib.optionalAttrs caps.mcp (mkLinks [
        ".config/mcp/mcp-master.json"

        # Link files individually to keep adjacent runtime state out of the repo.
        # mcp_sync generates OpenCode's config.
        ".copilot/settings.json"
        ".cursor/cli-config.json"

        # `pi install` updates settings.json's packages through this symlink,
        # producing a tracked diff. Sessions and trust remain outside the repo.
        # piAgentsAssemble owns AGENTS.md; sync-skills owns the skills directory.
        ".pi/agent/settings.json"
        ".pi/agent/models.json"
        ".pi/agent/themes/everforest-dark-hard.json"
        ".pi/agent/prompts/review.md"
        ".pi/agent/prompts/blind-review.md"
        ".pi/agent/AGENTS.d/10-pi-runtime.md"
        ".pi/agent/extensions/omlx-discovery.ts"
        ".pi/agent/extensions/package.json"
        ".pi/agent/extensions/package-lock.json"

        # pi-web-access activity panel defaults to ctrl+shift+w, which pi-warden
        # also binds for its trace sidebar. Keep warden's documented key and move
        # the web-access panel; see getWebSearchConfigDir in pi-web-access.
        ".config/pi/web-search.json"

        # Firstmate owns its checkout and runtime state, never the whole directory.
        ".local/bin/firstmate"
        ".config/firstmate/revision"
        ".local/share/firstmate/config/backend"
        ".local/share/firstmate/config/crew-harness"
      ]))
      (lib.optionalAttrs caps.mcp {
        ".config/mcp/overrides/.keep".text = "";
        # mkDefault: an external overlay repo may take ownership of this
        # machine's overlay (LOCKED contract: declared seam).
        ".config/mcp/machine/${overlay}".source = lib.mkDefault (link ".config/mcp/machine/${overlay}");
      })

      # ---- caps.skills ------------------------------------------------------
      # Manifest + this machine's overlay; sync-skills (sync-hooks.nix) reads them.
      (lib.optionalAttrs caps.skills (mkLinks [
        ".config/skills/skills-master.json"
      ]))
      (lib.optionalAttrs caps.skills {
        # mkDefault: an external overlay repo may take ownership (LOCKED contract: declared seam).
        ".config/skills/machine/${overlay}".source = lib.mkDefault (
          link ".config/skills/machine/${overlay}"
        );
      })
      # Link personal skills from this checkout for each tool.
      (lib.optionalAttrs (caps.skills && identity == "personal") {
        # Keep use-railway static until upstream restores the injection guards.
        # A 2026-07 refresh removed shell-injection (dal.py) and SQL-injection
        # (pg-extensions.py) protections restored in this copy.
        ".config/opencode/skills/use-railway" = forcedRepoLink "skills/personal/use-railway";
        # Pi and Codex both read ~/.agents/skills, so the upstream install there
        # would shadow this pinned snapshot. Pin it too; Claude has its own copy.
        ".agents/skills/use-railway" = forcedRepoLink "skills/personal/use-railway";
        ".claude/skills/use-railway" = forcedRepoLink "skills/personal/use-railway";
        ".codex/skills/playwright" = forcedRepoLink "skills/personal/playwright";
        ".codex/skills/use-railway" = forcedRepoLink "skills/personal/use-railway";
        ".cursor/skills/use-railway" = forcedRepoLink "skills/personal/use-railway";
        ".copilot/skills/use-railway" = forcedRepoLink "skills/personal/use-railway";
        ".junie/skills/clerk" = forcedRepoLink "skills/personal/clerk";
        ".junie/skills/clerk-testing" = forcedRepoLink "skills/personal/clerk-testing";
        ".junie/skills/clerk-webhooks" = forcedRepoLink "skills/personal/clerk-webhooks";
        ".junie/skills/design-an-interface" = forcedRepoLink "skills/personal/design-an-interface";
        ".junie/skills/domain-model" = forcedRepoLink "skills/personal/domain-model";
        ".junie/skills/gh-axi" = forcedRepoLink "skills/personal/gh-axi";
        ".junie/skills/github-triage" = forcedRepoLink "skills/personal/github-triage";
        ".junie/skills/request-refactor-plan" = forcedRepoLink "skills/personal/request-refactor-plan";
        ".junie/skills/ubiquitous-language" = forcedRepoLink "skills/personal/ubiquitous-language";

        # ponytail: static v4.9.0 skill copies with local prose edits. Refresh
        # manually and review the diff. Link only for tools without plugin support
        # to avoid loading the skill twice.
        ".junie/skills/ponytail" = forcedRepoLink "skills/personal/ponytail";
        ".junie/skills/ponytail-review" = forcedRepoLink "skills/personal/ponytail-review";
        ".junie/skills/ponytail-audit" = forcedRepoLink "skills/personal/ponytail-audit";
        ".junie/skills/ponytail-debt" = forcedRepoLink "skills/personal/ponytail-debt";
        ".junie/skills/ponytail-gain" = forcedRepoLink "skills/personal/ponytail-gain";
        ".junie/skills/ponytail-help" = forcedRepoLink "skills/personal/ponytail-help";
        ".copilot/skills/ponytail" = forcedRepoLink "skills/personal/ponytail";
        ".copilot/skills/ponytail-review" = forcedRepoLink "skills/personal/ponytail-review";
        ".copilot/skills/ponytail-audit" = forcedRepoLink "skills/personal/ponytail-audit";
        ".copilot/skills/ponytail-debt" = forcedRepoLink "skills/personal/ponytail-debt";
        ".copilot/skills/ponytail-gain" = forcedRepoLink "skills/personal/ponytail-gain";
        ".copilot/skills/ponytail-help" = forcedRepoLink "skills/personal/ponytail-help";
        ".cursor/skills/ponytail" = forcedRepoLink "skills/personal/ponytail";
        ".cursor/skills/ponytail-review" = forcedRepoLink "skills/personal/ponytail-review";
        ".cursor/skills/ponytail-audit" = forcedRepoLink "skills/personal/ponytail-audit";
        ".cursor/skills/ponytail-debt" = forcedRepoLink "skills/personal/ponytail-debt";
        ".cursor/skills/ponytail-gain" = forcedRepoLink "skills/personal/ponytail-gain";
        ".cursor/skills/ponytail-help" = forcedRepoLink "skills/personal/ponytail-help";
      })

      # ---- caps.agent_journal ----------------------------------------------
      (lib.optionalAttrs caps.agent_journal (mkLinks [
        ".local/bin/agent-journal"
        ".local/bin/agent-note"
      ]))

      # ---- agent-reap SessionEnd teardown hook (all machines) ---------------
      # settings-base.json runs this on SessionEnd to disband the team.
      # It exits without action if agent-reap is not installed yet.
      (mkLinks [
        ".claude/hooks/agent-reap-session-end.sh"
      ])

      # ---- agent-reap (all machines) ----------------------------------------
      # `just sync` installs the CLI; linking its path would collide with uv's shim.
      # Every host gets the config. Without tmux or a team, agent-reap does nothing.
      (mkLinks [
        ".config/agent-reap" # config.toml (plain out-of-store symlink; edits are live)
      ])

      # ---- ssh tier 1: universal base (all machines) -------------------------
      # External overlays can override the file or add config.d fragments.
      {
        ".ssh/config".source = lib.mkDefault (link ".ssh/config");
      }

      # ---- extension seam dirs (all machines) --------------------------------
      {
        # Real, neutral overlay roots avoid nesting external home.file entries
        # beneath the out-of-store .config/git and .config/tmux parent symlinks.
        #
        # SSH includes personal rendered and external work fragments before
        # every Host block so their settings take precedence.
        ".ssh/config.d/.keep".text = "";
        ".config/external-overlays/git/.keep".text = "";
        ".config/external-overlays/tmux/.keep".text = "";

        # Create fragment directories even when no overlay supplies files.
        # ai-stack.nix deep-merges settings.d JSON over managed settings.
        ".claude/settings.d/.keep".text = "";

        # codexAgentsAssemble appends Markdown fragments from this directory.
        ".codex/AGENTS.d/.keep".text = "";

        # piAgentsAssemble appends 10-pi-runtime.md and external fragments.
        ".pi/agent/AGENTS.d/.keep".text = "";
      }
    ];

    # Codex has no include directive, so assemble instructions after linkGeneration
    # creates fragment symlinks. This hook must be the only writer to avoid
    # home-manager backup collisions. Body edits require a switch to take effect.
    activation = {
      codexAgentsAssemble = lib.hm.dag.entryAfter [ "linkGeneration" ] ''
        (
          set -u
          BODY="${dotfiles}/home/.codex/AGENTS.md"
          OUT="$HOME/.codex/AGENTS.md"

          if [ ! -f "$BODY" ]; then
            echo "Warning: Codex AGENTS body not found at $BODY; leaving $OUT alone." >&2
            exit 0
          fi

          mkdir -p "$HOME/.codex"
          tmp="$OUT.hm-tmp"
          cat "$BODY" > "$tmp"

          # Append overlay Markdown in lexical order; ignore an unmatched glob.
          for frag in "$HOME"/.codex/AGENTS.d/*.md; do
            [ -f "$frag" ] || continue
            printf '\n' >> "$tmp"
            cat "$frag" >> "$tmp"
          done

          mv "$tmp" "$OUT"
        ) || true
      '';

      # pi also lacks includes. Reuse the Codex body with pi-specific fragments,
      # after linkGeneration creates their symlinks. Edits require a switch.
      piAgentsAssemble = lib.hm.dag.entryAfter [ "linkGeneration" ] ''
        (
          set -u
          BODY="${dotfiles}/home/.codex/AGENTS.md"
          OUT="$HOME/.pi/agent/AGENTS.md"

          if [ ! -f "$BODY" ]; then
            echo "Warning: Codex AGENTS body not found at $BODY; leaving $OUT alone." >&2
            exit 0
          fi

          mkdir -p "$HOME/.pi/agent"
          tmp="$OUT.hm-tmp"
          cat "$BODY" > "$tmp"

          # Append managed and external Markdown fragments in lexical order.
          for frag in "$HOME"/.pi/agent/AGENTS.d/*.md; do
            [ -f "$frag" ] || continue
            printf '\n' >> "$tmp"
            cat "$frag" >> "$tmp"
          done

          mv "$tmp" "$OUT"
        ) || true
      '';
    }
    // lib.optionalAttrs (identity == "personal") {
      # Add the personal hippo hook without replacing other hooks. Convert any
      # store symlink to a writable file for the codebase-memory-mcp installer.
      codexHooksMerge = lib.hm.dag.entryAfter [ "linkGeneration" ] ''
        (
          set -u
          HOOKS="$HOME/.codex/hooks.json"
          hippo="$HOME/.local/share/hippo-brain/shell/claude-session-hook.sh"
          mkdir -p "$HOME/.codex"

          if [ -L "$HOOKS" ]; then
            content="$(cat "$HOOKS" 2>/dev/null || printf '{"hooks":{}}')"
            rm -f "$HOOKS"
            printf '%s' "$content" > "$HOOKS"
          fi
          [ -f "$HOOKS" ] || printf '{"hooks":{}}' > "$HOOKS"

          if merged="$(${pkgs.jq}/bin/jq --arg cmd "$hippo" '
                .hooks //= {} |
                if ([.hooks.SessionStart[]?.hooks[]?.command] | index($cmd)) != null then .
                else .hooks.SessionStart = [{hooks: [{type: "command", command: $cmd}]}]
                       + (.hooks.SessionStart // [])
                end' "$HOOKS")"; then
            printf '%s\n' "$merged" > "$HOOKS.hm-tmp" && mv "$HOOKS.hm-tmp" "$HOOKS"
          else
            echo "Warning: could not merge hippo hook into $HOOKS; leaving it alone." >&2
          fi
        ) || true
      '';
    };
  };

  # One link deliberately routed through the public rawDotfiles API so the
  # in-repo build exercises the same code path external wrappers use.
  rawDotfiles.trees = [
    {
      root = "${dotfiles}/home";
      paths = [ ".duckdbrc" ];
    }
  ];
}
