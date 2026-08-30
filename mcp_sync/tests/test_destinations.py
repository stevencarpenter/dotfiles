"""sync_destinations is the single list of files run_sync writes."""

from __future__ import annotations

from pathlib import Path

from mcp_sync.sync import _build_targets, patch_specs, sync_destinations


def test_sync_destinations_match_run_sync_writers(tmp_path: Path) -> None:
    """The helper is _build_targets + codex + patch_specs, and nothing else.

    The verify scripts used to append a handwritten third special-case
    (``~/.config/.copilot/config.json``) that no writer produces. Copilot CLI
    is already in ``_build_targets`` as ``~/.copilot/mcp-config.json``.
    """
    dests = sync_destinations(tmp_path)
    assert [d.name for d in dests] == (
        [target.name for target in _build_targets(tmp_path)]
        + ["codex"]
        + [spec.name for spec in patch_specs(tmp_path)]
    )
    relative = {str(dest.path.relative_to(tmp_path)) for dest in dests}
    assert ".copilot/mcp-config.json" in relative
    assert ".codex/config.toml" in relative
    assert ".claude.json" in relative
    assert ".config/.copilot/config.json" not in relative


def test_sync_destinations_kinds(tmp_path: Path) -> None:
    """Wholesale targets are generated; codex and claude are patched in place."""
    kinds = {dest.name: dest.kind for dest in sync_destinations(tmp_path)}
    assert kinds["copilot-cli"] == "wholesale"
    assert kinds["codex"] == "patch"
    assert kinds["claude"] == "patch"
