"""Unit and integration tests for the MCP sync package."""

from __future__ import annotations

import json
from pathlib import Path

import pytest

from mcp_sync import (
    deep_merge,
    load_master_config,
    patch_claude_code_config,
    set_serena_context,
    sync_codex_mcp,
    sync_copilot_cli_config,
    sync_opencode_mcp,
    sync_to_locations,
    transform_to_copilot_format,
    transform_to_generic_mcp_format,
    transform_to_mcpservers_format,
    transform_to_opencode_format,
)


def test_load_master_config_valid(master_config_file):
    """Test loading a valid master config file."""
    config = load_master_config(master_config_file)
    assert "servers" in config
    assert "filesystem" in config["servers"]
    assert config["servers"]["filesystem"]["command"] == "node"


def test_load_master_config_missing(temp_home):
    """Test loading a nonexistent master config."""
    missing_path = temp_home / ".config" / "mcp" / "mcp-master.json"
    with pytest.raises(FileNotFoundError):
        load_master_config(missing_path)


def test_load_master_config_malformed_json(temp_home):
    """Test loading malformed JSON."""
    config_dir = temp_home / ".config" / "mcp"
    config_dir.mkdir(parents=True, exist_ok=True)
    bad_config = config_dir / "mcp-master.json"
    bad_config.write_text("{invalid json}", encoding="utf-8")

    with pytest.raises(json.JSONDecodeError):
        load_master_config(bad_config)


def test_transform_to_copilot_format(master_config):
    """Test transformation to GitHub Copilot format."""
    result = transform_to_copilot_format(master_config)

    assert "mcpServers" in result
    assert "filesystem" in result["mcpServers"]
    assert result["mcpServers"]["filesystem"]["tools"] == ["*"]
    assert result["mcpServers"]["filesystem"]["type"] == "local"


def test_transform_to_generic_mcp_format(master_config):
    """Test transformation to generic MCP format."""
    result = transform_to_generic_mcp_format(master_config)

    assert "$schema" in result
    assert "mcpServers" in result
    assert "filesystem" in result["mcpServers"]
    assert result["$schema"] == "https://modelcontextprotocol.io/schema/config.json"


def test_transform_to_mcpservers_format(master_config):
    """Test transformation to mcpServers format."""
    result = transform_to_mcpservers_format(master_config)

    assert "mcpServers" in result
    assert "filesystem" in result["mcpServers"]


def test_set_serena_context_servers_format():
    """Test adding Serena context to servers format."""
    config = {"servers": {"serena": {"command": "bash", "args": ["-lc", "echo hello"]}}}

    result = set_serena_context(config, "test-context")

    assert "--context=test-context" in result["servers"]["serena"]["args"]


def test_set_serena_context_mcp_servers_format():
    """Test adding Serena context to mcpServers format."""
    config = {
        "mcpServers": {"serena": {"command": "bash", "args": ["-lc", "echo hello"]}}
    }

    result = set_serena_context(config, "ide")

    assert "--context=ide" in result["mcpServers"]["serena"]["args"]


def test_set_serena_context_replaces_existing():
    """Test that existing context is replaced."""
    config = {
        "servers": {
            "serena": {
                "command": "bash",
                "args": ["--context=old-context", "other-arg"],
            }
        }
    }

    result = set_serena_context(config, "new-context")
    args = result["servers"]["serena"]["args"]

    assert "--context=new-context" in args
    assert "--context=old-context" not in args
    assert "other-arg" in args


def test_set_serena_context_missing_serena():
    """Test that config without Serena is unchanged."""
    config = {"servers": {"filesystem": {"command": "node", "args": []}}}

    result = set_serena_context(config, "test")

    # Should be unchanged
    assert result == config


def test_set_serena_context_opencode_format():
    """Test adding Serena context to OpenCode format (command-only, no args)."""
    config = {"mcp": {"serena": {"command": ["bash", "-lc", "echo"]}}}

    result = set_serena_context(config, "editor")

    # OpenCode format uses command array only, no separate args field
    assert "--context=editor" in result["mcp"]["serena"]["command"]
    assert "args" not in result["mcp"]["serena"]


def test_transform_to_opencode_format(master_config):
    """Test transformation to OpenCode format."""
    result = transform_to_opencode_format(master_config)

    assert "mcp" in result
    assert "filesystem" in result["mcp"]
    assert result["mcp"]["filesystem"]["type"] == "local"
    assert result["mcp"]["filesystem"]["enabled"] is True
    assert result["mcp"]["filesystem"]["timeout"] == 30000
    assert isinstance(result["mcp"]["filesystem"]["command"], list)


def test_transform_to_opencode_with_env(master_config):
    """Test OpenCode format preserves environment variables."""
    result = transform_to_opencode_format(master_config)

    # github server has env
    assert "environment" in result["mcp"]["github"]
    assert result["mcp"]["github"]["environment"]["GITHUB_TOKEN"] == "${GITHUB_TOKEN}"


def test_sync_to_locations_creates_parent_dirs(temp_home, monkeypatch_home):
    """Test that sync_to_locations creates parent directories."""
    config = {"mcpServers": {"test": {}}}
    target = temp_home / ".config" / "test" / "deep" / "path" / "mcp.json"

    # Parent dirs should not exist yet
    assert not target.parent.exists()

    sync_to_locations(config, target)

    assert target.exists()
    assert json.loads(target.read_text()) == config


def test_sync_to_locations_with_legacy(temp_home, monkeypatch_home):
    """Test that sync_to_locations mirrors to legacy location."""
    config = {"mcpServers": {"test": {}}}
    xdg_target = temp_home / ".config" / "test" / "mcp.json"
    legacy_dir = temp_home / ".test"
    legacy_target = legacy_dir / "mcp.json"

    # Create legacy dir to trigger copy
    legacy_dir.mkdir(parents=True, exist_ok=True)

    sync_to_locations(config, xdg_target, legacy_dir, legacy_target)

    assert xdg_target.exists()
    assert legacy_target.exists()
    assert xdg_target.read_text() == legacy_target.read_text()


def test_patch_claude_code_config_missing(temp_home, monkeypatch_home, master_config):
    """Test that missing Claude Code config is skipped gracefully."""
    # No ~/.claude.json file exists
    # Should not raise, just log and return
    patch_claude_code_config(master_config)

    # Verify no file was created
    claude_path = temp_home / ".claude.json"
    assert not claude_path.exists()


def test_patch_claude_code_config_merges_servers(
    temp_home, monkeypatch_home, master_config, claude_config_template
):
    """Test that Claude Code config merges MCP servers (old + new)."""
    claude_path = temp_home / ".claude.json"
    claude_path.write_text(
        json.dumps(claude_config_template, indent=2), encoding="utf-8"
    )

    patch_claude_code_config(master_config)

    result = json.loads(claude_path.read_text())

    # Old servers should be preserved (merge, not replace)
    assert "old_server" in result["mcpServers"]

    # Master servers should also be present
    assert "filesystem" in result["mcpServers"]
    assert "github" in result["mcpServers"]


def test_patch_claude_code_config_sets_serena_context(
    temp_home, monkeypatch_home, master_config
):
    """Test that Claude Code Serena gets claude-code context."""
    claude_config = {"mcpServers": {"serena": {"command": "bash", "args": []}}}

    claude_path = temp_home / ".claude.json"
    claude_path.write_text(json.dumps(claude_config, indent=2), encoding="utf-8")

    patch_claude_code_config(master_config)

    result = json.loads(claude_path.read_text())
    assert "--context=claude-code" in result["mcpServers"]["serena"]["args"]


def test_empty_master_config_handling(master_config_file, temp_home, monkeypatch_home):
    """Test handling of master config with no servers."""
    empty_config = {"servers": {}}

    result = transform_to_generic_mcp_format(empty_config)

    assert "mcpServers" in result
    assert result["mcpServers"] == {}


def test_none_servers_handling(master_config):
    """Test handling when servers is None."""
    config = {"servers": None}

    result = transform_to_generic_mcp_format(config)

    assert "mcpServers" in result
    assert result["mcpServers"] == {}


def test_edge_case_special_chars_in_args(master_config):
    """Test handling of special characters in command arguments."""
    config = {
        "servers": {
            "test": {
                "command": "bash",
                "args": ["-c", 'echo "hello world" && echo $VAR'],
            }
        }
    }

    result = transform_to_opencode_format(config)

    # Should preserve the arguments exactly
    assert 'echo "hello world" && echo $VAR' in result["mcp"]["test"]["command"]


def test_deep_merge_appends_list_with_plus_key():
    """Test that deep_merge appends list values using the + suffix."""
    base = {"enabledPlugins": ["alpha"]}
    override = {"enabledPlugins+": ["beta", "alpha"]}

    result = deep_merge(base, override)

    assert result["enabledPlugins"] == ["alpha", "beta"]


def test_patch_claude_code_config_applies_override(
    temp_home, monkeypatch_home, master_config
):
    """Test that Claude overrides are merged into the config."""
    claude_path = temp_home / ".claude.json"
    claude_path.write_text(
        json.dumps({"mcpServers": {}, "theme": "light"}, indent=2), encoding="utf-8"
    )

    override_dir = temp_home / ".config" / "mcp" / "overrides"
    override_dir.mkdir(parents=True, exist_ok=True)
    override_path = override_dir / "claude.json"
    override_path.write_text(
        json.dumps(
            {"theme": "dark", "enabledPlugins": {"new-plugin@source": True}}, indent=2
        ),
        encoding="utf-8",
    )

    monkeypatch_home.setattr(Path, "home", lambda: temp_home)
    patch_claude_code_config(master_config)

    result = json.loads(claude_path.read_text())
    assert result["theme"] == "dark"
    assert result["enabledPlugins"]["new-plugin@source"] is True


def test_sync_opencode_mcp_with_existing_config(
    temp_home, monkeypatch_home, master_config
):
    """Test syncing MCP servers to OpenCode config."""
    opencode_dir = temp_home / ".config" / "opencode"
    opencode_dir.mkdir(parents=True, exist_ok=True)
    opencode_path = opencode_dir / "opencode.json"

    # Create initial OpenCode config
    initial_config = {
        "$schema": "https://opencode.ai/config.json",
        "provider": {
            "lmstudio": {
                "npm": "@ai-sdk/openai-compatible",
                "name": "LM Studio (local)",
                "options": {"baseURL": "http://localhost:1234/v1"},
                "models": {"qwen/qwen3-coder-30b": {"name": "qwen3-coder-30b"}},
            }
        },
        "mcp": {},
    }
    opencode_path.write_text(json.dumps(initial_config, indent=2), encoding="utf-8")

    monkeypatch_home.setattr(Path, "home", lambda: temp_home)
    sync_opencode_mcp(master_config)

    result = json.loads(opencode_path.read_text())

    # Provider config should be preserved
    assert "provider" in result
    assert result["provider"]["lmstudio"]["name"] == "LM Studio (local)"

    # MCP servers should be synced
    assert "mcp" in result
    assert "filesystem" in result["mcp"]

    # Serena should have IDE context
    assert "--context=ide" in result["mcp"]["serena"]["command"]


def test_sync_opencode_mcp_missing_config(temp_home, monkeypatch_home, master_config):
    """Test syncing creates OpenCode config when missing."""
    monkeypatch_home.setattr(Path, "home", lambda: temp_home)
    sync_opencode_mcp(master_config)

    opencode_path = temp_home / ".config" / "opencode" / "opencode.json"
    assert opencode_path.exists()


def test_sync_codex_mcp_with_existing_config(
    temp_home, monkeypatch_home, master_config
):
    """Test syncing MCP servers to Codex config."""
    codex_dir = temp_home / ".codex"
    codex_dir.mkdir(parents=True, exist_ok=True)
    codex_path = codex_dir / "config.toml"

    # Create initial Codex config
    initial_config = """model = "gpt-5.2"
model_reasoning_effort = "medium"

[projects."/home/user/projects/test"]
trust_level = "trusted"

[notice]
hide_gpt5_1_migration_prompt = true
"""
    codex_path.write_text(initial_config, encoding="utf-8")

    monkeypatch_home.setattr(Path, "home", lambda: temp_home)
    sync_codex_mcp(master_config, "codex")

    result = codex_path.read_text(encoding="utf-8")

    # Base template settings should be present
    assert 'model = "gpt-5.2"' in result
    assert "[notice]" in result

    # MCP servers should be added
    assert "[mcp_servers.filesystem]" in result
    assert "[mcp_servers.serena]" in result

    # Serena should have codex context
    assert "--context=codex" in result


def test_sync_codex_mcp_removes_old_servers(temp_home, monkeypatch_home, master_config):
    """Test that old MCP server sections are removed."""
    codex_dir = temp_home / ".codex"
    codex_dir.mkdir(parents=True, exist_ok=True)
    codex_path = codex_dir / "config.toml"

    # Create Codex config with old server
    initial_config = """model = "gpt-5.2"

[mcp_servers.old-server]
command = "node"
args = ["--version"]

[notice]
hide_prompt = true
"""
    codex_path.write_text(initial_config, encoding="utf-8")

    monkeypatch_home.setattr(Path, "home", lambda: temp_home)
    sync_codex_mcp(master_config, "codex")

    result = codex_path.read_text(encoding="utf-8")

    # Old server should be gone
    assert "[mcp_servers.old-server]" not in result
    # New servers should be present
    assert "[mcp_servers.filesystem]" in result


def test_sync_codex_mcp_missing_config(temp_home, monkeypatch_home, master_config):
    """Test syncing creates Codex config when missing."""
    monkeypatch_home.setattr(Path, "home", lambda: temp_home)
    sync_codex_mcp(master_config, "codex")

    codex_path = temp_home / ".codex" / "config.toml"
    assert codex_path.exists()


def test_sync_copilot_cli_preserves_auth_tokens(temp_home, monkeypatch_home):
    """Test that sync_copilot_cli_config preserves auth tokens from backup."""
    copilot_dir = temp_home / ".config" / ".copilot"
    copilot_dir.mkdir(parents=True, exist_ok=True)

    # Create deployed config (from chezmoi, no auth tokens)
    deployed_config = {
        "banner": "never",
        "model": "claude-opus-4.5",
        "render_markdown": True,
        "theme": "auto",
        "trusted_folders": ["/home/user/projects"],
        "logged_in_users": [],
        "last_logged_in_user": {"host": "https://github.com", "login": ""},
    }
    deployed_path = copilot_dir / "config.json"
    deployed_path.write_text(json.dumps(deployed_config, indent=2), encoding="utf-8")

    # Create backup with auth tokens
    backup_config = {
        **deployed_config,
        "logged_in_users": [
            {"host": "https://github.com", "login": "user1"},
            {"host": "https://github.com", "login": "user2"},
        ],
        "last_logged_in_user": {"host": "https://github.com", "login": "user1"},
    }
    backup_path = copilot_dir / "config.backup.json"
    backup_path.write_text(json.dumps(backup_config, indent=2), encoding="utf-8")

    monkeypatch_home.setattr(Path, "home", lambda: temp_home)
    sync_copilot_cli_config()

    # Check that auth tokens were restored
    result = json.loads(deployed_path.read_text())
    assert len(result["logged_in_users"]) == 2
    assert result["logged_in_users"][0]["login"] == "user1"
    assert result["last_logged_in_user"]["login"] == "user1"


def test_sync_copilot_cli_creates_backup(temp_home, monkeypatch_home):
    """Test that sync_copilot_cli_config creates backup for next run."""
    copilot_dir = temp_home / ".config" / ".copilot"
    copilot_dir.mkdir(parents=True, exist_ok=True)

    deployed_config = {
        "banner": "never",
        "model": "claude-opus-4.5",
        "render_markdown": True,
        "theme": "auto",
        "trusted_folders": [],
        "logged_in_users": [],
    }
    deployed_path = copilot_dir / "config.json"
    deployed_path.write_text(json.dumps(deployed_config, indent=2), encoding="utf-8")

    monkeypatch_home.setattr(Path, "home", lambda: temp_home)
    sync_copilot_cli_config()

    # Check that backup was created
    backup_path = copilot_dir / "config.backup.json"
    assert backup_path.exists()
    backup = json.loads(backup_path.read_text())
    assert backup["model"] == "claude-opus-4.5"


def test_sync_copilot_cli_missing_config(temp_home, monkeypatch_home):
    """Test handling when Copilot config doesn't exist."""
    # Should not raise, just skip
    monkeypatch_home.setattr(Path, "home", lambda: temp_home)
    sync_copilot_cli_config()

    # Verify no files were created
    copilot_path = temp_home / ".config" / ".copilot" / "config.json"
    assert not copilot_path.exists()


def test_sync_copilot_cli_missing_backup(temp_home, monkeypatch_home):
    """Test handling when backup doesn't exist (first run)."""
    copilot_dir = temp_home / ".config" / ".copilot"
    copilot_dir.mkdir(parents=True, exist_ok=True)

    deployed_config = {
        "banner": "never",
        "model": "claude-opus-4.5",
        "trusted_folders": [],
        "logged_in_users": [],
    }
    deployed_path = copilot_dir / "config.json"
    deployed_path.write_text(json.dumps(deployed_config, indent=2), encoding="utf-8")

    monkeypatch_home.setattr(Path, "home", lambda: temp_home)
    sync_copilot_cli_config()

    # Should still work, just won't restore auth
    result = json.loads(deployed_path.read_text())
    assert result["model"] == "claude-opus-4.5"

    # Backup should be created for next run
    backup_path = copilot_dir / "config.backup.json"
    assert backup_path.exists()


if __name__ == "__main__":
    pytest.main([__file__, "-v"])
