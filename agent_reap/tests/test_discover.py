"""Discovery: socket enumeration, pane parsing, and the process table."""

from __future__ import annotations

from pathlib import Path

from agent_reap.discover import (
    ancestry,
    find_sockets,
    list_panes,
    live_sockets,
    parse_etime,
    parse_teammate,
    process_table,
)
from agent_reap.runner import RecordingRunner, Result

from .conftest import make_process, make_socket, pane_line


def test_find_sockets_covers_every_shape(short_tmp_path: Path) -> None:
    """All three real-world socket layouts are discovered, regular files are not."""
    stock = short_tmp_path / "tmux-501"
    stock.mkdir()
    make_socket(stock / "default")
    make_socket(short_tmp_path / "z4h-tmux-501-1455")
    (short_tmp_path / "not-a-socket").write_text("", encoding="utf-8")

    found = find_sockets(
        [
            str(stock / "*"),
            str(short_tmp_path / "z4h-tmux-501-*"),
            str(short_tmp_path / "*"),
        ]
    )

    assert str(stock / "default") in found
    assert str(short_tmp_path / "z4h-tmux-501-1455") in found
    assert str(short_tmp_path / "not-a-socket") not in found


def test_find_sockets_is_deduplicated(short_tmp_path: Path) -> None:
    """Overlapping globs yield each socket once."""
    make_socket(short_tmp_path / "sock")
    found = find_sockets([str(short_tmp_path / "*"), str(short_tmp_path / "sock")])
    assert found == [str((short_tmp_path / "sock").resolve())]


def test_find_sockets_collapses_symlinked_roots(short_tmp_path: Path) -> None:
    """A socket reachable through a symlinked directory is one server, not two.

    This is the /tmp -> /private/tmp case on macOS: the stock globs match the same
    default socket twice, which would double-count every pane on that server.
    """
    real = short_tmp_path / "real"
    real.mkdir()
    make_socket(real / "default")
    (short_tmp_path / "alias").symlink_to(real)

    found = find_sockets([str(real / "*"), str(short_tmp_path / "alias" / "*")])

    assert found == [str((real / "default").resolve())]


def test_live_sockets_drops_stale_socket_files() -> None:
    """A socket file whose server has exited is filtered out."""
    runner = RecordingRunner(
        responses={"tmux -S /live list-sessions": Result(0, "main: 1 windows")},
        default=Result(1, stderr="no server running"),
    )
    assert live_sockets(["/live", "/dead"], runner) == ["/live"]


def test_list_panes_parses_every_field() -> None:
    """A well-formed row maps onto the Pane dataclass."""
    row = pane_line(
        "%68", "devbox", 3, 1, 34033, 1785832415, "2.1.221", "/Users/dev/.dotfiles"
    )
    runner = RecordingRunner(responses={"tmux -S /s list-panes": Result(0, row)})

    (pane,) = list_panes("/s", runner)

    assert pane.pane_id == "%68"
    assert pane.target == "devbox:3.1"
    assert pane.pid == 34033
    assert pane.window_activity == 1785832415
    assert pane.path == "/Users/dev/.dotfiles"


def test_list_panes_tolerates_missing_activity_and_paths_with_tabs() -> None:
    """An empty activity field parses as None; a tab in the path stays in the path."""
    row = pane_line("%1", "s", 1, 1, 10, "", "zsh", "/tmp/od\td")
    runner = RecordingRunner(responses={"tmux -S /s list-panes": Result(0, row)})

    (pane,) = list_panes("/s", runner)

    assert pane.window_activity is None
    assert pane.path == "/tmp/od\td"


def test_list_panes_skips_malformed_rows() -> None:
    """Short or non-numeric rows are dropped rather than raising."""
    good = pane_line("%1", "s", 1, 1, 10, 5, "zsh", "/tmp")
    rows = f"too\tfew\n\n{good}"
    runner = RecordingRunner(responses={"tmux -S /s list-panes": Result(0, rows)})
    assert [p.pane_id for p in list_panes("/s", runner)] == ["%1"]


def test_list_panes_returns_empty_when_server_is_gone() -> None:
    """A failed listing is not an error."""
    assert list_panes("/s", RecordingRunner(default=Result(1))) == []


def test_parse_teammate_extracts_name_and_session() -> None:
    """The observed teammate argv shape is recognised."""
    teammate = parse_teammate(
        "/Users/dev/.local/share/claude/versions/2.1.221 "
        "--agent-id docs-readme@session-d50ed876 --agent-name docs-readme"
    )
    assert teammate is not None
    assert teammate.agent_name == "docs-readme"
    assert teammate.session_id == "d50ed876"


def test_parse_teammate_ignores_plain_sessions() -> None:
    """An interactive Claude process is not a teammate."""
    assert parse_teammate("/Users/dev/.local/bin/claude --ide --resume") is None


def test_parse_etime_handles_all_ps_shapes() -> None:
    """Elapsed times parse across the MM:SS, HH:MM:SS and D-HH:MM:SS forms."""
    assert parse_etime("00:42") == 42
    assert parse_etime("01:40:24") == 6024
    assert parse_etime("17-04:06:41") == 1_483_601
    assert parse_etime("garbage") == 0


def test_process_table_keeps_spaces_in_command() -> None:
    """The command column is not split on its internal spaces."""
    runner = RecordingRunner(
        responses={
            "ps -eo": Result(
                0, "  200   100 400000 Ss+   01:40:24 claude --agent-id a@b"
            )
        }
    )
    table = process_table(runner)
    assert table[200].command == "claude --agent-id a@b"
    assert table[200].rss_kb == 400_000
    assert table[200].sleeping is True


def test_process_table_marks_running_processes_busy() -> None:
    """A running process is not considered idle."""
    runner = RecordingRunner(responses={"ps -eo": Result(0, "1 0 10 R 00:01 busy")})
    assert process_table(runner)[1].sleeping is False


def test_ancestry_walks_to_the_root() -> None:
    """A pid's full ancestor chain is collected."""
    table = {
        400: make_process(pid=400, ppid=300),
        300: make_process(pid=300, ppid=200),
        200: make_process(pid=200, ppid=1),
        1: make_process(pid=1, ppid=1),
    }
    assert ancestry(400, table) == {400, 300, 200, 1}


def test_ancestry_survives_a_parent_cycle() -> None:
    """A malformed table cannot hang the walk."""
    table = {2: make_process(pid=2, ppid=3), 3: make_process(pid=3, ppid=2)}
    assert ancestry(2, table) == {2, 3}
