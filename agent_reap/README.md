# agent-reap

Finds and reaps idle Claude Code teammate panes across **every** tmux socket.

## The problem

Claude Code agent teams in tmux mode leave one pane per teammate alive after the work is
done. Nothing in the team lifecycle closes them, so they accumulate until they exhaust the
subagent budget. Observed in the wild: 19 idle teammates in a single window holding
**7.18 GB** of resident memory, drained and untouched for 90 minutes.

They are not orphans. They are healthy, attached panes whose leader never receives EOF or
SIGHUP, because nothing ever closes the pane.

## Two facts that shaped the design

**Socket discovery globs the filesystem instead of reading `$TMUX`.** A machine running z4h
has several tmux servers on separate sockets. `tmux kill-server` is socket-scoped, so running
it from the wrong window kills a server the team does not live on and appears to do nothing.
Paths are symlink-resolved before de-duplication — on macOS `/tmp` is a symlink to
`/private/tmp`, so the default socket matches two of the stock globs and would otherwise be
searched twice.

**`tmux kill-pane` is the only kill primitive.** Pane destruction with `remain-on-exit off`
SIGHUPs the pane leader and its non-disowned children, so it is already a complete teardown.
Signal escalation in the normal path would be dead code dressed as a safety net; `--force`
exists only for processes that have no pane at all. Panes are addressed by pane *id* (`%68`),
never by index — indices are positional and renumber as panes die.

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
`~/.claude/hooks/agent-reap-subagent-stop.sh` for `SubagentStop` and
`~/.claude/hooks/agent-reap-session-end.sh` for `SessionEnd`. The former receives the completed
agent and parent team from the event, bypasses only time thresholds for that exact teammate, and
keeps the drained-inbox and process-safety checks. The latter runs a team-scoped reap for an ended
team and removes that exact team's state directory afterward. Solo sessions exit without creating
either log.

A configured hook proves only that generation succeeded, not that a qualifying event ran. Verify
the generated `~/.claude/settings.json`, the hook log, `agent-reap -v sockets`, and the live pane
inventory together. The reaper recognizes Claude teammate command lines and Claude team inboxes;
it is not a general tmux or Codex process collector.

The executable is a side channel owned by `just sync` / `just sync-side-channels`, while the config
is a live out-of-store symlink. The installer deliberately uses `--force --reinstall`: `uv` can
otherwise reuse a stale wheel when local source changes without a version bump.

See the [tmux runtime lifecycle runbook](../docs/ai-tools/tmux-runtime-lifecycle.md) for the broader
source/deployment/runtime/process verification model and the other retained-state failure classes.

## What it will and will not kill

A teammate pane is reaped only when **all** hold: its command carries
`--agent-id <name>@session-<id>`; the team directory exists; its inbox is drained (an empty
JSON container) **and** has been quiet past `teammate_idle_minutes`; the window has also been
quiet past that threshold; the process is sleeping; no active or foreground descendant remains;
and it is not yours. Every condition is checked again immediately before `kill-pane`. "Not yours"
is three independent guards — process ancestry (the
strongest, it works with no tmux environment at all), the current `TMUX_PANE`, and the
caller's own team session.

The `reap --live-team <id> --completed-agent <name> --kill` path is reserved for the
`SubagentStop` hook. It skips the window and inbox-age thresholds for the named agent, but still
requires the team directory, a drained inbox, a sleeping process, no active or foreground
descendant, and immediate pane and ancestry revalidation. It never broadens selection to sibling
teammates.

Never killed without an explicit extra flag:

- **Team leads** — they hold the team's context (`--include-lead`).
- **Idle interactive sessions** — an abandoned Claude window. `^D` does not close a Claude
  pane (measured: neither an empty prompt nor a double tap exits), so these accumulate
  silently. Each may hold conversation context worth more than its memory, so the tool
  reports them and leaves the decision to you.

## Strays

Two leak classes pane teardown provably cannot reach, both report-only:

- **ssh control masters** — `ControlPersist` keeps them alive on purpose; they were never a
  child of the shell that created them.
- **user-owned PPID-1 processes with no pane** — the only measured path by which `^D` can
  leave something behind is `disown`/`nohup`; a plain `sleep &` is SIGHUP'd and does not
  survive.

Selection here is an allowlist (`stray_command_prefixes`), not a blocklist. Blocklisting
system paths was tried first and produced 23 false positives on a real machine: bare-name
launchd jobs, audio drivers, vendor agents under `/usr/local/bin`, and login shells. The
report ends with a single number — how many strays are Claude processes — because that is the
question this category exists to answer.

## Configuration

`~/.config/agent-reap/config.toml`, a live out-of-store symlink from the dotfiles repo. Every
field has a working default and a missing file is normal. A malformed file degrades to
defaults with a warning for report-only commands: a config typo must not stop you from seeing what
is leaking. Destructive commands fail closed on any config error. Explicit operator-driven
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
tmux or signals a real process — a hard requirement for a tool whose job is killing things.
