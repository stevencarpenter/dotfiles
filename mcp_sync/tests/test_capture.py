"""Tests for override capture (sync-mcp-configs --capture <target>)."""

from __future__ import annotations

import json

import pytest

from mcp_sync.capture import capture_target, run_capture
from mcp_sync.cli import cli
from mcp_sync.drift import drift_report, run_check
from mcp_sync.sync import load_master_config, run_sync


def _entries_by_name(entries):
    return {entry.name: entry for entry in entries}


def _read_json(path):
    return json.loads(path.read_text(encoding="utf-8"))


def _write_json(path, payload):
    path.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")


def test_capture_hand_added_server_round_trips(
    temp_home, monkeypatch_home, master_config_file
):
    """A server added by hand to cursor's config survives the next sync."""
    run_sync(home=temp_home)
    cursor_path = temp_home / ".cursor" / "mcp.json"
    config = _read_json(cursor_path)
    config["mcpServers"]["hand-added"] = {"command": "echo", "args": ["hi"]}
    _write_json(cursor_path, config)

    master = load_master_config(master_config_file)
    result = capture_target("cursor", master, temp_home)

    assert result.verified
    assert not result.uncapturable
    override = _read_json(temp_home / ".config/mcp/overrides/cursor.json")
    assert override["mcpServers"]["hand-added"]["command"] == "echo"

    run_sync(home=temp_home)
    assert _read_json(cursor_path)["mcpServers"]["hand-added"]["args"] == ["hi"]
    entries = _entries_by_name(drift_report(master, temp_home))
    assert entries["cursor"].status == "clean"


def test_empty_capture_target_errors_not_full_sync(
    temp_home, monkeypatch_home, master_config_file
):
    """`--capture ""` must error out, never silently run a full sync."""
    assert cli(["--capture", "", "--home", str(temp_home)]) == 1


def test_capture_retired_server_reports_specific_residual(
    temp_home, monkeypatch_home, master_config_file, capsys
):
    """Re-adding a retired server can't round-trip; residual names the path."""
    run_sync(home=temp_home)
    cursor_path = temp_home / ".cursor" / "mcp.json"
    config = _read_json(cursor_path)
    # "github" is retired: the sync strips it, so it can never be reproduced.
    config["mcpServers"]["github"] = {"command": "gh", "args": ["mcp"]}
    _write_json(cursor_path, config)

    master = load_master_config(master_config_file)
    result = capture_target("cursor", master, temp_home)

    assert not result.verified
    assert any("github" in path for path in result.residual)

    # run_capture surfaces the specific path and exits 1 (not a generic message).
    assert run_capture(home=temp_home, name="cursor") == 1
    assert "github" in capsys.readouterr().out


def test_capture_changed_field_round_trips(
    temp_home, monkeypatch_home, master_config_file
):
    """A tweaked field on a managed server replays through the override."""
    run_sync(home=temp_home)
    lmstudio_path = temp_home / ".lmstudio" / "mcp.json"
    config = _read_json(lmstudio_path)
    config["mcpServers"]["memory"]["args"] = ["--fast"]
    _write_json(lmstudio_path, config)

    master = load_master_config(master_config_file)
    result = capture_target("lmstudio", master, temp_home)

    assert result.verified
    run_sync(home=temp_home)
    assert _read_json(lmstudio_path)["mcpServers"]["memory"]["args"] == ["--fast"]


def test_capture_deleted_server_becomes_enabled_false(
    temp_home, monkeypatch_home, master_config_file
):
    """Deleting a server by hand captures as a pre-transform disable."""
    run_sync(home=temp_home)
    junie_path = temp_home / ".junie" / "mcp" / "mcp.json"
    config = _read_json(junie_path)
    del config["mcpServers"]["memory"]
    _write_json(junie_path, config)

    master = load_master_config(master_config_file)
    result = capture_target("junie", master, temp_home)

    assert result.verified
    override = _read_json(temp_home / ".config/mcp/overrides/junie.json")
    assert override["servers"]["memory"]["enabled"] is False

    run_sync(home=temp_home)
    assert "memory" not in _read_json(junie_path)["mcpServers"]
    entries = _entries_by_name(drift_report(master, temp_home))
    assert entries["junie"].status == "clean"


def test_capture_claude_managed_server_edit(
    temp_home, monkeypatch_home, master_config_file, claude_config_template
):
    """Hand edits to managed servers in ~/.claude.json replay via override."""
    claude_path = temp_home / ".claude.json"
    _write_json(claude_path, claude_config_template)
    run_sync(home=temp_home)

    config = _read_json(claude_path)
    config["mcpServers"]["memory"]["env"] = {"MEM_DEBUG": "1"}
    _write_json(claude_path, config)

    master = load_master_config(master_config_file)
    result = capture_target("claude", master, temp_home)

    assert result.verified
    run_sync(home=temp_home)
    assert _read_json(claude_path)["mcpServers"]["memory"]["env"] == {"MEM_DEBUG": "1"}
    entries = _entries_by_name(drift_report(master, temp_home))
    assert entries["claude"].status == "clean"


def test_capture_merges_into_existing_override(
    temp_home, monkeypatch_home, master_config_file
):
    """Capturing never clobbers keys already present in the override file."""
    overrides_dir = temp_home / ".config" / "mcp" / "overrides"
    overrides_dir.mkdir(parents=True)
    _write_json(overrides_dir / "cursor.json", {"customTopLevel": {"keep": True}})
    run_sync(home=temp_home)

    cursor_path = temp_home / ".cursor" / "mcp.json"
    config = _read_json(cursor_path)
    config["mcpServers"]["hand-added"] = {"command": "echo"}
    _write_json(cursor_path, config)

    master = load_master_config(master_config_file)
    capture_target("cursor", master, temp_home)

    override = _read_json(overrides_dir / "cursor.json")
    assert override["customTopLevel"] == {"keep": True}
    assert "hand-added" in override["mcpServers"]


def test_capture_codex_is_refused(temp_home, monkeypatch_home, master_config_file):
    """Codex is patch-managed; capture refuses rather than guessing."""
    run_sync(home=temp_home)
    master = load_master_config(master_config_file)

    with pytest.raises(ValueError, match="codex"):
        capture_target("codex", master, temp_home)
    assert not (temp_home / ".config/mcp/overrides/codex.json").exists()


def test_capture_clean_target_writes_nothing(
    temp_home, monkeypatch_home, master_config_file
):
    """No drift means no override file and a zero exit."""
    run_sync(home=temp_home)

    exit_code = run_capture("cursor", master_path=master_config_file, home=temp_home)

    assert exit_code == 0
    assert not (temp_home / ".config/mcp/overrides/cursor.json").exists()


def test_capture_uncapturable_deletion_warns(
    temp_home, monkeypatch_home, master_config_file
):
    """Deleting a nested field can't be expressed; capture reports it."""
    run_sync(home=temp_home)
    cursor_path = temp_home / ".cursor" / "mcp.json"
    config = _read_json(cursor_path)
    del config["mcpServers"]["memory"]["args"]
    _write_json(cursor_path, config)

    master = load_master_config(master_config_file)
    result = capture_target("cursor", master, temp_home)

    assert not result.verified
    assert any("memory" in path for path in result.uncapturable)


def test_cli_capture_flag(temp_home, monkeypatch_home, master_config_file):
    """--capture wires through the CLI and exits 0 on a full capture."""
    run_sync(home=temp_home)
    cursor_path = temp_home / ".cursor" / "mcp.json"
    config = _read_json(cursor_path)
    config["mcpServers"]["cli-added"] = {"command": "true"}
    _write_json(cursor_path, config)

    exit_code = cli(
        [
            "--capture",
            "cursor",
            "--home",
            str(temp_home),
            "--master",
            str(master_config_file),
        ]
    )

    assert exit_code == 0
    override = _read_json(temp_home / ".config/mcp/overrides/cursor.json")
    assert "cli-added" in override["mcpServers"]


def test_cli_capture_unknown_target_errors(
    temp_home, monkeypatch_home, master_config_file
):
    """An unknown target name exits nonzero without writing."""
    run_sync(home=temp_home)

    exit_code = cli(
        [
            "--capture",
            "nonesuch",
            "--home",
            str(temp_home),
            "--master",
            str(master_config_file),
        ]
    )

    assert exit_code == 1


def test_capture_malformed_json_reports_error_not_crash(
    temp_home, monkeypatch_home, master_config_file, capsys
):
    """A deployed file with broken JSON exits 1, never a traceback."""
    run_sync(home=temp_home)
    cursor_path = temp_home / ".cursor" / "mcp.json"
    cursor_path.write_text("{ not valid json", encoding="utf-8")

    exit_code = run_capture("cursor", master_path=master_config_file, home=temp_home)

    assert exit_code == 1
    assert "not valid JSON" in capsys.readouterr().out


def test_capture_master_missing_exits_1(temp_home, monkeypatch_home):
    """--capture with a nonexistent master config exits 1."""
    exit_code = run_capture(
        "cursor", master_path=temp_home / "nonesuch.json", home=temp_home
    )
    assert exit_code == 1


def test_check_master_missing_exits_1(temp_home, monkeypatch_home):
    """--check with a nonexistent master config exits 1."""
    exit_code = run_check(master_path=temp_home / "nonesuch.json", home=temp_home)
    assert exit_code == 1
