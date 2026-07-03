"""SSO portal REST client."""

from __future__ import annotations

import json
import urllib.parse
import urllib.request
from typing import Any

from aws_config_gen.types import SSOAccount

_BASE = "https://portal.sso.{region}.amazonaws.com/assignment"

_TIMEOUT = 10  # seconds — prevent hanging when SSO endpoint is unreachable

_PAGE_SIZE = "100"  # max_result per SSO portal page request


def _build_request(url: str, token: str) -> urllib.request.Request:
    return urllib.request.Request(url, headers={"x-amz-sso_bearer_token": token})


def _fetch_all_pages(
    endpoint: str,
    token: str,
    key: str,
    extra_params: dict[str, str] | None = None,
) -> list[Any]:
    """Fetch every page of an SSO portal listing endpoint.

    Args:
        endpoint: Fully formatted endpoint URL, without a query string.
        token: SSO bearer token.
        key: Response key holding each page's items (e.g. ``"accountList"``).
        extra_params: Additional query parameters sent with each page request.

    Returns:
        Concatenated items from ``key`` across all pages.
    """
    items: list[Any] = []
    next_token: str | None = None

    while True:
        params: dict[str, str] = {**(extra_params or {}), "max_result": _PAGE_SIZE}
        if next_token is not None:
            params["next_token"] = next_token
        url = f"{endpoint}?{urllib.parse.urlencode(params)}"
        req = _build_request(url, token)
        with urllib.request.urlopen(req, timeout=_TIMEOUT) as resp:
            data = json.loads(resp.read())

        items.extend(data[key])

        next_token = data.get("nextToken")
        if not next_token:
            break

    return items


def list_accounts(token: str, region: str) -> list[SSOAccount]:
    """Fetch all SSO accounts visible to the bearer token, handling pagination.

    Args:
        token: SSO bearer token.
        region: SSO portal region.

    Returns:
        Every account visible to the token.
    """
    endpoint = f"{_BASE.format(region=region)}/accounts"
    return [
        SSOAccount(
            account_id=acct["accountId"],
            account_name=acct["accountName"],
            email_address=acct["emailAddress"],
        )
        for acct in _fetch_all_pages(endpoint, token, "accountList")
    ]


def list_account_roles(token: str, region: str, account_id: str) -> list[str]:
    """Fetch all role names for a given account, handling pagination.

    Args:
        token: SSO bearer token.
        region: SSO portal region.
        account_id: Account whose roles to list.

    Returns:
        Every role name available in the account.
    """
    endpoint = f"{_BASE.format(region=region)}/roles"
    return [
        role["roleName"]
        for role in _fetch_all_pages(
            endpoint, token, "roleList", {"account_id": account_id}
        )
    ]
