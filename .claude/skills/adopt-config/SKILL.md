---
name: adopt-config
description: Promote a tool's ad-hoc config (and the tool itself) into these nix-darwin dotfiles so it reproduces on every machine. USE THIS SKILL whenever the user says they want to "keep"/"adopt"/"manage"/"save"/"commit"/"add to dotfiles" a config for a tool they installed and test-drove; whenever moving a real file from ~/.config/<tool> (or ~/.<tool>rc) under `home/` and linking it; whenever a `darwin-rebuild switch` reports an "existing file in the way" / creates a `*.chezmoi-bak`; whenever deciding file-level vs directory-level out-of-store symlinking for a new config; or whenever the user asks "how do I add this tool's config to my dotfiles", "should I link the file or the dir", "why did nix back up my config", "does this need a rebuild". Bias toward triggering the moment a test-driven tool graduates to permanent — adoption is a Lane 2 (rebuild) op with a collision step that is easy to get wrong by editing the wrong copy.
---

# Adopt a config into the dotfiles

Promote a tool's config from an unmanaged real file under `~` into a repo-managed
out-of-store symlink, so it is reproducible and live-editable. Full runbook:
`docs/adopting-a-config.md`. This skill is the operational entry point.

## Why this is not a plain file copy

The deployed file *is* the repo file (`~/.config/foo` → `~/.dotfiles/home/.config/foo`).
The config the tool already wrote to `~` is therefore a **real file sitting where nix wants
a symlink**. Adoption resolves that collision, registers the link, and rebuilds. Two facts
shape every adoption:

- **It's a Lane 2 change.** Adding a new `home.file` entry means nix must create the
  symlink, so adoption always ends in `./rebuild.sh`. (Editing an *already-linked* file is
  Lane 1 — live, no rebuild.)
- **Collisions are caught, not fatal.** `home-manager.backupFileExtension = "chezmoi-bak"`
  (`flake.nix`) moves an in-the-way real file to `<file>.chezmoi-bak` instead of aborting
  the switch. Clean it up after; better, `rm` the original yourself first.

## Run the planner first (deterministic)

```bash
bash .claude/skills/adopt-config/scripts/plan_adoption.sh ~/.config/<tool>/<config>
```

It prints, deterministically: the repo target path, a **file-vs-directory** recommendation
(by scanning for tool-written state), a collision note, and the exact `dotfiles.nix` line
to add. It **does not** guess the two judgment calls below — those are yours.

## The two decisions the planner won't make for you

| Decision | Options | How to choose |
|---|---|---|
| **Which machines** | base list (all) · `identity == personal\|work` · `caps.<x>` | Where should this config exist? Gate accordingly in `dotfiles.nix`. A brand-new axis → add a capability (`lib/machines.nix` every row). |
| **Package source** | `modules/home/packages.nix` (nixpkgs) · `modules/darwin/homebrew.nix` (cask / not in nixpkgs) | Is the binary in nixpkgs? CLI/font → home.packages. GUI/macOS-native → homebrew. |

## File vs directory linking (the load-bearing call the planner recommends)

Link the **file** whenever the tool writes state (cache, history, logs, sockets, lockfiles,
`.git`) next to its config — so runtime junk never lands in the repo checkout. Link the
**directory** only when the whole dir is config you author. Repo precedents:

| Config | Linked as | Why |
|---|---|---|
| `jj/config.toml`, `nushell/config.nu`, copilot instructions | file | tool writes state in the dir |
| `git`, `nvim` | directory | pure config (nvim's `lazy-lock.json` in-repo is wanted) |

When unsure, link the file — you can widen later.

## Procedure (after the planner)

1. Declare the package (nixpkgs or homebrew), gated if machine-specific.
2. `cp` the tuned config into `home/<rel-path>`.
3. Add the planner's link line to the right `mkLinks [ … ]` list in `modules/home/dotfiles.nix`.
4. `rm` the original real file from `~` (or accept the `.chezmoi-bak`).
5. `./rebuild.sh`.
6. Verify: `realpath ~/.config/<tool>/<config>` lands in `~/.dotfiles/…`; no stray `.chezmoi-bak`.

## When NOT to use this skill

- Editing a config that is **already** a repo symlink — that's Lane 1, just edit it live
  (the planner short-circuits with "ALREADY ADOPTED").
- Declaring only a package with no config to manage — that's a plain `packages.nix` /
  `homebrew.nix` edit, no linking.
- Secrets (`op://`, age, tokens, keys) — use the `dotfiles-secret-authoring` skill instead;
  never copy a plaintext secret into `home/`.

## Cross-agent note

This auto-triggering skill is Claude Code only (the skills mechanism targets
`~/.claude/skills/`). Codex/opencode get the same procedure via `AGENTS.md` → `CLAUDE.md` →
`docs/adopting-a-config.md`.

## Reference

- `docs/adopting-a-config.md` — the full runbook this skill operationalizes.
- `modules/home/dotfiles.nix` — link lists, gating blocks, and the file-vs-dir precedents.
- `flake.nix` — `backupFileExtension` (the collision safety net).
- `scripts/plan_adoption.sh` — deterministic planner (target path, link mode, collision, nix line).
