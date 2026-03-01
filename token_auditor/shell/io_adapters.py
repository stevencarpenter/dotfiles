"""Impure filesystem and environment adapters for token_auditor."""

import os
from collections.abc import Sequence
from pathlib import Path


def read_lines(path: Path) -> tuple[str, ...]:
    """Read a text file as an immutable tuple of raw lines."""
    with path.open("r", encoding="utf-8", errors="ignore") as handle:
        return tuple(handle)


def glob_paths(base_dir: Path, pattern: str) -> tuple[Path, ...]:
    """Evaluate a glob under a base directory and return immutable path results."""
    return tuple(base_dir.glob(pattern))


def path_exists(path: Path) -> bool:
    """Check whether a filesystem path currently exists."""
    return path.exists()


def path_mtime(path: Path) -> float:
    """Read mtime for ordering candidate session files by recency."""
    return path.stat().st_mtime


def env_value(name: str, default: str = "") -> str:
    """Read an environment variable with an optional default fallback string."""
    return os.getenv(name, default)


def has_env(name: str) -> bool:
    """Return whether an environment variable is explicitly present."""
    return os.getenv(name) is not None


def is_tty(stream: object) -> bool:
    """Detect whether an output stream reports TTY support."""
    return bool(getattr(stream, "isatty", lambda: False)())


def sorted_paths_by_mtime(paths: Sequence[Path]) -> tuple[Path, ...]:
    """Sort a path sequence by mtime in ascending order for stable processing."""
    return tuple(sorted(paths, key=path_mtime))
