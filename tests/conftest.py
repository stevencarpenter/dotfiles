"""Pytest configuration and shared fixtures for MCP sync tests."""

from __future__ import annotations

import json
import sys
from pathlib import Path

import pytest

# Add scripts directory to path so we can import the sync script
sys.path.insert(0, str(Path(__file__).parent.parent / "scripts"))


@pytest.fixture
def temp_home(tmp_path):
    """Create a temporary home directory for testing."""
    home = tmp_path / "home"
    home.mkdir()
    yield home


@pytest.fixture
def master_config():
    """Sample master MCP configuration for testing."""
    return {
        "servers": {
            "filesystem": {
                "command": "node",
                "args": [
                    "/path/to/filesystem-mcp-server/dist/index.js"
                ],
                "type": "local",
                "note": "Local filesystem access"
            },
            "memory": {
                "command": "node",
                "args": [
                    "/path/to/memory-mcp-server/dist/index.js"
                ],
                "type": "local"
            },
            "github": {
                "command": "uv",
                "args": [
                    "run",
                    "github-mcp"
                ],
                "type": "local",
                "env": {
                    "GITHUB_TOKEN": "${GITHUB_TOKEN}"
                }
            },
            "serena": {
                "command": "bash",
                "args": [
                    "-lc",
                    'exec "$HOME/.local/share/chezmoi/scripts/serena-mcp" "$@"',
                    "serena-mcp",
                    "start-mcp-server"
                ],
                "type": "local"
            }
        }
    }


@pytest.fixture
def claude_config_template():
    """Template Claude Code config with existing settings."""
    return {
        "version": "1.0",
        "model": "claude-opus-4-5",
        "enabledPlugins": ["github", "context7"],
        "mcpServers": {
            "old_server": {
                "command": "old",
                "args": ["old"]
            }
        }
    }


@pytest.fixture
def opencode_config_template():
    """Template OpenCode config."""
    return {
        "model": "gpt-4",
        "providers": ["openai"],
        "mcp": {
            "filesystem": {
                "command": ["old", "filesystem"],
                "enabled": True,
                "timeout": 30000
            }
        }
    }


@pytest.fixture
def master_config_file(temp_home, master_config):
    """Create a master config file in temp home."""
    config_dir = temp_home / ".config" / "mcp"
    config_dir.mkdir(parents=True, exist_ok=True)
    config_file = config_dir / "mcp-master.json"
    config_file.write_text(json.dumps(master_config, indent=2), encoding="utf-8")
    return config_file


@pytest.fixture
def monkeypatch_home(monkeypatch, temp_home):
    """Monkeypatch Path.home() to return temp home."""
    monkeypatch.setattr(Path, "home", lambda: temp_home)
    return monkeypatch
