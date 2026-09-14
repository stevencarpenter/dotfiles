# Framework adapters

Use the adapter exported by the installed Clerk framework SDK. Check its request type and supported version against the [Clerk data-sync guide](https://clerk.com/docs/guides/development/webhooks/syncing) before copying a handler. Keep signature verification separate from application processing errors.

| Framework | Adapter import | Integration constraint |
|---|---|---|
| Express | `@clerk/express/webhooks` | Use `express.raw({ type: 'application/json' })` on the webhook route before any JSON body parser consumes the request. Preserve the existing endpoint path. |
| Astro | `@clerk/astro/webhooks` | Pass the route's `request`; provide `signingSecret` from server-only `import.meta.env` when required by the SDK. |
| Fastify | `@clerk/fastify/webhooks` | Follow the installed adapter's raw-body and request requirements. |
| Nuxt | `@clerk/nuxt/webhooks` | Pass the H3 event and configure the signing secret through the application's server runtime configuration. |
| React Router | `@clerk/react-router/webhooks` | Handle POST in the route action and register it in the existing route configuration. |
| TanStack Start | `@clerk/tanstack-react-start/webhooks` | Use the server-route API supported by the installed TanStack Start version. |

Exclude only the webhook route from interactive authentication. Verify its signature with `CLERK_WEBHOOK_SIGNING_SECRET` or the SDK's explicit server-side signing-secret option.

When a development tunnel is authorized, allow its actual hostname if the development server rejects it. Do not copy a sample hostname or disable host checks globally.
