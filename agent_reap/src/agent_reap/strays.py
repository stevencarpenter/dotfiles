"""Leak classes that pane teardown provably cannot reach.

Destroying a pane SIGHUPs the pane leader and its non-disowned children. Two kinds
of process escape that entirely:

* **ssh control masters** — ``ControlPersist`` keeps a master alive on purpose,
  refreshed on every use. It was never a child of the shell that created it, so
  closing the pane does nothing to it.
* **disowned or nohup'd descendants** — the only measured path by which ``^D``
  can leave something behind. A plain ``sleep &`` is SIGHUP'd and does *not*
  survive; ``disown``/``nohup`` reparent to init and do.

Both are report-only. The second doubles as an instrument: a non-zero count is the
evidence that would revive the "Ctrl+D orphans processes" hypothesis, which
otherwise measures as false.
"""

from __future__ import annotations

import re
from collections.abc import Sequence
from dataclasses import dataclass
from pathlib import Path

from .discover import Process
from .runner import Runner

_MUX_RE = re.compile(r"^ssh: (?P<path>\S+) \[mux\]")

_APP_MARKERS = (".app/Contents/", ".appex/Contents/", ".framework/")


@dataclass(frozen=True)
class ControlMaster:
    """An ssh multiplexing master.

    Attributes:
        socket: Control socket path.
        socket_exists: Whether the socket file is present.
        pid: Owning ``[mux]`` process id, when one is running.
        elapsed_s: Age of the master process in seconds.
        responding: Whether ``ssh -O check`` succeeded, when probed.
    """

    socket: str
    socket_exists: bool
    pid: int | None = None
    elapsed_s: int = 0
    responding: bool | None = None

    @property
    def stale(self) -> bool:
        """Whether this entry is a leftover rather than a working master.

        Returns:
            True for a socket with no process, or a process with no socket.
        """
        return self.socket_exists != (self.pid is not None)


def control_masters(
    ssh_dir: Path,
    processes: dict[int, Process],
    runner: Runner | None = None,
) -> list[ControlMaster]:
    """Inventory ssh control masters from both directions.

    Sockets and processes are matched both ways so a socket without a server and
    a server without a socket are each surfaced rather than cancelling out.

    Args:
        ssh_dir: Directory holding ``cm-*`` sockets.
        processes: Process table keyed by pid.
        runner: Optional executor; when given, each live socket is probed with
            ``ssh -O check``.

    Returns:
        One entry per socket or ``[mux]`` process, sorted by socket path.
    """
    by_socket: dict[str, ControlMaster] = {}

    root = ssh_dir.expanduser()
    try:
        socket_paths = sorted(str(p) for p in root.glob("cm-*") if p.is_socket())
    except OSError:
        socket_paths = []
    for path in socket_paths:
        by_socket[path] = ControlMaster(socket=path, socket_exists=True)

    for process in processes.values():
        match = _MUX_RE.match(process.command.strip())
        if match is None:
            continue
        path = match.group("path")
        existing = by_socket.get(path)
        by_socket[path] = ControlMaster(
            socket=path,
            socket_exists=existing.socket_exists if existing else False,
            pid=process.pid,
            elapsed_s=process.elapsed_s,
        )

    if runner is not None:
        for path, master in list(by_socket.items()):
            if not master.socket_exists:
                continue
            ok = runner(["ssh", "-O", "check", "-o", f"ControlPath={path}", "dummy"]).ok
            by_socket[path] = ControlMaster(
                socket=master.socket,
                socket_exists=master.socket_exists,
                pid=master.pid,
                elapsed_s=master.elapsed_s,
                responding=ok,
            )

    return [by_socket[k] for k in sorted(by_socket)]


def disowned_descendants(
    processes: dict[int, Process],
    pane_pids: set[int],
    interest_prefixes: Sequence[str],
) -> list[Process]:
    """Find user-owned processes reparented to init that no pane accounts for.

    Selection is an **allowlist**, not a blocklist. Blocklisting system paths was
    tried first and produced 23 false positives on a real machine: launchd jobs
    invoked by bare name (``endpointsecurityd``, ``automountd``), audio drivers,
    vendor agents under ``/usr/local/bin``, and login shells (``-zsh``). All of
    those are legitimately parented by launchd and none of them can be a disowned
    descendant of a tmux pane.

    Precision matters more than recall here: this counter exists to answer one
    question — did anything escape pane teardown — and a report full of daemons is
    a report nobody reads. Widen ``interest_prefixes`` in config if a real stray
    ever falls outside them.

    Args:
        processes: Process table keyed by pid.
        pane_pids: Pids that are tmux pane leaders, which are legitimately
            parented by the tmux server rather than a shell.
        interest_prefixes: Executable path prefixes considered user-owned.

    Returns:
        PPID-1 processes launched from an interesting path, with no pane.
    """
    strays: list[Process] = []
    for process in processes.values():
        if process.ppid != 1 or process.pid in pane_pids:
            continue
        command = process.command.strip()
        if not command or command.startswith(("(", "-")):
            continue  # Kernel thread or login shell.
        argv0 = command.split(maxsplit=1)[0]
        if "/" not in argv0:
            continue  # Bare name: a launchd job, not a shell descendant.
        if not argv0.startswith(tuple(interest_prefixes)):
            continue
        if any(marker in argv0 for marker in _APP_MARKERS):
            continue
        # A tmux server daemonizes to PPID 1 by design; that is not a leak.
        if Path(argv0).name == "tmux":
            continue
        strays.append(process)
    return sorted(strays, key=lambda p: p.pid)
