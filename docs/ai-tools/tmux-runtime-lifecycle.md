# Tmux and Agent Runtime Lifecycle

Tmux, z4h, Claude Code, and side-channel tools all retain runtime state outside the tracked
configuration. A correct file in this repo does not prove that a long-lived server, pane, hook, or
installed tool is using it. These failures are slow: they accumulate across shells and sessions,
then look unrelated to the change that introduced them.

Use this guide when tmux opens a shell in an unexpected directory, detaching closes the terminal,
agent panes survive completed work, a removed plugin still changes behavior, or a deployed tool
does not match the checkout.

## The four layers to verify

Always inspect all four layers before calling a runtime-state problem fixed:

1. **Tracked source** — the file under `home/`, `modules/`, or `scripts/`.
2. **Deployed artifact** — the live symlink, generated config, or installed executable.
3. **Long-lived runtime** — tmux server options, key bindings, environment, panes, and hooks.
4. **Processes and sockets** — what survived, who owns it, and which tmux server it belongs to.

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
launched rather than the location the user expects. The result looks like invisible pane identity
or a resurrected directory even though it is ordinary cwd inheritance.

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

No Nix rebuild is needed for the raw file, but an already-running tmux server never reloads it by
magic. `scripts/test-tmux-lifecycle-contract.sh` loads the config into an isolated server in CI and
asserts the effective bindings, not merely the presence of matching text.

## Explicit tmux startup and detach behavior

The current z4h setting is `zstyle ':z4h:' start-tmux no`. A terminal starts as a normal outer zsh;
run `tmux` explicitly when a persistent session is wanted. `prefix d` then detaches back to that
outer shell instead of closing the terminal tab. Explicit tmux still uses the default socket and
loads `~/.config/tmux/tmux.conf`, including the `$HOME` cwd bindings and Claude state monitor.

The rejected `start-tmux system` policy used `exec tmux -u`, replacing the terminal's login shell.
The pane shell survived a detach, but the client had no outer shell to return to, so the terminal
tab closed. That was process topology rather than tmux killing the pane.

Do not remove the setting and assume that means "no tmux". z4h's unset default is isolated tmux,
which creates the socket sprawl this configuration was intended to remove.

## Pane, process, and socket leaks

`agent-reap` targets Claude Code teammate panes identified by Claude's `--agent-id` command shape
and `~/.claude/teams/session-*` state. It is not a general tmux garbage collector and does not reap
ordinary shells or Codex agent processes.

There is no `agent-reap` daemon or launchd job. Cleanup has three entry points:

- `~/.claude/hooks/agent-reap-subagent-stop.sh` receives the completed `agent_id` and
  `parent_session_id` from a `SubagentStop` event, then reaps only that named teammate. It
  skips window-activity idle (the event already proves the turn ended) and shortens inbox-age
  to `completion_grace_seconds`. It still requires a live session directory, a drained inbox, a
  sleeping process, no active or foreground descendants, and the normal pane and ancestry guards.
- `~/.claude/hooks/agent-reap-session-end.sh` runs a team-scoped reap after a qualifying Claude
  `SessionEnd` event, then removes that ended session's exact `session-*` state directory.
- `just reap`, `just reap-sockets`, `just reap-strays`, and `just reap-kill` provide manual audit
  and cleanup paths.

The hook logs are created only after a qualifying event owns a matching team directory:

```bash
tail -n 100 ~/.claude/logs/agent-reap-session-end.log
tail -n 100 ~/.claude/logs/agent-reap-subagent-stop.log
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
instead of being painted as active Claude work.

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
| Raw dotfile edit appears ignored | The target is live, but the consumer caches state | Resolve the symlink with `realpath`, then reload/restart the consumer. Do not rebuild Nix merely to reload tmux or zsh. |
| Nix module or package change appears absent | The current system generation predates the edit | Inspect `/run/current-system` and run `just rebuild` or `just sync` as appropriate. A raw-config reload cannot apply Nix-owned state. |
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
