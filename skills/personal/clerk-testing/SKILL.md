---
name: clerk-testing
description: E2E authentication tests for Clerk applications using Playwright or Cypress.
allowed-tools: WebFetch
license: MIT
metadata:
  author: clerk
  version: 1.2.0
compatibility: Requires a configured Clerk development instance for the default test workflow
---

# Clerk Testing

Use the project's existing test runner and installed SDK versions. Read the matching official setup before changing authentication fixtures:

| Runner | Documentation |
|---|---|
| Overview | [Testing with Clerk](https://clerk.com/docs/guides/development/testing/overview) |
| Playwright | [Playwright setup](https://clerk.com/docs/guides/development/testing/playwright/overview) |
| Cypress | [Cypress setup](https://clerk.com/docs/guides/development/testing/cypress/overview) |

Use development-instance keys (`pk_test_*`, `sk_test_*`) and dedicated test users. Keep secret keys and saved authenticated browser state out of source control.

For Playwright, `clerkSetup()` obtains a Testing Token. Run it in a setup project declared as a dependency of the test projects so its environment reaches the workers. Call `setupClerkTestingToken({ page })` before navigating to Clerk authentication pages. A manually supplied `CLERK_TESTING_TOKEN` is an alternative, not a prerequisite.

Reuse authenticated state for tests that require a signed-in user. Exercise the actual sign-in UI when that flow is what the test covers. Give tests independent browser contexts and isolate users or records that they mutate.

Run the affected authentication test and check its visible outcome. Follow the existing suite's fixture and cleanup conventions rather than adding a second test harness.
