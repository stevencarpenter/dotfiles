# Codebase Review Checklist

Checks for reviewing an existing browser extension. Select those relevant to the requested scope and target browsers. Each group links to detailed guidance.

## Phase 1: Architecture Assessment

### Execution context mapping

- [ ] **Identify all execution contexts.** What code runs as background, content script, extension page, or injected main-world script?
- [ ] **Is logic in the right context?** Network requests and API calls should be in the background, not content scripts. DOM manipulation should be in content scripts, not background. Heavy computation should not be in content scripts (they run on every matched page).
- [ ] **Content script weight.** Are content scripts minimal? They execute on every matched page: bloated content scripts cause visible page slowdowns. Move business logic to the background.

### Message passing

- [ ] **Typed protocols?** Are messages structured with discriminants and checked payloads? Reuse the existing protocol; a messaging dependency is optional.
- [ ] **Async response handling.** Do callback-based `onMessage` listeners keep the response channel open? Check Promise listener support against the target browser versions.
- [ ] **Error propagation.** Are errors in async handlers caught and sent back via `sendResponse`? Uncaught rejections silently drop the response.

### State management

- [ ] **Where does state live?** Global variables in background are lost on service worker termination. State must be in `storage.local`, `storage.session`, or `storage.sync`.
- [ ] **Service worker restart resilience.** Does the background gracefully handle waking up with no in-memory state? (See "woke up with no state" pattern in extension-architecture.md)
- [ ] **Event listener registration.** Are all event listeners registered at the top level of the background script? Conditional or deferred registration means listeners may not exist after worker restart.

### Manifest

- [ ] **Permissions match usage.** Every declared permission must be used in the code. Every API call that requires a permission must have that permission declared.
- [ ] **No unused permissions.** Unused permissions invite store rejection and increase attack surface.
- [ ] **Version and metadata.** Name, description, version follow store requirements.

## Phase 2: Security Audit

Walk through each section of **security-review.md** against the codebase:

- [ ] **Permissions audit.** Apply the "justify every permission" test. Flag broad host permissions, `tabs`, `debugger`, and other dangerous permissions. Check for optional permissions that should replace required ones.
- [ ] **CSP compliance.** No remote code loading, no dynamic code execution from strings, no inline scripts. Check that `content_security_policy` in manifest is restrictive.
- [ ] **Content script XSS.** Search for `innerHTML`, `outerHTML`, `insertAdjacentHTML` in content scripts. All must use sanitized or text-only content.
- [ ] **Sender validation.** Every `onMessage` and `onMessageExternal` handler must validate `sender`. Check for `postMessage` listeners without `event.origin` validation.
- [ ] **Storage access levels.** Where supported, restrict sensitive `storage.local` data with `setAccessLevel({ accessLevel: 'TRUSTED_CONTEXTS' })`. Prefer `storage.session` for ephemeral secrets. Nothing sensitive in `storage.sync`.
- [ ] **Data flow.** Trace data from content script to background. Is untrusted data validated at the boundary? Are there paths where page-controlled data reaches sensitive operations?

## Phase 3: Cross-Browser Readiness

Walk through **cross-browser-compat.md** known issues:

- [ ] **Background context.** Any DOM API usage (`document`, `DOMParser`, `XMLHttpRequest`, `Image`) in background code? This breaks Chrome. Use `fetch()`, `TextEncoder`/`TextDecoder`, etc.
- [ ] **Manifest compatibility.** Does manifest include both `service_worker` and `scripts` for cross-browser? Is `browser_specific_settings.gecko` present for Firefox?
- [ ] **Browser-specific APIs.** Any `chrome.sidePanel`, `chrome.offscreen`, or other browser-specific APIs used without fallbacks? Check cross-browser-compat.md API gaps table.
- [ ] **Namespace usage.** Are APIs supported by the declared browsers? Native `chrome.*` is valid for a Chromium-only extension; add wrappers or a polyfill only for an actual compatibility gap.
- [ ] **Build outputs.** Does `wxt build -b firefox` and `wxt build -b safari` succeed? Or if not using WXT, are there separate manifests per browser?
- [ ] **Safari silent failures.** Has the extension been tested in Safari? Unsupported APIs fail silently: functionality may appear to work but actually do nothing.

## Phase 4: Store Readiness (When Applicable)

- [ ] **Permission justification.** Can you write one sentence explaining why each permission is needed? If not, the permission should be removed or made optional.
- [ ] **Privacy policy.** Present and hosted at a stable URL if the extension handles any user data.
- [ ] **Data use disclosures.** Chrome requires explicit declaration of data types collected and how they're used.
- [ ] **Source code reproducibility.** For Firefox AMO: can a reviewer run your build and get identical output? Are build instructions documented?
- [ ] **No obfuscation.** Only standard minification. No control flow obfuscation, no deliberate name mangling beyond what standard bundlers do.
- [ ] **Single-purpose compliance.** Does the extension do one clear thing? Bundled unrelated features trigger rejection.
- [ ] **Safari privacy declarations.** Check current requirements for the target distribution route, SDKs, and required-reason APIs.

## Review Output Format

Report verified findings with affected behavior and source locations. Include browser status only for targeted browsers and distinguish tested from untested. Omit empty categories. For a broad review, an example format is:

```markdown
## Extension Review: [name]

### Critical (must fix before ship)
- [issue]: [description]: [which phase/check]

### High (should fix)
- [issue]: [description]: [which phase/check]

### Medium (recommended)
- [issue]: [description]: [which phase/check]

### Architecture Notes
- [observations about structure, patterns, technical debt]

### Cross-Browser Status
- Chrome: [pass/fail/untested]
- Firefox: [pass/fail/untested]
- Safari: [pass/fail/untested]
```
