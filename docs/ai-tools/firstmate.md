# Firstmate with Pi

`firstmate` starts Pi in an application-owned checkout of
[kunchenguid/firstmate](https://github.com/kunchenguid/firstmate). Its supervisor,
watcher, turn-end guard, Calm UI, and supervision branch remain project-local.
Normal Pi sessions retain their existing packages, model, and trust policy.

```bash
just sync                 # links config, installs tools, provisions Firstmate if absent
firstmate                 # run inside tmux to see workers in the same session
# Outside tmux, optionally start a dedicated session:
tmux new-session -s firstmate firstmate
```

Approve Pi's project trust prompt for `~/.local/share/firstmate/repo` on first
launch. This loads the upstream `.pi/extensions/` and `.agents/skills/`.
Do not install Firstmate with `pi install` or copy its internal skills globally.
`firstmate --setup` (also `just firstmate-setup`) installs the checkout without
launching Pi; it expects the configuration links created by `just rebuild`.
New installations clone upstream `main`. Existing installations are reused without fetching
or changing their version, including after a native self-update.

## Managed configuration

- `home/.config/mise/conf.d/firstmate.toml` declares the companion tools at
  `latest`, because upstream raises its version floors to each new release.
  Pi, node, git, gh, jq, and tmux already have owners in this repository.
- `home/.local/share/firstmate/config/backend` selects tmux explicitly rather
  than auto-detecting Herdr; `crew-harness` selects pi for workers.
- `home/.local/bin/firstmate` exports `FM_HOME=~/.local/share/firstmate` and
  `FM_PI_HARNESS=pi`, enters the code checkout, and uses Pi's regular TUI.
  Additional arguments pass through to Pi, for example `firstmate --continue`.

These files and the mise fragment share the existing `caps.mcp` gate with Pi.
Only individual files are linked. The checkout is at
`~/.local/share/firstmate/repo`; mutable `data/`, `state/`, and `projects/` live
beside it, outside dotfiles. Use Firstmate's `bin/fm-tasks-axi.sh` wrapper for its
backlog so it addresses this separate operational home.

Firstmate inherits your Pi model and authentication. Use `/model` for the main
session and `/supervision-model` to choose a separate supervision model.
No credentials, project registrations, worker launches, Relay integration, or
merge-autonomy grants are created by setup. The mise companion toolchain includes
Lavish for rich reports; Firstmate can also use plain-text reports.

To manage dotfiles, ask Firstmate to register
`https://github.com/stevencarpenter/dotfiles` as `dotfiles`, use `direct-PR` with
merge autonomy off, and use the repository's existing checks. Keep its project
clone separate from `~/.dotfiles`, which supplies live configuration. Do not
symlink the live checkout into Firstmate's `projects/` directory.

## Native updates

Send `/updatefirstmate` in the running Firstmate session. Its
[upstream skill](https://github.com/kunchenguid/firstmate/blob/main/.agents/skills/updatefirstmate/SKILL.md)
updates the primary and secondmate homes, asks secondmates to persist pending work, and restarts
eligible secondmate agents after acknowledgement. Their crewmates keep running. A fallback
reread or an unconfirmed restart is reported separately from a successful restart. The primary
rereads its instructions; its launch-time settings are not thereby guaranteed refreshed.

`just update` updates the package-manager-owned dependencies and runs sync. At the end of a
successful `just sync` or `just sync-side-channels`, dotfiles runs `firstmate --request-update`,
which writes a durable request through Firstmate's `bin/fm-inbox.sh note` and queues a wake. The
primary processes the full native update skill at its next inbox drain; this command does not
launch another supervisor.

For a separate noninteractive request, run:

```bash
firstmate --request-update
```

Each invocation prints a request ID. If it exits 3, the note was saved but its wake failed;
retry the printed `firstmate --request-update <request-id>` command to repair the announcement
without duplicating the request. Other nonzero exits propagate as failures. The native inbox's
`receipts` command exposes pending notes and any recorded outcome:

```bash
FM_HOME="$HOME/.local/share/firstmate" "$HOME/.local/share/firstmate/repo/bin/fm-inbox.sh" receipts
```

Dotfiles does not advance the checkout directly, stop workers, or invoke only the mechanical
Git portion of the native updater. The existing Nix, sudo, and 1Password approval behavior is unchanged.
There is no dotfiles revision pin or `just update-firstmate` command. This follows the shared
[update ownership contract](../adopting-a-config.md#update-ownership).

Mise retains old tool installations with `upgrade --no-prune`. Firstmate's bootstrap checks
tool compatibility, but installing a newer CLI does not refresh an existing process or its PATH.
For ongoing checks, ask Firstmate to configure its local `config/watched-tools.json` and arm
`bin/fm-tool-update-check.sh arm`. The native watcher reports available updates and newer
installations shadowed on PATH; it does not install anything. See
[upstream tool monitoring](https://github.com/kunchenguid/firstmate/blob/main/docs/configuration.md#watched-tool-updates-configwatched-toolsjson).
Shared service restarts must follow the service's lifecycle rules; restarting the shared
no-mistakes daemon interrupts other lanes' active runs.

## Migrating the former pinned installation

Run `firstmate --setup` once, or let the next sync run it. A clean detached checkout is attached
to `main` at its existing commit only when `origin/main` contains that commit and the local
`main` has no commits absent from it. The retired pin updater advanced the checkout with a URL
fetch that never moved the cached `origin/main`, so a legacy checkout can legitimately sit ahead
of that ref; `--setup` then fetches `origin/main` once to re-check that commit and refuses if it
still cannot confirm it. A checkout already on `main` is reused without any fetch. Git also
refuses a branch held by another worktree. This changes branch metadata without changing code or
stopping agents.

Dirty detached checkouts, unique detached history, a newer or divergent local `main`, other
named branches, unexpected origins, and an origin unreachable for that one-time check require
inspection instead of an automatic reset.
Local edits on an existing `main` remain untouched; Firstmate's native updater decides whether
it can update them. The next Nix rebuild removes the obsolete revision-file link.

Local validation covers first install, repeated offline setup, a native update followed by sync,
preservation of local edits, and that a migration preserves worktree content and branch history:

```bash
scripts/test-firstmate-config.sh
FM_HOME="$HOME/.local/share/firstmate" FM_PI_HARNESS=pi \
  FM_BOOTSTRAP_DETECT_ONLY=1 FM_BOOTSTRAP_NETWORK=skip \
  "$HOME/.local/share/firstmate/repo/bin/fm-bootstrap.sh"
```
