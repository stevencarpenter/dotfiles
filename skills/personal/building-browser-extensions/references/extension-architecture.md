# Extension Architecture

This is the domain knowledge you need. Browser extensions have a unique execution model unlike web apps or servers.

## Execution Contexts

A browser extension runs code in **four isolated contexts**. They cannot share memory or call each other's functions directly — they communicate only via message passing.

| Context | API Access | DOM Access | Lifetime | Trust Level |
|---------|-----------|-----------|----------|-------------|
| **Background (service worker)** | Full extension APIs | None (no DOM in Chrome) | Short-lived, terminated when idle | Highest |
| **Extension pages** (popup, sidebar, options) | Full extension APIs | Own HTML only | Destroyed when closed | High |
| **Content scripts** | Limited (`runtime`, `storage`, `i18n`) | Host page DOM (isolated world) | Per-page | Low (hostile environment) |
| **Injected scripts** (main world) | None | Full page JS context | Per-page | Untrusted |

### Key mental model

Think of these as **separate processes** that happen to be part of the same extension:

- **Background service worker** is your "server." It handles API calls, state, and coordination. It has NO DOM — no `document`, no `DOMParser`, no `XMLHttpRequest`. Use `fetch()` instead. In Chrome, it's a service worker. In Firefox, it's a non-persistent event page (which does have DOM access, but **do not use DOM APIs in background code** or it will break in Chrome).

- **Content scripts** are injected into web pages. They share the page's DOM but run in an **isolated world** — separate JS globals from the page. They can read/modify DOM elements but cannot access the page's JavaScript variables. Treat all DOM data as **attacker-controlled**.

- **Extension pages** (popup, sidebar, options) are your extension's own UI. They have full API access but are **destroyed when closed** — don't store state in their JS globals.

- **Injected scripts** (main world) run in the page's actual JS context. They have zero extension API access. Use only when you must interact with page-level JS variables. Specify via `world: "MAIN"` in `scripting.executeScript` or `defineContentScript`.

## Message Passing

Since contexts can't share memory, use message passing:

### One-shot messages

```typescript
// Content script -> Background
const response = await browser.runtime.sendMessage({
  type: 'FETCH_DATA',
  payload: { url: 'https://api.example.com/data' }
});

// Background listener
browser.runtime.onMessage.addListener((message, sender, sendResponse) => {
  if (message.type === 'FETCH_DATA') {
    fetch(message.payload.url)
      .then(r => r.json())
      .then(data => sendResponse({ data }))
      .catch(err => sendResponse({ error: err.message }));
    return true; // CRITICAL: keeps message channel open for async response
  }
});
```

**The `return true` trap:** If your handler is async, you MUST return `true` synchronously from the listener to keep the message channel open. Forgetting this causes `sendResponse` to silently fail. Use `@webext-core/messaging` (see tech-stack.md) to avoid this entirely.

### Long-lived connections

```typescript
// For streaming or ongoing communication
const port = browser.runtime.connect({ name: 'sidebar' });
port.postMessage({ type: 'SUBSCRIBE', topic: 'updates' });
port.onMessage.addListener((msg) => { /* handle */ });
port.onDisconnect.addListener(() => { /* cleanup */ });
```

### Anti-patterns

- **Sharing state directly** between contexts (e.g., global variables) — they're isolated, this doesn't work
- **Untyped message blobs** — use typed message protocols (see `@webext-core/messaging` in tech-stack.md)
- **Missing sender validation** on message handlers — content scripts run in hostile environments, always validate `sender.url` and `sender.tab` before acting on messages

## Storage

Extension storage is async, shared across all contexts, and persists across browser restarts.

| Area | Persistence | Size Limit (Chrome) | Use Case |
|------|------------|-------------------|----------|
| `storage.local` | Permanent | 10 MB (unlimited with permission) | Main data store, cached results |
| `storage.sync` | Synced across devices via browser account | ~100 KB total, 8 KB/item | User preferences |
| `storage.session` | In-memory, cleared on browser close | ~10 MB | Ephemeral sensitive data (tokens, session state) |

### WXT's typed storage

WXT provides a typed wrapper. Use it instead of raw `browser.storage`:

```typescript
import { storage } from '#imports';

// Define a typed storage item with a default
const apiKey = storage.defineItem<string>('local:apiKey');
const settings = storage.defineItem<Settings>('sync:settings', {
  defaultValue: { theme: 'dark', language: 'en' }
});

// Usage
await apiKey.getValue();        // string | null
await settings.getValue();      // Settings (never null, has default)
await apiKey.setValue('sk-...');
await apiKey.watch((newVal) => { /* react to changes */ });
```

### Security considerations

- `storage.local` is **not encrypted on disk**. Anyone with physical access can read it. Don't store raw API keys in distributed extensions — use `storage.session` for ephemeral tokens.
- `storage.local` is accessible from content scripts by default. Restrict sensitive data with `chrome.storage.local.setAccessLevel('TRUSTED_CONTEXTS')` so only background/popup can read it.
- `storage.sync` transmits data through the browser vendor's cloud (Google/Mozilla). Never store PII or secrets there.

### Schema migration

When your storage schema changes between versions, handle migration in the `runtime.onInstalled` listener:

```typescript
browser.runtime.onInstalled.addListener(async (details) => {
  if (details.reason === 'update') {
    const data = await browser.storage.local.get('settings');
    if (data.settings && !data.settings.version) {
      // Migrate from v1 to v2 schema
      await browser.storage.local.set({
        settings: { ...data.settings, version: 2, newField: 'default' }
      });
    }
  }
});
```

## Permissions Model

The manifest declares what your extension CAN do. Think of it as a **security contract**.

### Required vs optional

```json
{
  "permissions": ["storage", "activeTab"],
  "optional_permissions": ["history", "bookmarks"],
  "host_permissions": ["https://specific-site.com/*"],
  "optional_host_permissions": ["https://*.example.com/*"]
}
```

- **Required permissions** are granted at install. Adding new ones in an update **disables the extension** until the user re-approves.
- **Optional permissions** are requested at runtime via `browser.permissions.request()`. No install warning, no update disruption.

### `activeTab` — use this by default

`activeTab` grants temporary access to the current tab ONLY when the user explicitly invokes the extension (clicks icon, keyboard shortcut, context menu). Access is revoked when the user navigates away. **No install warning.**

Prefer `activeTab` over broad host permissions (`<all_urls>`, `*://*/*`). Broad host permissions trigger scary install warnings and invite store rejection.

### Dangerous permissions

These enable powerful capabilities. Every one needs justification:

| Permission | Risk | Justification needed |
|-----------|------|---------------------|
| `<all_urls>` / `*://*/*` | Read/modify all web content | Why can't you scope to specific hosts? |
| `webRequest` / `declarativeNetRequest` | Intercept all network requests | Why do you need to see/modify traffic? |
| `cookies` | Read/write cookies for any host you have access to | Session hijacking risk |
| `debugger` | Full Chrome DevTools Protocol access | Essentially root access to tabs |
| `tabs` | See URL/title of ALL open tabs | Browsing history surveillance |
| `management` | Enable/disable/uninstall other extensions | |
| `nativeMessaging` | Communicate with native apps | Escape from browser sandbox |

### Content script injection

Two approaches:

- **Declarative** (manifest): runs automatically on matching pages. Use when you always need the script on those pages.
- **Programmatic** (`scripting.executeScript`): runs on demand. Use with `activeTab` for user-triggered actions. Requires the `scripting` permission.

## Service Worker Lifecycle (MV3)

**The service worker can be terminated at any time when idle.** This is the #1 surprise for backend devs.

- Chrome terminates after ~30 seconds of inactivity
- It restarts when an event fires (message received, alarm triggered, etc.)
- **All global variable state is lost** on termination

### Consequences

1. **Never store state in global variables.** Use `storage.session` or `storage.local`.
2. **Long-running operations can be killed mid-execution.** Use `chrome.alarms` for deferred work, or keep-alive techniques for operations that must complete.
3. **Event listeners must be registered at the top level** of the service worker, not inside async callbacks or conditional blocks. The browser needs to know what events your worker handles before it terminates.

```typescript
// CORRECT: top-level registration
browser.runtime.onMessage.addListener(handler);
browser.alarms.onAlarm.addListener(alarmHandler);

// WRONG: conditional registration (listener may not exist on restart)
async function setup() {
  const settings = await storage.get('settings');
  if (settings.enableFeature) {
    browser.runtime.onMessage.addListener(handler); // May be lost!
  }
}
```

### The "woke up with no state" pattern

```typescript
// Background service worker
let cachedData: Data | null = null;

async function getData(): Promise<Data> {
  // Check memory cache first (fast path when worker is alive)
  if (cachedData) return cachedData;

  // Worker was terminated — restore from storage
  const stored = await browser.storage.session.get('cachedData');
  if (stored.cachedData) {
    cachedData = stored.cachedData;
    return cachedData;
  }

  // Nothing cached — fetch fresh
  cachedData = await fetchFreshData();
  await browser.storage.session.set({ cachedData });
  return cachedData;
}
```
