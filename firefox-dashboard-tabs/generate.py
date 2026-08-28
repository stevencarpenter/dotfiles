#!/usr/bin/env python3
"""Generate the Dashboard Tabs extension manifest from provisioned Grafana JSON.

Both Grafana instances provision their dashboards from JSON checked into their
own repositories, so the tab list is derived from those files rather than
maintained by hand. Adding a dashboard to either repo and re-running this
script is the whole update path.

Grafana resolves ``/d/<uid>`` to the canonical slugged URL, so the slug is
deliberately omitted: a renamed dashboard keeps working without regeneration.
"""

from __future__ import annotations

import json
import sys
from pathlib import Path
from typing import Any

HERE = Path(__file__).resolve().parent
SOURCES = HERE / "sources.json"
OUTPUT = HERE / "extension" / "dashboards.json"

# tabGroups.Color, per the WebExtensions schema. Note "grey", not "gray".
VALID_COLORS = frozenset(
    {"blue", "cyan", "grey", "green", "orange", "pink", "purple", "red", "yellow"}
)


def read_dashboard(path: Path) -> tuple[str, str] | None:
    """Extract the uid and title from one provisioned Grafana dashboard file.

    Args:
        path: Path to a dashboard JSON file. Both the bare dashboard object and
            the ``{"dashboard": {...}}`` export wrapper are accepted.

    Returns:
        A ``(uid, title)`` pair, or None if the file is not valid JSON or
        carries no uid (a datasource or provisioning file caught by the glob).
    """
    try:
        data: Any = json.loads(path.read_text())
    except (json.JSONDecodeError, OSError) as error:
        print(f"  skip {path.name}: {error}", file=sys.stderr)
        return None

    if not isinstance(data, dict):
        return None
    if isinstance(data.get("dashboard"), dict):
        data = data["dashboard"]

    uid = data.get("uid")
    title = data.get("title")
    if not uid or not title:
        return None
    return str(uid), str(title)


def build_group(spec: dict[str, Any]) -> dict[str, Any] | None:
    """Turn one source-group spec into the tab list the extension consumes.

    Args:
        spec: A group entry from sources.json, carrying the group title, color,
            Grafana base URL, dashboard directory, and an optional ``first``
            list of uids to pin to the front of the group.

    Returns:
        The group object to emit, or None if the dashboard directory is absent
        (expected on a machine that does not check out that repository).

    Raises:
        ValueError: If the group declares a color outside tabGroups.Color.
    """
    color = spec["color"]
    if color not in VALID_COLORS:
        raise ValueError(f"{spec['title']}: invalid color {color!r}")

    directory = Path(spec["dashboard_dir"]).expanduser()
    if not directory.is_dir():
        print(f"{spec['title']}: {directory} not found, skipping group")
        return None

    found = [
        result
        for path in sorted(directory.glob("*.json"))
        if (result := read_dashboard(path)) is not None
    ]

    # Pinned uids lead, in the order given; everything else follows by title.
    pinned: list[str] = spec.get("first", [])
    order = {uid: index for index, uid in enumerate(pinned)}
    found.sort(key=lambda item: (order.get(item[0], len(pinned)), item[1].lower()))

    base_url = spec["base_url"].rstrip("/")
    tabs = [{"title": title, "url": f"{base_url}/d/{uid}"} for uid, title in found]
    print(f"{spec['title']}: {len(tabs)} dashboards from {directory}")
    return {"title": spec["title"], "color": color, "tabs": tabs}


def main() -> int:
    """Write extension/dashboards.json from the configured sources.

    Returns:
        0 if at least one group was emitted, 1 otherwise.
    """
    sources = json.loads(SOURCES.read_text())
    groups = [
        group for spec in sources["groups"] if (group := build_group(spec)) is not None
    ]

    if not groups:
        print("no dashboard sources found, refusing to write", file=sys.stderr)
        return 1

    OUTPUT.write_text(json.dumps({"groups": groups}, indent=2) + "\n")
    total = sum(len(group["tabs"]) for group in groups)
    print(f"wrote {OUTPUT.relative_to(HERE)}: {len(groups)} groups, {total} tabs")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
