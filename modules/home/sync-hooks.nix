# Imperative sync hooks (bucket B: offline / fast / idempotent working-tree work
# run at every switch as home.activation entries after writeBoundary).
#
# Ports the chezmoi post-apply hooks:
#   .chezmoiscripts/run_after_sync-mcp.sh.tmpl      -> mcpSync
#   .chezmoiscripts/run_after_sync-skills.sh.tmpl   -> skillsSync
#   .chezmoiscripts/run_after_sync-aws-config.sh.tmpl -> awsConfigGen
#   .chezmoiscripts/run_after_sync-agents.sh.tmpl   -> agentsInstall
#   .chezmoitemplates/sync-hook-body.sh             -> shared preamble below
#
# The vendored mcp_sync + aws_config_gen uv projects have NO runtime deps and
# target Python 3.14+, so `uv run` is fully offline when handed a nix-provided
# interpreter. Every entry:
#   - runs after writeBoundary (so home.file symlinks + agenix secrets exist),
#   - uses the nix-store uv (${pkgs.uv}) and exports UV_PYTHON so uv never
#     downloads an interpreter at switch time,
#   - is wrapped in a subshell ending `|| true` so a failure warns but NEVER
#     fails the switch (parity with the chezmoi fail_or_warn default; setting
#     MCP_SYNC_STRICT had no persistent analog — activation must not abort).
#
# Overlay selection is by `identity` (personal/work/lab), matching the overlay
# filenames, chosen at eval time — never by whatever file sorts first on disk.
{ config, pkgs, lib, caps, identity, ... }:

let
  uv = "${pkgs.uv}/bin/uv";
  # python314 must match the interpreter in modules/home/packages.nix and
  # satisfy the tools' requires-python >= 3.14; UV_PYTHON_DOWNLOADS=never turns
  # an interpreter miss into a warn instead of a silent network download.
  py = "${pkgs.python314}/bin/python3";

  repoRoot = "$HOME/.dotfiles";
  mcpSyncProject = "${repoRoot}/mcp_sync";
  awsProject = "${repoRoot}/aws_config_gen";
in
{
  home.activation = {
    # --- MCP fan-out (caps.mcp) --------------------------------------------
    mcpSync = lib.mkIf caps.mcp (
      lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        (
          set -u
          export UV_PYTHON="${py}"
          export UV_PYTHON_DOWNLOADS=never
          PROJECT="${mcpSyncProject}"
          OVERLAY="$HOME/.config/mcp/machine/${identity}.json"
          if [ ! -f "$PROJECT/pyproject.toml" ]; then
            echo "Warning: MCP sync project not found at $PROJECT; skipping." >&2
            exit 0
          fi
          cmd=( "${uv}" run --project "$PROJECT" sync-mcp-configs )
          [ -f "$OVERLAY" ] && cmd+=( --machine-config "$OVERLAY" )
          if ! "''${cmd[@]}"; then
            echo "Warning: MCP sync failed." >&2
            exit 0
          fi
        ) || true
      ''
    );

    # --- Skills fan-out (caps.skills) --------------------------------------
    # sync-skills is an entry point of the SAME mcp_sync project. It hardcodes
    # repo_root ~/.local/share/chezmoi for symlinking personal skills, so we
    # MUST pass --repo-root "$HOME/.dotfiles" or those symlinks dangle.
    #
    # ORDERING: the agenix-decrypted work skills (modules/home/secrets.nix)
    # must be written to ~/.claude/skills BEFORE this runs — sync-skills GCs
    # only entries it recorded, so as long as the decrypted dirs land first it
    # never removes them. agenix's secret installation runs before the
    # writeBoundary-ordered user activation entries; keep it that way if the
    # secrets module's ordering is ever revisited.
    skillsSync = lib.mkIf caps.skills (
      lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        (
          set -u
          export UV_PYTHON="${py}"
          export UV_PYTHON_DOWNLOADS=never
          PROJECT="${mcpSyncProject}"
          OVERLAY="$HOME/.config/skills/machine/${identity}.json"
          if [ ! -f "$PROJECT/pyproject.toml" ]; then
            echo "Warning: skill sync project not found at $PROJECT; skipping." >&2
            exit 0
          fi
          cmd=( "${uv}" run --project "$PROJECT" sync-skills --repo-root "${repoRoot}" )
          [ -f "$OVERLAY" ] && cmd+=( --machine-config "$OVERLAY" )
          if ! "''${cmd[@]}"; then
            echo "Warning: skill sync failed." >&2
            exit 0
          fi
        ) || true
      ''
    );

    # --- AWS SSO profile generation (caps.aws_sso) -------------------------
    awsConfigGen = lib.mkIf caps.aws_sso (
      lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        (
          set -u
          export UV_PYTHON="${py}"
          export UV_PYTHON_DOWNLOADS=never
          PROJECT="${awsProject}"
          if [ ! -f "$PROJECT/pyproject.toml" ]; then
            echo "Warning: AWS config gen project not found at $PROJECT; skipping." >&2
            exit 0
          fi
          if ! "${uv}" run --project "$PROJECT" aws-config-gen; then
            echo "Warning: AWS config gen failed." >&2
            exit 0
          fi
        ) || true
      ''
    );

    # --- Agent registry install (caps.agents) ------------------------------
    # Prefer the actively-edited working copy at ~/projects/agents; fall back to
    # the SSH-cloned external at ~/.local/share/agent-registry. Both are set up
    # by `just sync` (SSH clone); if neither exists we warn to run it. The
    # registry is a uv virtual project, so invoke its module like its justfile:
    # `python -m agent_registry.cli install` under --directory. Its own uv deps
    # are unknown, so on a cold cache this may resolve packages over the
    # network — acceptable (warn-never-fail); pre-warm via `just sync` if needed.
    agentsInstall = lib.mkIf caps.agents (
      lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        (
          set -u
          export UV_PYTHON="${py}"
          WORKING_COPY="$HOME/projects/agents"
          if [ -f "$WORKING_COPY/pyproject.toml" ]; then
            PROJECT="$WORKING_COPY"
          else
            PROJECT="$HOME/.local/share/agent-registry"
          fi
          if [ ! -f "$PROJECT/pyproject.toml" ]; then
            echo "Warning: agent registry not found at $PROJECT; run 'just sync' to clone it." >&2
            exit 0
          fi
          if ! "${uv}" run --directory "$PROJECT" python -m agent_registry.cli install; then
            echo "Warning: agent registry install failed." >&2
            exit 0
          fi

          # Refresh the SessionStart routing-context cache now that
          # ~/.claude/agents is current. Stdlib-only; best-effort — a stale
          # cache means slightly old routing hints, never a broken switch.
          ROUTING_SCRIPT="$PROJECT/tools/routing/generate_context.py"
          ROUTING_CACHE="$HOME/.cache/agent-routing/context.md"
          if [ -f "$ROUTING_SCRIPT" ]; then
            mkdir -p "$(dirname "$ROUTING_CACHE")"
            if "${py}" "$ROUTING_SCRIPT" > "$ROUTING_CACHE.tmp" 2>/dev/null; then
              mv "$ROUTING_CACHE.tmp" "$ROUTING_CACHE"
            else
              rm -f "$ROUTING_CACHE.tmp"
              echo "Warning: agent-routing context generation failed; keeping previous cache." >&2
            fi
          fi

          # Guard carried from the original hook: no installed Claude agent may
          # declare a tools: allowlist of ONLY built-in tools (that strips the
          # agent of MCP/skill access silently). Warn on violation.
          if ! violations="$("${py}" - "$HOME/.claude/agents" <<'PYEOF'
from pathlib import Path
import sys

root = Path(sys.argv[1])
builtins = {"Read", "Write", "Edit", "MultiEdit", "NotebookEdit",
            "Bash", "Glob", "Grep", "LS"}
violations = []
for path in sorted(root.glob("*.md")) if root.is_dir() else []:
    try:
        text = path.read_text(encoding="utf-8")
    except OSError as exc:
        violations.append(f"{path.name}: cannot read: {exc}")
        continue
    if not text.startswith("---\n"):
        continue
    frontmatter = text[4:].split("\n---\n", 1)[0]
    for line_number, line in enumerate(frontmatter.splitlines(), start=2):
        if not line.startswith("tools:"):
            continue
        tools = [p.strip() for p in line.split(":", 1)[1].split(",") if p.strip()]
        if tools and all(tool in builtins for tool in tools):
            violations.append(f"{path.name}:{line_number}: {line}")
if violations:
    print("\n".join(violations))
    sys.exit(1)
PYEOF
          )"; then
            echo "Warning: Claude agents contain built-in-only tools allowlists:" >&2
            echo "$violations" >&2
          fi
        ) || true
      ''
    );
  };
}
