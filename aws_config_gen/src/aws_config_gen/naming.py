"""Profile naming logic with overrides."""

from __future__ import annotations

import json
from collections import Counter
from pathlib import Path

from aws_config_gen.types import AccountRole, Overrides, ProfileEntry


def load_overrides(path: Path) -> Overrides:
    """Read overrides JSON and return an Overrides instance."""
    data = json.loads(path.read_text())
    return Overrides(
        sso_session=data["sso_session"],
        sso_start_url=data["sso_start_url"],
        sso_region=data["sso_region"],
        default_region=data["default_region"],
        account_names=data.get("account_names", {}),
        role_short_names=data.get("role_short_names", {}),
        skip=[tuple(pair) for pair in data.get("skip", [])],
    )


def build_profile_entries(
    roles: list[AccountRole],
    overrides: Overrides,
) -> list[ProfileEntry]:
    """Build sorted ProfileEntry list from roles and overrides."""
    # Determine which accounts have multiple roles
    role_counts = Counter(r.account.account_id for r in roles)

    entries: list[ProfileEntry] = []
    for role in roles:
        account_id = role.account.account_id
        account_name = overrides.account_names.get(
            account_id,
            role.account.account_name.lower().replace(" ", "-"),
        )
        role_short = overrides.role_short_names.get(
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
                sso_session=overrides.sso_session,
                account_id=account_id,
                role_name=role.role_name,
                region=overrides.default_region,
            )
        )

    return sorted(entries, key=lambda e: e.profile_name)
