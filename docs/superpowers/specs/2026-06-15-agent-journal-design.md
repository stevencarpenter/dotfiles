# Agent Journal and Daily Standup Automation - Design

**Date:** 2026-06-15
**Status:** Approved via brainstorming on 2026-06-15
**Scope:** Dotfiles-managed tooling for personal and work machines; Obsidian vault output

## Problem

Daily notes are useful as an operational index, but they are currently too manual
for agent-heavy work. Agent sessions can span multiple repositories, especially
on the work machine where one Jira task may require changes across Terraform,
Kubernetes configuration, and service repositories. Capturing this by hand at
the end of the day loses decisions, verification details, and carry-forward
items.

At the same time, raw agent transcripts and command logs do not belong in the
daily note. They are too large, noisy, and likely to contain details that should
not be copied into a long-lived daily index.

## Goals

- Keep Obsidian daily notes as concise daily indexes.
- Preserve the work standup workflow as an automation-owned, copyable draft.
- Capture agent work as workstream-centered notes, not repo-centered notes.
- Support multi-repo workstreams, especially work Jira tasks that touch several
  repositories in one afternoon.
- Manage all machine-specific tooling from the chezmoi dotfiles repo.
- Keep plugin distribution, skill distribution, MCP sync, and agent journaling
  as separate concerns.
- Prefer explicit agent events where possible, with passive transcript adapters
  as enrichment.
- Avoid durable writes when a workstream cannot be confidently identified.

## Non-Goals

- No direct Slack posting in v1. The system writes a draft for review/copying.
- No GitHub Copilot adapter. Copilot is too weak as a durable transcript source
  and should not distort the design.
- No raw transcript or command-output dumping into daily notes.
- No home-lab/central service dependency for work-machine capture.
- No replacement for Hippo on personal machines. Hippo can enrich this later,
  but the work-machine path must stand alone.
- No automatic creation of untriaged workstream notes.

## Key Decisions

| Decision | Choice |
|---|---|
| Primary organization unit | Workstream, not repository or individual session |
| Daily note role | Chronological index and generated standup destination |
| Session note role | Subordinate evidence and running narrative |
| Unknown workstream behavior | Stop and ask; do not invent or dump |
| Standup ownership | `## Standup Draft` is automation-owned and replaceable |
| Manual standup preservation | User creates/calls out a separate manual copy |
| Dotfiles capability | New `agent_journal` capability |
| Copilot | Out of scope |

## Obsidian Note Model

### Daily Note

The daily note remains small and chronological:

```md
## Todo
## Work Log

## Decisions
## Agent Activity
## Carry Forward

## Standup Draft
## Home + Family Logistics
## Notes
```

`Agent Activity` contains compact index entries:

```md
- 14:00 [[Workstreams/LA-3141 databricks compute plane]]: updated Terraform,
  Kubernetes config, and service repo; verified plan; one follow-up remains.
```

Daily notes link to workstream notes. They do not contain raw transcript chunks,
long command output, or full running narratives.

### Workstream Note

Workstream notes are the durable source for a task or ticket:

```md
# LA-3141 databricks compute plane

machine: work
jira: LA-3141
context: work
repos:
  - terraform
  - k8s-config
  - service-repo
sessions:
  - [[Agent Sessions/work/2026-06-15 1300 codex terraform apply]]

## Running Narrative
## Decisions
## Repo Changes
## Verification
## Standup-Relevant Notes
## Carry Forward
```

For personal work, the same structure applies. The workstream name may be a
project task such as `stevectl release 7.4.0` instead of a Jira key.

### Agent Session Note

Session notes are subordinate evidence:

```md
# 2026-06-15 1300 codex terraform apply

tool: codex
machine: work
cwd: /path/to/repo
workstream: [[Workstreams/LA-3141 databricks compute plane]]
source_session_id: codex-2026-06-15T13-00-00
last_source_offset: 18452

## Running Narrative
## Decisions
## Changes
## Verification
## Open Threads
## Standup-Relevant Notes
```

Each session note records a source offset or equivalent watermark so repeated
hourly runs summarize only new transcript/log material.

## Dotfiles Architecture

New tooling lives beside existing vendored Python tools:

```text
agent_journal/
  pyproject.toml
  src/agent_journal/
  tests/
dot_config/agent-journal/config.toml.tmpl
dot_config/agent-journal/workstreams.toml.tmpl
dot_local/bin/executable_agent-note
.chezmoiscripts/run_after_sync-agent-journal.sh.tmpl
Library/LaunchAgents/org.stevec.agent-journal.plist.tmpl
```

The naming intentionally does not reuse `mcp_sync`. MCP sync gives agents tools;
skills sync teaches agents behavior; agent journal records and summarizes what
agents did.

### Capability Gating

Add `agent_journal` to every row of `.chezmoidata/machines.toml`:

```toml
[machines.personal-mac]
agent_journal = true

[machines.work-mac]
agent_journal = true

[machines.lab-mac]
agent_journal = false
```

The capability gates:

- `dot_config/agent-journal/`
- `dot_local/bin/executable_agent-note`
- `.chezmoiscripts/run_after_sync-agent-journal.sh.tmpl`
- `Library/LaunchAgents/org.stevec.agent-journal.plist.tmpl`

The post-apply hook must self-gate at runtime. Chezmoi-managed scripts can
appear in `chezmoi managed` even when they are hooks, so gating only via
`.chezmoiignore` is not enough.

## Command Surface

`agent-note`

- Thin CLI for explicit event capture by agents.
- Appends structured JSONL to local state.
- Stable contract for agent instructions, independent of each vendor's
  transcript format.

`agent-journal ingest`

- Reads explicit events and passive transcript/log adapters.
- Normalizes them into the internal event/session model.
- Updates local state and watermarks.

`agent-journal digest`

- Updates workstream notes, session notes, and daily `Agent Activity`.
- Refuses durable note writes when workstream classification is low-confidence.

`agent-journal standup`

- Rewrites the automation-owned `## Standup Draft` in today's daily note.
- Uses daily `Decisions`, `Agent Activity`, `Carry Forward`, linked workstream
  notes, and `Standup-Relevant Notes`.

`agent-journal status`

- Reports skipped sessions that need workstream classification.
- Reports adapter health and last successful run timestamps.

## Explicit Event Schema

The event schema is append-only JSONL:

```json
{
  "time": "2026-06-15T14:00:00-06:00",
  "machine": "work",
  "tool": "codex",
  "cwd": "/repo/foo",
  "workstream": "LA-3141 databricks compute plane",
  "event": "verification",
  "summary": "Ran terraform plan for services/infrastructure; remaining drift is expected.",
  "links": [],
  "repos": ["terraform", "k8s-config"]
}
```

Allowed event types in v1:

- `start`
- `decision`
- `change`
- `verification`
- `blocker`
- `carry_forward`
- `finish`

Agents should emit explicit events at material boundaries: start, important
decision, meaningful change, verification, blocker, and finish. These events
are source material, not prose for Slack.

## Passive Adapters

### v1 Adapters

- Codex session JSONL and local Codex state.
- Claude Code transcript/state adapter after verifying the actual source layout
  on each machine.
- OpenCode adapter if local state is available and stable enough.

### Explicitly Excluded

- GitHub Copilot.

### Adapter Rules

- Identify source type before summarizing.
- Track source offsets/watermarks.
- Do not treat workflow journals as ordinary active sessions.
- Prefer schema-aware parsing over free-text scraping.
- Redact obvious secrets and high-risk tokens before model summarization.
- Never write raw transcript content into Obsidian.

## Workstream Resolution

Resolution inputs:

- Explicit `workstream` from `agent-note`.
- Jira key from prompt, branch, or transcript.
- Existing workstream note aliases.
- Current working directory and git remote.
- Branch name.
- Recent daily note links.
- Session prompt/task title.

Resolution outcomes:

- High confidence: write to the matched workstream.
- Multiple plausible matches: ask the user.
- No plausible match: ask the user.

Unknown sessions are not filed into an `Untriaged Agent Work` note. They remain
in local state and appear in `agent-journal status` until classified.

## Standup Synthesis

The standup draft remains in the daily note:

```md
## Standup Draft
_Generated: 2026-06-15 08:45 from Decisions, Agent Activity, Carry Forward, and linked workstreams._

*Yesterday*
* Updated Terraform and Kubernetes configuration for the Databricks compute plane.

*Today*
* Verify the apply result and clean up the follow-up service repo change.

*Blockers*
* None
```

`## Standup Draft` is automation-owned. Regeneration may replace it. If manual
wording must be preserved, the user creates a separate section such as
`## Manual Standup Draft` or explicitly tells the agent not to overwrite it.

The generator should optimize for short work-communication prose. It should not
include detailed command output or verbose agent self-reporting.

## Scheduling

Use a launchd LaunchAgent managed by chezmoi.

Default schedule:

- Hourly during waking/work hours: `agent-journal ingest` then
  `agent-journal digest`.
- Morning before standup: `agent-journal standup`.
- Manual runs remain available through the CLI.

The exact calendar intervals are configuration, not hard-coded behavior.

## Machine Behavior

### Work Machine

- Writes work notes and workstream/session notes.
- No Hippo dependency.
- Workstream classification is especially important because work commonly spans
  multiple repositories per ticket or prompted task.

### Personal Machine

- Writes personal and cross-device project notes.
- May optionally use Hippo-derived context as enrichment later.
- Cross-device projects include dotfiles, `python_playa`, `stevectl`, and `nuv`.

### Lab Machine

- Off in v1.

## Safety and Privacy

- No raw logs in daily notes.
- No raw transcript dumps in workstream notes.
- Obvious secrets/tokens are redacted before summarization.
- Work-machine processing stays local to the work machine.
- Unknown workstreams cause a prompt/classification request, not silent filing.
- Generated standup drafts do not post to Slack automatically.

## Testing Strategy

Unit tests in `agent_journal/tests/` using temporary directories and fixture
transcripts:

- Event schema validation.
- Config rendering/parsing.
- Daily note path calculation.
- Daily section replacement for automation-owned `Standup Draft`.
- Workstream resolver: explicit match, Jira match, branch match, ambiguous
  match, no match.
- Watermark behavior for JSONL/session sources.
- Codex adapter fixtures.
- Workflow-journal exclusion.
- Obsidian writer idempotence.
- Secret redaction on representative tokens.

Integration/smoke tests:

- `agent-note` appends a valid event.
- `agent-journal digest` updates a temp vault without duplicating daily entries.
- `agent-journal standup` replaces only `## Standup Draft`.
- LaunchAgent plist renders only when `agent_journal = true`.

## Documentation

Update dotfiles documentation with:

- `agent_journal` capability description.
- Manual CLI usage.
- How agents should call `agent-note`.
- Where local state, watermarks, and logs live.
- How to classify skipped sessions.

The Obsidian vault template should be updated separately to include the
automation-friendly sections, but the tooling and per-machine deployment live in
this dotfiles repo.

## Open Questions

None. The remaining decisions are implementation details to discover while
building adapters against real local transcript formats.

## Success Criteria

- `agent_journal` is deployed only on intended machines.
- `agent-note` provides a stable explicit event contract for agents.
- Hourly digest updates workstream/session notes without bloating daily notes.
- Unknown workstreams are surfaced for classification instead of silently filed.
- `## Standup Draft` is regenerated from daily and linked workstream material.
- No direct Slack posting occurs.
- Copilot is not part of the v1 adapter surface.
