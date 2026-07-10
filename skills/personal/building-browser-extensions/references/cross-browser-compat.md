# Cross-Browser Compatibility

The "works in Chrome, breaks elsewhere" tribal knowledge. As of April 2026.

## MV3 Status Per Browser

| Browser | MV2 | MV3 | Background Model |
|---------|-----|-----|-----------------|
| **Chrome** | Dead (fully sunset, code being removed) | Required | Service worker (no DOM) |
| **Firefox** | Still supported (12-month deprecation notice promised) | Fully available | Event page (has DOM, NOT a service worker) |
| **Safari** | Legacy | Supported since 15.4 | Both; uses `preferred_environment` key |

## The Biggest Cross-Browser Headache: Background Context

Chrome and Firefox made opposite architectural choices for MV3 background scripts:

- **Chrome:** Service worker. No DOM. No `document`, `DOMParser`, `XMLHttpRequest`, `Image`. Worker terminates when idle.
- **Firefox:** Non-persistent event page. HAS DOM access. Does NOT support service workers. Silently ignores `service_worker` in manifest (Firefox 121+).
- **Safari:** Supports both. Uses `preferred_environment` manifest key to choose. Defaults to event page unless you specify service worker.

### Cross-browser manifest pattern

Specify both — each browser reads what it understands and ignores the rest:

```json
{
  "background": {
    "service_worker": "background.js",
    "scripts": ["background.js"],
    "type": "module",
    "preferred_environment": "service_worker"
  }
}
```

- Chrome uses `service_worker`, silently ignores `scripts` (Chrome 121+)
- Firefox uses `scripts`, silently ignores `service_worker` (Firefox 121+)
- Safari uses whichever `preferred_environment` indicates

**WXT handles this automatically.** You write one `entrypoints/background.ts` and WXT generates the correct manifest per browser.

### The golden rule

**Never use DOM APIs in background code.** Even though Firefox's event page has DOM access, using it means your extension breaks in Chrome. Write background code as if you're in a service worker: `fetch()` instead of `XMLHttpRequest`, `TextEncoder`/`TextDecoder` instead of `DOMParser`, no `document` access.

If you absolutely need DOM manipulation in the background, Chrome provides the `chrome.offscreen` API — but it's Chrome-only. There is no equivalent in Firefox or Safari. Avoid this architectural dependency.

## Namespace: `chrome.*` vs `browser.*`

| Browser | `chrome.*` | `browser.*` | Promises |
|---------|-----------|-------------|---------|
| Chrome (M136+, April 2025) | Primary | Available as alias | Native on both |
| Firefox | Compat shim | Primary (native) | Native |
| Safari | Compat shim | Primary (native) | Native |

**WXT abstracts this.** Use `browser` from `#imports` — WXT's lightweight wrapper handles the differences. The `webextension-polyfill` package is effectively inactive (no releases in 2+ years) and WXT dropped it in v0.20.

**Use WXT's build-time environment variables** for browser-specific code instead of runtime detection:

```typescript
if (import.meta.env.FIREFOX) {
  // Firefox-specific path
}
if (import.meta.env.CHROME) {
  // Chrome-specific path
}
```

## API Availability Gaps

APIs that exist in some browsers but not others:

| API | Chrome | Firefox | Safari | Alternative |
|-----|--------|---------|--------|-------------|
| `sidePanel` | Yes | No | No | Firefox has `sidebarAction`; Safari has neither |
| `sidebarAction` | No | Yes | No | Chrome has `sidePanel` |
| `offscreen` | Yes (109+) | No | No | No direct equivalent — restructure to avoid DOM in background |
| `notifications` | Yes | Yes | No | Must bridge to native app via `nativeMessaging` on Safari |
| `declarativeNetRequest` | Yes | Yes | Partial (buggy `getMatchedRules`) | |
| `webRequest` (blocking, MV3) | No | Yes | No | Firefox preserved blocking; Chrome/Safari use `declarativeNetRequest` only |

### Handling gaps

Use WXT's `include`/`exclude` on entrypoints for browser-specific features:

```typescript
// entrypoints/sidebar.content.ts
export default defineContentScript({
  include: ['chrome'],  // Only builds for Chrome (uses sidePanel API)
  matches: ['<all_urls>'],
  main() { /* Chrome sidePanel logic */ },
});

// entrypoints/sidebar-firefox.content.ts
export default defineContentScript({
  include: ['firefox'],  // Only builds for Firefox (uses sidebarAction API)
  matches: ['<all_urls>'],
  main() { /* Firefox sidebarAction logic */ },
});
```

## Safari-Specific

Safari is the most constrained browser for extensions.

### Distribution

- **Traditional:** Requires Xcode wrapper project, Apple Developer account ($99/year), App Store distribution
- **New (Sept 2025):** App Store Connect ZIP upload — upload extension ZIP directly, no Xcode or Mac needed for distribution. Still requires Apple Developer account.

Convert existing extension: `xcrun safari-web-extension-converter /path/to/extension --project-location ./safari`

### API Limitations

- **Silent failures.** The converter succeeds, but unsupported APIs just don't work at runtime — no errors, no warnings. This makes debugging painful.
- **Cannot modify sensitive headers** (`Origin`, `Host`) via `webRequest` or `declarativeNetRequest`.
- **No `notifications` API.** Must use native messaging bridge.
- **`declarativeNetRequest`** has reporting bugs — `getMatchedRules` returns incomplete results.
- Apple reverse-engineered Chromium's API independently — behavior is not identical even where API surface looks the same.

### Privacy manifest

Required since May 2024. The `PrivacyInfo.xcprivacy` file must declare:
- Types of data collected
- Required Reasons API usage (e.g., `UserDefaults`)
- Tracking domains

Apps without privacy manifests are rejected.

### User permissions

Safari lets users grant access for "one day", "always", or "on this website only." Extensions must function gracefully with partial permission grants — don't assume `<all_urls>` means universal access.

## Storage Quota Differences

| Area | Chrome | Firefox | Safari |
|------|--------|---------|--------|
| `storage.local` | 10 MB (unlimited with `unlimitedStorage` perm) | Variable (IndexedDB-based) | ~60% of disk |
| `storage.sync` | ~100 KB total, 8 KB/item | Same limits | Limited support |
| `storage.session` | ~10 MB | Supported | Limited documentation |

Firefox's `unlimitedStorage` can still hit quota errors when system disk space is low.

## Common "Works in Chrome, Breaks Elsewhere"

1. **DOM in background scripts** — works in Firefox (event page), breaks in Chrome (service worker). The #1 issue.
2. **`chrome.offscreen`** — Chrome-only. No equivalent in Firefox/Safari.
3. **`chrome.sidePanel`** — Chrome-only. Firefox has `sidebarAction` (completely different API).
4. **Blocking `webRequest` in MV3** — Firefox only. Chrome and Safari removed it.
5. **`notifications` API** — absent in Safari entirely.
6. **Header modification** — Safari blocks modifying `Origin` and `Host` headers.
7. **Silent Safari failures** — APIs that look like they should work just silently do nothing.
8. **Popup sizing** — Safari sizes popups differently than Chrome/Firefox. Test visual layout in all three.
9. **`storage.session`** — supported in Chrome and Firefox 115+, limited in Safari. Feature-detect before using.

### Feature detection pattern

```typescript
// Check for API existence before using
if (typeof browser.sidePanel !== 'undefined') {
  // Chrome sidePanel available
} else if (typeof browser.sidebarAction !== 'undefined') {
  // Firefox sidebarAction available
} else {
  // Neither — fall back to content script sidebar
}
```

Prefer WXT's `import.meta.env.BROWSER` build-time check when possible — it eliminates dead code.
