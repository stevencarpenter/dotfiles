"""Discovery of tmux servers, panes, and the process table.

Everything here is read-only. The one non-obvious choice is that socket discovery
globs the filesystem instead of reading ``$TMUX``: a machine running z4h has
several tmux servers on separate sockets, and a tool that trusts ``$TMUX`` sees
only the one it happens to be attached to. That blind spot is exactly what makes
``tmux kill-server`` look broken.
"""

from __future__ import annotations

import glob
import re
import stat
from collections.abc import Iterable, Sequence
from dataclasses import dataclass
from pathlib import Path

from .runner import Result, Runner

# Tab-delimited. Free-form fields (command, path) come last so a tab inside a path
# cannot shift the earlier columns — the parser splits with a bounded maxsplit and
# lets the trailing field keep whatever it contains.
_PANE_FORMAT = (
    "#{pane_id}\t"
    "#{session_name}\t"
    "#{window_index}\t"
    "#{pane_index}\t"
    "#{pane_pid}\t"
    "#{window_activity}\t"
    "#{pane_current_command}\t"
    "#{pane_current_path}"
)

_PANE_FIELDS = 8

# Matches the teammate shape observed in the wild:
#   --agent-id docs-readme@session-d50ed876 --agent-name docs-readme
_AGENT_ID_RE = re.compile(
    r"--agent-id[= ](?P<name>[^@\s]+)@session-(?P<session>[^\s]+)"
)

_ETIME_RE = re.compile(
    r"^(?:(?:(?P<days>\d+)-)?(?P<hours>\d+):)?(?P<mins>\d+):(?P<secs>\d+)$"
)


@dataclass(frozen=True)
class Pane:
    """A live tmux pane.

    Attributes:
        socket: Server socket this pane belongs to.
        pane_id: Stable tmux pane identifier (``%68``). Used for every kill,
            because pane *indices* are positional and renumber as panes die.
        session: Session name.
        window_index: Window index within the session.
        pane_index: Pane index within the window, at the time of listing.
        pid: Pane leader pid.
        window_activity: Unix timestamp of the window's last activity, or None.
        command: Pane's current command name (not the full argv).
        path: Pane's current working directory.
    """

    socket: str
    pane_id: str
    session: str
    window_index: int
    pane_index: int
    pid: int
    window_activity: int | None
    command: str
    path: str

    @property
    def target(self) -> str:
        """Human-facing location of this pane.

        Returns:
            A ``session:window.pane`` label.
        """
        return f"{self.session}:{self.window_index}.{self.pane_index}"


@dataclass(frozen=True)
class Process:
    """A row from the process table.

    Attributes:
        pid: Process id.
        ppid: Parent process id.
        pgid: Process-group id.
        tpgid: Foreground process-group id for the controlling terminal, or 0/-1
            when no foreground group is available.
        rss_kb: Resident set size in kilobytes.
        state: Short state code from ``ps`` (``S``, ``R``, ``Z``...).
        elapsed_s: Seconds since the process started.
        command: Full command line.
    """

    pid: int
    ppid: int
    pgid: int
    tpgid: int
    rss_kb: int
    state: str
    elapsed_s: int
    command: str

    @property
    def sleeping(self) -> bool:
        """Whether the process is idle rather than running.

        Returns:
            True when the primary state code is ``S`` or ``I``.
        """
        return bool(self.state) and self.state[0] in {"S", "I"}


@dataclass(frozen=True)
class Teammate:
    """Identity parsed out of a teammate's command line.

    Attributes:
        agent_name: Teammate name, matching its inbox filename.
        session_id: Team session id, matching ``teams/session-<id>/``.
    """

    agent_name: str
    session_id: str


def parse_teammate(command: str) -> Teammate | None:
    """Extract teammate identity from a command line.

    Args:
        command: Full command line of a candidate process.

    Returns:
        The teammate identity, or None when this is not a teammate process.
    """
    match = _AGENT_ID_RE.search(command)
    if match is None:
        return None
    return Teammate(agent_name=match.group("name"), session_id=match.group("session"))


def parse_etime(value: str) -> int:
    """Convert a ``ps`` elapsed-time field to seconds.

    Handles the three shapes ``ps`` emits: ``MM:SS``, ``HH:MM:SS`` and
    ``D-HH:MM:SS``.

    Args:
        value: Raw elapsed-time field.

    Returns:
        Elapsed seconds, or 0 when the field cannot be parsed.
    """
    match = _ETIME_RE.match(value.strip())
    if match is None:
        return 0
    days = int(match.group("days") or 0)
    hours = int(match.group("hours") or 0)
    return (
        days * 86400
        + hours * 3600
        + int(match.group("mins")) * 60
        + int(match.group("secs"))
    )


def find_sockets(globs: Iterable[str]) -> list[str]:
    """Locate candidate tmux server sockets.

    Paths are resolved before de-duplication. On macOS ``/tmp`` is a symlink to
    ``/private/tmp``, so the default socket matches two of the stock globs and
    would otherwise be reported — and searched — as two separate servers.

    Args:
        globs: Glob patterns to search.

    Returns:
        Sorted, de-duplicated, symlink-resolved paths that are unix sockets.
    """
    found: set[str] = set()
    for pattern in globs:
        for hit in glob.glob(pattern):
            try:
                path = Path(resolve_socket_path(hit))
                if stat.S_ISSOCK(path.stat().st_mode):
                    found.add(str(path))
            except OSError:
                continue
    return sorted(found)


def resolve_socket_path(path: str) -> str:
    """Normalize a tmux socket path for identity comparisons.

    Args:
        path: Socket path as reported by tmux or supplied through ``$TMUX``.

    Returns:
        A symlink-resolved absolute path when resolution succeeds, otherwise the
        original value.
    """
    try:
        return str(Path(path).resolve())
    except OSError:
        return path


def live_sockets(sockets: Sequence[str], runner: Runner) -> list[str]:
    """Filter sockets down to those with a server actually answering.

    A socket file outlives its server, so existence is not liveness.

    Args:
        sockets: Candidate socket paths.
        runner: Command executor.

    Returns:
        Paths whose server responded to a session listing.
    """
    return [s for s in sockets if runner(["tmux", "-S", s, "list-sessions"]).ok]


def list_panes(socket: str, runner: Runner) -> list[Pane]:
    """List every pane on one tmux server.

    Args:
        socket: Server socket path.
        runner: Command executor.

    Returns:
        Panes on that server; empty when the server is gone or has none.
    """
    result: Result = runner(
        ["tmux", "-S", socket, "list-panes", "-a", "-F", _PANE_FORMAT]
    )
    if not result.ok:
        return []

    panes: list[Pane] = []
    for line in result.stdout.splitlines():
        if not line.strip():
            continue
        parts = line.split("\t", _PANE_FIELDS - 1)
        if len(parts) < _PANE_FIELDS:
            continue
        pane_id, session, window, index, pid, activity, command, path = parts
        try:
            panes.append(
                Pane(
                    socket=socket,
                    pane_id=pane_id,
                    session=session,
                    window_index=int(window),
                    pane_index=int(index),
                    pid=int(pid),
                    window_activity=int(activity) if activity.strip() else None,
                    command=command,
                    path=path,
                )
            )
        except ValueError:
            continue
    return panes


def discover_panes(globs: Iterable[str], runner: Runner) -> list[Pane]:
    """List panes across every live tmux server.

    Args:
        globs: Socket glob patterns.
        runner: Command executor.

    Returns:
        Panes from all servers, in socket order.
    """
    panes: list[Pane] = []
    for socket in live_sockets(find_sockets(globs), runner):
        panes.extend(list_panes(socket, runner))
    return panes


def process_table(runner: Runner) -> dict[int, Process]:
    """Snapshot the process table.

    Args:
        runner: Command executor.

    Returns:
        Processes keyed by pid; empty when ``ps`` fails.
    """
    result = runner(
        [
            "ps",
            "-eo",
            "pid=,ppid=,pgid=,tpgid=,rss=,state=,etime=,command=",
        ]
    )
    if not result.ok:
        return {}

    table: dict[int, Process] = {}
    for line in result.stdout.splitlines():
        parts = line.split(maxsplit=7)
        if len(parts) < 8:
            continue
        pid_s, ppid_s, pgid_s, tpgid_s, rss_s, state, etime_s, command = parts
        try:
            pid = int(pid_s)
            ppid = int(ppid_s)
            pgid = int(pgid_s)
            tpgid = int(tpgid_s)
            rss = int(rss_s)
        except ValueError:
            continue
        table[pid] = Process(
            pid=pid,
            ppid=ppid,
            pgid=pgid,
            tpgid=tpgid,
            rss_kb=rss,
            state=state,
            elapsed_s=parse_etime(etime_s),
            command=command,
        )
    return table


def ancestry(pid: int, table: dict[int, Process]) -> set[int]:
    """Collect a pid and all of its ancestors.

    This is the tool's primary self-protection: any pane whose leader appears in
    the caller's own ancestry is never a candidate, so ``agent-reap`` cannot kill
    the session it is running in.

    Args:
        pid: Starting process id.
        table: Process table to walk.

    Returns:
        The pid plus every ancestor pid reachable from it.
    """
    seen: set[int] = set()
    current = pid
    while current and current not in seen:
        seen.add(current)
        parent = table.get(current)
        if parent is None or parent.ppid == current:
            break
        current = parent.ppid
    return seen


def descendants(pid: int, table: dict[int, Process]) -> set[int]:
    """Collect every process descended from a pid.

    Args:
        pid: Root process id, which is not included in the result.
        table: Process table to walk.

    Returns:
        All reachable descendant pids. Malformed cycles terminate safely.
    """
    children: dict[int, list[int]] = {}
    for process in table.values():
        if process.pid == process.ppid:
            continue
        children.setdefault(process.ppid, []).append(process.pid)

    found: set[int] = set()
    pending = list(children.get(pid, ()))
    while pending:
        child = pending.pop()
        if child in found or child == pid:
            continue
        found.add(child)
        pending.extend(children.get(child, ()))
    return found
