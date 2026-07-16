---
name: screenshot-bug-hunt
description: Take screenshots of a running frontend site and find visual, layout, or rendering bugs. USE THIS SKILL whenever the user mentions a site running locally (localhost:3000 / 4321 / 5173 / staging URL / preview / dev server) AND asks any of: "screenshot it", "look at it", "check for regressions", "find visual bugs", "is the layout broken", "verify the design", "audit the pages", "compare desktop and mobile", "playwright check", "visual review", "spot-check rendering", "investigate visually", "sanity check before I commit/merge/ship/deploy", "did anything break", "did this regress", or any phrasing where the user wants Claude to *look at the built site* rather than reason about source code alone. Triggers especially after CSS, component, layout, design-system, or framework-version changes when the user wants a pre-merge sanity check. Also fires on "tell me what's broken on /<page>", "the user reported something looks wrong", "verify the rendering of /<page>". Bias toward triggering: if the user mentions a localhost or staging URL together with any visual or layout concern, use this skill. The cost of an unnecessary trigger is small; the cost of missing a real visual regression is a shipped bug.
---

# Screenshot bug hunt

Drive Playwright + headless Chromium against a running site, read the PNGs back through the image-aware Read tool, then cross-check `dist/` HTML with grep to catch what visual review misses.

## Workflow

### 1. Server up

Connect to whatever's already running on `localhost:4321` / `:3000` / `:5173`. If nothing is listening, prefer `pnpm build && pnpm preview` over `pnpm dev` — the dev server skips build-time integrations (Pagefind, OG generation, static-site rendering) and can mask bugs that only surface in production output.

### 2. Bootstrap Playwright (one-time, idempotent)

```bash
bash $SKILL_DIR/scripts/setup.sh
```

Installs Playwright + Chromium into `/tmp/screenshot-bug-hunt-pw/` so the project's `node_modules` stays clean.

### 3. Capture

```bash
node $SKILL_DIR/scripts/shoot.mjs --base http://localhost:4321 --out /tmp/shots
```

By default discovers pages from `/sitemap-index.xml` (or `/sitemap.xml`); pass `--targets <file.json>` for a custom list (see "Page list overrides" below). Output:

- `desktop-<slug>.png` — full-page 1440×900
- `tablet-<slug>.png` — 1024×900
- `narrow-<slug>.png` — 768×900
- `mobile-<slug>.png` — 480×900
- `detail/<slug>.png` — viewport-only 1440×900 (legible at native zoom; full-page mode compresses detail)

The four widths exist to catch breakpoint failures: `1440 → 1024 → 768 → 480` covers desktop, split-screen, tablet, and phone.

### 4. Read screenshots back

`Read /tmp/shots/detail/<slug>.png` displays inline. Walk through systematically — homepage, marketing pages, docs, 404. Catalog issues; don't fix as you go.

### 5. Cross-check the DOM

Visual review misses broken hrefs, missing alt text, attributes that didn't propagate, plugins that no-op'd. Grep `dist/`. The minimum after any substantial change: `grep -roE 'href="[^"]*\.md"' dist/` should be empty on a markdown-driven site. See `references/dom-checks.md` for recipes by bug class.

### 6. Catalog by severity

Critical / High / Medium / Low. Critical = user-visible failure on the golden path (broken nav, broken install command, 404'd canonical). Low = polish. Fix the high-severity items; flag the rest.

### 7. Fix-and-reshoot

After each fix: `pnpm build` → re-run shoot.mjs → re-Read the affected screenshot. See `references/iteration-loop.md` for batching tactics, real before/after via `git stash`, and the DevTools Protocol stylesheet-override trick for fast CSS comparisons.

## Beyond the workflow

The steps above are a floor. To reach the more interesting bugs:

- **One regression usually has siblings.** A wide-table fix on one docs page may have created the same regression on every page that uses tables — find them with `grep '<table'` over the source or by scanning the screenshots for the same visual signature.
- **Prove the rule that's actually winning.** Two CSS rules with equal specificity tie on source order; the earlier one becomes dead code. Confirm via DevTools or `getComputedStyle()` rather than assuming.
- **Capture a real before/after when "what changed" is ambiguous.** `git stash` + reshoot, or the DevTools stylesheet override (`references/iteration-loop.md`).

## Artifact discipline

When the harness captures `outputs/`: keep it small. ~10–20 PNGs is plenty; 100+ will choke the eval viewer. Never dump raw HTML files — cite snippets from grep instead. Heavy artifacts (full-page captures, raw `dist/` dumps) belong in `/tmp/`, not in `outputs/`.

## Page list overrides

```json
[
  { "slug": "00-home", "path": "/" },
  { "slug": "01-add-source", "path": "/docs/capture/adding-a-source", "scroll": 700 }
]
```

```bash
node $SKILL_DIR/scripts/shoot.mjs --targets ./screenshot-targets.json
```

`scroll` captures after scrolling N pixels — useful for sections far below the fold.

## Common failure modes

- **Plugin silently no-op'd in `dist/`.** Source has the transformer; built output doesn't. Astro 6 requires the tuple form `[plugin, {}]` in `markdown.rehypePlugins` for some named-export plugin shapes — bare references silently drop. Verify by adding `process.stdout.write` at module top vs inside the transformer; if the top-level prints once but the transformer never does, registration is wrong.
- **Screenshots came back narrow when you expected desktop.** Confirm size with `file *.png` or `Image.open(p).size` before calling it a layout bug — the user's browser may be narrower than your assumption.
- **Sticky elements drift in full-page captures.** They render at original-flow position, not scroll-pinned. Verify sticky behavior with viewport-only + a `scroll` value.

## Not for

- Backend / CLI / pipeline projects — no visual surface. Use logs, tests, metrics.
- Pixel-exact snapshot regression — Percy / Chromatic / Playwright snapshot mode are the right tool. This skill is exploratory.
- A11y audits — overlap exists, but assistive-tech testing is outside scope.

## Reference files

- `references/dom-checks.md` — grep recipes for built HTML.
- `references/iteration-loop.md` — fix-and-reshoot tactics, before/after capture techniques.
- `scripts/setup.sh` — Playwright bootstrap.
- `scripts/shoot.mjs` — sitemap-driven capture tool.
