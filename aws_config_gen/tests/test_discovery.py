"""Tests for account and role discovery orchestration."""

from __future__ import annotations

import pytest
from pathlib import Path
from unittest.mock import patch

from aws_config_gen.discovery import discover_all_roles
from aws_config_gen.types import SSOAccount


@pytest.fixture
def _mock_token():
    with patch("aws_config_gen.discovery.load_sso_token", return_value="tok") as m:
        yield m


@pytest.fixture
def _two_accounts():
    accounts = [
        SSOAccount("111", "Acme", "a@e.com"),
        SSOAccount("222", "Beta", "b@e.com"),
    ]
    with patch("aws_config_gen.discovery.list_accounts", return_value=accounts) as m:
        yield m


@pytest.fixture
def _roles_per_account():
    def _roles(_tok, _region, acct_id):
        mapping = {"111": ["Admin", "ReadOnly"], "222": ["Developer"]}
        return mapping.get(acct_id, [])

    with patch("aws_config_gen.discovery.list_account_roles", side_effect=_roles) as m:
        yield m


class TestDiscoverAllRoles:
    @pytest.mark.usefixtures("_mock_token", "_two_accounts", "_roles_per_account")
    def test_returns_all_roles(self):
        result = discover_all_roles("sess", "us-east-1", [])
        assert len(result) == 3
        role_names = [r.role_name for r in result]
        assert "Admin" in role_names
        assert "ReadOnly" in role_names
        assert "Developer" in role_names

    @pytest.mark.usefixtures("_mock_token", "_two_accounts", "_roles_per_account")
    def test_skip_filters_matching_pairs(self):
        result = discover_all_roles("sess", "us-east-1", [("111", "Admin")])
        assert len(result) == 2
        role_names = [r.role_name for r in result]
        assert "Admin" not in role_names
        assert "ReadOnly" in role_names
        assert "Developer" in role_names

    @pytest.mark.usefixtures("_mock_token", "_two_accounts", "_roles_per_account")
    def test_skip_ignores_non_matching_pairs(self):
        result = discover_all_roles("sess", "us-east-1", [("999", "Admin")])
        assert len(result) == 3

    @pytest.mark.usefixtures("_mock_token", "_two_accounts", "_roles_per_account")
    def test_skip_multiple_pairs(self):
        result = discover_all_roles(
            "sess", "us-east-1", [("111", "Admin"), ("222", "Developer")]
        )
        assert len(result) == 1
        assert result[0].role_name == "ReadOnly"

    @pytest.mark.usefixtures("_mock_token")
    def test_empty_accounts(self):
        with patch("aws_config_gen.discovery.list_accounts", return_value=[]):
            result = discover_all_roles("sess", "us-east-1", [])
        assert result == []

    def test_passes_cache_dir_to_load_sso_token(self):
        cache = Path("/custom/cache")
        with (
            patch("aws_config_gen.discovery.load_sso_token", return_value="tok") as m,
            patch("aws_config_gen.discovery.list_accounts", return_value=[]),
        ):
            discover_all_roles("sess", "us-east-1", [], cache_dir=cache)
        m.assert_called_once_with("sess", cache)
