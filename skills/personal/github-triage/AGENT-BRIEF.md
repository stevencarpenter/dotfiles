# Agent briefs

An implementation brief records the requested behavior and acceptance criteria so a later implementer can work without the original conversation.

Use the issue's existing description when it already serves that purpose. Add a separate brief only when requested or part of the repository's handoff workflow.

Include:

- Current behavior and the concrete trigger or reproduction.
- Desired behavior, relevant edge cases, and error conditions.
- Known interfaces and constraints that affect the implementation.
- Independently checkable acceptance criteria.
- Scope exclusions that prevent a likely misunderstanding.

Scale the brief to the task. A small bug may need one paragraph and its reproduction command. Do not invent dependencies, architecture decisions, or a fixed number of criteria to fill a template.

Use symbols and behavioral contracts as the primary references. Include current file paths when they help locate the implementation, but describe the behavior so the brief survives a rename. Line numbers alone are not a specification.

Example:

> Descriptions longer than 1024 characters currently truncate mid-word.
> Keep shorter descriptions unchanged. For longer descriptions, cut at the
> last word boundary that leaves room for `...`, including the suffix within
> the 1024-character limit. If no word boundary exists, cut at that limit
> minus the suffix length. Verify a short description, a multiword overflow,
> and a single word longer than the limit.

The latest maintainer direction remains authoritative. A posted brief does not override later clarification or grant permission for unrelated external actions.
