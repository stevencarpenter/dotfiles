# Tech Stack

Recommended dependencies and configuration for WXT-based browser extensions.

## UI Framework

Choose based on popup/options complexity:

| Complexity | Recommendation | When |
|-----------|---------------|------|
| Simple (few buttons, status text) | Vanilla TypeScript | Popup is mostly display with minimal interactivity |
| Moderate (forms, tabs, state) | Preact or Svelte | Need reactivity without React's bundle size |
| Complex (rich UI, many components) | React or Vue | Significant component composition, state management |

### WXT framework modules

Install the module for your chosen framework:

```bash
npm install @wxt-dev/module-react    # React
npm install @wxt-dev/module-vue      # Vue
npm install @wxt-dev/module-svelte   # Svelte
npm install @wxt-dev/module-solid    # Solid
```

Add to `wxt.config.ts`:

```typescript
export default defineConfig({
  modules: ['@wxt-dev/module-react'],
});
```

**Bundle size matters for extensions.** Content scripts load on every matched page. A React-based content script adds ~40KB gzipped to every page load. For content scripts specifically, prefer vanilla TypeScript or Preact unless you need significant UI complexity. Popup/options pages are less sensitive since they load on demand.

## Testing

### Unit testing: Vitest + fake-browser

WXT recommends Vitest. `wxt/testing/fake-browser` provides in-memory browser API mocks:

```typescript
import { describe, it, expect, beforeEach } from 'vitest';
import { fakeBrowser } from 'wxt/testing/fake-browser';
import { storage } from '#imports';

describe('settings', () => {
  beforeEach(() => {
    fakeBrowser.reset();
  });

  it('persists user preferences', async () => {
    const theme = storage.defineItem<string>('local:theme');
    await theme.setValue('dark');
    expect(await theme.getValue()).toBe('dark');
  });
});
```

### What to test

- **Message passing contracts.** Send typed messages, verify handlers respond correctly. Mock `fakeBrowser.runtime.onMessage` to test content script message sending.
- **Storage operations.** Read/write/migration logic using `fakeBrowser`.
- **Business logic.** Data transformation, parsing, validation — pure functions extracted from entrypoints.
- **Content script DOM logic.** Use jsdom or happy-dom (Vitest environments) for DOM manipulation tests.

### E2E testing: Playwright

Playwright can load unpacked extensions in Chromium:

```typescript
import { test, chromium } from '@playwright/test';
import path from 'path';

test('sidebar appears on PR page', async () => {
  const extPath = path.resolve('.output/chrome-mv3');
  const context = await chromium.launchPersistentContext('', {
    headless: false, // Extensions require headed mode
    args: [
      `--disable-extensions-except=${extPath}`,
      `--load-extension=${extPath}`,
    ],
  });

  const page = await context.newPage();
  await page.goto('https://github.com/owner/repo/pull/1');
  // Assert sidebar elements exist
  await context.close();
});
```

Note: E2E testing in Firefox/Safari is harder. `web-ext run` works for manual Firefox testing but isn't easily scriptable. Safari requires Xcode.

## Linting and Formatting

### ESLint

```bash
npm install -D eslint @typescript-eslint/eslint-plugin @typescript-eslint/parser
```

### Biome (lighter alternative)

```bash
npm install -D @biomejs/biome
```

Biome is faster and combines linting + formatting in one tool. Good choice for extensions where you don't need ESLint's plugin ecosystem.

## TypeScript Configuration

WXT generates a `.wxt/` directory with type declarations. Run `wxt prepare` after install (add to `postinstall` script):

```json
{
  "scripts": {
    "postinstall": "wxt prepare"
  }
}
```

The `#imports` virtual module provides types for all WXT APIs. Strict mode recommended:

```json
{
  "compilerOptions": {
    "strict": true
  }
}
```

## Recommended Libraries

### Message passing: `@webext-core/messaging`

Type-safe messaging between extension contexts. Same author as WXT.

```bash
npm install @webext-core/messaging
```

```typescript
// lib/messaging.ts — shared protocol definition
import { defineExtensionMessaging } from '@webext-core/messaging';

interface ProtocolMap {
  getStringLength(data: string): number;
  fetchData(url: string): { data: unknown };
}

export const { sendMessage, onMessage } = defineExtensionMessaging<ProtocolMap>();
```

```typescript
// entrypoints/background.ts — handler
import { onMessage } from '@/lib/messaging';

onMessage('getStringLength', ({ data }) => {
  return data.length; // Type-safe: data is string, return is number
});
```

```typescript
// entrypoints/content.ts — caller
import { sendMessage } from '@/lib/messaging';

const length = await sendMessage('getStringLength', 'hello');
// length is typed as number
```

Eliminates the `return true` / `sendResponse` footgun entirely.

### Background RPC: `@webext-core/proxy-service`

Call background functions from content scripts as if they were local:

```bash
npm install @webext-core/proxy-service
```

### Internationalization: `@wxt-dev/i18n`

```bash
npm install @wxt-dev/i18n
```

### Icon generation: `@wxt-dev/auto-icons`

Auto-generates all required icon sizes from a single source:

```bash
npm install @wxt-dev/auto-icons
```

### DOM sanitization: DOMPurify

**Required** if your content script renders any HTML from external sources:

```bash
npm install dompurify
npm install -D @types/dompurify
```

Use DOMPurify to sanitize any untrusted HTML before inserting it into the DOM. Prefer `textContent` when rich HTML is not needed.

## CI Configuration

GitHub Actions example:

```yaml
name: Extension CI
on:
  push:
    branches: [main]
  pull_request:

jobs:
  lint:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-node@v4
        with: { node-version: 20 }
      - run: npm ci
      - run: npm run lint

  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-node@v4
        with: { node-version: 20 }
      - run: npm ci
      - run: npm run test

  build:
    runs-on: ubuntu-latest
    strategy:
      matrix:
        browser: [chrome, firefox]
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-node@v4
        with: { node-version: 20 }
      - run: npm ci
      - run: wxt build -b ${{ matrix.browser }}
      - uses: actions/upload-artifact@v4
        with:
          name: extension-${{ matrix.browser }}
          path: .output/${{ matrix.browser }}-mv3/
```
