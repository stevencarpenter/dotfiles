# agent-reap

Finds and reaps idle Claude Code teammate panes across **every** tmux socket.

## The problem

Claude Code agent teams in tmux mode leave one pane per teammate alive after the work is
done. Nothing in the team lifecycle closes them, so they accumulate until they exhaust the
subagent budget. One observed window held 19 idle teammates using
**7.18 GB** of resident memory, drained and untouched for 90 minutes.

The panes remain attached until explicitly closed.

## Two facts that shaped the design

**Socket discovery globs the filesystem instead of reading `$TMUX`.** A machine running z4h
has several tmux servers on separate sockets. `tmux kill-server` is socket-scoped, so running
it from the wrong window kills a server the team does not live on and appears to do nothing.
Paths are symlink-resolved before de-duplication: on macOS `/tmp` is a symlink to
`/private/tmp`, so the default socket matches two of the stock globs and would otherwise be
searched twice.

**`tmux kill-pane` is the only kill primitive.** Pane destruction with `remain-on-exit off`
SIGHUPs the pane leader and its non-disowned children, so it is already a complete teardown.
`--force` exists only for processes that have no pane at all. Panes are addressed by pane *id* (`%68`),
never by index: indices are positional and renumber as panes die.

## Usage

```bash
agent-reap                 # report: reapable teammates + idle interactive sessions
agent-reap sockets         # every tmux server, and which one $TMUX points at
agent-reap strays          # ssh control masters + disowned descendants
agent-reap reap            # dry run
agent-reap reap --kill     # actually reap
agent-reap --json report   # machine-readable
agent-reap -v report       # include the reason every pane was excluded
```

## Lifecycle and automatic cleanup

`agent-reap` is not a daemon and this repo installs no launchd job for it. Automatic cleanup is
event-driven: the generated Claude settings register
`~/.claude/hooks/agent-reap-stop.sh` for `Stop` and
`~/.claude/hooks/agent-reap-session-end.sh` for `SessionEnd`. The former runs after each of the
lead's turns, detached, as `reap --live-team <lead session> --kill`: only the lead's own
teammates are considered, and every liveness gate still applies. It is the only lead-side moment
that follows a split-pane teammate's report (`TeammateIdle` fires for in-process teammates only).
The latter runs a team-scoped reap for an ended
team and removes that exact team's state directory afterward. Solo sessions exit without creating
either log.

A configured hook proves only that generation succeeded, not that a qualifying event ran. Verify
the generated `~/.claude/settings.json`, the hook log, `agent-reap -v sockets`, and the live pane
inventory together. The reaper recognizes Claude teammate command lines and Claude team inboxes;
it is not a general tmux or Codex process collector.

The executable is a side channel owned by `just sync` / `just sync-side-channels`, while the config
is a live out-of-store symlink. The installer uses `--force --reinstall`: `uv` can
otherwise reuse a stale wheel when local source changes without a version bump.

See the [tmux runtime lifecycle runbook](../docs/ai-tools/tmux-runtime-lifecycle.md) for the broader
source/deployment/runtime/process verification model and the other retained-state failure classes.

## What it will and will not kill

A teammate pane is reaped only when **all** hold: its command carries
`--agent-id <name>@session-<id>`; the team directory exists; its inbox is drained (an empty
JSON container) **and** has been quiet past `teammate_idle_minutes`; its pane title starts with
Claude's ✳ waiting marker (a braille spinner means working, and any other title fails closed);
the process is sleeping; no active or foreground descendant remains;
and it is not yours. Every condition is checked again immediately before `kill-pane`. "Not yours"
is enforced by process ancestry (which works without a tmux environment), the current `TMUX_PANE`, and the
caller's own team session.

tmux's `window_activity` is not an idle signal for a Claude pane: the TUI redraws while it
waits for input, so the timestamp never ages past a few seconds.

`reap --live-team <id> --kill` lifts the own-team guard for that one team so the lead's `Stop`
hook can reap its own finished teammates; nothing else changes. Adding `--completed-agent <name>`
narrows it to one teammate named by a completion event: the title gate is skipped and inbox-age
shortens to `completion_grace_seconds`, while the team directory, drained inbox, sleeping
process, descendant, and revalidation checks still hold. No shipped hook uses that form today.

Never killed without an explicit extra flag:

- **Team leads**: they hold the team's context (`--include-lead`).
- **Idle interactive sessions**: an abandoned Claude window. `^D` does not close a Claude
  pane (measured: neither an empty prompt nor a double tap exits), so these accumulate
  silently. The tool reports these sessions and requires explicit permission to close them.

## Strays

Two leak classes pane teardown provably cannot reach, both report-only:

- **ssh control masters**: `ControlPersist` keeps them alive on purpose; they were never a
  child of the shell that created them.
- **user-owned PPID-1 processes with no pane**: the only measured path by which `^D` can
  leave something behind is `disown`/`nohup`; a plain `sleep &` is SIGHUP'd and does not
  survive.

`stray_command_prefixes` selects processes by allowlist. This excludes unrelated launchd
jobs, drivers, vendor agents, and login shells. The report counts Claude processes separately.

## Configuration

`~/.config/agent-reap/config.toml`, a live out-of-store symlink from the dotfiles repo. Every
field has a working default and a missing file is normal. A malformed file degrades to
defaults with a warning for report-only commands. Destructive commands fail closed on any config error. Explicit operator-driven
`reap --kill` remains available regardless of `kill_enabled`; unattended `--team ... --kill`
cleanup requires `kill_enabled = true`.

## Development

```bash
uv run --project agent_reap --group dev ruff check agent_reap/src agent_reap/tests
uv run --project agent_reap --group dev ruff format agent_reap/src agent_reap/tests
uv run --project agent_reap --group dev mypy agent_reap/src agent_reap/tests
uv run --project agent_reap --group dev pytest agent_reap/tests --cov=agent_reap
```

Every external command goes through an injected `Runner`, so no test shells out to a real
tmux or signals a real process.
