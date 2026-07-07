"""Tests for the Gemini CLI patch-style sync target (~/.gemini/settings.json)."""

from __future__ import annotations

import json

import pytest

from mcp_sync.capture import capture_target
from mcp_sync.drift import drift_report
from mcp_sync.sync import (
    load_master_config,
    patch_gemini_config,
    render_gemini_config,
    run_sync,
)


def _entries_by_name(entries):
    return {entry.name: entry for entry in entries}


def _read_json(path):
    return json.loads(path.read_text(encoding="utf-8"))


def _write_json(path, payload):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")


def test_render_returns_none_when_file_absent(temp_home):
    """No ~/.gemini/settings.json means nothing to patch."""
    master = {"servers": {"memory": {"command": "node", "args": ["x"]}}}

    assert render_gemini_config(master, temp_home) is None


def test_sync_skips_gemini_when_absent(temp_home, monkeypatch_home, master_config_file):
    """A sync on a home without Gemini installed does not create the file."""
    run_sync(home=temp_home)

    assert not (temp_home / ".gemini" / "settings.json").exists()


def test_drift_reports_skipped_when_absent(
    temp_home, monkeypatch_home, master_config_file
):
    """Drift reports gemini as skipped rather than missing when absent."""
    run_sync(home=temp_home)

    master = load_master_config(master_config_file)
    entries = _entries_by_name(drift_report(master, temp_home))

    assert entries["gemini"].status == "skipped"


def test_local_server_mapped_to_stdio_type(temp_home):
    """A command-based server drops master's type/note and gets type: stdio."""
    gemini_path = temp_home / ".gemini" / "settings.json"
    _write_json(gemini_path, {"mcpServers": {}})
    master = {
        "servers": {
            "memory": {
                "command": "node",
                "args": ["/path/to/memory.js"],
                "type": "local",
                "note": "should be stripped",
            }
        }
    }

    config = render_gemini_config(master, temp_home)

    assert config["mcpServers"]["memory"] == {
        "command": "node",
        "args": ["/path/to/memory.js"],
        "type": "stdio",
    }


def test_url_server_mapped_to_http_url(temp_home):
    """A remote server with a url field maps to httpUrl, dropping command/args."""
    gemini_path = temp_home / ".gemini" / "settings.json"
    _write_json(gemini_path, {"mcpServers": {}})
    master = {
        "servers": {
            "grafana": {
                "type": "stdio",
                "url": "http://localhost:3000/mcp",
            }
        }
    }

    config = render_gemini_config(master, temp_home)

    assert config["mcpServers"]["grafana"] == {"httpUrl": "http://localhost:3000/mcp"}


def test_preserves_hand_added_server_and_other_keys(temp_home):
    """Unmanaged servers and non-mcpServers keys survive a render untouched."""
    gemini_path = temp_home / ".gemini" / "settings.json"
    _write_json(
        gemini_path,
        {
            "theme": "dark",
            "mcpServers": {
                "hand-added": {"type": "stdio", "command": "echo", "args": ["hi"]}
            },
        },
    )
    master = {
        "servers": {"memory": {"command": "node", "args": ["x"], "type": "local"}}
    }

    config = render_gemini_config(master, temp_home)

    assert config["theme"] == "dark"
    assert config["mcpServers"]["hand-added"] == {
        "type": "stdio",
        "command": "echo",
        "args": ["hi"],
    }
    assert config["mcpServers"]["memory"]["type"] == "stdio"


def test_run_sync_writes_gemini_config(temp_home, monkeypatch_home, master_config_file):
    """A real sync patches an existing settings.json in place."""
    gemini_path = temp_home / ".gemini" / "settings.json"
    _write_json(gemini_path, {"mcpServers": {}})

    assert run_sync(home=temp_home) == 0

    config = _read_json(gemini_path)
    assert config["mcpServers"]["memory"]["type"] == "stdio"
    assert "note" not in config["mcpServers"]["filesystem"]


def test_drift_clean_immediately_after_sync(
    temp_home, monkeypatch_home, master_config_file
):
    """A freshly synced gemini config reports clean drift."""
    gemini_path = temp_home / ".gemini" / "settings.json"
    _write_json(gemini_path, {"mcpServers": {}})
    run_sync(home=temp_home)

    master = load_master_config(master_config_file)
    entries = _entries_by_name(drift_report(master, temp_home))

    assert entries["gemini"].status == "clean"


def test_drift_flags_managed_server_hand_edit(
    temp_home, monkeypatch_home, master_config_file
):
    """Hand edits to a managed server entry are reported as drift."""
    gemini_path = temp_home / ".gemini" / "settings.json"
    _write_json(gemini_path, {"mcpServers": {}})
    run_sync(home=temp_home)

    config = _read_json(gemini_path)
    config["mcpServers"]["memory"]["args"] = ["--tweaked"]
    _write_json(gemini_path, config)

    master = load_master_config(master_config_file)
    entries = _entries_by_name(drift_report(master, temp_home))

    assert entries["gemini"].status == "drift"
    assert "--tweaked" in entries["gemini"].diff


def test_capture_managed_server_edit_round_trips(
    temp_home, monkeypatch_home, master_config_file
):
    """Hand edits to managed servers replay via the gemini override file."""
    gemini_path = temp_home / ".gemini" / "settings.json"
    _write_json(gemini_path, {"mcpServers": {}})
    run_sync(home=temp_home)

    config = _read_json(gemini_path)
    config["mcpServers"]["memory"]["env"] = {"MEM_DEBUG": "1"}
    _write_json(gemini_path, config)

    master = load_master_config(master_config_file)
    result = capture_target("gemini", master, temp_home)

    assert result.verified
    override = _read_json(temp_home / ".config/mcp/overrides/gemini.json")
    assert override["mcpServers"]["memory"]["env"] == {"MEM_DEBUG": "1"}

    run_sync(home=temp_home)
    assert _read_json(gemini_path)["mcpServers"]["memory"]["env"] == {"MEM_DEBUG": "1"}
    entries = _entries_by_name(drift_report(master, temp_home))
    assert entries["gemini"].status == "clean"


def test_capture_unknown_target_mentions_gemini(
    temp_home, monkeypatch_home, master_config_file
):
    """The unknown-target error advertises gemini as a known capture name."""
    master = load_master_config(master_config_file)

    with pytest.raises(ValueError, match="gemini"):
        capture_target("nonesuch", master, temp_home)


def test_patch_gemini_config_skips_when_absent(temp_home, capsys):
    """patch_gemini_config logs and no-ops when the file is absent."""
    master = {"servers": {}}

    patch_gemini_config(master, temp_home)

    assert not (temp_home / ".gemini" / "settings.json").exists()
