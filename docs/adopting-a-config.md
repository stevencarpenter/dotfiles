# Adopting a tool's config into the dotfiles

You install a tool, test-drive it for a while, and decide to keep it. This is the
procedure for promoting its ad-hoc config (and the tool itself) into managed dotfiles so
it reproduces on every machine.

It exists because this repo uses **out-of-store symlinks**: the deployed file *is* the
repo file (`~/.config/foo` → `~/.dotfiles/home/.config/foo`). That makes editing live with
no rebuild — but it also means a config the tool already wrote to `~` is a *real file
sitting where nix wants to put a symlink*. Adoption is the ritual that resolves that
cleanly.

## Two lanes (know which one you're in)

- **Lane 1 — raw config content:** editing an *already-linked* file under `home/`. Live
  immediately, no rebuild. (This is most day-to-day config tweaking.)
- **Lane 2 — anything nix evaluates:** packages, macOS defaults, Homebrew casks,
  capability gating — **and adding a new file/path**, because nix must create the symlink.
  Needs `./rebuild.sh`.

**Adoption is a Lane 2 operation** (you add a new `home.file` entry), so it ends in a
rebuild. After that, editing the adopted file is Lane 1 forever.

## The collision safety net

`flake.nix` sets `home-manager.backupFileExtension = "chezmoi-bak"`. When a real file is in
the way of a symlink home-manager wants to create, the switch **moves it aside to
`<file>.chezmoi-bak`** instead of aborting. So adoption never hard-blocks — but clean up
the `.chezmoi-bak` afterward, and prefer removing the original yourself so none is created.

## Procedure

1. **Declare the package (reproducibility).** The binary must be nix-owned or a fresh
   machine won't have it.
   - In nixpkgs, CLI/font → `modules/home/packages.nix` (`home.packages`).
   - GUI cask / not in nixpkgs / macOS-native → `modules/darwin/homebrew.nix`.
   - Gate it (`caps.*` / `identity`) if it's machine-specific.

2. **Move the tuned config into the repo.** Copy `~/.config/foo/config` →
   `~/.dotfiles/home/.config/foo/config`, preserving exactly what you tuned. The `home/`
   tree mirrors `~`, so the relative path is identical.

3. **Choose file-level vs directory-level linking — the load-bearing decision.**
   See [Decision: file vs directory](#decision-file-vs-directory-linking) below.

4. **Register the link in `modules/home/dotfiles.nix`.** Add the relative path to the right
   `mkLinks [ … ]` list:
   - all machines → the base list (`# ---- all machines ----`)
   - personal/work-only → the `lib.optionalAttrs (identity == "personal"|"work")` block
   - capability-gated → the matching `lib.optionalAttrs caps.<x>` block
   - needs a brand-new axis of variance → that's the heavier **[adding a
     capability](#adding-a-capability)** flow.

5. **Clear the collision.** `rm ~/.config/foo/config` (you copied it into the repo in step
   2). Skipping this is safe — the `chezmoi-bak` net catches it — but you'll then want to
   delete the backup.

6. **Rebuild.** `./rebuild.sh` (or `just rebuild`). Nix creates the out-of-store symlink.

7. **Verify.** `realpath ~/.config/foo/config` lands in `~/.dotfiles/…`; the tool still
   reads it; no stray `*.chezmoi-bak`.

A helper does the mechanical parts of steps 2–5 deterministically:

```bash
bash .claude/skills/adopt-config/scripts/plan_adoption.sh ~/.config/foo/config
```

It prints the repo target path, a file-vs-directory recommendation (by scanning for tool
state), a collision check, and the exact `dotfiles.nix` line to add. It does **not** decide
gating or package source — those are judgment calls it surfaces for you.

## Decision: file vs directory linking

The question: **does the tool write runtime state into the same directory as its config?**

- **File-level** (link `.config/foo/config`) — the safe default. Use whenever the tool also
  writes caches, history, logs, sockets, lockfiles, or `.git` state alongside its config.
  You manage only the config; the tool's runtime junk stays out of the repo checkout.
- **Directory-level** (link `.config/foo`) — only when the *entire* directory is config you
  author and the tool does not scribble state there. Convenient (sibling config files
  auto-appear), but if the tool writes state into a dir-linked path, that state flows
  through the symlink into the **repo working tree** and dirties git.

This repo's own precedents (all in `dotfiles.nix`):

| Config | Linked as | Why |
|---|---|---|
| `jj/config.toml` | file | jj writes repo metadata under `~/.config/jj/repos` |
| `nushell/config.nu` | file | nushell writes `history`/`env.nu` in the dir |
| `github-copilot/intellij/…instructions.md` | file | copilot writes runtime state in the dir |
| `git` | directory | pure config dir (+ `.gitignore_global`); no state written |
| `nvim` | directory | LazyVim rewrites `lazy-lock.json` in place — expected & wanted in-repo |

When unsure, link the file. You can always widen to a directory later.

## Cross-agent note

The auto-triggering skill (`.claude/skills/adopt-config/`) is **Claude Code only** — the
skills mechanism here targets `~/.claude/skills/`, which Codex and opencode do not consume.
Codex and opencode read `AGENTS.md` (a symlink to `CLAUDE.md`), which points at *this doc*.
So all three agents share the same procedure; only Claude Code gets first-class triggering.

## Related

- `CLAUDE.md` § *Layout & module conventions* — the out-of-store-symlink model.
- `docs/nix-migration.md` — chezmoi → nix mechanism map (why there's no `apply` step).
- `modules/home/dotfiles.nix` — the link lists and gating blocks you edit in step 4.

<a id="adding-a-capability"></a>
### Adding a capability

If the config needs an on/off axis no existing `caps.*` covers: add the key to **every** row
in `lib/machines.nix` (`flake.nix` asserts the row shape), then gate the owning module on
`caps.<x>`. See `CLAUDE.md` § *Machine-Type Gating*.
