---
name: clerk
description: Route Clerk authentication, organization, billing, webhook, and testing work to the relevant Clerk guidance. Use when Clerk is requested or already used by the affected application.
license: MIT
metadata:
  version: 2.0.0
---

# Clerk Skills Router

Use the application's installed Clerk SDK and framework versions. Check its dependency manifest and lockfile before selecting an API example. If versions are unclear, inspect the package or current official documentation rather than assuming a major version. Do not replace another authentication provider unless the task includes that migration.

Load the relevant skill when it is available. If it is absent, use [Clerk documentation](https://clerk.com/docs) for the installed framework and SDK. The routing table does not imply that every skill is installed.

| Task | Skill |
|---|---|
| Install or migrate to Clerk | `clerk-setup` |
| Custom sign-in, sign-up, or component appearance | `clerk-custom-ui` |
| Next.js middleware, server actions, or route protection | `clerk-nextjs-patterns` |
| React hooks and protected routes | `clerk-react-patterns` |
| React Router loaders and actions | `clerk-react-router-patterns` |
| Vue composables and route guards | `clerk-vue-patterns` |
| Nuxt middleware and server APIs | `clerk-nuxt-patterns` |
| Astro SSR and islands | `clerk-astro-patterns` |
| TanStack Start server functions and route protection | `clerk-tanstack-patterns` |
| Expo secure storage and OAuth linking | `clerk-expo-patterns` |
| Chrome extension authentication | `clerk-chrome-extension-patterns` |
| Organizations, memberships, roles, and permissions | `clerk-orgs` |
| Clerk billing and entitlements | `clerk-billing` |
| Event delivery and data synchronization | `clerk-webhooks` |
| Playwright or Cypress authentication tests | `clerk-testing` |
| Native Swift and SwiftUI authentication | `clerk-swift` |
| Native Kotlin and Jetpack Compose authentication | `clerk-android` |
| Backend REST API requests | `clerk-backend-api` |
