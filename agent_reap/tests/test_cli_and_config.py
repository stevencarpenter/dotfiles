"""End-to-end CLI behavior and config loading."""

from __future__ import annotations

import json
from dataclasses import dataclass
from pathlib import Path

import pytest

from agent_reap.cli import _revalidate_candidate, build_report, cli
from agent_reap.config import Config, load_config
from agent_reap.runner import RecordingRunner, Result

from .conftest import NOW, make_socket, pane_line, write_inbox


@dataclass(frozen=True)
class Machine:
    """A fully stubbed machine for CLI tests.

    Attributes:
        config_path: Config file wired to the fake socket and teams dirs.
        runner: Runner stubbed for this machine's tmux and ps output.
        socket: Path of the fake tmux socket.
    """

    config_path: Path
    runner: RecordingRunner
    socket: Path


@pytest.fixture
def wired(
    tmp_path: Path, short_tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> Machine:
    """Build a fake machine: one socket, one teammate pane, one drained inbox.

    Args:
        tmp_path: Pytest temporary directory for files.
        short_tmp_path: Short directory, required for binding a unix socket.
        monkeypatch: Fixture used to clear inherited session env vars.

    Returns:
        The stubbed machine.
    """
    monkeypatch.delenv("TMUX_PANE", raising=False)
    monkeypatch.delenv("CLAUDE_SESSION_ID", raising=False)
    monkeypatch.delenv("CODEX_COMPANION_SESSION_ID", raising=False)
    monkeypatch.delenv("TMUX", raising=False)

    sockets_dir = short_tmp_path / "s"
    sockets_dir.mkdir()
    sock_path = make_socket(sockets_dir / "default")

    teams = tmp_path / "teams"
    teams.mkdir()
    write_inbox(teams, "abc123", "docs-readme", mtime=1.0)

    config_path = tmp_path / "config.toml"
    config_path.write_text(
        "\n".join(
            [
                f'socket_globs = ["{sockets_dir}/*"]',
                f'teams_dir = "{teams}"',
                f'ssh_dir = "{tmp_path / "ssh"}"',
                "teammate_idle_minutes = 30",
            ]
        ),
        encoding="utf-8",
    )

    row = pane_line("%2", "devbox", 1, 2, 200, 10, "2.1.221", "/repo")
    runner = RecordingRunner(
        responses={
            f"tmux -S {sock_path} list-sessions": Result(0, "devbox: 3 windows"),
            f"tmux -S {sock_path} list-panes": Result(0, row),
            "ps -eo": Result(
                0,
                "200 100 200 200 400000 Ss+ 01:40:24 "
                "claude --agent-id docs-readme@session-abc123",
            ),
            f"tmux -S {sock_path} kill-pane": Result(0),
        }
    )
    return Machine(config_path=config_path, runner=runner, socket=sock_path)


def test_report_lists_the_candidate(
    wired: Machine, capsys: pytest.CaptureFixture[str]
) -> None:
    """The default command surfaces the reapable teammate and its memory."""
    assert cli(["--config", str(wired.config_path), "report"], runner=wired.runner) == 0

    out = capsys.readouterr().out
    assert "docs-readme" in out
    assert "reapable teammates: 1" in out


def test_report_json_is_machine_readable(
    wired: Machine, capsys: pytest.CaptureFixture[str]
) -> None:
    """``--json`` emits parseable output with the fields a caller needs."""
    cli(["--config", str(wired.config_path), "--json", "report"], runner=wired.runner)

    payload = json.loads(capsys.readouterr().out)
    assert payload["candidates"][0]["agent"] == "docs-readme"
    assert payload["candidates"][0]["pane_id"] == "%2"
    assert payload["reclaimable_kb"] == 400_000


def test_reap_without_kill_flag_touches_nothing(
    wired: Machine, capsys: pytest.CaptureFixture[str]
) -> None:
    """Report-only is the default even for the reap subcommand."""
    cli(["--config", str(wired.config_path), "reap"], runner=wired.runner)

    assert not any("kill-pane" in " ".join(c) for c in wired.runner.calls)
    assert "dry run" in capsys.readouterr().out


def test_reap_with_kill_flag_kills_by_pane_id(wired: Machine) -> None:
    """``--kill`` issues exactly one kill-pane against the stable pane id."""
    status = cli(
        ["--config", str(wired.config_path), "reap", "--kill"], runner=wired.runner
    )

    assert status == 0
    kills = [c for c in wired.runner.calls if "kill-pane" in c]
    assert len(kills) == 1
    assert kills[0][-1] == "%2"


def test_revalidation_observes_activity_after_initial_report(wired: Machine) -> None:
    """Fresh output between reporting and killing invalidates the candidate."""
    config = load_config(wired.config_path).config
    initial = build_report(config, wired.runner, now=NOW)
    assert len(initial.candidates) == 1
    wired.runner.responses[f"tmux -S {wired.socket} list-panes"] = Result(
        0,
        pane_line("%2", "devbox", 1, 2, 200, int(NOW), "2.1.221", "/repo"),
    )

    valid, reason = _revalidate_candidate(
        initial.candidates[0],
        config=config,
        runner=wired.runner,
        team_scope=None,
        now=NOW,
    )

    assert valid is False
    assert "window active" in reason


def test_json_reap_failure_is_nonzero_and_socket_qualified(
    wired: Machine, capsys: pytest.CaptureFixture[str]
) -> None:
    """Machine consumers can identify and reject a failed cross-socket kill."""
    wired.runner.responses[f"tmux -S {wired.socket} kill-pane"] = Result(
        1, stderr="simulated failure"
    )

    status = cli(
        ["--config", str(wired.config_path), "--json", "reap", "--kill"],
        runner=wired.runner,
    )

    payload = json.loads(capsys.readouterr().out)
    assert status == 1
    assert payload[0] == {
        "pane_id": "%2",
        "socket": str(wired.socket),
        "target": "devbox:1.2",
        "agent": "docs-readme",
        "session": "abc123",
        "killed": False,
        "detail": "simulated failure",
    }


def test_team_kill_requires_unattended_policy(
    wired: Machine, capsys: pytest.CaptureFixture[str]
) -> None:
    """The SessionEnd-style path cannot kill while its policy gate is disabled."""
    status = cli(
        [
            "--config",
            str(wired.config_path),
            "reap",
            "--team",
            "abc123",
            "--kill",
        ],
        runner=wired.runner,
    )

    assert status == 2
    assert "kill_enabled" in capsys.readouterr().err
    assert not any("kill-pane" in call for call in map(" ".join, wired.runner.calls))


def test_team_kill_runs_when_unattended_policy_is_enabled(wired: Machine) -> None:
    """An enabled targeted cleanup still revalidates and destroys its team pane."""
    with wired.config_path.open("a", encoding="utf-8") as config_file:
        config_file.write("\nkill_enabled = true\n")

    status = cli(
        [
            "--config",
            str(wired.config_path),
            "reap",
            "--team",
            "abc123",
            "--kill",
        ],
        runner=wired.runner,
    )

    assert status == 0
    assert sum("kill-pane" in call for call in map(" ".join, wired.runner.calls)) == 1


def test_completion_event_kill_requires_unattended_policy(
    wired: Machine, capsys: pytest.CaptureFixture[str]
) -> None:
    """The live-team completion path has the same unattended policy gate."""
    status = cli(
        [
            "--config",
            str(wired.config_path),
            "reap",
            "--live-team",
            "abc123",
            "--completed-agent",
            "docs-readme",
            "--kill",
        ],
        runner=wired.runner,
    )

    assert status == 2
    assert "kill_enabled" in capsys.readouterr().err
    assert not any("kill-pane" in call for call in map(" ".join, wired.runner.calls))


def test_completion_event_kills_only_the_confirmed_agent(wired: Machine) -> None:
    """A SubagentStop-targeted reap uses the completion grace, not the 30m window."""
    with wired.config_path.open("a", encoding="utf-8") as config_file:
        config_file.write("\nkill_enabled = true\n")

    status = cli(
        [
            "--config",
            str(wired.config_path),
            "reap",
            "--live-team",
            "abc123",
            "--completed-agent",
            "docs-readme",
            "--kill",
        ],
        runner=wired.runner,
    )

    assert status == 0
    kills = [call for call in wired.runner.calls if "kill-pane" in call]
    assert len(kills) == 1
    assert kills[0][-1] == "%2"


def test_completion_event_options_must_be_paired(
    wired: Machine, capsys: pytest.CaptureFixture[str]
) -> None:
    """An incomplete event scope cannot accidentally become a broad reap."""
    status = cli(
        [
            "--config",
            str(wired.config_path),
            "reap",
            "--live-team",
            "abc123",
        ],
        runner=wired.runner,
    )

    assert status == 2
    assert "provided together" in capsys.readouterr().err
    assert not any("kill-pane" in call for call in map(" ".join, wired.runner.calls))


def test_idle_minutes_override_spares_a_fresh_inbox(
    wired: Machine, capsys: pytest.CaptureFixture[str]
) -> None:
    """A large threshold turns the candidate back into a skip."""
    cli(
        ["--config", str(wired.config_path), "--idle-minutes", "999999999", "report"],
        runner=wired.runner,
    )

    assert "reapable teammates: 0" in capsys.readouterr().out


def test_negative_idle_minutes_is_rejected(
    wired: Machine, capsys: pytest.CaptureFixture[str]
) -> None:
    """A CLI override cannot turn every fresh teammate into an idle candidate."""
    with pytest.raises(SystemExit) as raised:
        cli(
            [
                "--config",
                str(wired.config_path),
                "--idle-minutes",
                "-1",
                "reap",
                "--kill",
            ],
            runner=wired.runner,
        )

    assert raised.value.code == 2
    assert "non-negative integer" in capsys.readouterr().err
    assert not any("kill-pane" in call for call in map(" ".join, wired.runner.calls))


def test_sockets_marks_the_current_server(
    wired: Machine,
    capsys: pytest.CaptureFixture[str],
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    """The current marker survives a /tmp-style symlink alias."""
    alias = wired.socket.parent.parent / "socket-alias"
    alias.symlink_to(wired.socket.parent, target_is_directory=True)
    monkeypatch.setenv("TMUX", f"{alias / wired.socket.name},7068,0")

    cli(["--config", str(wired.config_path), "sockets"], runner=wired.runner)

    out = capsys.readouterr().out
    assert "<- $TMUX" in out
    assert "devbox: 3 windows" in out


def test_strays_reports_zero_when_nothing_escaped(
    wired: Machine, capsys: pytest.CaptureFixture[str]
) -> None:
    """With no disowned Claude processes the Ctrl+D hypothesis reads unsupported."""
    cli(["--config", str(wired.config_path), "strays"], runner=wired.runner)

    out = capsys.readouterr().out
    assert "claude processes among them: 0" in out
    assert "no evidence of Claude processes escaping pane teardown" in out


def test_missing_config_falls_back_to_defaults(tmp_path: Path) -> None:
    """An absent config file is normal, not an error."""
    loaded = load_config(tmp_path / "nope.toml")

    assert loaded.path is None
    assert loaded.config == Config()


def test_malformed_config_degrades_instead_of_raising(tmp_path: Path) -> None:
    """A syntax error still lets you see what is leaking."""
    path = tmp_path / "config.toml"
    path.write_text("this is not toml =", encoding="utf-8")

    loaded = load_config(path)

    assert loaded.config == Config()
    assert loaded.errors and "unreadable config" in loaded.errors[0]


def test_bad_field_types_fall_back_per_key(tmp_path: Path) -> None:
    """One bad key does not discard the whole file."""
    path = tmp_path / "config.toml"
    path.write_text(
        'teammate_idle_minutes = "soon"\ninteractive_idle_minutes = 15\n',
        encoding="utf-8",
    )

    loaded = load_config(path)

    assert loaded.config.teammate_idle_minutes == Config().teammate_idle_minutes
    assert loaded.config.interactive_idle_minutes == 15
    assert any("teammate_idle_minutes" in e for e in loaded.errors)


def test_unknown_config_key_is_reported(tmp_path: Path) -> None:
    """Typos cannot silently remove a safety policy from destructive runs."""
    path = tmp_path / "config.toml"
    path.write_text("deny_agent_name = []\n", encoding="utf-8")

    loaded = load_config(path)

    assert loaded.errors == ("unknown key: deny_agent_name",)


def test_destructive_mode_fails_closed_on_config_error(
    wired: Machine, capsys: pytest.CaptureFixture[str]
) -> None:
    """Reports may degrade, but a kill never runs with a partially trusted policy."""
    with wired.config_path.open("a", encoding="utf-8") as config_file:
        config_file.write("\nunknown_policy = true\n")

    status = cli(
        ["--config", str(wired.config_path), "reap", "--kill"],
        runner=wired.runner,
    )

    assert status == 2
    assert "invalid config" in capsys.readouterr().err
    assert not any("kill-pane" in call for call in map(" ".join, wired.runner.calls))


def test_socket_globs_substitute_the_uid() -> None:
    """``{uid}`` is expanded so one config works on every machine."""
    config = Config(socket_globs=("/private/tmp/tmux-{uid}/*",))
    assert config.resolved_globs(uid=501) == ("/private/tmp/tmux-501/*",)


def test_env_var_selects_the_config(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    """AGENT_REAP_CONFIG makes the hook's kill path testable and launchd-friendly."""
    path = tmp_path / "env.toml"
    path.write_text("teammate_idle_minutes = 7\n", encoding="utf-8")
    monkeypatch.setenv("AGENT_REAP_CONFIG", str(path))

    assert load_config().config.teammate_idle_minutes == 7


def test_explicit_config_beats_the_env_var(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    """An explicit --config must win over the environment."""
    env = tmp_path / "env.toml"
    env.write_text("teammate_idle_minutes = 7\n", encoding="utf-8")
    explicit = tmp_path / "explicit.toml"
    explicit.write_text("teammate_idle_minutes = 99\n", encoding="utf-8")
    monkeypatch.setenv("AGENT_REAP_CONFIG", str(env))

    assert load_config(explicit).config.teammate_idle_minutes == 99
