"""Integration tests for the complete MCP sync workflow."""

from __future__ import annotations

import json
from pathlib import Path

import pytest

from mcp_sync import main


def test_full_sync_workflow_all_targets(
    temp_home, monkeypatch_home, master_config_file
):
    """Integration test: full sync to all target locations."""
    # Mock Path.home() to return temp_home
    monkeypatch_home.setattr(Path, "home", lambda: temp_home)

    exit_code = main()

    assert exit_code == 0

    # Verify all expected files were created
    expected_files = [
        ".config/.copilot/mcp-config.json",
        ".config/github-copilot/intellij/mcp.json",
        ".config/github-copilot/mcp.json",
        ".config/mcp/mcp_config.json",
        ".config/opencode/opencode.json",
        ".config/cursor/mcp.json",
        ".config/vscode/mcp.json",
        ".config/junie/mcp/mcp.json",
        ".config/lmstudio/mcp.json",
    ]

    for file_path in expected_files:
        full_path = temp_home / file_path
        assert full_path.exists(), f"Missing: {file_path}"
        # Verify it's valid JSON
        config = json.loads(full_path.read_text())
        assert isinstance(config, dict)


def test_full_sync_copilot_format_has_tools_array(
    temp_home, monkeypatch_home, master_config_file
):
    """Integration test: verify Copilot format includes tools array."""

    monkeypatch_home.setattr(Path, "home", lambda: temp_home)
    main()

    copilot_config = json.loads(
        (temp_home / ".config/.copilot/mcp-config.json").read_text()
    )

    # Copilot format should have tools array
    for server_name, server_config in copilot_config.get("mcpServers", {}).items():
        assert "tools" in server_config, f"Server {server_name} missing tools array"
        assert server_config["tools"] == ["*"]


def test_full_sync_generic_mcp_has_schema(
    temp_home, monkeypatch_home, master_config_file
):
    """Integration test: verify generic MCP format has schema."""

    monkeypatch_home.setattr(Path, "home", lambda: temp_home)
    main()

    generic_config = json.loads((temp_home / ".config/mcp/mcp_config.json").read_text())

    assert "$schema" in generic_config
    assert (
        generic_config["$schema"]
        == "https://modelcontextprotocol.io/schema/config.json"
    )


def test_full_sync_ide_context_applied(temp_home, monkeypatch_home, master_config_file):
    """Integration test: IDE tools get IDE context in Serena args."""

    monkeypatch_home.setattr(Path, "home", lambda: temp_home)
    main()

    # Check GitHub Copilot
    copilot_config = json.loads(
        (temp_home / ".config/github-copilot/mcp.json").read_text()
    )
    serena_args = copilot_config.get("servers", {}).get("serena", {}).get("args", [])
    assert "--context=ide" in serena_args

    # Check VSCode
    vscode_config = json.loads((temp_home / ".config/vscode/mcp.json").read_text())
    serena_args = vscode_config.get("servers", {}).get("serena", {}).get("args", [])
    assert "--context=ide" in serena_args


def test_full_sync_cursor_legacy_mirror(
    temp_home, monkeypatch_home, master_config_file
):
    """Integration test: Cursor config is mirrored to legacy location."""

    monkeypatch_home.setattr(Path, "home", lambda: temp_home)

    # Create legacy dir to enable mirroring
    (temp_home / ".cursor").mkdir(parents=True, exist_ok=True)

    main()

    xdg_path = temp_home / ".config/cursor/mcp.json"
    legacy_path = temp_home / ".cursor/mcp.json"

    assert xdg_path.exists()
    assert legacy_path.exists()

    # Files should have identical content
    assert xdg_path.read_text() == legacy_path.read_text()


def test_full_sync_env_vars_preserved(temp_home, monkeypatch_home, master_config_file):
    """Integration test: environment variables are preserved in all formats."""

    monkeypatch_home.setattr(Path, "home", lambda: temp_home)
    main()

    # Check GitHub config has env
    github_config = json.loads(
        (temp_home / ".config/github-copilot/intellij/mcp.json").read_text()
    )
    github_server = github_config.get("servers", {}).get("github", {})
    assert "env" in github_server
    assert github_server["env"]["GITHUB_TOKEN"] == "${GITHUB_TOKEN}"

    # Check OpenCode format
    opencode_path = temp_home / ".config/opencode/opencode.json"
    opencode_config = json.loads(opencode_path.read_text())
    if "mcp" in opencode_config and "github" in opencode_config["mcp"]:
        assert "environment" in opencode_config["mcp"]["github"]


def test_sync_with_existing_claude_config(
    temp_home, monkeypatch_home, master_config_file, claude_config_template
):
    """Integration test: existing Claude config is merged correctly."""

    monkeypatch_home.setattr(Path, "home", lambda: temp_home)

    # Create existing Claude config
    claude_path = temp_home / ".claude.json"
    claude_path.write_text(
        json.dumps(claude_config_template, indent=2), encoding="utf-8"
    )

    exit_code = main()

    assert exit_code == 0

    result = json.loads(claude_path.read_text())

    # Old servers merged with master servers (not replaced)
    assert "filesystem" in result["mcpServers"]
    assert "old_server" in result["mcpServers"]

    # Claude Code context
    assert "--context=claude-code" in result["mcpServers"]["serena"]["args"]

    # Other config preserved
    assert result["model"] == "claude-opus-4-5"
    assert "github" in result["enabledPlugins"]


def test_sync_with_existing_opencode_config(
    temp_home, monkeypatch_home, master_config_file
):
    """Integration test: existing OpenCode config is overwritten from base template."""

    monkeypatch_home.setattr(Path, "home", lambda: temp_home)

    # Create existing OpenCode config
    opencode_dir = temp_home / ".config/opencode"
    opencode_dir.mkdir(parents=True, exist_ok=True)
    opencode_path = opencode_dir / "opencode.json"
    opencode_path.write_text(
        json.dumps({"model": "gpt-4", "providers": ["openai"], "mcp": {}}, indent=2),
        encoding="utf-8",
    )

    exit_code = main()

    assert exit_code == 0

    result = json.loads(opencode_path.read_text())

    # Base template should be present
    assert "provider" in result

    # Should have updated mcp section
    assert "mcp" in result
    assert "filesystem" in result["mcp"]

    # OpenCode format should use command array
    assert isinstance(result["mcp"]["filesystem"]["command"], list)

    # IDE context in command array (OpenCode doesn't use separate args field)
    assert "--context=ide" in result["mcp"]["serena"]["command"]
    assert "args" not in result["mcp"]["serena"]

    # Prior custom fields should be overwritten
    assert "model" not in result
    assert "providers" not in result


def test_sync_missing_master_config(temp_home, monkeypatch_home):
    """Integration test: graceful failure when master config missing."""

    monkeypatch_home.setattr(Path, "home", lambda: temp_home)

    exit_code = main()

    assert exit_code == 1


def test_sync_with_codex_config(temp_home, monkeypatch_home, master_config_file):
    """Integration test: Codex config created with Serena server."""

    monkeypatch_home.setattr(Path, "home", lambda: temp_home)

    # Create existing Codex config
    codex_dir = temp_home / ".codex"
    codex_dir.mkdir(parents=True, exist_ok=True)
    codex_config = codex_dir / "config.toml"
    codex_config.write_text('[tool]\nname = "codex"\n', encoding="utf-8")

    exit_code = main()

    assert exit_code == 0

    result = codex_config.read_text()
    assert "[mcp_servers.serena]" in result
    assert "--context=codex" in result
    assert 'model = "gpt-5.2"' in result


def test_junie_gets_agent_context(temp_home, monkeypatch_home, master_config_file):
    """Integration test: Junie gets agent context, not IDE context."""

    monkeypatch_home.setattr(Path, "home", lambda: temp_home)
    main()

    junie_config = json.loads((temp_home / ".config/junie/mcp/mcp.json").read_text())

    serena_args = junie_config.get("mcpServers", {}).get("serena", {}).get("args", [])
    assert "--context=agent" in serena_args
    assert "--context=ide" not in serena_args


def test_lmstudio_gets_desktop_context(temp_home, monkeypatch_home, master_config_file):
    """Integration test: LM Studio gets desktop-app context."""

    monkeypatch_home.setattr(Path, "home", lambda: temp_home)
    main()

    lm_config = json.loads((temp_home / ".config/lmstudio/mcp.json").read_text())

    serena_args = lm_config.get("mcpServers", {}).get("serena", {}).get("args", [])
    assert "--context=desktop-app" in serena_args


def test_sync_idempotency(temp_home, monkeypatch_home, master_config_file):
    """Integration test: running sync twice produces identical results."""

    monkeypatch_home.setattr(Path, "home", lambda: temp_home)

    # First run
    main()
    first_results = {}
    for config_file in temp_home.glob("**/*.json"):
        relative = config_file.relative_to(temp_home)
        first_results[str(relative)] = config_file.read_text()

    # Second run
    main()
    second_results = {}
    for config_file in temp_home.glob("**/*.json"):
        relative = config_file.relative_to(temp_home)
        second_results[str(relative)] = config_file.read_text()

    # Results should be identical
    assert first_results == second_results, "Sync is not idempotent"


if __name__ == "__main__":
    pytest.main([__file__, "-v"])
