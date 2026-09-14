"""Destroy candidate panes with tmux kill-pane.

Pane destruction with ``remain-on-exit off`` sends SIGHUP to the pane leader and
its non-disowned children. Address panes by stable IDs (``%68``); positional
indices renumber as panes close.
"""

from __future__ import annotations

from dataclasses import dataclass
from typing import Protocol

from .classify import Candidate
from .runner import Runner


@dataclass(frozen=True)
class Outcome:
    """Result of attempting to reap one candidate.

    Attributes:
        candidate: The candidate acted on.
        killed: Whether the pane was actually destroyed.
        detail: Error text when the kill failed, else empty.
    """

    candidate: Candidate
    killed: bool
    detail: str = ""


class Revalidator(Protocol):
    """Callable that confirms a candidate is still safe to destroy."""

    def __call__(self, candidate: Candidate) -> tuple[bool, str]:
        """Return whether the candidate remains valid and any rejection reason."""
        ...


def kill_pane(socket: str, pane_id: str, runner: Runner) -> tuple[bool, str]:
    """Destroy one pane.

    Args:
        socket: Server socket the pane lives on.
        pane_id: Stable tmux pane id.
        runner: Command executor.

    Returns:
        Whether the kill succeeded, and any error text.
    """
    result = runner(["tmux", "-S", socket, "kill-pane", "-t", pane_id])
    return result.ok, "" if result.ok else (
        result.stderr or f"exit {result.returncode}"
    )


def reap(
    candidates: tuple[Candidate, ...],
    runner: Runner,
    dry_run: bool = True,
    revalidator: Revalidator | None = None,
) -> list[Outcome]:
    """Reap candidates, or report what a reap would do.

    Args:
        candidates: Panes classified as reapable.
        runner: Command executor.
        dry_run: When True, nothing is killed and every outcome is a no-op.
        revalidator: Fresh safety check run immediately before each real kill.
            A real reap fails closed when no revalidator is provided.

    Returns:
        One outcome per candidate, in order.
    """
    outcomes: list[Outcome] = []
    for candidate in candidates:
        if dry_run:
            outcomes.append(
                Outcome(candidate=candidate, killed=False, detail="dry-run")
            )
            continue
        if revalidator is None:
            outcomes.append(
                Outcome(
                    candidate=candidate,
                    killed=False,
                    detail="revalidation unavailable; refusing to kill",
                )
            )
            continue
        valid, reason = revalidator(candidate)
        if not valid:
            outcomes.append(
                Outcome(
                    candidate=candidate,
                    killed=False,
                    detail=f"revalidation failed: {reason}",
                )
            )
            continue
        killed, detail = kill_pane(
            candidate.pane.socket, candidate.pane.pane_id, runner
        )
        outcomes.append(Outcome(candidate=candidate, killed=killed, detail=detail))
    return outcomes
