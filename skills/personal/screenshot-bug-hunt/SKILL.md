---
name: screenshot-bug-hunt
description: "Visual review of running frontends: screenshots, layout/rendering bugs, regressions, responsive checks, and UI-change sanity checks."
---

# Screenshot bug hunt

1. Use `:4321`, `:3000`, or `:5173`. If none runs, use `pnpm build && pnpm preview`, not `pnpm dev`.
2. Bootstrap: `bash "$SKILL_DIR/scripts/setup.sh"`.
3. Capture: `node "$SKILL_DIR/scripts/shoot.mjs" --base http://localhost:4321 --out /tmp/shots`. It uses the sitemap; pass `--targets file.json` for custom pages. Review responsive widths.
4. Read `detail/*.png` with the image-aware Read tool. Check home, key pages, docs, and 404 before fixing.
5. Inspect `dist/` for broken links, missing alt text, and dropped transformations. Markdown sites should have no `.md` hrefs.
6. Fix high-severity issues, then build, recapture, and reread affected images. Keep 10–20 PNGs in `/tmp`.

Not for backend projects, pixel-exact snapshots, or standalone accessibility audits.
