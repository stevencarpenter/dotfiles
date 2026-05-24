# Networking — recommendations for this dotfiles repo

A working document. Captures decisions made, the corrections ratified
mid-conversation, and the open work that still needs to land in this repo
(the *client* side). The *server* side lives in `~/projects/homelab/`.

> **Scope reminder**: this dotfiles repo is the **client** side — what each
> Mac runs, deploys, or syncs. Compose stacks for `caddy`, `atuin`, etc.
> live in `~/projects/homelab/services/<name>/` and are deployed
> independently. Don't add Compose files here.

## Today's reality

What this repo currently touches networking-wise:

- `dot_config/atuin/private_config.toml` — points at
  `https://logbook.snugmarina.org` for shell-history sync. Gated by the
  `atuin` capability.
- `dot_config/zsh/profile.d/tailscale.zsh` — `tsexit` helpers for picking
  Tailscale exit nodes (homelab or Mullvad add-on). Sourced by zsh on any
  machine where `tailscale` is installed.
- `dot_config/aerospace/`, `dot_config/sketchybar/` — local UI, not network.
- Tailscale itself is installed via Homebrew (cask); its config lives in
  user libraries managed by the GUI app, not chezmoi.
- `private_dot_ssh/private_config` → `~/.ssh/config` — chezmoi-managed ssh
  config (personal + lab; work excluded for now). Carries `Host i9`
  (Tailscale MagicDNS) plus keepalive / `ControlMaster` defaults, and
  reproduces the OrbStack include + 1Password `IdentityAgent` those tools
  would otherwise auto-inject. Paired with the personal-only `i9` shell alias
  (`mosh i9 -- tmux new -A -s main`) and `mosh` in the Brewfile, this is the
  primary "reach the i9 home server" path — it replaces leaving a macOS
  Screen Share session open.

Everything else — DNS, firewall, VPN exit nodes — is unmanaged from this
repo today. Some of that should change; some should stay outside the repo.

## Decisions captured

- **AdGuard, not WireGuard, for "all home Wi-Fi traffic"**. AdGuard gives
  DNS-level filtering for everything on the home network at zero per-device
  cost (router DHCP DNS → AdGuard).
- **Tailscale is the homelab mesh** and the "phone home" path. Tailscale
  speaks WireGuard underneath, so adding raw WireGuard on top would be
  duplicative without a specific reason (devices that can't run Tailscale,
  contractual restrictions, etc.). There is intentionally no `wireguard`
  capability in `.chezmoidata/machines.toml` — add it back if and when a
  real consumer lands.
- **Mullvad, if and when it's worth it, rides Tailscale's exit-node
  add-on** rather than a parallel raw-WG setup. The `tsexit mullvad`
  helper is already wired for this.
- **SSH into i9 over Tailscale + mosh + tmux, not Screen Share.** Screen
  Share's `screensharingd` continuously re-encodes screen motion and was the
  dominant heat/fan source on the thermally-marginal 2019 i9 — it only runs
  while a session is connected. SSH + a long-lived tmux session is the daily
  path now; Screen Share stays *enabled* for the rare GUI need on i9's
  unreliable display, just not left open. `~/.ssh/config` is chezmoi-managed
  (personal + lab) to make this repeatable; work-mac is excluded until it
  gets its own per-machine block.

## Recommendations

### 1. Confirm AdGuard via router DHCP (no dotfile change)

**Goal**: every device that joins the home Wi-Fi gets ad/tracker filtering,
no per-device config.

**Action** (router-side, not in this repo):

1. In the home router admin (UDM / OPNsense / whatever): set DHCP DNS
   server to `i9`'s LAN IP (`192.168.0.232`). Disable any "secondary DNS"
   field if it falls back to public DNS — fallback defeats filtering.
2. Confirm AdGuard is the *only* DHCP-distributed DNS server, then
   `arp -a` on a phone or laptop to make sure the lease really points at
   `i9`.

**No changes in this repo.** Chasing this with a tunnel would route traffic
through one extra hop on the same network for the same outcome AdGuard
already provides at the DNS layer.

### 2. Tailscale + Mullvad exit nodes (when you want a privacy posture)

Tailscale offers Mullvad exit nodes as a paid add-on (~$5/device/month). On
any machine with Tailscale installed:

```bash
tsexit list                 # see available exit nodes
tsexit mullvad us-          # fuzzy-match a Mullvad exit (e.g. US ones)
tsexit home                 # route through i9
tsexit off                  # back to direct routing
```

The helper is already deployed (`dot_config/zsh/profile.d/tailscale.zsh`).
No additional capability flag needed — it self-no-ops on machines without
`tailscale` on PATH.

- **Pro**: zero new tunnels to manage. Toggleable per-device, per-session.
- **Con**: extra subscription, vendor lock to Tailscale.

### 3. SSID-gated activation (low priority — only if manual toggling gets old)

> Friendly nudge: this is a finicky pattern with no first-class macOS API.
> `tsexit` already covers most "I want to toggle privacy" cases. Skip
> unless you find yourself running it dozens of times per week.

If it does become worth automating:

- macOS has no "SSID changed" event. Pragmatic options are polling via a
  LaunchAgent or `WatchPaths` on
  `/Library/Preferences/SystemConfiguration/preferences.plist` (the file
  changes on network config events).
- The script reads current SSID via `networksetup -getairportnetwork en0`,
  matches against a known-home list, and runs `tailscale set --exit-node`
  accordingly.
- **Inversion to remember**: usually you want exit-node *off* on home
  Wi-Fi (you're already trusted) and *on* elsewhere. Wire it that way, not
  the inverse.

This would live in a new `dot_config/networking/` directory with a
LaunchAgent template; defer adding the directory until there's a real
script to put in it.

## What I'd do first

1. **Now** — confirm AdGuard via router DHCP (Recommendation 1). No code
   change. This handles the *original* "all home Wi-Fi" goal.
2. **When you next sit down with the privacy goal** — try Tailscale +
   Mullvad exit nodes via `tsexit mullvad <hint>` for one device.
   ~5 minutes to evaluate.
3. **Only if you find yourself toggling all the time** — wire SSID-gated
   activation (Recommendation 3).

## Things explicitly *not* recommended

- ❌ Building raw WireGuard tunnels alongside Tailscale. Tailscale already
  speaks WireGuard, and adding a parallel stack means two key-rotation
  paths, two ACL surfaces, and two failure modes. If WG truly is needed
  later, it'll be because Tailscale specifically can't reach a device — at
  which point it's a one-off, not a capability column.
- ❌ Filtering home Wi-Fi traffic via tunnels. AdGuard at the DNS layer
  handles this for free.
- ❌ Polling SSID every second from a LaunchAgent. Use file watches.
