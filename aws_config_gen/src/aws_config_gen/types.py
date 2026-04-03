"""Data types for aws_config_gen."""

from __future__ import annotations

from dataclasses import dataclass


@dataclass(frozen=True)
class SSOAccount:
    account_id: str
    account_name: str
    email_address: str


@dataclass(frozen=True)
class AccountRole:
    account: SSOAccount
    role_name: str


@dataclass(frozen=True)
class ProfileEntry:
    profile_name: str
    sso_session: str
    account_id: str
    role_name: str
    region: str


@dataclass(frozen=True)
class Overrides:
    account_names: dict[str, str]
    role_short_names: dict[str, str]
    skip: list[tuple[str, str]]
    default_region: str
    sso_session: str
    sso_start_url: str
    sso_region: str
