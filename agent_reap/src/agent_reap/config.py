"""Configuration loading for ``agent-reap``.

The config is a plain TOML file symlinked out of the dotfiles repo, so edits are
live with no rebuild. Every field has a working default; a missing file is normal,
not an error.
"""

from __future__ import annotations

import os
import tomllib
from dataclasses import dataclass, field
from pathlib import Path

DEFAULT_CONFIG_PATH = Path("~/.config/agent-reap/config.toml")

# Socket locations, in the shapes actually seen on these machines: the stock
# per-uid directory, the /tmp variant, and z4h's private per-server sockets.
# "{uid}" is substituted at load time.
DEFAULT_SOCKET_GLOBS: tuple[str, ...] = (
    "/private/tmp/tmux-{uid}/*",
    "/tmp/tmux-{uid}/*",
    "/tmp/z4h-tmux-{uid}-*",
)

_CONFIG_KEYS = frozenset(
    {
        "socket_globs",
        "teammate_idle_minutes",
        "completion_grace_seconds",
        "interactive_idle_minutes",
        "include_lead",
        "kill_enabled",
        "deny_agent_names",
        "allow_agent_names",
        "teams_dir",
        "ssh_dir",
        "stray_command_prefixes",
    }
)


@dataclass(frozen=True)
class Config:
    """Runtime settings.

    Attributes:
        socket_globs: Glob patterns searched for tmux server sockets.
        teammate_idle_minutes: How long a teammate's inbox must have been quiet
            before its pane is reapable.
        completion_grace_seconds: How long a teammate's inbox must have been
            quiet before a SubagentStop completion event may reap it. Replaces
            ``teammate_idle_minutes`` in live-team mode only. A completion event
            proves the turn ended, not that the lead is done with the teammate,
            so this window preserves the send-a-follow-up workflow. Sized for a
            lead that is reading a long reply or waiting on a sibling agent: at
            90s those leads found the pane already reaped.
        interactive_idle_minutes: How long an interactive session's window must
            have been quiet before it is *reported*. Never triggers a kill on its
            own.
        include_lead: Whether a team lead pane may be reaped.
        kill_enabled: Whether targeted unattended team cleanup may kill. The CLI
            still requires both ``--team`` and ``--kill``; this policy gate is
            ignored by explicit operator-driven unscoped cleanup.
        deny_agent_names: Agent names that are never reaped.
        allow_agent_names: If non-empty, only these agent names are reapable.
        teams_dir: Root holding ``session-<id>/inboxes/<agent>.json``.
        ssh_dir: Directory scanned for ``cm-*`` control-master sockets.
        stray_command_prefixes: Executable path prefixes treated as user-owned
            when hunting disowned descendants. ``~`` is expanded at use.
    """

    socket_globs: tuple[str, ...] = DEFAULT_SOCKET_GLOBS
    teammate_idle_minutes: int = 30
    completion_grace_seconds: int = 300
    interactive_idle_minutes: int = 240
    include_lead: bool = False
    kill_enabled: bool = False
    deny_agent_names: tuple[str, ...] = ()
    allow_agent_names: tuple[str, ...] = ()
    teams_dir: Path = Path("~/.claude/teams")
    ssh_dir: Path = Path("~/.ssh")
    stray_command_prefixes: tuple[str, ...] = ("~/", "/nix/store/")

    def resolved_stray_prefixes(self) -> tuple[str, ...]:
        """Expand ``~`` in the stray-hunting prefixes.

        Returns:
            Absolute path prefixes.
        """
        return tuple(
            str(Path(p).expanduser()) + ("/" if p.endswith("/") else "")
            for p in self.stray_command_prefixes
        )

    def resolved_globs(self, uid: int | None = None) -> tuple[str, ...]:
        """Expand ``{uid}`` in the socket globs.

        Args:
            uid: Numeric user id. Defaults to the current effective uid.

        Returns:
            Glob patterns with ``{uid}`` substituted.
        """
        real_uid = os.geteuid() if uid is None else uid
        return tuple(g.format(uid=real_uid) for g in self.socket_globs)


@dataclass(frozen=True)
class LoadedConfig:
    """A config plus where it came from.

    Attributes:
        config: The effective settings.
        path: File the settings were read from, or None when defaults were used.
        errors: Human-readable problems found while parsing. Non-fatal: bad keys
            fall back to their default rather than aborting the run.
    """

    config: Config
    path: Path | None = None
    errors: tuple[str, ...] = field(default_factory=tuple)


def load_config(path: Path | None = None) -> LoadedConfig:
    """Read settings from disk, falling back to defaults.

    A malformed file degrades to defaults with a recorded error rather than
    raising: a config typo must not stop you from *seeing* what is leaking.

    Args:
        path: Config file to read. Defaults to ``~/.config/agent-reap/config.toml``.

    Returns:
        The effective config, its source path, and any parse errors.
    """
    # AGENT_REAP_CONFIG exists so the SessionEnd hook's kill path is testable
    # against a scratch socket, and so an unattended runner can be pointed at
    # its own policy file. An explicit --config still wins over it.
    env_path = os.environ.get("AGENT_REAP_CONFIG")
    if path is None and env_path:
        path = Path(env_path)
    target = (path or DEFAULT_CONFIG_PATH).expanduser()
    if not target.is_file():
        return LoadedConfig(config=Config(), path=None)

    try:
        raw = tomllib.loads(target.read_text(encoding="utf-8"))
    except (OSError, tomllib.TOMLDecodeError) as exc:
        return LoadedConfig(
            config=Config(), path=target, errors=(f"unreadable config: {exc}",)
        )

    defaults = Config()
    errors = [f"unknown key: {key}" for key in sorted(raw.keys() - _CONFIG_KEYS)]

    def _int(key: str, fallback: int) -> int:
        value = raw.get(key, fallback)
        if isinstance(value, bool) or not isinstance(value, int) or value < 0:
            errors.append(f"{key}: expected a non-negative integer, got {value!r}")
            return fallback
        return value

    def _bool(key: str, fallback: bool) -> bool:
        value = raw.get(key, fallback)
        if not isinstance(value, bool):
            errors.append(f"{key}: expected a boolean, got {value!r}")
            return fallback
        return value

    def _strs(key: str, fallback: tuple[str, ...]) -> tuple[str, ...]:
        value = raw.get(key, fallback)
        if isinstance(value, (list, tuple)) and all(isinstance(v, str) for v in value):
            return tuple(value)
        errors.append(f"{key}: expected a list of strings, got {value!r}")
        return fallback

    def _path(key: str, fallback: Path) -> Path:
        value = raw.get(key)
        if value is None:
            return fallback
        if not isinstance(value, str):
            errors.append(f"{key}: expected a string path, got {value!r}")
            return fallback
        return Path(value)

    config = Config(
        socket_globs=_strs("socket_globs", defaults.socket_globs),
        teammate_idle_minutes=_int(
            "teammate_idle_minutes", defaults.teammate_idle_minutes
        ),
        completion_grace_seconds=_int(
            "completion_grace_seconds", defaults.completion_grace_seconds
        ),
        interactive_idle_minutes=_int(
            "interactive_idle_minutes", defaults.interactive_idle_minutes
        ),
        include_lead=_bool("include_lead", defaults.include_lead),
        kill_enabled=_bool("kill_enabled", defaults.kill_enabled),
        deny_agent_names=_strs("deny_agent_names", defaults.deny_agent_names),
        allow_agent_names=_strs("allow_agent_names", defaults.allow_agent_names),
        teams_dir=_path("teams_dir", defaults.teams_dir),
        ssh_dir=_path("ssh_dir", defaults.ssh_dir),
        stray_command_prefixes=_strs(
            "stray_command_prefixes", defaults.stray_command_prefixes
        ),
    )
    return LoadedConfig(config=config, path=target, errors=tuple(errors))
