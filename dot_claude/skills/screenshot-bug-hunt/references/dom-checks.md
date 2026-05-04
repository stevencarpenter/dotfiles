# DOM checks alongside screenshots

Screenshots show pixels; the DOM shows truth. A badge can render correctly but link to nowhere. A heading can look right but lack the `<h1>` tag a screen reader needs. The grep recipes below catch what visual review misses.

Run all of these against the *built* output (`dist/`, `build/`, `out/` — whichever your project uses). Don't grep the source — the source is what you wrote, not what shipped.

## Detect plugin no-ops

Symptom: the source code has a rehype/remark/Vite plugin that's supposed to transform something — rewrite links, add anchors, inject metadata — but the transformation never appears in the built output.

```bash
# Astro 5/6 — were rehype/remark plugins registered as bare references?
# Bare refs to NAMED exports silently no-op; tuple form `[plugin, {}]` works.
grep -nE "rehypePlugins:|remarkPlugins:" astro.config.* /dev/null
```

If your config has `rehypePlugins: [rehypeFoo, rehypeBar]` and one of them is a named export (not a default), wrap it: `[[rehypeFoo, {}], [rehypeBar, {}]]`. There's no error message — the plugin module loads, the transformer just never runs.

Fast verification: add `process.stdout.write("[plugin-name] called\n")` at the top of the transformer body. If it prints during `pnpm build`, it's wired up. If it doesn't, the registration is wrong.

## Internal link rewrite check

Symptom: a markdown-rendering site has `[link](sibling.md)` style links that should have been rewritten to site URLs, but the rendered page still has `.md` in the `href`.

```bash
# Any .md leaks in the built HTML? Should be zero on a markdown-driven site.
grep -roE 'href="[^"]+\.md[^"]*"' dist/ | head -20

# Same for raw repo paths that should resolve to GitHub blob URLs.
grep -roE 'href="(LICENSE|CHANGELOG|crates/|src/|scripts/)[^"]*"' dist/ | head -20
```

If either returns results, your link-rewrite rehype plugin isn't running on those pages. (Common cause: see "plugin no-ops" above.)

## Cross-tree relative paths

Symptom: a doc page in one directory links to a sibling in a different tree (e.g., `../../scripts/install.sh` from a `docs/capture/foo.md`). These aren't `.md` and aren't `/`-prefixed, so naive link-rewrite logic skips them — they end up as broken `/docs/.../scripts/install.sh` after the slug rewrite.

```bash
# Look for relative paths that escape the docs tree.
grep -roE 'href="\.\.[^"]+"' dist/ | head -20
```

Rewriting these to absolute GitHub blob URLs is the usual fix.

## Heading hierarchy

Symptom: a page renders headings that look fine (because CSS does the visual work) but skip levels (h1 → h3) or have multiple h1s — both screen-reader failures.

```bash
# Count h1s per page. Anything other than 1 is a bug.
for f in dist/**/index.html; do
  count=$(grep -c '<h1' "$f")
  echo "$count $f"
done | sort -n | head -20

# Find pages with NO h1.
for f in dist/**/index.html; do
  if ! grep -q '<h1' "$f"; then echo "no h1: $f"; fi
done

# Find pages where h2 appears before h1 (skip-level).
for f in dist/**/index.html; do
  first_h1=$(grep -no '<h1' "$f" | head -1 | cut -d: -f1)
  first_h2=$(grep -no '<h2' "$f" | head -1 | cut -d: -f1)
  if [[ -n "$first_h2" && (-z "$first_h1" || "$first_h2" -lt "$first_h1") ]]; then
    echo "h2-before-h1: $f"
  fi
done
```

## Demoted heading levels (h4/h5/h6) without styling

Symptom: a page with multiple heading levels has its lower levels rendering as plain bold text — visual hierarchy collapses.

This often happens when a markdown renderer demotes headings (e.g., shifting h1→h3, h2→h4 to fit a wrapper context) but the prose CSS only styles h1/h2/h3. The h4/h5/h6 fall through to the global reset.

```bash
# Look for h4/h5/h6 in built pages — if they exist, your prose CSS must style them.
grep -roE '<(h4|h5|h6)[^>]*>' dist/ | head -10

# Then verify your stylesheet actually has rules for them:
grep -nE '\.prose h(4|5|6)' src/**/*.css
```

## Image badges and image-only links

Symptom: a link wraps only an `<img>` (e.g., a shields.io badge) but a text arrow `↗` got appended, creating visual noise.

```bash
# Find <a> elements whose only child is an <img> followed by an arrow.
grep -roE '<a [^>]*><img [^>]*></a> ↗' dist/
grep -roE '<a [^>]*><img [^>]*> ↗</a>' dist/
```

The fix is to skip the arrow when the link's only meaningful child is an image. (See the conversation history of the screenshot-bug-hunt skill for the implementation.)

## Missing alt text

Symptom: images without alt attributes — fail accessibility audits and are useless to screen readers.

```bash
# Strict: any <img> without an alt attribute at all.
grep -roE '<img(?![^>]*\balt=)' dist/ | head -10

# Looser: <img alt="" with no description (intentional empty alt for decorative images is OK).
grep -roE '<img [^>]*alt=""[^>]*>' dist/ | wc -l
```

## ARIA landmark coverage

Symptom: screen-reader navigation by landmark fails because critical regions lack roles or labels.

```bash
# Every page should have these. Anything missing on any page is a bug.
for landmark in "<header" "<main" "<nav" "<footer"; do
  count=$(grep -rl "$landmark" dist/ | wc -l)
  total=$(find dist -name "index.html" | wc -l)
  echo "$landmark: $count / $total pages"
done
```

## Canonical URL sanity

Symptom: `<link rel="canonical">` points to a wrong URL (often happens when the build's site URL is misconfigured, or a redirect rule changes the public path).

```bash
# All canonical URLs in the build. Should all start with the production hostname.
grep -roE 'rel="canonical" href="[^"]+"' dist/ | sort -u | head -10
```

## OG / social card metadata

Symptom: `og:image` references a path that doesn't exist in `dist/`, or all pages share one hardcoded card.

```bash
# Check every page has an OG image set.
for f in dist/**/index.html; do
  if ! grep -q 'property="og:image"' "$f"; then echo "no og:image: $f"; fi
done

# Verify the referenced files actually exist.
grep -ohE 'property="og:image"[^>]+content="([^"]+)"' dist/**/*.html \
  | sed -E 's/.*content="([^"]+)"/\1/' \
  | sort -u \
  | while read url; do
      path=$(echo "$url" | sed 's|^https://[^/]*||')
      if [[ ! -f "dist${path}" ]]; then echo "MISSING: $url"; fi
    done
```

## Print stylesheet sanity

Symptom: a docs site advertises print-friendliness but the printed PDF includes nav, footer, sidebar — useless.

```bash
# Confirm @media print rules exist and hide chrome.
grep -nA5 "@media print" dist/_astro/*.css 2>/dev/null \
  || grep -nA5 "@media print" dist/assets/*.css 2>/dev/null
```

A complete print stylesheet should hide `.site-header`, `.site-footer`, navs, search/copy buttons, and skip-links.

## How to use this in a screenshot-bug-hunt session

1. After taking screenshots and visually cataloging suspected bugs, run the relevant grep recipe above for *each* suspected bug to confirm or rule out.
2. If a grep returns unexpected results (e.g., `.md` links you thought were rewritten), that's a real bug — likely a plugin no-op.
3. If a grep returns clean but the screenshot still looks wrong, the bug is purely visual (CSS, font, layout). Fix in stylesheets.
4. Cross-checks at the dist/ level catch ~30% of bugs that screenshots miss; screenshots catch ~70% that grep misses. Use both.
