---
name: domain-model
description: Stress-test a plan against the project's domain language and documented decisions, resolve material ambiguities, and capture agreed terminology or architectural decisions.
disable-model-invocation: true
---

# Domain Model

Read the plan, relevant code, and existing domain documentation before asking questions. Use `CONTEXT-MAP.md` when present to locate the affected contexts; otherwise look for `CONTEXT.md` or the project's existing glossary and decision records.

Challenge claims that conflict with the code or documented domain. State the evidence and propose a specific interpretation. Do not treat an implementation detail as proof of the intended business rule.

## Discussion

Ask one question at a time when user judgment is needed. Include your recommended answer and its consequence. Resolve dependencies between decisions before asking about their details.

Use concrete scenarios to expose ambiguous terms, ownership, cardinality, or lifecycle rules. Stop when the plan's material ambiguities are resolved. Do not enumerate hypothetical branches that cannot affect the requested work.

## Capture agreed decisions

Update the existing domain document as terms are agreed. If none exists, create `CONTEXT.md` when there is a resolved term worth preserving. Use [CONTEXT-FORMAT.md](CONTEXT-FORMAT.md) as a compact fallback, not a replacement for the project's established format.

Keep domain terms separate from implementation details. Mark unresolved proposals as unresolved rather than recording them as decisions.

Record an ADR when a real trade-off is costly to reverse or its rationale would otherwise be lost. Follow the existing ADR convention, or use [ADR-FORMAT.md](ADR-FORMAT.md). Routine reversible choices do not require a decision record.
