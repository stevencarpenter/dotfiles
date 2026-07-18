# ~/.ssh/config — rendered by op-render from this template (WS1). Public-safe:
# the i9 host address comes from 1Password at render time and is never committed
# here. (Do not write a literal 1Password ref scheme in a comment — inject scans
# the whole file and would try to resolve it.)
#
# OrbStack injects `Include ~/.orbstack/ssh/config` and will NOT re-add it if
# removed, so it must stay first (before any Host block). 1Password's SSH agent
# provides the IdentityAgent socket in `Host *`.

# OrbStack: 'orb' SSH host for Linux machines. Must stay before any Host blocks.
Include ~/.orbstack/ssh/config

# Extension seam (LOCKED contract): external overlay fragments. MUST stay
# above every Host block — ssh_config is first-match-wins, so a fragment's
# specific Host stanzas can never win from below `Host *`. Empty glob is fine.
Include ~/.ssh/config.d/*

# i9 — 2019 Intel MacBook Pro home server, via Tailscale MagicDNS.
# `ssh i9` for one-off / scp; the `i9` shell alias wraps this in mosh + tmux.
Host i9
    HostName {{ op://Homelab/I9/tailnet_hostname }}
    User steven

Host *
    # Survive laptop sleep / NAT idle: probe every 30s, give up after 3 misses.
    ServerAliveInterval 30
    ServerAliveCountMax 3
    # Multiplex repeat connections for instant reuse. %C hashes the connection
    # tuple, dodging macOS's 104-char unix-socket path limit.
    ControlMaster auto
    ControlPath ~/.ssh/cm-%C
    ControlPersist 10m
    # 1Password SSH agent (reproduced from 1Password's own injection; see header).
    IdentityAgent "~/Library/Group Containers/2BUA8C4S2C.com.1password/t/agent.sock"
