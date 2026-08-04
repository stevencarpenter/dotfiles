"""Shared fixtures.

Every fixture here is hermetic: a fake teams directory under ``tmp_path`` and a
``RecordingRunner`` standing in for tmux and ps. No test may discover a real tmux
server, read a real inbox, or signal a real process.
"""

from __future__ import annotations

import json
import os
import socket as socketlib
import tempfile
from collections.abc import Iterator
from pathlib import Path

import pytest

from agent_reap.config import Config
from agent_reap.discover import Pane, Process
from agent_reap.runner import RecordingRunner, Result

NOW = 1_785_830_000.0

# One tab-delimited pane row, matching the format string in discover.py.
PANE_FORMAT_FIELDS = 8


def pane_line(
    pane_id: str,
    session: str,
    window: int,
    index: int,
    pid: int,
    activity: int | str,
    command: str,
    path: str,
) -> str:
    """Build one tmux ``list-panes`` output row.

    Args:
        pane_id: Stable pane id.
        session: Session name.
        window: Window index.
        index: Pane index.
        pid: Pane leader pid.
        activity: Window activity timestamp, or "" when absent.
        command: Pane current command.
        path: Pane current path.

    Returns:
        A tab-delimited row.
    """
    return "\t".join(
        [
            pane_id,
            session,
            str(window),
            str(index),
            str(pid),
            str(activity),
            command,
            path,
        ]
    )


def make_pane(
    pane_id: str = "%2",
    pid: int = 200,
    session: str = "devbox",
    window: int = 1,
    index: int = 2,
    activity: int | None = int(NOW) - 7200,
    command: str = "2.1.221",
    path: str = "/Users/dev/repo",
    socket: str = "/tmp/tmux-501/default",
) -> Pane:
    """Construct a pane directly, bypassing tmux parsing.

    Args:
        pane_id: Stable pane id.
        pid: Pane leader pid.
        session: Session name.
        window: Window index.
        index: Pane index.
        activity: Window activity timestamp.
        command: Pane current command.
        path: Pane current path.
        socket: Owning socket.

    Returns:
        The pane.
    """
    return Pane(
        socket=socket,
        pane_id=pane_id,
        session=session,
        window_index=window,
        pane_index=index,
        pid=pid,
        window_activity=activity,
        command=command,
        path=path,
    )


def make_process(
    pid: int = 200,
    ppid: int = 100,
    command: str = "claude --agent-id docs-readme@session-abc123 --agent-name docs-readme",
    rss_kb: int = 400_000,
    state: str = "Ss+",
    elapsed_s: int = 6000,
) -> Process:
    """Construct a process row.

    Args:
        pid: Process id.
        ppid: Parent process id.
        command: Full command line.
        rss_kb: Resident size in kilobytes.
        state: ``ps`` state code.
        elapsed_s: Age in seconds.

    Returns:
        The process.
    """
    return Process(
        pid=pid,
        ppid=ppid,
        rss_kb=rss_kb,
        state=state,
        elapsed_s=elapsed_s,
        command=command,
    )


@pytest.fixture
def teams_dir(tmp_path: Path) -> Path:
    """Create a fake teams root.

    Args:
        tmp_path: Pytest temporary directory.

    Returns:
        Path to the teams root.
    """
    root = tmp_path / "teams"
    root.mkdir()
    return root


def write_inbox(
    teams_dir: Path,
    session_id: str,
    agent: str,
    payload: object = None,
    mtime: float | None = None,
) -> Path:
    """Write a teammate inbox file.

    Args:
        teams_dir: Teams root.
        session_id: Team session id.
        agent: Teammate name.
        payload: JSON payload; ``None`` writes an empty (drained) container.
        mtime: Optional mtime to stamp onto the file.

    Returns:
        Path to the inbox file.
    """
    inboxes = teams_dir / f"session-{session_id}" / "inboxes"
    inboxes.mkdir(parents=True, exist_ok=True)
    path = inboxes / f"{agent}.json"
    path.write_text("{}" if payload is None else json.dumps(payload), encoding="utf-8")
    if mtime is not None:
        os.utime(path, (mtime, mtime))
    return path


@pytest.fixture
def config(teams_dir: Path) -> Config:
    """Build a config pointed at the fake teams root.

    Args:
        teams_dir: Fake teams root.

    Returns:
        Test configuration.
    """
    return Config(
        teams_dir=teams_dir, teammate_idle_minutes=30, interactive_idle_minutes=240
    )


@pytest.fixture
def runner() -> RecordingRunner:
    """Provide a recording runner that fails every unstubbed command.

    Returns:
        The recording runner.
    """
    return RecordingRunner(default=Result(returncode=1, stderr="unstubbed"))


@pytest.fixture
def short_tmp_path() -> Iterator[Path]:
    """Temporary directory short enough to hold a unix socket.

    ``tmp_path`` lives under ``/private/var/folders/...`` which blows past the
    104-character ``AF_UNIX`` limit — the same limit tmux's ``%C`` hashing exists
    to dodge. Socket-binding tests need a shallower root.

    Yielded already resolved: ``/tmp`` itself is a symlink to ``/private/tmp`` on
    macOS, and ``find_sockets`` resolves before de-duplicating, so an unresolved
    fixture path would never match what discovery returns.

    Yields:
        A resolved directory under ``/tmp`` that is removed on teardown.
    """
    with tempfile.TemporaryDirectory(dir="/tmp") as directory:
        yield Path(directory).resolve()


def make_socket(path: Path) -> Path:
    """Bind and immediately close a real unix socket.

    Args:
        path: Where to bind. Must be short enough for ``AF_UNIX``.

    Returns:
        The socket path.
    """
    sock = socketlib.socket(socketlib.AF_UNIX, socketlib.SOCK_STREAM)
    sock.bind(str(path))
    sock.close()
    return path
