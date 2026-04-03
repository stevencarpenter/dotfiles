"""INI config rendering and marker-based merge."""

from __future__ import annotations

import os
import re
from pathlib import Path

from aws_config_gen.types import GeneratorConfig, ProfileEntry

BEGIN_MARKER = "# BEGIN aws_config_gen managed block — do not edit"
END_MARKER = "# END aws_config_gen managed block"
SECTION_PATTERN = re.compile(r"^\[(?P<section>[^\]]+)\]\s*$")


def render_profiles(
        entries: list[ProfileEntry], generator_config: GeneratorConfig
) -> str:
    """Render the full managed block including markers and all stanzas."""
    lines: list[str] = [BEGIN_MARKER]

    # sso-session stanza
    lines.append(f"[sso-session {generator_config.sso_session}]")
    lines.append(f"sso_start_url = {generator_config.sso_start_url}")
    lines.append(f"sso_region = {generator_config.sso_region}")
    lines.append("sso_registration_scopes = sso:account:access")

    # profile stanzas
    for entry in entries:
        lines.append("")
        lines.append(f"[profile {entry.profile_name}]")
        lines.append(f"sso_session = {entry.sso_session}")
        lines.append(f"sso_account_id = {entry.account_id}")
        lines.append(f"sso_role_name = {entry.role_name}")
        lines.append(f"region = {entry.region}")

    lines.append(END_MARKER)
    return "\n".join(lines) + "\n"


def _extract_section_names(content: str) -> set[str]:
    """Return INI section names from the provided content."""
    section_names: set[str] = set()
    for line in content.splitlines():
        match = SECTION_PATTERN.match(line.strip())
        if match:
            section_names.add(match.group("section"))
    return section_names


def merge_config(existing_content: str, generated_block: str) -> str:
    """Merge a generated block into existing config content.

    If BEGIN/END markers are found, replace that range (inclusive).
    Otherwise, prepend the generated block before existing content.
    """
    existing_lines = existing_content.splitlines(keepends=True)

    begin_idx: int | None = None
    end_idx: int | None = None

    for i, line in enumerate(existing_lines):
        stripped = line.rstrip("\n\r")
        if stripped == BEGIN_MARKER:
            if begin_idx is not None:
                raise ValueError(
                    "Multiple managed block BEGIN markers found in config."
                )
            begin_idx = i
        elif stripped == END_MARKER:
            if begin_idx is None:
                raise ValueError(
                    "Managed block END marker found before BEGIN marker in config."
                )
            if end_idx is not None:
                raise ValueError("Multiple managed block END markers found in config.")
            end_idx = i

    if begin_idx is not None:
        if end_idx is None:
            raise ValueError(
                "Managed block BEGIN marker found without matching END marker."
            )
        before = existing_lines[:begin_idx]
        after = existing_lines[end_idx + 1 :]
        unmanaged_content = "".join(before) + "".join(after)
        merged_existing = "".join(before) + generated_block + "".join(after)
    else:
        unmanaged_content = existing_content
        # No markers found — prepend
        if existing_content:
            merged_existing = generated_block + "\n" + existing_content
        else:
            merged_existing = generated_block

    duplicate_sections = sorted(
        _extract_section_names(unmanaged_content).intersection(
            _extract_section_names(generated_block)
        )
    )
    if duplicate_sections:
        duplicates = ", ".join(duplicate_sections)
        raise ValueError(
            "Generated section names would duplicate existing AWS config section "
            f"names outside the managed block: {duplicates}"
        )

    return merged_existing


def write_config(config_path: Path, generated_block: str) -> None:
    """Atomically write the merged config to disk."""
    existing_content = ""
    existing_mode: int | None = None
    if config_path.exists():
        existing_content = config_path.read_text()
        existing_mode = config_path.stat().st_mode & 0o777

    merged = merge_config(existing_content, generated_block)

    config_path.parent.mkdir(parents=True, exist_ok=True)
    tmp_path = config_path.with_suffix(".tmp")
    tmp_path.write_text(merged)
    if existing_mode is not None:
        os.chmod(tmp_path, existing_mode)
    os.replace(tmp_path, config_path)
