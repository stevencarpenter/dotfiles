# Worktrunk work-machine handoff (la-dotfiles portion)

> Dropped 2026-09-02 for pickup on the work M3. Delete this file from the
> personal repo once the la-dotfiles portion is merged and verified — it is a
> handoff artifact, not durable documentation.

## Context

The worktrunk composition model was settled after the 2026-09-01 breakage
(`home/.config/worktrunk/config.toml` committed as a nix-store symlink by
`af49806`/`24b4093`, fixed in `098885e`). Goal: everything work-specific lives
in la-dotfiles; everything overlapping ships from the personal repo and is
active on the work machine; work overrides personal.

Worktrunk makes this possible without a whole-file fork: **every user-config
key can be overridden by a `WORKTRUNK_*` env var, and env vars outrank the
user config file** (verified empirically on 0.76.0: `wt config show --full`
reported the env-provided commit-generation command over the config file's).
Key mapping is mechanical: `commit.generation.command` →
`WORKTRUNK_COMMIT__GENERATION__COMMAND`, `worktree-path` →
`WORKTRUNK_WORKTREE_PATH`.

## What the personal repo already provides (no action needed)

- `~/.config/worktrunk/config.toml` — shared skeleton: `worktree-path`
  (sibling dirs), `[[pre-start]] copy-ignored`, `[list]`, `[commit] stage`,
  `[merge]`, `[commit.generation]` with the personal generator and
  `template-append` style rules. Deployed as a regular out-of-store symlink.
- `~/.local/bin/worktrunk-commit-generator` — ungated, identical on all
  machines; honors `CLAUDE_BIN`, so it needs no work variant unless work
  replaces the generator outright.
- `~/.config/zsh/profile.d/worktrunk-aliases.zsh` — `wsc`/`wsi`/`ws`/`wl`/`wm`.
- The profile.d sourced loop globs `profile.d/*.zsh` in a REAL directory
  (repo fragments are individually linked; external fragments are plain
  files — precedent: `work-shell-functions.zsh`). la-dotfiles' fragment
  drops in without touching this repo.

## la-dotfiles portion (do on the work machine)

1. **Add the fragment** in la-dotfiles' files tree, e.g.
   `files/zsh/profile.d/worktrunk-work.zsh`, delivered by la-dotfiles' module
   (or installer) as a plain file at
   `~/.config/zsh/profile.d/worktrunk-work.zsh`:

   ```zsh
   # Work-machine worktrunk overrides. Env vars outrank
   # ~/.config/worktrunk/config.toml (verified on worktrunk 0.76.0).
   # The value is a TOML string, so it needs inner double quotes.
   export WORKTRUNK_COMMIT__GENERATION__COMMAND='"<org generator command>"'
   ```

   Replace `<org generator command>` with the org's commit generator (or a
   trivial `"true"` to disable generation — there is no "unset" semantics).
   Only divergent scalar keys go here; do NOT mirror the shared skeleton.

2. **Do NOT fork or symlink the base config.** The 2026-09-01 incident was an
   attempt to make the base file overridable via a store symlink; that path is
   closed. If divergence ever outgrows scalar keys (notably `[[pre-start]]`,
   an array-of-tables that env cannot override cleanly), escalate to the
   whole-file override seam in la-dotfiles' module — already contract-tested
   in the personal repo at `scripts/test-external-overlay-contract.sh:76-78`.

## Verification (work machine, after a shell restart or re-login)

```bash
# Generator resolves and generation works end-to-end:
wt config show --full          # DIAGNOSTICS: commit generation section should
                               # show the ORG command, not the personal one
wt list                        # config parses; shared skeleton active

# Pre-start hook approvals are per-machine (approvals.toml is unmanaged):
wt config approvals list       # approve interactively once if prompted
```

Then run the daily flow once: `wsc <branch>` (or `ws <branch>`) and `wm` on a
throwaway branch.

## Caveats

- Env overrides apply only where the env is set: interactive shells and agent
  processes launched from tmux inherit profile.d. A bare non-interactive git
  context (IDE, cron) will NOT see the work command and falls back to the
  personal generator. Acceptable (matches the secrets model); revisit with
  the whole-file seam if it bites.
- `template-append` (a file key, not overridden) still applies on the work
  machine. Its rules are generic style constraints (Conventional Commits, no
  AI attribution) — intended to stay, but note it in la-dotfiles review.
- `approvals.toml`/`.lock` are per-machine, never linked, never committed.
- `docs/external-overlays.md` is LOCKED v1.0. The env-var seam row needs an
  explicit review round in the personal repo before it becomes documented
  contract; until then la-dotfiles' fragment is an informal consumer of the
  existing profile.d seam (line 62), which is already documented.
