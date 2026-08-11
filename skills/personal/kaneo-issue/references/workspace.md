# Kaneo workspace — reference

Self-hosted Kaneo at `https://kaneo.snugmarina.org`, tailnet-only (see
`homelab: docs/runbooks/kaneo.md` for MCP wiring and the epic/DAG pattern).
Workspace `carpenter`, ID `7tMuvznyx3ZOUb2boKJQbakZi44sT0eU`.

Verified 2026-08-10. Re-derive with `list_workspaces`, `list_projects`,
`list_workspace_labels` if anything here doesn't match — IDs are stable but
task counts move constantly.

## Contents

- [Projects](#projects) — IDs, slugs, and what each board is for
- [Columns](#columns) — the four-column ladder
- [Labels](#labels) — the complete fifteen
- [Per-project conventions](#per-project-conventions) — agent contracts, gates
- [Migration facts](#migration-facts) — what came from Linear and what didn't

## Projects

`projectId` is what every MCP call wants. The slug is what renders in display
IDs (`HOME-1`).

| Project | Slug | `projectId` | Scope |
|---|---|---|---|
| Snugmarina | `SNUG` | `f4ww6cb482sfi7olt8yyouxt` | Household-OS iOS app + server |
| Whistlepost — Full Vision | `WPFV` | `je7viaubbnripmb7ves6gah5` | Rail sighting journal, post-launch vision |
| Whistlepost | `WP` | `yukuvlygrt8un3zcyw4zh8a9` | Rail sighting journal, launch sprint |
| Sluice | `SLU` | `rqqqk70o40v9sk1wcklxwh9a` | CDC pipeline (Rust workspace) |
| Gringotts | `GG` | `qnr68a6537658jy4ys85f8x6` | Secret/config control plane |
| gitdiff | `GITD` | `j3ds6o3vs7s6gujeibl91brb` | Code-review view-transform tool |
| Stevectl | `SCTL` | `vfg4hw5e8rg03h4hqi4nlkuq` | Personal Rust CLI |
| Dotfiles | `DOT` | `eyfb1ppqo627qtmiwgo0nuiq` | nix-darwin restructure, secrets, i9 fork |
| homelab | `HOME` | `g6995f1fcqyabq54t18lmjsz` | i9 services (Compose + Caddy, tailnet-only) |
| Hippo | `HIPO` | `i4o4byau9mfpdef7wjz7mwii` | Local knowledge base |

There are no teams — projects are flat and are the only routing dimension.

## Columns

`to-do` → `in-progress` → `in-review` → `done`. `done` is the only column
flagged `isFinal`. Uniform across every project; there is no Backlog, Canceled,
or Duplicate. Use the slug, not the display name ("To Do"), in tool calls.

## Labels

Labels are **per-task rows**, not a shared vocabulary: every attachment is its
own record with its own ID, sharing only the `name` string. `agent-autonomous`
is 281 distinct rows. `list_workspace_labels` therefore returns ~1,000
attachment records, not a list of label types, and `delete_label` detaches one
task's row rather than retiring a name everywhere.

Names in circulation:

**Dispatch** — `ready-for-agent` · `needs-human` · `agent:haiku` ·
`agent:sonnet` · `agent-autonomous` · `agent-parallel` · `orchestrator`

**Structure** — `epic`

**Snugmarina roadmap** — `M1` · `M2` · `M3` · `M4` · `M5`. Kaneo has no
milestone or cycle entity, so labels are the only mechanism.

**Removed 2026-08-10** — `priority:high` · `priority:medium`, 122 rows deleted.
They duplicated the native `priority` field (`no-priority` | `low` | `medium` |
`high` | `urgent`), which is what the board sorts on. Every task carrying one
had a native priority set, so nothing was lost — and in three cases the field
said `urgent` while the label said `priority:high`, because the migration had no
urgent label to map to. That is the drift a parallel taxonomy produces. Use the
field; don't recreate these.

Linear's `area:*`, `db:*`, `cdc-mode:*`, `connector:*`, `sink:*`, `format:*`,
`cloud:*`, `scope:*`, the repo labels, and the work-type labels
(`Bug`/`Feature`/`Improvement`) did **not** migrate, and shouldn't be rebuilt.
Most of that taxonomy existed to partition one Linear project into many on a
free account; paid, separate projects now do that structurally. The test for a
new label is whether someone filters on it.

## Per-project conventions

Each project's `description` field carries an AGENT CONTRACT block that an
orchestrator reads before dispatching. Read it with `get_project` rather than
trusting this summary, which will drift.

The shared shape across every board:

> Ready frontier = `to-do` tasks with no `epic` label, no `needs-human` label,
> and every `blocks`-predecessor done (check with `get_task_relations`).
> Claim by moving to `in-progress` and commenting your agent ID and plan.
> `in-review` = PR open; the PR review is the human gate. **Close on merge:**
> whoever lands the merge moves the task to `done` with the PR link and a
> one-line evidence comment — no separate board approval. If scope was
> narrowed, say which criteria were dropped.

`needs-human` is never auto-dispatched — surface it in the report instead.
`needs-human` tasks are also the one case still requiring explicit human
promotion to `done`: their done-ness isn't PR-shaped, so no merge event exists
to close on. (Contract updated 2026-08-11; before that, every board required
human promotion of `in-review` → `done`.)

Project-specific notes worth knowing:

- **Sluice** — gate command for the acceptance-criteria checklist is
  `scripts/verify.sh` (fmt + clippy + tests + supply chain), or `just preflight`
  when the change touches connectors or anything Linux-specific. Branches use
  the repo's `type/kebab-case`, commits use a `Closes SLU-N` footer. Epics:
  SLU-1 (endurance harness), SLU-72 (release honesty). Cross-project gate:
  SNUG-356 blocks SLU-4. SLU-106 is owner-gated legal work.
- **homelab** — deploys go through `just` recipes and the preflight/proof
  gates; read `docs/runbooks/` before touching a service.
- **Dotfiles** — repo is `~/.dotfiles`; read its CLAUDE.md first. Secrets work
  must follow the dotfiles-secret-authoring skill (op-render, never plaintext).
- **Whistlepost** — epic DAG via `blocks`: WP-49→{52,53}, WP-50→{51,55},
  WP-51→{54,56}, WP-56→{57,58}. Launch gate: WP-36 blocks WP-39.
- **Gringotts** — flat backlog, no epics or DAG. ADR numbers in titles refer to
  the gringotts repo's ADR corpus.
- **Snugmarina** — holds both the migrated backlog and the Kaneo-native M1–M5
  product roadmap.

## Migration facts

724 issues across 10 projects were migrated from Linear on 2026-08-09; the
subscription was then canceled and the sync tooling deleted.

Consequences that show up in daily use:

- Every migrated task's description opens with `Migrated from Linear **<ID>**`
  (or `Mirrored from Linear **<ID>**`) and a `linear.app` URL. **The URLs are
  dead.** The ID line was the migration's join key — leave it in place as
  provenance.
- Task bodies and project descriptions cite old Linear IDs (`SNUG-346`,
  `WP-19`, `GG-99`, `CARP-9`) that don't match Kaneo's per-project numbering.
  Both schemes are in circulation and will be for a long time.
- Completed history was migrated into `done`, so boards show high task counts
  with much of it archived work rather than open backlog.
- **Kaneo's Postgres is the only copy of this history.** The nightly
  `just backup-kaneo` dump on i9 is the sole durability guarantee — it is not
  optional.
