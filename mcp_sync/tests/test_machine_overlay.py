"""Tests for machine config overlay loading and merge behavior."""

from __future__ import annotations

import json

from mcp_sync import deep_merge, load_machine_config
from mcp_sync.sync import run_sync


class TestLoadMachineConfig:
    """Unit tests for load_machine_config()."""

    def test_none_path_returns_empty(self):
        """Return empty dict when path is None."""
        assert load_machine_config(None) == {}

    def test_missing_file_returns_empty(self, tmp_path):
        """Return empty dict when the file does not exist."""
        missing = tmp_path / "does-not-exist.json"
        assert load_machine_config(missing) == {}

    def test_valid_file_returns_parsed(self, tmp_path):
        """Return parsed dict for a valid JSON file."""
        overlay = {"servers": {"work-tool": {"command": "work-tool", "args": []}}}
        path = tmp_path / "machine.json"
        path.write_text(json.dumps(overlay), encoding="utf-8")

        result = load_machine_config(path)
        assert result == overlay

    def test_invalid_json_returns_empty(self, tmp_path, capsys):
        """Return empty dict and log when JSON is invalid."""
        path = tmp_path / "bad.json"
        path.write_text("{not valid json!!", encoding="utf-8")

        result = load_machine_config(path)

        assert result == {}
        captured = capsys.readouterr()
        assert "invalid JSON" in captured.out


class TestMachineOverlayMerge:
    """Tests for deep_merge behavior with machine overlay data."""

    def test_overlay_adds_new_server(self):
        """Machine overlay adds a server not in master."""
        master = {"servers": {"base": {"command": "base"}}}
        overlay = {"servers": {"extra": {"command": "extra"}}}

        merged = deep_merge(master, overlay)

        assert "base" in merged["servers"]
        assert "extra" in merged["servers"]

    def test_overlay_overrides_existing_server(self):
        """Machine overlay overrides a server that exists in master."""
        master = {"servers": {"tool": {"command": "v1", "args": ["--old"]}}}
        overlay = {"servers": {"tool": {"command": "v2"}}}

        merged = deep_merge(master, overlay)

        assert merged["servers"]["tool"]["command"] == "v2"
        # deep_merge is recursive, so args from master survives since overlay
        # didn't touch it
        assert merged["servers"]["tool"]["args"] == ["--old"]

    def test_overlay_adds_top_level_key(self):
        """Machine overlay can add keys outside of servers."""
        master = {"servers": {"a": {"command": "a"}}}
        overlay = {"metadata": {"machine": "work"}}

        merged = deep_merge(master, overlay)

        assert merged["metadata"]["machine"] == "work"
        assert "a" in merged["servers"]

    def test_empty_overlay_is_identity(self):
        """Empty overlay does not change master."""
        master = {"servers": {"x": {"command": "x"}}}
        merged = deep_merge(master, {})
        assert merged == master


class TestRunSyncWithMachineConfig:
    """Integration test: machine overlay servers appear in generated configs."""

    def test_machine_overlay_servers_in_output(
        self, temp_home, master_config_file, monkeypatch_home
    ):
        """Servers from machine overlay appear in all generated configs."""
        # Create a machine overlay with a work-only server
        machine_overlay = {
            "servers": {
                "work-only": {
                    "command": "work-tool",
                    "args": ["--serve"],
                    "type": "local",
                }
            }
        }
        machine_path = temp_home / "machine.json"
        machine_path.write_text(json.dumps(machine_overlay, indent=2), encoding="utf-8")

        exit_code = run_sync(
            master_path=master_config_file,
            home=temp_home,
            machine_config_path=machine_path,
        )

        assert exit_code == 0

        # Check that the machine overlay server shows up in a JSON-based target
        opencode_path = temp_home / ".config" / "opencode" / "opencode.json"
        opencode_config = json.loads(opencode_path.read_text())
        assert "work-only" in opencode_config["mcp"]

        # Also appears in generic MCP config
        generic_path = temp_home / ".config" / "mcp" / "mcp_config.json"
        generic_config = json.loads(generic_path.read_text())
        assert "work-only" in generic_config["mcpServers"]

        # Master servers still present
        assert "filesystem" in opencode_config["mcp"]
        assert "filesystem" in generic_config["mcpServers"]

    def test_no_machine_config_still_works(
        self, temp_home, master_config_file, monkeypatch_home
    ):
        """run_sync works fine when machine_config_path is None (default)."""
        exit_code = run_sync(
            master_path=master_config_file,
            home=temp_home,
            machine_config_path=None,
        )

        assert exit_code == 0

        opencode_path = temp_home / ".config" / "opencode" / "opencode.json"
        opencode_config = json.loads(opencode_path.read_text())
        assert "filesystem" in opencode_config["mcp"]

    def test_missing_machine_config_file_still_works(
        self, temp_home, master_config_file, monkeypatch_home
    ):
        """run_sync works when machine_config_path points to nonexistent file."""
        exit_code = run_sync(
            master_path=master_config_file,
            home=temp_home,
            machine_config_path=temp_home / "nonexistent.json",
        )

        assert exit_code == 0

        opencode_path = temp_home / ".config" / "opencode" / "opencode.json"
        opencode_config = json.loads(opencode_path.read_text())
        assert "filesystem" in opencode_config["mcp"]
