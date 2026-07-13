# WXT Guide

WXT is the prescribed framework for cross-browser extension development. Vite-based, TypeScript-first, handles manifest generation and cross-browser targeting automatically.

**Current version:** 0.20.x (release candidate for v1.0)

## Scaffolding

```bash
npx wxt@latest init       # npm
pnpm dlx wxt@latest init  # pnpm
bunx wxt@latest init      # bun
```

Interactive prompts let you choose a UI framework template (Vanilla/React/Vue/Svelte/Solid).

## Project Structure

```
my-extension/
  entrypoints/           # All extension entrypoints (file-based routing)
    background.ts        # Background service worker / event page
    popup.html           # Or popup/index.html for multi-file popup
    options.html         # Options page
    content.ts           # Content script (or content/index.ts)
    *.content.ts         # Named content scripts (e.g., overlay.content.ts)
    sidepanel.html       # Side panel
  assets/                # CSS, images processed by Vite
  components/            # Auto-imported UI components
  utils/                 # Auto-imported utility functions
  public/                # Static files copied as-is to output
  wxt.config.ts          # Project configuration
  .wxt/                  # Generated directory (types, tsconfig)
  .output/               # Build output
```

Directories are customizable in `wxt.config.ts`:

```typescript
export default defineConfig({
  srcDir: 'src',              // default: "."
  entrypointsDir: 'entries',  // default: "entrypoints"
  outDir: 'dist',             // default: ".output"
});
```

## Entrypoints System

WXT auto-generates the manifest from your entrypoint files. No manual `manifest.json` needed.

### Background

```typescript
// entrypoints/background.ts
export default defineBackground({
  type: 'module',  // Enables ESM + code-splitting (MV3)
  main() {
    console.log('Background loaded');
    browser.runtime.onMessage.addListener((msg, sender, sendResponse) => {
      // handle messages
    });
  },
});
```

### Content Scripts

```typescript
// entrypoints/github-pr.content.ts
export default defineContentScript({
  matches: ['https://github.com/*/pull/*'],
  runAt: 'document_idle',
  world: 'ISOLATED',           // default; use 'MAIN' only when needed
  cssInjectionMode: 'ui',      // 'manifest' | 'manual' | 'ui'

  main(ctx: ContentScriptContext) {
    console.log('Content script loaded on', window.location.href);
    // ctx provides lifecycle helpers (onInvalidated, etc.)
  },
});
```

### HTML Entrypoints

For popup, options, sidebar — use HTML files or directories:

```
entrypoints/popup/index.html   # Multi-file popup
entrypoints/popup/main.ts
entrypoints/popup/style.css
```

Or a single `entrypoints/popup.html` for simple popups.

### Browser targeting per entrypoint

```typescript
export default defineContentScript({
  matches: ['https://example.com/*'],
  include: ['chrome', 'firefox'],  // Only these browsers
  exclude: ['safari'],             // Never Safari
  main(ctx) { /* ... */ },
});
```

## Configuration

```typescript
// wxt.config.ts
import { defineConfig } from 'wxt';

export default defineConfig({
  // UI framework module
  modules: ['@wxt-dev/module-react'],

  // Manifest fields (merged into auto-generated manifest)
  manifest: {
    name: 'My Extension',
    description: 'Does things',
    permissions: ['storage', 'activeTab'],
    host_permissions: ['https://api.example.com/*'],

    // Firefox requires this for MV3
    browser_specific_settings: {
      gecko: {
        id: 'my-extension@example.com',
        strict_min_version: '109.0',
      },
    },
  },

  // Vite config overrides
  vite: () => ({
    // Standard Vite config
  }),

  // Dev browser startup
  webExt: {
    startUrls: ['https://example.com'],
  },
});
```

## Development Workflow

```bash
wxt                    # Dev server (Chrome MV3 by default)
wxt -b firefox         # Dev for Firefox
wxt -b safari          # Dev for Safari
wxt -b firefox --mv2   # Dev for Firefox MV2
```

### HMR behavior

| Change Type | Behavior |
|------------|---------|
| HTML pages (popup, options) | Full HMR — instant update |
| Content script UI (shadow DOM via `createContentScriptUi`) | HMR inside iframe |
| Content script logic | Per-tab reload (no full extension reload) |
| Background script | Full extension reload (unavoidable) |
| Manifest changes (permissions, matches) | Full extension reload |
| `public/` assets | Full extension reload |

### Debugging

Each execution context has its own devtools console:
- **Background:** `chrome://extensions` -> click "Inspect views: service worker"
- **Popup:** Right-click popup -> "Inspect"
- **Content script:** Regular page devtools -> Console (select extension context from dropdown)

## Building

```bash
wxt build                # Production build (Chrome MV3)
wxt build -b firefox     # Firefox build
wxt build -b safari      # Safari build
wxt build --analyze      # Bundle visualization

wxt zip                  # Build + zip for Chrome Web Store
wxt zip -b firefox       # Build + zip for Firefox AMO
wxt zip --sources        # Create sources zip (required for Firefox AMO)
```

Output directory template: `{{browser}}-mv{{manifestVersion}}` (e.g., `chrome-mv3/`, `firefox-mv3/`)

### Recommended package.json scripts

```json
{
  "scripts": {
    "dev": "wxt",
    "dev:firefox": "wxt -b firefox",
    "build": "wxt build",
    "build:firefox": "wxt build -b firefox",
    "zip": "wxt zip",
    "zip:firefox": "wxt zip -b firefox",
    "postinstall": "wxt prepare"
  }
}
```

## WXT Modules and APIs

### Imports: use `#imports`

As of WXT v0.20, all WXT APIs are available through the `#imports` virtual module:

```typescript
import { storage, defineContentScript, browser } from '#imports';
```

Or just use auto-imports (no import statement needed) — WXT auto-imports from `utils/`, `components/`, `hooks/`, and its own APIs.

**Do NOT use the old import paths** (`wxt/storage`, `wxt/client`, `wxt/sandbox`). These are deprecated since v0.20.

### Storage module

```typescript
import { storage } from '#imports';

const counter = storage.defineItem<number>('local:counter', {
  defaultValue: 0,
});

await counter.getValue();       // number (never null, has default)
await counter.setValue(42);
await counter.watch((newVal) => console.log('Counter:', newVal));
```

Storage keys are prefixed with their area: `local:`, `sync:`, `session:`.

### Environment variables

WXT provides build-time environment variables for browser detection:

```typescript
if (import.meta.env.FIREFOX) {
  // Firefox-specific code
}
if (import.meta.env.SAFARI) {
  // Safari-specific code
}
// Also: import.meta.env.CHROME, .EDGE, .OPERA
// import.meta.env.BROWSER — 'chrome' | 'firefox' | 'safari' | etc.
// import.meta.env.MANIFEST_VERSION — 2 | 3
```

**Use these instead of runtime browser detection** (user-agent sniffing, API feature detection). They're resolved at build time, so dead code is eliminated.

### Auto-imports

WXT auto-imports from these directories (no explicit `import` needed):
- `components/`
- `composables/` (Vue convention)
- `hooks/` (React/Solid convention)
- `utils/`

## Testing

### Vitest + fake-browser

```typescript
import { describe, it, expect, beforeEach } from 'vitest';
import { fakeBrowser } from 'wxt/testing/fake-browser';

describe('storage feature', () => {
  beforeEach(() => {
    fakeBrowser.reset(); // Reset all state between tests
  });

  it('reads from storage', async () => {
    const item = storage.defineItem<string>('local:greeting');
    await item.setValue('hello');
    expect(await item.getValue()).toBe('hello');
  });
});
```

`fakeBrowser` provides an in-memory implementation of `browser.storage`, `browser.runtime`, and other extension APIs. Tests run in Node — no browser needed.

## v0.20 Breaking Changes (RC for v1.0)

If you encounter code or examples using pre-v0.20 patterns, here's what changed:

1. **`webextension-polyfill` removed.** WXT's `browser` object now uses its own lightweight wrapper over `chrome.*` APIs. Types are based on `@types/chrome`, not `@types/webextension-polyfill`.

2. **Import paths restructured.** Use `#imports` instead of `wxt/storage`, `wxt/client`, `wxt/sandbox`.

3. **Default loader changed to `vite-node`** (was `jiti`).

4. **CSS reset in content script UIs.** WXT now sets `all: initial` inside shadow roots. Content script UIs that relied on inheriting page styles may look different.

5. **`extensionApi` config removed.** The non-polyfill browser API is now the only behavior.

6. **`zip.ignoredSources` renamed to `zip.excludeSources`.**

### Upgrade checklist

1. Update `wxt` to `^0.20.0`
2. Replace imports from `wxt/storage`, `wxt/client`, `wxt/sandbox` with `#imports`
3. Run `wxt prepare` to regenerate TypeScript declarations
4. Fix type issues from the `@types/chrome` migration
5. Test content script UIs for style reset issues
