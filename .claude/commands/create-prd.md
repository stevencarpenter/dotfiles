---
description: Create a Product Requirements Document from the current requirements
argument-hint: [output-filename]
---

Write a PRD to `$ARGUMENTS` (default: `PRD.md`) using the current conversation and
relevant project evidence. Inspect an existing destination before updating it and
preserve requirements that still apply.

Describe the user problem, intended users, agreed scope, required behavior, constraints,
and observable acceptance criteria. Include interfaces, security requirements,
migration details, or delivery stages only when they affect this product's decisions.
Use the fewest sections that make the requirements actionable.

Distinguish requirements from assumptions and unresolved decisions. Ask only for
missing information that materially changes the specification. Do not invent a
technology stack, fixed number of stories or phases, design patterns, optional
dependencies, or a future roadmap to fill a template.

Check that the requirements are consistent and verifiable. Return the file path and
any decision the user must resolve. This command writes a specification; it does not
authorize implementation, external issue creation, or deployment.
