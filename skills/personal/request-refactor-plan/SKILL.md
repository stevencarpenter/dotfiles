---
name: request-refactor-plan
description: Produce an actionable, behavior-preserving refactor plan or RFC from the current code and requirements. Use when the user requests planning; publish a GitHub issue only when requested or already authorized.
---

# Plan a refactor

Read the affected implementation, callers, existing tests, and repository workflow.
Verify the stated problem before proposing changes. Use the conversation's existing
requirements and ask only questions whose answers would change scope or approach.

Prefer deletion, reuse, and the existing architecture. Compare alternatives only
when an unresolved tradeoff matters. Do not turn a local cleanup into a framework,
module split, dependency replacement, or exhaustive user interview.

Include the information needed to implement and review the requested change:

- The concrete problem and behavior that must remain unchanged.
- The proposed edit, affected paths and callers, and any compatibility or migration
  constraint. Current paths and small examples are useful when they remove ambiguity.
- The fewest independently verifiable steps needed. A one-step refactor can have a
  one-step plan; do not prescribe a commit per edit.
- Relevant existing checks and any focused regression coverage needed for changed
  logic. Do not add a generic testing tutorial or ask the user to design the tests.
- Material unresolved decisions, with evidence needed to resolve them.

Return the plan in the requested destination. Creating an external issue requires
authorization for that action; a request to plan alone is insufficient. When issue
creation is authorized, use the configured GitHub tool and report the resulting link.
