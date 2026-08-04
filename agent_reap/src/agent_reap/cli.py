"""Command-line interface.

Report-only by default. Killing teammates needs ``--kill``; killing an interactive
session needs the separate ``--kill-interactive``, because an abandoned Claude
window may hold conversation context worth more than the memory it occupies, and
that trade is the operator's call, not the tool's.
"""

from __future__ import annotations

import argparse
import json
import os
import sys
import time
from collections.abc import Sequence
from pathlib import Path

from .classify import Report, classify
from .config import Config, load_config
from .discover import (
    Pane,
    ancestry,
    discover_panes,
    find_sockets,
    list_panes,
    live_sockets,
    process_table,
)
from .reap import Outcome, reap
from .runner import Runner, subprocess_runner
from .strays import ControlMaster, control_masters, disowned_descendants


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
    processes: dict, runner: Runner
) -> tuple[set[int], set[str], set[str]]:
    """Determine what belongs to the caller and must never be reaped.

    Three independent guards, because any one of them can be absent: process
    ancestry (the strongest — it works even with no tmux environment), the current
    pane id, and the caller's own team session.

    Args:
        processes: Process table keyed by pid.
        runner: Command executor, unused but kept for symmetry with callers.

    Returns:
        Protected pids, protected pane ids, and protected team session ids.
    """
    del runner
    pids = ancestry(os.getpid(), processes)
    pane_ids = {p for p in (os.environ.get("TMUX_PANE"),) if p}
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
) -> Report:
    """Discover and classify the current pane population.

    Args:
        config: Effective settings.
        runner: Command executor.
        now: Current unix timestamp; defaults to wall clock.
        team_scope: Restrict to one team session id for targeted teardown.

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
        protected_pane_ids=protected_panes,
        protected_sessions=protected_sessions,
        sockets=sockets,
        team_scope=team_scope,
    )


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


def _report_json(report: Report) -> dict:
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
                "target": i.pane.target,
                "pid": i.pane.pid,
                "path": i.pane.path,
                "idle_s": None if i.idle_s is None else int(i.idle_s),
                "rss_kb": i.rss_kb,
            }
            for i in report.interactive
        ],
        "skipped": [
            {"pane_id": s.pane.pane_id, "reason": s.reason} for s in report.skipped
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
    failed = 0
    for outcome in outcomes:
        name = outcome.candidate.teammate.agent_name
        pane = outcome.candidate.pane
        if outcome.killed:
            print(f"reaped  {pane.pane_id:>5} {pane.target:<16} {name}")
        elif outcome.detail == "dry-run":
            print(f"would   {pane.pane_id:>5} {pane.target:<16} {name}")
        else:
            failed += 1
            print(
                f"FAILED  {pane.pane_id:>5} {pane.target:<16} {name}: {outcome.detail}"
            )
    return 1 if failed else 0


def _print_strays(masters: list[ControlMaster], disowned: list, verbose: bool) -> None:
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
        type=int,
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
    overrides = {}
    if args.idle_minutes is not None:
        overrides["teammate_idle_minutes"] = args.idle_minutes
    if getattr(args, "include_lead", False):
        overrides["include_lead"] = True
    if overrides:
        config = Config(**{**config.__dict__, **overrides})

    command = args.command or "report"

    if command == "sockets":
        sockets = find_sockets(config.resolved_globs())
        current = (os.environ.get("TMUX") or "").split(",")[0]
        payload = []
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

    report = build_report(config, run, team_scope=getattr(args, "team", None))

    if command == "reap":
        outcomes = reap(report.candidates, run, dry_run=not args.kill)
        if args.json:
            print(
                json.dumps(
                    [
                        {
                            "pane_id": o.candidate.pane.pane_id,
                            "agent": o.candidate.teammate.agent_name,
                            "killed": o.killed,
                            "detail": o.detail,
                        }
                        for o in outcomes
                    ],
                    indent=2,
                )
            )
            return 0
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


def _all_panes(config: Config, runner: Runner) -> list:
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
