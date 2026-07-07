"""Drift detection between deployed MCP configs and what a sync would write.

The drift definition is operational: a target is drifted exactly when running
``sync-mcp-configs`` would rewrite its file differently than it is on disk.
For the patch-style targets (codex ``config.toml`` and ``~/.claude.json``)
the render is a function of the current file contents, so keys those tools
own are never reported as drift — only the managed portions are.
"""

from __future__ import annotations

import difflib
import json
from dataclasses import dataclass
from pathlib import Path
from typing import Any

from mcp_sync.sync import (
    _build_targets,
    deep_merge,
    load_machine_config,
    load_master_config,
    log_error,
    log_info,
    log_success,
    render_claude_config,
    render_codex_config,
    render_gemini_config,
)

type JsonDict = dict[str, Any]


@dataclass(frozen=True, slots=True)
class DriftEntry:
    """One target's drift status.

    Attributes:
        name: Sync target name (e.g. ``"cursor"``, ``"codex"``, ``"claude"``).
        path: Deployed file the target writes.
        status: ``"clean"``, ``"drift"``, ``"missing"``, or ``"skipped"``.
        diff: Unified diff (deployed → expected); empty unless status is
            ``"drift"``.
    """

    name: str
    path: Path
    status: str
    diff: str = ""


def _unified_diff(deployed: str, expected: str, path: Path) -> str:
    return "".join(
        difflib.unified_diff(
            deployed.splitlines(keepends=True),
            expected.splitlines(keepends=True),
            fromfile=f"deployed: {path}",
            tofile="expected: what sync would write",
        )
    )


def _compare_text(name: str, path: Path, expected: str) -> DriftEntry:
    if not path.is_file():
        return DriftEntry(name, path, "missing")
    deployed = path.read_text(encoding="utf-8")
    if deployed == expected:
        return DriftEntry(name, path, "clean")
    return DriftEntry(name, path, "drift", _unified_diff(deployed, expected, path))


def drift_report(master: JsonDict, home: Path) -> list[DriftEntry]:
    """Compare every sync target's deployed file against a fresh render.

    Args:
        master: Merged master + machine-overlay MCP config.
        home: Home directory to inspect.

    Returns:
        One entry per target, in sync order.
    """
    entries: list[DriftEntry] = []

    for target in _build_targets(home):
        expected = (
            json.dumps(target.build(master, home=home), indent=2, sort_keys=True) + "\n"
        )
        entries.append(_compare_text(target.name, target.destination, expected))

    codex_path = home / ".codex" / "config.toml"
    codex_expected = render_codex_config(master, home)
    if codex_expected is None:
        entries.append(DriftEntry("codex", codex_path, "skipped"))
    else:
        entries.append(_compare_text("codex", codex_path, codex_expected))

    claude_path = home / ".claude.json"
    claude_expected = render_claude_config(master, home)
    if claude_expected is None:
        entries.append(DriftEntry("claude", claude_path, "skipped"))
    else:
        # ~/.claude.json is co-owned: Claude Code rewrites it with its own
        # serializer (literal UTF-8, no trailing newline), so byte comparison
        # would report permanent false drift. Compare content, and normalize
        # both sides through the same dump only to render a readable diff.
        deployed = json.loads(claude_path.read_text(encoding="utf-8"))
        if deployed == claude_expected:
            entries.append(DriftEntry("claude", claude_path, "clean"))
        else:
            deployed_text = json.dumps(deployed, indent=2, sort_keys=True) + "\n"
            expected_text = json.dumps(claude_expected, indent=2, sort_keys=True) + "\n"
            entries.append(
                DriftEntry(
                    "claude",
                    claude_path,
                    "drift",
                    _unified_diff(deployed_text, expected_text, claude_path),
                )
            )

    gemini_path = home / ".gemini" / "settings.json"
    gemini_expected = render_gemini_config(master, home)
    if gemini_expected is None:
        entries.append(DriftEntry("gemini", gemini_path, "skipped"))
    else:
        # ~/.gemini/settings.json is co-owned by Gemini CLI, same rationale as
        # ~/.claude.json above: compare content, not bytes.
        deployed = json.loads(gemini_path.read_text(encoding="utf-8"))
        if deployed == gemini_expected:
            entries.append(DriftEntry("gemini", gemini_path, "clean"))
        else:
            deployed_text = json.dumps(deployed, indent=2, sort_keys=True) + "\n"
            expected_text = json.dumps(gemini_expected, indent=2, sort_keys=True) + "\n"
            entries.append(
                DriftEntry(
                    "gemini",
                    gemini_path,
                    "drift",
                    _unified_diff(deployed_text, expected_text, gemini_path),
                )
            )

    return entries


def run_check(
    master_path: Path | None = None,
    home: Path | None = None,
    machine_config_path: Path | None = None,
) -> int:
    """Entry point for ``sync-mcp-configs --check``.

    Args:
        master_path: Master config location override.
        home: Home directory override.
        machine_config_path: Optional machine overlay merged over the master.

    Returns:
        ``0`` when every target is clean or skipped, ``1`` when any target
        is missing or drifted (or the master config is absent).
    """
    home_path = home or Path.home()
    master_config_path = (
        master_path or home_path / ".config" / "mcp" / "mcp-master.json"
    )
    if not master_config_path.is_file():
        log_error(f"Master config not found at {master_config_path}")
        return 1

    master = load_master_config(master_config_path)
    machine = load_machine_config(machine_config_path)
    if machine:
        log_info(f"Applying machine overlay: {machine_config_path}")
        master = deep_merge(master, machine)

    dirty = 0
    for entry in drift_report(master, home_path):
        if entry.status == "clean":
            log_success(f"{entry.name}: clean ({entry.path})")
        elif entry.status == "skipped":
            log_info(f"{entry.name}: skipped ({entry.path} not deployed)")
        elif entry.status == "missing":
            dirty += 1
            log_error(f"{entry.name}: missing — sync would create {entry.path}")
        else:
            dirty += 1
            log_error(f"{entry.name}: drifted from what sync would write")
            print(entry.diff, end="")

    if dirty:
        log_info(
            f"{dirty} target(s) drifted. Capture intentional edits with "
            "'sync-mcp-configs --capture <target>' or discard them by re-running "
            "the sync."
        )
        return 1
    log_success("All MCP targets match what a sync would write.")
    return 0
