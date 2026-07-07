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
from collections.abc import Callable
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


def _semantic_drift(
    name: str, path: Path, render: Callable[[], JsonDict | None]
) -> DriftEntry:
    """Drift for a co-owned JSON file, comparing content rather than bytes.

    The owning tool (Claude Code, Gemini CLI) rewrites the file with its own
    serializer — literal UTF-8, no trailing newline, its own key order — so a
    byte comparison would report permanent false drift. We parse both sides and
    compare the documents, normalizing through a shared dump only to render a
    readable diff. A deployed file that is unreadable or not valid JSON is
    reported as drift rather than crashing the whole check with a traceback.

    Args:
        name: Sync target name.
        path: Deployed co-owned file.
        render: Zero-arg renderer returning the expected document, or ``None``
            when the file is absent (the sync skips it). It reads ``path``
            internally, so it can also raise on a malformed deployed file.

    Returns:
        A ``DriftEntry`` with status ``"skipped"``, ``"clean"``, or ``"drift"``.
    """
    try:
        expected = render()
        if expected is None:
            return DriftEntry(name, path, "skipped")
        deployed = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        return DriftEntry(
            name,
            path,
            "drift",
            f"deployed file is unreadable or not valid JSON: {exc}\n",
        )
    if deployed == expected:
        return DriftEntry(name, path, "clean")
    deployed_text = json.dumps(deployed, indent=2, sort_keys=True) + "\n"
    expected_text = json.dumps(expected, indent=2, sort_keys=True) + "\n"
    return DriftEntry(
        name, path, "drift", _unified_diff(deployed_text, expected_text, path)
    )


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

    # Co-owned JSON targets: the owning tool rewrites the file with its own
    # serializer, so these compare content (not bytes) via _semantic_drift.
    for name, path, render in (
        ("claude", home / ".claude.json", lambda: render_claude_config(master, home)),
        (
            "gemini",
            home / ".gemini" / "settings.json",
            lambda: render_gemini_config(master, home),
        ),
    ):
        entries.append(_semantic_drift(name, path, render))

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
