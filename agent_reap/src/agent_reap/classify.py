"""Turn raw panes into reap candidates, with reasons for every exclusion.

Two categories, because they leak for different reasons and carry very different
risk:

* **Teammates** — a team member pane whose work is done. Auto-reapable.
* **Interactive sessions** — a Claude window you walked away from. These are the
  other half of the accumulation problem (``^D`` does not close a Claude pane, so
  an abandoned window stays alive), but each may hold conversation context worth
  more than its memory. Report-only; killing them takes a separate explicit flag.

Every pane that is *not* a candidate carries a reason, so the report can explain
itself rather than silently omitting things.
"""

from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path

from .config import Config
from .discover import Pane, Process, Teammate, descendants, parse_teammate
from .teams import Inbox, read_inbox, session_exists

# Command names a Claude pane leader reports. Claude Code shows its version as the
# pane command (e.g. "2.1.221"), so match the version shape as well as the name.
_CLAUDE_COMMANDS = ("claude", "node")


@dataclass(frozen=True)
class Candidate:
    """A teammate pane eligible for reaping.

    Attributes:
        pane: The pane itself.
        process: Its leader process.
        teammate: Parsed teammate identity.
        inbox: Inbox state backing the decision.
        idle_s: Seconds since the inbox last saw traffic.
    """

    pane: Pane
    process: Process
    teammate: Teammate
    inbox: Inbox
    idle_s: float

    @property
    def rss_kb(self) -> int:
        """Resident memory of this candidate.

        Returns:
            Resident set size in kilobytes.
        """
        return self.process.rss_kb


@dataclass(frozen=True)
class Interactive:
    """An idle interactive Claude session. Reported, never auto-killed.

    Attributes:
        pane: The pane itself.
        process: Its leader process.
        idle_s: Seconds since the window last showed activity, or None when tmux
            reported no activity timestamp.
    """

    pane: Pane
    process: Process
    idle_s: float | None

    @property
    def rss_kb(self) -> int:
        """Resident memory of this session.

        Returns:
            Resident set size in kilobytes.
        """
        return self.process.rss_kb


@dataclass(frozen=True)
class Skipped:
    """A pane that was considered and rejected.

    Attributes:
        pane: The pane itself.
        reason: Why it is not a candidate.
    """

    pane: Pane
    reason: str


@dataclass(frozen=True)
class Report:
    """Full classification of the current pane population.

    Attributes:
        candidates: Reapable teammate panes.
        interactive: Idle interactive sessions, report-only.
        skipped: Panes excluded, each with a reason.
        sockets: Sockets that were searched.
    """

    candidates: tuple[Candidate, ...] = ()
    interactive: tuple[Interactive, ...] = ()
    skipped: tuple[Skipped, ...] = ()
    sockets: tuple[str, ...] = ()

    @property
    def reclaimable_kb(self) -> int:
        """Memory held by reapable teammates.

        Returns:
            Summed resident set size in kilobytes.
        """
        return sum(c.rss_kb for c in self.candidates)


def _is_claude_pane(pane: Pane, process: Process) -> bool:
    """Whether a pane's leader looks like a Claude Code process.

    Args:
        pane: Pane under test.
        process: Its leader process.

    Returns:
        True when either the pane command or the full argv identifies Claude.
    """
    if "/claude" in process.command or process.command.startswith("claude"):
        return True
    command = pane.command.strip()
    if command in _CLAUDE_COMMANDS:
        return True
    # Claude Code reports its version string as the pane command ("2.1.221").
    head, _, tail = command.partition(".")
    return (
        head.isdigit() and tail != "" and all(p.isdigit() for p in tail.split(".") if p)
    )


def _agent_allowed(name: str, config: Config) -> bool:
    """Apply the allow/deny lists to a teammate name.

    Args:
        name: Teammate name.
        config: Effective settings.

    Returns:
        True when this teammate may be reaped.
    """
    if name in config.deny_agent_names:
        return False
    return not config.allow_agent_names or name in config.allow_agent_names


def classify(
    panes: list[Pane],
    processes: dict[int, Process],
    config: Config,
    now: float,
    protected_pids: set[int],
    protected_panes: set[tuple[str, str]] | None = None,
    protected_sessions: set[str] | None = None,
    sockets: tuple[str, ...] = (),
    teams_dir: Path | None = None,
    team_scope: str | None = None,
    live_team_scope: str | None = None,
    completed_agent: str | None = None,
) -> Report:
    """Sort panes into candidates, interactive sessions, and exclusions.

    Args:
        panes: Panes discovered across all servers.
        processes: Process table keyed by pid.
        config: Effective settings.
        now: Current unix timestamp.
        protected_pids: Pids that must never be reaped — normally the caller's own
            ancestry, so the tool cannot kill the session running it.
        protected_panes: (socket, pane_id) pairs that must never be reaped.
            Qualified by socket on purpose: a pane id is unique only WITHIN a
            tmux server, so comparing bare ids lets the caller's own id protect a
            same-numbered pane on every other socket — which silently under-reaps
            exactly the leak this tool exists to stop.
        protected_sessions: Team session ids that must never be reaped, normally
            the caller's own team.
        sockets: Sockets searched, recorded on the report.
        teams_dir: Override for the teams root; defaults to the configured path.
        team_scope: Tear down exactly this team session id. Used by the
            ``SessionEnd`` hook, where the team's lifecycle has *ended* — so the
            inbox-drained, idle-threshold, and sleeping checks no longer apply
            (they exist to avoid reaping mid-work agents in a *live* team), and
            the own-team guard is deliberately lifted for this id. The pane and
            ancestry guards still hold, so the hook can never kill its own shell.
        live_team_scope: The caller's live team session id for a completion-event
            reap. Only the named ``completed_agent`` in this team is considered.
        completed_agent: The exact teammate name confirmed by a ``SubagentStop``
            event. Its time-based window and inbox-age thresholds are bypassed,
            but session, pane, process, descendant, and drained-inbox checks hold.

    Returns:
        The classification, with a reason attached to every exclusion.
    """
    protected_panes = protected_panes or set()
    protected_sessions = protected_sessions or set()
    if (live_team_scope is None) != (completed_agent is None):
        raise ValueError(
            "live_team_scope and completed_agent must be provided together"
        )
    if team_scope is not None and live_team_scope is not None:
        raise ValueError("team_scope and live_team_scope are mutually exclusive")
    root = (teams_dir or config.teams_dir).expanduser()
    teammate_idle_s = config.teammate_idle_minutes * 60
    completion_grace_s = float(config.completion_grace_seconds)
    interactive_idle_s = config.interactive_idle_minutes * 60

    candidates: list[Candidate] = []
    interactive: list[Interactive] = []
    skipped: list[Skipped] = []

    for pane in panes:
        process = processes.get(pane.pid)
        if process is None:
            skipped.append(Skipped(pane, "no process for pane leader"))
            continue

        teammate = parse_teammate(process.command)

        if teammate is None:
            if not _is_claude_pane(pane, process):
                continue  # Not ours; not worth reporting.
            if (
                pane.pid in protected_pids
                or (pane.socket, pane.pane_id) in protected_panes
            ):
                skipped.append(Skipped(pane, "this session"))
                continue
            idle = (
                None
                if pane.window_activity is None
                else max(0.0, now - pane.window_activity)
            )
            if idle is not None and idle < interactive_idle_s:
                skipped.append(Skipped(pane, f"interactive, active {int(idle)}s ago"))
                continue
            interactive.append(Interactive(pane=pane, process=process, idle_s=idle))
            continue

        if pane.pid in protected_pids or (pane.socket, pane.pane_id) in protected_panes:
            skipped.append(Skipped(pane, "this session"))
            continue

        if team_scope is not None:
            # Targeted teardown: this team is over. Only the self-guards above
            # apply; liveness checks would keep the leak alive.
            if teammate.session_id != team_scope:
                continue
            if teammate.agent_name == "team-lead" and not config.include_lead:
                skipped.append(Skipped(pane, "team lead (use --include-lead)"))
                continue
            if not _agent_allowed(teammate.agent_name, config):
                skipped.append(Skipped(pane, "excluded by allow/deny list"))
                continue
            candidates.append(
                Candidate(
                    pane=pane,
                    process=process,
                    teammate=teammate,
                    inbox=read_inbox(root, teammate.session_id, teammate.agent_name),
                    idle_s=0.0,
                )
            )
            continue

        if live_team_scope is not None:
            # A completion event is authoritative only for this exact teammate.
            # Do not turn live-team mode into a team-wide liveness bypass.
            if teammate.session_id != live_team_scope:
                continue
            if teammate.agent_name != completed_agent:
                continue
        elif teammate.session_id in protected_sessions:
            skipped.append(Skipped(pane, "own team session"))
            continue
        if teammate.agent_name == "team-lead" and not config.include_lead:
            skipped.append(Skipped(pane, "team lead (use --include-lead)"))
            continue
        if not _agent_allowed(teammate.agent_name, config):
            skipped.append(Skipped(pane, "excluded by allow/deny list"))
            continue
        if not session_exists(root, teammate.session_id):
            skipped.append(Skipped(pane, "no team dir for session"))
            continue
        if live_team_scope is None:
            window_idle_s = (
                None
                if pane.window_activity is None
                else max(0.0, now - pane.window_activity)
            )
            if window_idle_s is None:
                skipped.append(Skipped(pane, "window activity unavailable"))
                continue
            if window_idle_s < teammate_idle_s:
                skipped.append(
                    Skipped(pane, f"teammate window active {int(window_idle_s)}s ago")
                )
                continue
        if not process.sleeping:
            skipped.append(Skipped(pane, f"process not idle (state {process.state})"))
            continue

        descendant_processes = [
            processes[pid]
            for pid in descendants(pane.pid, processes)
            if pid in processes
        ]
        foreground = [
            child
            for child in descendant_processes
            if process.tpgid > 0 and child.pgid == process.tpgid
        ]
        if foreground:
            skipped.append(
                Skipped(
                    pane,
                    "foreground descendant process group "
                    f"{process.tpgid} still attached",
                )
            )
            continue
        active_descendants = [
            child for child in descendant_processes if not child.sleeping
        ]
        if active_descendants:
            pids = ",".join(str(child.pid) for child in active_descendants[:3])
            skipped.append(Skipped(pane, f"active descendant process ({pids})"))
            continue

        inbox = read_inbox(root, teammate.session_id, teammate.agent_name)
        if not inbox.exists:
            skipped.append(Skipped(pane, "no inbox file"))
            continue
        if not inbox.drained:
            skipped.append(Skipped(pane, f"inbox has queued work ({inbox.size}b)"))
            continue
        idle_s = inbox.idle_seconds(now) or 0.0
        # A completion event shortens this window but does not remove it. The
        # lead may still send the finished teammate a follow-up, and reaping it
        # seconds after its turn ends would destroy the context that makes the
        # follow-up worth sending.
        min_idle_s = (
            completion_grace_s if live_team_scope is not None else teammate_idle_s
        )
        if idle_s < min_idle_s:
            skipped.append(Skipped(pane, f"drained only {int(idle_s)}s ago"))
            continue

        candidates.append(
            Candidate(
                pane=pane,
                process=process,
                teammate=teammate,
                inbox=inbox,
                idle_s=idle_s,
            )
        )

    return Report(
        candidates=tuple(candidates),
        interactive=tuple(interactive),
        skipped=tuple(skipped),
        sockets=sockets,
    )
