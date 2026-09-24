# Firstmate with Pi

`firstmate` starts Pi in a pinned checkout of
[kunchenguid/firstmate](https://github.com/kunchenguid/firstmate). Its supervisor,
watcher, turn-end guard, Calm UI, and supervision branch remain project-local.
Normal Pi sessions retain their existing packages, model, and trust policy.

```bash
just sync                 # links config, installs tools, ensures the pinned checkout
firstmate                 # run inside tmux to see workers in the same session
# Outside tmux, optionally start a dedicated session:
tmux new-session -s firstmate firstmate
```

Approve Pi's project trust prompt for `~/.local/share/firstmate/repo` on first
launch. This loads the upstream `.pi/extensions/` and `.agents/skills/`.
Do not install Firstmate with `pi install` or copy its internal skills globally.
`firstmate --setup` (also `just firstmate-setup`) installs the checkout without
launching Pi; it expects the configuration links created by `just rebuild`.

## Managed configuration

- `home/.config/firstmate/revision` pins the upstream commit.
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
merge-autonomy grants are created by setup. Lavish is optional and not installed;
Firstmate can use plain-text reports.

To manage dotfiles, ask Firstmate to register
`https://github.com/stevencarpenter/dotfiles` as `dotfiles`, use `direct-PR` with
merge autonomy off, and use the repository's existing checks. Keep its project
clone separate from `~/.dotfiles`, which supplies live configuration. Do not
symlink the live checkout into Firstmate's `projects/` directory.

## Pin changes

`just update` previews the upstream commits since the pin and, after approval,
runs `scripts/update-firstmate.sh --apply` before sync. That moves the checkout to
upstream `main` and rewrites the tracked revision, so each bump is a `git diff`.
`just update-firstmate` previews only; `just update-firstmate --apply` bumps
without the rest of the update. The bump refuses a dirty checkout, a checkout not
contained in upstream `main`, or a running supervisor (stop Firstmate and its
workers first). The launcher refuses any revision mismatch rather than resetting
the checkout. Do not use `/updatefirstmate`; it moves the checkout without the pin.

Local validation:

```bash
scripts/test-firstmate-config.sh
FM_HOME="$HOME/.local/share/firstmate" FM_PI_HARNESS=pi \
  FM_BOOTSTRAP_DETECT_ONLY=1 FM_BOOTSTRAP_NETWORK=skip \
  "$HOME/.local/share/firstmate/repo/bin/fm-bootstrap.sh"
```
