"""Tests for the CLI module."""

from __future__ import annotations

import json
import urllib.error
from unittest.mock import patch

from aws_config_gen.cli import cli
from aws_config_gen.sso_token import TokenExpiredError, TokenNotFoundError
from aws_config_gen.types import AccountRole, SSOAccount

_ACCOUNT = SSOAccount(
    account_id="111111111111",
    account_name="Acme Corp",
    email_address="acme@example.com",
)


def _write_generator_config(tmp_path, sample_generator_config):
    generator_config_path = tmp_path / "config.json"
    generator_config_path.write_text(
        json.dumps(
            {
                "sso_session": sample_generator_config.sso_session,
                "sso_start_url": sample_generator_config.sso_start_url,
                "sso_region": sample_generator_config.sso_region,
                "default_region": sample_generator_config.default_region,
                "account_names": sample_generator_config.account_names,
                "role_short_names": sample_generator_config.role_short_names,
                "skip": sample_generator_config.skip,
            }
        )
    )
    return generator_config_path


def test_dry_run_prints_to_stdout(capsys, tmp_path, sample_generator_config):
    generator_config_path = _write_generator_config(tmp_path, sample_generator_config)
    roles = [AccountRole(account=_ACCOUNT, role_name="SRE-ClientEnvironments")]

    with patch("aws_config_gen.cli.discover_all_roles", return_value=roles):
        rc = cli(["--dry-run", "--generator-config", str(generator_config_path)])

    assert rc == 0
    captured = capsys.readouterr()
    assert "[profile acme]" in captured.out
    assert "[sso-session test-session]" in captured.out


def test_strict_returns_one_on_token_expired(capsys, tmp_path, sample_generator_config):
    generator_config_path = _write_generator_config(tmp_path, sample_generator_config)

    with patch(
        "aws_config_gen.cli.discover_all_roles",
        side_effect=TokenExpiredError("expired"),
    ):
        rc = cli(["--strict", "--generator-config", str(generator_config_path)])

    assert rc == 1
    captured = capsys.readouterr()
    assert "aws sso login" in captured.err


def test_non_strict_returns_zero_on_token_not_found(
    capsys, tmp_path, sample_generator_config
):
    generator_config_path = _write_generator_config(tmp_path, sample_generator_config)

    with patch(
        "aws_config_gen.cli.discover_all_roles",
        side_effect=TokenNotFoundError("not found"),
    ):
        rc = cli(["--generator-config", str(generator_config_path)])

    assert rc == 0
    captured = capsys.readouterr()
    assert "aws sso login" in captured.err


def test_missing_generator_config_returns_one(capsys, tmp_path):
    rc = cli(["--generator-config", str(tmp_path / "nonexistent.json")])

    assert rc == 1
    captured = capsys.readouterr()
    assert "not found" in captured.err


def test_malformed_generator_config_returns_one(capsys, tmp_path):
    bad_config = tmp_path / "bad.json"
    bad_config.write_text("{not valid json")

    rc = cli(["--generator-config", str(bad_config)])

    assert rc == 1
    captured = capsys.readouterr()
    assert "Invalid" in captured.err


def test_invalid_skip_config_returns_one(capsys, tmp_path):
    bad_config = tmp_path / "bad-skip.json"
    bad_config.write_text(
        json.dumps(
            {
                "sso_session": "test-session",
                "sso_start_url": "https://example.com/start",
                "sso_region": "us-east-1",
                "default_region": "us-east-1",
                "skip": [["123"]],
            }
        )
    )

    rc = cli(["--generator-config", str(bad_config)])

    assert rc == 1
    captured = capsys.readouterr()
    assert "Invalid generator config file" in captured.err
    assert "skip entry 0 must be" in captured.err


def test_duplicate_profile_names_return_one(capsys, tmp_path, sample_generator_config):
    generator_config_path = tmp_path / "config.json"
    generator_config_path.write_text(
        json.dumps(
            {
                "sso_session": sample_generator_config.sso_session,
                "sso_start_url": sample_generator_config.sso_start_url,
                "sso_region": sample_generator_config.sso_region,
                "default_region": sample_generator_config.default_region,
                "account_names": {
                    "111111111111": "prod",
                    "222222222222": "prod",
                },
                "role_short_names": sample_generator_config.role_short_names,
                "skip": sample_generator_config.skip,
            }
        )
    )
    roles = [
        AccountRole(account=_ACCOUNT, role_name="ReadOnly"),
        AccountRole(
            account=SSOAccount(
                account_id="222222222222",
                account_name="Acme Dev",
                email_address="acme-dev@example.com",
            ),
            role_name="ReadOnly",
        ),
    ]

    with patch("aws_config_gen.cli.discover_all_roles", return_value=roles):
        rc = cli(["--generator-config", str(generator_config_path)])

    assert rc == 1
    captured = capsys.readouterr()
    assert "Invalid generator config file" in captured.err
    assert "Duplicate profile names" in captured.err


def test_existing_manual_profile_collision_returns_one(
    capsys, tmp_path, sample_generator_config
):
    generator_config_path = tmp_path / "config.json"
    generator_config_path.write_text(
        json.dumps(
            {
                "sso_session": sample_generator_config.sso_session,
                "sso_start_url": sample_generator_config.sso_start_url,
                "sso_region": sample_generator_config.sso_region,
                "default_region": sample_generator_config.default_region,
                "account_names": {
                    "111111111111": "prod",
                },
                "role_short_names": sample_generator_config.role_short_names,
                "skip": sample_generator_config.skip,
            }
        )
    )
    config_path = tmp_path / "aws-config"
    config_path.write_text("[profile prod]\nregion = us-east-1\n")
    roles = [AccountRole(account=_ACCOUNT, role_name="ReadOnly")]

    with patch("aws_config_gen.cli.discover_all_roles", return_value=roles):
        rc = cli(
            [
                "--generator-config",
                str(generator_config_path),
                "--config",
                str(config_path),
            ]
        )

    assert rc == 0
    captured = capsys.readouterr()
    assert "Absorbed" in captured.err
    # Manual profile replaced by generated one
    content = config_path.read_text()
    assert content.count("[profile prod]") == 1
    assert "sso_session = test-session" in content


def test_http_401_shows_login_message(capsys, tmp_path, sample_generator_config):
    generator_config_path = _write_generator_config(tmp_path, sample_generator_config)

    with patch(
        "aws_config_gen.cli.discover_all_roles",
        side_effect=urllib.error.HTTPError(
            url="https://example.com",
            code=401,
            msg="Unauthorized",
            hdrs=None,  # type: ignore[arg-type]
            fp=None,
        ),
    ):
        rc = cli(["--generator-config", str(generator_config_path)])

    assert rc == 0
    captured = capsys.readouterr()
    assert "aws sso login" in captured.err
    assert "401" in captured.err


def test_network_error_non_strict_returns_zero(
    capsys, tmp_path, sample_generator_config
):
    generator_config_path = _write_generator_config(tmp_path, sample_generator_config)

    with patch(
        "aws_config_gen.cli.discover_all_roles",
        side_effect=urllib.error.URLError("Name or service not known"),
    ):
        rc = cli(["--generator-config", str(generator_config_path)])

    assert rc == 0
    captured = capsys.readouterr()
    assert "Failed to reach" in captured.err


def test_network_error_strict_returns_one(capsys, tmp_path, sample_generator_config):
    generator_config_path = _write_generator_config(tmp_path, sample_generator_config)

    with patch(
        "aws_config_gen.cli.discover_all_roles",
        side_effect=urllib.error.URLError("Connection refused"),
    ):
        rc = cli(["--strict", "--generator-config", str(generator_config_path)])

    assert rc == 1
