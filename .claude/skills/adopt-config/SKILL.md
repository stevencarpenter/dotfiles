---
name: adopt-config
description: Adopt an unmanaged tool configuration into this dotfiles-manager repository as a checkout link. Use for config adoption, link granularity, or link collision questions; ordinary edits to existing links need no adoption workflow.
---

# Adopt a config into the dotfiles

Promote a tool's config from an unmanaged real file under `~` into a repo-managed
symlink, so it is reproducible and live-editable. Full runbook:
`docs/adopting-a-config.md`.

## Why this is not a plain file copy

The deployed file *is* the repo file (`~/.config/foo` → `~/.dotfiles/home/.config/foo`).
The config the tool already wrote to `~` is therefore a **real file sitting where the
manager wants a symlink**. Adoption moves the content into the repo, declares the link in a
module manifest, and applies. Two facts shape every adoption:

- **It ends in an apply.** A new `[[resources]]` link means `dotfiles-manager` must create
  the symlink: `just sync-dfm`, then `just sync-dfm-apply <digest>`. (Editing an
  *already-linked* file is live, no apply.)
- **Collisions are refused, not overwritten.** The plan lists a real file at a managed target
  as blocked until you pass `--allow-adopt '<id>'` (the `sync-dfm` recipe writes that flag
  for you). Verify the repository copy before approving; the apply replaces the live file.

## Run the planner first

```bash
bash .claude/skills/adopt-config/scripts/plan_adoption.sh ~/.config/<tool>/<config>
```

It prints the repo target path, a **file-vs-directory** recommendation
(by scanning for tool-written state), a collision note, and the exact `[[resources]]`
stanza to add. Choose the module and package source separately.

## Module and package source

| Decision | Options | How to choose |
|---|---|---|
| **Which machines** | `dfm-module-core.toml` (all) · `dfm-module-personal.toml` (identity) · `dfm-module-<cap>.toml` | Where should this config exist? A brand-new axis → add a module to `dfm-bundle.toml` and select it in `dfm/profiles/<host>.toml`. |
| **Package source** | `Brewfile` (formula, cask, font) · `home/.config/mise/` (version-managed CLI) | Mise owns runtimes and npm CLIs; everything else is Homebrew. |

## File vs directory linking

Link the **file** whenever the tool writes state (cache, history, logs, sockets, lockfiles,
`.git`) next to its config, so runtime state stays outside the repo checkout. Link the
**directory** (`directory = true`) only when the whole dir is config you author. Repo precedents:

| Config | Linked as | Why |
|---|---|---|
| `jj/config.toml`, `nushell/config.nu`, copilot instructions | file | tool writes state in the dir |
| `git`, `nvim` | directory | pure config (nvim's `lazy-lock.json` in-repo is wanted) |

When unsure, link the file.

## Procedure (after the planner)

1. Check how the package is already managed. Add a declaration only when adopting
   package management is part of the request and no existing source owns it.
2. `cp` the tuned config into `home/<rel-path>`.
3. Add the planner's `[[resources]]` stanza to the right `dfm-module-*.toml`.
4. Verify the copied contents. Keep the original until the apply has replaced it.
5. Run `just sync-dfm`, read the plan, then `just sync-dfm-apply <digest>` when an apply is
   authorized. A request to prepare a config change for review does not require applying.
6. After the apply, verify that the deployed path resolves into the repository and
   the tool reads the intended configuration.

## When NOT to use this skill

- Editing a config that is **already** a repo symlink: just edit it live
  (the planner short-circuits with "ALREADY ADOPTED").
- Declaring only a package with no config to manage: that's a plain `Brewfile` or mise
  edit, no linking.
- Secrets (`op://`, age, tokens, keys): use the `dotfiles-secret-authoring` skill instead;
  never copy a plaintext secret into `home/`.

## Cross-agent note

This auto-triggering skill is Claude Code only (the skills mechanism targets
`~/.claude/skills/`). Codex/opencode get the same procedure via `AGENTS.md` → `CLAUDE.md` →
`docs/adopting-a-config.md`.

## Reference

- `docs/adopting-a-config.md`: adoption runbook.
- `dfm-module-core.toml`: the link stanzas every machine gets, and the file-vs-dir precedents.
- `dfm-bundle.toml`, `dfm/profiles/`: module list and per-host selection.
- `scripts/plan_adoption.sh`: deterministic planner (target path, link mode, collision, stanza).
