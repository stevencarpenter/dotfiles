# Networking — recommendations for this dotfiles repo

A working document. Captures decisions you've made, the corrections you've
ratified mid-conversation, and the open work that still needs to land in
this repo (the *client* side). The *server* side lives in
`~/projects/homelab/`.

> **Scope reminder**: this dotfiles repo is the **client** side — what each
> Mac runs, deploys, or syncs. Compose stacks for `caddy`, `atuin`,
> eventually `wireguard`, etc. live in `~/projects/homelab/services/<name>/`
> and are deployed independently. Don't add Compose files here.

## Today's reality

What this repo currently touches networking-wise:

- `dot_config/atuin/config.toml` — points at `https://logbook.snugmarina.org`
  for shell-history sync. Gated by the `atuin` capability.
- `dot_config/aerospace/`, `dot_config/sketchybar/` — local UI, not network.
- That's it. Tailscale is installed via Homebrew (cask), but its config
  lives in user libraries managed by the GUI app, not chezmoi.

Everything else — DNS, VPN, firewall, exit nodes — is unmanaged from this
repo today. Some of that should change; some should stay outside the repo.

## Corrections / clarifications captured

- **AdGuard, not WireGuard, for "all home Wi-Fi traffic"**. Earlier ask
  conflated the two. AdGuard gives DNS-level filtering for everything on
  the home network at zero per-device cost (router DHCP DNS → AdGuard).
  WireGuard is the *future* tunnel, not the home-network filter.
- **Tailscale stays as the homelab mesh**. WireGuard configs added later
  are *additional*, not replacements.
- **The "phone home" use case** is Tailscale's existing job. Adding raw
  WireGuard for it is duplicative unless we have a specific reason
  (devices that can't run Tailscale, contractual restrictions, etc.).

## Recommendations

Numbered roughly by ordering — earliest things first.

### 1. Confirm AdGuard via router DHCP (no dotfile change)

**Goal**: every device that joins `Fuck Nebraska` / `Fuck Nebraska More`
gets ad/tracker filtering, no per-device config.

**Action** (router-side, not in this repo):

1. In the home router admin (UDM / OPNsense / whatever): set DHCP DNS
   server to `i9`'s LAN IP (`192.168.0.232`). Disable any "secondary DNS"
   field if it falls back to public DNS — fallback defeats filtering.
2. Confirm AdGuard is the *only* DHCP-distributed DNS server, then
   `arp -a` on a phone or laptop to make sure the lease really points at
   `i9`.

**No changes in this repo.** This was the antipattern flagged earlier:
chasing this with WireGuard would route traffic through one extra hop on
the same network for the same outcome AdGuard already provides at the DNS
layer.

### 2. Fix the atuin client comment drift (small dotfile change, ready now)

**File**: `dot_config/atuin/config.toml`

The comment block currently says:

```
# Self-hosted atuin sync target. Server lives on i9
# (homelab repo: services/atuin/). Deployed only on machines where the
# `atuin` capability is true (see .chezmoidata/machines.toml).
```

That path now genuinely exists (`~/projects/homelab/services/atuin/`), so
the comment is *finally* accurate — but only after the homelab repo is
deployed. Recommend a small touch-up once the server is verified running:

- Add a one-liner crossref to the deploy verification command:
  `# Verify server: curl -sI https://logbook.snugmarina.org/healthz`
- Optionally, add a `# Last verified: YYYY-MM-DD` line and update on each
  major homelab change. (Cheap drift-detection.)

**Don't** add the username, key, or any per-device state to this file —
that lives in `~/.local/share/atuin/` and is per-machine.

### 3. WireGuard client configs (future — for "phone home" if Tailscale isn't enough)

**Pre-question**: does Tailscale not already cover this?

- ✅ Tailscale gives every signed-in device a stable `100.x` IP.
- ✅ ACLs control which devices can reach which.
- ✅ MagicDNS resolves `i9` from anywhere.
- ✅ Tailscale SSH avoids managing keys per-host.

If the answer is *yes, Tailscale covers it*: skip this recommendation.

If the answer is *no, I want a raw WG path because [specific reason]*:

**Where the configs go**: a new `dot_config/wireguard/` directory with
peer configs as templates so each machine pulls only its peer.

**Suggested layout**:

```
dot_config/wireguard/
├── peer_personal.conf.tmpl   # personal-mac's peer config (gated)
├── peer_lab.conf.tmpl        # lab-mac's peer config (gated)
└── README.md                 # "do not edit; rotate via homelab repo"
```

Each `.tmpl` materializes the per-machine peer config with secrets pulled
from 1Password (`{{ onepasswordRead "op://homelab/wg-peer-<host>/private-key" }}`).

**Capability**: add `wireguard` to `.chezmoidata/machines.toml`. Default
true on machines that should auto-deploy a peer config; false elsewhere.

**Antipattern to avoid**: do **not** check actual private keys into the
repo, even encrypted. The homelab WG server already generates them per
peer; pull the private key from 1Password (or copy on first deploy) and
let chezmoi reference it via `op://`.

### 4. Mullvad / "ultra-secure VPN" (future — pick a posture)

Three reasonable approaches, ranked by effort:

#### Option A — Tailscale + Mullvad exit nodes (lowest effort)

Tailscale offers Mullvad exit nodes as a paid add-on (~$5/device/month last
I checked). Each device on the tailnet can opt into a Mullvad exit:

```bash
tailscale set --exit-node=<mullvad-exit-node-name>
```

- **Pro**: zero new config, zero new tunnels to manage. Toggleable
  per-device, per-session.
- **Con**: extra subscription, vendor lock to Tailscale.
- **Dotfile change**: optional — a `tailscale-exit` shell function with
  named presets (`tailscale-exit mullvad-stockholm`, `tailscale-exit off`)
  could live in `dot_config/zsh/`. Trivial.

This is the recommended starting point unless you have a reason to bypass
it.

#### Option B — Direct Mullvad WireGuard configs

Mullvad lets you download per-server WireGuard configs from their
account portal. Each is a self-contained `.conf` you import into
WireGuard.app (macOS) or `wg-quick` (CLI).

- **Pro**: no Tailscale dependency for privacy tunnel. Works on iOS/Android
  via Mullvad's apps. Cheaper if you already pay for Mullvad.
- **Con**: per-device key management. SSID-gated activation has to be
  scripted (see #5). Configs rotate over time — you'll re-download.

**Where in dotfiles**: put a `dot_config/wireguard/mullvad/.gitkeep` and
document in the README that Mullvad configs are downloaded per-device, not
synced — they're keyed material that varies per-install. Don't try to
centralize them.

#### Option C — Mullvad chained behind home WG (highest effort, niche)

Phone → home WG → Mullvad → internet. This means the home WG server
itself runs a Mullvad client and routes peer traffic out the Mullvad
tunnel. Requires `services/wireguard/` to add a Mullvad upstream, and
ip-rules / namespaces to keep peer traffic separated from i9's own.

- **Pro**: peers don't need to know about Mullvad; they just connect home.
- **Con**: complex, brittle, Mullvad outage = home tunnel outage, double
  latency overhead. Almost always overkill.

Skip unless you have a specific reason (multi-hop privacy with home as a
known anchor, family devices that can't run Mullvad apps, etc.).

**Recommendation**: start with Option A. Move to B if you want to skip
Tailscale's add-on cost. Avoid C until/unless there's a concrete need.

### 5. SSID-gated activation (future — only if you really want it)

> Friendly nudge: this is a finicky pattern with no first-class macOS API.
> Consider whether you actually need it before building it. Tailscale +
> Mullvad exit nodes are toggle-on-demand without SSID logic.

If you do want "auto-engage tunnel on `Fuck Nebraska` / `Fuck Nebraska
More`":

**Where it lives**: a LaunchAgent + script in dotfiles, NOT the homelab
repo. Sketch:

```
dot_config/networking/
├── ssid-watch.sh             # script: check current SSID, toggle WG
└── com.steven.ssid-watch.plist.tmpl   # LaunchAgent (loaded at login)
```

**How it triggers**: there's no "SSID changed" event on macOS. Pragmatic
options:

1. **Polling**: LaunchAgent runs `ssid-watch.sh` every 30s. Cheap, late.
2. **`networksetup -listpreferredwirelessnetworks`** + `system_profiler` +
   `WatchPaths` on `/Library/Preferences/SystemConfiguration/preferences.plist`
   — the file changes on network config events. Better.
3. **WireGuard.app's "On-Demand" rules** — built-in SSID matching, no
   custom script. **This is the easiest path** if your tunnel is the
   Mullvad-style consumer setup; the GUI handles it.

**Recommendation**: prefer WireGuard.app's "On-Demand" rules where they
fit. Only build the LaunchAgent path if you're managing the tunnel
entirely from CLI for a specific reason.

If the LaunchAgent path is needed, it should:

- Read current SSID via `networksetup -getairportnetwork en0`.
- If SSID matches `^Fuck Nebraska( More)?$`, ensure the home tunnel is
  *down* (it's redundant on the home LAN — see Recommendation 1).
- If SSID is *anything else*, ensure the privacy tunnel is *up* (Mullvad
  via Option A or B).

That inversion — tunnel *off* on home Wi-Fi, *on* elsewhere — is usually
what people actually want. Read your goal carefully before wiring it the
other way.

### 6. Add capabilities for the new features (when they actually land)

Per the existing capability pattern (`.chezmoidata/machines.toml`), each
of these gets a column when implemented:

| Capability | True for | What it gates |
|---|---|---|
| `wireguard` | machines that get a homelab peer config | `dot_config/wireguard/peer_*.conf.tmpl` |
| `mullvad` | machines that run Mullvad CLI/app via dotfiles | (mostly nothing — Mullvad's app self-manages) |
| `ssid_watch` | machines that auto-toggle tunnel by SSID | `dot_config/networking/` + LaunchAgent |

Don't add these *until* the corresponding feature is actually being
deployed — empty capabilities are clutter.

## What I'd do first

1. **Now** — confirm AdGuard via router DHCP (Recommendation 1). No code
   change. This handles the *original* "all home Wi-Fi" goal.
2. **After homelab atuin lands** — touch up the `dot_config/atuin/config.toml`
   comment (Recommendation 2). One-line drift fix.
3. **When you next sit down with the privacy goal** — try Tailscale +
   Mullvad exit nodes (Recommendation 4 Option A) for one device.
   No dotfile changes, ~5 minutes to evaluate.
4. **Only if 3 doesn't fit** — start the WG client config plumbing
   (Recommendation 3) and pick a Mullvad option (4B or 4C).
5. **Only if you've actually deployed a tunnel and find yourself toggling
   it manually all the time** — build SSID-gated activation
   (Recommendation 5).

## Things explicitly *not* recommended

- ❌ Building WireGuard "to filter home Wi-Fi traffic" — AdGuard already
  does that at the DNS layer with no tunnel overhead.
- ❌ Replacing Tailscale with raw WireGuard — large redesign, contradicts
  the homelab CLAUDE.md, removes useful features (ACLs, MagicDNS, mobile
  apps). Tailscale already speaks WireGuard underneath.
- ❌ Storing WG private keys in the dotfiles repo, even age-encrypted.
  The homelab generates them; pull via 1Password at apply time.
- ❌ Polling SSID every second from a LaunchAgent. Use file watches or
  WireGuard.app's built-in matchers.
