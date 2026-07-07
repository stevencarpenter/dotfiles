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
    PatchSpec,
    _build_targets,
    load_merged_master,
    log_error,
    log_info,
    log_success,
    patch_specs,
    render_codex_config,
    render_patch_with_source,
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


def _semantic_drift(spec: PatchSpec, master: JsonDict, home: Path) -> DriftEntry:
    """Drift for a co-owned JSON file, comparing content rather than bytes.

    The owning tool (Claude Code, Gemini CLI) rewrites the file with its own
    serializer — literal UTF-8, no trailing newline, its own key order — so a
    byte comparison would report permanent false drift. We parse the file once
    (via :func:`render_patch_with_source`, which returns both the deployed and
    expected documents) and compare the documents, normalizing through a
    shared dump only to render a readable diff. A deployed file that is
    unreadable or not valid JSON is reported as drift rather than crashing the
    whole check with a traceback.

    Args:
        spec: The patch target to check.
        master: Merged master + machine-overlay MCP config.
        home: Home directory to inspect.

    Returns:
        A ``DriftEntry`` with status ``"skipped"``, ``"clean"``, or ``"drift"``.
    """
    try:
        rendered = render_patch_with_source(spec, master, home)
    except (OSError, json.JSONDecodeError) as exc:
        return DriftEntry(
            spec.name,
            spec.path,
            "drift",
            f"deployed file is unreadable or not valid JSON: {exc}\n",
        )
    if rendered is None:
        return DriftEntry(spec.name, spec.path, "skipped")
    deployed, expected = rendered
    if deployed == expected:
        return DriftEntry(spec.name, spec.path, "clean")
    deployed_text = json.dumps(deployed, indent=2, sort_keys=True) + "\n"
    expected_text = json.dumps(expected, indent=2, sort_keys=True) + "\n"
    return DriftEntry(
        spec.name,
        spec.path,
        "drift",
        _unified_diff(deployed_text, expected_text, spec.path),
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
    for spec in patch_specs(home):
        entries.append(_semantic_drift(spec, master, home))

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
    master = load_merged_master(master_path, home_path, machine_config_path)
    if master is None:
        return 1

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
