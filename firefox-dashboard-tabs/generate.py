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
import os
import sys
import tempfile
from pathlib import Path
from typing import Any
from urllib.parse import urlparse

HERE = Path(__file__).resolve().parent
SOURCES = HERE / "sources.json"
OUTPUT = HERE / "extension" / "dashboards.json"

# tabGroups.Color, per the WebExtensions schema. Note "grey", not "gray".
VALID_COLORS = frozenset(
    {"blue", "cyan", "grey", "green", "orange", "pink", "purple", "red", "yellow"}
)
VALID_URL_SCHEMES = frozenset({"http", "https"})


class DashboardSourceError(ValueError):
    """Raised when a configured dashboard source cannot be read safely."""


def read_dashboard(path: Path) -> tuple[str, str] | None:
    """Extract the uid and title from one provisioned Grafana dashboard file.

    Args:
        path: Path to a dashboard JSON file. Both the bare dashboard object and
            the ``{"dashboard": {...}}`` export wrapper are accepted.

    Returns:
        A ``(uid, title)`` pair, or None if the file is valid JSON but is not a
        dashboard (for example, a datasource or provisioning file caught by
        the glob).

    Raises:
        DashboardSourceError: If the file cannot be read or contains malformed
            JSON or malformed dashboard identity fields.
    """
    try:
        data: Any = json.loads(path.read_text(encoding="utf-8"))
    except (json.JSONDecodeError, OSError, UnicodeError) as error:
        raise DashboardSourceError(f"cannot read dashboard {path}: {error}") from error

    if not isinstance(data, dict):
        return None
    if isinstance(data.get("dashboard"), dict):
        data = data["dashboard"]

    uid = data.get("uid")
    title = data.get("title")
    if uid is None and title is None:
        return None
    if not isinstance(uid, str) or not uid.strip():
        raise DashboardSourceError(f"dashboard {path} has an invalid uid")
    if not isinstance(title, str) or not title.strip():
        raise DashboardSourceError(f"dashboard {path} has an invalid title")
    return uid, title


def validate_sources(sources: dict[str, Any]) -> list[dict[str, Any]]:
    """Validate the source manifest before reading or replacing any output.

    Args:
        sources: Parsed sources.json contents.

    Returns:
        The validated group specifications.

    Raises:
        DashboardSourceError: If the manifest shape or group identities are
            invalid.
    """
    groups = sources.get("groups")
    if not isinstance(groups, list) or not groups:
        raise DashboardSourceError("sources.json must define a non-empty 'groups' list")

    validated: list[dict[str, Any]] = []
    seen_ids: set[str] = set()
    seen_titles: set[str] = set()
    for index, spec in enumerate(groups, start=1):
        if not isinstance(spec, dict):
            raise DashboardSourceError(f"group {index} must be an object")
        for key in ("id", "title", "color", "base_url", "dashboard_dir"):
            if not isinstance(spec.get(key), str) or not spec[key].strip():
                raise DashboardSourceError(
                    f"group {index} must define a non-empty string '{key}'"
                )

        group_id = spec["id"]
        title = spec["title"]
        if group_id in seen_ids:
            raise DashboardSourceError(f"duplicate group id {group_id!r}")
        if title in seen_titles:
            raise DashboardSourceError(f"duplicate group title {title!r}")
        seen_ids.add(group_id)
        seen_titles.add(title)

        if spec["color"] not in VALID_COLORS:
            raise DashboardSourceError(f"{title}: invalid color {spec['color']!r}")
        parsed_url = urlparse(spec["base_url"])
        if parsed_url.scheme not in VALID_URL_SCHEMES or not parsed_url.netloc:
            raise DashboardSourceError(f"{title}: base_url must be an http(s) origin")
        if parsed_url.query or parsed_url.fragment:
            raise DashboardSourceError(
                f"{title}: base_url must not contain a query or fragment"
            )

        pinned = spec.get("first", [])
        if not isinstance(pinned, list) or not all(
            isinstance(uid, str) for uid in pinned
        ):
            raise DashboardSourceError(f"{title}: first must be a list of string UIDs")
        if len(pinned) != len(set(pinned)):
            raise DashboardSourceError(f"{title}: first contains duplicate UIDs")
        validated.append(spec)
    return validated


def build_group(spec: dict[str, Any]) -> dict[str, Any]:
    """Turn one source-group spec into the tab list the extension consumes.

    Args:
        spec: A validated group entry from sources.json, carrying the group ID,
            title, color,
            Grafana base URL, dashboard directory, and an optional ``first``
            list of uids to pin to the front of the group.

    Returns:
        The group object to emit.

    Raises:
        DashboardSourceError: If the source directory is unavailable, a
            dashboard cannot be parsed, or UIDs are duplicated.
    """
    directory = Path(spec["dashboard_dir"]).expanduser()
    if not directory.is_dir():
        raise DashboardSourceError(f"{spec['title']}: {directory} not found")

    found: list[tuple[str, str]] = []
    paths_by_uid: dict[str, Path] = {}
    for path in sorted(directory.glob("*.json")):
        result = read_dashboard(path)
        if result is None:
            continue
        uid, title = result
        if uid in paths_by_uid:
            raise DashboardSourceError(
                f"{spec['title']}: duplicate dashboard UID {uid!r} in "
                f"{paths_by_uid[uid]} and {path}"
            )
        paths_by_uid[uid] = path
        found.append((uid, title))

    # Pinned uids lead, in the order given; everything else follows by title.
    pinned: list[str] = spec.get("first", [])
    unknown_pinned = [uid for uid in pinned if uid not in paths_by_uid]
    if unknown_pinned:
        raise DashboardSourceError(
            f"{spec['title']}: pinned UID(s) not found: {', '.join(unknown_pinned)}"
        )
    order = {uid: index for index, uid in enumerate(pinned)}
    found.sort(key=lambda item: (order.get(item[0], len(pinned)), item[1].lower()))

    base_url = spec["base_url"].rstrip("/")
    tabs = [{"title": title, "url": f"{base_url}/d/{uid}"} for uid, title in found]
    print(f"{spec['title']}: {len(tabs)} dashboards from {directory}")
    return {
        "id": spec["id"],
        "title": spec["title"],
        "color": spec["color"],
        "tabs": tabs,
    }


def write_output(data: dict[str, Any], output: Path) -> None:
    """Atomically replace a generated manifest after successful validation.

    Args:
        data: JSON-serializable generated manifest.
        output: Destination path.

    Raises:
        OSError: If the temporary file or replacement cannot be written.
    """
    output.parent.mkdir(parents=True, exist_ok=True)
    descriptor, temporary_name = tempfile.mkstemp(
        dir=output.parent, prefix=f".{output.name}.", suffix=".tmp"
    )
    temporary = Path(temporary_name)
    try:
        mode = output.stat().st_mode & 0o777 if output.exists() else 0o644
        os.chmod(temporary, mode)
        with os.fdopen(descriptor, "w", encoding="utf-8") as stream:
            json.dump(data, stream, indent=2)
            stream.write("\n")
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(temporary, output)
    except BaseException:
        temporary.unlink(missing_ok=True)
        raise


def main(sources_path: Path = SOURCES, output_path: Path = OUTPUT) -> int:
    """Write extension/dashboards.json from the configured sources.

    Returns:
        0 if at least one group was emitted, 1 otherwise.
    """
    try:
        sources: Any = json.loads(sources_path.read_text(encoding="utf-8"))
        if not isinstance(sources, dict):
            raise DashboardSourceError("sources.json must contain an object")
        specs = validate_sources(sources)
        groups = [build_group(spec) for spec in specs]
        manifest = {"groups": groups}
        write_output(manifest, output_path)
    except (ValueError, OSError) as error:
        print(f"error: {error}", file=sys.stderr)
        return 1

    total = sum(len(group["tabs"]) for group in groups)
    print(f"wrote {output_path}: {len(groups)} groups, {total} tabs")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
