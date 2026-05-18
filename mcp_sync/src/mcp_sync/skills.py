"""Claude Code skill synchronization: vendored + personal, machine-gated."""

from __future__ import annotations

import json
import re
from dataclasses import dataclass
from pathlib import Path
from typing import Any

type JsonDict = dict[str, Any]

_DURATION_UNITS = {"s": 1, "m": 60, "h": 3600, "d": 86400}
_DURATION_RE = re.compile(r"^(\d+)([smhd])$")

DEFAULT_REFRESH = "168h"
DEFAULT_REF = "main"


def parse_duration(text: str) -> int:
    """Parse a single-unit duration (e.g. '168h', '7d') into seconds.

    Args:
        text: A duration string of the form ``<integer><unit>`` where unit is
            one of ``s``, ``m``, ``h``, ``d``.

    Returns:
        The duration expressed in seconds.

    Raises:
        ValueError: If the string is not a recognized duration.
    """
    match = _DURATION_RE.match(text.strip())
    if not match:
        raise ValueError(f"Invalid duration: {text!r}")
    amount, unit = match.groups()
    return int(amount) * _DURATION_UNITS[unit]


def load_skills_manifest(path: Path) -> JsonDict:
    """Load and minimally validate the skills master manifest.

    Args:
        path: Path to ``skills-master.json``.

    Returns:
        The manifest with ``sources`` and ``skills`` keys guaranteed present.

    Raises:
        ValueError: If the JSON root is not an object.
    """
    with open(path, encoding="utf-8") as handle:
        data = json.load(handle)
    if not isinstance(data, dict):
        raise ValueError(f"Manifest root must be an object: {path}")
    data.setdefault("sources", {})
    data.setdefault("skills", {})
    return data


@dataclass(frozen=True, slots=True)
class ResolvedSkill:
    """A skill resolved from the manifest, ready to deploy.

    Attributes:
        name: Deployed directory name under ``~/.claude/skills/`` (manifest key).
        source_name: Name of the source this skill comes from.
        source_type: ``"git"`` or ``"local"``.
        subpath: For git sources, the skill directory within the cloned repo.
            For local sources, the path relative to the chezmoi repo root.
        mode: ``"copy"`` (git) or ``"symlink"`` (local).
    """

    name: str
    source_name: str
    source_type: str
    subpath: str
    mode: str


def resolve_skills(manifest: JsonDict) -> list[ResolvedSkill]:
    """Resolve the manifest's skill map into a deployable list.

    Args:
        manifest: The merged manifest (master config + machine overlay).

    Returns:
        Resolved skills sorted by name, excluding any disabled via an
        overlay ``false`` value.

    Raises:
        ValueError: If a skill references an unknown source, a git-sourced
            skill omits the required ``path``, or a source has an invalid type.
    """
    sources = manifest.get("sources", {})
    resolved: list[ResolvedSkill] = []
    for name, entry in sorted(manifest.get("skills", {}).items()):
        if entry is False:
            continue
        if not isinstance(entry, dict):
            raise ValueError(f"Skill {name!r} must be an object or false")
        source_name = entry.get("source")
        if source_name not in sources:
            raise ValueError(
                f"Skill {name!r} references unknown source {source_name!r}"
            )
        source = sources[source_name]
        source_type = source.get("type")
        if source_type == "git":
            subpath = entry.get("path")
            if not subpath:
                raise ValueError(f"Git-sourced skill {name!r} requires a 'path'")
            mode = "copy"
        elif source_type == "local":
            subpath = entry.get("path") or f"{source['path']}/{name}"
            mode = "symlink"
        else:
            raise ValueError(f"Source {source_name!r} has invalid type {source_type!r}")
        resolved.append(ResolvedSkill(name, source_name, source_type, subpath, mode))
    return resolved
