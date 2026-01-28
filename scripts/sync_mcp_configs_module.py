"""
Importable module version of sync-mcp-configs.py for testing and internal use.

This module contains the core functionality of the MCP configuration sync script,
making it possible to import and test the functions directly.
"""

from __future__ import annotations

import copy
import json
import re
import shutil
import sys
from pathlib import Path
from typing import Any

# Colors for output (same style as original bash script)
GREEN = "\033[0;32m"
YELLOW = "\033[1;33m"
NC = "\033[0m"  # No Color


def log_success(msg: str) -> None:
    print(f"{GREEN}✓{NC} {msg}")


def log_info(msg: str) -> None:
    print(f"{YELLOW}→{NC} {msg}")


def load_master_config(path: Path) -> dict[str, Any]:
    with open(path, encoding="utf-8") as f:
        return json.load(f)


def set_serena_context(config: dict[str, Any], context: str) -> dict[str, Any]:
    """
    Add or update the --context argument in Serena's args array.
    Supports:
      - {servers:{serena:{args:[...]}}}
      - {mcpServers:{serena:{args:[...]}}}
      - OpenCode: {mcp:{serena:{command:[...]}}}
    """
    serena: dict[str, Any] | None = None
    use_command_key = False

    if "servers" in config and "serena" in (config["servers"] or {}):
        serena = config["servers"]["serena"]
    elif "mcpServers" in config and "serena" in (config["mcpServers"] or {}):
        serena = config["mcpServers"]["serena"]
    elif "mcp" in config and "serena" in (config["mcp"] or {}):
        serena = config["mcp"]["serena"]
        if "command" in serena and isinstance(serena["command"], list):
            serena["args"] = serena["command"]
            use_command_key = True

    if serena is None:
        return config

    args = serena.get("args", [])
    if not isinstance(args, list):
        return config

    context_arg = f"--context={context}"
    updated = False
    for i, arg in enumerate(args):
        if isinstance(arg, str) and arg.startswith("--context="):
            args[i] = context_arg
            updated = True
            break

    if not updated:
        args.append(context_arg)

    serena["args"] = args

    if use_command_key:
        config["mcp"]["serena"]["command"] = args

    return config


def sync_codex_mcp(master: dict[str, Any], context: str = "codex") -> None:
    """
    Sync all MCP servers from master config to Codex CLI configuration.

    Updates ~/.codex/config.toml with MCP servers from master config,
    removing old server sections and adding new ones based on the master config.
    Preserves all non-MCP configuration (model, projects, notice, etc.).

    Args:
        master: Master MCP configuration
        context: Context for Serena MCP server (default: "codex")
    """
    codex_config_path = Path.home() / ".codex" / "config.toml"
    if not codex_config_path.is_file():
        log_info(f"Skipping: {codex_config_path} (file not found)")
        return

    text = codex_config_path.read_text(encoding="utf-8")

    # Remove all existing mcp_servers.* sections
    text = re.sub(r"(?ms)^\[mcp_servers\.[^\]]*\].*?(?=^\[|\Z)", "", text)
    # Clean up extra blank lines created by removal
    text = re.sub(r"\n\n\n+", "\n\n", text)

    # Build MCP servers section
    servers = master.get("servers", {}) or {}

    def toml_string(value: str) -> str:
        return '"' + value.replace("\\", "\\\\").replace('"', '\\"') + '"'

    mcp_section = "\n# MCP Servers\n"
    for name, server in servers.items():
        mcp_section += f"\n[mcp_servers.{name}]\n"
        mcp_section += f"command = {toml_string(server.get('command', ''))}\n"

        args = server.get("args", []) or []
        # Special handling for Serena: add context argument
        if name == "serena":
            context_arg = f"--context={context}"
            if context_arg not in args:
                args = list(args) + [context_arg]

        args_str = "[" + ", ".join(toml_string(arg) for arg in args) + "]"
        mcp_section += f"args = {args_str}\n"

        if "env" in server:
            mcp_section += "environment = { "
            env_parts = []
            for env_key, env_val in server["env"].items():
                env_parts.append(f'{env_key} = {toml_string(env_val)}')
            mcp_section += ", ".join(env_parts)
            mcp_section += " }\n"

    # Append MCP section to end of config
    if not text.endswith("\n"):
        text += "\n"
    text += mcp_section

    codex_config_path.write_text(text, encoding="utf-8")
    log_success(f"Synced MCP servers to: {codex_config_path} (Serena context: {context})")


def ensure_codex_serena_server(config_path: Path, context: str) -> None:
    """
    Deprecated: Use sync_codex_mcp() instead.

    Ensure Codex has a working Serena MCP server entry.
    This function is kept for backward compatibility but is no longer used.
    """
    log_info(f"Note: ensure_codex_serena_server() is deprecated, use sync_codex_mcp() instead")


def merge_claude_code_plugins(claude_cfg: dict[str, Any]) -> dict[str, Any]:
    """
    Merge enabled plugins from the canonical plugins config into Claude Code config.

    Reads from scripts/claude-enabled-plugins.json (not deployed by chezmoi, only used
    by this sync script) and merges the enabled plugins into ~/.claude/settings.json.

    The plugins config is a dict mapping plugin identifiers to boolean values:
    {
      "context7@claude-plugins-official": true,
      "github@claude-plugins-official": true,
      ...
    }
    """
    # Look in scripts directory - this file is only for MCP sync, not chezmoi deployment
    chezmoi_dir = Path.home() / ".local" / "share" / "chezmoi"
    plugins_config_path = chezmoi_dir / "scripts" / "claude-enabled-plugins.json"

    if not plugins_config_path.is_file():
        # No plugins file, leave enabledPlugins untouched
        return claude_cfg

    try:
        with open(plugins_config_path, encoding="utf-8") as f:
            plugins_dict = json.load(f)

        # plugins_dict should be {plugin_id: bool, ...}
        if isinstance(plugins_dict, dict) and plugins_dict:
            # Merge into existing enabledPlugins, preserving any manually-set values
            current_plugins = claude_cfg.get("enabledPlugins", {}) or {}
            if not isinstance(current_plugins, dict):
                current_plugins = {}

            # Merge: our canonical plugins override, but preserve manually-added ones
            merged_plugins = {**current_plugins, **plugins_dict}
            claude_cfg["enabledPlugins"] = merged_plugins
            log_success(f"Synced enabledPlugins: {len(plugins_dict)} canonical plugins")
    except json.JSONDecodeError:
        log_info(f"Skipping plugins: {plugins_config_path} (invalid JSON)")
    except Exception:
        log_info(f"Skipping plugins: {plugins_config_path} (read error)")

    return claude_cfg


def sync_copilot_cli_config(master: dict[str, Any] | None = None) -> None:
    """
    Preserve OAuth tokens in GitHub Copilot CLI config after chezmoi deployment.

    Chezmoi deploys ~/.config/.copilot/config.json from template, which doesn't
    include OAuth tokens (they're sensitive). This function:
    1. Reads config deployed by chezmoi (has structure, no auth tokens)
    2. Reads backup of previous config (has OAuth tokens)
    3. Merges tokens back into deployed config
    4. Preserves any manually-updated settings

    This is called after chezmoi apply to restore authentication state.
    """
    copilot_config_path = Path.home() / ".config" / ".copilot" / "config.json"
    copilot_backup_path = Path.home() / ".config" / ".copilot" / "config.backup.json"

    if not copilot_config_path.is_file():
        log_info(f"Skipping: {copilot_config_path} (file not found)")
        return

    try:
        # Read newly deployed config
        with open(copilot_config_path, encoding="utf-8") as f:
            deployed_config = json.load(f)

        # Try to read backup of previous config (has auth tokens)
        auth_tokens = None
        if copilot_backup_path.is_file():
            try:
                with open(copilot_backup_path, encoding="utf-8") as f:
                    backup_config = json.load(f)
                    # Extract auth tokens from backup
                    auth_tokens = {
                        "logged_in_users": backup_config.get("logged_in_users", []),
                        "last_logged_in_user": backup_config.get("last_logged_in_user"),
                    }
            except (json.JSONDecodeError, IOError):
                log_info(f"Skipping auth restore: {copilot_backup_path} (invalid or missing)")

        # Merge auth tokens back if we found them
        if auth_tokens:
            deployed_config["logged_in_users"] = auth_tokens.get("logged_in_users", [])
            if auth_tokens.get("last_logged_in_user"):
                deployed_config["last_logged_in_user"] = auth_tokens["last_logged_in_user"]

        # Write back merged config
        with open(copilot_config_path, "w", encoding="utf-8") as f:
            json.dump(deployed_config, f, indent=2)

        # Create backup of current config for next run
        # (This will be used the next time chezmoi apply is run)
        copilot_config_path.parent.mkdir(parents=True, exist_ok=True)
        with open(copilot_backup_path, "w", encoding="utf-8") as f:
            json.dump(deployed_config, f, indent=2)

        log_success(f"Preserved auth tokens in: {copilot_config_path}")
    except Exception as e:
        log_info(f"Warning: Could not preserve Copilot auth tokens: {e}")


def patch_claude_code_config(master: dict[str, Any]) -> None:
    """
    Patch Claude Code's ~/.claude.json mcpServers in-place.

    This file changes frequently (model, projects, onboarding state, etc.), so we
    only update the mcpServers subtree and optionally merge enabledPlugins.
    """
    claude_path = Path.home() / ".claude.json"
    if not claude_path.is_file():
        log_info(f"Skipping: {claude_path} (file not found)")
        return

    with open(claude_path, encoding="utf-8") as f:
        claude_cfg = json.load(f)

    servers = master.get("servers", {})
    servers = {k: {kk: vv for kk, vv in v.items() if kk != "note"} for k, v in servers.items()}

    claude_cfg["mcpServers"] = {**(claude_cfg.get("mcpServers") or {}), **servers}
    claude_cfg = set_serena_context(claude_cfg, "claude-code")
    claude_cfg = merge_claude_code_plugins(claude_cfg)

    with open(claude_path, "w", encoding="utf-8") as f:
        json.dump(claude_cfg, f, indent=2)
    log_success(f"Synced: {claude_path} (Serena context: claude-code)")


def sync_to_locations(
    config: dict[str, Any],
    xdg_target: Path,
    legacy_dir: Path | None = None,
    legacy_target: Path | None = None,
) -> None:
    xdg_target.parent.mkdir(parents=True, exist_ok=True)
    with open(xdg_target, "w", encoding="utf-8") as f:
        json.dump(config, f, indent=2)
    log_success(f"Synced: {xdg_target}")

    if legacy_dir and legacy_target and legacy_dir.is_dir():
        legacy_target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy(xdg_target, legacy_target)
        log_success(f"Synced: {legacy_target} (legacy)")


def transform_to_copilot_format(master: dict[str, Any]) -> dict[str, Any]:
    servers = master.get("servers", {}) or {}
    mcp_servers: dict[str, Any] = {}
    for name, server in servers.items():
        mcp_servers[name] = {
            **server,
            "tools": ["*"],
            "type": server.get("type", "local"),
        }
    return {"mcpServers": mcp_servers}


def transform_to_generic_mcp_format(master: dict[str, Any]) -> dict[str, Any]:
    return {
        "$schema": "https://modelcontextprotocol.io/schema/config.json",
        "mcpServers": master.get("servers", {}) or {},
    }


def transform_to_mcpservers_format(master: dict[str, Any]) -> dict[str, Any]:
    return {"mcpServers": master.get("servers", {}) or {}}


def transform_to_opencode_format(
    master: dict[str, Any], existing_config: dict[str, Any]
) -> dict[str, Any]:
    servers = master.get("servers", {}) or {}
    mcp: dict[str, Any] = {}
    for name, server in servers.items():
        command = server.get("command")
        args = server.get("args", []) or []
        cmd_array = [command] + args if command else args

        entry: dict[str, Any] = {
            "type": "local",
            "command": cmd_array,
            "enabled": True,
            "timeout": 30000,
        }
        if "env" in server:
            entry["environment"] = server["env"]
        mcp[name] = entry

    existing_config["mcp"] = mcp
    return existing_config


def sync_opencode_mcp(master: dict[str, Any]) -> None:
    """
    Sync MCP servers to OpenCode configuration.

    Updates ~/.config/opencode/opencode.json with MCP servers from master config,
    ensuring Serena has the correct IDE context.
    """
    opencode_config_path = Path.home() / ".config" / "opencode" / "opencode.json"
    if not opencode_config_path.is_file():
        log_info(f"Skipping: {opencode_config_path} (file not found)")
        return

    with open(opencode_config_path, encoding="utf-8") as f:
        opencode_config = json.load(f)

    # Transform master config to OpenCode format and merge MCP servers
    opencode_config = transform_to_opencode_format(master, opencode_config)
    opencode_config = set_serena_context(opencode_config, "ide")

    with open(opencode_config_path, "w", encoding="utf-8") as f:
        json.dump(opencode_config, f, indent=2)
    log_success(f"Synced MCP servers to: {opencode_config_path} (Serena context: ide)")


def main() -> int:
    home = Path.home()
    master_config_path = home / ".config" / "mcp" / "mcp-master.json"

    if not master_config_path.is_file():
        print(f"Error: Master config not found at {master_config_path}")
        print("Run 'chezmoi apply' to deploy dotfiles first")
        return 1

    log_info("Syncing MCP configurations from master...")
    master = load_master_config(master_config_path)

    # 1. Copilot (GitHub Copilot) - mcpServers format with tools array
    config = transform_to_copilot_format(master)
    config = set_serena_context(config, "ide")
    sync_to_locations(config, home / ".config" / ".copilot" / "mcp-config.json")

    # 2. GitHub Copilot (IntelliJ) - servers format (same as master)
    config = copy.deepcopy(master)
    config = set_serena_context(config, "ide")
    sync_to_locations(config, home / ".config" / "github-copilot" / "intellij" / "mcp.json")

    # 3. GitHub Copilot (general) - servers format with IDE context
    config = copy.deepcopy(master)
    config = set_serena_context(config, "ide")
    sync_to_locations(config, home / ".config" / "github-copilot" / "mcp.json")

    # 4. Generic MCP config (for other tools) - servers format, no context
    config = transform_to_generic_mcp_format(master)
    sync_to_locations(config, home / ".config" / "mcp" / "mcp_config.json")

    # 5. Codex CLI - sync all MCP servers with codex context
    sync_codex_mcp(master, "codex")

    # 5b. Claude Code - patch ~/.claude.json (only touches mcpServers)
    patch_claude_code_config(master)

    # 6. OpenCode - syncs MCP servers with IDE context
    sync_opencode_mcp(master)

    # 7. Cursor - mcpServers format with IDE context (XDG + legacy mirror)
    config = transform_to_mcpservers_format(master)
    config = set_serena_context(config, "ide")
    sync_to_locations(
        config,
        home / ".config" / "cursor" / "mcp.json",
        home / ".cursor",
        home / ".cursor" / "mcp.json",
    )

    # 8. VSCode - servers format with IDE context (XDG + legacy mirror)
    config = copy.deepcopy(master)
    config = set_serena_context(config, "ide")
    sync_to_locations(
        config,
        home / ".config" / "vscode" / "mcp.json",
        home / ".vscode",
        home / ".vscode" / "mcp.json",
    )

    # 9. Junie - mcpServers format with agent context (XDG + legacy mirror)
    config = transform_to_mcpservers_format(master)
    config = set_serena_context(config, "agent")
    sync_to_locations(
        config,
        home / ".config" / "junie" / "mcp" / "mcp.json",
        home / ".junie",
        home / ".junie" / "mcp" / "mcp.json",
    )

    # 10. LM Studio - mcpServers format with desktop-app context (XDG + legacy mirror)
    config = transform_to_mcpservers_format(master)
    config = set_serena_context(config, "desktop-app")
    sync_to_locations(
        config,
        home / ".config" / "lmstudio" / "mcp.json",
        home / ".lmstudio",
        home / ".lmstudio" / "mcp.json",
    )

    # 11. GitHub Copilot CLI - preserve OAuth tokens after chezmoi deployment
    sync_copilot_cli_config()

    print()
    log_success("MCP configuration sync complete!")
    return 0


if __name__ == "__main__":
    sys.exit(main())
