# Tmux and Agent Runtime Lifecycle

Tmux, z4h, Claude Code, and side-channel tools all retain runtime state outside the tracked
configuration. A correct file in this repo does not prove that a long-lived server, pane, hook, or
installed tool is using it. Retained state can affect later shells and sessions.

Use this guide when tmux opens a shell in an unexpected directory, detaching closes the terminal,
agent panes survive completed work, a removed plugin still changes behavior, or a deployed tool
does not match the checkout.

## The four layers to verify

Always inspect all four layers before calling a runtime-state problem fixed:

1. **Tracked source**: the file under `home/`, `modules/`, or `scripts/`.
2. **Deployed artifact**: the live symlink, generated config, or installed executable.
3. **Long-lived runtime**: tmux server options, key bindings, environment, panes, and hooks.
4. **Processes and sockets**: what survived, who owns it, and which tmux server it belongs to.

Useful read-only checks:

```bash
git status --short --branch
realpath ~/.config/tmux/tmux.conf ~/.config/zsh/.zshrc ~/.config/agent-reap/config.toml

tmux display-message -p 'socket=#{socket_path} session=#{session_name} client=#{client_tty}'
tmux list-sessions -F '#{session_name} attached=#{session_attached} windows=#{session_windows}'
tmux list-panes -a -F '#{session_name}:#{window_index}.#{pane_index} pid=#{pane_pid} path=#{pane_current_path} cmd=#{pane_current_command}'
tmux list-keys -T prefix | rg 'new-window|split-window|detach-client'
tmux show-options -g

agent-reap -v sockets
agent-reap -v report
agent-reap strays
ps -axo pid,ppid,tty,lstart,command | rg 'tmux|zsh|claude|codex'
```

`agent-reap` commands are report-only unless the `reap` subcommand receives an explicit kill
flag. Do not substitute `tmux kill-server` as a diagnostic: it acts on one socket and destroys
state before proving which server owns the problem.

## Working-directory inheritance

Bare `new-window` and `split-window` commands inherit a working directory from tmux's current
context. With a long-lived agent in the foreground, that can be the directory where the agent was
launched rather than the location the user expects.

The prefix bindings in `home/.config/tmux/tmux.conf` deliberately break that inheritance:

```tmux
bind c new-window -c "$HOME"
bind | split-window -h -c "$HOME"
bind - split-window -v -c "$HOME"
```

This contract covers `prefix c`, `prefix |`, and `prefix -`. A script, plugin, mouse menu, or agent
that invokes `tmux new-window` directly must also pass `-c "$HOME"` when home is the intended
directory. Window naming is a separate concern: this config derives names from `pane_title` and
keeps `allow-rename` off.

After editing the raw config, reload the existing server and verify the effective bindings:

```bash
tmux source-file ~/.config/tmux/tmux.conf
tmux list-keys -T prefix | rg 'new-window|split-window'
```

No apply is needed for the raw file. Reload it explicitly in an already-running tmux server.
`scripts/test-tmux-lifecycle-contract.sh` loads the config into an isolated server in CI to
test pane classification and cleanup. Key bindings and working-directory choices remain preferences.

## Explicit tmux startup and detach behavior

The current z4h setting is `zstyle ':z4h:' start-tmux no`. A terminal starts as a normal outer zsh;
run `tmux` explicitly when a persistent session is wanted. `prefix d` then detaches back to that
outer shell instead of closing the terminal tab. Explicit tmux still uses the default socket and
loads `~/.config/tmux/tmux.conf`, including the `$HOME` cwd bindings and Claude state monitor.

The rejected `start-tmux system` policy used `exec tmux -u`, replacing the terminal's login shell.
The pane shell survived a detach, but the client had no outer shell to return to, so the terminal
tab closed. That was process topology rather than tmux killing the pane.

Do not remove the setting and assume that means "no tmux". z4h's unset default is isolated tmux,
which creates additional tmux sockets.

## Italics and `default-terminal`

tmux substitutes reverse video for SGR 3 when the pane terminal's terminfo declares no italic
capability. `screen-256color` and `screen` declare none, so every italic run renders as an inverted
band of the foreground color on the terminal background. Agent TUIs italicize reasoning text and
metadata, which turns most of a transcript into that band. Codex, Claude Code, opencode, and pi all
share the cause, because the fallback happens in tmux rather than in any one tool.

`default-terminal` must resolve to a terminfo entry that declares `sitm` and `ritm`; `tmux-256color`
does, `screen-256color` does not. A `terminal-overrides` entry for the pane name does not repair it.
`scripts/test-tmux-lifecycle-contract.sh` reads the option from an isolated server with the real
config and fails when the terminfo loses the capability.

The option is a server option, and tmux re-resolves it on the next output, so `prefix r` (or
`tmux source-file ~/.config/tmux/tmux.conf`) is enough; `tmux kill-server` is not required. Existing
panes keep the `$TERM` they were created with, so restart the server only when every pane must move
to the new value. `show-options -sv default-terminal` reports what the running server uses.

## Pane, process, and socket leaks

`agent-reap` targets Claude Code teammate panes identified by Claude's `--agent-id` command shape
and `~/.claude/teams/session-*` state. It is not a general tmux garbage collector and does not reap
ordinary shells or Codex agent processes.

There is no `agent-reap` daemon or launchd job. Cleanup has three entry points:

- `~/.claude/hooks/agent-reap-stop.sh` runs after each of the lead's turns (`Stop`) and reaps
  the lead's own split-pane teammates that pass every liveness gate. No other lead-side event
  follows a split-pane teammate's report: `TeammateIdle` fires for in-process teammates only, and
  `SubagentStop` carries no team identity. The teammate's own `Stop` hook cannot reap its pane
  because agent-reap protects the caller's ancestry. The hook is detached and exits at once for a
  session with no team directory.
- `~/.claude/hooks/agent-reap-session-end.sh` runs a team-scoped reap after a qualifying Claude
  `SessionEnd` event, then removes that ended session's exact `session-*` state directory.
- `just reap`, `just reap-sockets`, `just reap-strays`, and `just reap-kill` provide manual audit
  and cleanup paths.

The hook logs are created only after a qualifying event owns a matching team directory:

```bash
tail -n 100 ~/.claude/logs/agent-reap-session-end.log
tail -n 100 ~/.claude/logs/agent-reap-stop.log
rg -n -C 4 'SessionEnd|agent-reap' ~/.claude/settings.json
```

No log is not proof that installation failed; it can mean no qualifying team has ended. Conversely,
a configured hook is not proof that it ran. Check the generated settings, hook log, socket report,
and remaining panes together.

The SessionEnd command handler has a 20-second Claude timeout. The hook also carries its own
shorter process-group watchdog because macOS provides neither `timeout` nor `gtimeout`; it never
falls back to an unbounded reap. The `agent-reap` worker separately bounds the individual tmux and
process-inspection subprocesses it starts.

The status monitor classifies a window only when its pane title begins with Claude's ✳ waiting
marker or a braille working spinner. Arbitrary application titles such as `nvim` remain unclassified
instead of being painted as active Claude work. `agent-reap` reads the same marker: a teammate is
idle only when its title starts with ✳. tmux's `window_activity` is not usable for this, because
Claude's TUI redraws while it waits for input, so the timestamp never ages.

`agent-reap strays` covers two state classes that pane teardown cannot: persistent SSH control
masters and allowlisted user processes adopted by PID 1. These remain report-only because broad
process cleanup has unacceptable false-positive risk.

## Other slow state leaks

| Symptom | Retained state | Verification and remedy |
| --- | --- | --- |
| Removed tmux plugin still owns a key or style | Options and bindings stored in the live server | Inspect `tmux list-keys` and `tmux show-options -g`; remove plugin-owned state explicitly, then reload. Trial stateful plugins on an isolated socket. |
| New shells see old environment values | The tmux server and existing panes captured older environment | Inspect `tmux show-environment -g`; run `tmux-refresh-env` (report-only) and `tmux-refresh-env --apply` to re-seed the server env from a pristine login shell without restarting it, then `eval "$(tmux show-environment -g -s)"` in long-lived shells. `update-environment` does not rewrite existing process environments, and running TUIs keep theirs until restarted. |
| New shell starts in a deleted worktree | A pane or foreground process retained a deleted cwd | Inspect `pane_current_path` and process cwd; the zsh startup guard falls back to `$HOME`, while prefix-created windows and panes force `$HOME`. |
| Source changed but installed `agent-reap` did not | A uv tool wheel was reused for an unchanged local version | Run `just sync-side-channels`; the installer requires `uv tool install --force --reinstall`. Compare the installed package with `agent_reap/src/agent_reap` when in doubt. |
| Source template looks correct but an AI tool behaves differently | Generated `~/.claude/settings.json` or MCP target is stale | Inspect the emitted file and rerun the owning sync path. Never infer emitted state from the source template alone. |
| Raw dotfile edit appears ignored | The target is live, but the consumer caches state | Resolve the symlink with `realpath`, then reload/restart the consumer. Do not run an apply merely to reload tmux or zsh. |
| A new link or package appears absent | The last apply or Brewfile run predates the edit | Run `just sync-dfm`, then `just sync-dfm-apply <digest>`. A raw-config reload cannot create links or install packages. |
| `tmux kill-server` succeeds but panes survive | The panes belong to another socket | Run `agent-reap sockets`; address the exact socket or pane id. Never assume `$TMUX` enumerates every server. |

## Operating rules

- Prefer pane ids and socket paths over positional pane indices and the ambient `$TMUX` value.
- Test stateful tmux changes on an isolated socket before touching the daily server.
- Removing a stateful plugin requires live cleanup as well as deleting its config line.
- Keep automatic cleanup narrow and report-first. Leads and interactive sessions contain valuable
  context and need separate explicit authority to kill.
- Verify generated and installed artifacts after sync. A successful source edit is only layer one.
- Recheck live state after a reboot; rebooting clears processes but can also reactivate a different
  generation or startup path.
