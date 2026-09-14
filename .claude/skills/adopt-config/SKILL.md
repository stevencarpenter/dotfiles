---
name: adopt-config
description: Adopt an unmanaged tool configuration into this nix-darwin repository using out-of-store links. Use for config adoption, link granularity, or Home Manager collision questions; ordinary edits to existing links need no adoption workflow.
---

# Adopt a config into the dotfiles

Promote a tool's config from an unmanaged real file under `~` into a repo-managed
out-of-store symlink, so it is reproducible and live-editable. Full runbook:
`docs/adopting-a-config.md`.

## Why this is not a plain file copy

The deployed file *is* the repo file (`~/.config/foo` → `~/.dotfiles/home/.config/foo`).
The config the tool already wrote to `~` is therefore a **real file sitting where nix wants
a symlink**. Adoption resolves that collision, registers the link, and rebuilds. Two facts
shape every adoption:

- **It's a Lane 2 change.** Adding a new `home.file` entry means nix must create the
  symlink, so adoption always ends in `./rebuild.sh`. (Editing an *already-linked* file is
  Lane 1: live, no rebuild.)
- **Collisions are caught, not fatal.** `home-manager.backupFileExtension = "chezmoi-bak"`
  (`flake.nix`) can move an in-the-way real file to `<file>.chezmoi-bak` on switch.
  Check for an existing backup collision; do not overwrite a backup or delete the
  original before verifying its repository copy.

## Run the planner first

```bash
bash .claude/skills/adopt-config/scripts/plan_adoption.sh ~/.config/<tool>/<config>
```

It prints the repo target path, a **file-vs-directory** recommendation
(by scanning for tool-written state), a collision note, and the exact `dotfiles.nix` line
to add. Choose machine scope and package source separately.

## Machine scope and package source

| Decision | Options | How to choose |
|---|---|---|
| **Which machines** | base list (all) · `identity == personal\|work` · `caps.<x>` | Where should this config exist? Gate accordingly in `dotfiles.nix`. A brand-new axis → add a capability (`lib/machines.nix` every row). |
| **Package source** | `modules/home/packages.nix` (nixpkgs) · `modules/darwin/homebrew.nix` (cask / not in nixpkgs) | Is the binary in nixpkgs? CLI/font → home.packages. GUI/macOS-native → homebrew. |

## File vs directory linking

Link the **file** whenever the tool writes state (cache, history, logs, sockets, lockfiles,
`.git`) next to its config, so runtime state stays outside the repo checkout. Link the
**directory** only when the whole dir is config you author. Repo precedents:

| Config | Linked as | Why |
|---|---|---|
| `jj/config.toml`, `nushell/config.nu`, copilot instructions | file | tool writes state in the dir |
| `git`, `nvim` | directory | pure config (nvim's `lazy-lock.json` in-repo is wanted) |

When unsure, link the file.

## Procedure (after the planner)

1. Check how the package is already managed. Add a declaration only when adopting
   package management is part of the request and no existing source owns it.
2. `cp` the tuned config into `home/<rel-path>`.
3. Add the planner's link line to the right `mkLinks [ … ]` list in `modules/home/dotfiles.nix`.
4. Verify the copied contents. Preserve the original in a non-colliding backup, or
   use the configured Home Manager backup behavior. Do not discard the sole copy.
5. Run `./rebuild.sh` when activation is authorized. A request to prepare a config
   change for review does not require switching the system.
6. After activation, verify that the deployed path resolves into the repository and
   the tool reads the intended configuration. Retain backups until verified.

## When NOT to use this skill

- Editing a config that is **already** a repo symlink: that's Lane 1, just edit it live
  (the planner short-circuits with "ALREADY ADOPTED").
- Declaring only a package with no config to manage: that's a plain `packages.nix` /
  `homebrew.nix` edit, no linking.
- Secrets (`op://`, age, tokens, keys): use the `dotfiles-secret-authoring` skill instead;
  never copy a plaintext secret into `home/`.

## Cross-agent note

This auto-triggering skill is Claude Code only (the skills mechanism targets
`~/.claude/skills/`). Codex/opencode get the same procedure via `AGENTS.md` → `CLAUDE.md` →
`docs/adopting-a-config.md`.

## Reference

- `docs/adopting-a-config.md`: adoption runbook.
- `modules/home/dotfiles.nix`: link lists, gating blocks, and the file-vs-dir precedents.
- `flake.nix`: `backupFileExtension` for preserving existing files.
- `scripts/plan_adoption.sh`: deterministic planner (target path, link mode, collision, nix line).
