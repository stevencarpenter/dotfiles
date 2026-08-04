"""Team inbox state.

A teammate's inbox under ``~/.claude/teams/session-<id>/inboxes/<agent>.json`` is
the closest thing to a "this agent is finished" signal. A drained inbox is an
empty JSON container (observed as 2 bytes), and its mtime is when the agent last
had traffic. Both conditions are required before a pane is reapable: drained but
*recently* drained means the agent may still be finishing up.
"""

from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path

# An empty JSON container ("{}" or "[]"). Anything larger is queued work.
DRAINED_MAX_BYTES = 2


@dataclass(frozen=True)
class Inbox:
    """State of one teammate's inbox file.

    Attributes:
        path: Inbox file location.
        exists: Whether the file is present.
        size: File size in bytes, 0 when absent.
        mtime: Last-modified time as a unix timestamp, None when absent.
    """

    path: Path
    exists: bool
    size: int = 0
    mtime: float | None = None

    @property
    def drained(self) -> bool:
        """Whether the inbox holds no queued work.

        Returns:
            True when the file exists and is an empty JSON container.
        """
        return self.exists and self.size <= DRAINED_MAX_BYTES

    def idle_seconds(self, now: float) -> float | None:
        """How long the inbox has been quiet.

        Args:
            now: Current unix timestamp.

        Returns:
            Seconds since the last write, or None when the file is absent.
        """
        if self.mtime is None:
            return None
        return max(0.0, now - self.mtime)


def read_inbox(teams_dir: Path, session_id: str, agent_name: str) -> Inbox:
    """Read one teammate's inbox state.

    Args:
        teams_dir: Root holding ``session-<id>/inboxes/``.
        session_id: Team session id.
        agent_name: Teammate name, matching the inbox filename.

    Returns:
        The inbox state; ``exists=False`` when the file is missing or unreadable.
    """
    path = (
        teams_dir.expanduser()
        / f"session-{session_id}"
        / "inboxes"
        / f"{agent_name}.json"
    )
    try:
        info = path.stat()
    except OSError:
        return Inbox(path=path, exists=False)
    return Inbox(path=path, exists=True, size=info.st_size, mtime=info.st_mtime)


def session_exists(teams_dir: Path, session_id: str) -> bool:
    """Whether a team session directory is present.

    Args:
        teams_dir: Root holding ``session-<id>/``.
        session_id: Team session id.

    Returns:
        True when the session directory exists.
    """
    return (teams_dir.expanduser() / f"session-{session_id}").is_dir()
