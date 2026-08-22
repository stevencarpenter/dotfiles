---
name: kaneo-issue
description: >
  File, update, or close Kaneo tasks for any repo tracked in the self-hosted
  Kaneo workspace (sluice, hippo, homelab, snugmarina, snugmarina-base,
  dotfiles, gringotts, whistlepost, stevectl, gitdiff, ski-area-tycoon).
  Encodes project
  routing, the label set, the task body template, and the column ladder. Use
  whenever work should be tracked or its tracking state changed: "file an
  issue", "open a ticket", "add this to the backlog", "track this follow-up",
  "mark HOME-2 in progress", "close SLU-4" — and whenever a task turns up a
  defect or follow-up worth recording rather than dropping. Also use before
  filing, to dedupe. Kaneo replaced Linear as the system of record in August
  2026, so use this skill even when the request says "Linear".
user-invocable: true
---

# Filing Kaneo tasks

**Kaneo is the system of record for every repo here.** It is self-hosted at
`https://kaneo.snugmarina.org`, tailnet-only, and replaced Linear on
2026-08-09 — the Linear subscription is gone and `linear.app` URLs found in old
task descriptions no longer resolve. Never file a GitHub issue for tracking; on
`sjcarpenter/sluice` GitHub Issues are disabled outright, so a bare `#NN` in an
old commit is a dead reference.

If a request says "Linear", it means this. Don't go looking for a Linear MCP.

## 1. Route it: repo → project

Kaneo has no teams. Projects are flat, one level, and the project *is* the
routing decision — which is why the old per-repo labels (`sluice`, `homelab`,
…) no longer exist and shouldn't be recreated. Derive the target from the git
remote of the working directory; ask only if the remote is absent or ambiguous.

| Repo | Project | Slug |
|---|---|---|
| `carpenter` (meta workspace) | Carpenter | `CARP` |
| `sluice` | Sluice | `SLU` |
| `hippo` | Hippo | `HIPO` |
| `homelab` | homelab | `HOME` |
| `snugmarina` (iOS) | Snugmarina | `SNUG` |
| `snugmarina-base` (server) | Snugmarina | `SNUG` |
| `dotfiles` | Dotfiles | `DOT` |
| `gringotts` | Gringotts | `GG` |
| `whistlepost` | Whistlepost | `WP` |
| `stevectl` | Stevectl | `SCTL` |
| `gitdiff` | gitdiff | `GITD` |
| `ski-area-tycoon` | Ski Area Tycoon | `SKI` |

A repo with no row isn't onboarded — ask rather than guessing a project.

**Whistlepost is one board again.** The launch-sprint (`WP`) and full-vision
(`WPFV`) projects were merged on 2026-08-20 into a single Whistlepost project
that kept the vision board's identity and numbering: an old `WPFV-n` reference
is today's `WP-n`, and old launch `WP-n` tasks were renumbered to `n + 260`
with a "Consolidated from launch board WP-n" provenance line in each body. The
emptied launch project was renamed `WPOLD` pending deletion — never file there.

**Snugmarina's server split is transitional.** `snugmarina-base` was extracted
from `homelab` with history preserved, but deploy wiring hasn't moved — the
authoritative *production* checkout for `api/` is still
`homelab/services/snugmarina/`. API code, schema, migrations and workers are
Snugmarina work; build, deploy, ingress and observability are homelab work.
Both share the `SNUG` board except the homelab half, which goes to `HOME`.
Never edit `homelab/services/snugmarina/` directly, or the two copies fork.

**One repo per task.** Work spanning two repos becomes two tasks on their own
boards, joined with a `related` relation.

## 2. Know which ID you're holding

This trips people up more than anything else in Kaneo, because three different
identifiers are in play and only one of them works in a tool call.

| Kind | Looks like | Use |
|---|---|---|
| Opaque task ID | `jp822ltf144dsbits4o3bn98` | **Every MCP call.** Non-guessable. |
| Display ID | `HOME-1` | What humans say and read. Project slug + `number`. |
| Legacy Linear ID | `SNUG-424` | Only inside descriptions, as provenance. |

`list_tasks` returns `number` and the project returns `slug`; compose them to
get the display ID. There is no lookup-by-display-ID tool, so resolving
"HOME-2" means listing the project and matching on `number`.

The legacy IDs matter because ~724 tasks were migrated from Linear and each
carries a `Migrated from Linear **<ID>**` line. That line was the migration's
join key — leave it alone. Kaneo's own numbering restarted per project, so
`SNUG-424` became `HOME-1`: an old ID and a new ID that look alike and mean
different things. When someone gives you an ID that finds nothing, try reading
it as the other kind before concluding the task doesn't exist.

## 3. Dedupe before you file

Search first, every time — a duplicate costs far more to untangle than a search
costs to run. Kaneo has no text-query tool, so this is a list-and-scan:

```
list_tasks(projectId: "<id>", limit: 100, sortBy: "createdAt", sortOrder: "desc")
```

Boards are large (`WPFV` ~224 tasks, `SLU` ~216) and full listings are heavy,
so narrow with `status` or `priority` when you can and page rather than pulling
everything at once. Scan for the *symptom*, not your phrasing of it — a defect
is often already filed under different words. Found a match? Comment on it or
sharpen its description instead of filing. Genuine duplicate? Link the two with
a `related` relation and close the newer one; Kaneo has no `duplicateOf`.

## 4. Body template

Sections in this order; omit one only when it would be empty.

```markdown
## Problem

One or two sentences on the observed behavior and why it matters. State the
defect, not the fix.

## Acceptance criteria

- [ ] Specific, checkable outcome
- [ ] Second outcome
- [ ] <the repo's green gate — e.g. for sluice: `scripts/verify.sh` clean>

## Suggested agent

* **Implement:** `<agent-name>` — <model>
* **Verify:** `code-reviewer`

## Dependencies

- Blocked by HOME-2 — <one clause on what it unblocks>
```

What makes the template work:

- **Acceptance criteria are the contract.** Each must be checkable by someone
  who wasn't in this conversation. "Handle the error properly" fails; "a
  transient S3 body error retries, other generic errors stay fatal" passes. The
  last box is the repo's gate command, so a green run is part of done.
- **`Suggested agent` sizes the work**, and must agree with the `agent:*` label.
  Haiku for mechanical single-file edits; Sonnet for design-bearing or
  multi-file changes. Never suggest Opus — subagents cap at Sonnet.
- **`Dependencies` is a mirror, never the source of truth.** The authoritative
  form is the relation. Create the relation first; add the prose line only when
  the *why* isn't obvious from the linked title. A task whose prose claims a
  dependency it doesn't carry as a relation is a bug in the task.
- **Title is a Conventional Commit subject**: `type(scope): imperative
  description`, no trailing period, under 72 chars — e.g. `fix(sluice-delta):
  prevent SCD2 tombstone timestamp overlap`. It becomes the branch name and
  usually the commit, so getting it right here saves rework.

`description` takes markdown with literal newlines, not escape sequences.

## 5. Labels

Kaneo labels are **per-task rows, not a shared taxonomy.** Each attachment is
its own record with its own ID that merely shares a `name` with the others —
`agent-autonomous` is 281 separate rows, not one label used 281 times. So there
is no central list to curate, `list_workspace_labels` returns every attachment
rather than a vocabulary, and `delete_label` removes one task's row rather than
retiring a name.

That shape rewards a small label set. Nine names earn their keep, and all of
them exist because an orchestrator or a human actually filters on them:

| Label | Meaning |
|---|---|
| `epic` | Parent task; children hang off it via `subtask` relations |
| `orchestrator` | Meta task; never dispatch to a worker |
| `ready-for-agent` | Fully specified; an agent can finish it unattended |
| `needs-human` | Done-when needs a device, console, or credential access |
| `agent:haiku` | Mechanical, single-file, no design decisions |
| `agent:sonnet` | Design-bearing or multi-file |
| `agent-autonomous` | Safe to run unsupervised |
| `agent-parallel` | Safe to run concurrently with siblings |
| `M1`–`M5` | Snugmarina roadmap milestones — the only stand-in for the milestone entity Kaneo lacks |

Apply `agent:*` **plus** `ready-for-agent` only when the task is genuinely
self-contained — an agent could finish it from the description alone with no
decisions left open. A half-specified task marked `ready-for-agent` wastes an
agent run, which is the whole cost this label is supposed to prevent.

**Don't reach for a label when a field exists.** Priority is the worked
example: set the native `priority` field (`no-priority` | `low` | `medium` |
`high` | `urgent`), never a `priority:*` label. The board sorts on the field, so
a label carrying the same value is a second source of truth that can only
drift — and did: the `priority:*` labels inherited from Linear were deleted on
2026-08-10 after three tasks turned up whose field said `urgent` while their
label still said `priority:high`. Don't recreate them.

More generally: Linear's long tail (`area:*`, `db:*`, `connector:*`,
`format:*`, work types, per-repo labels) does not exist here and shouldn't be
rebuilt. Most of it was a workaround for packing many projects into one
account; separate projects now do that job structurally. Before creating a
label, name who filters on it — if the answer is nobody, it's decoration on
every card it touches.

Labels attach and detach individually — `attach_label_to_task` and
`detach_label_from_task`. Unlike Linear's `save_issue`, passing labels does not
replace the whole set, so there's no read-union-write dance to remember.

Create a genuinely new label with `create_label`, and give it a colour — an
uncoloured label falls back to grey and disappears into the board.

## 6. Column ladder

Move the task as the work moves; the board is only useful when it's current.

| Column | When |
|---|---|
| `to-do` | Triaged and specified, or captured and not yet committed to |
| `in-progress` | Branch created / first commit |
| `in-review` | PR opened |
| `done` | PR merged |

Set it with `update_task_status(taskId, status)` using the column slug.

Two Linear states have no Kaneo equivalent, so handle them by convention:

- **Backlog vs Todo collapsed into `to-do`.** Nothing distinguishes "captured"
  from "ready to pick up" structurally, so say it in the body: a task without
  firm acceptance criteria is visibly not ready, and `ready-for-agent` is the
  positive signal that it is.
- **No Canceled column.** Won't-do work moves to `done` with a comment saying
  why it was dropped. Without that comment it reads later as delivered, which
  is worse than leaving it open.

Reference the task from the work with the display ID in the commit body
(`Closes HOME-2`). There is no GitHub integration — nothing auto-closes, so
move the column yourself when the PR merges. Keep the branch name on the repo's
own `type/kebab-case` convention.

**The merge is the promotion.** The PR review is where the human gate lives —
once a PR merges, whoever lands the merge (usually the agent in that session)
moves the task straight to `done`; there is no separate board approval to wait
for. Close it with the PR link and one line on what shipped. If you closed it
without implementing everything the description asked for, say which criteria
you dropped and why — a silently narrowed task reads as fully delivered later.
The exception is `needs-human` tasks, whose done-ness isn't PR-shaped (device,
console, or credential work): those still wait for explicit human promotion.

Also close on behalf of dead sessions: if you find an open task whose work
demonstrably merged (a `Closes <ID>` footer, a matching PR), close it with the
evidence rather than leaving it to rot — stale board state is the failure mode
this rule exists to prevent.

## 7. Epics and hierarchy

Kaneo has no epic entity. An epic is an ordinary task carrying the `epic` label
with children attached by a `subtask` relation (source = parent, target =
child). Attach a new task to its epic at file time; an orphan drifts out of the
roadmap view.

Use `blocks` for sequencing between siblings. Parent/child expresses *scope*,
blocking expresses *order* — conflating them makes both useless. `related` is
bidirectional and carries no ordering, so it's the right choice for
cross-project links and duplicates.

Known UI limits, worth designing around rather than fighting: nesting renders
one level deep, kanban cards show no subtask rollup (only the detail view
does), and the parent sits in a column like any other task.

## 8. Tools

`mcp__kaneo__*`: `create_task`, `update_task`, `update_task_status`,
`move_task`, `list_tasks`, `get_task`, `list_projects`, `create_task_comment`,
`list_task_comments`, `create_task_relation`, `get_task_relations`,
`list_workspace_labels`, `create_label`, `attach_label_to_task`,
`detach_label_from_task`.

Three things worth knowing before the first call:

- **`create_task` requires all five of** `projectId`, `title`, `description`,
  `priority`, `status`. There are no defaults; a create with only a title fails.
- **`projectId` is the opaque ID, not the slug.** Resolve it once with
  `list_projects` and reuse it. Project IDs are listed in
  `references/workspace.md`, but re-derive if a call rejects one.
- **`whoami` is not a health check.** It reports the cached device-flow session,
  so on the API-key path it returns `null` with `isError: false` — identical to
  a broken credential. Use `list_workspaces`, which returns real rows and fails
  loudly.

Full workspace inventory — projects with IDs, per-project conventions, agent
contracts, and gate commands: `references/workspace.md`.
