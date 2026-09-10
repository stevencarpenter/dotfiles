---
name: design-an-interface
description: Design or compare code module and API interfaces against actual caller requirements. Use for interface design requests or an explicit "design it twice" exercise, not visual UI design or routine implementation.
---

# Design an Interface

Read the existing interface, callers, compatibility constraints, and failure model.
Use the supplied requirements; ask only for information that would change the
design and cannot be established from the code or conversation.

Start with the smallest interface that supports the current use cases. Reuse
existing types and conventions. Do not add methods, extension points, configurable
strategies, or a new dependency for hypothetical callers.

For an explicit comparison or a consequential unresolved tradeoff, develop a small
number of materially different designs. Use parallel specialists only when
independent exploration adds value and delegation is available. A routine interface
does not require a team or a quota of alternatives. An explicit "design it twice"
request requires at least two alternatives.

For each design, show the signature, a realistic caller example, failure behavior,
and the implementation responsibility hidden behind it. Compare ease of correct
use, compatibility, implementation and migration cost, and the actual constraints.
Fewer methods are useful only when they do not make the contract ambiguous.

Recommend the design supported by those requirements. Keep incompatible alternatives
separate instead of combining every feature. For a design-only request, deliver the
interface proposal without implementing it or opening an external issue.
