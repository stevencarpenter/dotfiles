---
name: linear-issue
description: >
  File, update, or close Linear issues for any repo in the Snugmarina Linear
  workspace (sluice, hippo, homelab, snugmarina, snugmarina-base, dotfiles,
  gringotts, whistlepost, stevectl). Encodes team/project routing, the label
  taxonomy, the
  issue body template, and the status ladder. Use whenever work should be
  tracked or its tracking state changed: "file an issue", "open a ticket", "add
  this to the backlog", "track this follow-up", "mark SLU-N in progress",
  "close SLU-N" — and whenever a task turns up a defect or follow-up worth
  recording rather than dropping. Also use before filing, to dedupe.
user-invocable: true
---

# Filing Linear issues (Snugmarina workspace)

**Linear is the tracker of record for every repo in this workspace.** Never file
a GitHub issue for tracking. On `sjcarpenter/sluice`, GitHub Issues are disabled
outright (`has_issues: false`), so a bare `#NN` in an old commit or comment is a
dead reference — the repo also moved from `stevencarpenter/` to `sjcarpenter/`,
so those numbers resolve nowhere.

## 1. Route it: repo → team → project → repo label

Derive the target from the git remote of the working directory. Ask only if the
remote is absent or ambiguous.

| Repo | Team (key) | Project | Repo label |
|---|---|---|---|
| `sluice` | Sluice (`SLU`) | Sluice | `sluice` |
| `hippo` | Snugmarina (`SNUG`) | Hippo | `hippo` |
| `homelab` | Snugmarina (`SNUG`) | Homelab | `homelab` |
| `snugmarina` (iOS) | Snugmarina (`SNUG`) | Snugmarina | `snugmarina` |
| `snugmarina-base` (server) | Snugmarina (`SNUG`) | Snugmarina | `snugmarina-base` |
| `dotfiles` | Snugmarina (`SNUG`) | Dotfiles | `dotfiles` |
| `gringotts` | Gringotts (`GG`) | Gringotts | `gringotts` |
| `whistlepost` | Whistlepost (`WP`) | Whistlepost | — |
| `stevectl` | Stevectl (`SCTL`) | Stevectl | — |

Both `team` and `project` are required on every issue. A team with no matching
row means the repo isn't onboarded — ask rather than guessing.

**One repo per issue.** Work spanning two repos becomes two issues linked with
`relatedTo`, each routed to its own team. The exception is Snugmarina: its three
repos share the `SNUG` team **and** the `Snugmarina` project, so a change
spanning them carries multiple repo labels on a single issue.

> **Snugmarina's server split is transitional.** `snugmarina-base` was extracted
> from `homelab` in July 2026 with history preserved, but deploy wiring has not
> moved — per `snugmarina-base/README.md` the authoritative *production*
> checkout for `api/` is still `homelab/services/snugmarina/`. So API code,
> schema, migrations, and workers → `snugmarina-base`; build/deploy/ingress/
> observability → `homelab`; anything touching both → **both labels**. Never
> edit `homelab/services/snugmarina/` directly, or the two copies fork. Drop the
> paired `homelab` label once deploy is rewired.

> **Legacy shape — do not extend it.** The `Side Projects` project and its
> `Repository` label group (`sluice`, `hippo`, `gringotts`) predate the
> one-team-per-repo split of 2026-07-12. The repo labels survive and are still
> applied where the table lists one, but file new issues against the repo's own
> team and project, never against `Side Projects`.

## 2. Dedupe before you file

Search first, every time. A duplicate costs more to untangle than a search costs
to run.

```
list_issues(team: "<Team>", query: "<distinctive noun phrase>", includeArchived: true)
```

Search the *symptom*, not your phrasing of it — a defect is often already filed
under different words. If you find a match, comment on it or update its
description instead of filing. If it's genuinely a duplicate that already exists
twice, set `duplicateOf` rather than closing by hand.

## 3. Body template

Match the hand-triaged format exactly. Sections in this order; omit a section
only when it would be empty.

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

- Blocked by SLU-N — <one clause on what it unblocks>
```

Rules that make the template work:

- **Acceptance criteria are the contract.** Each one must be checkable by
  someone who wasn't in this conversation. "Handle the error properly" fails;
  "a transient S3 body error retries, other generic errors stay fatal" passes.
  The last box is the repo's gate command, so a green run is part of done.
- **`Suggested agent` sizes the work,** and the sizing must agree with the
  `agent:*` label. Haiku for mechanical single-file edits; Sonnet for
  design-bearing or multi-file changes. Never suggest Opus for a subagent.
- **`Dependencies` is a mirror, never the source of truth.** The authoritative
  form is the Linear relation (`blockedBy` / `blocks` / `parentId`). Write the
  relation first; add the prose line only if the *why* isn't obvious from the
  linked title. An issue whose prose claims a dependency it doesn't carry as a
  relation is a bug in the issue.
- **Title is a Conventional Commit subject:** `type(scope): imperative
  description`, no trailing period, under 72 chars — e.g.
  `fix(sluice-delta): prevent SCD2 tombstone timestamp overlap`. It becomes the
  branch name and usually the commit, so getting it right here saves rework.

## 4. Labels

Apply, in this order:

1. **Repo label** — exactly one, per the routing table (where the repo has one).
2. **`area:*`** — exactly one. The subsystem, not the symptom.
3. **`priority:*`** — exactly one, and set the native `priority` field to match
   (`2`=high, `3`=medium, `4`=low). They are separate fields; a mismatch makes
   the backlog sort wrong.
4. **Domain labels** — as many as apply: `db:*`, `cdc-mode:*`, `connector:*`,
   `sink:*`, `format:*`, `cloud:*`, `scope:*`.
5. **Agent-dispatch labels** — `agent:haiku` or `agent:sonnet` **plus**
   `ready-for-agent`, and only when the issue is genuinely self-contained: an
   agent could finish it from the description alone, with no decisions left
   open. A half-specified issue with `ready-for-agent` wastes an agent run.
   Use `needs-human` when done-when requires a physical device, console, or
   credential access.
6. **`blocked`** — only alongside a real `blockedBy` relation.

`labels` on `save_issue` **replaces the entire set**. When adding one label to an
existing issue, read the current labels first and pass the union, or you will
silently strip the rest.

Full label inventory with descriptions: `references/workspace.md`.

## 5. Status ladder

Move the issue as the work moves — the board is only useful if it's current.

| Transition | When |
|---|---|
| → `Todo` | Triaged and specified; ready to be picked up |
| → `In Progress` | Branch created / first commit |
| → `In Review` | PR opened |
| → `Done` | PR merged |
| → `Canceled` | Won't do — leave a comment saying why |

Set it with `save_issue(id: "SLU-N", state: "In Progress")`. Reference the issue
from the work with a `Closes SLU-N` footer in the commit (Linear's GitHub
integration reads it), and keep the branch name on the repo's own
`type/kebab-case` convention rather than Linear's suggested `gitBranchName`
unless the repo says otherwise.

Closing an issue that a merged PR resolved: set `Done` and comment with the PR
link and a one-line statement of what shipped. If you closed it *without*
implementing everything the description asked for, say which criteria you
dropped and why — a silently narrowed issue reads as fully delivered later.

## 6. Epics and hierarchy

Epics are ordinary issues carrying the `epic` label, usually sitting in
`Backlog`, with children attached via `parentId`. Attach a new issue to its epic
at file time; an orphaned issue drifts out of the roadmap view. Use `blockedBy`
for sequencing between siblings — parent/child expresses *scope*, blocking
expresses *order*, and conflating them makes both useless.

## 7. Tools

`mcp__linear__save_issue` (create when `id` is omitted, update when present),
`list_issues`, `get_issue`, `save_comment`, `list_issue_labels`,
`create_issue_label`, `list_issue_statuses`.

Two gotchas:

- **The MCP has no update-label tool.** Renaming a label or editing its
  description is a Linear UI operation (Settings → Labels). Only creation is
  scriptable.
- **The tool prefix varies by harness** — `mcp__linear__*` here,
  `mcp__plugin_linear_linear__*` where Linear is loaded as a plugin. If a call
  fails on an unknown tool name, `ToolSearch` for `linear` rather than assuming
  the server is absent.

Pass markdown to `description` with literal newlines, not escape sequences.
