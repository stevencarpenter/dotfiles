"""Tests for profile naming logic."""

from __future__ import annotations

import json

from aws_config_gen.naming import build_profile_entries, load_overrides
from aws_config_gen.types import AccountRole, Overrides


def test_account_name_override_applied(sample_overrides, sample_accounts):
    acme = sample_accounts[0]  # 111111111111 -> overridden to "acme"
    roles = [AccountRole(account=acme, role_name="ReadOnly")]

    entries = build_profile_entries(roles, sample_overrides)

    assert entries[0].profile_name == "acme"


def test_account_name_fallback(sample_overrides, sample_accounts):
    other = sample_accounts[2]  # 333333333333 -> "Other Account" -> "other-account"
    roles = [AccountRole(account=other, role_name="ReadOnly")]

    entries = build_profile_entries(roles, sample_overrides)

    assert entries[0].profile_name == "other-account"


def test_role_short_name_override_applied(sample_overrides, sample_accounts):
    acme = sample_accounts[0]
    roles = [
        AccountRole(account=acme, role_name="SRE-ClientEnvironments"),
        AccountRole(account=acme, role_name="Administrator-Access-SRE"),
    ]

    entries = build_profile_entries(roles, sample_overrides)

    names = {e.profile_name for e in entries}
    assert "acme-sre" in names
    assert "acme-admin" in names


def test_role_short_name_fallback(sample_overrides, sample_accounts):
    acme = sample_accounts[0]
    roles = [
        AccountRole(account=acme, role_name="ReadOnly"),
        AccountRole(account=acme, role_name="PowerUser"),
    ]

    entries = build_profile_entries(roles, sample_overrides)

    names = {e.profile_name for e in entries}
    assert "acme-readonly" in names
    assert "acme-poweruser" in names


def test_single_role_account_omits_suffix(sample_overrides, sample_accounts):
    dev = sample_accounts[1]  # 222222222222 -> overridden to "acme-dev"
    roles = [AccountRole(account=dev, role_name="ReadOnly")]

    entries = build_profile_entries(roles, sample_overrides)

    assert entries[0].profile_name == "acme-dev"


def test_multi_role_account_includes_suffix(sample_overrides, sample_accounts):
    other = sample_accounts[2]
    roles = [
        AccountRole(account=other, role_name="ReadOnly"),
        AccountRole(account=other, role_name="Admin"),
    ]

    entries = build_profile_entries(roles, sample_overrides)

    assert entries[0].profile_name == "other-account-admin"
    assert entries[1].profile_name == "other-account-readonly"


def test_alphabetical_sorting(sample_overrides, sample_accounts):
    roles = [
        AccountRole(account=sample_accounts[2], role_name="ReadOnly"),  # other-account
        AccountRole(account=sample_accounts[0], role_name="ReadOnly"),  # acme
        AccountRole(account=sample_accounts[1], role_name="ReadOnly"),  # acme-dev
    ]

    entries = build_profile_entries(roles, sample_overrides)

    assert [e.profile_name for e in entries] == ["acme", "acme-dev", "other-account"]


def test_profile_entry_fields(sample_overrides, sample_accounts):
    acme = sample_accounts[0]
    roles = [AccountRole(account=acme, role_name="ReadOnly")]

    entries = build_profile_entries(roles, sample_overrides)

    entry = entries[0]
    assert entry.sso_session == "lumin"
    assert entry.account_id == "111111111111"
    assert entry.role_name == "ReadOnly"
    assert entry.region == "us-west-2"


def test_load_overrides(tmp_path):
    data = {
        "sso_session": "test-session",
        "sso_start_url": "https://example.com/start",
        "sso_region": "us-east-1",
        "default_region": "us-east-1",
        "account_names": {"123": "myacct"},
        "role_short_names": {"AdminRole": "admin"},
        "skip": [["123", "AdminRole"]],
    }
    path = tmp_path / "overrides.json"
    path.write_text(json.dumps(data))

    result = load_overrides(path)

    assert isinstance(result, Overrides)
    assert result.sso_session == "test-session"
    assert result.sso_start_url == "https://example.com/start"
    assert result.sso_region == "us-east-1"
    assert result.default_region == "us-east-1"
    assert result.account_names == {"123": "myacct"}
    assert result.role_short_names == {"AdminRole": "admin"}
    assert result.skip == [("123", "AdminRole")]
