# Firefox Dashboard Tabs

A Firefox-only MV3 extension that opens each Grafana dashboard set as its own
**collapsed tab group** at browser startup.

- **Hippo OTel** (purple), 4 dashboards from `http://localhost:3030`
- **Homelab** (blue), 9 dashboards from `https://grafana.snugmarina.org`

## Why not WXT

The repo skill `building-browser-extensions` prescribes WXT plus TypeScript,
scoped to *cross-browser* extensions. This one cannot be cross-browser: it is
built on `tabGroups`, which Safari does not implement, and it is a personal
startup helper that will never be submitted to a store. WXT would add an npm
toolchain and a fourth CI lane to a repo whose CI is Nix, uv, and shell, in
exchange for a manifest this extension can state in 20 lines. Plain MV3 it is.

## Layout

```
firefox-dashboard-tabs/
  sources.json               # which repos to read, group titles, colors, base URLs
  generate.py                # sources.json + provisioned JSON → extension/dashboards.json
  extension/
    manifest.json
    background.js
    dashboards.json          # GENERATED, do not hand-edit
```

## Regenerating the tab list

Both Grafana instances provision dashboards from JSON checked into their own
repositories, so the tab list is derived rather than hand-maintained:

| Group | Source directory |
| --- | --- |
| Hippo OTel | `~/projects/hippo/otel/grafana/dashboards/` |
| Homelab | `~/projects/homelab/services/observability/grafana-dashboards/` |

```bash
just dashboard-tabs      # → firefox-dashboard-tabs/extension/dashboards.json
```

Add a dashboard to either repo, re-run, and reload the extension. Generation
fails without replacing the previous manifest if any configured source is
missing, unreadable, malformed, or contains duplicate UIDs. Keep both source
repositories checked out on the machine where the manifest is regenerated.

URLs are emitted as `/d/<uid>` with no slug. Grafana redirects to the canonical
slugged URL, so a renamed dashboard keeps working without regeneration.

## Installing

Firefox Developer Edition (and only Developer Edition, Nightly, or ESR) can run
an unsigned extension:

1. `about:config` → set `xpinstall.signatures.required` to `false`.
2. `about:debugging#/runtime/this-firefox` → **Load Temporary Add-on** →
   pick `extension/manifest.json`.

A temporary add-on is dropped on every restart, which defeats an
`onStartup` listener. For a permanent install, zip the `extension/` directory
and submit it to AMO as an **unlisted** add-on to get a signed XPI, then
install that. Until then, use the toolbar button.

## Behavior notes

- **Tabs open discarded.** `tabs.create({discarded: true})` builds the tab
  without fetching. Startup stays instant at any dashboard count, and hippo's
  dashboards show placeholders rather than connection errors when the OTel
  stack is down. Firefox only honors a caller-supplied tab `title` on a
  discarded tab, which is why every tab carries its dashboard name.
- **Re-running reconciles.** The extension owns tabs with extension-private
  markers and normalized dashboard URLs, not by title alone. It adds newly
  configured dashboards, removes stale dashboard tabs, and leaves unrelated
  same-titled groups alone.
- **Startup waits for restore stability.** `runtime.onStartup` schedules
  repeated one-shot Firefox alarms about 2.5 seconds apart. The event page
  persists two identical tab/group snapshots before reconciling, so it can be
  suspended between probes and a slow restore gets additional probes. Firefox
  exposes no session-restore-complete event, so the check is conservative but
  cannot promise a browser-internal completion boundary.
- **Auth.** Hippo's Grafana runs with `GF_AUTH_ANONYMOUS_ENABLED=true`, so
  those 4 load without a login. The homelab instance requires a session cookie.

## Requirements

Firefox 140+ for the `tabGroups` API (`collapsed`, `title`, `color`) and
Firefox's built-in data-collection declaration. Verified against Developer
Edition 155.
