"""INI config rendering and marker-based merge."""

from __future__ import annotations

import os
from pathlib import Path

from aws_config_gen.types import GeneratorConfig, ProfileEntry

BEGIN_MARKER = "# BEGIN aws_config_gen managed block — do not edit"
END_MARKER = "# END aws_config_gen managed block"


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
        return "".join(before) + generated_block + "".join(after)

    # No markers found — prepend
    if existing_content:
        return generated_block + "\n" + existing_content
    return generated_block


def write_config(config_path: Path, generated_block: str) -> None:
    """Atomically write the merged config to disk."""
    existing_content = ""
    if config_path.exists():
        existing_content = config_path.read_text()

    merged = merge_config(existing_content, generated_block)

    config_path.parent.mkdir(parents=True, exist_ok=True)
    tmp_path = config_path.with_suffix(".tmp")
    tmp_path.write_text(merged)
    os.replace(tmp_path, config_path)
