"""Tests for the enabled flag feature in MCP server configurations."""

from __future__ import annotations

import json

import pytest

from mcp_sync import (
    deep_merge,
    transform_to_copilot_format,
    transform_to_generic_mcp_format,
    transform_to_mcpservers_format,
    transform_to_opencode_format,
)
from mcp_sync.sync import (
    _filter_enabled_servers,
    patch_claude_code_config,
    run_sync,
    sync_codex_mcp,
)


class TestFilterEnabledServers:
    """Unit tests for _filter_enabled_servers helper."""

    def test_filter_keeps_enabled_servers(self):
        """Servers with enabled=True are kept."""
        servers = {
            "server1": {"command": "cmd1", "enabled": True},
            "server2": {"command": "cmd2", "enabled": True},
        }
        result = _filter_enabled_servers(servers)
        assert "server1" in result
        assert "server2" in result

    def test_filter_removes_disabled_servers(self):
        """Servers with enabled=False are removed."""
        servers = {
            "enabled_server": {"command": "cmd1", "enabled": True},
            "disabled_server": {"command": "cmd2", "enabled": False},
        }
        result = _filter_enabled_servers(servers)
        assert "enabled_server" in result
        assert "disabled_server" not in result

    def test_filter_keeps_servers_without_enabled_field(self):
        """Servers without 'enabled' field are kept (default is enabled)."""
        servers = {
            "server1": {"command": "cmd1"},
            "server2": {"command": "cmd2", "args": ["--flag"]},
        }
        result = _filter_enabled_servers(servers)
        assert "server1" in result
        assert "server2" in result

    def test_filter_mixed_enabled_states(self):
        """Mix of enabled, disabled, and missing 'enabled' field."""
        servers = {
            "explicit_enabled": {"command": "cmd1", "enabled": True},
            "explicit_disabled": {"command": "cmd2", "enabled": False},
            "implicit_enabled": {"command": "cmd3"},
        }
        result = _filter_enabled_servers(servers)
        assert "explicit_enabled" in result
        assert "explicit_disabled" not in result
        assert "implicit_enabled" in result

    def test_filter_preserves_server_config(self):
        """Server configuration is preserved after filtering."""
        servers = {
            "server1": {
                "command": "node",
                "args": ["index.js"],
                "type": "local",
                "env": {"KEY": "value"},
                "enabled": True,
            }
        }
        result = _filter_enabled_servers(servers)
        assert result["server1"]["command"] == "node"
        assert result["server1"]["args"] == ["index.js"]
        assert result["server1"]["type"] == "local"
        assert result["server1"]["env"] == {"KEY": "value"}

    def test_filter_handles_empty_dict(self):
        """Empty server dict returns empty dict."""
        assert _filter_enabled_servers({}) == {}

    def test_filter_handles_non_dict_server_config(self):
        """Non-dict server configs are filtered out."""
        servers = {
            "valid": {"command": "cmd1", "enabled": True},
            "invalid": "not a dict",
            "also_invalid": None,
        }
        result = _filter_enabled_servers(servers)
        assert "valid" in result
        assert "invalid" not in result
        assert "also_invalid" not in result


class TestTransformWithEnabledFlag:
    """Test that all transform functions respect the enabled flag."""

    def test_copilot_format_filters_disabled(self):
        """Copilot transform filters disabled servers."""
        master = {
            "servers": {
                "enabled_server": {"command": "cmd1", "enabled": True},
                "disabled_server": {"command": "cmd2", "enabled": False},
            }
        }
        result = transform_to_copilot_format(master)
        assert "enabled_server" in result["mcpServers"]
        assert "disabled_server" not in result["mcpServers"]

    def test_copilot_format_removes_enabled_field_from_output(self):
        """Enabled field is not included in copilot output."""
        master = {
            "servers": {
                "server1": {"command": "cmd1", "enabled": True, "type": "local"}
            }
        }
        result = transform_to_copilot_format(master)
        assert "enabled" not in result["mcpServers"]["server1"]
        assert result["mcpServers"]["server1"]["command"] == "cmd1"

    def test_generic_mcp_format_filters_disabled(self):
        """Generic MCP transform filters disabled servers."""
        master = {
            "servers": {
                "enabled_server": {"command": "cmd1", "enabled": True},
                "disabled_server": {"command": "cmd2", "enabled": False},
            }
        }
        result = transform_to_generic_mcp_format(master)
        assert "enabled_server" in result["mcpServers"]
        assert "disabled_server" not in result["mcpServers"]

    def test_generic_mcp_format_removes_enabled_field(self):
        """Enabled field is not included in generic MCP output."""
        master = {"servers": {"server1": {"command": "cmd1", "enabled": True}}}
        result = transform_to_generic_mcp_format(master)
        assert "enabled" not in result["mcpServers"]["server1"]

    def test_mcpservers_format_filters_disabled(self):
        """McpServers transform filters disabled servers."""
        master = {
            "servers": {
                "enabled_server": {"command": "cmd1"},
                "disabled_server": {"command": "cmd2", "enabled": False},
            }
        }
        result = transform_to_mcpservers_format(master)
        assert "enabled_server" in result["mcpServers"]
        assert "disabled_server" not in result["mcpServers"]

    def test_opencode_format_filters_disabled(self):
        """OpenCode transform filters disabled servers."""
        master = {
            "servers": {
                "enabled_server": {"command": "cmd1", "args": []},
                "disabled_server": {"command": "cmd2", "args": [], "enabled": False},
            }
        }
        result = transform_to_opencode_format(master)
        assert "enabled_server" in result["mcp"]
        assert "disabled_server" not in result["mcp"]

    def test_opencode_format_has_own_enabled_true(self):
        """OpenCode format always sets enabled=True in output (format requirement)."""
        master = {"servers": {"server1": {"command": "cmd1", "args": []}}}
        result = transform_to_opencode_format(master)
        # OpenCode format has its own enabled field set to True
        assert result["mcp"]["server1"]["enabled"] is True


class TestEnabledFlagWithMachineOverlay:
    """Test enabled flag with machine overlay merging."""

    def test_machine_overlay_can_disable_master_server(self):
        """Machine overlay can disable a server from master config."""
        master = {"servers": {"server1": {"command": "cmd1"}}}
        machine = {"servers": {"server1": {"enabled": False}}}

        merged = deep_merge(master, machine)

        # After merge, server1 should have enabled=False
        assert merged["servers"]["server1"]["enabled"] is False

    def test_machine_overlay_can_enable_disabled_server(self):
        """Machine overlay can re-enable a disabled server."""
        master = {"servers": {"server1": {"command": "cmd1", "enabled": False}}}
        machine = {"servers": {"server1": {"enabled": True}}}

        merged = deep_merge(master, machine)

        assert merged["servers"]["server1"]["enabled"] is True

    def test_machine_overlay_adds_enabled_servers(self):
        """Machine overlay can add new servers with enabled flag."""
        master = {"servers": {"base": {"command": "base"}}}
        machine = {
            "servers": {
                "work-only": {"command": "work", "enabled": True},
                "disabled-work": {"command": "disabled", "enabled": False},
            }
        }

        merged = deep_merge(master, machine)

        assert "base" in merged["servers"]
        assert "work-only" in merged["servers"]
        assert "disabled-work" in merged["servers"]


class TestEnabledFlagIntegration:
    """Integration tests with full sync process."""

    def test_run_sync_excludes_disabled_servers(
        self, temp_home, master_config_file, monkeypatch_home
    ):
        """Disabled servers do not appear in any generated configs."""
        # Add a disabled server to master config
        master_with_disabled = {
            "servers": {
                "enabled_server": {
                    "command": "node",
                    "args": ["enabled.js"],
                    "type": "local",
                },
                "disabled_server": {
                    "command": "node",
                    "args": ["disabled.js"],
                    "type": "local",
                    "enabled": False,
                },
            }
        }
        master_config_file.write_text(
            json.dumps(master_with_disabled, indent=2), encoding="utf-8"
        )

        exit_code = run_sync(
            master_path=master_config_file,
            home=temp_home,
        )

        assert exit_code == 0

        # Check various output formats
        opencode_path = temp_home / ".config" / "opencode" / "opencode.json"
        opencode_config = json.loads(opencode_path.read_text())
        assert "enabled_server" in opencode_config["mcp"]
        assert "disabled_server" not in opencode_config["mcp"]

        generic_path = temp_home / ".config" / "mcp" / "mcp_config.json"
        generic_config = json.loads(generic_path.read_text())
        assert "enabled_server" in generic_config["mcpServers"]
        assert "disabled_server" not in generic_config["mcpServers"]

    def test_machine_overlay_disables_server_in_output(
        self, temp_home, master_config_file, monkeypatch_home
    ):
        """Machine overlay can disable a master server via enabled=False."""
        machine_overlay = {
            "servers": {
                "filesystem": {"enabled": False},  # Disable filesystem from master
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

        # filesystem should not appear in output
        opencode_path = temp_home / ".config" / "opencode" / "opencode.json"
        opencode_config = json.loads(opencode_path.read_text())
        assert "filesystem" not in opencode_config["mcp"]

        # Other servers from master should still be present
        assert "memory" in opencode_config["mcp"]

    def test_backward_compatibility_servers_without_enabled(
        self, temp_home, master_config_file, monkeypatch_home
    ):
        """Servers without 'enabled' field work as before (default enabled)."""
        exit_code = run_sync(
            master_path=master_config_file,
            home=temp_home,
        )

        assert exit_code == 0

        # All servers from master_config fixture should appear
        opencode_path = temp_home / ".config" / "opencode" / "opencode.json"
        opencode_config = json.loads(opencode_path.read_text())
        assert "filesystem" in opencode_config["mcp"]
        assert "memory" in opencode_config["mcp"]
        assert "github" in opencode_config["mcp"]


class TestCodexSyncWithEnabledFlag:
    """Test Codex TOML sync respects enabled flag."""

    def test_codex_sync_filters_disabled_servers(self, temp_home):
        """sync_codex_mcp filters disabled servers."""
        master = {
            "servers": {
                "enabled": {"command": "cmd1", "args": []},
                "disabled": {"command": "cmd2", "args": [], "enabled": False},
            }
        }

        # Create codex base template
        codex_template_dir = temp_home / ".local" / "share" / "chezmoi" / "mcp_sync" / "src" / "mcp_sync" / "templates"
        codex_template_dir.mkdir(parents=True, exist_ok=True)
        (codex_template_dir / "codex.base.toml").write_text(
            "[general]\nmodel = 'claude'\n"
        )

        sync_codex_mcp(master, home=temp_home)

        codex_path = temp_home / ".codex" / "config.toml"
        assert codex_path.is_file()
        content = codex_path.read_text()

        assert "[mcp_servers.enabled]" in content
        assert "[mcp_servers.disabled]" not in content


class TestClaudeCodePatchWithEnabledFlag:
    """Test Claude Code config patching respects enabled flag."""

    def test_claude_patch_filters_disabled_servers(
        self, temp_home, claude_config_template
    ):
        """patch_claude_code_config filters disabled servers."""
        claude_path = temp_home / ".claude.json"
        claude_path.write_text(json.dumps(claude_config_template), encoding="utf-8")

        master = {
            "servers": {
                "enabled": {"command": "cmd1", "args": []},
                "disabled": {"command": "cmd2", "args": [], "enabled": False},
            }
        }

        patch_claude_code_config(master, home=temp_home)

        claude_config = json.loads(claude_path.read_text())
        assert "enabled" in claude_config["mcpServers"]
        assert "disabled" not in claude_config["mcpServers"]
        # Old server from fixture should still be there
        assert "old_server" in claude_config["mcpServers"]

    def test_claude_patch_removes_enabled_field_from_output(
        self, temp_home, claude_config_template
    ):
        """Enabled field is not written to Claude config."""
        claude_path = temp_home / ".claude.json"
        claude_path.write_text(json.dumps(claude_config_template), encoding="utf-8")

        master = {
            "servers": {"server": {"command": "cmd", "args": [], "enabled": True}}
        }

        patch_claude_code_config(master, home=temp_home)

        claude_config = json.loads(claude_path.read_text())
        assert "enabled" not in claude_config["mcpServers"]["server"]
