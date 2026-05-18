"""Claude Code skill synchronization: vendored + personal, machine-gated."""

from __future__ import annotations

import json
import re
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
