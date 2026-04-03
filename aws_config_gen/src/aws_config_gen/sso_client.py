"""SSO portal REST client."""

from __future__ import annotations

import json
import urllib.error
import urllib.request

from aws_config_gen.types import SSOAccount

_BASE = "https://portal.sso.{region}.amazonaws.com/assignment"


def _build_request(url: str, token: str) -> urllib.request.Request:
    return urllib.request.Request(url, headers={"x-amz-sso_bearer_token": token})


def list_accounts(token: str, region: str) -> list[SSOAccount]:
    """Fetch all SSO accounts visible to the bearer token, handling pagination."""
    accounts: list[SSOAccount] = []
    base_url = f"{_BASE.format(region=region)}/accounts?max_result=100"
    next_token: str | None = None

    while True:
        url = base_url if next_token is None else f"{base_url}&next_token={next_token}"
        req = _build_request(url, token)
        with urllib.request.urlopen(req) as resp:
            data = json.loads(resp.read())

        for acct in data["accountList"]:
            accounts.append(
                SSOAccount(
                    account_id=acct["accountId"],
                    account_name=acct["accountName"],
                    email_address=acct["emailAddress"],
                )
            )

        next_token = data.get("nextToken")
        if not next_token:
            break

    return accounts


def list_account_roles(token: str, region: str, account_id: str) -> list[str]:
    """Fetch all role names for a given account, handling pagination."""
    roles: list[str] = []
    base_url = (
        f"{_BASE.format(region=region)}/roles?account_id={account_id}&max_result=100"
    )
    next_token: str | None = None

    while True:
        url = base_url if next_token is None else f"{base_url}&next_token={next_token}"
        req = _build_request(url, token)
        with urllib.request.urlopen(req) as resp:
            data = json.loads(resp.read())

        for role in data["roleList"]:
            roles.append(role["roleName"])

        next_token = data.get("nextToken")
        if not next_token:
            break

    return roles
