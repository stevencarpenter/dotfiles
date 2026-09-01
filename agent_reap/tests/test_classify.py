"""Classification rules, especially the ones that keep the tool from killing you."""

from __future__ import annotations

from pathlib import Path

from agent_reap.classify import Report, classify
from agent_reap.config import Config
from agent_reap.discover import Pane, Process

from .conftest import NOW, make_pane, make_process, write_inbox

DRAINED_LONG_AGO = NOW - 5400  # 90 minutes


def _classify(
    config: Config,
    panes: list[Pane],
    processes: dict[int, Process],
    *,
    protected_pids: set[int] | None = None,
    protected_panes: set[tuple[str, str]] | None = None,
    protected_sessions: set[str] | None = None,
    team_scope: str | None = None,
    live_team_scope: str | None = None,
    completed_agent: str | None = None,
) -> Report:
    """Run classification with test defaults.

    Args:
        config: Effective settings.
        panes: Panes to classify.
        processes: Process table.
        protected_pids: Process ancestry protected from reaping.
        protected_panes: Socket-qualified panes protected from reaping.
        protected_sessions: Team sessions protected from reaping.
        team_scope: Optional targeted teardown session.
        live_team_scope: Optional live team session for a completion event.
        completed_agent: Optional exact agent confirmed by that event.

    Returns:
        The classification report.
    """
    return classify(
        panes=panes,
        processes=processes,
        config=config,
        now=NOW,
        protected_pids=protected_pids or set(),
        protected_panes=protected_panes or set(),
        protected_sessions=protected_sessions or set(),
        team_scope=team_scope,
        live_team_scope=live_team_scope,
        completed_agent=completed_agent,
    )


def test_drained_and_stale_teammate_is_reapable(
    config: Config, teams_dir: Path
) -> None:
    """The happy path: inbox drained long enough, process asleep."""
    write_inbox(teams_dir, "abc123", "docs-readme", mtime=DRAINED_LONG_AGO)
    pane, process = make_pane(), make_process()

    report = _classify(config, [pane], {200: process})

    assert [c.teammate.agent_name for c in report.candidates] == ["docs-readme"]
    assert report.reclaimable_kb == 400_000


def test_recently_drained_teammate_is_spared(config: Config, teams_dir: Path) -> None:
    """A freshly drained inbox may still be finishing up."""
    write_inbox(teams_dir, "abc123", "docs-readme", mtime=NOW - 60)

    report = _classify(config, [make_pane()], {200: make_process()})

    assert report.candidates == ()
    assert "drained only" in report.skipped[0].reason


def test_inbox_with_queued_work_is_spared(config: Config, teams_dir: Path) -> None:
    """A non-empty inbox means the agent still has work."""
    write_inbox(
        teams_dir,
        "abc123",
        "docs-readme",
        payload=[{"m": "go"}],
        mtime=DRAINED_LONG_AGO,
    )

    report = _classify(config, [make_pane()], {200: make_process()})

    assert report.candidates == ()
    assert "queued work" in report.skipped[0].reason


def test_running_teammate_is_spared(config: Config, teams_dir: Path) -> None:
    """A process in the running state is mid-work regardless of its inbox."""
    write_inbox(teams_dir, "abc123", "docs-readme", mtime=DRAINED_LONG_AGO)

    report = _classify(config, [make_pane()], {200: make_process(state="R+")})

    assert report.candidates == ()
    assert "not idle" in report.skipped[0].reason


def test_recent_window_activity_spares_sleeping_teammate(
    config: Config, teams_dir: Path
) -> None:
    """Fresh output is active work even when the event-loop process is sleeping."""
    write_inbox(teams_dir, "abc123", "docs-readme", mtime=DRAINED_LONG_AGO)
    pane = make_pane(activity=int(NOW))

    report = _classify(config, [pane], {200: make_process(state="Ss+")})

    assert report.candidates == ()
    assert "window active" in report.skipped[0].reason


def test_unknown_window_activity_spares_sleeping_teammate(
    config: Config, teams_dir: Path
) -> None:
    """Missing tmux liveness telemetry must fail closed for destructive candidates."""
    write_inbox(teams_dir, "abc123", "docs-readme", mtime=DRAINED_LONG_AGO)

    report = _classify(
        config,
        [make_pane(activity=None)],
        {200: make_process(state="Ss+")},
    )

    assert report.candidates == ()
    assert "activity unavailable" in report.skipped[0].reason


def test_running_descendant_spares_sleeping_teammate(
    config: Config, teams_dir: Path
) -> None:
    """A busy tool child keeps its sleeping Claude parent out of the kill set."""
    write_inbox(teams_dir, "abc123", "docs-readme", mtime=DRAINED_LONG_AGO)
    processes = {
        200: make_process(pid=200, state="S"),
        201: make_process(pid=201, ppid=200, state="R", command="pytest"),
    }

    report = _classify(config, [make_pane()], processes)

    assert report.candidates == ()
    assert "active descendant" in report.skipped[0].reason


def test_sleeping_foreground_descendant_spares_teammate(
    config: Config, teams_dir: Path
) -> None:
    """A foreground child remains work even while it waits on terminal I/O."""
    write_inbox(teams_dir, "abc123", "docs-readme", mtime=DRAINED_LONG_AGO)
    processes = {
        200: make_process(pid=200, pgid=200, tpgid=201, state="S"),
        201: make_process(
            pid=201,
            ppid=200,
            pgid=201,
            tpgid=201,
            state="S",
            command="sleep 3600",
        ),
    }

    report = _classify(config, [make_pane()], processes)

    assert report.candidates == ()
    assert "foreground descendant" in report.skipped[0].reason


def test_sleeping_same_group_descendant_spares_teammate(
    config: Config, teams_dir: Path
) -> None:
    """Silent child work often inherits Claude's own foreground process group."""
    write_inbox(teams_dir, "abc123", "docs-readme", mtime=DRAINED_LONG_AGO)
    processes = {
        200: make_process(pid=200, pgid=200, tpgid=200, state="S"),
        201: make_process(
            pid=201,
            ppid=200,
            pgid=200,
            tpgid=200,
            state="S",
            command="sleep 3600",
        ),
    }

    report = _classify(config, [make_pane()], processes)

    assert report.candidates == ()
    assert "foreground descendant" in report.skipped[0].reason


def test_own_ancestry_is_never_reapable(config: Config, teams_dir: Path) -> None:
    """A pane in the caller's own process ancestry is untouchable."""
    write_inbox(teams_dir, "abc123", "docs-readme", mtime=DRAINED_LONG_AGO)

    report = _classify(
        config, [make_pane()], {200: make_process()}, protected_pids={200}
    )

    assert report.candidates == ()
    assert report.skipped[0].reason == "this session"


def test_own_pane_is_never_reapable(config: Config, teams_dir: Path) -> None:
    """The caller's own pane is untouchable even if ancestry lookup failed."""
    write_inbox(teams_dir, "abc123", "docs-readme", mtime=DRAINED_LONG_AGO)

    report = _classify(
        config,
        [make_pane()],
        {200: make_process()},
        protected_panes={("/tmp/tmux-501/default", "%2")},
    )

    assert report.candidates == ()


def test_own_team_session_is_never_reapable(config: Config, teams_dir: Path) -> None:
    """A tool run by a team lead must not reap its own teammates."""
    write_inbox(teams_dir, "abc123", "docs-readme", mtime=DRAINED_LONG_AGO)

    report = _classify(
        config, [make_pane()], {200: make_process()}, protected_sessions={"abc123"}
    )

    assert report.candidates == ()
    assert report.skipped[0].reason == "own team session"


def test_team_lead_is_spared_by_default(config: Config, teams_dir: Path) -> None:
    """The lead holds the team's context and needs an explicit opt-in."""
    write_inbox(teams_dir, "abc123", "team-lead", mtime=DRAINED_LONG_AGO)
    process = make_process(command="claude --agent-id team-lead@session-abc123")

    report = _classify(config, [make_pane()], {200: process})

    assert report.candidates == ()
    assert "team lead" in report.skipped[0].reason


def test_team_lead_is_reapable_with_include_lead(teams_dir: Path) -> None:
    """``--include-lead`` lifts the lead exclusion."""
    write_inbox(teams_dir, "abc123", "team-lead", mtime=DRAINED_LONG_AGO)
    config = Config(teams_dir=teams_dir, include_lead=True)
    process = make_process(command="claude --agent-id team-lead@session-abc123")

    report = _classify(config, [make_pane()], {200: process})

    assert len(report.candidates) == 1


def test_deny_list_wins(teams_dir: Path) -> None:
    """A denied agent name is never reaped."""
    write_inbox(teams_dir, "abc123", "docs-readme", mtime=DRAINED_LONG_AGO)
    config = Config(teams_dir=teams_dir, deny_agent_names=("docs-readme",))

    report = _classify(config, [make_pane()], {200: make_process()})

    assert report.candidates == ()
    assert "allow/deny" in report.skipped[0].reason


def test_allow_list_excludes_everything_else(teams_dir: Path) -> None:
    """A non-empty allow list is exclusive."""
    write_inbox(teams_dir, "abc123", "docs-readme", mtime=DRAINED_LONG_AGO)
    config = Config(teams_dir=teams_dir, allow_agent_names=("someone-else",))

    report = _classify(config, [make_pane()], {200: make_process()})

    assert report.candidates == ()


def test_missing_team_dir_is_spared(config: Config) -> None:
    """Without a team directory the inbox signal cannot be trusted."""
    report = _classify(config, [make_pane()], {200: make_process()})

    assert report.candidates == ()
    assert "no team dir" in report.skipped[0].reason


def test_missing_inbox_is_spared(config: Config, teams_dir: Path) -> None:
    """A team dir with no inbox for this agent proves nothing about its state."""
    (teams_dir / "session-abc123" / "inboxes").mkdir(parents=True)

    report = _classify(config, [make_pane()], {200: make_process()})

    assert report.candidates == ()
    assert report.skipped[0].reason == "no inbox file"


def test_pane_without_a_process_is_reported_not_reaped(config: Config) -> None:
    """A pane whose leader vanished is surfaced, never killed."""
    report = _classify(config, [make_pane()], {})

    assert report.candidates == ()
    assert "no process" in report.skipped[0].reason


def test_idle_interactive_session_is_reported_separately(config: Config) -> None:
    """An abandoned Claude window lands in the report-only bucket."""
    pane = make_pane(pane_id="%9", pid=300, activity=int(NOW) - 20_000)
    process = make_process(pid=300, command="/Users/dev/.local/bin/claude --ide")

    report = _classify(config, [pane], {300: process})

    assert report.candidates == ()
    assert [i.pane.pane_id for i in report.interactive] == ["%9"]


def test_recently_used_interactive_session_is_not_reported(config: Config) -> None:
    """A window you were just using is not clutter."""
    pane = make_pane(pane_id="%9", pid=300, activity=int(NOW) - 60)
    process = make_process(pid=300, command="/Users/dev/.local/bin/claude --ide")

    report = _classify(config, [pane], {300: process})

    assert report.interactive == ()


def test_non_claude_panes_are_ignored_entirely(config: Config) -> None:
    """A plain shell pane is neither a candidate nor noise in the report."""
    pane = make_pane(pane_id="%3", pid=500, command="zsh")
    process = make_process(pid=500, command="-zsh")

    report = _classify(config, [pane], {500: process})

    assert report.candidates == ()
    assert report.interactive == ()
    assert report.skipped == ()


def test_team_scope_reaps_regardless_of_inbox_state(
    config: Config, teams_dir: Path
) -> None:
    """Targeted teardown ignores liveness checks: the team is already over."""
    write_inbox(
        teams_dir, "abc123", "docs-readme", payload=[{"m": "queued"}], mtime=NOW
    )

    report = _classify(
        config, [make_pane()], {200: make_process(state="R+")}, team_scope="abc123"
    )

    assert [c.teammate.agent_name for c in report.candidates] == ["docs-readme"]


def test_team_scope_ignores_other_teams(config: Config, teams_dir: Path) -> None:
    """A teardown for one session must not touch a different live team."""
    write_inbox(teams_dir, "abc123", "docs-readme", mtime=DRAINED_LONG_AGO)

    report = _classify(
        config, [make_pane()], {200: make_process()}, team_scope="other999"
    )

    assert report.candidates == ()


def test_team_scope_still_protects_own_ancestry(
    config: Config, teams_dir: Path
) -> None:
    """The hook must never kill the shell it runs in, even during teardown."""
    write_inbox(teams_dir, "abc123", "docs-readme", mtime=DRAINED_LONG_AGO)

    report = _classify(
        config,
        [make_pane()],
        {200: make_process()},
        protected_pids={200},
        team_scope="abc123",
    )

    assert report.candidates == ()
    assert report.skipped[0].reason == "this session"


def test_team_scope_still_spares_the_lead(config: Config, teams_dir: Path) -> None:
    """Teardown of a team leaves its lead alone unless asked."""
    write_inbox(teams_dir, "abc123", "team-lead", mtime=NOW)
    process = make_process(command="claude --agent-id team-lead@session-abc123")

    report = _classify(config, [make_pane()], {200: process}, team_scope="abc123")

    assert report.candidates == ()
    assert "team lead" in report.skipped[0].reason


def test_completion_event_shortens_time_thresholds(
    config: Config, teams_dir: Path
) -> None:
    """A named completion event reaps past the grace, not past the 30m window."""
    write_inbox(teams_dir, "abc123", "docs-readme", mtime=NOW - 600)
    pane = make_pane(activity=int(NOW))

    report = _classify(
        config,
        [pane],
        {200: make_process()},
        protected_sessions={"abc123"},
        live_team_scope="abc123",
        completed_agent="docs-readme",
    )

    assert [c.teammate.agent_name for c in report.candidates] == ["docs-readme"]


def test_completion_event_respects_completion_grace(
    config: Config, teams_dir: Path
) -> None:
    """A teammate that just finished stays alive long enough to be re-messaged."""
    write_inbox(teams_dir, "abc123", "docs-readme", mtime=NOW - 5)

    report = _classify(
        config,
        [make_pane(activity=int(NOW))],
        {200: make_process()},
        live_team_scope="abc123",
        completed_agent="docs-readme",
    )

    assert report.candidates == ()
    assert "drained only" in report.skipped[0].reason


def test_completion_event_still_spares_the_lead(
    config: Config, teams_dir: Path
) -> None:
    """A completion event naming the lead cannot reap it."""
    write_inbox(teams_dir, "abc123", "team-lead", mtime=NOW - 120)
    process = make_process(command="claude --agent-id team-lead@session-abc123")

    report = _classify(
        config,
        [make_pane()],
        {200: process},
        live_team_scope="abc123",
        completed_agent="team-lead",
    )

    assert report.candidates == ()
    assert "team lead" in report.skipped[0].reason


def test_completion_event_still_requires_drained_inbox(
    config: Config, teams_dir: Path
) -> None:
    """The event does not override queued work in the teammate inbox."""
    write_inbox(
        teams_dir,
        "abc123",
        "docs-readme",
        payload=[{"m": "go"}],
        mtime=NOW,
    )

    report = _classify(
        config,
        [make_pane(activity=int(NOW))],
        {200: make_process()},
        live_team_scope="abc123",
        completed_agent="docs-readme",
    )

    assert report.candidates == ()
    assert "queued work" in report.skipped[0].reason


def test_completion_event_only_targets_named_agent(
    config: Config, teams_dir: Path
) -> None:
    """A live-team completion event cannot reap a sibling teammate."""
    write_inbox(teams_dir, "abc123", "docs-readme", mtime=NOW - 600)
    panes = [
        make_pane(pane_id="%2", pid=200, activity=int(NOW)),
        make_pane(pane_id="%3", pid=201, activity=int(NOW)),
    ]
    processes = {
        200: make_process(),
        201: make_process(
            pid=201,
            command="claude --agent-id api-review@session-abc123",
            state="R+",
        ),
    }

    report = _classify(
        config,
        panes,
        processes,
        live_team_scope="abc123",
        completed_agent="docs-readme",
    )

    assert [c.teammate.agent_name for c in report.candidates] == ["docs-readme"]
    assert all(c.teammate.agent_name != "api-review" for c in report.candidates)


def test_completion_event_keeps_process_safety_guard(
    config: Config, teams_dir: Path
) -> None:
    """A completion event cannot reap a still-running teammate process."""
    write_inbox(teams_dir, "abc123", "docs-readme", mtime=NOW)

    report = _classify(
        config,
        [make_pane(activity=int(NOW))],
        {200: make_process(state="R+")},
        live_team_scope="abc123",
        completed_agent="docs-readme",
    )

    assert report.candidates == ()
    assert "not idle" in report.skipped[0].reason


def test_same_pane_id_on_another_socket_is_still_reapable(
    config: Config, teams_dir: Path
) -> None:
    """Pane ids collide across servers; protection must be socket-qualified.

    Every tmux server numbers panes from %0, so the caller's own id matches a
    different pane on every other socket. Comparing bare ids silently spared
    those teammates — an under-reap of exactly the leak this tool exists to stop,
    and one that got MORE likely after a full tmux restart renumbered everything.
    """
    pane = make_pane(pane_id="%0", socket="/tmp/scratch.sock")
    write_inbox(teams_dir, "abc123", "docs-readme", mtime=DRAINED_LONG_AGO)

    report = _classify(
        config,
        [pane],
        {200: make_process()},
        # Caller sits at %0 on a DIFFERENT server.
        protected_panes={("/private/tmp/tmux-503/default", "%0")},
    )

    assert [c.pane.pane_id for c in report.candidates] == ["%0"]


def test_same_pane_id_on_the_same_socket_is_protected(
    config: Config, teams_dir: Path
) -> None:
    """The guard must still fire for a genuine self-match."""
    pane = make_pane(pane_id="%0", socket="/tmp/scratch.sock")
    write_inbox(teams_dir, "abc123", "docs-readme", mtime=DRAINED_LONG_AGO)

    report = _classify(
        config,
        [pane],
        {200: make_process()},
        protected_panes={("/tmp/scratch.sock", "%0")},
    )

    assert report.candidates == ()
    assert report.skipped[0].reason == "this session"
