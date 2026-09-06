# Imperative sync hooks run at every switch as home.activation entries
# after writeBoundary (so home.file symlinks exist — no secret-decryption node
# is a dependant). Ports the retired chezmoi post-apply hooks:
#   mcpSync      <- run_after_sync-mcp.sh.tmpl
#   skillsSync    <- run_after_sync-skills.sh.tmpl
#   (shared preamble <- sync-hook-body.sh)
# mcp_sync has NO runtime deps and targets Python 3.14+, so activation calls
# its modules directly with the nix-store interpreter + explicit PYTHONPATH.
# Deliberately avoids uv editable installs: their .pth files embed the checkout
# path and break after a worktree move. Every entry is wrapped in
# `|| true` — failures warn but NEVER abort the switch (activation must not
# abort; MCP_SYNC_STRICT has no persistent analog).
# Overlay selection is by `identity` (personal/work/lab) at eval time, never
# by whatever file sorts first on disk.
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
    # --- op-render staleness nag (identity: personal) -----------------------
    # Reports only. The RENDER itself lives in `just sync`, not here, per the
    # repo's bucketing contract: activation is for offline + fast + idempotent
    # work, and rendering is neither offline nor unattended. It needs network
    # and an interactive 1Password approval that this context cannot get — the
    # activation PATH is a closed nix-store list with no /opt/homebrew (so a
    # bare `op` does not even resolve), and the desktop app authorizes CLI
    # access by process ancestry, which under `sudo darwin-rebuild` is not an
    # approved one. Attempting it here failed silently for weeks.
    #
    # What stays is the sentinel check: no `op`, no network, just a warning
    # when the last successful render is older than the threshold. That nag is
    # the only thing that ever surfaced the breakage, so it keeps earning its
    # place in the switch.
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

    # --- Skills fan-out (caps.skills) --------------------------------------
    # sync-skills is an entry point of the SAME mcp_sync project. Pass the
    # canonical repo root explicitly so personal skill links remain stable.
    #
    # No identity declares age secrets any more, so there is no decryption node
    # to order against — every identity uses the ordinary writeBoundary
    # dependency. An external wrapper that supplies its own work skills is
    # responsible for ordering its own hooks.
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
