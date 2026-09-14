---
name: screenshot-bug-hunt
description: Inspect screenshots and the rendered DOM of a running frontend for layout defects and responsive regressions. Use for a visual review or verification of a UI change.
---

# Screenshot Bug Hunt

Identify the requested pages and their running URL from the task or project configuration. Reuse the existing server. If a build or preview is needed, use the project's package manager and scripts; do not assume a port, framework, or static output directory.

Use the configured browser tools for targeted captures and DOM inspection. For a sitemap-based batch, the bundled helper provides multiple viewports:

```bash
bash "$SKILL_DIR/scripts/setup.sh"
node "$SKILL_DIR/scripts/shoot.mjs" --base "$SITE_URL" --out /tmp/shots
```

Set `SKILL_DIR` to this skill's directory and `SITE_URL` to the verified running URL. The setup script installs the helper's browser dependency in a user cache. Reuse an existing installation when available. Pass `--targets file.json` for selected pages or sites without a sitemap.

Inspect the captured images with an image-capable tool. Pair visible defects with relevant DOM checks from [dom-checks.md](references/dom-checks.md). Check affected pages at representative narrow and wide viewports; expand to shared components when the evidence warrants it.

A review request produces findings. When fixes are requested, use [iteration-loop.md](references/iteration-loop.md) to verify them. Keep artifacts outside the repository unless the user requests committed snapshots.
