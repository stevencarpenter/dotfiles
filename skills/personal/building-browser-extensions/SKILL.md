---
name: building-browser-extensions
description: Use when building, scaffolding, or reviewing browser extensions targeting Chromium, Firefox, and/or Safari — covers WXT framework, cross-browser APIs, manifest configuration, permissions security, and architecture review
---

# Building Browser Extensions

Build cross-compatible browser extensions (Chrome, Firefox, Safari) using **WXT** with TypeScript. Also provides structured codebase review for existing extensions.

**Framework:** WXT is prescribed — not optional. It handles manifest generation, cross-browser targeting, HMR, and the service-worker/event-page divergence automatically.

## Routing

```dot
digraph route {
  "Task?" [shape=diamond];
  "New extension" [shape=box];
  "Review existing" [shape=box];
  "Cross-browser issue" [shape=box];

  "Task?" -> "New extension" [label="building"];
  "Task?" -> "Review existing" [label="reviewing"];
  "Task?" -> "Cross-browser issue" [label="debugging"];

  "New extension" -> "Read: wxt-guide.md\nthen: extension-architecture.md\nthen: tech-stack.md" [style=dashed];
  "Review existing" -> "Read: review-checklist.md\n(routes to security-review.md\nand cross-browser-compat.md)" [style=dashed];
  "Cross-browser issue" -> "Read: cross-browser-compat.md" [style=dashed];
}
```

## References

- **wxt-guide.md** — Scaffolding, project structure, dev workflow, build commands, WXT modules
- **extension-architecture.md** — Execution contexts, message passing, storage, permissions, service worker lifecycle
- **tech-stack.md** — UI frameworks, testing, linting, recommended libraries
- **security-review.md** — Permissions audit, CSP, unsafe patterns, store rejection pitfalls
- **cross-browser-compat.md** — MV3 status, API gaps, Safari constraints, background context divergence
- **review-checklist.md** — Structured 4-phase codebase review process
