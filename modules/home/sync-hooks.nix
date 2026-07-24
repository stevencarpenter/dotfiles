# Imperative sync hooks (bucket B: offline / fast / idempotent working-tree work
# run at every switch as home.activation entries after writeBoundary).
#
# Ports the chezmoi post-apply hooks:
#   .chezmoiscripts/run_after_sync-mcp.sh.tmpl      -> mcpSync
#   .chezmoiscripts/run_after_sync-skills.sh.tmpl   -> skillsSync
#   .chezmoitemplates/sync-hook-body.sh             -> shared preamble below
#
# The vendored mcp_sync project has NO runtime deps and
# targets Python 3.14+, so activation invokes its modules directly with the
# nix-provided interpreter and an explicit PYTHONPATH. This deliberately avoids
# uv editable environments: their .pth files embed the checkout path and break
# after a worktree move. Every entry:
#   - runs after writeBoundary (so home.file symlinks exist),
#   - depends on synchronous agenixDecrypt when consuming work secrets,
#   - uses the nix-store Python directly with user site-packages disabled,
#   - is wrapped in a subshell ending `|| true` so a failure warns but NEVER
#     fails the switch (parity with the chezmoi fail_or_warn default; setting
#     MCP_SYNC_STRICT had no persistent analog — activation must not abort).
#
# Overlay selection is by `identity` (personal/work/lab), matching the overlay
# filenames, chosen at eval time — never by whatever file sorts first on disk.
{
  config,
  pkgs,
  lib,
  caps,
  identity,
  ...
}:

let
  # python314 must match the interpreter in modules/home/packages.nix and
  # satisfy the vendored tools' requires-python >= 3.14.
  py = "${pkgs.python314}/bin/python3";

  repoRoot = "$HOME/.dotfiles";
  mcpSyncProject = "${repoRoot}/mcp_sync";
in
{
  home.activation = {
    # --- op-render: materialize op:// secret templates (identity: personal) --
    # Renders ~/.config/zsh/.personal.env and ~/.ssh/config from op:// templates
    # via the desktop app on m5 (no Connect). Fail-safe: a broken/absent op
    # leaves existing secret files byte-for-byte intact and NEVER fails the
    # switch. No-op where no manifest exists. See the WS1 migration plan.
    opRender = lib.mkIf (identity == "personal") (
      lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        (
          set -u
          MANIFEST="$HOME/.config/op/render-manifest"
          RENDER="${repoRoot}/home/.local/bin/op-render"
          [ -f "$MANIFEST" ] || exit 0
          OP_RENDER_MANIFEST="$MANIFEST" "$RENDER" \
            || echo "op-render: warned (secrets left intact)." >&2
        ) || true
      ''
    );

    # --- MCP fan-out (caps.mcp) --------------------------------------------
    mcpSync = lib.mkIf caps.mcp (
      lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        (
          set -u
          PROJECT="${mcpSyncProject}"
          export PYTHONNOUSERSITE=1
          export PYTHONPATH="$PROJECT/src"
          OVERLAY="$HOME/.config/mcp/machine/${identity}.json"
          if [ ! -f "$PROJECT/pyproject.toml" ]; then
            echo "Warning: MCP sync project not found at $PROJECT; skipping." >&2
            exit 0
          fi
          cmd=( "${py}" -m mcp_sync )
          if [ -f "$OVERLAY" ]; then
            cmd+=( --machine-config "$OVERLAY" )
          else
            echo "Warning: no machine overlay at $OVERLAY; syncing master config only." >&2
          fi
          if ! "''${cmd[@]}"; then
            echo "Warning: MCP sync failed." >&2
            exit 0
          fi
        ) || true
      ''
    );

    # --- Skills fan-out (caps.skills) --------------------------------------
    # sync-skills is an entry point of the SAME mcp_sync project. Pass the
    # canonical repo root explicitly so personal skill links remain stable.
    #
    # Work skills are agenix-decrypted, so work activation depends on the
    # synchronous agenixDecrypt node. Personal has no age secrets and retains
    # the ordinary writeBoundary dependency.
    skillsSync = lib.mkIf caps.skills (
      lib.hm.dag.entryAfter ([ "writeBoundary" ] ++ lib.optional (identity == "work") "agenixDecrypt") ''
        (
          set -u
          # sync-skills fetches pinned Git sources through subprocess. Home
          # Manager activation does not inherit the interactive user PATH, so
          # provide Git explicitly instead of relying on a new login shell.
          export PATH="${
            lib.makeBinPath [
              pkgs.git
              pkgs.openssh
            ]
          }:$PATH"
          PROJECT="${mcpSyncProject}"
          export PYTHONNOUSERSITE=1
          export PYTHONPATH="$PROJECT/src"
          OVERLAY="$HOME/.config/skills/machine/${identity}.json"
          if [ ! -f "$PROJECT/pyproject.toml" ]; then
            echo "Warning: skill sync project not found at $PROJECT; skipping." >&2
            exit 0
          fi
          cmd=( "${py}" -m mcp_sync.skills_cli --repo-root "${repoRoot}" )
          if [ -f "$OVERLAY" ]; then
            cmd+=( --machine-config "$OVERLAY" )
          else
            echo "Warning: no machine overlay at $OVERLAY; syncing master config only." >&2
          fi
          if ! "''${cmd[@]}"; then
            echo "Warning: skill sync failed." >&2
            exit 0
          fi
        ) || true
      ''
    );

  };
}
