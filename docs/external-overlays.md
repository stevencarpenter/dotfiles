# External overlay repos — extension contract (LOCKED v1.0)

> Status: **locked 2026-07-18** after a multi-round adversarial review. The
> sanitized consensus history, decision rationale, and migration plan are in
> [`external-overlays-decision-record.md`](external-overlays-decision-record.md).
> Changes require an explicit new review round, not silent edits. Describes the seam this repo exposes on
> the `m5` branch so an external repo (e.g. an employer's dotfiles) can extend
> it. Nothing here names or assumes any specific organization; that is a
> design requirement, not an accident.
>
> v1.0 = original draft + round-2 amendments: dual-mode non-nix path,
> tools-are-not-fragments, repo-access-as-boundary secrets option, caps
> tradeoff ownership, module-name alias, operational handoff.

## Problem

This repo is a personal, public nix-darwin + home-manager flake. Some machines
(identity `work`) additionally need organization-specific configuration that
must live in that organization's own source control, be usable by teammates
who do not run nix, and be swappable when the owner changes employers —
without any change to this repo.

## Architecture: the dependency points inward

**The external repo is a thin wrapper flake that consumes this repo as an
input.** This repo never references an external repo.

```
┌──────────────────────────────┐        ┌─────────────────────────────────┐
│ external repo (org-hosted)   │ input  │ this repo (public)              │
│  flake.nix (thin shim)       │──────▶ │  lib.mkHost, darwinModules,     │
│  files/        (plain files) │        │  homeModules, machines table    │
│  overlays/     (mcp, skills) │        │  declared seams (below)         │
│  justfile      (non-nix path)│        └─────────────────────────────────┘
│  module.nix    (nix adapter) │
└──────────────────────────────┘
```

Why this direction:

- A private input URL in a public flake leaks the organization, breaks
  `nix flake check` for every machine and CI job without org credentials,
  and must be ripped out on every job change.
- Inverted, a job change means the *new* org writes a ~30-line wrapper; this
  repo changes zero lines.
- The work machine runs `darwin-rebuild switch --flake <org-repo>#work-host`;
  personal machines keep using this repo directly.

## Ownership rule: no file has two writers

The personal repo owns **every base file plus a declared extension seam**.
The external repo only ever contributes **fragments dropped into seams** or
**whole files this repo has explicitly marked overridable**. If a proposed
work config needs to edit a file this repo owns, that is a contract violation
— the fix is a new seam here, not a patch there.

## Declared seams

| Seam | Mechanism | Status |
|---|---|---|
| `~/.ssh/config.d/*.conf` | native `Include`, placed **above all `Host` blocks** | exists |
| `~/.config/external-overlays/git/{extra,work}.inc` | native `[include]` / `[includeIf "gitdir:..."]` | exists |
| `~/.config/external-overlays/tmux/*.conf` | native `source-file -q` glob | exists |
| `~/.config/zsh/profile.d/*.zsh` | sourced loop | exists |
| `~/.config/mcp/machine/<identity>.json` | mcp_sync overlay merge (master → machine → overrides) | exists; ownership yields via `mkDefault` |
| `~/.config/skills/machine/<identity>.json` | skills overlay merge | exists; ownership yields via `mkDefault` |
| Claude settings fragment | activation-time jq merge (extends the existing `ai-stack.nix` base+variant pattern) | exists |
| Whole-file overrides (`aerospace.<identity>.toml`, worktrunk config, other no-include tools) | identity-selected symlink declared with `lib.mkDefault` | exists |

### Implementation notes (m5, 2026-07-18)

Mechanism as shipped, per seam (deviations from the original draft called out):

- **ssh `config.d/` fragment requirements (hard, not stylistic):** the glob is
  `*.conf`, and a fragment MUST be written atomically and MUST parse. ssh does
  not skip a bad include — it exits `terminating, 1 bad configuration options`
  and every connection on the machine fails, including the one you would use to
  repair it. Verified by dropping one malformed file into the directory. Render
  to a tmpfile and rename; never write a fragment in place.
- **ssh `config.d/`** — `~/.ssh/config.d/.keep` is a real `home.file` entry
  (`modules/home/dotfiles.nix`): `~/.ssh` itself is not directory-linked (only
  `~/.ssh/config` is materialized, by `op-render` from an `op://` template), so
  the seam dir needs its own home-manager-owned entry to exist pre-fragment.
- **git overlay tree** — fixed include filenames, not a glob:
  `~/.config/git/config` sources
  `~/.config/external-overlays/git/extra.inc` and `work.inc` explicitly. The
  neutral overlay tree is a real Home Manager-owned directory; it is not nested
  below the existing out-of-store `~/.config/git` parent link.
- **tmux overlay tree** — fragments live at
  `~/.config/external-overlays/tmux/*.conf`. This has the same isolated-owner
  shape as git while preserving the existing base tmux directory and runtime
  plugin behavior.
- **Claude settings fragment** — `~/.claude/settings.d/.keep` is a real
  `home.file` entry (parallels ssh: `.claude` is not whole-directory-linked
  either). The activation-time merge hardened its commit to only fire on
  successful `jq` output (a Task 5 review catch) so a fragment parse failure
  can't wipe the managed base with an empty/partial merge result.
- **NEW — hostName collision rule:** an external wrapper's host row name must
  not collide with a basename under this repo's `hosts/*.nix`
  (`personal-mac`, `work-mac`). `lib.mkHost` selects the host-specific import
  by `builtins.pathExists ./hosts/${hostName}.nix` first and only falls back
  to the generic `modules/darwin` import when no such file exists — so a
  wrapper naming its host `work-mac` gets this repo's in-tree shim silently
  substituted instead of its own module, with no eval error to flag the
  mistake. Wrapper authors must pick a hostName distinct from every file in
  `hosts/`.

Design preference, in order: **native layering** (git/ssh/tmux includes) →
**sync-time structured merge** (mcp/skills/settings) → **whole-file identity
swap** (last resort; forked copies stop receiving base improvements).

Self-scoping seams beat deploy-time gating. The model case is git:
`[includeIf "gitdir:~/work/"]` activates org identity, email, signing key, and
URL rewrites per-directory on the same machine — the fragment needs no
knowledge of how it was deployed.

### SSH ordering note (trap)

`ssh_config` is **first-match-wins**. The `Include ~/.ssh/config.d/*.conf` line
must sit at the top of the base config — after the OrbStack include, before
`Host i9` and `Host *` — or org host stanzas can never take effect. Include
placement is base-file design and is owned by this repo.

## Flake API this repo will export (m5)

- `lib.mkHost` — accepts a host row `{ system, user, identity, caps,
  configurationRevision ?, extraDarwinModules ? [], extraHomeModules ? [] }`.
  External wrappers should pass their own `self.rev or self.dirtyRev or null`;
  the base revision is only the default and an extra Darwin module may also
  override it without `mkForce`.
- `darwinModules.default` / `homeModules.default` — the module sets, importable
  without forking.
- `homeModules.rawDotfiles` — the out-of-store symlink machinery from
  `dotfiles.nix`, parameterized by source root, so an external repo gets the
  same edit-live-without-rebuild property for its own files.
- Caps contract: the row-shape assertion relaxes from *exact key equality* to
  *superset of this repo's canonical keys* — external rows may add caps their
  own modules gate on. Tradeoff accepted knowingly: a dropped canonical cap is
  still caught; a **misspelled extra cap is not** — validating external-added
  caps is the external repo's responsibility (its wrapper may assert its own
  cap list).
- Naming: `homeModules.default` is canonical; `homeManagerModules` is exported
  as an alias so either import spelling works.
- All identity-selected symlinks (aerospace toml, mcp/skills overlays) are
  declared `lib.mkDefault` so an external module overrides them without an
  eval conflict.

## What the external repo provides

Required:

1. **`files/`** — plain configs with real names. The primary interface.
2. **A non-nix path, dual-mode.** The seams above describe layering on a
   machine whose base *is* this repo (the owner). Teammates have their own
   dotfiles and none of these include lines, so for them the installer is a
   **content distributor**: copy/install into each tool's standard location
   (`~/.claude/skills`, MCP config merge, `uv tool install`, rendered creds)
   without touching their base configs, reversible via `uninstall.sh`.
   Content-copy is the teammate default; seam-drop is an optional mode for
   consumers who share this repo's base. The nix module is optional sugar on
   top of either.
3. **Fragments only** on any machine based on this repo — everything lands in
   a seam from the table above. (Teammate machines are the teammate's own
   files; the rule there is "standard tool locations, reversible".)

Not every deliverable is a file fragment: **tools + activation hooks** (e.g.
an AWS SSO profile generator) ride `extraHomeModules` on the nix path and
`uv tool install` (public `git+https`) + a generation step on the non-nix
path. The seam table governs *configs*; tools compose through the
module/installer, not a seam.

Optional:

4. **`flake.nix`** — consumes this repo, calls `lib.mkHost` with its host row
   and `extraHomeModules = [ ./module.nix ]`.
5. **`module.nix`** — uses `homeModules.rawDotfiles` to link `files/`, takes
   over the `<identity>.json` overlay symlinks, registers a Claude settings
   fragment, declares its own secrets.
6. **Secrets** — org-chosen mechanism, and now **entirely** the external
   repo's problem: this repo declares zero `age.secrets`, imports no agenix,
   and tracks no ciphertext. Encrypted-at-rest (SOPS, op-connect, org agenix)
   **or repo-access-as-boundary**: non-credential work content as plaintext in
   the private repo, with only credential-class values as `op://` references
   rendered against an org-managed vault. Hard requirements either way: never
   encrypted against the personal age recipient (see `secrets/README.md`),
   never a single person's keys as the team's decryption path, and no
   credential-class value in plaintext even in the private repo.

   Note the operational constraint learned on the personal side: a renderer
   that shells out to `op` can **never** run from a `home.activation` hook.
   The activation PATH is a closed nix-store list with no `op` on it, and
   1Password authorizes CLI access by calling-process ancestry, so only an
   approved interactive terminal can render. Drive it from a task-runner
   command that signs in first (TTY-guarded); leave activation a stale-check
   warning at most.

Explicitly out of scope for the external repo: editing this repo's base
files, adding inputs to this repo's flake, introducing a third identity
(the two-value `personal`/`work` identity model stays; extension happens via
caps + extra modules).

## Per-project agent instructions

Agent-harness guidance splits three ways: global-personal
(`~/.claude/CLAUDE.md`, this repo), machine-global-work (the Claude settings
fragment seam above), and per-project (each org repo's own `CLAUDE.md` /
`.github/copilot-instructions.md` — no dotfiles involvement). Prefer pushing
org guidance into org repos over layering it on the machine; the fragment
seam is for genuinely machine-global behavior only.

## m5 preparation checklist

1. **Done.** Export the flake API (`lib.mkHost` + module outputs); relax the
   caps assertion to superset.
2. **Done.** Generalize `dotfiles.nix` symlinking into `homeModules.rawDotfiles`.
3. **Done (mkDefault only).** Identity-selected symlinks are `mkDefault`ed; gate-site consolidation deferred to step 6/extraction, where those sites are deleted outright.
4. **Done.** Add the missing native seams: ssh `Include config.d/*.conf`
   (top-placed), isolated git includes, and the isolated tmux fragment glob.
5. **Done.** Add the Claude settings fragment hook to `ai-stack.nix`.
6. Extraction (separate, after the external repo exists), in two parts:

   **6a. Done.** Secrets are out: the 26 work ciphertexts, the recipient file,
   `modules/home/secrets.nix`, the agenix input and module imports, and
   `bootstrap.sh`'s age-identity fetch are all deleted. No host declares
   `age.secrets` or an age identity, so an external work host no longer
   inherits a mandatory (and fatally-failing) decrypt step from this base.
   `home-manager.backupFileExtension` is now set, so a first switch on a box
   still carrying another dotfile manager's files backs them up instead of
   aborting.

   **6b. Pending.** Move the remaining work files and overlays out and delete
   the work host row. **Operational handoff is part of this step:** the work
   machine's daily flow becomes `darwin-rebuild switch --flake <org-repo>#<host>`;
   the org repo takes ownership of that machine's bootstrap/rebuild scripts and
   flake-root assumption, and this repo's `rebuild.sh`/`bootstrap.sh`
   host-detect maps drop the work host.

## Review criteria for an external-repo spec

- Dependency direction: consumes this repo; never the reverse.
- Every assumed API call exists in the export list above (diff both ways).
- Every work config names the seam it uses; nothing claims a file this repo
  owns.
- Secrets: org-scoped keys, teammate-decryptable, no personal-recipient reuse.
- The non-nix path is the primary documented interface, not an afterthought.
