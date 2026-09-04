"""Command-line interface.

Report-only by default. Killing teammates needs ``--kill``. Interactive sessions
are inventory-only because an abandoned Claude window may hold conversation
context worth more than the memory it occupies.
"""

from __future__ import annotations

import argparse
import json
import os
import sys
import time
from collections.abc import Sequence
from dataclasses import replace
from pathlib import Path
from typing import TypedDict

from .classify import Candidate, Report, classify
from .config import Config, load_config
from .discover import (
    Pane,
    Process,
    ancestry,
    discover_panes,
    find_sockets,
    list_panes,
    live_sockets,
    process_table,
    resolve_socket_path,
)
from .reap import Outcome, reap
from .runner import Runner, subprocess_runner
from .strays import ControlMaster, control_masters, disowned_descendants


class SocketEntry(TypedDict):
    """Machine-readable state for one discovered tmux socket."""

    socket: str
    live: bool
    current: bool
    sessions: list[str]


def _mb(kb: int) -> str:
    """Render kilobytes as megabytes.

    Args:
        kb: Size in kilobytes.

    Returns:
        A short human-readable string.
    """
    return f"{kb / 1024:.0f} MB"


def _duration(seconds: float | None) -> str:
    """Render a duration compactly.

    Args:
        seconds: Duration in seconds, or None when unknown.

    Returns:
        A short human-readable string such as ``1h35m``.
    """
    if seconds is None:
        return "unknown"
    total = int(seconds)
    if total < 60:
        return f"{total}s"
    if total < 3600:
        return f"{total // 60}m"
    return f"{total // 3600}h{(total % 3600) // 60:02d}m"


def _self_context(
    processes: dict[int, Process], runner: Runner
) -> tuple[set[int], set[tuple[str, str]], set[str]]:
    """Determine what belongs to the caller and must never be reaped.

    Three independent guards, because any one of them can be absent: process
    ancestry (the strongest — it works even with no tmux environment), the current
    pane id, and the caller's own team session.

    Args:
        processes: Process table keyed by pid.
        runner: Command executor, unused but kept for symmetry with callers.

    Returns:
        Protected pids, protected (socket, pane_id) pairs, and protected team
        session ids.
    """
    del runner
    pids = ancestry(os.getpid(), processes)

    # Socket-qualify the pane. $TMUX is "<socket>,<server-pid>,<session>", and a
    # pane id is unique only WITHIN a server — every server numbers from %0. A
    # bare id would therefore protect a same-numbered pane on every other socket,
    # which under-reaps silently. Resolve the socket the same way discovery does
    # so /tmp and /private/tmp compare equal.
    pane_ids: set[tuple[str, str]] = set()
    tmux_env = os.environ.get("TMUX", "")
    pane_env = os.environ.get("TMUX_PANE")
    if tmux_env and pane_env:
        socket_path = tmux_env.split(",", 1)[0]
        pane_ids.add((resolve_socket_path(socket_path), pane_env))
    sessions = {
        s
        for s in (
            os.environ.get("CLAUDE_SESSION_ID"),
            os.environ.get("CODEX_COMPANION_SESSION_ID"),
        )
        if s
    }
    # Team dirs are named by the session id's leading segment.
    sessions |= {s.split("-", 1)[0] for s in list(sessions)}
    return pids, pane_ids, sessions


def build_report(
    config: Config,
    runner: Runner,
    now: float | None = None,
    team_scope: str | None = None,
    live_team_scope: str | None = None,
    completed_agent: str | None = None,
) -> Report:
    """Discover and classify the current pane population.

    Args:
        config: Effective settings.
        runner: Command executor.
        now: Current unix timestamp; defaults to wall clock.
        team_scope: Restrict to one team session id for targeted teardown.
        live_team_scope: Restrict a completion-event reap to the caller's team.
        completed_agent: Restrict a completion-event reap to this exact agent.

    Returns:
        The classification report.
    """
    globs = config.resolved_globs()
    sockets = tuple(live_sockets(find_sockets(globs), runner))
    panes: list[Pane] = []
    for socket in sockets:
        panes.extend(list_panes(socket, runner))

    processes = process_table(runner)
    protected_pids, protected_panes, protected_sessions = _self_context(
        processes, runner
    )
    return classify(
        panes=panes,
        processes=processes,
        config=config,
        now=time.time() if now is None else now,
        protected_pids=protected_pids,
        protected_panes=protected_panes,
        protected_sessions=protected_sessions,
        sockets=sockets,
        team_scope=team_scope,
        live_team_scope=live_team_scope,
        completed_agent=completed_agent,
    )


def _revalidate_candidate(
    candidate: Candidate,
    config: Config,
    runner: Runner,
    team_scope: str | None,
    live_team_scope: str | None = None,
    completed_agent: str | None = None,
    now: float | None = None,
) -> tuple[bool, str]:
    """Confirm a candidate still refers to the same safe-to-reap teammate.

    Args:
        candidate: Snapshot candidate selected by the initial report.
        config: Effective settings.
        runner: Command executor.
        team_scope: Optional targeted teardown session.
        live_team_scope: Optional live team session for a completion event.
        completed_agent: Optional exact agent confirmed by that event.
        now: Wall clock override for tests.

    Returns:
        Whether the candidate remains valid, plus a rejection reason.
    """
    fresh_pane = next(
        (
            pane
            for pane in list_panes(candidate.pane.socket, runner)
            if pane.pane_id == candidate.pane.pane_id
        ),
        None,
    )
    if fresh_pane is None:
        return False, "pane no longer exists"
    if fresh_pane.pid != candidate.pane.pid:
        return False, "pane leader changed"

    processes = process_table(runner)
    if fresh_pane.pid not in processes:
        return False, "pane leader is absent from the fresh process table"
    protected_pids, protected_panes, protected_sessions = _self_context(
        processes, runner
    )
    fresh_report = classify(
        panes=[fresh_pane],
        processes=processes,
        config=config,
        now=time.time() if now is None else now,
        protected_pids=protected_pids,
        protected_panes=protected_panes,
        protected_sessions=protected_sessions,
        team_scope=team_scope,
        live_team_scope=live_team_scope,
        completed_agent=completed_agent,
    )
    for fresh in fresh_report.candidates:
        if (
            fresh.teammate == candidate.teammate
            and fresh.pane.pid == candidate.pane.pid
        ):
            return True, ""
    if fresh_report.skipped:
        return False, fresh_report.skipped[0].reason
    return False, "pane no longer matches the teammate identity"


def _print_report(report: Report, verbose: bool) -> None:
    """Render a report as text.

    Args:
        report: Classification to print.
        verbose: Whether to include per-pane exclusion reasons.
    """
    print(f"sockets searched: {len(report.sockets)}")
    for socket in report.sockets:
        print(f"  {socket}")

    print(f"\nreapable teammates: {len(report.candidates)}")
    for c in report.candidates:
        print(
            f"  {c.pane.pane_id:>5} {c.pane.target:<16} {c.teammate.agent_name:<24} "
            f"idle {_duration(c.idle_s):>7}  {_mb(c.rss_kb):>8}"
        )
    if report.candidates:
        print(f"  → {_mb(report.reclaimable_kb)} reclaimable")

    print(f"\nidle interactive sessions (report-only): {len(report.interactive)}")
    for i in report.interactive:
        print(
            f"  {i.pane.pane_id:>5} {i.pane.target:<16} {i.pane.path:<40} "
            f"idle {_duration(i.idle_s):>7}  {_mb(i.rss_kb):>8}"
        )

    if verbose and report.skipped:
        print(f"\nskipped: {len(report.skipped)}")
        for s in report.skipped:
            print(f"  {s.pane.pane_id:>5} {s.pane.target:<16} {s.reason}")


def _report_json(report: Report) -> dict[str, object]:
    """Serialize a report.

    Args:
        report: Classification to serialize.

    Returns:
        A JSON-ready dictionary.
    """
    return {
        "sockets": list(report.sockets),
        "candidates": [
            {
                "pane_id": c.pane.pane_id,
                "socket": c.pane.socket,
                "target": c.pane.target,
                "pid": c.pane.pid,
                "agent": c.teammate.agent_name,
                "session": c.teammate.session_id,
                "idle_s": int(c.idle_s),
                "rss_kb": c.rss_kb,
            }
            for c in report.candidates
        ],
        "interactive": [
            {
                "pane_id": i.pane.pane_id,
                "socket": i.pane.socket,
                "target": i.pane.target,
                "session": i.pane.session,
                "pid": i.pane.pid,
                "path": i.pane.path,
                "idle_s": None if i.idle_s is None else int(i.idle_s),
                "rss_kb": i.rss_kb,
            }
            for i in report.interactive
        ],
        "skipped": [
            {
                "pane_id": s.pane.pane_id,
                "socket": s.pane.socket,
                "target": s.pane.target,
                "session": s.pane.session,
                "reason": s.reason,
            }
            for s in report.skipped
        ],
        "reclaimable_kb": report.reclaimable_kb,
    }


def _print_outcomes(outcomes: list[Outcome]) -> int:
    """Render reap outcomes.

    Args:
        outcomes: Per-candidate results.

    Returns:
        Process exit status: non-zero when any kill failed.
    """
    for outcome in outcomes:
        name = outcome.candidate.teammate.agent_name
        pane = outcome.candidate.pane
        if outcome.killed:
            print(f"reaped  {pane.pane_id:>5} {pane.target:<16} {name}")
        elif outcome.detail == "dry-run":
            print(f"would   {pane.pane_id:>5} {pane.target:<16} {name}")
        else:
            print(
                f"FAILED  {pane.pane_id:>5} {pane.target:<16} {name}: {outcome.detail}"
            )
    return _outcome_status(outcomes)


def _outcome_status(outcomes: list[Outcome]) -> int:
    """Return non-zero when any requested kill failed safety or execution.

    Args:
        outcomes: Per-candidate results.

    Returns:
        Zero for kills and dry runs that completed as requested, otherwise one.
    """
    return 1 if any(not o.killed and o.detail != "dry-run" for o in outcomes) else 0


def _print_strays(
    masters: list[ControlMaster], disowned: list[Process], verbose: bool
) -> None:
    """Render the stray inventory.

    Args:
        masters: Control-master entries.
        disowned: PPID-1 user processes with no pane.
        verbose: Whether to print full command lines.
    """
    print(f"ssh control masters: {len(masters)}")
    for m in masters:
        bits = [f"pid {m.pid}" if m.pid else "no process"]
        if not m.socket_exists:
            bits.append("no socket")
        if m.responding is not None:
            bits.append("responding" if m.responding else "not responding")
        if m.stale:
            bits.append("STALE")
        print(f"  {m.socket}  [{', '.join(bits)}]  age {_duration(m.elapsed_s)}")

    print(f"\nuser-owned PPID-1 processes with no pane: {len(disowned)}")
    for p in disowned:
        command = p.command if verbose else p.command[:90]
        print(f"  pid {p.pid:<8} age {_duration(p.elapsed_s):>7}  {command}")
    if disowned:
        print("  (long-running user daemons legitimately appear here)")

    # The Ctrl+D question in one number. A disowned Claude process is the only
    # thing that would show ^D leaving work behind; daemons above are expected.
    escaped = [p for p in disowned if "claude" in p.command.lower()]
    print(f"\nclaude processes among them: {len(escaped)}")
    if not escaped:
        print("  none — no evidence of Claude processes escaping pane teardown")
    for p in escaped:
        print(f"  pid {p.pid:<8} age {_duration(p.elapsed_s):>7}  {p.command[:90]}")


def _nonnegative_int(value: str) -> int:
    """Parse a CLI integer that cannot weaken an idle threshold below zero."""
    parsed = int(value)
    if parsed < 0:
        raise argparse.ArgumentTypeError("must be a non-negative integer")
    return parsed


def build_parser() -> argparse.ArgumentParser:
    """Construct the argument parser.

    Returns:
        The configured parser.
    """
    parser = argparse.ArgumentParser(
        prog="agent-reap",
        description="Find and reap idle Claude teammate panes across every tmux socket.",
    )
    parser.add_argument("--config", help="path to config.toml")
    parser.add_argument("--json", action="store_true", help="machine-readable output")
    parser.add_argument(
        "-v", "--verbose", action="store_true", help="include exclusion reasons"
    )
    parser.add_argument(
        "--idle-minutes",
        type=_nonnegative_int,
        help="override how long a teammate inbox must be quiet before reaping",
    )
    sub = parser.add_subparsers(dest="command")

    sub.add_parser("report", help="show reapable teammates and idle sessions (default)")
    sub.add_parser("sockets", help="list every tmux server and its sessions")
    sub.add_parser("strays", help="ssh control masters and disowned descendants")

    reap_cmd = sub.add_parser("reap", help="reap idle teammate panes")
    reap_cmd.add_argument(
        "--kill", action="store_true", help="actually kill (default: dry run)"
    )
    reap_cmd.add_argument(
        "--include-lead", action="store_true", help="also reap team lead panes"
    )
    reap_cmd.add_argument(
        "--team",
        metavar="SESSION_ID",
        help=(
            "tear down exactly this team (the SessionEnd hook's path): skips the "
            "liveness checks, since the team is already over"
        ),
    )
    reap_cmd.add_argument(
        "--live-team",
        metavar="SESSION_ID",
        help=(
            "scope a completion-event reap to this live team; requires "
            "--completed-agent"
        ),
    )
    reap_cmd.add_argument(
        "--completed-agent",
        metavar="AGENT_NAME",
        help=(
            "reap only the teammate named by a SubagentStop event; window "
            "idle is skipped, inbox-age shortens to completion_grace_seconds"
        ),
    )
    return parser


def cli(argv: Sequence[str] | None = None, runner: Runner | None = None) -> int:
    """Entry point.

    Args:
        argv: Argument vector, defaulting to ``sys.argv[1:]``.
        runner: Command executor, defaulting to real subprocesses.

    Returns:
        Process exit status.
    """
    args = build_parser().parse_args(argv)
    run: Runner = runner or subprocess_runner

    loaded = load_config(Path(args.config) if args.config else None)
    for error in loaded.errors:
        print(f"config: {error}", file=sys.stderr)

    config = loaded.config
    if args.idle_minutes is not None:
        config = replace(config, teammate_idle_minutes=args.idle_minutes)
    if getattr(args, "include_lead", False):
        config = replace(config, include_lead=True)

    command = args.command or "report"
    team_scope: str | None = getattr(args, "team", None)
    live_team_scope: str | None = getattr(args, "live_team", None)
    completed_agent: str | None = getattr(args, "completed_agent", None)
    destructive = command == "reap" and bool(getattr(args, "kill", False))
    if (live_team_scope is None) != (completed_agent is None):
        print(
            "reap: --live-team and --completed-agent must be provided together",
            file=sys.stderr,
        )
        return 2
    if team_scope is not None and live_team_scope is not None:
        print(
            "reap: --team and --live-team are mutually exclusive",
            file=sys.stderr,
        )
        return 2
    if destructive and loaded.errors:
        print(
            "config: refusing destructive operation with invalid config",
            file=sys.stderr,
        )
        return 2
    if (
        destructive
        and (team_scope is not None or live_team_scope is not None)
        and not config.kill_enabled
    ):
        print(
            "config: unattended team cleanup requires kill_enabled = true",
            file=sys.stderr,
        )
        return 2

    if command == "sockets":
        sockets = find_sockets(config.resolved_globs())
        current_raw = (os.environ.get("TMUX") or "").split(",")[0]
        current = resolve_socket_path(current_raw) if current_raw else ""
        payload: list[SocketEntry] = []
        for socket in sockets:
            listing = run(["tmux", "-S", socket, "list-sessions"])
            payload.append(
                {
                    "socket": socket,
                    "live": listing.ok,
                    "current": socket == current,
                    "sessions": listing.stdout.splitlines() if listing.ok else [],
                }
            )
        if args.json:
            print(json.dumps(payload, indent=2))
        else:
            for entry in payload:
                mark = " <- $TMUX" if entry["current"] else ""
                state = "live" if entry["live"] else "stale socket, no server"
                print(f"{entry['socket']}  [{state}]{mark}")
                for line in entry["sessions"]:
                    print(f"    {line}")
        return 0

    if command == "strays":
        processes = process_table(run)
        pane_pids = {p.pid for p in _all_panes(config, run)}
        masters = control_masters(config.ssh_dir, processes, run)
        disowned = disowned_descendants(
            processes, pane_pids, config.resolved_stray_prefixes()
        )
        if args.json:
            print(
                json.dumps(
                    {
                        "control_masters": [m.__dict__ for m in masters],
                        "disowned": [p.__dict__ for p in disowned],
                    },
                    indent=2,
                )
            )
        else:
            _print_strays(masters, disowned, args.verbose)
        return 0

    report = build_report(
        config,
        run,
        team_scope=team_scope,
        live_team_scope=live_team_scope,
        completed_agent=completed_agent,
    )

    if command == "reap":
        outcomes = reap(
            report.candidates,
            run,
            dry_run=not args.kill,
            revalidator=lambda candidate: _revalidate_candidate(
                candidate,
                config=config,
                runner=run,
                team_scope=team_scope,
                live_team_scope=live_team_scope,
                completed_agent=completed_agent,
            ),
        )
        if args.json:
            print(
                json.dumps(
                    [
                        {
                            "pane_id": o.candidate.pane.pane_id,
                            "socket": o.candidate.pane.socket,
                            "target": o.candidate.pane.target,
                            "agent": o.candidate.teammate.agent_name,
                            "session": o.candidate.teammate.session_id,
                            "killed": o.killed,
                            "detail": o.detail,
                        }
                        for o in outcomes
                    ],
                    indent=2,
                )
            )
            return _outcome_status(outcomes)
        if not outcomes:
            print("nothing to reap")
            return 0
        status = _print_outcomes(outcomes)
        if not args.kill:
            print(
                f"\ndry run — {_mb(report.reclaimable_kb)} would be reclaimed. Pass --kill."
            )
        return status

    if args.json:
        print(json.dumps(_report_json(report), indent=2))
    else:
        _print_report(report, args.verbose)
    return 0


def _all_panes(config: Config, runner: Runner) -> list[Pane]:
    """List panes across every live server.

    Args:
        config: Effective settings.
        runner: Command executor.

    Returns:
        Every pane found.
    """
    return discover_panes(config.resolved_globs(), runner)


def main() -> None:
    """Console-script wrapper."""
    raise SystemExit(cli())


if __name__ == "__main__":
    main()
