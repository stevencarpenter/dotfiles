---
name: using-hippo-brain
description: Retrieve prior attempts, decisions, lessons, or recorded CI outcomes from Hippo when that history is relevant to the active task.
---

# Using the Hippo Brain

Use the configured Hippo MCP server to retrieve shell activity, prior sessions, browser history, and recorded CI outcomes. Follow the active repository's recall requirements.

## Select the retrieval

| Need | Tool |
|---|---|
| A synthesized answer about prior work | `ask(question)` |
| Raw ranked semantic or lexical matches | `search_hybrid(query, mode=hybrid|semantic|lexical|recent)` |
| Distilled knowledge nodes | `search_knowledge(query, mode=semantic|lexical)` |
| A shell, session, or browser timeline | `search_events(query, source=shell|claude|browser|all)` |
| A compact context block | `get_context(query)` |
| Repeated failure lessons | `get_lessons(repo?, path?, tool?)` |
| A recorded CI outcome | `get_ci_status(repo, sha=…|branch=…)` |
| Projects or named entities | `list_projects()` or `get_entities(type?, query?)` |

Discover the tool before calling it and use its current schema. A missing lesson does not establish that an approach was never tried; lessons contain repeated patterns rather than every event.

## Scope

Use `project` for repository-specific history. Search without it when the question concerns other projects or when the active instructions require both scopes. Add `since` only when older history is irrelevant.

The general retrieval tools accept `project` and `since`. Most accept `branch`; `get_context` does not. `search_events` uses `source=all` and does not include the `workflow` source accepted by the knowledge retrievers.

## Use the evidence

Check the recorded repository, branch, timestamp, and outcome before applying a lesson. State the relevant prior attempt or lesson in one sentence. Verify current source or system state before treating a historical result as a current fact.

For CI, query the exact pushed SHA when the active task needs its result. A captured status may lag GitHub; use the GitHub tool when current status is required or Hippo has no record. Do not start checking an unrelated earlier push merely because the user resumes the conversation.

Avoid repeating an unchanged query between edits. Query again when the approach changes, new evidence matters, or the active instructions require another checkpoint.
