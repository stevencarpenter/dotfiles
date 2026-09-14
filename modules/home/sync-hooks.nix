# Sync hooks run after writeBoundary; failures warn without aborting the switch.
# mcp_sync needs only Python 3.14+, so use the store interpreter and PYTHONPATH.
# Editable installs embed checkout paths that break after worktree moves.
# Select overlays by identity at evaluation time.
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
    # Check render age locally. Rendering belongs in `just sync`: activation
    # lacks Homebrew's op on PATH and interactive 1Password authorization.
    opRenderStaleCheck = lib.mkIf (identity == "personal") (
      lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        (
          set -u
          MANIFEST="$HOME/.config/op/render-manifest"
          RENDER="${repoRoot}/home/.local/bin/op-render"
          [ -f "$MANIFEST" ] || exit 0
          OP_RENDER_MANIFEST="$MANIFEST" "$RENDER" --warn-stale-only || true
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
            echo "Warning: no machine overlay at $OVERLAY; skipping MCP sync." >&2
            exit 0
          fi
          if ! "''${cmd[@]}"; then
            echo "Warning: MCP sync failed." >&2
            exit 0
          fi
        ) || true
      ''
    );

    # Pass the canonical repo root so personal skill links remain stable.
    # External wrappers must order their own skill hooks.
    skillsSync = lib.mkIf caps.skills (
      lib.hm.dag.entryAfter [ "writeBoundary" ] ''
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
            echo "Warning: no machine overlay at $OVERLAY; skipping skill sync." >&2
            exit 0
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
