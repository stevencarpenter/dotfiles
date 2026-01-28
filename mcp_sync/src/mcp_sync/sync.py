"""Core MCP synchronization logic."""

from __future__ import annotations

import copy
import json
import shutil
from dataclasses import dataclass
from pathlib import Path
from string import Template as StringTemplate
from string.templatelib import Template
from typing import Any, Callable


type JsonDict = dict[str, Any]
type Transform = Callable[[JsonDict], JsonDict]

TEMPLATES_DIR = Path(__file__).with_name("templates")


@dataclass(frozen=True, slots=True)
class SyncTarget:
    name: str
    destination: Path
    transform: Transform
    context: str | None = None
    template_key: str | None = None
    override_key: str | None = None
    legacy_dir: Path | None = None
    legacy_destination: Path | None = None

    def build(self, master: JsonDict, home: Path | None = None) -> JsonDict:
        template_key = self.template_key or self.name
        override_key = self.override_key or self.name

        base = _load_json_template(template_key, home)
        generated = self.transform(copy.deepcopy(master))
        if self.context:
            generated = set_serena_context(generated, self.context)

        config = deep_merge(base, generated)
        overrides = _load_override(override_key, home)
        if overrides:
            config = deep_merge(config, overrides)
        return config

    def sync(self, master: JsonDict, home: Path | None = None) -> None:
        config = self.build(master, home=home)
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


def _template_vars(home: Path | None) -> dict[str, str]:
    home_path = _home_dir(home)
    return {
        "HOME": str(home_path),
        "XDG_CONFIG_HOME": str(home_path / ".config"),
        "XDG_DATA_HOME": str(home_path / ".local" / "share"),
        "XDG_STATE_HOME": str(home_path / ".local" / "state"),
        "XDG_CACHE_HOME": str(home_path / ".cache"),
    }


def _apply_template(text: str, home: Path | None) -> str:
    return StringTemplate(text).safe_substitute(_template_vars(home))


def _load_json_template(key: str, home: Path | None) -> JsonDict:
    template_path = TEMPLATES_DIR / f"{key}.base.json"
    if not template_path.is_file():
        return {}
    text = template_path.read_text(encoding="utf-8")
    rendered = _apply_template(text, home)
    return json.loads(rendered)


def _load_text_template(key: str, home: Path | None) -> str:
    template_path = TEMPLATES_DIR / f"{key}.base.toml"
    if not template_path.is_file():
        return ""
    text = template_path.read_text(encoding="utf-8")
    return _apply_template(text, home)


def _load_override(key: str, home: Path | None) -> JsonDict:
    home_path = _home_dir(home)
    override_path = home_path / ".config" / "mcp" / "overrides" / f"{key}.json"
    if not override_path.is_file():
        return {}
    try:
        return _load_json(override_path)
    except json.JSONDecodeError:
        log_info(f"Skipping override: {override_path} (invalid JSON)")
        return {}
    except Exception:
        log_info(f"Skipping override: {override_path} (read error)")
        return {}


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


def _merge_lists(base: list[Any], extra: list[Any]) -> list[Any]:
    merged: list[Any] = []
    for item in base:
        if item not in merged:
            merged.append(item)
    for item in extra:
        if item not in merged:
            merged.append(item)
    return merged


def deep_merge(base: JsonDict, override: JsonDict) -> JsonDict:
    result: JsonDict = copy.deepcopy(base)
    for key, value in override.items():
        if key.endswith("+"):
            target = key[:-1]
            existing = result.get(target)
            if isinstance(existing, list) and isinstance(value, list):
                result[target] = _merge_lists(existing, value)
            elif isinstance(value, list):
                result[target] = list(value)
            else:
                result[target] = copy.deepcopy(value)
            continue

        if isinstance(value, dict) and isinstance(result.get(key), dict):
            result[key] = deep_merge(result[key], value)
        else:
            result[key] = copy.deepcopy(value)
    return result


def sync_codex_mcp(master: JsonDict, context: str = "codex", home: Path | None = None) -> None:
    home_path = _home_dir(home)
    codex_config_path = home_path / ".codex" / "config.toml"
    base_text = _load_text_template("codex", home_path)
    if not base_text:
        log_info("Skipping codex config (base template not found)")
        return

    servers = _normalize_servers(master)
    overrides = _load_override("codex", home_path)
    if isinstance(overrides.get("servers"), dict):
        servers = deep_merge(servers, overrides["servers"])

    mcp_section = _render_codex_mcp_section(servers, context)
    text = base_text.rstrip() + "\n" + mcp_section

    codex_config_path.parent.mkdir(parents=True, exist_ok=True)
    codex_config_path.write_text(text, encoding="utf-8")
    log_success(f"Synced MCP servers to: {codex_config_path} (Serena context: {context})")


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
    overrides = _load_override("claude", home_path)
    if overrides:
        claude_cfg = deep_merge(claude_cfg, overrides)

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


def transform_to_opencode_format(master: JsonDict) -> JsonDict:
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

    return {"mcp": mcp}


def sync_opencode_mcp(master: JsonDict, home: Path | None = None) -> None:
    home_path = _home_dir(home)
    target = SyncTarget(
        name="opencode",
        destination=home_path / ".config" / "opencode" / "opencode.json",
        transform=transform_to_opencode_format,
        context="ide",
        template_key="opencode",
        override_key="opencode",
    )
    target.sync(master, home=home_path)
    log_success(
        f"Synced MCP servers to: {target.destination} (Serena context: ide)"
    )


def _build_targets(home: Path) -> list[SyncTarget]:
    return [
        SyncTarget(
            name="copilot-xdg",
            destination=home / ".config" / ".copilot" / "mcp-config.json",
            transform=transform_to_copilot_format,
            context="ide",
            template_key="copilot",
            override_key="copilot",
        ),
        SyncTarget(
            name="github-copilot-intellij",
            destination=home / ".config" / "github-copilot" / "intellij" / "mcp.json",
            transform=_identity,
            context="ide",
            template_key="github-copilot",
            override_key="github-copilot",
        ),
        SyncTarget(
            name="github-copilot",
            destination=home / ".config" / "github-copilot" / "mcp.json",
            transform=_identity,
            context="ide",
            template_key="github-copilot",
            override_key="github-copilot",
        ),
        SyncTarget(
            name="generic-mcp",
            destination=home / ".config" / "mcp" / "mcp_config.json",
            transform=transform_to_generic_mcp_format,
            template_key="generic-mcp",
            override_key="generic-mcp",
        ),
        SyncTarget(
            name="opencode",
            destination=home / ".config" / "opencode" / "opencode.json",
            transform=transform_to_opencode_format,
            context="ide",
            template_key="opencode",
            override_key="opencode",
        ),
        SyncTarget(
            name="cursor",
            destination=home / ".config" / "cursor" / "mcp.json",
            transform=transform_to_mcpservers_format,
            context="ide",
            legacy_dir=home / ".cursor",
            legacy_destination=home / ".cursor" / "mcp.json",
            template_key="cursor",
            override_key="cursor",
        ),
        SyncTarget(
            name="vscode",
            destination=home / ".config" / "vscode" / "mcp.json",
            transform=_identity,
            context="ide",
            legacy_dir=home / ".vscode",
            legacy_destination=home / ".vscode" / "mcp.json",
            template_key="vscode",
            override_key="vscode",
        ),
        SyncTarget(
            name="junie",
            destination=home / ".config" / "junie" / "mcp" / "mcp.json",
            transform=transform_to_mcpservers_format,
            context="agent",
            legacy_dir=home / ".junie",
            legacy_destination=home / ".junie" / "mcp" / "mcp.json",
            template_key="junie",
            override_key="junie",
        ),
        SyncTarget(
            name="lmstudio",
            destination=home / ".config" / "lmstudio" / "mcp.json",
            transform=transform_to_mcpservers_format,
            context="desktop-app",
            legacy_dir=home / ".lmstudio",
            legacy_destination=home / ".lmstudio" / "mcp.json",
            template_key="lmstudio",
            override_key="lmstudio",
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
        target.sync(master, home=home_path)

    sync_codex_mcp(master, "codex", home=home_path)
    patch_claude_code_config(master, home=home_path)
    sync_copilot_cli_config(home=home_path)

    print()
    log_success("MCP configuration sync complete!")
    return 0


def main() -> int:
    return run_sync()
