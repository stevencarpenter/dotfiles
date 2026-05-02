---
name: screenshot-bug-hunt
description: Use this skill whenever the user wants to find visual, layout, or rendering bugs in a frontend site by capturing screenshots and comparing them against expected design. Triggers on phrases like "hunt for visual bugs", "screenshot the site", "playwright check", "visual review", "look at the live site", "audit the pages", "compare desktop and mobile", "verify the design", "is the layout broken", or any time the user wants Claude to *look* at a built site rather than reason about it from code alone. Also use this skill proactively after substantial CSS / component / layout changes when the user asks for a sanity check before merging.
---

# Screenshot bug hunt

Find visual, layout, and rendering bugs in a frontend site by driving Playwright + headless Chromium, then reading the screenshots back through the image-aware Read tool. Cross-check against the rendered DOM (the `dist/` output) so you catch issues that pure visual inspection misses — broken `href`s, missing alt text, attributes that didn't propagate.

## Why this works

A visual diff catches different bugs than a code review or a unit test. The pattern that emerged from real use:

- Screenshots reveal **layout overlap, sizing weirdness, font issues, motion glitches, ornament misreads** — things humans notice instantly but linters can't see.
- Built HTML grep-checks reveal **wrong-cased URLs, plugins that silently no-op'd, attributes that didn't survive the build pipeline, link targets that resolve to 404s** — things screenshots miss because the broken-link badge looks fine until clicked.
- **Together** they catch a class of "tests passed but prod broken" bugs that neither alone would. The lesson from the original use: a unit-tested rehype plugin shipped 3 weeks of broken links because the test harness bypassed the integration path. The screenshot pass + dist-grep caught it in 30 minutes.

## When to invoke

- Before merging a substantial CSS/layout/component change.
- After upgrading a frontend framework major version (Astro 5→6, Next 14→15, etc.) — config changes silently break plugin pipelines.
- When a user says "look at the site", "is this rendering right", "screenshot the pages", "playwright check", "visual audit".
- Iteratively while polishing — capture baseline, fix something, capture again, compare.
- When something passes tests but the user thinks it looks wrong. Trust the eyes.

## Workflow

### 1. Confirm the dev/preview server is up

The skill inspects `localhost:4321` (Astro default), `localhost:3000` (Next/Vite/etc.), and `localhost:5173` (Vite default). If nothing is listening, start the project's preview script:

```bash
# Detect the right command from package.json scripts
cd <project>/site || cd <project>
# Use `pnpm preview` for the production build (truer to deployed output);
# fall back to `pnpm dev` only if no preview script exists.
pnpm build && pnpm preview &
```

**Prefer `preview` over `dev`** when possible:
- The `dev` server may use different code paths (HMR, on-demand compilation) and miss bugs that only surface in production builds.
- Pagefind/search indexes, OG image generation, and other build-time integrations only run during `build`, not `dev`.
- Static-site generators (Astro, Eleventy, etc.) often have markedly different output between dev and prod.

If the user has the server running already, just connect — don't restart.

### 2. Bootstrap Playwright into /tmp (one-time)

To avoid polluting the project's `node_modules`, install Playwright in a throwaway directory:

```bash
bash $SKILL_DIR/scripts/setup.sh
```

This creates `/tmp/screenshot-bug-hunt-pw/` with `playwright` installed and Chromium downloaded. The script is idempotent — running it again is a no-op if everything's already there.

### 3. Run the screenshot pass

The bundled script captures multiple URLs at multiple viewports. By default it auto-discovers pages from `/sitemap-index.xml` (or `/sitemap.xml`); pass an override file for targeted runs.

```bash
node $SKILL_DIR/scripts/shoot.mjs \
  --base http://localhost:4321 \
  --out /tmp/hippo-screenshots
```

Output:
- `/tmp/hippo-screenshots/desktop-<slug>.png` — full-page at 1440×900
- `/tmp/hippo-screenshots/tablet-<slug>.png` — 1024×900 for breakpoint validation
- `/tmp/hippo-screenshots/narrow-<slug>.png` — 768×900
- `/tmp/hippo-screenshots/mobile-<slug>.png` — 480×900
- `/tmp/hippo-screenshots/detail/<slug>.png` — viewport-only at 1440×900 (legible at native zoom)

**Why each viewport matters:**
- **1440** — primary desktop, where most layout decisions are validated.
- **1024** — common laptop / split-screen; usually where the first responsive breakpoint kicks in.
- **768** — tablet portrait / small laptop; second breakpoint, rails often collapse here.
- **480** — small phone; hamburger nav, single-column, scaled type.

A page that looks fine at 1440 can break at 1024. A user who screenshots their browser at 800px wide and says "this looks broken" might just be at the wrong viewport — capturing all four lets you tell the difference.

### 4. Read screenshots back via the Read tool

Claude Code's `Read` tool displays PNG files inline. Use it to view each screenshot in turn:

```
Read /tmp/hippo-screenshots/detail/desktop-00-home.png
```

Walk through the captures systematically — homepage first, then key marketing/landing pages, then docs/inner pages, then 404. As you view each, catalog issues. Don't try to fix as you go; keep the inspection pass clean. **Note**: full-page screenshots compress detail; use the `detail/` viewport-only captures for closer inspection.

### 5. Cross-check the rendered DOM

For every visual bug you suspect, also grep the built HTML to either confirm it or rule it out. This is the step that finds the bugs screenshots miss.

See `references/dom-checks.md` for grep recipes by bug type — link rewrites, missing alt text, heading hierarchy, footnote ordering, ARIA landmarks, etc.

The minimum check after any substantial change: confirm internal links don't 404 by grepping for `href="[^"]*\.md"` (markdown extension leaking through the build) or `href="[^"]*\.html"` (often a bare-build artifact) in `dist/`.

### 6. Catalog bugs with severity

Group findings into Critical / High / Medium / Low. Critical means a user-visible failure on the golden path (broken nav, broken install command, 404'd canonical link). Low is polish (a glyph that's 2px off-center). Don't fix everything you find — fix the high-priority items, flag the rest.

### 7. Iterate the fix-and-reshoot loop

After each fix:

1. `pnpm build` (the preview server doesn't auto-rebuild for static output).
2. Re-run `node scripts/shoot.mjs` (same args).
3. Re-Read the relevant screenshots.
4. Move to the next bug.

See `references/iteration-loop.md` for tactics — when to re-run all viewports vs. one, how to compare baseline vs. fixed, when to use targeted scrolls.

## Page list overrides

To screenshot a specific set of URLs (rather than auto-discover from sitemap), create a JSON file and pass `--targets`:

```json
[
  { "slug": "00-home", "path": "/" },
  { "slug": "01-add-source", "path": "/docs/capture/adding-a-source", "scroll": 700 },
  { "slug": "02-changelog-mid", "path": "/changelog", "scroll": 1500 }
]
```

```bash
node $SKILL_DIR/scripts/shoot.mjs --targets ./screenshot-targets.json
```

The `scroll` field captures the page after scrolling N pixels — useful for sections far below the fold.

## What this skill is NOT for

- **Non-frontend projects** — backend services, CLIs, data pipelines have no visual surface to inspect. Use logs / tests / metrics instead.
- **Pixel-exact regression testing** — that's a separate discipline (Percy, Chromatic, Playwright snapshot mode). This skill is for *exploratory* visual review by a human-in-the-loop agent.
- **A11y audits** — there's overlap (axe-core checks happen in CI), but a fully automated a11y pass is outside scope. The screenshots help spot obvious failures (low contrast, missing focus rings) but won't substitute for assistive-tech testing.

## Common failure modes

- **Screenshots came back narrow when you expected desktop** — your viewport size in Playwright is right, but the user's browser is at a different width. Always confirm the size of the rendered output (`file *.png` or `python -c 'from PIL import Image; print(Image.open("x.png").size)'`) before assuming a layout regression.
- **Plugins silently no-op'd in production** — if your bug catalog includes "this attribute didn't render", grep `dist/` to confirm. If the attribute IS in the source code but NOT in `dist/`, the build pipeline dropped it. Astro 6 specifically requires the tuple form `[plugin, {}]` for named-export plugins in `markdown.rehypePlugins`; bare references work for default exports but silently no-op for named ones. (See `references/dom-checks.md` for the exact diagnostic.)
- **`fullPage: true` screenshots are too tall to read detail in** — use `fullPage: false` (viewport only) for detail inspection. The full-page mode is for catching bugs that only appear far below the fold.
- **Sticky-positioned elements behave weirdly in `fullPage: true` screenshots** — they render at their original-flow position rather than scroll-pinned. This is expected; verify sticky behavior with a viewport-only capture and a `scroll` parameter.

## Reference files

- `references/dom-checks.md` — grep recipes for inspecting built HTML alongside screenshots.
- `references/iteration-loop.md` — tactics for the fix-and-reshoot loop, including baseline vs. fixed comparison.
- `scripts/setup.sh` — bootstraps Playwright + Chromium in `/tmp/`.
- `scripts/shoot.mjs` — the screenshot tool. Driven by sitemap auto-discovery or a `--targets` JSON.
