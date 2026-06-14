"""Codex ``config.toml`` settings-table rendering and ``[tui]`` enforcement."""

from __future__ import annotations

import copy
import datetime
import tomllib
from typing import Any, Callable

type JsonDict = dict[str, Any]
type LogFn = Callable[[str], None]


def toml_string(value: str) -> str:
    return '"' + value.replace("\\", "\\\\").replace('"', '\\"') + '"'


def toml_key(key: str) -> str:
    """Render a TOML key, quoting it unless it is a bare key.

    Args:
        key: The raw key string.

    Returns:
        The key rendered for use in a TOML key/value pair or table header.
    """
    if key and key.isascii() and all(c.isalnum() or c in "-_" for c in key):
        return key
    return toml_string(key)


def toml_value(value: Any) -> str:
    """Render a Python value parsed by ``tomllib`` back to TOML syntax.

    Args:
        value: The Python value to render.

    Returns:
        The TOML source text for the value.

    Raises:
        TypeError: If the value type has no TOML rendering here.
    """
    if isinstance(value, bool):
        return "true" if value else "false"
    if isinstance(value, str):
        return toml_string(value)
    if isinstance(value, int | float):
        return str(value)
    if isinstance(value, list):
        return "[" + ", ".join(toml_value(item) for item in value) + "]"
    if isinstance(value, datetime.datetime | datetime.date | datetime.time):
        return str(value)
    raise TypeError(f"Cannot render {type(value).__name__} as a TOML value")


def render_settings_table(name: str, table: JsonDict) -> str:
    """Render a settings table (with nested subtables) as TOML text.

    Args:
        name: Fully-qualified table name (e.g. ``tui``).
        table: Mapping of keys to scalar values or nested dicts.

    Returns:
        The TOML source text for the table, without a trailing newline.
    """
    lines = [f"[{name}]"]
    subtables: list[tuple[str, JsonDict]] = []
    for key, value in table.items():
        if isinstance(value, dict):
            subtables.append((f"{name}.{toml_key(key)}", value))
        else:
            lines.append(f"{toml_key(key)} = {toml_value(value)}")
    for sub_name, sub_table in subtables:
        lines.append("")
        lines.append(render_settings_table(sub_name, sub_table))
    return "\n".join(lines)


def strip_table(text: str, root: str) -> str:
    """Remove ``[root]`` and ``[root.*]`` tables, preserving everything else.

    Args:
        text: Existing ``config.toml`` contents.
        root: Top-level table name to remove (e.g. ``tui``).

    Returns:
        The config text with the named table sections removed.
    """
    kept: list[str] = []
    dropping = False
    for line in text.splitlines():
        stripped = line.strip()
        if stripped.startswith("[") and stripped.endswith("]"):
            header = stripped[1:-1].strip()
            dropping = header == root or header.startswith(f"{root}.")
        if not dropping:
            kept.append(line)
    return "\n".join(kept)


def _merge_dicts(existing: JsonDict, overlay: JsonDict) -> JsonDict:
    result = copy.deepcopy(existing)
    for key, value in overlay.items():
        if isinstance(value, dict) and isinstance(result.get(key), dict):
            result[key] = _merge_dicts(result[key], value)
        else:
            result[key] = copy.deepcopy(value)
    return result


def apply_tui_settings(
    base_text: str,
    template_text: str,
    *,
    log_info: LogFn | None = None,
) -> str:
    """Enforce the base template's ``[tui]`` keys on existing config text.

    Args:
        base_text: Existing ``config.toml`` contents.
        template_text: Rendered ``codex.base.toml`` template text.
        log_info: Optional info logger (e.g. ``mcp_sync.sync.log_info``).

    Returns:
        The config text with the merged ``[tui]`` table enforced, or the
        original text when nothing needs to change.
    """
    if not template_text:
        return base_text
    try:
        template_tui = tomllib.loads(template_text).get("tui")
    except tomllib.TOMLDecodeError:
        if log_info is not None:
            log_info("Skipping codex [tui] settings (template is not valid TOML)")
        return base_text
    if not isinstance(template_tui, dict) or not template_tui:
        return base_text

    try:
        existing_tui = tomllib.loads(base_text).get("tui")
    except tomllib.TOMLDecodeError:
        if log_info is not None:
            log_info(
                "Skipping codex [tui] settings (existing config is not valid TOML)"
            )
        return base_text
    if not isinstance(existing_tui, dict):
        existing_tui = {}

    merged_tui = _merge_dicts(existing_tui, template_tui)
    if merged_tui == existing_tui:
        return base_text

    stripped = strip_table(base_text, "tui")
    rendered = render_settings_table("tui", merged_tui)
    return stripped.rstrip() + "\n\n" + rendered + "\n"
