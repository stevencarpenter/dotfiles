# Snugmarina Linear workspace — reference

Workspace slug `snugmarina` (`https://linear.app/snugmarina/`). Verified
2026-07-25; re-derive with `list_teams`, `list_projects`, `list_issue_labels`,
`list_issue_statuses` if something here doesn't match.

## Teams

| Team | Key | Scope |
|---|---|---|
| Sluice | `SLU` | The sluice CDC framework (Rust workspace) |
| Snugmarina | `SNUG` | Umbrella for the household-app estate: Hippo, Homelab, Snugmarina, Dotfiles |
| Gringotts | `GG` | Config/secret control plane |
| Whistlepost | `WP` | Rail sighting journal |
| Stevectl | `SCTL` | Personal platform-engineering CLI |
| Carpenter | `CARP` | Home board; also hosts the `gitdiff` experiment |

Team `Snugmarina` carries four distinct projects — routing by team alone is not
enough there, so the project field does the real work.

## Statuses (uniform across teams)

`Backlog` → `Todo` → `In Progress` → `In Review` → `Done`, plus `Canceled` and
`Duplicate`.

`Backlog` means "captured but not committed to"; `Todo` means "specified and
ready to pick up". Filing straight into `Todo` is right when the issue is fully
triaged; use `Backlog` when the acceptance criteria are still soft.

## Labels

All labels below are **workspace-level**, which is why they survived the
2026-07-12 team split. Keep it that way: a team-scoped label is silently dropped
when an issue moves teams.

### Repository (label group `Repository`)

`sluice` · `hippo` · `gringotts`

Predates the one-team-per-repo split. Still applied on the repos listed in the
SKILL routing table; not created for new repos, which get their own team.

> The `sluice` label's description still reads "Issues for the
> stevencarpenter/sluice GitHub repository" — a stale org (now `sjcarpenter`).
> Cosmetic; fix in the Linear UI, since the MCP can't update labels.

### Product / repo (ungrouped)

`dotfiles` · `homelab` · `snugmarina` · `snugmarina-base` · `claude-memory`

`snugmarina-base` was created 2026-07-26 for the server repo extracted from
`homelab`. Pair it with `homelab` while the deploy split is transitional — see
the SKILL routing table for which half of a change goes where.

### `area:*` — subsystem

`area:core` (sluice-core pipeline/model) · `area:source` (source connector
interface) · `area:sink` (external sink target) · `area:testing` (coverage / CI
fidelity) · `area:ci` (GitHub Actions / release) · `area:docs` ·
`area:security` · `area:async` (runtime / shutdown) · `area:k8s` (deployment
manifests) · `area:target-format` (object-store output formats)

### `db:*` — database engine

`db:mysql` · `db:postgres` · `db:sqlite` · `db:sqlserver`

`db:sqlserver` is retained for history only — the SQL Server connector was
removed from sluice. Do not apply it to new work.

### `cdc-mode:*` — output semantics

`cdc-mode:raw` (landing envelope) · `cdc-mode:scd` (SCD1/SCD2 mirrors)

### `connector:*` / `sink:*` / `format:*`

- `connector:database` · `connector:object-store` · `connector:warehouse`
- `sink:snowflake` · `sink:redshift` · `sink:bigquery`
- `format:parquet` · `format:jsonl` · `format:csv` · `format:orc`

### `cloud:*` / `scope:*`

`cloud:aws` · `cloud:gcp` · `cloud:azure` — managed-service compatibility.
`scope:cloud` · `scope:local` — runtime scope.

### `priority:*`

`priority:high` · `priority:medium` · `priority:low`

Mirror into the native `priority` field: high=`2`, medium=`3`, low=`4`.

### Agent dispatch

| Label | Meaning |
|---|---|
| `agent:haiku` | Mechanical, single-file, no design decisions |
| `agent:sonnet` | Design-bearing, multi-file, or borrow-checker-sensitive |
| `ready-for-agent` | Fully specified; an agent can finish it unattended |
| `needs-human` | Done-when needs a device, console, or credential access |
| `blocked` | Blocked on an external decision — pair with a `blockedBy` relation |
| `orchestrator` | Meta issue; never dispatch to a worker |
| `agent-autonomous` | Cursor Composer multitask-safe |
| `agent-parallel` | Safe to run concurrently (no shared file/migration conflict) |

There is no `agent:opus` and there should not be — subagents cap at Sonnet.

### Work type

`Bug` · `Feature` · `Improvement` · `epic`

`enhancement` and `documentation` are GitHub-imported legacy duplicates of
`Feature` and `area:docs`. They appear on imported issues; don't apply them to
new ones.

## Projects

| Project | Team | Notes |
|---|---|---|
| Sluice | Sluice | |
| Hippo | Snugmarina | |
| Homelab | Snugmarina | |
| Snugmarina | Snugmarina | iOS app + backend |
| Dotfiles | Snugmarina | |
| Gringotts | Gringotts | |
| Whistlepost | Whistlepost | |
| Stevectl | Stevectl + Carpenter | |
| gitdiff | Carpenter | One-shot experiment |
| ~~Side Projects~~ | Snugmarina | **Legacy** — superseded by per-repo projects |

## Sluice specifics

- Every issue: team `Sluice`, project `Sluice`, label `sluice`.
- Gate command for the acceptance-criteria checklist: `scripts/verify.sh`
  (fmt + clippy + tests + supply chain), or `just preflight` when the change
  touches the connectors or anything Linux-specific.
- Branch convention is the repo's own `type/kebab-case-description`, not
  Linear's suggested `steven/slu-N-...`.
- Commits reference the issue with a `Closes SLU-N` footer, never `Closes #N`.
- Epics live as `epic`-labeled parents in `Backlog` (e.g. SLU-72 "Release
  honesty & scoping"); attach children with `parentId`.
