# Networking: recommendations for this dotfiles repo

This repo owns client configuration. Server configuration lives in `~/projects/homelab/`.

> **Scope reminder**: this dotfiles repo is the **client** side: what each
> Mac runs, deploys, or syncs. Compose stacks for `caddy`, `atuin`, etc.
> live in `~/projects/homelab/services/<name>/` and are deployed
> independently. Don't add Compose files here.

## Current configuration

Network-related configuration:

- `home/.config/atuin/config.sync.toml`: points at
  `https://logbook.snugmarina.org` for shell-history sync. Deployed as
  `~/.config/atuin/config.toml` on machines where the `atuin` capability is
  true. Machines where it is false get `config.local.toml` instead, which sets
  `auto_sync = false` and names no server: the capability selects the
  variant, it does not gate the file's existence.
- `home/.config/zsh/profile.d/tailscale.zsh`: `tsexit` helpers for picking
  Tailscale exit nodes (homelab or Mullvad add-on). Sourced by zsh on any
  machine where `tailscale` is installed.
- `home/.config/aerospace/`, `home/.config/sketchybar/`: local UI, not network.
- Tailscale itself is installed via Homebrew (cask); its config lives in
  user libraries managed by the GUI app, not Nix.
- `home/.ssh/config.d/10-homelab.conf.tpl` → `~/.ssh/config.d/10-homelab.conf`: personal-only `op-render` template, deployed mode
  0600 from 1Password references. Carries `Host i9`
  (Tailscale MagicDNS) plus keepalive / `ControlMaster` defaults, and
  reproduces the OrbStack include + 1Password `IdentityAgent` those tools
  would otherwise auto-inject. Paired with the personal-only `i9` shell alias
  (`mosh i9 -- tmux new -A -s main`) and `mosh` in the package set, this is the
  primary "reach the i9 home server" path: it replaces leaving a macOS
  Screen Share session open.

DNS, firewall, and VPN exit-node configuration are not managed by this repo.

## Decisions captured

- **AdGuard, not WireGuard, for "all home Wi-Fi traffic"**. AdGuard gives
  DNS-level filtering for everything on the home network at zero per-device
  cost (router DHCP DNS → AdGuard).
- **Tailscale provides remote access to the homelab.** Tailscale
  speaks WireGuard underneath, so adding raw WireGuard on top would be
  duplicative without a specific reason (devices that can't run Tailscale,
  contractual restrictions, etc.). There is intentionally no `wireguard`
  capability in `lib/machines.nix`: add it back if and when a
  real consumer lands.
- **Use Tailscale's Mullvad exit-node add-on** when Mullvad is needed,
  rather than a parallel raw-WG setup. The `tsexit mullvad`
  helper is already wired for this.
- **SSH into i9 over Tailscale + mosh + tmux, not Screen Share.** Screen
  Share's `screensharingd` continuously re-encodes screen motion and was the
  dominant heat/fan source on the thermally-marginal 2019 i9: it only runs
  while a session is connected. SSH + a long-lived tmux session is the daily
  path now; Screen Share stays *enabled* for the rare GUI need on i9's
  unreliable display, just not left open. The `Host i9` stanza is a personal-only
  op-rendered tier-2 fragment (`~/.ssh/config.d/10-homelab.conf`), so it never materializes on a
  machine that cannot reach the tailnet. A work machine is built by its own external wrapper,
  which owns the corresponding tier-3 fragment.

## Recommendations

### 1. Confirm AdGuard via router DHCP (no dotfile change)

**Goal**: every device that joins the home Wi-Fi gets ad/tracker filtering,
no per-device config.

**Action** (router-side, not in this repo):

1. In the home router admin (UDM / OPNsense / whatever): set DHCP DNS
   server to `i9`'s LAN IP (`192.168.0.232`). Disable any "secondary DNS"
   field if it falls back to public DNS: fallback defeats filtering.
2. Confirm AdGuard is the *only* DHCP-distributed DNS server, then
   `arp -a` on a phone or laptop to make sure the lease really points at
   `i9`.

**No changes in this repo.** Chasing this with a tunnel would route traffic
through one extra hop on the same network for the same outcome AdGuard
already provides at the DNS layer.

### 2. Tailscale + Mullvad exit nodes

Tailscale offers Mullvad exit nodes as a paid add-on (~$5/device/month). On
any machine with Tailscale installed:

```bash
tsexit list                 # see available exit nodes
tsexit mullvad us-          # fuzzy-match a Mullvad exit (e.g. US ones)
tsexit home                 # route through i9
tsexit off                  # back to direct routing
```

The helper is already deployed (`dot_config/zsh/profile.d/tailscale.zsh`).
No additional capability flag is needed: the helper does nothing without
`tailscale` on PATH.

- **Pro**: zero new tunnels to manage. Toggleable per-device, per-session.
- **Con**: extra subscription, vendor lock to Tailscale.

### 3. SSID-gated activation (only if manual toggling becomes frequent)

> There is no first-class macOS API for this pattern. Use `tsexit` manually
> unless toggling is needed dozens of times per week.

If automation is needed:

- macOS has no "SSID changed" event. Options are polling via a
  LaunchAgent or `WatchPaths` on
  `/Library/Preferences/SystemConfiguration/preferences.plist` (the file
  changes on network config events).
- The script reads current SSID via `networksetup -getairportnetwork en0`,
  matches against a known-home list, and runs `tailscale set --exit-node`
  accordingly.
- Usually configure the exit node *off* on trusted home Wi-Fi and *on* elsewhere.

This would live in a new `dot_config/networking/` directory with a
LaunchAgent template; defer adding the directory until there's a real
script to put in it.

## Recommended order

1. Confirm AdGuard via router DHCP (Recommendation 1). No code change.
2. If an exit node is needed, try Tailscale +
   Mullvad exit nodes via `tsexit mullvad <hint>` for one device.
   ~5 minutes to evaluate.
3. If manual toggling becomes frequent, configure SSID-gated
   activation (Recommendation 3).

## Avoid

- Building raw WireGuard tunnels alongside Tailscale. Tailscale already
  speaks WireGuard, and adding a parallel stack means two key-rotation
  paths, two ACL surfaces, and two failure modes. Add raw WireGuard only for
  a device Tailscale cannot reach, using device-specific configuration.
- Filtering home Wi-Fi traffic via tunnels. AdGuard at the DNS layer
  handles this for free.
- Polling SSID every second from a LaunchAgent. Use file watches.
