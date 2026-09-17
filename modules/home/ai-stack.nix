# Merge managed Claude settings into a writable file so in-tool edits survive.
# settings-base.json supplies shared values; variant supplies capability gates.
# External fragments override managed values; unknown live hooks are preserved.
# dotfiles.nix owns raw hooks and configs; sync-hooks.nix owns MCP and skills sync.
{
  config,
  pkgs,
  lib,
  caps,
  identity,
  ...
}:

let
  work = identity == "work";
  hippo = identity == "personal";
  inherit (caps) dev agents;

  home = config.home.homeDirectory;

  # Use absolute paths because directly invoked JSON commands may not expand ~.
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

  # Omit SessionStart when no managed hooks are enabled. The merge removes
  # disabled owned hooks while preserving unknown live hooks.
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
  # linkGeneration must create hook and fragment symlinks before this merge.
  # Failures warn without aborting the switch.
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

      # Merge settings.d fragments in lexical order, later files winning.
      # Apply them to managed settings before preserving live-only keys and hooks.
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

      # jq's recursive merge replaces arrays. Rebuild hooks with managed entries
      # followed by unknown live handlers. Remove owned handlers by equality or
      # command marker, including disabled and retired hooks; preserve non-command
      # handlers by object identity. Markers must cover every managed command family.
      # Tests extract the exact jq between the sentinels below.
      merged="$(printf '%s\n' "$existing" | ${jq} --argjson managed "$managed" '
        # hooks-merge-jq:begin
        [
          "/hippo-brain/",
          "/emit-routing-context.sh",
          "/agent-journal-stop.sh",
          "/agent-reap-subagent-stop.sh",
          "/agent-reap-session-end.sh",
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
      # Guard each transform: the outer || true suppresses inherited errexit.
      merged="$(printf '%s\n' "$merged" | ${jq} '
        (if .model == null then .model = "opusplan" else . end)
        | (if .effortLevel == null then .effortLevel = "xhigh" else . end)')" \
        || { echo "Warning: Claude defaults normalization failed; keeping existing settings." >&2; exit 0; }

      # Allow uvx cache and registry checkout writes without removing user-added
      # sandbox paths. Normalize allowWrite to an array before appending.
      merged="$(printf '%s\n' "$merged" | ${jq} \
        --arg p1 "$HOME/.cache/uv" \
        --arg p2 "$HOME/projects/agents" '
        reduce ($p1, $p2) as $p (.;
          (.sandbox.filesystem.allowWrite // [] | if type == "array" then . else [] end) as $aw
          | if ($aw | index($p)) then .
            else .sandbox.filesystem.allowWrite = ($aw + [$p]) end)')" \
        || { echo "Warning: Claude sandbox normalization failed; keeping existing settings." >&2; exit 0; }
      mkdir -p "$(dirname "$SETTINGS")"
      printf '%s\n' "$merged" > "$SETTINGS.tmp" && mv "$SETTINGS.tmp" "$SETTINGS"
    ) || true
  '';
}
