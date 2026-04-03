"""Account and role discovery orchestration."""

from __future__ import annotations

from pathlib import Path

from aws_config_gen.sso_client import list_account_roles, list_accounts
from aws_config_gen.sso_token import load_sso_token
from aws_config_gen.types import AccountRole


def discover_all_roles(
    session_name: str,
    region: str,
    skip: list[tuple[str, str]],
    cache_dir: Path | None = None,
) -> list[AccountRole]:
    """Discover every account-role pair visible to the SSO session.

    Loads the cached bearer token, enumerates all accounts, fetches roles
    for each account, and returns a flat list of AccountRole objects with
    any (account_id, role_name) pairs in *skip* filtered out.
    """
    token = load_sso_token(session_name, cache_dir)
    accounts = list_accounts(token, region)
    skip_set = set(skip)

    roles: list[AccountRole] = []
    for account in accounts:
        for role_name in list_account_roles(token, region, account.account_id):
            if (account.account_id, role_name) not in skip_set:
                roles.append(AccountRole(account=account, role_name=role_name))

    return roles
