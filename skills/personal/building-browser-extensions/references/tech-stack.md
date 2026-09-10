# Extension tooling

Preserve the project's framework, package manager, and checks. Add a dependency only when it removes work needed by the extension's current behavior.

## UI

Use native DOM code for a small popup or content script. Reuse an existing UI framework for forms or component-heavy pages. Content scripts run on matched pages, so measure their bundle impact before adding a framework solely for injected UI.

In a WXT project, use the module matching the chosen UI framework. Follow the installed WXT version's configuration; do not install every framework module.

## Messaging and storage

A discriminated TypeScript message type and native `runtime.sendMessage` can cover a small protocol. Validate messages at the receiver regardless of static typing.

`@webext-core/messaging` is an option when an existing WXT project needs shared protocol typing across many handlers. `@webext-core/proxy-service` is an option for an actual background RPC requirement. Neither belongs in every extension.

Reuse WXT storage items if the project already uses them. Native `browser.storage` remains valid. Preserve access restrictions, migration behavior, and recovery after background worker termination.

## Testing

Use the existing runner. For a WXT project using Vitest, `wxt/testing/fake-browser` supports isolated browser API tests; reset its state between tests.

Check the behavior affected by the change:

- Message validation, responses, and error propagation.
- Persisted settings and schema migrations.
- State recovery after worker restart.
- Content-script DOM behavior.

For integration checks, load the built extension in a supported browser and exercise the requested flow. Use the project's existing Playwright setup when available. Check current extension-loading support for its browser build instead of assuming all headless or branded browser variants work.

## Other dependencies

Use `textContent` for untrusted text. If rich untrusted HTML is required, use a maintained sanitizer such as DOMPurify or the project's existing equivalent. Do not write an ad hoc sanitizer.

Add internationalization or icon-generation tooling only when the extension needs those capabilities. Reuse existing linting and formatting configuration.

## Builds

In WXT projects, preserve the generated type setup, including `wxt prepare` where the project uses it. Build only the requested browser targets and verify the resulting manifests. Extend the current CI workflow instead of copying a second lint/test/build pipeline.
