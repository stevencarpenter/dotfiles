---
name: journaling
description: Use when agent-journal is configured and material work should be captured in the user's journal.
---

# Journaling

Use this skill to decide whether to record agent work through `agent-journal`.

Before journaling, self-gate:

```bash
test -f "$HOME/.config/agent-journal/config.toml" && command -v agent-note >/dev/null 2>&1
```

If that check fails, do nothing and continue the user's task.

## The bar

Record it only if the user would ask about it in two weeks.

Four things clear that bar:

- **decision**: a choice among alternatives that constrains later work.
- **milestone**: a unit of work that reached a done state, such as shipped,
  merged, opened as a PR, deployed, or verified passing.
- **issue**: a blocker, defect, or risk that stops progress until acted on.
- **todo**: a follow-up explicitly deferred for later.

## Do not record

These are the failures that filled the journal with noise. None of them belong:

- Announcing what you are about to do, or restating the task.
- Orienting in a repository, reading files, or searching.
- Intermediate steps inside work that is still in progress.
- A test run that passed without shipping anything.
- A routine refactor with no outcome.
- Progress reports such as "running the full gate now" or "checking the diff".

One completed unit of work is one event. A feature that took four commits, two
review rounds, and a merge is one milestone, not seven.

## Recording

`--event` is optional and advisory. The recorded type is assigned from the
summary's substance and may differ from what you claim. A summary claiming
`finish` that describes blocked work is recorded as an `issue`. That is
expected, not an error.

An event judged to belong in no section is not recorded at all. `agent-note`
prints `skipped` and exits 0.

Never record secrets, credentials, or tokens.

Use the narrower skills when they apply:

- `record-decision` for architectural or workflow decisions.
- `record-todo` for follow-up tasks.
- `wrap-session` for milestones and issues.
