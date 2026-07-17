#!/usr/bin/env zsh
#
# Tailscale exit-node helpers. The fastest path to "all my traffic via a
# trusted tunnel" without per-device WireGuard config:
#
#   tsexit                # show current state
#   tsexit list           # list available exit nodes (tailnet peers + Mullvad)
#   tsexit set <name>     # route all traffic through <name> as exit node
#   tsexit home           # shorthand: route through i9 (the home homelab)
#   tsexit mullvad [hint] # pick a Mullvad exit node (requires the paid add-on);
#                         # with no hint, picks any; with a hint, fuzzy-matches
#                         # against the node name (e.g. `tsexit mullvad us-`)
#   tsexit off            # clear exit node, return to direct routing
#
# All operations keep LAN access enabled so printers, AirPlay, etc. still work.
# No-op (with a friendly message) on machines without tailscale installed.

if ! command -v tailscale >/dev/null 2>&1; then
  return 0
fi

function tsexit() {
  emulate -L zsh
  local sub="${1:-status}"
  shift 2>/dev/null || true

  case "$sub" in
    status|"")
      local current
      current=$(tailscale status --json 2>/dev/null \
        | jq -r '.ExitNodeStatus.ID // empty' 2>/dev/null)
      if [[ -z "$current" ]]; then
        echo "tsexit: no exit node set (direct routing)"
      else
        local name
        name=$(tailscale status --json 2>/dev/null \
          | jq -r --arg id "$current" \
              '.Peer | to_entries[] | select(.value.ID==$id) | .value.HostName' 2>/dev/null)
        echo "tsexit: routing through ${name:-$current}"
      fi
      ;;

    list)
      echo "Available exit nodes:"
      tailscale exit-node list 2>/dev/null \
        || tailscale status --json \
          | jq -r '.Peer | to_entries[] | select(.value.ExitNodeOption==true) |
              "  \(.value.HostName)\t\(.value.TailscaleIPs[0])"'
      ;;

    set)
      if [[ -z "${1:-}" ]]; then
        echo "Usage: tsexit set <hostname-or-tailnet-name>" >&2
        return 2
      fi
      tailscale set --exit-node="$1" --exit-node-allow-lan-access=true \
        && echo "tsexit: → $1 (LAN access preserved)"
      ;;

    home)
      tailscale set --exit-node=i9 --exit-node-allow-lan-access=true \
        && echo "tsexit: → i9 (homelab)"
      ;;

    mullvad)
      local hint="${1:-}" pick
      pick=$(tailscale exit-node list 2>/dev/null \
        | awk -v h="$hint" 'NR>1 && /mullvad/ && (h=="" || index($0,h)) { print $2; exit }')
      if [[ -z "$pick" ]]; then
        echo "tsexit: no matching Mullvad exit node found." >&2
        echo "  Hint: 'tailscale exit-node list' shows all options. Mullvad" >&2
        echo "  exit nodes require the paid add-on on your tailnet." >&2
        return 1
      fi
      tailscale set --exit-node="$pick" --exit-node-allow-lan-access=true \
        && echo "tsexit: → $pick (Mullvad)"
      ;;

    off|none|clear)
      tailscale set --exit-node= && echo "tsexit: cleared (direct routing)"
      ;;

    *)
      echo "Unknown subcommand: $sub" >&2
      echo "Usage: tsexit [status|list|set <name>|home|mullvad [hint]|off]" >&2
      return 2
      ;;
  esac
}
