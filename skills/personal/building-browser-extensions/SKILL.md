---
name: building-browser-extensions
description: Build, debug, or review browser extensions for Chromium, Firefox, or Safari. Covers execution contexts, permissions, cross-browser APIs, and WXT projects.
---

# Building Browser Extensions

Match the requested browsers and the project's existing framework. For a new extension, consider WXT when its manifest generation and multi-browser builds remove work. A small native extension does not need a framework migration.

Read the manifest and entrypoints before changing permissions, execution contexts, or build tooling. Preserve the user's stack choice.

## Routing

- For execution contexts, messaging, storage, and worker lifetime, read [extension-architecture.md](references/extension-architecture.md).
- For WXT setup, read [wxt-guide.md](references/wxt-guide.md). Consult [tech-stack.md](references/tech-stack.md) only when selecting tooling.
- For an extension review, use the applicable checks in [review-checklist.md](references/review-checklist.md).
- For permissions and untrusted data, read [security-review.md](references/security-review.md).
- For a browser compatibility problem, read [cross-browser-compat.md](references/cross-browser-compat.md). Verify current API support for the target browser versions before adopting a workaround.
