"""Core MCP synchronization logic."""

from __future__ import annotations

import copy
import json
import re
import shutil
from dataclasses import dataclass
from pathlib import Path
from string.templatelib import Template
from typing import Any, Callable


type JsonDict = dict[str, Any]
type Transform = Callable[[JsonDict], JsonDict]


@dataclass(frozen=True, slots=True)
class SyncTarget:
    name: str
    destination: Path
    transform: Transform
    context: str | None = None
    legacy_dir: Path | None = None
    legacy_destination: Path | None = None

    def build(self, master: JsonDict) -> JsonDict:
        config = self.transform(copy.deepcopy(master))
        if self.context:
            config = set_serena_context(config, self.context)
        return config

    def sync(self, master: JsonDict) -> None:
        config = self.build(master)
        sync_to_locations(config, self.destination, self.legacy_dir, self.legacy_destination)


def _render(template: Template | str) -> str:
    if isinstance(template, str):
        return template
    substitute = getattr(template, "substitute", None)
    if callable(substitute):
        try:
            return substitute()
        except TypeError:
            pass
    return str(template)


def _log(prefix: str, message: str) -> None:
    print(_render(t"{prefix} {message}"))


def log_success(message: str) -> None:
    _log("[ok]", message)


def log_info(message: str) -> None:
    _log("[info]", message)


def log_error(message: str) -> None:
    _log("[error]", message)


def load_master_config(path: Path) -> JsonDict:
    with open(path, encoding="utf-8") as handle:
        return json.load(handle)


def _ensure_mapping(value: Any) -> JsonDict:
    return value if isinstance(value, dict) else {}


def _home_dir(home: Path | None) -> Path:
    return home or Path.home()


def set_serena_context(config: JsonDict, context: str) -> JsonDict:
    serena: JsonDict | None = None
    use_command_key = False

    servers = _ensure_mapping(config.get("servers"))
    mcp_servers = _ensure_mapping(config.get("mcpServers"))
    mcp = _ensure_mapping(config.get("mcp"))

    if "serena" in servers:
        serena = servers["serena"]
    elif "serena" in mcp_servers:
        serena = mcp_servers["serena"]
    elif "serena" in mcp:
        serena = mcp["serena"]
        if isinstance(serena.get("command"), list):
            serena["args"] = list(serena["command"])
            use_command_key = True

    if serena is None:
        return config

    args = serena.get("args", [])
    if not isinstance(args, list):
        return config

    context_arg = f"--context={context}"
    for idx, arg in enumerate(args):
        if isinstance(arg, str) and arg.startswith("--context="):
            args[idx] = context_arg
            break
    else:
        args.append(context_arg)

    serena["args"] = args

    if use_command_key:
        config["mcp"]["serena"]["command"] = args

    return config


def _identity(master: JsonDict) -> JsonDict:
    return master


def _normalize_servers(master: JsonDict) -> JsonDict:
    return _ensure_mapping(master.get("servers"))


def sync_codex_mcp(master: JsonDict, context: str = "codex", home: Path | None = None) -> None:
    home_path = _home_dir(home)
    codex_config_path = home_path / ".codex" / "config.toml"
    if not codex_config_path.is_file():
        log_info(f"Skipping: {codex_config_path} (file not found)")
        return

    text = codex_config_path.read_text(encoding="utf-8")

    text = _remove_toml_sections(text, "mcp_servers")
    text = re.sub(r"\n\n\n+", "\n\n", text)

    servers = _normalize_servers(master)
    mcp_section = _render_codex_mcp_section(servers, context)

    if not text.endswith("\n"):
        text += "\n"
    text += mcp_section

    codex_config_path.write_text(text, encoding="utf-8")
    log_success(f"Synced MCP servers to: {codex_config_path} (Serena context: {context})")


def _remove_toml_sections(text: str, section_prefix: str) -> str:
    pattern = rf"(?ms)^\[{re.escape(section_prefix)}\.[^\]]*\].*?(?=^\[|\Z)"
    return re.sub(pattern, "", text)


def _toml_string(value: str) -> str:
    return '"' + value.replace("\\", "\\\\").replace('"', '\\"') + '"'


def _render_codex_mcp_section(servers: JsonDict, context: str) -> str:
    lines: list[str] = ["", "# MCP Servers"]

    for name, server in servers.items():
        lines.append("")
        lines.append(f"[mcp_servers.{name}]")
        lines.append(f"command = {_toml_string(str(server.get('command', '')))}")

        args = list(server.get("args", []) or [])
        if name == "serena":
            context_arg = f"--context={context}"
            if context_arg not in args:
                args.append(context_arg)

        args_str = ", ".join(_toml_string(str(arg)) for arg in args)
        lines.append(f"args = [{args_str}]")

        env = server.get("env")
        if isinstance(env, dict):
            env_parts = [f"{key} = {_toml_string(str(value))}" for key, value in env.items()]
            lines.append(f"environment = {{ {', '.join(env_parts)} }}")

    return "\n".join(lines) + "\n"


def merge_claude_code_plugins(claude_cfg: JsonDict, home: Path | None = None) -> JsonDict:
    home_path = _home_dir(home)
    chezmoi_dir = home_path / ".local" / "share" / "chezmoi"
    plugins_config_path = chezmoi_dir / "scripts" / "claude-enabled-plugins.json"

    if not plugins_config_path.is_file():
        return claude_cfg

    try:
        with open(plugins_config_path, encoding="utf-8") as handle:
            plugins_dict = json.load(handle)

        if isinstance(plugins_dict, dict) and plugins_dict:
            current_plugins = _normalize_plugins(claude_cfg.get("enabledPlugins"))
            merged_plugins = {**current_plugins, **plugins_dict}
            claude_cfg["enabledPlugins"] = merged_plugins
            log_success(f"Synced enabledPlugins: {len(plugins_dict)} canonical plugins")
    except json.JSONDecodeError:
        log_info(f"Skipping plugins: {plugins_config_path} (invalid JSON)")
    except Exception:
        log_info(f"Skipping plugins: {plugins_config_path} (read error)")

    return claude_cfg


def _normalize_plugins(value: Any) -> dict[str, bool]:
    if isinstance(value, dict):
        return {str(key): bool(val) for key, val in value.items()}
    if isinstance(value, list):
        return {str(item): True for item in value if isinstance(item, str)}
    return {}


def sync_copilot_cli_config(home: Path | None = None) -> None:
    home_path = _home_dir(home)
    copilot_config_path = home_path / ".config" / ".copilot" / "config.json"
    copilot_backup_path = home_path / ".config" / ".copilot" / "config.backup.json"

    if not copilot_config_path.is_file():
        log_info(f"Skipping: {copilot_config_path} (file not found)")
        return

    try:
        deployed_config = _load_json(copilot_config_path)
        auth_tokens: dict[str, Any] | None = None

        if copilot_backup_path.is_file():
            try:
                backup_config = _load_json(copilot_backup_path)
                auth_tokens = {
                    "logged_in_users": backup_config.get("logged_in_users", []),
                    "last_logged_in_user": backup_config.get("last_logged_in_user"),
                }
            except (json.JSONDecodeError, OSError):
                log_info(f"Skipping auth restore: {copilot_backup_path} (invalid or missing)")

        if auth_tokens:
            deployed_config["logged_in_users"] = auth_tokens.get("logged_in_users", [])
            if auth_tokens.get("last_logged_in_user"):
                deployed_config["last_logged_in_user"] = auth_tokens["last_logged_in_user"]

        _write_json(copilot_config_path, deployed_config)
        _write_json(copilot_backup_path, deployed_config)
        log_success(f"Preserved auth tokens in: {copilot_config_path}")
    except Exception as exc:
        log_info(f"Warning: Could not preserve Copilot auth tokens: {exc}")


def _load_json(path: Path) -> JsonDict:
    with open(path, encoding="utf-8") as handle:
        return json.load(handle)


def _write_json(path: Path, payload: JsonDict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    serialized = json.dumps(payload, indent=2, sort_keys=True)
    path.write_text(serialized + "\n", encoding="utf-8")


def patch_claude_code_config(master: JsonDict, home: Path | None = None) -> None:
    home_path = _home_dir(home)
    claude_path = home_path / ".claude.json"
    if not claude_path.is_file():
        log_info(f"Skipping: {claude_path} (file not found)")
        return

    claude_cfg = _load_json(claude_path)

    servers = _normalize_servers(master)
    servers = {key: {k: v for k, v in val.items() if k != "note"} for key, val in servers.items()}

    existing = _ensure_mapping(claude_cfg.get("mcpServers"))
    claude_cfg["mcpServers"] = {**existing, **servers}
    claude_cfg = set_serena_context(claude_cfg, "claude-code")
    claude_cfg = merge_claude_code_plugins(claude_cfg, home=home_path)

    _write_json(claude_path, claude_cfg)
    log_success(f"Synced: {claude_path} (Serena context: claude-code)")


def sync_to_locations(
    config: JsonDict,
    xdg_target: Path,
    legacy_dir: Path | None = None,
    legacy_target: Path | None = None,
) -> None:
    _write_json(xdg_target, config)
    log_success(f"Synced: {xdg_target}")

    if legacy_dir and legacy_target and legacy_dir.is_dir():
        legacy_target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(xdg_target, legacy_target)
        log_success(f"Synced: {legacy_target} (legacy)")


def transform_to_copilot_format(master: JsonDict) -> JsonDict:
    servers = _normalize_servers(master)
    mcp_servers: JsonDict = {}
    for name, server in servers.items():
        mcp_servers[name] = {
            **server,
            "tools": ["*"],
            "type": server.get("type", "local"),
        }
    return {"mcpServers": mcp_servers}


def transform_to_generic_mcp_format(master: JsonDict) -> JsonDict:
    return {
        "$schema": "https://modelcontextprotocol.io/schema/config.json",
        "mcpServers": _normalize_servers(master),
    }


def transform_to_mcpservers_format(master: JsonDict) -> JsonDict:
    return {"mcpServers": _normalize_servers(master)}


def transform_to_opencode_format(master: JsonDict, existing_config: JsonDict) -> JsonDict:
    servers = _normalize_servers(master)
    mcp: JsonDict = {}
    for name, server in servers.items():
        command = server.get("command")
        args = list(server.get("args", []) or [])
        cmd_array = [command, *args] if command else args

        entry: JsonDict = {
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


def sync_opencode_mcp(master: JsonDict, home: Path | None = None) -> None:
    home_path = _home_dir(home)
    opencode_config_path = home_path / ".config" / "opencode" / "opencode.json"
    if not opencode_config_path.is_file():
        log_info(f"Skipping: {opencode_config_path} (file not found)")
        return

    opencode_config = _load_json(opencode_config_path)

    opencode_config = transform_to_opencode_format(master, opencode_config)
    opencode_config = set_serena_context(opencode_config, "ide")

    _write_json(opencode_config_path, opencode_config)
    log_success(f"Synced MCP servers to: {opencode_config_path} (Serena context: ide)")


def _build_targets(home: Path) -> list[SyncTarget]:
    return [
        SyncTarget(
            name="copilot-xdg",
            destination=home / ".config" / ".copilot" / "mcp-config.json",
            transform=transform_to_copilot_format,
            context="ide",
        ),
        SyncTarget(
            name="github-copilot-intellij",
            destination=home / ".config" / "github-copilot" / "intellij" / "mcp.json",
            transform=_identity,
            context="ide",
        ),
        SyncTarget(
            name="github-copilot",
            destination=home / ".config" / "github-copilot" / "mcp.json",
            transform=_identity,
            context="ide",
        ),
        SyncTarget(
            name="generic-mcp",
            destination=home / ".config" / "mcp" / "mcp_config.json",
            transform=transform_to_generic_mcp_format,
        ),
        SyncTarget(
            name="cursor",
            destination=home / ".config" / "cursor" / "mcp.json",
            transform=transform_to_mcpservers_format,
            context="ide",
            legacy_dir=home / ".cursor",
            legacy_destination=home / ".cursor" / "mcp.json",
        ),
        SyncTarget(
            name="vscode",
            destination=home / ".config" / "vscode" / "mcp.json",
            transform=_identity,
            context="ide",
            legacy_dir=home / ".vscode",
            legacy_destination=home / ".vscode" / "mcp.json",
        ),
        SyncTarget(
            name="junie",
            destination=home / ".config" / "junie" / "mcp" / "mcp.json",
            transform=transform_to_mcpservers_format,
            context="agent",
            legacy_dir=home / ".junie",
            legacy_destination=home / ".junie" / "mcp" / "mcp.json",
        ),
        SyncTarget(
            name="lmstudio",
            destination=home / ".config" / "lmstudio" / "mcp.json",
            transform=transform_to_mcpservers_format,
            context="desktop-app",
            legacy_dir=home / ".lmstudio",
            legacy_destination=home / ".lmstudio" / "mcp.json",
        ),
    ]


def run_sync(master_path: Path | None = None, home: Path | None = None) -> int:
    home_path = home or Path.home()
    master_config_path = master_path or home_path / ".config" / "mcp" / "mcp-master.json"

    if not master_config_path.is_file():
        log_error(f"Master config not found at {master_config_path}")
        log_info("Run 'chezmoi apply' to deploy dotfiles first")
        return 1

    log_info("Syncing MCP configurations from master...")
    master = load_master_config(master_config_path)

    for target in _build_targets(home_path):
        target.sync(master)

    sync_codex_mcp(master, "codex", home=home_path)
    patch_claude_code_config(master, home=home_path)
    sync_opencode_mcp(master, home=home_path)
    sync_copilot_cli_config(home=home_path)

    print()
    log_success("MCP configuration sync complete!")
    return 0


def main() -> int:
    return run_sync()
