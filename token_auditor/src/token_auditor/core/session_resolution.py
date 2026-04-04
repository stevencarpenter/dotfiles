"""Pure path selection helpers for provider session discovery."""

import re
from collections.abc import Callable, Sequence
from pathlib import Path


def claude_project_slug(cwd: Path) -> str:
    """Convert a workspace path into Claude's filesystem-safe project slug."""
    normalized = str(cwd.expanduser().resolve())
    return re.sub(r"[^A-Za-z0-9]", "-", normalized)


def claude_project_dir(claude_home: Path, cwd: Path) -> Path:
    """Build the Claude project directory path for the given workspace."""
    return claude_home / "projects" / claude_project_slug(cwd)


def latest_path(paths: Sequence[Path], mtime_lookup: Callable[[Path], float]) -> Path | None:
    """Select the most recent path by mtime from an input sequence."""
    if not paths:
        return None
    return max(paths, key=mtime_lookup)


def choose_claude_session_path(project_paths: Sequence[Path], global_paths: Sequence[Path], mtime_lookup: Callable[[Path], float]) -> Path | None:
    """Pick latest project path first, then fallback to latest global path."""
    project_latest = latest_path(project_paths, mtime_lookup)
    if project_latest is not None:
        return project_latest
    return latest_path(global_paths, mtime_lookup)
