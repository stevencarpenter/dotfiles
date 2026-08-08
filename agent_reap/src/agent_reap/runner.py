"""Command execution seam.

Every external command in this package goes through a ``Runner``. Tests inject a
recorded runner so no test ever shells out to a real tmux or signals a real
process — a hard requirement for a tool whose job is killing things.
"""

from __future__ import annotations

import subprocess
from collections.abc import Sequence
from dataclasses import dataclass, field
from typing import Protocol

COMMAND_TIMEOUT_SECONDS = 3.0


@dataclass(frozen=True)
class Result:
    """Outcome of a single command.

    Attributes:
        returncode: Process exit status.
        stdout: Captured standard output, decoded and newline-trimmed.
        stderr: Captured standard error, decoded and newline-trimmed.
    """

    returncode: int
    stdout: str = ""
    stderr: str = ""

    @property
    def ok(self) -> bool:
        """Whether the command exited cleanly.

        Returns:
            True when the exit status is zero.
        """
        return self.returncode == 0


class Runner(Protocol):
    """Callable that executes an argv and returns its result."""

    def __call__(self, argv: Sequence[str]) -> Result:
        """Execute a command.

        Args:
            argv: Full argument vector, program first.

        Returns:
            The command's result.
        """
        ...


def subprocess_runner(argv: Sequence[str]) -> Result:
    """Execute a command with ``subprocess``.

    A missing executable is reported as a non-zero result rather than raising, so
    callers can treat "no tmux installed" the same as "tmux found nothing".

    Args:
        argv: Full argument vector, program first.

    Returns:
        The command's result.
    """
    try:
        proc = subprocess.run(
            list(argv),
            capture_output=True,
            text=True,
            check=False,
            timeout=COMMAND_TIMEOUT_SECONDS,
        )
    except (FileNotFoundError, PermissionError) as exc:
        return Result(returncode=127, stderr=str(exc))
    except subprocess.TimeoutExpired:
        return Result(
            returncode=124,
            stderr=f"command timed out after {COMMAND_TIMEOUT_SECONDS:g}s",
        )
    return Result(
        returncode=proc.returncode,
        stdout=proc.stdout.strip("\n"),
        stderr=proc.stderr.strip("\n"),
    )


@dataclass
class RecordingRunner:
    """Test double that replays canned output and records every invocation.

    Attributes:
        responses: Maps a joined argv prefix to the result to return. The longest
            matching prefix wins, so a test can stub ``tmux -S sock list-panes``
            without enumerating every flag.
        calls: Every argv this runner was asked to execute, in order.
        default: Result returned when no prefix matches.
    """

    responses: dict[str, Result] = field(default_factory=dict)
    calls: list[list[str]] = field(default_factory=list)
    default: Result = Result(returncode=1)

    def __call__(self, argv: Sequence[str]) -> Result:
        """Record the call and return the best-matching canned result.

        Args:
            argv: Full argument vector, program first.

        Returns:
            The canned result for the longest matching prefix, else ``default``.
        """
        argv = list(argv)
        self.calls.append(argv)
        joined = " ".join(argv)
        best: Result | None = None
        best_len = -1
        for prefix, result in self.responses.items():
            if joined.startswith(prefix) and len(prefix) > best_len:
                best, best_len = result, len(prefix)
        return best if best is not None else self.default
