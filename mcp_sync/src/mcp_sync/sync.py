"""Core MCP synchronization logic."""

from __future__ import annotations

import copy
import json
import os
import tempfile
from collections.abc import Callable
from dataclasses import dataclass
from pathlib import Path
from string import Template as StringTemplate
from typing import Any

from mcp_sync.codex_tui import apply_tui_settings, toml_string

type JsonDict = dict[str, Any]
type Transform = Callable[[JsonDict], JsonDict]

TEMPLATES_DIR = Path(__file__).with_name("templates")
CODEX_MCP_BEGIN_MARKER = "# MCP Servers - BEGIN Codex"
CODEX_MCP_END_MARKER = "# MCP Servers - END Codex"
RETIRED_MCP_SERVER_NAMES = frozenset({"github", "xcode"})

# Timeout stamped onto local servers in the opencode output (milliseconds).
_OPENCODE_TIMEOUT_MS = 30_000


@dataclass(frozen=True, slots=True)
class SyncTarget:
    name: str
    destination: Path
    transform: Transform
    template_key: str | None = None
    override_key: str | None = None

    def build(self, master: JsonDict, home: Path | None = None) -> JsonDict:
        template_key = self.template_key or self.name
        override_key = self.override_key or self.name

        overrides = _load_override(override_key, home)
        merged_master = _master_with_servers(
            master, _merge_override_servers(master, overrides)
        )
        base = _load_json_template(template_key, home)
        generated = self.transform(merged_master)

        config = deep_merge(base, generated)
        cleaned_overrides = _override_without_servers(overrides)
        if cleaned_overrides:
            config = deep_merge(config, cleaned_overrides)
        return _remove_retired_server_entries(config)

    def sync(self, master: JsonDict, home: Path | None = None) -> None:
        config = self.build(master, home=home)
        sync_to_locations(config, self.destination)


@dataclass(frozen=True, slots=True)
class SyncDestination:
    """One file ``run_sync`` writes.

    Attributes:
        name: Target name used by ``--check`` and ``--capture``.
        path: Absolute destination under the given home.
        kind: ``"wholesale"`` for a generated file; ``"patch"`` for a
            co-owned file updated in place.
    """

    name: str
    path: Path
    kind: str


def _log(prefix: str, message: str) -> None:
    print(f"{prefix} {message}")


def log_success(message: str) -> None:
    _log("[ok]", message)


def log_info(message: str) -> None:
    _log("[info]", message)


def log_error(message: str) -> None:
    _log("[error]", message)


def load_master_config(path: Path) -> JsonDict:
    """Load the master MCP config document.

    Args:
        path: Path to ``mcp-master.json``.

    Returns:
        The parsed master config.
    """
    return _load_json(path)


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
        return _load_json_object(override_path)
    except (json.JSONDecodeError, ValueError):
        log_info(
            f"Skipping override: {override_path} (invalid JSON or non-object root)"
        )
        return {}
    except OSError:
        log_info(f"Skipping override: {override_path} (read error)")
        return {}


def load_machine_config(path: Path | None) -> JsonDict:
    """Load machine-type overlay config (work.json / personal.json).

    Returns empty dict if path is None, file doesn't exist, or JSON is invalid.
    """
    if path is None:
        return {}
    if not path.is_file():
        return {}
    try:
        return _load_json_object(path)
    except (json.JSONDecodeError, ValueError):
        log_info(f"Skipping machine config: {path} (invalid JSON or non-object root)")
        return {}
    except OSError:
        log_info(f"Skipping machine config: {path} (read error)")
        return {}


def load_merged_master(
    master_path: Path | None,
    home: Path,
    machine_config_path: Path | None,
) -> JsonDict | None:
    """Load the master config with the machine overlay merged on top.

    Shared by every CLI entry point (sync, ``--check``, ``--capture``) so the
    default master location, the missing-master error, and the overlay-merge
    semantics cannot drift between them.

    Args:
        master_path: Master config location override; defaults to
            ``<home>/.config/mcp/mcp-master.json``.
        home: Home directory used to resolve the default master location.
        machine_config_path: Optional machine overlay merged over the master.

    Returns:
        The merged master document, or ``None`` (after logging the error)
        when the master config is absent.
    """
    master_config_path = master_path or home / ".config" / "mcp" / "mcp-master.json"
    if not master_config_path.is_file():
        log_error(f"Master config not found at {master_config_path}")
        log_info("Run 'just rebuild' (darwin-rebuild switch) to deploy dotfiles first")
        return None

    master = load_master_config(master_config_path)
    machine = load_machine_config(machine_config_path)
    if machine:
        log_info(f"Applying machine overlay: {machine_config_path}")
        master = deep_merge(master, machine)
    return master


def _normalize_servers(master: JsonDict) -> JsonDict:
    return _ensure_mapping(master.get("servers"))


# Fields used to gate server inclusion. Stripped from per-tool outputs because
# downstream MCP clients don't all understand them and it's a sync-time concern.
_ENABLEMENT_FIELDS: tuple[str, ...] = ("enabled", "disabled")


def _is_server_enabled(config: JsonDict) -> bool:
    """Determine if a server config is enabled.

    Supports two equivalent forms (later wins on collision):
        "enabled": true | false   (mcp_sync convention)
        "disabled": true | false  (Claude/Cline schema convention; inverted)

    A server is enabled by default if neither field is present. If both
    fields are present, "enabled" takes precedence (it is the canonical
    repo convention; "disabled" exists only for compatibility with foreign
    schemas that ship with that key, e.g. dot_config/mcp/machine/work.json).
    """
    if "enabled" in config:
        return config["enabled"] is not False
    if "disabled" in config:
        return config["disabled"] is not True
    return True


def _filter_enabled_servers(servers: JsonDict) -> JsonDict:
    """Filter servers dict to only include enabled, non-retired servers.

    Args:
        servers: Dictionary of server configurations.

    Returns:
        Dictionary containing only servers that are enabled and not retired. A
        server is enabled if it has neither field, or "enabled" is truthy, or
        "disabled" is falsy (when "enabled" is absent). See
        ``_is_server_enabled`` for full precedence rules.
    """
    return {
        name: config
        for name, config in servers.items()
        if (
            name not in RETIRED_MCP_SERVER_NAMES
            and isinstance(config, dict)
            and _is_server_enabled(config)
        )
    }


def _strip_server_fields(servers: JsonDict, *fields: str) -> JsonDict:
    stripped: JsonDict = {}
    for name, config in servers.items():
        if not isinstance(config, dict):
            continue
        stripped[name] = {
            key: value for key, value in config.items() if key not in fields
        }
    return stripped


def _merge_override_servers(master: JsonDict, overrides: JsonDict) -> JsonDict:
    servers = _normalize_servers(master)
    override_servers = _ensure_mapping(overrides.get("servers"))
    if override_servers:
        return deep_merge(servers, override_servers)
    return servers


def _master_with_servers(master: JsonDict, servers: JsonDict) -> JsonDict:
    merged_master = copy.deepcopy(master)
    merged_master["servers"] = servers
    return merged_master


def _disabled_or_retired_server_names(servers: JsonDict) -> set[str]:
    disabled = {
        key
        for key, val in servers.items()
        if isinstance(val, dict) and not _is_server_enabled(val)
    }
    return disabled | set(RETIRED_MCP_SERVER_NAMES)


def _remove_retired_server_entries(config: JsonDict) -> JsonDict:
    cleaned = copy.deepcopy(config)
    for key in ("servers", "mcpServers", "mcp"):
        servers = cleaned.get(key)
        if not isinstance(servers, dict):
            continue
        for name in RETIRED_MCP_SERVER_NAMES:
            servers.pop(name, None)
    return cleaned


def _override_without_servers(overrides: JsonDict) -> JsonDict:
    if "servers" not in overrides:
        return copy.deepcopy(overrides)
    cleaned = copy.deepcopy(overrides)
    cleaned.pop("servers", None)
    return cleaned


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
    """Recursively merge ``override`` into ``base`` without mutating either.

    Nested dicts merge key-by-key; scalars and lists replace. A key ending in
    ``+`` appends to the list under the un-suffixed key instead of replacing
    it.

    Args:
        base: Document providing default values.
        override: Document whose values win on collision.

    Returns:
        A new merged document; both inputs are left untouched.
    """
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


def _codex_config_path(home: Path) -> Path:
    """Return Codex's co-owned ``config.toml`` path under ``home``.

    Args:
        home: Home directory the deployed path lives under.

    Returns:
        ``<home>/.codex/config.toml``.
    """
    return home / ".codex" / "config.toml"


def render_codex_config(master: JsonDict, home: Path | None = None) -> str | None:
    """Render the ``config.toml`` text a codex sync would write.

    Pure with respect to the target file: reads the current
    ``~/.codex/config.toml`` (or the base template on a fresh machine) but
    never writes it, so drift checks can compare without side effects.

    Args:
        master: Merged master + machine-overlay MCP config.
        home: Override home directory (for tests). Defaults to ``Path.home()``.

    Returns:
        The full config text a sync would write, or ``None`` when there is
        neither an existing file nor a base template to seed from.
    """
    home_path = _home_dir(home)
    codex_config_path = _codex_config_path(home_path)

    overrides = _load_override("codex", home_path)
    merged_servers = _merge_override_servers(master, overrides)
    managed = _enabled_stripped_servers(merged_servers)
    disabled = _disabled_or_retired_server_names(merged_servers)

    # Load the template once; it seeds a fresh config and enforces [tui] below.
    template_text = _load_text_template("codex", home_path)

    if codex_config_path.is_file():
        base_text = codex_config_path.read_text(encoding="utf-8")
    elif template_text:
        base_text = template_text
    else:
        return None

    base_text = apply_tui_settings(base_text, template_text, log_info=log_info)

    preserved = _strip_codex_managed_blocks(base_text, set(managed) | disabled)
    return preserved.rstrip() + "\n" + _render_codex_mcp_section(managed)


def sync_codex_mcp(master: JsonDict, home: Path | None = None) -> None:
    """Patch managed MCP servers into Codex's ``config.toml`` non-destructively.

    Codex owns ``~/.codex/config.toml`` and continuously writes its own state
    there (built-in ``mcp_servers`` such as ``node_repl``, ``plugins``,
    ``hooks`` trust hashes, ``marketplaces`` timestamps, desktop settings). We
    therefore preserve the existing file verbatim and only replace the
    ``[mcp_servers.NAME]`` tables we manage, mirroring
    ``patch_claude_code_config`` for ``~/.claude.json``. The base template
    seeds a brand-new file on a fresh machine; on existing files its ``[tui]``
    table is additionally enforced via ``codex_tui.apply_tui_settings`` so status
    line changes reach already-provisioned machines.

    Args:
        master: Merged master + machine-overlay MCP config.
        home: Override home directory (for tests). Defaults to ``Path.home()``.

    Returns:
        None: The target ``config.toml`` is updated in place.
    """
    home_path = _home_dir(home)
    codex_config_path = _codex_config_path(home_path)

    text = render_codex_config(master, home_path)
    if text is None:
        log_info("Skipping codex config (base template not found)")
        return

    codex_config_path.parent.mkdir(parents=True, exist_ok=True)
    codex_config_path.write_text(text, encoding="utf-8")
    log_success(f"Synced MCP servers to: {codex_config_path}")


def _strip_codex_managed_blocks(text: str, names: set[str]) -> str:
    """Remove the ``[mcp_servers.NAME]`` tables we own, preserving all else.

    Drops each ``[mcp_servers.NAME]`` table (and any nested subtable like
    ``[mcp_servers.NAME.env]``) whose NAME is in ``names``. It also drops the
    previous managed block emitted by this tool so servers
    deleted from the current master do not linger. Every other line — including
    Codex-owned ``mcp_servers`` such as ``node_repl`` and unrelated tables
    (``plugins``, ``hooks``, ``desktop``) — is kept verbatim, which keeps the
    rewrite idempotent.

    Args:
        text: Existing ``config.toml`` contents.
        names: MCP server names this tool manages (or is explicitly disabling).

    Returns:
        The config text with the owned MCP server tables removed.
    """
    roots = {f"mcp_servers.{name}" for name in names}
    kept: list[str] = []
    dropping = False
    in_managed_block = False
    for line in text.splitlines():
        stripped = line.strip()
        if stripped == CODEX_MCP_BEGIN_MARKER:
            in_managed_block = True
            dropping = True
            continue

        if in_managed_block and stripped == CODEX_MCP_END_MARKER:
            in_managed_block = False
            dropping = False
            continue

        if stripped.startswith("[") and stripped.endswith("]"):
            header = stripped[1:-1].strip()
            if not in_managed_block:
                dropping = any(
                    header == root or header.startswith(f"{root}.") for root in roots
                )
        if dropping:
            continue
        kept.append(line)
    return "\n".join(kept)


def _render_codex_mcp_section(servers: JsonDict) -> str:
    lines: list[str] = ["", CODEX_MCP_BEGIN_MARKER]

    for name, server in servers.items():
        lines.append("")
        lines.append(f"[mcp_servers.{name}]")

        url = server.get("url")
        if isinstance(url, str) and url:
            lines.append(f"url = {toml_string(url)}")
            continue

        lines.append(f"command = {toml_string(str(server.get('command', '')))}")

        args = list(server.get("args", []) or [])
        args_str = ", ".join(toml_string(str(arg)) for arg in args)
        lines.append(f"args = [{args_str}]")

        env = server.get("env")
        if isinstance(env, dict):
            env_parts = [
                f"{key} = {toml_string(str(value))}" for key, value in env.items()
            ]
            lines.append(f"environment = {{ {', '.join(env_parts)} }}")

    lines.append("")
    lines.append(CODEX_MCP_END_MARKER)
    return "\n".join(lines) + "\n"


def _load_json(path: Path) -> JsonDict:
    with open(path, encoding="utf-8") as handle:
        return json.load(handle)


def _load_json_object(path: Path) -> JsonDict:
    """Load a JSON document and require an object at its root.

    Args:
        path: JSON file to load.

    Returns:
        The parsed JSON object.

    Raises:
        ValueError: When the document is valid JSON but its root is not an object.
    """
    payload = _load_json(path)
    if not isinstance(payload, dict):
        raise ValueError(f"{path} must contain a JSON object at the document root")
    return payload


def _write_json(
    path: Path,
    payload: JsonDict,
    *,
    sort_keys: bool = True,
    trailing_newline: bool = True,
) -> None:
    """Write JSON to ``path`` atomically via a tempfile + rename.

    By default keys are alphabetized for deterministic output (good for
    files we own end-to-end). Pass ``sort_keys=False`` for files where a
    third-party tool also writes/reads the document and key ordering
    carries meaning or churns diffs (e.g. ``~/.claude.json``).

    ``ensure_ascii=False`` for the same reason: the other writers of these
    documents (Claude Code's JS ``JSON.stringify``, for one) emit non-ASCII
    literally, so escaping it to ``\\uXXXX`` here would rewrite unrelated
    keys on every sync and leave the file oscillating between two writers.
    The bytes are UTF-8 encoded below either way; escaping only changes
    which spelling of an identical string lands on disk.

    ``trailing_newline=False`` completes the same set. Files this tool
    generates end with a newline (POSIX convention, and ``drift.py``
    byte-compares them against ``json.dumps(...) + "\\n"``), but a co-owned
    file must match whatever its owner writes — Claude Code emits none, so
    adding one makes the last byte flip back and forth on every sync.
    """
    path.parent.mkdir(parents=True, exist_ok=True)
    serialized = json.dumps(payload, indent=2, sort_keys=sort_keys, ensure_ascii=False)
    fd, tmp = tempfile.mkstemp(dir=path.parent, prefix=f".{path.name}.", suffix=".tmp")
    try:
        os.write(fd, (serialized + ("\n" if trailing_newline else "")).encode("utf-8"))
        os.fsync(fd)
    finally:
        os.close(fd)
    os.replace(tmp, path)


def _render_patched_owned_config(
    master: JsonDict,
    home: Path | None,
    *,
    path: Path,
    override_key: str,
    server_map: Callable[[JsonDict], JsonDict] | None = None,
) -> JsonDict | None:
    """Render one co-owned config a sync would write, without side effects.

    Shared body for the "patch-style" targets (e.g. ``~/.claude.json``):
    tools that own their file, where a sync only
    rewrites the ``mcpServers`` key — managed servers replace their entries,
    unmanaged (hand-added) ones are preserved, and the owning tool's
    own keys are left untouched. Reads the current file but never writes it,
    so drift checks can compare deployed vs expected.

    Args:
        master: Master MCP config document.
        home: Home directory override for tests; defaults to ``Path.home()``.
        path: The owned file to read and render.
        override_key: ``~/.config/mcp/overrides/<key>.json`` layer to apply.
        server_map: Optional per-server transform into the tool's schema.
            Identity when ``None``.

    Returns:
        The patched document, or ``None`` when ``path`` is absent (the sync
        skips it in that case).
    """
    if not path.is_file():
        return None
    return _patch_owned_config(
        master,
        home,
        _load_json_object(path),
        override_key=override_key,
        server_map=server_map,
    )


def _patch_owned_config(
    master: JsonDict,
    home: Path | None,
    cfg: JsonDict,
    *,
    override_key: str,
    server_map: Callable[[JsonDict], JsonDict] | None = None,
) -> JsonDict:
    """Apply the managed ``mcpServers`` patch to an already-parsed document.

    The pure patch step behind :func:`_render_patched_owned_config`, split out
    so callers that already hold the parsed deployed document (drift checks,
    capture verification) can re-patch it without re-reading the file.
    Overrides are still read from disk on every call, so a just-written
    override file is always picked up. ``cfg`` is mutated.

    Args:
        master: Master MCP config document.
        home: Home directory override for tests; defaults to ``Path.home()``.
        cfg: The parsed deployed document to patch.
        override_key: ``~/.config/mcp/overrides/<key>.json`` layer to apply.
        server_map: Optional per-server transform into the tool's schema.

    Returns:
        The patched document.
    """
    home_path = _home_dir(home)

    overrides = _load_override(override_key, home_path)
    merged_servers = _merge_override_servers(master, overrides)
    disabled_servers = _disabled_or_retired_server_names(merged_servers)
    servers = _enabled_stripped_servers(merged_servers, "note")
    if server_map is not None:
        servers = {name: server_map(config) for name, config in servers.items()}

    existing = _ensure_mapping(cfg.get("mcpServers"))
    preserved_existing = {
        key: value for key, value in existing.items() if key not in disabled_servers
    }
    # Per-server collisions: managed config fully replaces the existing server
    # entry. We don't shallow-merge per-server fields because that would leave
    # stale env/args/etc. behind when master removes them. Hand-edits to
    # individual server entries (e.g. tweaking `timeout`) will NOT survive a
    # sync — make those changes in the master config or in the target's
    # dot_config/mcp/overrides/<key>.json layer instead.
    cfg["mcpServers"] = {**preserved_existing, **servers}
    cleaned_overrides = _override_without_servers(overrides)
    if cleaned_overrides:
        cfg = deep_merge(cfg, cleaned_overrides)
    return _remove_retired_server_entries(cfg)


def render_claude_config(master: JsonDict, home: Path | None = None) -> JsonDict | None:
    """Render the ``~/.claude.json`` document a sync would write.

    Reads the current file (Claude Code owns it) and applies the managed
    ``mcpServers`` patch without writing anything back, so drift checks can
    compare deployed vs expected without side effects.

    Args:
        master: Master MCP config document.
        home: Home directory override for tests; defaults to ``Path.home()``.

    Returns:
        The patched document, or ``None`` when ``~/.claude.json`` is absent
        (the sync skips it in that case).
    """
    home_path = _home_dir(home)
    return _render_patch(_patch_spec("claude", home_path), master, home_path)


def patch_claude_code_config(master: JsonDict, home: Path | None = None) -> None:
    """Patch managed MCP servers into ``~/.claude.json`` in place.

    Unlike the file-generating targets, Claude Code owns this file — only the
    ``mcpServers`` key is rewritten (managed servers replace their entries,
    unmanaged ones are preserved), and key order is kept to avoid churning
    Claude's own runtime state.

    Args:
        master: Master MCP config document.
        home: Home directory override for tests; defaults to ``Path.home()``.
    """
    home_path = _home_dir(home)
    _sync_patch_spec(_patch_spec("claude", home_path), master, home_path)


@dataclass(frozen=True, slots=True)
class PatchSpec:
    """One co-owned, patch-managed JSON target.

    Attributes:
        name: Target name as used by the sync and ``--check``/``--capture``.
        path: Deployed file the owning tool and the sync co-own.
        override_key: ``~/.config/mcp/overrides/<key>.json`` layer to apply.
        server_map: Optional per-server transform into the tool's schema.
    """

    name: str
    path: Path
    override_key: str
    server_map: Callable[[JsonDict], JsonDict] | None = None


def patch_specs(home: Path) -> list[PatchSpec]:
    """The co-owned patch-managed JSON targets, in sync order.

    Single source of truth shared by the sync, ``--check`` (drift), and
    ``--capture``: adding a new patch-style target here wires it into
    all three entry points at once. ``codex`` is intentionally absent — it is
    patch-managed TOML with its own renderer, check-only and not capturable.

    Args:
        home: Home directory the deployed paths live under.

    Returns:
        One spec per co-owned JSON target.
    """
    return [
        PatchSpec("claude", home / ".claude.json", "claude"),
    ]


def _patch_spec(name: str, home: Path) -> PatchSpec:
    """Look up one patch spec by target name.

    Args:
        name: A name returned by :func:`patch_specs`.
        home: Home directory the deployed paths live under.

    Returns:
        The matching spec.

    Raises:
        KeyError: When ``name`` is not a patch-managed target.
    """
    for spec in patch_specs(home):
        if spec.name == name:
            return spec
    raise KeyError(name)


def _render_patch(spec: PatchSpec, master: JsonDict, home: Path) -> JsonDict | None:
    """Render the document a sync would write for one patch spec."""
    return _render_patched_owned_config(
        master,
        home,
        path=spec.path,
        override_key=spec.override_key,
        server_map=spec.server_map,
    )


def _sync_patch_spec(spec: PatchSpec, master: JsonDict, home: Path) -> None:
    """Render one patch spec and write the deployed file back in place.

    Preserves key order: the owning tool (e.g. Claude Code) writes its
    own state into this file (recent projects, transient UI bits, etc.);
    alphabetizing the whole document on every sync churns the diff and can
    interleave managed keys with the tool's runtime state in confusing ways.
    Per-tool outputs generated from scratch stay ``sort_keys=True`` for
    deterministic diffs.

    Args:
        spec: The patch target to sync.
        master: Merged master + machine-overlay MCP config.
        home: Home directory the deployed paths live under.
    """
    cfg = _render_patch(spec, master, home)
    if cfg is None:
        log_info(f"Skipping: {spec.path} (file not found)")
        return
    _write_json(spec.path, cfg, sort_keys=False, trailing_newline=False)
    log_success(f"Synced: {spec.path}")


def render_patch_with_source(
    spec: PatchSpec, master: JsonDict, home: Path
) -> tuple[JsonDict, JsonDict] | None:
    """Parse a patch target's deployed file once, returning both sides.

    Drift checks and capture need the deployed document *and* the patched
    render; going through :func:`_render_patched_owned_config` and then
    re-reading the file would parse it twice (``~/.claude.json`` can reach
    hundreds of KB of Claude runtime state).

    Args:
        spec: The patch target to render.
        master: Merged master + machine-overlay MCP config.
        home: Home directory override for tests.

    Returns:
        ``(deployed, expected)`` — the parsed deployed document and the
        document a sync would write — or ``None`` when the deployed file is
        absent (the sync skips it).

    Raises:
        OSError: When the deployed file cannot be read.
        json.JSONDecodeError: When the deployed file is not valid JSON.
    """
    if not spec.path.is_file():
        return None
    deployed = _load_json_object(spec.path)
    expected = _patch_owned_config(
        master,
        home,
        copy.deepcopy(deployed),
        override_key=spec.override_key,
        server_map=spec.server_map,
    )
    return deployed, expected


def sync_to_locations(config: JsonDict, xdg_target: Path) -> None:
    """Write a generated per-tool config to its destination.

    Args:
        config: The fully merged per-tool config document.
        xdg_target: Destination file; parent directories are created.
    """
    _write_json(xdg_target, config)
    log_success(f"Synced: {xdg_target}")


def _enabled_stripped_servers(servers: JsonDict, *extra_fields: str) -> JsonDict:
    """Enabled servers from ``servers`` with sync-time gating fields stripped.

    Args:
        servers: Mapping of server name to config (already normalized/merged).
        extra_fields: Additional per-target fields to strip beyond the
            enablement fields every target strips (e.g. ``"note"``).

    Returns:
        Mapping of server name to config, ready for per-tool output.
    """
    return _strip_server_fields(
        _filter_enabled_servers(servers), *extra_fields, *_ENABLEMENT_FIELDS
    )


def transform_to_copilot_format(master: JsonDict) -> JsonDict:
    """Shape the master config for GitHub Copilot's ``mcpServers`` document.

    Args:
        master: Master MCP config document.

    Returns:
        Copilot-format document with every server granted ``tools: ["*"]``.
    """
    servers = _enabled_stripped_servers(_normalize_servers(master))
    mcp_servers: JsonDict = {}
    for name, server in servers.items():
        mcp_servers[name] = {
            **server,
            "tools": ["*"],
            "type": server.get("type", "local"),
        }
    return {"mcpServers": mcp_servers}


def transform_to_identity_format(master: JsonDict) -> JsonDict:
    """Pass the master config through, filtered to enabled servers.

    Args:
        master: Master MCP config document.

    Returns:
        A copy of ``master`` with disabled servers and gating fields removed.
    """
    config = copy.deepcopy(master)
    # The master config carries an MCP-flavored `$schema` URL, but per-tool
    # outputs that use the identity transform (vscode, github-copilot) have
    # their own schema URLs (or none). Don't propagate the master's schema —
    # let the per-tool base template assert the right one.
    config.pop("$schema", None)
    config["servers"] = _enabled_stripped_servers(_normalize_servers(master))
    return config


def transform_to_mcpservers_format(master: JsonDict) -> JsonDict:
    """Shape the master config as a bare ``mcpServers`` document.

    Args:
        master: Master MCP config document.

    Returns:
        ``{"mcpServers": ...}`` holding only enabled, stripped servers.
    """
    return {"mcpServers": _enabled_stripped_servers(_normalize_servers(master))}


def transform_to_opencode_format(master: JsonDict) -> JsonDict:
    """Shape the master config for opencode's ``mcp`` block.

    Args:
        master: Master MCP config document.

    Returns:
        opencode-format document: remote servers keep their URL; local
        servers get a merged command array and a default timeout.
    """
    servers = _enabled_stripped_servers(_normalize_servers(master))
    mcp: JsonDict = {}
    for name, server in servers.items():
        url = server.get("url")
        if isinstance(url, str) and url:
            mcp[name] = {
                "type": "remote",
                "url": url,
                "enabled": True,
            }
            continue

        command = server.get("command")
        args = list(server.get("args", []) or [])
        cmd_array = [command, *args] if command else args

        entry: JsonDict = {
            "type": "local",
            "command": cmd_array,
            "enabled": True,
            "timeout": _OPENCODE_TIMEOUT_MS,
        }
        if "env" in server:
            entry["environment"] = server["env"]
        mcp[name] = entry

    return {"mcp": mcp}


def _build_targets(home: Path) -> list[SyncTarget]:
    return [
        SyncTarget(
            # GitHub Copilot CLI reads ~/.copilot/mcp-config.json (home dir; it
            # does not honor XDG — only COPILOT_HOME overrides the location).
            name="copilot-cli",
            destination=home / ".copilot" / "mcp-config.json",
            transform=transform_to_copilot_format,
            template_key="copilot",
            override_key="copilot",
        ),
        SyncTarget(
            name="github-copilot-intellij",
            destination=home / ".config" / "github-copilot" / "intellij" / "mcp.json",
            transform=transform_to_identity_format,
            template_key="github-copilot",
            override_key="github-copilot",
        ),
        SyncTarget(
            name="github-copilot",
            destination=home / ".config" / "github-copilot" / "mcp.json",
            transform=transform_to_identity_format,
            template_key="github-copilot",
            override_key="github-copilot",
        ),
        SyncTarget(
            name="opencode",
            destination=home / ".config" / "opencode" / "opencode.json",
            transform=transform_to_opencode_format,
            template_key="opencode",
            override_key="opencode",
        ),
        SyncTarget(
            # Cursor reads ~/.cursor/mcp.json globally; ~/.config/cursor is never
            # read on macOS (verified against cursor.com/docs).
            name="cursor",
            destination=home / ".cursor" / "mcp.json",
            transform=transform_to_mcpservers_format,
            template_key="cursor",
            override_key="cursor",
        ),
        SyncTarget(
            # VS Code user-level MCP config (macOS, default profile). The
            # ~/.vscode/mcp.json path is workspace-only, never read globally.
            name="vscode",
            destination=home
            / "Library"
            / "Application Support"
            / "Code"
            / "User"
            / "mcp.json",
            transform=transform_to_identity_format,
            template_key="vscode",
            override_key="vscode",
        ),
        SyncTarget(
            name="junie",
            destination=home / ".junie" / "mcp" / "mcp.json",
            transform=transform_to_mcpservers_format,
            template_key="junie",
            override_key="junie",
        ),
        SyncTarget(
            name="lmstudio",
            destination=home / ".lmstudio" / "mcp.json",
            transform=transform_to_mcpservers_format,
            template_key="lmstudio",
            override_key="lmstudio",
        ),
        SyncTarget(
            # Tool-agnostic user-global MCP config. pi-mcp-adapter reads this
            # path as its precedence-1 source (ahead of ~/.pi/agent/mcp.json,
            # which the adapter reserves for its own overrides), so pi needs no
            # pi-specific file. Named for the location, not for pi: any other
            # host that adopts the same convention picks it up unchanged.
            #
            # This is the one target whose destination sits in the directory
            # that also holds sync *inputs* (mcp-master.json, overrides/*.json).
            # The filename must stay distinct from every input the loader reads
            # -- see test_pi_target_does_not_collide_with_master_config.
            name="xdg-mcp",
            destination=home / ".config" / "mcp" / "mcp.json",
            transform=transform_to_mcpservers_format,
            template_key="xdg-mcp",
            override_key="xdg-mcp",
        ),
    ]


def sync_destinations(home: Path) -> list[SyncDestination]:
    """Every path ``run_sync`` writes, in the same order.

    This is ``_build_targets`` plus the Codex TOML patch plus
    ``patch_specs``. Verify scripts must consume this list rather than
    repeating the special cases by hand. ``drift_report`` walks the same
    three primitives (it needs the writer objects, not only the paths).

    Args:
        home: Home directory the deployed paths live under.

    Returns:
        One entry per writer, wholesale first, then patch targets.
    """
    destinations = [
        SyncDestination(target.name, target.destination, "wholesale")
        for target in _build_targets(home)
    ]
    destinations.append(SyncDestination("codex", _codex_config_path(home), "patch"))
    destinations.extend(
        SyncDestination(spec.name, spec.path, "patch") for spec in patch_specs(home)
    )
    return destinations


def run_sync(
    master_path: Path | None = None,
    home: Path | None = None,
    machine_config_path: Path | None = None,
) -> int:
    """Fan the master MCP config out to every tool's native config.

    Args:
        master_path: Master config location; defaults to
            ``~/.config/mcp/mcp-master.json``.
        home: Home directory override for tests; defaults to ``Path.home()``.
        machine_config_path: Optional machine overlay merged over the master.

    Returns:
        Process exit code: ``0`` on success, ``1`` if the master is missing.
    """
    home_path = home or Path.home()
    master = load_merged_master(master_path, home_path, machine_config_path)
    if master is None:
        return 1
    log_info("Syncing MCP configurations from master...")

    for target in _build_targets(home_path):
        target.sync(master, home=home_path)

    sync_codex_mcp(master, home=home_path)
    for spec in patch_specs(home_path):
        _sync_patch_spec(spec, master, home_path)

    print()
    log_success("MCP configuration sync complete!")
    return 0


def main() -> int:
    """Entry point for the ``sync-mcp-configs`` console script.

    Returns:
        Process exit code from :func:`run_sync`.
    """
    return run_sync()
