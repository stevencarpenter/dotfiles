# The fix-and-reshoot iteration loop

The bug-finding pass produces a list of issues. The fixing pass works through them one at a time. Re-screenshotting after each fix is what turns "I think this is fixed" into "I can see this is fixed."

## The basic loop

```
1. Catalog bugs from the initial pass
2. Fix the highest-priority bug
3. pnpm build (or whatever rebuilds dist)
4. Re-run scripts/shoot.mjs (or just --only desktop for speed)
5. Read the affected screenshot
6. Confirm the bug is gone — or note the new shape it takes
7. Repeat
```

The two non-obvious tactics: **batching** and **scope-narrowing**.

## Batching: how many bugs to fix between reshoots

Re-screenshotting takes ~30s for a full sweep, ~10s for one viewport. Fixing trivial bugs (typos, copy fixes) takes seconds. Don't reshoot after every comma fix — batch them:

- **Trivial polish (copy, typos, tiny CSS tweaks)**: fix 5-10 in a row, then reshoot.
- **Layout / structural changes (CSS grid, component restructuring)**: fix 1-2, reshoot, confirm. These have higher risk of unintended consequences.
- **Anything that touches a shared component / global stylesheet**: reshoot after each one. A change to `tier-1.css` can ripple to every page.
- **Risky bug that may not actually be reproducible**: reshoot before AND after the fix to confirm the bug exists in the first place.

## Scope-narrowing: don't re-shoot everything

The full sweep does 4 viewports × N pages. For most fixes you only need one or two captures.

```bash
# Just the desktop pass (fastest):
node $SKILL_DIR/scripts/shoot.mjs --only desktop

# Just one specific page at all viewports:
cat > /tmp/one-target.json <<EOF
[{"slug": "home", "path": "/"}]
EOF
node $SKILL_DIR/scripts/shoot.mjs --targets /tmp/one-target.json

# A specific scrolled position on one page:
cat > /tmp/one-target.json <<EOF
[{"slug": "blog-zero", "path": "/blog", "scroll": 500}]
EOF
node $SKILL_DIR/scripts/shoot.mjs --targets /tmp/one-target.json --only desktop
```

The sweet spot for an iterative loop is `--only desktop` plus a focused targets file. Full multi-viewport sweep is for the *initial* pass and the *final* verification pass — not the middle.

## Browser cache caveat

`pnpm preview` serves files from `dist/` directly without caching headers — but the user's browser may cache CSS/JS aggressively. After a `pnpm build`, the user might still see stale CSS in their open browser tab.

Solutions:

- **Hard-refresh in the browser** (Cmd+Shift+R / Ctrl+Shift+R) clears the page's resource cache.
- **Restart the preview server** between large refactors. Astro's preview is `astro preview` which reads `dist/` at request time, but the server's own cache can be sticky after framework upgrades.
- **Playwright captures don't cache** — each browser context is fresh, so reshooting always gets the new build. If your screenshot shows the new state but your real browser still shows the old, hard-refresh the browser, not the screenshot.

## Comparing baseline vs. fixed

When the visual change is subtle, it helps to put the before-and-after side by side. The skill doesn't bundle a diff tool, but two simple options:

```bash
# Save a baseline copy before fixing.
cp /tmp/screenshot-bug-hunt-out/desktop-04-faq.png /tmp/baseline-faq.png

# After fixing and reshooting, view both via the Read tool:
#   Read /tmp/baseline-faq.png
#   Read /tmp/screenshot-bug-hunt-out/desktop-04-faq.png
# Then visually compare in conversation.
```

For pixel-precise diffs (rare for exploratory work; often valuable for last-mile verification), `imagemagick`'s `compare` produces a diff image:

```bash
compare /tmp/baseline-faq.png /tmp/screenshot-bug-hunt-out/desktop-04-faq.png /tmp/diff-faq.png
# Then Read /tmp/diff-faq.png — pixels that changed are highlighted red.
```

## Capturing a true "before" without rebuilding

The hardest baseline to capture is the one you've already overwritten — the user committed the fix, you applied it locally, the original broken state is now only reachable by reverting code. Two reliable ways to recover it:

### Option 1: git stash + reshoot

When the broken state is *uncommitted* (e.g. you're verifying a fix you just made):

```bash
# 1. Stash the in-progress fix
git stash push -m "fix-being-tested" -- site/src/styles/prose.css

# 2. Rebuild and shoot the baseline
pnpm --dir site build
node $SKILL_DIR/scripts/shoot.mjs --out /tmp/before

# 3. Pop the stash and shoot the after
git stash pop
pnpm --dir site build
node $SKILL_DIR/scripts/shoot.mjs --out /tmp/after

# 4. Read /tmp/before/<file>.png and /tmp/after/<file>.png back-to-back.
```

This is the gold standard for "did my fix actually do anything?" verification — the comparison is against an identically-built artifact, with only the targeted file changed.

### Option 2: DevTools Protocol stylesheet override (no rebuild)

When the change is purely CSS and rebuilding is slow, you can inject a *reverse* stylesheet at runtime that undoes the fix, then capture, then remove the override and capture again. This avoids any build cost.

```js
// Driving Playwright via Chrome DevTools Protocol:
const client = await page.context().newCDPSession(page);
await client.send('Runtime.evaluate', {
  expression: `
    const style = document.createElement('style');
    style.id = '__reverse-fix';
    style.textContent = \`
      /* Undo the fix being tested by re-applying the prior rule */
      .prose td, .prose th { overflow-wrap: normal !important; }
    \`;
    document.head.appendChild(style);
  `
});

// ... screenshot the "before" state ...

await client.send('Runtime.evaluate', {
  expression: `document.getElementById('__reverse-fix')?.remove();`
});

// ... screenshot the "after" state — this is the real shipped behavior ...
```

**When to use which:**

- **`git stash`** — you trust the build is reproducible, you have time for two builds, and the change isn't purely cosmetic CSS. This is the safer choice; the captured baseline is byte-identical to what the user would have seen.
- **DevTools override** — the change is a small CSS rule, rebuilding takes minutes, and you want a tight feedback loop. Trust this less for non-CSS changes (you can't reliably "undo" a JSX restructuring with an injected stylesheet).

The override technique is also useful for *speculative* before/afters: "what would this page look like if we deleted this rule?" — you can capture both states without ever editing source.

## When to stop

Stop when:

- Every catalogued bug is verified-fixed by a fresh screenshot OR explicitly deferred with a note.
- A final full-viewport sweep produces screenshots that match expectations end-to-end.
- The DOM grep checks (see `dom-checks.md`) come up clean for the categories you care about (link rewrites, heading hierarchy, alt text).
- The user has eyeballed the final pass and signed off.

Don't stop just because you ran out of patience — that's how regressions ship. Don't keep going forever — there's always another 2px imperfection to chase. The "is this still load-bearing?" test: if the bug is in a code path a user actually traverses, it's worth fixing. If it only affects an internal page no one visits, it's probably safe to defer.

## Common failure mode: looking at the wrong screenshot

After several iterations, screenshot files start to feel similar. Verify you're looking at the freshly-captured one:

```bash
ls -la /tmp/screenshot-bug-hunt-out/desktop-04-faq.png
# Check that the modification time is recent (post-build).
```

If the file timestamp is from an older run, your reshoot didn't actually overwrite it (could be a file-system permission issue or a path mismatch). Re-run the shoot with `--out` pointing at a fresh directory if in doubt.
