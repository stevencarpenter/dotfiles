# Adopting a tool's config into the dotfiles

You install a tool, test-drive it for a while, and decide to keep it. This is the
procedure for promoting its ad-hoc config (and the tool itself) into managed dotfiles so
it reproduces on every machine.

This repo uses **out-of-store symlinks**: the deployed file points to the
repo file (`~/.config/foo` → `~/.dotfiles/home/.config/foo`). Edits need no rebuild.
An existing file at the target path must be moved before Nix can create the symlink.

## When a rebuild is required

- **Raw config content:** editing an *already-linked* file under `home/` needs no rebuild.
- **Anything Nix evaluates:** packages, macOS defaults, Homebrew casks,
  capability gating, **and adding a new file/path**, because Nix must create the symlink.
  Needs `./rebuild.sh`.

**Adoption requires a rebuild** because it adds a new `home.file` entry.
Subsequent edits to the linked file need no rebuild.

## Collision handling

Home Manager intentionally aborts when a real file occupies a managed target. The migration-only
global `chezmoi-bak` policy was removed after cutover because silently moving an unexpected file
hides ownership mistakes. Preserve the source in the repository and clear the exact target
yourself before rebuilding.

Activation also rejects symlinked parent directories of managed files. When changing
from a whole-directory link to individual file links, preserve the source directory,
move the old live directory symlink aside, and create a real directory at the live
path before rebuilding. Removing child files through the old directory link would
remove files from the source checkout. Managed directory links remain valid when
they are leaves of the new generation, with no separately managed files beneath them.

## Procedure

1. **Declare the package (reproducibility).** The binary must be nix-owned or a fresh
   machine won't have it.
   - In nixpkgs, CLI/font → `modules/home/packages.nix` (`home.packages`).
   - GUI cask / not in nixpkgs / macOS-native → `modules/darwin/homebrew.nix`.
   - Gate it (`caps.*` / `identity`) if it's machine-specific.

2. **Move the tuned config into the repo.** Copy `~/.config/foo/config` →
   `~/.dotfiles/home/.config/foo/config`, preserving exactly what you tuned. The `home/`
   tree mirrors `~`, so the relative path is identical.

3. **Choose file-level vs directory-level linking.**
   See [Decision: file vs directory](#decision-file-vs-directory-linking) below.

4. **Register the link in `modules/home/dotfiles.nix`.** Add the relative path to the right
   `mkLinks [ … ]` list:
   - all machines → the base list (`# ---- all machines ----`)
   - personal/work-only → the `lib.optionalAttrs (identity == "personal"|"work")` block
   - capability-gated → the matching `lib.optionalAttrs caps.<x>` block
   - needs a new capability → **[add a capability](#adding-a-capability)**.

5. **Clear the collision.** After verifying the repository copy, remove the exact original target:
   `rm ~/.config/foo/config`. Skipping this correctly makes activation fail.

6. **Rebuild.** `./rebuild.sh` (or `just rebuild`). Nix creates the out-of-store symlink.

7. **Verify.** `realpath ~/.config/foo/config` lands in `~/.dotfiles/…` and the tool still
   reads it.

A helper plans the file copy, link, and collision handling:

```bash
bash .claude/skills/adopt-config/scripts/plan_adoption.sh ~/.config/foo/config
```

It prints the repo target path, a file-vs-directory recommendation (by scanning for tool
state), a collision check, and the exact `dotfiles.nix` line to add. It does **not** decide
gating or package source: those are judgment calls it surfaces for you.

## Decision: file vs directory linking

The question: **does the tool write runtime state into the same directory as its config?**

- **File-level** (link `.config/foo/config`): the safe default. Use whenever the tool also
  writes caches, history, logs, sockets, lockfiles, or `.git` state alongside its config.
  You manage only the config; runtime state stays out of the repo checkout.
- **Directory-level** (link `.config/foo`): only when the *entire* directory is config you
  author and the tool does not write state there. Sibling config files
  are linked automatically. If the tool writes state into a directory-linked path, it flows
  through the symlink into the **repo working tree** and dirties git.

This repo's own precedents (all in `dotfiles.nix`):

| Config | Linked as | Why |
|---|---|---|
| `jj/config.toml` | file | jj writes repo metadata under `~/.config/jj/repos` |
| `nushell/config.nu` | file | nushell writes `history`/`env.nu` in the dir |
| `github-copilot/intellij/…instructions.md` | file | copilot writes runtime state in the dir |
| `git` | directory | pure config dir (+ `.gitignore_global`); no state written |
| `nvim` | directory | LazyVim rewrites `lazy-lock.json` in place: expected & wanted in-repo |

When unsure, link the file. You can always widen to a directory later.

## Cross-agent note

The auto-triggering skill (`.claude/skills/adopt-config/`) is **Claude Code only**: the
skills mechanism here targets `~/.claude/skills/`, which Codex and opencode do not consume.
Codex and opencode read `AGENTS.md` (a symlink to `CLAUDE.md`), which points at *this doc*.
So all three agents share the same procedure; only Claude Code gets first-class triggering.

## Related

- `CLAUDE.md` § *Layout & module conventions*: the out-of-store-symlink model.
- `modules/home/dotfiles.nix`: the link lists and gating blocks you edit in step 4.

<a id="adding-a-capability"></a>
### Adding a capability

If the config needs an on/off axis no existing `caps.*` covers: add the key to **every** row
in `lib/machines.nix` (`flake.nix` asserts the row shape), then gate the owning module on
`caps.<x>`. See `CLAUDE.md` § *Machine-Type Gating*.
