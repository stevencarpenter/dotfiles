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
#                                       existing * managed with preserve-unknown
#                                       hook semantics (foreign self-registered
#                                       hooks survive; managed/marker/capability-
#                                       off hooks are re-added or swept), seed
#                                       model/effort, ensure ~/.cache/pre-commit +
#                                       ~/projects/agents sandbox-write.
#
# BOUNDARY: this module owns ONLY the settings.json merge. The raw dotfiles it
# depends on are declared elsewhere:
#   - ~/.claude/hooks/*, ~/.claude/statusline-command.sh  -> modules/home/dotfiles.nix
#   - ~/.config/mcp/machine/<identity>.json (overlay)     -> modules/home/dotfiles.nix (identity-gated)
#   - the MCP/skills fan-out that consumes those overlays -> modules/home/sync-hooks.nix
#
# ~/.claude/skills interplay note: in THIS repo there is now exactly one writer
# of ~/.claude/skills/ — the sync-skills activation (modules/home/sync-hooks.nix).
# The former second writer (age-decrypted work skills) is gone with the age
# bridge. An external wrapper may add its own writer via extraHomeModules;
# sync-skills only GCs entries it recorded, so a wrapper's skills survive
# regardless of ordering. This module does not touch ~/.claude/skills.
{
  config,
  pkgs,
  lib,
  caps,
  identity,
  ...
}:

let
  # Resolve the template's four conditionals from the host row.
  work = identity == "work"; # $work = hasPrefix "work" .machine
  hippo = identity == "personal"; # $hippo = hasPrefix "personal" .machine
  # $dev/$agents = the corresponding machine capability.
  inherit (caps) dev agents;

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
in
{
  # Runs after writeBoundary so the hook scripts + statusline symlinked by
  # dotfiles.nix already exist. Wrapped in a subshell terminated with `|| true`
  # so a merge failure warns but never fails the switch (parity with the
  # chezmoi fail_or_warn default; MCP_SYNC_STRICT had no analog here).
  # entryAfter "linkGeneration", NOT "writeBoundary": linkGeneration is itself a
  # writeBoundary dependant, so ordering between the two was never defined and
  # this entry in fact sorted BEFORE it. Same latent defect that made the Codex
  # AGENTS.d seam read empty — here it would silently skip every
  # ~/.claude/settings.d fragment an overlay had dropped, which is a LOCKED
  # contract. No live impact yet only because that seam has no fragments.
  home.activation.claudeSettingsMerge = lib.hm.dag.entryAfter [ "linkGeneration" ] ''
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

      # Fragment seam (LOCKED contract): external overlay repos drop JSON
      # files into ~/.claude/settings.d/; each deep-merges over the managed
      # block in lexical order (later file wins). Merging here — BEFORE the
      # existing-settings merge — keeps live-only keys and the hooks pass
      # below out of the fragment path.
      for frag in "$HOME"/.claude/settings.d/*.json; do
        [ -f "$frag" ] || continue
        if tmp="$(printf '%s\n' "$managed" | ${jq} --slurpfile f "$frag" '. * $f[0]')"; then
          managed="$tmp"
        else
          echo "Warning: bad settings fragment $frag; skipping." >&2
        fi
      done

      existing="{}"
      [ -f "$SETTINGS" ] && existing="$(cat "$SETTINGS")"
      [ -z "$existing" ] && existing="{}"

      # Recursive merge (existing * managed) preserves live-only keys (theme,
      # editorMode, …) but replaces arrays WHOLESALE — which would wipe hooks a
      # tool self-registers into the live file (e.g. an agent-state hook) under
      # ANY event. Preserve-unknown semantics (ported from the pre-nix
      # dot_claude/modify_settings.json.tmpl, PR #120): after the merge, rebuild
      # .hooks so each event = managed entries first, then live hooks we don't
      # own re-appended. A live handler is "ours" (dropped — $managed already
      # re-added the current one) when it is byte-identical to a managed handler
      # OR its command matches an ownership marker. Markers sweep stale spellings,
      # capability-off hooks, and retired chezmoi hooks that are no longer present
      # in the managed block. Non-command handler types are preserved by object
      # identity instead of being discarded for lacking `.command`.
      # $owned_command_markers MUST cover every command family managed here or in
      # settings-base.json, plus deliberate migration tombstones. The program is
      # fenced by sentinels so scripts/test-claude-hooks-preservation.sh extracts
      # and tests this exact jq (single source of truth).
      merged="$(printf '%s\n' "$existing" | ${jq} --argjson managed "$managed" '
        # hooks-merge-jq:begin
        [
          "/hippo-brain/",
          "/emit-routing-context.sh",
          "/agent-journal-stop.sh",
          "/wt-create.sh",
          "/wt-remove.sh",
          "encrypted_* via",
          "chezmoi execute-template"
        ] as $owned_command_markers
        | . as $live
        | ($live * $managed)
        | (($live.hooks // {}) | if type == "object" then . else {} end) as $lh
        | if ($lh | keys | length) > 0 then
            .hooks = (
              reduce ($lh | keys[]) as $k (.hooks // {};
                (($managed.hooks[$k] // []) ) as $m
                | ($m | [.[].hooks[]?]) as $managed_handlers
                | .[$k] = ($m + (
                    ($lh[$k] | if type == "array" then . else [] end)
                    | map(select(type == "object"))
                    | map(.hooks = ((.hooks // []) | map(select(
                        . as $handler
                        | (($managed_handlers | index($handler)) == null)
                          and (
                            ($handler.command? // null) as $command
                            | if ($command | type) == "string" then
                                (($owned_command_markers
                                  | map(. as $marker | $command | contains($marker))
                                  | any) | not)
                              else true
                              end
                          )
                      ))))
                    | map(select((.hooks | length) > 0))
                  ))
              )
              | with_entries(select((.value | length) > 0))
            )
            | (if ((.hooks // {}) | keys | length) == 0 then del(.hooks) else . end)
          else . end
        # hooks-merge-jq:end
        ')" \
        || { echo "Warning: Claude settings merge failed." >&2; exit 0; }

      # Seed cross-machine defaults for model + effort ONLY when unset, so an
      # in-tool override survives (kept out of the managed block on purpose).
      merged="$(printf '%s\n' "$merged" | ${jq} '
        (if .model == null then .model = "opusplan" else . end)
        | (if .effortLevel == null then .effortLevel = "xhigh" else . end)')"

      # Ensure ~/.cache/pre-commit stays sandbox-writable, and ~/projects/agents
      # too so jj/uv/git writes under the agents registry working copy run inside
      # the sandbox (append-if-absent so /sandbox additions survive; allowWrite
      # normalized to an array first).
      merged="$(printf '%s\n' "$merged" | ${jq} \
        --arg p1 "$HOME/.cache/pre-commit" \
        --arg p2 "$HOME/projects/agents" '
        reduce ($p1, $p2) as $p (.;
          (.sandbox.filesystem.allowWrite // [] | if type == "array" then . else [] end) as $aw
          | if ($aw | index($p)) then .
            else .sandbox.filesystem.allowWrite = ($aw + [$p]) end)')"
      mkdir -p "$(dirname "$SETTINGS")"
      printf '%s\n' "$merged" > "$SETTINGS.tmp" && mv "$SETTINGS.tmp" "$SETTINGS"
    ) || true
  '';
}
