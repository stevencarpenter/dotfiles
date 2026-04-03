"""Profile naming logic with generator config."""

from __future__ import annotations

import json
from collections import Counter
from pathlib import Path

from aws_config_gen.types import AccountRole, GeneratorConfig, ProfileEntry


def _parse_skip_list(raw: list) -> list[tuple[str, str]]:
    """Validate and convert skip entries to (account_id, role_name) tuples."""
    result: list[tuple[str, str]] = []
    for i, pair in enumerate(raw):
        if len(pair) != 2:
            msg = f"skip entry {i} must be [account_id, role_name], got {pair!r}"
            raise ValueError(msg)
        result.append((pair[0], pair[1]))
    return result


def load_generator_config(path: Path) -> GeneratorConfig:
    """Read the generator config JSON and return a GeneratorConfig instance."""
    data = json.loads(path.read_text())
    return GeneratorConfig(
        sso_session=data["sso_session"],
        sso_start_url=data["sso_start_url"],
        sso_region=data["sso_region"],
        default_region=data["default_region"],
        account_names=data.get("account_names", {}),
        role_short_names=data.get("role_short_names", {}),
        skip=_parse_skip_list(data.get("skip", [])),
    )


def _validate_unique_profile_names(entries: list[ProfileEntry]) -> None:
    """Ensure generated profile names are unique."""
    duplicate_names = sorted(
        profile_name
        for profile_name, count in Counter(
            entry.profile_name for entry in entries
        ).items()
        if count > 1
    )
    if duplicate_names:
        duplicates = ", ".join(duplicate_names)
        msg = (
            f"Duplicate profile names generated: {duplicates}. "
            "Update account_names or role_short_names to keep names unique."
        )
        raise ValueError(msg)


def build_profile_entries(
    roles: list[AccountRole],
    generator_config: GeneratorConfig,
) -> list[ProfileEntry]:
    """Build sorted ProfileEntry list from roles and generator config."""
    # Determine which accounts have multiple roles
    role_counts = Counter(r.account.account_id for r in roles)

    entries: list[ProfileEntry] = []
    for role in roles:
        account_id = role.account.account_id
        account_name = generator_config.account_names.get(
            account_id,
            role.account.account_name.lower().replace(" ", "-"),
        )
        role_short = generator_config.role_short_names.get(
            role.role_name,
            role.role_name.lower(),
        )

        if role_counts[account_id] > 1:
            profile_name = f"{account_name}-{role_short}"
        else:
            profile_name = account_name

        entries.append(
            ProfileEntry(
                profile_name=profile_name,
                sso_session=generator_config.sso_session,
                account_id=account_id,
                role_name=role.role_name,
                region=generator_config.default_region,
            )
        )

    _validate_unique_profile_names(entries)
    return sorted(entries, key=lambda e: e.profile_name)
