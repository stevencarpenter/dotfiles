"""The kill path and the stray inventory."""

from __future__ import annotations

import subprocess
from pathlib import Path
from typing import Never

import pytest

from agent_reap.classify import Candidate
from agent_reap.reap import kill_pane, reap
from agent_reap.runner import (
    COMMAND_TIMEOUT_SECONDS,
    RecordingRunner,
    Result,
    subprocess_runner,
)
from agent_reap.strays import control_masters, disowned_descendants
from agent_reap.teams import Inbox

from .conftest import make_pane, make_process, make_socket


def _candidate(pane_id: str = "%2", socket: str = "/tmp/s") -> Candidate:
    """Build a candidate for kill-path tests.

    Args:
        pane_id: Stable pane id.
        socket: Owning socket.

    Returns:
        A candidate wrapping synthetic pane and process rows.
    """
    from agent_reap.discover import Teammate

    return Candidate(
        pane=make_pane(pane_id=pane_id, socket=socket),
        process=make_process(),
        teammate=Teammate(agent_name="docs-readme", session_id="abc123"),
        inbox=Inbox(path=Path("/tmp/inbox.json"), exists=True, size=2, mtime=0.0),
        idle_s=5400.0,
    )


def _valid(candidate: Candidate) -> tuple[bool, str]:
    """Approve a synthetic candidate after a fresh safety check."""
    del candidate
    return True, ""


def test_kill_targets_pane_id_not_index() -> None:
    """Kills address ``%id`` so renumbering cannot retarget them mid-loop."""
    runner = RecordingRunner(responses={"tmux -S /tmp/s kill-pane": Result(0)})

    ok, detail = kill_pane("/tmp/s", "%2", runner)

    assert ok and detail == ""
    assert runner.calls == [["tmux", "-S", "/tmp/s", "kill-pane", "-t", "%2"]]


def test_dry_run_executes_nothing() -> None:
    """The default path must not touch tmux at all."""
    runner = RecordingRunner()

    outcomes = reap((_candidate(),), runner, dry_run=True)

    assert runner.calls == []
    assert [o.killed for o in outcomes] == [False]
    assert outcomes[0].detail == "dry-run"


def test_reap_kills_each_candidate_on_its_own_socket() -> None:
    """Candidates from different servers are killed against the right socket."""
    runner = RecordingRunner(responses={"tmux -S": Result(0)})

    outcomes = reap(
        (_candidate("%2", "/tmp/a"), _candidate("%9", "/tmp/b")),
        runner,
        dry_run=False,
        revalidator=_valid,
    )

    assert all(o.killed for o in outcomes)
    assert [c[2] for c in runner.calls] == ["/tmp/a", "/tmp/b"]


def test_failed_kill_is_reported_not_swallowed() -> None:
    """A kill that fails surfaces its error text."""
    runner = RecordingRunner(default=Result(1, stderr="can't find pane"))

    (outcome,) = reap((_candidate(),), runner, dry_run=False, revalidator=_valid)

    assert outcome.killed is False
    assert "can't find pane" in outcome.detail


def test_real_reap_fails_closed_without_revalidation() -> None:
    """No caller can accidentally bypass the immediate destructive safety check."""
    runner = RecordingRunner(responses={"tmux -S": Result(0)})

    (outcome,) = reap((_candidate(),), runner, dry_run=False)

    assert outcome.killed is False
    assert "revalidation unavailable" in outcome.detail
    assert runner.calls == []


def test_revalidation_rejection_prevents_kill() -> None:
    """A candidate that became active after reporting is not destroyed."""
    runner = RecordingRunner(responses={"tmux -S": Result(0)})

    (outcome,) = reap(
        (_candidate(),),
        runner,
        dry_run=False,
        revalidator=lambda _candidate: (False, "window became active"),
    )

    assert outcome.killed is False
    assert outcome.detail == "revalidation failed: window became active"
    assert runner.calls == []


def test_subprocess_runner_bounds_a_stuck_tmux_client(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    """A server that accepts but never responds cannot hang discovery forever."""
    observed: dict[str, object] = {}

    def time_out(*_args: object, **kwargs: object) -> Never:
        observed.update(kwargs)
        raise subprocess.TimeoutExpired("tmux", COMMAND_TIMEOUT_SECONDS)

    monkeypatch.setattr("agent_reap.runner.subprocess.run", time_out)

    result = subprocess_runner(["tmux", "-S", "/stuck", "list-sessions"])

    assert observed["timeout"] == COMMAND_TIMEOUT_SECONDS
    assert result.returncode == 124
    assert "timed out" in result.stderr


def test_control_master_socket_without_process_is_stale(short_tmp_path: Path) -> None:
    """A leftover socket file is flagged."""
    make_socket(short_tmp_path / "cm-github-abc")

    (master,) = control_masters(short_tmp_path, {})

    assert master.socket_exists is True
    assert master.pid is None
    assert master.stale is True


def test_control_master_process_and_socket_pair_up(short_tmp_path: Path) -> None:
    """A live master with its socket present is not stale."""
    path = make_socket(short_tmp_path / "cm-github-abc")
    processes = {
        37441: make_process(
            pid=37441, ppid=1, command=f"ssh: {path} [mux]", elapsed_s=8000
        )
    }

    (master,) = control_masters(short_tmp_path, processes)

    assert master.pid == 37441
    assert master.stale is False
    assert master.elapsed_s == 8000


def test_control_master_process_without_socket_is_stale(tmp_path: Path) -> None:
    """A master whose socket was deleted is flagged from the process side."""
    processes = {1: make_process(pid=1, command="ssh: /gone/cm-x [mux]")}

    (master,) = control_masters(tmp_path, processes)

    assert master.socket_exists is False
    assert master.stale is True


def test_control_master_probe_records_responsiveness(short_tmp_path: Path) -> None:
    """``ssh -O check`` results are recorded when a runner is supplied."""
    make_socket(short_tmp_path / "cm-x")
    runner = RecordingRunner(responses={"ssh -O check": Result(0)})

    (master,) = control_masters(short_tmp_path, {}, runner)

    assert master.responding is True


INTEREST = ("/Users/dev/", "/nix/store/")


def test_disowned_ignores_system_daemons_and_apps() -> None:
    """Only user-owned processes count as strays."""
    processes = {
        1: make_process(pid=1, ppid=1, command="/usr/libexec/secd"),
        2: make_process(
            pid=2, ppid=1, command="/Applications/Ghostty.app/Contents/MacOS/ghostty"
        ),
        3: make_process(
            pid=3, ppid=1, command="/System/Library/CoreServices/loginwindow.app x"
        ),
        4: make_process(pid=4, ppid=1, command="/Users/dev/.local/bin/claude --ide"),
    }

    assert [p.pid for p in disowned_descendants(processes, set(), INTEREST)] == [4]


def test_disowned_ignores_bare_name_launchd_jobs() -> None:
    """Daemons invoked by bare name cannot be descendants of a shell.

    These produced most of the false positives on a real machine.
    """
    processes = {
        1: make_process(pid=1, ppid=1, command="endpointsecurityd"),
        2: make_process(pid=2, ppid=1, command="automountd"),
        3: make_process(pid=3, ppid=1, command="Core Audio Driver (Zoom.driver)"),
    }

    assert disowned_descendants(processes, set(), INTEREST) == []


def test_disowned_ignores_login_shells() -> None:
    """``-zsh`` is a login shell, legitimately parented by launchd."""
    processes = {1625: make_process(pid=1625, ppid=1, command="-zsh")}
    assert disowned_descendants(processes, set(), INTEREST) == []


def test_disowned_ignores_paths_outside_the_interest_list() -> None:
    """Vendor agents under /usr/local/bin are not shell descendants."""
    processes = {
        871: make_process(pid=871, ppid=1, command="/usr/local/bin/vendor-agent")
    }
    assert disowned_descendants(processes, set(), INTEREST) == []


def test_disowned_finds_a_nix_store_binary() -> None:
    """A disowned nix-store executable is user-owned and reported."""
    processes = {5: make_process(pid=5, ppid=1, command="/nix/store/abc-uv/bin/uv run")}
    assert [p.pid for p in disowned_descendants(processes, set(), INTEREST)] == [5]


def test_disowned_ignores_the_tmux_server() -> None:
    """A tmux server daemonizes to PPID 1 by design; that is not a leak."""
    processes = {
        7068: make_process(pid=7068, ppid=1, command="/Users/dev/bin/tmux new -A")
    }
    assert disowned_descendants(processes, set(), INTEREST) == []


def test_disowned_ignores_pane_leaders() -> None:
    """A pane leader is accounted for even when reparented."""
    processes = {9: make_process(pid=9, ppid=1, command="/Users/dev/.local/bin/claude")}
    assert disowned_descendants(processes, {9}, INTEREST) == []
