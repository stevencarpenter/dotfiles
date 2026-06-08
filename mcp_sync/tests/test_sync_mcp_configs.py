"""Unit and integration tests for the MCP sync package."""

from __future__ import annotations

import json
from pathlib import Path

import pytest
from mcp_sync import (
    deep_merge,
    load_master_config,
    patch_claude_code_config,
    sync_codex_mcp,
    sync_to_locations,
    transform_to_copilot_format,
    transform_to_mcpservers_format,
    transform_to_opencode_format,
)
from mcp_sync.sync import transform_to_generic_mcp_format
from mcp_sync.sync import transform_to_identity_format


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


def test_transform_to_opencode_url_server():
    """URL-based servers render as remote entries, not local command arrays."""
    master = {
        "servers": {
            "xcode": {"type": "http", "url": "http://localhost:9876/mcp"},
        }
    }
    result = transform_to_opencode_format(master)

    entry = result["mcp"]["xcode"]
    assert entry == {
        "type": "remote",
        "url": "http://localhost:9876/mcp",
        "enabled": True,
    }
    assert "command" not in entry
    assert "timeout" not in entry
    assert "environment" not in entry


def test_transform_to_opencode_mixed_stdio_and_url(master_config):
    """Stdio servers render unchanged when URL servers are also present."""
    master = {
        **master_config,
        "servers": {
            **master_config["servers"],
            "xcode": {"type": "http", "url": "http://localhost:9876/mcp"},
        },
    }
    result = transform_to_opencode_format(master)

    # Stdio entries keep the original local shape
    assert result["mcp"]["filesystem"]["type"] == "local"
    assert isinstance(result["mcp"]["filesystem"]["command"], list)
    assert result["mcp"]["filesystem"]["timeout"] == 30000

    # URL entry uses remote shape
    assert result["mcp"]["xcode"]["type"] == "remote"
    assert result["mcp"]["xcode"]["url"] == "http://localhost:9876/mcp"


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


def test_patch_claude_code_config_passes_url_servers_through(
    temp_home, monkeypatch_home, claude_config_template
):
    """URL-based servers reach ~/.claude.json verbatim (Claude Code reads type:http natively)."""
    claude_path = temp_home / ".claude.json"
    claude_path.write_text(
        json.dumps(claude_config_template, indent=2), encoding="utf-8"
    )

    master = {
        "servers": {
            "xcode": {"type": "http", "url": "http://127.0.0.1:9876/mcp"},
        }
    }
    patch_claude_code_config(master)

    result = json.loads(claude_path.read_text())
    assert result["mcpServers"]["xcode"] == {
        "type": "http",
        "url": "http://127.0.0.1:9876/mcp",
    }


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


def test_sync_codex_mcp_with_existing_config(
    temp_home, monkeypatch_home, master_config
):
    """Preserve existing Codex config while adding managed MCP servers.

    Args:
        temp_home: Path fixture for the isolated home directory.
        monkeypatch_home: MonkeyPatch fixture used to patch ``Path.home``.
        master_config: MCP master config fixture.

    Returns:
        None.
    """
    codex_dir = temp_home / ".codex"
    codex_dir.mkdir(parents=True, exist_ok=True)
    codex_path = codex_dir / "config.toml"

    # Create initial Codex config
    initial_config = """model = "gpt-5.4"
model_reasoning_effort = "medium"

[projects."/home/user/projects/test"]
trust_level = "trusted"

[notice]
hide_gpt5_1_migration_prompt = true
"""
    codex_path.write_text(initial_config, encoding="utf-8")

    monkeypatch_home.setattr(Path, "home", lambda: temp_home)
    sync_codex_mcp(master_config)

    result = codex_path.read_text(encoding="utf-8")

    # Existing Codex-owned settings are preserved verbatim (NOT overwritten by the
    # base template) because the file already exists.
    assert 'model = "gpt-5.4"' in result
    assert 'model_reasoning_effort = "medium"' in result
    assert '[projects."/home/user/projects/test"]' in result
    assert "[notice]" in result

    # Managed MCP servers are added
    assert "[mcp_servers.filesystem]" in result


def test_sync_codex_mcp_preserves_codex_owned_state(
    temp_home, monkeypatch_home, master_config
):
    """Preserve Codex-owned tables while adding managed MCP servers.

    Args:
        temp_home: Path fixture for the isolated home directory.
        monkeypatch_home: MonkeyPatch fixture used to patch ``Path.home``.
        master_config: MCP master config fixture.

    Returns:
        None.
    """
    codex_dir = temp_home / ".codex"
    codex_dir.mkdir(parents=True, exist_ok=True)
    codex_path = codex_dir / "config.toml"

    # node_repl is a server Codex injects itself; it must not be clobbered.
    initial_config = """model = "gpt-5.4"

[mcp_servers.node_repl]
command = "/Applications/Codex.app/Contents/Resources/node_repl"
args = []

[mcp_servers.node_repl.env]
CODEX_HOME = "/Users/carpenter/.codex"

[desktop]
appearanceTheme = "dark"
"""
    codex_path.write_text(initial_config, encoding="utf-8")

    monkeypatch_home.setattr(Path, "home", lambda: temp_home)
    sync_codex_mcp(master_config)

    result = codex_path.read_text(encoding="utf-8")

    # Codex's own server (and its subtable) and settings are untouched
    assert "[mcp_servers.node_repl]" in result
    assert "[mcp_servers.node_repl.env]" in result
    assert 'CODEX_HOME = "/Users/carpenter/.codex"' in result
    assert "[desktop]" in result
    # Managed servers are still added
    assert "[mcp_servers.filesystem]" in result


def test_sync_codex_mcp_removes_disabled_servers(temp_home, monkeypatch_home):
    """Remove a server that is explicitly disabled in master.

    Args:
        temp_home: Path fixture for the isolated home directory.
        monkeypatch_home: MonkeyPatch fixture used to patch ``Path.home``.

    Returns:
        None.
    """
    codex_dir = temp_home / ".codex"
    codex_dir.mkdir(parents=True, exist_ok=True)
    codex_path = codex_dir / "config.toml"

    initial_config = """model = "gpt-5.4"

[mcp_servers.legacy]
command = "node"
args = ["old.js"]
"""
    codex_path.write_text(initial_config, encoding="utf-8")

    master = {
        "servers": {
            "filesystem": {"command": "node", "args": ["fs.js"], "type": "local"},
            "legacy": {"command": "node", "args": ["old.js"], "enabled": False},
        }
    }
    monkeypatch_home.setattr(Path, "home", lambda: temp_home)
    sync_codex_mcp(master)

    result = codex_path.read_text(encoding="utf-8")

    # Explicitly-disabled server is removed; enabled managed server remains
    assert "[mcp_servers.legacy]" not in result
    assert "[mcp_servers.filesystem]" in result


def test_sync_codex_mcp_removes_deleted_managed_servers(temp_home, monkeypatch_home):
    """Remove a generated server that no longer exists in master.

    Args:
        temp_home: Path fixture for the isolated home directory.
        monkeypatch_home: MonkeyPatch fixture used to patch ``Path.home``.

    Returns:
        None.
    """
    codex_dir = temp_home / ".codex"
    codex_dir.mkdir(parents=True, exist_ok=True)
    codex_path = codex_dir / "config.toml"

    initial_config = """model = "gpt-5.4"

# MCP Servers - BEGIN Codex

[mcp_servers.legacy]
command = "node"
args = ["old.js"]

[mcp_servers.legacy.env]
TOKEN = "old"

# MCP Servers - END Codex
"""
    codex_path.write_text(initial_config, encoding="utf-8")

    master = {
        "servers": {
            "filesystem": {"command": "node", "args": ["fs.js"], "type": "local"},
        }
    }
    monkeypatch_home.setattr(Path, "home", lambda: temp_home)
    sync_codex_mcp(master)

    result = codex_path.read_text(encoding="utf-8")

    assert "[mcp_servers.legacy]" not in result
    assert "[mcp_servers.legacy.env]" not in result
    assert 'TOKEN = "old"' not in result
    assert "# MCP Servers - BEGIN Codex" in result
    assert "# MCP Servers - END Codex" in result
    assert "[mcp_servers.filesystem]" in result


def test_sync_codex_mcp_preserves_third_party_servers_after_plain_header(
    temp_home, monkeypatch_home
):
    """Preserve third-party MCP tables after a non-managed ``# MCP Servers`` header.

    Args:
        temp_home: Path fixture for the isolated home directory.
        monkeypatch_home: MonkeyPatch fixture used to patch ``Path.home``.

    Returns:
        None.
    """
    codex_dir = temp_home / ".codex"
    codex_dir.mkdir(parents=True, exist_ok=True)
    codex_path = codex_dir / "config.toml"

    initial_config = """model = "gpt-5.4"

# MCP Servers

[mcp_servers.third_party]
command = "third-party"
args = ["serve"]

[mcp_servers.third_party.env]
TOKEN = "keep"
"""
    codex_path.write_text(initial_config, encoding="utf-8")

    master = {
        "servers": {
            "filesystem": {"command": "node", "args": ["fs.js"], "type": "local"},
        }
    }
    monkeypatch_home.setattr(Path, "home", lambda: temp_home)
    sync_codex_mcp(master)

    result = codex_path.read_text(encoding="utf-8")

    assert "[mcp_servers.third_party]" in result
    assert "[mcp_servers.third_party.env]" in result
    assert 'TOKEN = "keep"' in result
    assert "[mcp_servers.filesystem]" in result


def test_sync_codex_mcp_idempotent(temp_home, monkeypatch_home, master_config):
    """Running the codex sync twice produces byte-identical output.

    Guards the marker-block management: the managed [mcp_servers.*] section is
    replaced in place while Codex-owned tables (node_repl, [desktop]) survive
    unchanged across runs.
    """
    codex_dir = temp_home / ".codex"
    codex_dir.mkdir(parents=True, exist_ok=True)
    codex_path = codex_dir / "config.toml"
    codex_path.write_text(
        'model = "gpt-5.4"\n\n'
        "[mcp_servers.node_repl]\n"
        'command = "/Applications/Codex.app/Contents/Resources/node_repl"\n'
        "args = []\n\n"
        "[desktop]\n"
        'appearanceTheme = "dark"\n',
        encoding="utf-8",
    )
    monkeypatch_home.setattr(Path, "home", lambda: temp_home)

    sync_codex_mcp(master_config)
    first = codex_path.read_text()
    sync_codex_mcp(master_config)
    second = codex_path.read_text()

    assert first == second, "codex sync is not idempotent"
    assert "[mcp_servers.node_repl]" in second
    assert "[desktop]" in second
    assert "[mcp_servers.filesystem]" in second


def test_sync_codex_mcp_missing_config(temp_home, monkeypatch_home, master_config):
    """Syncing seeds the Codex config from the base template when missing."""
    monkeypatch_home.setattr(Path, "home", lambda: temp_home)
    sync_codex_mcp(master_config)

    codex_path = temp_home / ".codex" / "config.toml"
    assert codex_path.exists()
    result = codex_path.read_text()
    # Fresh machine: base template is seeded...
    assert 'model = "gpt-5.5"' in result
    assert "[tui]" in result
    assert (
        'status_line = ["model-with-reasoning", "current-dir", "git-branch", '
        '"pull-request-number", "branch-changes", "permissions", '
        '"context-remaining", "five-hour-limit", "weekly-limit", '
        '"codex-version", "used-tokens", "total-input-tokens", '
        '"total-output-tokens", "fast-mode", "task-progress"]' in result
    )
    assert "status_line_use_colors = true" in result
    # ...and the managed MCP servers are delimited by the begin marker.
    assert "# MCP Servers - BEGIN Codex" in result
    assert "[mcp_servers.filesystem]" in result
    # The [features] block must not be seeded — it is inert on macOS.
    assert "[features]" not in result


def test_sync_codex_mcp_url_server(temp_home, monkeypatch_home):
    """URL-based servers render as `url = "..."` with no command/args."""
    master = {
        "servers": {
            "xcode": {"type": "http", "url": "http://localhost:9876/mcp"},
        }
    }
    monkeypatch_home.setattr(Path, "home", lambda: temp_home)
    sync_codex_mcp(master)

    result = (temp_home / ".codex" / "config.toml").read_text(encoding="utf-8")

    assert "[mcp_servers.xcode]" in result
    assert 'url = "http://localhost:9876/mcp"' in result
    # No stdio fields for a URL server
    xcode_section = result.split("[mcp_servers.xcode]", 1)[1]
    # Next section boundary (or EOF) bounds xcode's block
    xcode_block = xcode_section.split("[mcp_servers.", 1)[0]
    assert "command =" not in xcode_block
    assert "args =" not in xcode_block
    assert "environment =" not in xcode_block


def test_sync_codex_mcp_mixed_stdio_and_url(temp_home, monkeypatch_home, master_config):
    """Stdio server rendering is unchanged when URL servers coexist."""
    master = {
        **master_config,
        "servers": {
            **master_config["servers"],
            "xcode": {"type": "http", "url": "http://localhost:9876/mcp"},
        },
    }
    monkeypatch_home.setattr(Path, "home", lambda: temp_home)
    sync_codex_mcp(master)

    result = (temp_home / ".codex" / "config.toml").read_text(encoding="utf-8")

    # Stdio server keeps command/args
    fs_block = result.split("[mcp_servers.filesystem]", 1)[1].split("[mcp_servers.", 1)[
        0
    ]
    assert 'command = "node"' in fs_block
    assert "args =" in fs_block
    assert "url =" not in fs_block

    # URL server uses url=
    xcode_block = result.split("[mcp_servers.xcode]", 1)[1].split("[mcp_servers.", 1)[0]
    assert 'url = "http://localhost:9876/mcp"' in xcode_block
    assert "command =" not in xcode_block


def test_identity_format_does_not_propagate_master_schema():
    """The identity transform must not leak master's `$schema` into per-tool outputs.

    vscode/github-copilot have their own schema URLs; per-tool base templates
    are the source of truth. If the master ships with a different schema URL
    (e.g. modelcontextprotocol.io), it should NOT end up in those tools'
    config files.
    """
    master = {
        "$schema": "https://modelcontextprotocol.io/schema/config.json",
        "servers": {"a": {"command": "x"}},
    }
    result = transform_to_identity_format(master)
    assert "$schema" not in result
    assert "a" in result["servers"]


def test_identity_format_preserves_other_top_level_keys():
    """`$schema` is the only top-level key we strip — keep the rest."""
    master = {
        "$schema": "https://example.invalid/schema.json",
        "metadata": {"machine": "work"},
        "servers": {"a": {"command": "x"}},
    }
    result = transform_to_identity_format(master)
    assert "$schema" not in result
    assert result["metadata"] == {"machine": "work"}


def test_patch_claude_preserves_key_order(temp_home, monkeypatch_home):
    """patch_claude_code_config must NOT alphabetize ~/.claude.json.

    Claude Code owns this file and writes its own runtime state into it.
    Sorting the whole document on every sync churns the diff and can
    interleave managed keys with Claude's runtime state in confusing ways.
    """
    claude_path = temp_home / ".claude.json"
    # Deliberately non-alphabetical key order
    initial = {
        "version": "1.0",
        "model": "claude-opus-4-5",
        "enabledPlugins": ["github"],
        "mcpServers": {},
    }
    claude_path.write_text(json.dumps(initial, indent=2), encoding="utf-8")

    master = {"servers": {"s": {"command": "x", "args": []}}}
    monkeypatch_home.setattr(Path, "home", lambda: temp_home)
    patch_claude_code_config(master)

    text = claude_path.read_text(encoding="utf-8")
    # `version` (which comes first in the input) must still appear before
    # `enabledPlugins` and `model` (which would come first alphabetically).
    assert text.index('"version"') < text.index('"model"')
    assert text.index('"version"') < text.index('"enabledPlugins"')


def test_patch_claude_managed_server_replaces_existing_entry(
    temp_home, monkeypatch_home, claude_config_template
):
    """A managed server fully replaces the existing entry on collision.

    DOCUMENTED BEHAVIOR: hand-edits to a managed server's fields in
    ~/.claude.json (e.g. tweaking timeout or env) will NOT survive sync.
    Make those changes in master config or in
    dot_config/mcp/overrides/claude.json.

    This test pins the contract so a future "be helpful and merge" change
    doesn't slip in silently.
    """
    claude_path = temp_home / ".claude.json"
    # Pre-existing entry has a hand-edited timeout and a stale env var
    template = dict(claude_config_template)
    template["mcpServers"] = {
        "managed-server": {
            "command": "old-cmd",
            "timeout": 99999,
            "env": {"STALE": "yes"},
        }
    }
    claude_path.write_text(json.dumps(template, indent=2), encoding="utf-8")

    master = {
        "servers": {
            "managed-server": {"command": "new-cmd", "args": []},
        }
    }
    monkeypatch_home.setattr(Path, "home", lambda: temp_home)
    patch_claude_code_config(master)

    result = json.loads(claude_path.read_text())
    entry = result["mcpServers"]["managed-server"]
    # New value wins
    assert entry["command"] == "new-cmd"
    # Hand-edited fields are GONE (this is the documented contract)
    assert "timeout" not in entry
    assert "env" not in entry


def test_full_sync_does_not_propagate_master_schema_to_identity_tools(
    temp_home, monkeypatch_home, master_config_file
):
    """End-to-end: vscode and github-copilot configs do NOT get master's $schema."""
    # Ensure master has a $schema
    master_config_file.write_text(
        json.dumps(
            {
                "$schema": "https://modelcontextprotocol.io/schema/config.json",
                "servers": {"x": {"command": "x"}},
            },
            indent=2,
        ),
        encoding="utf-8",
    )
    from mcp_sync import main

    monkeypatch_home.setattr(Path, "home", lambda: temp_home)
    assert main() == 0

    vscode = json.loads(
        (
            temp_home / "Library" / "Application Support" / "Code" / "User" / "mcp.json"
        ).read_text()
    )
    assert vscode.get("$schema") != "https://modelcontextprotocol.io/schema/config.json"

    gh_copilot = json.loads(
        (temp_home / ".config" / "github-copilot" / "mcp.json").read_text()
    )
    assert (
        gh_copilot.get("$schema")
        != "https://modelcontextprotocol.io/schema/config.json"
    )


if __name__ == "__main__":
    pytest.main([__file__, "-v"])
