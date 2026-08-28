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

Add a dashboard to either repo, re-run, reload the extension. A machine that
does not check out one of those repos silently drops that group; a machine with
neither gets a non-zero exit and no file written, rather than an empty one.

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
- **Re-running is safe.** A group whose exact title is already open is left
  alone, so session restore plus this extension does not double up.
- **Startup waits 2.5s.** `runtime.onStartup` can fire before session restore
  finishes rebuilding groups; acting immediately would miss them and duplicate
  all 13 tabs.
- **Auth.** Hippo's Grafana runs with `GF_AUTH_ANONYMOUS_ENABLED=true`, so
  those 4 load without a login. The homelab instance requires a session cookie.

## Requirements

Firefox 139+ for the `tabGroups` API (`collapsed`, `title`, `color`). Verified
against Developer Edition 155.
