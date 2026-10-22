# External bundles

A private repository can compose this repository with dotfiles-manager (`dfm`) for a host that
is not personal, for example a work machine. This document is the contract between the two.
The private repository owns everything specific to its identity. This repository names no
private source.

## Layout

The private repository is the `--root` checkout. It holds its bundle, its identity module, the
bound profile and `dotfiles-manager.lock`. This repository is a nested checkout inside it,
pinned by commit:

```toml
# dotfiles-manager.lock in the private repository
[[sources]]
id = "work"
kind = "git"
origin = "ssh://git@github.com/<org>/<repo>"
ref = "refs/heads/main"

[[sources]]
id = "dotfiles"
kind = "git"
origin = "https://github.com/stevencarpenter/dotfiles"
ref = "refs/heads/main"
commit = "<40 hex>"
path = "base"
```

Grant each origin once with `dfm sync --trust-origin <origin>`; `dfm sync` exits 3 before any
fetch while a source's origin has no grant. `dfm sync` checks out the pinned commit and never
moves it. `dfm update` (DFM-31, not built yet)
will advance the pin. Until then, edit `commit` by hand.

## Bundle

```toml
schema = 1
id = "work"
extends = "base/dfm-bundle.toml"

[sources]
roots = ["base", "dfm", "files"]
exclude = [
  "base/.git",
  "base/home/.config/tmux/plugins",
  "base/home/.pi/agent/extensions/node_modules",
  "**/__pycache__",
  "**/.venv",
  "**/node_modules",
  "**/*.egg-info",
  "base/agent_reap/build",
]

[modules]
work = "dfm-module-work.toml"
```

1. Extend `dfm-bundle.toml`, not `dfm-personal.toml`. Only the bundle that a profile names may
   declare `[sources]`, so this repository keeps its source roots in `dfm-personal.toml`.
2. Declare the nested checkout itself as a root. The base manifests sit at its top level, and
   the loader reads a manifest only inside a root or beside the bundle the profile names.
   Exclude its `.git` and the runtime trees that `dfm-personal.toml` excludes. Also exclude what
   tools build inside the checkout, for example `base/agent_reap/build` and `**/*.egg-info`.
3. Name the identity module `work`. `scripts/host-capability.sh --identity` recognizes `personal`,
   `work` and `lab`. A module ID must not repeat a base module ID.
4. Put the identity module manifest at the private repository root. A module's sources stay
   inside the directory of its manifest, so a root-level manifest can link base files such as
   `base/home/.config/aerospace/aerospace.work.toml`.
5. Select base modules by ID in the profile, with `modules = [...]` on one line:
   `scripts/host-capability.sh` refuses a multi-line list. Leave out `personal`. Leave out `atuin` for
   local-only history: that module links the self-hosted sync variant. Link
   `base/home/.config/atuin/config.local.toml` from the identity module instead.

## What the identity module supplies

Shared capabilities read these per-identity files. The identity module links them; no base
module does. Fragment names use a `20-` prefix and must not repeat a base file name.

| Seam | Target | Reader |
| --- | --- | --- |
| Tiling | `.config/aerospace/aerospace.toml`, `.config/sketchybar/machine.env` | AeroSpace, SketchyBar |
| MCP overlay | `.config/mcp/machine/<identity>.json` | `scripts/hooks-sync.sh` (mcpSync) |
| Skills overlay | `.config/skills/machine/<identity>.json` | `scripts/hooks-sync.sh` (skillsSync) |
| Claude settings | `.claude/settings.d/20-*.json`; `sandbox.filesystem.allowWrite` appends | `core.claude-settings` merge |
| Codex and pi instructions | `.codex/AGENTS.d/20-*.md`, `.pi/agent/AGENTS.d/20-*.md` | `core.codex-agents`, `core.pi-agents` |
| Shell | `.config/zsh/profile.d/*.zsh` | `.zshrc` |
| SSH | `.ssh/config.d/20-*.conf` | `home/.ssh/config` |
| Git | `.config/external-overlays/git/extra.inc`, `work.inc` | `home/.config/git/config` |
| agent-journal | `.config/agent-journal/config.toml`, `workstreams.toml` | `agent-journal` |

Write paths under the user's home as absolute paths in a settings fragment. The merge copies
values as written; only hook commands keep a `${HOME}` reference live.

## Packages and secrets

- `scripts/brew-sync.sh` applies the shared `Brewfile`, then `Brewfile.<identity>` when this
  repository has one. Declare packages for another identity as `homebrew/v1` or `mise/v1`
  resources in the identity module. `dfm packages` installs them; `dfm apply` does not.
- Declare secrets as `op-template/v1` resources in the identity module, with the identity's
  1Password account. This repository holds personal secrets only.

## Scripts on a bound host

`scripts/host-capability.sh` reads the profile that `dfm binding` names, so the sync scripts in
the nested checkout gate on the private profile. A capability query must name a module declared
in `dfm-bundle.toml`.

`scripts/sync-side-channels.sh` runs `op-render` and installs the private fantasy-sports repo
only for the `personal` identity; the fantasy-sports skill source lives in the personal skills
overlay, not in `skills-master.json`.
