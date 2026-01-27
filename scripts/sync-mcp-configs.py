#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.14"
# dependencies = []
# ///
"""
Synchronize MCP configurations across different AI tool formats.
This ensures all tools use the same MCP server definitions.
"""

from __future__ import annotations

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


def ensure_codex_serena_server(config_path: Path, context: str) -> None:
    """
    Ensure Codex has a working Serena MCP server entry.

    We intentionally only touch the [mcp_servers.serena] section so Codex can
    keep its own frequently-mutated settings without triggering chezmoi drift prompts.
    """
    text = config_path.read_text(encoding="utf-8")

    section_re = re.compile(
        r"(?ms)^[ \t]*\[mcp_servers\.serena][ \t]*\n(?P<body>.*?)(?=^[ \t]*\[|\Z)"
    )
    m = section_re.search(text)

    desired_args = [
        "-lc",
        'exec "$HOME/.local/share/chezmoi/scripts/serena-mcp" "$@"',
        "serena-mcp",
        "start-mcp-server",
        "--project-from-cwd",
        "--mode=interactive",
        "--mode=editing",
        "--language-backend=JetBrains",
        f"--context={context}",
    ]

    def toml_string(value: str) -> str:
        return '"' + value.replace("\\", "\\\\").replace('"', '\\"') + '"'

    desired_command_line = f"command = {toml_string('bash')}\n"
    desired_args_line = "args = [" + ", ".join(toml_string(v) for v in desired_args) + "]\n"

    if not m:
        if not text.endswith("\n"):
            text += "\n"
        text += "\n[mcp_servers.serena]\n" + desired_command_line + desired_args_line
        config_path.write_text(text, encoding="utf-8")
        return

    body = m.group("body")

    def replace_or_add_line(section_body: str, key: str, value_line: str) -> str:
        if re.search(rf"(?m)^[ \t]*{re.escape(key)}[ \t]*=", section_body):
            section_body = re.sub(
                rf"(?m)^[ \t]*{re.escape(key)}[ \t]*=.*$",
                value_line.strip(),
                section_body,
            )
            if not section_body.endswith("\n"):
                section_body += "\n"
            return section_body
        return value_line + section_body

    body = replace_or_add_line(body, "command", desired_command_line)

    # Replace args (handle single/multi-line arrays). If parsing fails, just overwrite the args line.
    if re.search(r"(?m)^[ \t]*args[ \t]*=", body):
        body = re.sub(r"(?ms)^[ \t]*args[ \t]*=.*?]\s*$", desired_args_line.strip(), body)
        if not body.endswith("\n"):
            body += "\n"
    else:
        body = desired_args_line + body

    new_text = text[: m.start("body")] + body + text[m.end("body") :]
    config_path.write_text(new_text, encoding="utf-8")


def patch_claude_code_config(master: dict[str, Any]) -> None:
    """
    Patch Claude Code's ~/.claude.json mcpServers in-place.

    This file changes frequently (model, projects, onboarding state, etc.), so we
    only update the mcpServers subtree.
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
    config = dict(master)
    config = set_serena_context(config, "ide")
    sync_to_locations(config, home / ".config" / "github-copilot" / "intellij" / "mcp.json")

    # 3. GitHub Copilot (general) - servers format with IDE context
    config = dict(master)
    config = set_serena_context(config, "ide")
    sync_to_locations(config, home / ".config" / "github-copilot" / "mcp.json")

    # 4. Generic MCP config (for other tools) - servers format, no context
    config = transform_to_generic_mcp_format(master)
    sync_to_locations(config, home / ".config" / "mcp" / "mcp_config.json")

    # 5. Codex CLI - ensure Serena entry with codex context
    codex_config = home / ".codex" / "config.toml"
    if codex_config.is_file():
        ensure_codex_serena_server(codex_config, "codex")
        log_success(f"Ensured Serena in: {codex_config} (context: codex)")
    else:
        log_info(f"Skipping: {codex_config} (file not found)")

    # 5b. Claude Code - patch ~/.claude.json (only touches mcpServers)
    patch_claude_code_config(master)

    # 6. OpenCode - inherits MCP servers with IDE context
    opencode_config_path = home / ".config" / "opencode" / "opencode.json"
    if opencode_config_path.is_file():
        with open(opencode_config_path, encoding="utf-8") as f:
            opencode_config = json.load(f)
        if "mcp" in opencode_config:
            opencode_config = transform_to_opencode_format(master, opencode_config)
            opencode_config = set_serena_context(opencode_config, "ide")
            with open(opencode_config_path, "w", encoding="utf-8") as f:
                json.dump(opencode_config, f, indent=2)
            log_success(f"Synced MCP servers to: {opencode_config_path} (Serena context: ide)")
        else:
            log_info("OpenCode config exists but has no mcp section")
    else:
        log_info(f"Skipping: {opencode_config_path} (file not found)")

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
    config = dict(master)
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

    print()
    log_success("MCP configuration sync complete!")
    return 0


if __name__ == "__main__":
    sys.exit(main())

