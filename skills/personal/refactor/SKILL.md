---
name: refactor
description: Improve existing code structure without changing its observable behavior. Use for requested refactors, duplication removal, naming improvements, or simplification of an identified maintenance problem.
license: MIT
---

# Refactor

Make the smallest change that resolves the stated maintenance problem. Preserve
public behavior, compatibility, validation, error handling, and side effects.

## Establish the constraint

- Read the affected implementation and all callers before choosing a change.
  Include configuration, dynamic registration, tests, and documented external
  consumers when deciding whether something is unused.
- Identify what is difficult to change or understand and what improvement would
  resolve it. File length or a pattern name alone is not a reason to refactor.
- Check the working tree and preserve unrelated changes. Follow the repository's
  branch and commit workflow; this skill does not require a commit after each edit.

## Choose the smallest replacement

1. Delete code with no remaining contract or consumer.
2. Reuse an existing helper, standard-library operation, native feature, or
   installed dependency when it preserves the required semantics.
3. Inline forwarding wrappers and remove unused parameters or configuration.
4. Extract shared logic only when the callers need the same behavior. Similar
   syntax with different ownership, failure, or lifecycle rules is insufficient.
5. Introduce structure only when a current requirement justifies its cost.

Keep a typed parameter object instead of adding a fluent builder for ordinary
construction. Keep a short conditional instead of an interface and one class per
branch. Keep validation in a function unless rules actually need independent
registration or composition. Preserve whether validation accumulates errors or
stops at the first one, and preserve evaluation order.

Use types where they prevent actual invalid states or ambiguous inputs. Preserve
the existing return shape and error model; adding a result wrapper or domain class
is an API change unless callers already require it. Do not add a framework, plugin
system, cache, or extension point for hypothetical use.

## Verify the change

- Run the existing checks relevant to the changed behavior and repository-required
  gates. Add a focused regression check when a nontrivial behavior lacks coverage.
- Preserve edge cases, output formats, side effects, ownership, and failure paths.
  A shorter diff that changes those is not a behavior-preserving refactor.
- Make independently verifiable edits. Repeat checks after meaningful changes or
  failures, not automatically after every textual edit.
- Update callers and affected documentation in the same change. Report what was
  simplified and the verification actually run. Claim performance equivalence only
  when supported by measurements or the relevant execution semantics.
