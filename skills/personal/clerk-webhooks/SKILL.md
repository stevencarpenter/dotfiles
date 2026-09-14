---
name: clerk-webhooks
description: Implement or debug Clerk webhook handlers for user, organization, session, and billing events, including signature verification and reliable data synchronization.
allowed-tools: WebFetch
license: MIT
metadata:
  author: clerk
  version: 1.2.0
compatibility: Requires CLERK_WEBHOOK_SIGNING_SECRET (svix signing secret from Clerk dashboard)
---

# Clerk Webhooks

Read the existing endpoint, middleware, database schema, and installed Clerk SDK version. Preserve the route and application conventions. Add only the events and side effects the task requests.

Webhooks are eventually consistent and can arrive more than once or out of order. Use a session token or Backend API call when a synchronous request needs current Clerk data. See [delivery behavior](https://clerk.com/docs/guides/development/webhooks/overview) and [data synchronization](https://clerk.com/docs/guides/development/webhooks/syncing).

## Handler requirements

1. Verify the original request with the framework SDK's `verifyWebhook` adapter before using its payload. Keep the signing secret server-side. Verification also applies to notification-only handlers.
2. Exempt the webhook endpoint from interactive authentication middleware without making unrelated routes public. Signature verification authenticates webhook requests.
3. Narrow the `WebhookEvent` union by `evt.type` before reading event-specific fields. Use the installed SDK types and current event documentation.
4. Make requested writes tolerate retries. Use existing unique constraints, upserts, transactions, or event deduplication keyed by `svix-id`. Prevent stale events from overwriting newer state when ordering matters.
5. Return success after processing succeeds or a durable queue accepts the event. Let processing failures trigger retry; do not acknowledge work that exists only in a detached promise.

## Payload mapping

| Requested behavior | Fields and handling |
|---|---|
| Synchronize users | Map Clerk `id` to the application's Clerk ID field. Select the email whose `id` matches `primary_email_address_id`; handle absent email. Handle the requested create, update, and delete events. |
| Synchronize organizations | Use organization `id`, `name`, and `slug` as required by the existing schema. |
| Synchronize memberships | Use `organization.id`, `public_user_data.user_id`, and `role`. Deduplicate the organization/user pair and tolerate repeated deletion. |
| Send notifications | Reuse the installed email or messaging client. Escape untrusted data in rendered content and deduplicate the notification independently of unrelated database writes. |

Implement these operations against the actual schema. Do not invent a database client or add email and Slack integrations to a data-sync request.

## Framework selection

Use [framework adapter guidance](references/frameworks.md) for Express, Astro, Fastify, Nuxt, React Router, or TanStack Start. For Next.js, use the installed SDK's `@clerk/nextjs/webhooks` export and the existing App Router route conventions. The [Clerk verification reference](https://clerk.com/docs/reference/backend/verify-webhook) describes verification inputs and errors.

## Verification

Run the affected handler tests. Cover rejection before side effects for an invalid signature, the requested event mapping, repeated delivery, and failure before acknowledgement. Use the existing test runner and storage fixtures.

For local end-to-end delivery, use a development Clerk instance and a tunnel only when that workflow is requested. Changing a live endpoint, publishing a tunnel, or sending test notifications requires authorization for that action; generating handler code does not imply it.
