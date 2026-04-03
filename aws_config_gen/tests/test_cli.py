"""Tests for the CLI module."""

from __future__ import annotations

import json
from unittest.mock import patch

from aws_config_gen.cli import cli
from aws_config_gen.sso_token import TokenExpiredError, TokenNotFoundError
from aws_config_gen.types import AccountRole, SSOAccount

_ACCOUNT = SSOAccount(
    account_id="111111111111",
    account_name="Acme Corp",
    email_address="acme@example.com",
)


def _write_overrides(tmp_path, sample_overrides):
    overrides_path = tmp_path / "overrides.json"
    overrides_path.write_text(
        json.dumps(
            {
                "sso_session": sample_overrides.sso_session,
                "sso_start_url": sample_overrides.sso_start_url,
                "sso_region": sample_overrides.sso_region,
                "default_region": sample_overrides.default_region,
                "account_names": sample_overrides.account_names,
                "role_short_names": sample_overrides.role_short_names,
                "skip": sample_overrides.skip,
            }
        )
    )
    return overrides_path


def test_dry_run_prints_to_stdout(capsys, tmp_path, sample_overrides):
    overrides_path = _write_overrides(tmp_path, sample_overrides)
    roles = [AccountRole(account=_ACCOUNT, role_name="SRE-ClientEnvironments")]

    with patch("aws_config_gen.cli.discover_all_roles", return_value=roles):
        rc = cli(["--dry-run", "--overrides", str(overrides_path)])

    assert rc == 0
    captured = capsys.readouterr()
    assert "[profile acme]" in captured.out
    assert "[sso-session lumin]" in captured.out


def test_strict_returns_one_on_token_expired(capsys, tmp_path, sample_overrides):
    overrides_path = _write_overrides(tmp_path, sample_overrides)

    with patch(
        "aws_config_gen.cli.discover_all_roles",
        side_effect=TokenExpiredError("expired"),
    ):
        rc = cli(["--strict", "--overrides", str(overrides_path)])

    assert rc == 1
    captured = capsys.readouterr()
    assert "aws sso login" in captured.err


def test_non_strict_returns_zero_on_token_not_found(capsys, tmp_path, sample_overrides):
    overrides_path = _write_overrides(tmp_path, sample_overrides)

    with patch(
        "aws_config_gen.cli.discover_all_roles",
        side_effect=TokenNotFoundError("not found"),
    ):
        rc = cli(["--overrides", str(overrides_path)])

    assert rc == 0
    captured = capsys.readouterr()
    assert "aws sso login" in captured.err
