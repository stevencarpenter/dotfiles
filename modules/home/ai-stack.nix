# AI stack: Claude Code settings.json merge.
#
# Ports dot_claude/modify_settings.json.tmpl (a chezmoi modify_ script that
# read-merged a managed JSON block over the live ~/.claude/settings.json so
# Claude Code's own in-tool edits — theme, model, effortLevel, /sandbox
# additions — survive apply). home-manager cannot own settings.json as a store
# file (it would clobber those in-tool edits and fight Claude's serializer), so
# this is a home.activation entry that keeps the original bash+jq merge, with
# the four Go-template conditionals ($work/$hippo/$dev/$agents) resolved to Nix
# values from the host row.
#
# Split of responsibility:
#   home/.claude/settings-base.json   — the capability-INVARIANT managed block
#                                       (env, permissions, always-on hooks,
#                                       always-on plugins, marketplaces, scalars).
#                                       Read from the working tree at activation.
#   variant (computed below in Nix)   — the capability-VARYING slice pulled OUT
#                                       of the template: the 7 conditional plugin
#                                       flags + the conditional SessionStart hooks.
#   activation jq                     — base * variant = managed; then
#                                       existing * managed, seed model/effort,
#                                       ensure ~/.cache/pre-commit sandbox-write,
#                                       and (when a SessionStart capability is
#                                       off) strip its stale hook entry.
#
# BOUNDARY: this module owns ONLY the settings.json merge. The raw dotfiles it
# depends on are declared elsewhere:
#   - ~/.claude/hooks/*, ~/.claude/statusline-command.sh  -> modules/home/dotfiles.nix
#   - ~/.config/mcp/machine/<identity>.json (overlay)     -> modules/home/dotfiles.nix (identity-gated)
#   - the MCP/skills fan-out that consumes those overlays -> modules/home/sync-hooks.nix
#
# ~/.claude/skills interplay note: TWO writers populate ~/.claude/skills/ — the
# agenix-decrypted work skills (modules/home/secrets.nix) and the sync-skills
# activation (modules/home/sync-hooks.nix). sync-skills only GCs entries it
# recorded, so the decrypted work skills are safe PROVIDED they are written
# before skillsSync runs. That ordering lives in sync-hooks.nix / secrets.nix,
# not here; this module does not touch ~/.claude/skills.
{ config, pkgs, lib, caps, identity, ... }:

let
  # Resolve the template's four conditionals from the host row.
  work = identity == "work"; # $work = hasPrefix "work" .machine
  hippo = identity == "personal"; # $hippo = hasPrefix "personal" .machine
  dev = caps.dev; # $dev = (index .machines .machine).dev
  agents = caps.agents; # $agents = (index .machines .machine).agents

  home = config.home.homeDirectory;

  # SessionStart hook entries, unioned exactly like the template's sentinel
  # array. Absolute homeDirectory paths (uv/hooks are exec'd; no shell tilde
  # expansion guaranteed for a JSON command string invoked directly).
  sessionStartEntries =
    (lib.optional hippo {
      hooks = [
        {
          type = "command";
          command = "${home}/.local/share/hippo-brain/shell/claude-session-hook.sh";
        }
      ];
    })
    ++ (lib.optional agents {
      hooks = [
        {
          type = "command";
          command = "${home}/.claude/hooks/emit-routing-context.sh";
        }
      ];
    });

  # The capability-varying managed slice. When both SessionStart capabilities
  # are off we omit the SessionStart key entirely (matching the template's
  # `{{- if or $hippo $agents }}` guard) so the merge leaves the live array
  # untouched and the strip block below does the removal.
  variant = {
    enabledPlugins = {
      "atlassian@claude-plugins-official" = work;
      "frontend-design@claude-plugins-official" = dev;
      "lua-lsp@claude-plugins-official" = dev;
      "playwright@claude-plugins-official" = dev;
      "railway@claude-plugins-official" = dev;
      "swift-lsp@claude-plugins-official" = dev;
      "typescript-lsp@claude-plugins-official" = dev;
    };
  }
  // lib.optionalAttrs (sessionStartEntries != [ ]) {
    hooks.SessionStart = sessionStartEntries;
  };

  variantJson = builtins.toJSON variant;

  jq = "${pkgs.jq}/bin/jq";

  # Per-capability jq clauses for the strip pass (only rendered when at least
  # one capability is off — mirrors `{{- if or (not $hippo) (not $agents) }}`).
  hippoClause = if hippo then "true" else ''(contains("/hippo-brain/") | not)'';
  agentsClause = if agents then "true" else ''(contains("/emit-routing-context.sh") | not)'';

  stripBlock = lib.optionalString (!hippo || !agents) ''
    # A SessionStart capability is off; remove any previously-injected hook for
    # it by command substring (recursive merge alone cannot delete keys absent
    # from the managed block). Only touches the off capability's own hook, so a
    # hippo-off / agents-on host keeps the routing hook and vice versa.
    merged="$(printf '%s\n' "$merged" | ${jq} '
      if (.hooks.SessionStart // null) then
        .hooks.SessionStart |= (
          map(.hooks |= map(select(
            (.command // "") | (
              ${hippoClause}
            ) and (
              ${agentsClause}
            )
          )))
          | map(select((.hooks // []) | length > 0))
        )
        | (if (.hooks.SessionStart // [] | length) == 0 then del(.hooks.SessionStart) else . end)
        | (if (.hooks // {} | keys | length) == 0 then del(.hooks) else . end)
      else . end')"
  '';
in
{
  # Runs after writeBoundary so the hook scripts + statusline symlinked by
  # dotfiles.nix already exist. Wrapped in a subshell terminated with `|| true`
  # so a merge failure warns but never fails the switch (parity with the
  # chezmoi fail_or_warn default; MCP_SYNC_STRICT had no analog here).
  home.activation.claudeSettingsMerge =
    lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      (
        set -u
        SETTINGS="$HOME/.claude/settings.json"
        BASE="$HOME/.dotfiles/home/.claude/settings-base.json"

        if [ ! -f "$BASE" ]; then
          echo "Warning: settings-base.json not found at $BASE; skipping Claude settings merge." >&2
          exit 0
        fi

        # base * variant = the full managed block.
        managed="$(${jq} -n \
          --slurpfile base "$BASE" \
          --argjson variant ${lib.escapeShellArg variantJson} \
          '$base[0] * $variant')" || { echo "Warning: could not build managed Claude settings." >&2; exit 0; }

        existing="{}"
        [ -f "$SETTINGS" ] && existing="$(cat "$SETTINGS")"
        [ -z "$existing" ] && existing="{}"

        # Recursive merge preserves live-only keys (theme, editorMode, ...).
        merged="$(printf '%s\n' "$existing" | ${jq} --argjson managed "$managed" '. * $managed')" \
          || { echo "Warning: Claude settings merge failed." >&2; exit 0; }

        # Seed cross-machine defaults for model + effort ONLY when unset, so an
        # in-tool override survives (kept out of the managed block on purpose).
        merged="$(printf '%s\n' "$merged" | ${jq} '
          (if .model == null then .model = "opusplan" else . end)
          | (if .effortLevel == null then .effortLevel = "xhigh" else . end)')"

        # Ensure ~/.cache/pre-commit stays sandbox-writable (append-if-absent so
        # /sandbox additions survive; allowWrite normalized to an array first).
        merged="$(printf '%s\n' "$merged" | ${jq} --arg p "$HOME/.cache/pre-commit" '
          (.sandbox.filesystem.allowWrite // [] | if type == "array" then . else [] end) as $aw
          | if ($aw | index($p)) then .
            else .sandbox.filesystem.allowWrite = ($aw + [$p]) end')"
      ${stripBlock}
        mkdir -p "$(dirname "$SETTINGS")"
        printf '%s\n' "$merged" > "$SETTINGS.tmp" && mv "$SETTINGS.tmp" "$SETTINGS"
      ) || true
    '';
}
