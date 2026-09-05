"""Capture deployed-config drift back into the MCP overrides layer.

The inverse of the fan-out is lossy in general, but two properties of the
merge pipeline make capture exact for the common cases:

* Every target applies ``~/.config/mcp/overrides/<key>.json`` as the final
  deep-merge layer, so a delta recorded verbatim in output coordinates
  replays identically on the next sync.
* Deep-merge cannot express deletions, but the pre-transform enablement gate
  can: a server removed by hand becomes ``servers.<name>.enabled: false`` in
  the override, which every transform filters out.

Only deletions of non-server keys are genuinely uncapturable; those are
reported so they can be fixed in the master config instead.
"""

from __future__ import annotations

import copy
import json
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any

from mcp_sync.sync import (
    _build_targets,
    _load_json_object,
    _patch_owned_config,
    _write_json,
    deep_merge,
    load_merged_master,
    log_error,
    log_info,
    log_success,
    patch_specs,
    render_patch_with_source,
)

type JsonDict = dict[str, Any]

# Output keys that hold per-server entries across the target formats
# (identity → "servers", mcpServers-style → "mcpServers", opencode → "mcp").
_SERVER_CONTAINERS = frozenset({"servers", "mcpServers", "mcp"})


@dataclass(frozen=True, slots=True)
class CaptureResult:
    """Outcome of one capture run.

    Attributes:
        name: Target the capture ran against.
        override_path: Override file the delta was merged into.
        delta: The override fragment derived from the drift (empty when the
            target was already clean).
        uncapturable: Dotted paths of deletions the override layer cannot
            express.
        verified: True when a rebuild with the new override reproduces the
            deployed file's content.
        residual: Dotted paths that a rebuild still cannot reproduce (e.g. a
            hand-re-added retired server name, or an ``enabled: false`` on an
            identity-format target that the sync gate strips). Populated only
            when ``verified`` is False, to explain *what* did not round-trip
            instead of a generic "residual drift" message.
    """

    name: str
    override_path: Path
    delta: JsonDict = field(default_factory=dict)
    uncapturable: list[str] = field(default_factory=list)
    verified: bool = False
    residual: list[str] = field(default_factory=list)


def _diff_objects(
    expected: JsonDict, deployed: JsonDict, path: tuple[str, ...] = ()
) -> tuple[JsonDict, list[tuple[str, ...]]]:
    """Compute the override delta turning ``expected`` into ``deployed``.

    Args:
        expected: What a sync would write.
        deployed: What is actually on disk.
        path: Key path of the current recursion level (for deletion reports).

    Returns:
        A ``(delta, deletions)`` pair: ``delta`` is the minimal nested dict
        that deep-merges over ``expected`` to yield the changed/added parts
        of ``deployed``; ``deletions`` lists key paths present in
        ``expected`` but absent from ``deployed``.
    """
    delta: JsonDict = {}
    deletions: list[tuple[str, ...]] = []
    for key, dep_val in deployed.items():
        if key not in expected:
            delta[key] = copy.deepcopy(dep_val)
        elif isinstance(dep_val, dict) and isinstance(expected[key], dict):
            sub_delta, sub_deletions = _diff_objects(
                expected[key], dep_val, (*path, key)
            )
            if sub_delta:
                delta[key] = sub_delta
            deletions.extend(sub_deletions)
        elif dep_val != expected[key]:
            delta[key] = copy.deepcopy(dep_val)
    for key in expected:
        if key not in deployed:
            deletions.append((*path, key))
    return delta, deletions


def _leaf_paths(delta: JsonDict, prefix: tuple[str, ...] = ()) -> list[str]:
    """Flatten a nested delta into dotted leaf paths (for residual reporting)."""
    paths: list[str] = []
    for key, value in delta.items():
        if isinstance(value, dict) and value:
            paths.extend(_leaf_paths(value, (*prefix, key)))
        else:
            paths.append(".".join((*prefix, key)))
    return paths


def _expected_and_deployed(
    name: str, master: JsonDict, home: Path
) -> tuple[JsonDict, JsonDict, str, Any]:
    """Resolve a target name to its expected/deployed docs and rebuilder.

    The patch-managed targets come from :func:`mcp_sync.sync.patch_specs`, the
    same registry the sync and drift check dispatch on.

    Args:
        name: Sync target name (a ``SyncTarget`` name or a patch target).
        master: Merged master + machine-overlay MCP config.
        home: Home directory to inspect.

    Returns:
        ``(expected, deployed, override_key, rebuild)`` where ``expected`` is
        the current render, ``deployed`` is the parsed on-disk document (read
        exactly once here), and ``rebuild`` re-renders the expected doc via
        the identical patch/build code path — re-reading overrides from disk,
        so a just-written override is picked up — for post-write verification.

    Raises:
        ValueError: For ``"codex"`` (patch-managed TOML; not capturable), for a
            patch target whose deployed file is absent, for a ``SyncTarget``
            whose destination is absent, or for an unknown target name.
    """
    if name == "codex":
        raise ValueError(
            "codex is patch-managed TOML: hand edits outside the managed block "
            "already survive syncs, and edits inside it must go to the master "
            "config or a machine overlay — capture cannot express them."
        )

    for spec in patch_specs(home):
        if spec.name == name:
            rendered = render_patch_with_source(spec, master, home)
            if rendered is None:
                raise ValueError(f"{spec.path} does not exist; nothing to capture.")
            deployed, expected = rendered

            def rebuild(deployed: JsonDict = deployed, spec=spec) -> JsonDict:
                # Same patch code path as `expected`, re-reading overrides from
                # disk; the deployed doc — which capture never writes — is
                # re-patched from the parse above instead of a third file read.
                return _patch_owned_config(
                    master,
                    home,
                    copy.deepcopy(deployed),
                    override_key=spec.override_key,
                    server_map=spec.server_map,
                )

            return expected, deployed, spec.name, rebuild

    for target in _build_targets(home):
        if target.name == name:
            if not target.destination.is_file():
                raise ValueError(
                    f"{target.destination} does not exist; run a sync first."
                )
            return (
                target.build(master, home=home),
                _load_json_object(target.destination),
                target.override_key or target.name,
                lambda t=target: t.build(master, home=home),
            )
    known = ", ".join(t.name for t in _build_targets(home))
    patch_names = ", ".join(spec.name for spec in patch_specs(home))
    raise ValueError(f"Unknown capture target {name!r}. Known: {known}, {patch_names}.")


def capture_target(name: str, master: JsonDict, home: Path) -> CaptureResult:
    """Capture one target's drift into its override file.

    Args:
        name: Sync target name (a ``SyncTarget`` name or ``"claude"``).
        master: Merged master + machine-overlay MCP config.
        home: Home directory to inspect.

    Returns:
        The capture outcome.

    Raises:
        ValueError: For unknown targets, for ``"codex"`` (patch-managed; not
            capturable), or when the target's deployed file is absent.
    """
    expected, deployed, override_key, rebuild = _expected_and_deployed(
        name, master, home
    )
    override_path = home / ".config" / "mcp" / "overrides" / f"{override_key}.json"

    delta, deletions = _diff_objects(expected, deployed)

    candidate = copy.deepcopy(delta)
    uncapturable: list[str] = []
    for deletion in deletions:
        if len(deletion) == 2 and deletion[0] in _SERVER_CONTAINERS:
            server = candidate.setdefault("servers", {}).setdefault(deletion[1], {})
            server["enabled"] = False
        else:
            uncapturable.append(".".join(deletion))

    if not candidate and not uncapturable:
        return CaptureResult(name, override_path, verified=True)

    if candidate:
        existing: JsonDict = {}
        if override_path.is_file():
            try:
                existing = _load_json_object(override_path)
            except ValueError:
                log_info(f"Replacing override with non-object root: {override_path}")
        _write_json(override_path, deep_merge(existing, candidate))

    rebuilt = rebuild()
    verified = rebuilt == deployed
    residual: list[str] = []
    if not verified:
        # Report exactly what a rebuild still can't reproduce, rather than a
        # generic "residual drift" — e.g. a re-added retired server name, or an
        # enablement flag the sync gate strips, is unrepresentable in the
        # override layer and shows up here.
        residual_delta, residual_deletions = _diff_objects(rebuilt, deployed)
        residual = _leaf_paths(residual_delta) + [
            ".".join(deletion) for deletion in residual_deletions
        ]
    return CaptureResult(
        name, override_path, candidate, uncapturable, verified, residual
    )


def run_capture(
    name: str,
    master_path: Path | None = None,
    home: Path | None = None,
    machine_config_path: Path | None = None,
) -> int:
    """Entry point for ``sync-mcp-configs --capture <target>``.

    Args:
        name: Sync target name to capture.
        master_path: Master config location override.
        home: Home directory override.
        machine_config_path: Optional machine overlay merged over the master.

    Returns:
        ``0`` on a clean or fully captured target, ``1`` on errors or when
        part of the drift could not be captured.
    """
    home_path = home or Path.home()
    try:
        master = load_merged_master(master_path, home_path, machine_config_path)
    except (FileNotFoundError, OSError, ValueError) as exc:
        log_error(str(exc))
        return 1
    if master is None:
        return 1

    try:
        result = capture_target(name, master, home_path)
    except json.JSONDecodeError as exc:
        # JSONDecodeError subclasses ValueError, so this must precede the
        # ValueError arm to give a targeted message instead of a raw parse dump.
        log_error(
            f"{name}: deployed config is not valid JSON ({exc}); nothing captured."
        )
        return 1
    except ValueError as exc:
        log_error(str(exc))
        return 1

    if not result.delta and not result.uncapturable:
        log_success(f"{name}: no drift to capture.")
        return 0

    if result.delta:
        log_success(f"Captured drift into {result.override_path}")
        log_info(
            "The override replays on every future sync. To distribute it, add "
            "it to the dotfiles repo (dot_config/mcp/overrides/)."
        )
    for path in result.uncapturable:
        log_error(
            f"Cannot capture deletion of {path} — the override layer cannot "
            "delete keys. Change the master config or base template instead."
        )
    if not result.verified:
        detail = (
            f" The following could not be reproduced: {', '.join(result.residual)}."
            if result.residual
            else ""
        )
        log_error(
            "A rebuild with the new override does not fully reproduce the "
            "deployed file; residual drift remains." + detail
        )
        log_info(
            "This usually means a retired server name or an enablement flag the "
            "sync gate strips — such edits belong in the master config, not an "
            "override."
        )
        return 1
    log_info(
        "Content round-trips; formatting may still differ until the next "
        "sync rewrites the file."
    )
    return 0
