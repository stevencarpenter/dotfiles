# Skill Distribution via `mcp_sync` — Design

**Date:** 2026-05-17
**Issue:** [#57](https://github.com/stevencarpenter/dotfiles/issues/57) — *Extend mcp_sync to deploy Claude skills (vendored + personal, machine-gated)*
**Status:** Approved design — ready for implementation planning.

## Goal

Give `mcp_sync` a sibling capability for **Claude Code skills**, mirroring how it
handles MCP configs: a master manifest declares sources, machine overlays gate
work vs. personal vs. lab, and the sync runs after `chezmoi apply`. After this
work, `~/.claude/skills/` is fully reproducible from chezmoi — vendored skills
(mattpocock's collection) refresh on a schedule at deploy time, and personal
skills authored in the dotfiles repo are version-controlled alongside everything
else.

## Non-goals

- Git submodules.
- Always-latest vendored skills. A `refreshPeriod` (like the `.chezmoiexternal.toml`
  tpm entry) is sufficient.
- Multi-tool skill fanout (Codex, Copilot, etc.). Out of scope for v1; the design
  leaves room but does not implement it.

## Corrections to issue #57's stated "current state"

Verification while designing surfaced three facts that diverge from the issue:

1. **mattpocock/skills has a *nested* layout**, not flat. Skills live at
   `skills/<category>/<skill-name>/SKILL.md` with categories `engineering`,
   `productivity`, `misc`, `personal`, `deprecated`, `in-progress`. The issue's
   sketched `"*": {"source": "mattpocock"}` wildcard would have silently pulled in
   `deprecated/` and `in-progress/` skills. Selection and flattening both need
   real handling.
2. **The repo has 4 personal skills under `.agents/skills/`, not 1.** Besides
   `refactor` there are `chezmoi-verify`, `mcp-sync-verify`, and
   `machine-capability-audit` — all version-controlled but undeployed.
3. **`~/.claude/skills/` already contains symlinks to non-`.agents` locations**
   (`monitoring-hippo`, `using-hippo-brain` → `~/projects/hippo/...`) and real
   plugin-installed skill directories (`building-browser-extensions`,
   `use-railway`). Garbage collection must be strictly whitelisted to what *this
   sync* deployed.

Also confirmed: **Claude Code does not recursively discover personal skills.**
The docs are explicit — personal skills load from `~/.claude/skills/<name>/SKILL.md`,
exactly one level deep. Recursive discovery applies only to *project* `.claude/skills/`
in nested working directories. Vendored sources with nested layouts must therefore
be **flattened** at deploy time.

## Resolved design decisions

| # | Decision | Choice |
|---|----------|--------|
| 1 | Vendored skill selection | **Explicit allow-list.** Every vendored skill is named in the manifest. No wildcard. |
| 2 | Manifest location | **Separate file in a new `dot_config/skills/` directory.** |
| 3 | Cache vs. state location | **XDG-correct split:** clone cache in `~/.cache/mcp-sync/skills/`, GC state in `~/.local/state/mcp-sync/skills-state.json`. |
| 4 | Command surface | **Separate `sync-skills` entry point** alongside `sync-mcp-configs`. |
| 5 | Capability gating | **New `skills` capability** in `.chezmoidata/machines.toml`. |
| 6 | Repo-specific skills | `chezmoi-verify`, `mcp-sync-verify`, `machine-capability-audit` become **project skills** at `<repo>/.claude/skills/`. Only `refactor` becomes a deployed personal skill. |

The allow-list decision (1) eliminates the issue's hardest open problem: with an
explicit map, the manifest key *is* the deployed name, JSON keys are unique by
construction, so cross-source name collisions are impossible and no
conflict-resolution / fail-loudly logic is needed. Aliasing (deploying
`skills/engineering/tdd` as a differently-named directory) also comes free —
the key need not match the source leaf directory.

## Architecture

New code lives in the existing `mcp_sync` uv project (the package keeps its name;
renaming is out of scope).

| Component | Path |
|-----------|------|
| Core skills logic | `mcp_sync/src/mcp_sync/skills.py` |
| CLI | `mcp_sync/src/mcp_sync/skills_cli.py` |
| Entry point | `sync-skills = "mcp_sync.skills_cli:cli"` in `pyproject.toml` |
| Master manifest (source) | `dot_config/skills/skills-master.json` |
| Machine overlays (source) | `dot_config/skills/machine/{personal.json.tmpl,work.json,lab.json.tmpl}` |
| Personal skill sources | `skills/personal/<name>/` at repo root |
| Post-apply hook | `.chezmoiscripts/run_after_sync-skills.sh.tmpl` |
| Deploy target | `~/.claude/skills/<name>/` |
| Clone cache | `~/.cache/mcp-sync/skills/<source>/` |
| GC state | `~/.local/state/mcp-sync/skills-state.json` |

Reused from `sync.py`: `deep_merge` (including its `key+` list-append
convention), the XDG path helpers, and the `log_*` helpers. Shared helpers may be
lifted into a small `_common` module if duplication is meaningful; otherwise
import directly from `sync.py`.

## Manifest schema

`~/.config/skills/skills-master.json`:

```json
{
  "sources": {
    "mattpocock": {
      "type": "git",
      "url": "https://github.com/mattpocock/skills",
      "ref": "main",
      "refreshPeriod": "168h"
    },
    "personal": {
      "type": "local",
      "path": "skills/personal"
    }
  },
  "skills": {
    "caveman":  { "source": "mattpocock", "path": "skills/productivity/caveman" },
    "tdd":      { "source": "mattpocock", "path": "skills/engineering/tdd" },
    "refactor": { "source": "personal" }
  }
}
```

- **`sources`** — named source definitions.
  - `type: "git"` — `url`, `ref` (branch/tag/commit, default `main`),
    `refreshPeriod` (default `168h`).
  - `type: "local"` — `path` relative to the chezmoi repo root.
- **`skills`** — the explicit allow-list. Key = deployed directory name under
  `~/.claude/skills/`.
  - `source` — required, must name an entry in `sources`.
  - `path` — for `git` sources, **required**: the skill's directory within the
    source repo. For `local` sources, optional; defaults to `<source.path>/<key>`.

### Machine overlay

`~/.config/skills/machine/<machine>.json`:

```json
{ "skills": { "caveman": false } }
```

Merged into the master with the existing `deep_merge`. A skill whose value is
`false` is dropped from the resolved set. An overlay may also add a full skill
entry. Merge order: `master + machine-overlay` (overlay wins) — identical to MCP.

## Source handling

- **`git`** — if `~/.cache/mcp-sync/skills/<source>/` is absent, clone it
  (`--filter=blob:none` when supported, else a full clone) and checkout `ref`.
  If present, compare the last-fetch timestamp (recorded in the state file)
  against `refreshPeriod`; if stale, `git fetch` + checkout/reset to `ref`; if
  fresh, skip the network entirely. `refreshPeriod` parses Go-style durations
  (`h`, `m`, `s`, plus `d` for days).
- **`local`** — `path` resolves against the chezmoi repo root, defaulting to
  `~/.local/share/chezmoi`, overridable via a CLI flag for tests.

## Deploy

Target: `~/.claude/skills/<key>/`.

- **Git source** → **copy** the resolved skill directory. The cache is volatile
  (a later `git fetch` can rewrite it), so symlinks would be leaky. Nested
  source layouts are flattened here: `skills/productivity/caveman/` →
  `~/.claude/skills/caveman/`.
- **Local source** → **symlink** `~/.claude/skills/<key>` →
  `<repo-root>/skills/personal/<key>`. Editing the source is live without
  re-running the sync.

## Garbage collection

`~/.local/state/mcp-sync/skills-state.json` records, per run: each deployed
skill's name, deploy mode (`copy` / `symlink`), and source. Per-source git fetch
timestamps also live here.

On each run, after resolving the new set:
- Any skill present in the previous state but absent from the new resolved set is
  removed from `~/.claude/skills/`.
- Removal is guarded: the entry is deleted only if it still matches what the
  state recorded (a symlink the sync created, or a directory it owns). If the
  user has since replaced it, the sync logs and leaves it alone.
- Anything in `~/.claude/skills/` the sync never recorded — plugin skills, hippo
  symlinks, hand-placed directories — is never touched.

## Capability gating

A new `skills` capability is added to every row of `.chezmoidata/machines.toml`
(`true` on `personal-mac`, `work-mac`, `lab-mac` for now). It gates:
- `.chezmoiignore` — skips `.config/skills` when `skills = false`.
- `.chezmoiscripts/run_after_sync-skills.sh.tmpl` — body collapses to a no-op
  when `skills = false`, mirroring the MCP hook's self-gate.

`machines.toml`'s header comment gains a `skills` capability description.

## Post-apply hook

New `.chezmoiscripts/run_after_sync-skills.sh.tmpl`, modeled on
`run_after_sync-mcp.sh.tmpl`:
- Self-gates on the `skills` capability.
- Checks for `uv`; warns (or fails under `MCP_SYNC_STRICT=1`) if absent.
- Detects the deployed machine overlay at `~/.config/skills/machine/*.json` and
  passes it via `--machine-config`.
- Runs `uv run --project ~/.local/share/chezmoi/mcp_sync sync-skills ...`.

chezmoi runs `run_after_` scripts alphabetically, so `sync-mcp` runs before
`sync-skills` — no ordering dependency exists, but the order is deterministic.

## Migration

1. Move `.agents/skills/refactor/` → `skills/personal/refactor/`.
2. Move `.agents/skills/{chezmoi-verify,mcp-sync-verify,machine-capability-audit}/`
   → `<repo>/.claude/skills/` (project skills — active only when running Claude
   Code in this repo; chezmoi auto-ignores the dot-prefixed source directory).
3. Add `skills` to `.chezmoiignore` so chezmoi never deploys the repo-root
   `skills/` directory (the sync tool reads it; chezmoi must not copy it to `~`).
4. Rewrite the existing `.chezmoiignore` skills comment block to describe the new
   `mcp_sync`-driven deployment instead of the old `~/.agents/` symlink scheme.
5. Seed `dot_config/skills/skills-master.json` with the currently desired vendored
   skills (the ~24 mattpocock skills presently in `~/.agents/skills/`, each mapped
   to its `skills/<category>/<name>` path) plus the `refactor` personal skill.
6. **One-time manual cleanup** (documented in `mcp_sync/README.md`, *not*
   automated — it is destructive): remove the stale `~/.claude/skills/*` symlinks
   that point into `~/.agents/`, then remove `~/.agents/` itself once
   `skills/personal/` is its replacement.

## CI

`mcp-sync-ci.yml`'s `mcp_sync/**` path filter already covers the new Python code.
Add `dot_config/skills/**` to the `push` and `pull_request` path filters so
manifest edits also trigger the lint + test job.

## Testing strategy

`pytest`, following the existing `mcp_sync/tests/` patterns (`tmp_path`, `--home`
style injection, `test_*` naming). Coverage:

- Manifest parsing — valid, malformed JSON, missing `sources`/`skills`.
- Overlay merge — add, override, `false`-drop.
- Skill resolution — unknown source reference, missing required `path` on a git
  entry, local `path` defaulting.
- `refreshPeriod` — duration parsing; fresh cache skips fetch, stale cache
  refetches (mock the clock and `subprocess.run`).
- Git source — clone vs. fetch paths, `ref` checkout (mock `subprocess.run`).
- Local source — symlink creation, idempotent re-run.
- Deploy — copy flattening of a nested layout; symlink for local.
- Garbage collection — orphan removal, untracked-entry safety, replaced-entry
  guard.

`ruff check` + `ruff format --check` + `pytest` must be green.

## Acceptance criteria

- [ ] `mcp_sync` exposes a `sync-skills` entry point; ruff + pytest green.
- [ ] `dot_config/skills/skills-master.json` + machine overlays exist and document
      every currently desired skill.
- [ ] On a clean machine, `chezmoi apply` deploys every resolved skill to
      `~/.claude/skills/<name>/` with no manual git operations.
- [ ] mattpocock skills are pulled at deploy time, cached in
      `~/.cache/mcp-sync/skills/`, and only re-fetched after `refreshPeriod`.
- [ ] Pinning to a tag or commit via `ref` works; bumping is a single-field edit.
- [ ] `refactor` deploys via symlink — editing the source is live without
      re-running the sync.
- [ ] Work / personal / lab machines diverge per their overlays.
- [ ] Garbage collection removes manifest-dropped skills on the next sync but
      never touches skills the sync did not deploy.
- [ ] The migration reconciles existing dangling `~/.claude/skills/` symlinks; the
      one-time cleanup step is documented.
- [ ] `mcp-sync-ci.yml` path filter covers `dot_config/skills/**`.
- [ ] A new `skills` capability exists in `.chezmoidata/machines.toml` with a
      header-comment description, and gates `.config/skills` + the hook.

## Deferred (explicitly out of scope for v1)

- Multi-tool skill fanout (Codex/Copilot).
- Wildcard / category-glob skill selection.
- A `dot_config/skills/overrides/` per-target override layer.
