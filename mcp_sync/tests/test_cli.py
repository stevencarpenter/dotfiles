"""Tests for the CLI entry point."""

from __future__ import annotations

import json
from pathlib import Path
from unittest.mock import patch

import pytest

from mcp_sync.cli import build_parser, cli


def test_build_parser_returns_parser():
    """Test that build_parser returns an ArgumentParser with expected args."""
    parser = build_parser()

    assert parser.prog == "sync-mcp-configs"

    # Verify --master, --home, and --machine-config arguments exist
    actions = {a.dest: a for a in parser._actions if a.dest != "help"}
    assert "master" in actions
    assert "home" in actions
    assert "machine_config" in actions
    assert actions["master"].type is Path
    assert actions["home"].type is Path
    assert actions["machine_config"].type is Path


def test_build_parser_defaults_to_none():
    """Test that all arguments default to None."""
    parser = build_parser()
    args = parser.parse_args([])

    assert args.master is None
    assert args.home is None
    assert args.machine_config is None


def test_build_parser_accepts_paths():
    """Test that the parser correctly parses path arguments."""
    parser = build_parser()
    args = parser.parse_args(
        [
            "--master",
            "/tmp/master.json",
            "--home",
            "/tmp/home",
            "--machine-config",
            "/tmp/machine.json",
        ]
    )

    assert args.master == Path("/tmp/master.json")
    assert args.home == Path("/tmp/home")
    assert args.machine_config == Path("/tmp/machine.json")


def test_cli_with_valid_args(temp_home, master_config_file):
    """Test cli() with valid master config and home directory."""
    exit_code = cli(["--master", str(master_config_file), "--home", str(temp_home)])

    assert exit_code == 0

    # Verify at least one config was created
    opencode_path = temp_home / ".config" / "opencode" / "opencode.json"
    assert opencode_path.exists()
    config = json.loads(opencode_path.read_text())
    assert "mcp" in config


def test_cli_missing_master_config(temp_home):
    """Test cli() when master config does not exist."""
    exit_code = cli(["--home", str(temp_home)])

    assert exit_code == 1


def test_cli_help_exits_zero():
    """Test that --help exits with code 0."""
    with pytest.raises(SystemExit) as exc_info:
        cli(["--help"])

    assert exc_info.value.code == 0


def test_cli_no_args_calls_run_sync():
    """Test cli() with no args delegates to run_sync."""
    with patch("mcp_sync.cli.run_sync", return_value=0) as mock_sync:
        exit_code = cli([])

    assert exit_code == 0
    mock_sync.assert_called_once()
    call_kwargs = mock_sync.call_args[1]
    assert "master_path" in call_kwargs
    assert "home" in call_kwargs
    assert "machine_config_path" in call_kwargs
    assert call_kwargs["machine_config_path"] is None


def test_cli_expands_user_in_paths():
    """Test that ~ in paths is expanded."""
    with patch("mcp_sync.cli.run_sync", return_value=0) as mock_sync:
        cli(
            [
                "--master",
                "~/master.json",
                "--home",
                "~/myhome",
                "--machine-config",
                "~/machine.json",
            ]
        )

    call_kwargs = mock_sync.call_args[1]
    # expanduser should have been applied, so ~ should not be in the path
    assert "~" not in str(call_kwargs["master_path"])
    assert "~" not in str(call_kwargs["home"])
    assert "~" not in str(call_kwargs["machine_config_path"])


def test_cli_machine_config_passed_to_run_sync(temp_home, master_config_file):
    """Test that --machine-config is correctly passed through to run_sync."""
    machine_overlay = {"servers": {"work-srv": {"command": "work", "args": []}}}
    machine_path = temp_home / "machine.json"
    machine_path.write_text(json.dumps(machine_overlay), encoding="utf-8")

    exit_code = cli(
        [
            "--master",
            str(master_config_file),
            "--home",
            str(temp_home),
            "--machine-config",
            str(machine_path),
        ]
    )

    assert exit_code == 0

    # Verify the machine overlay server made it into an output config
    opencode_path = temp_home / ".config" / "opencode" / "opencode.json"
    config = json.loads(opencode_path.read_text())
    assert "work-srv" in config["mcp"]
