#!/usr/bin/env node
// Screenshot tool for the screenshot-bug-hunt skill.
//
// By default, auto-discovers URLs from the site's sitemap and captures every
// page at four viewports plus a viewport-only "detail" capture for legible
// inspection. Supports a JSON `--targets` override for partial / scrolled runs.
//
// The playwright dependency is loaded from a /tmp workdir so we don't pollute
// the user's project. See scripts/setup.sh.

import { mkdirSync } from "node:fs";
import { resolve, dirname } from "node:path";
import { fileURLToPath } from "node:url";
import { readFile } from "node:fs/promises";
import { createRequire } from "node:module";

// ---------- arg parsing ----------

function parseArgs(argv) {
  const args = {
    base: "http://127.0.0.1:4321",
    out: "/tmp/screenshot-bug-hunt-out",
    workdir: "/tmp/screenshot-bug-hunt-pw",
    targets: null,
    only: null,                 // viewport tag filter, e.g. "desktop"
    sitemapPath: "/sitemap-index.xml",
  };
  for (let i = 2; i < argv.length; i++) {
    const a = argv[i];
    const eq = a.indexOf("=");
    const [key, val] =
      eq >= 0 ? [a.slice(0, eq), a.slice(eq + 1)] : [a, argv[++i]];
    switch (key) {
      case "--base": args.base = val; break;
      case "--out": args.out = val; break;
      case "--workdir": args.workdir = val; break;
      case "--targets": args.targets = val; break;
      case "--only": args.only = val; break;
      case "--sitemap": args.sitemapPath = val; break;
      case "--help":
      case "-h":
        printHelp();
        process.exit(0);
      default:
        console.error(`unknown arg: ${a}`);
        printHelp();
        process.exit(2);
    }
  }
  return args;
}

function printHelp() {
  console.log(`Usage: node shoot.mjs [options]

Options:
  --base URL         Base URL of the running preview/dev server (default http://127.0.0.1:4321)
  --out DIR          Output directory for PNGs (default /tmp/screenshot-bug-hunt-out)
  --workdir DIR      Where playwright is installed (default /tmp/screenshot-bug-hunt-pw)
  --targets FILE     JSON array overriding sitemap auto-discovery
  --only TAG         Only capture one viewport (desktop|tablet|narrow|mobile|detail)
  --sitemap PATH     Sitemap path (default /sitemap-index.xml)

Targets file format:
  [
    { "slug": "00-home", "path": "/" },
    { "slug": "01-mid",  "path": "/docs/foo", "scroll": 700 }
  ]
`);
}

// ---------- sitemap discovery ----------

async function discoverFromSitemap(base, sitemapPath) {
  const indexUrl = base + sitemapPath;
  const baseUrl = new URL(base);
  const res = await fetch(indexUrl);
  if (!res.ok) {
    throw new Error(
      `sitemap fetch failed at ${indexUrl} (status ${res.status}). ` +
        `Pass a --targets file or check the dev server is running.`,
    );
  }
  const xml = await res.text();
  // Naive XML scrape — robust enough for sitemap-index.xml + sitemap.xml.
  // Handles <loc>...</loc> and follows nested sitemaps one level deep.
  const locs = [...xml.matchAll(/<loc>\s*([^<\s]+)\s*<\/loc>/g)].map(
    (m) => m[1],
  );
  const urls = [];
  for (const loc of locs) {
    // Astro's sitemap output uses the configured production `site` URL
    // (e.g. https://hippobrain.org/sitemap-0.xml), but we're hitting a local
    // preview. Rewrite any non-base host to point at our base before fetching
    // sub-sitemaps so DNS doesn't blow up.
    const localized = rewriteHost(loc, baseUrl);
    if (localized.endsWith(".xml")) {
      const sub = await fetch(localized).then((r) => (r.ok ? r.text() : ""));
      for (const m of sub.matchAll(/<loc>\s*([^<\s]+)\s*<\/loc>/g)) {
        // Rewrite each URL inside the sub-sitemap — they'll be production
        // hosts too. Without this the dedup pass filters every URL as
        // foreign-origin and we end up with zero targets.
        urls.push(rewriteHost(m[1], baseUrl));
      }
    } else {
      urls.push(localized);
    }
  }
  // Stable order, dedup, strip the base so paths are relative.
  const paths = [
    ...new Set(
      urls
        .map((u) => {
          try {
            const url = new URL(u);
            if (url.origin !== baseUrl.origin) return null;
            // Normalize trailing slash so /, /foo/, and /foo all dedupe sensibly.
            return url.pathname.replace(/\/+$/, "") || "/";
          } catch {
            return null;
          }
        })
        .filter((p) => p !== null),
    ),
  ].sort();
  return paths.map((p, i) => ({
    slug: `${String(i).padStart(2, "0")}-${pathToSlug(p)}`,
    path: p,
  }));
}

function rewriteHost(absUrl, baseUrl) {
  try {
    const u = new URL(absUrl);
    if (u.origin === baseUrl.origin) return absUrl;
    // Replace scheme + host with the local base, preserve path/query/hash.
    return baseUrl.origin + u.pathname + u.search + u.hash;
  } catch {
    return absUrl;
  }
}

function pathToSlug(p) {
  if (p === "/") return "home";
  return p.replace(/^\/|\/$/g, "").replace(/\//g, "-").replace(/[^a-z0-9-]/gi, "_");
}

// ---------- main ----------

const args = parseArgs(process.argv);
const __dirname = dirname(fileURLToPath(import.meta.url));

mkdirSync(args.out, { recursive: true });
mkdirSync(resolve(args.out, "detail"), { recursive: true });

// Load playwright from the workdir, not the user's project.
const require = createRequire(`${args.workdir}/`);
let chromium;
try {
  ({ chromium } = require("playwright"));
} catch (err) {
  console.error(
    `Could not load playwright from ${args.workdir}.\n` +
      `Run scripts/setup.sh first (or pass --workdir pointing at an install).`,
  );
  process.exit(1);
}

let targets;
if (args.targets) {
  const json = await readFile(args.targets, "utf8");
  targets = JSON.parse(json);
} else {
  console.log(`Auto-discovering pages from ${args.base}${args.sitemapPath} …`);
  targets = await discoverFromSitemap(args.base, args.sitemapPath);
}

if (!targets.length) {
  console.error("no targets — did the sitemap return anything?");
  process.exit(1);
}

console.log(`Capturing ${targets.length} pages.`);

// Viewport list. The "detail" entry is viewport-only at 1440 — useful for
// reading screenshots at native pixel scale (full-page squashes detail).
const VIEWPORTS = [
  { tag: "desktop", width: 1440, height: 900, fullPage: true },
  { tag: "tablet", width: 1024, height: 900, fullPage: true },
  { tag: "narrow", width: 768, height: 900, fullPage: true },
  { tag: "mobile", width: 480, height: 900, fullPage: true },
  { tag: "detail", width: 1440, height: 900, fullPage: false },
].filter((v) => !args.only || args.only === v.tag);

const browser = await chromium.launch();
const ctx = await browser.newContext({ deviceScaleFactor: 1 });

let count = 0;
for (const vp of VIEWPORTS) {
  const page = await ctx.newPage();
  await page.setViewportSize({ width: vp.width, height: vp.height });

  for (const target of targets) {
    const dir = vp.tag === "detail" ? resolve(args.out, "detail") : args.out;
    const file = resolve(dir, `${vp.tag === "detail" ? "" : vp.tag + "-"}${target.slug}.png`);
    try {
      await page.goto(args.base + target.path, {
        waitUntil: "networkidle",
        timeout: 15000,
      });
      // Wait for fonts so heading typography renders correctly.
      await page.evaluate(() => document.fonts.ready);
      if (target.scroll) {
        await page.evaluate((y) => window.scrollTo(0, y), target.scroll);
        await page.waitForTimeout(150);
      }
      await page.screenshot({ path: file, fullPage: vp.fullPage });
      count++;
      console.log(`OK  ${vp.tag.padEnd(7)} ${target.path} -> ${file}`);
    } catch (err) {
      console.log(`ERR ${vp.tag.padEnd(7)} ${target.path}: ${err.message}`);
    }
  }
  await page.close();
}

await ctx.close();
await browser.close();
console.log(`\n${count} screenshots written to ${args.out}`);
