# ~/.ssh/config.d/10-homelab.conf — tier-2 personal-host fragment.
#
# Rendered by op-render from this template, PERSONAL IDENTITY ONLY: both the
# manifest symlink and the renderer invocation are personal-gated, so this never
# materializes on a work machine. The homelab address comes from 1Password at
# render time and is never committed here. (Do not write a literal 1Password ref
# scheme in a comment — inject scans the whole file and would try to resolve it.)
#
# Included by ~/.ssh/config's `Include ~/.ssh/config.d/*`, which sits above that
# file's `Host *` block, so these stanzas win on first match.
#
# Agent, multiplexing, and keepalives are deliberately NOT repeated here — they
# come from the universal `Host *` in ~/.ssh/config on every machine.

# i9 — 2019 Intel MacBook Pro home server, via Tailscale MagicDNS.
# `ssh i9` for one-off / scp; the `i9` shell alias wraps this in mosh + tmux.
#
# The FQDN is listed as a second pattern because the homelab repo documents
# i9.snugmarina.org as the per-host SSH name. Without it that form matches no
# Host block, falls through to the universal `Host *`, and tries the LOCAL
# username, which i9 rejects with "Permission denied (publickey)". That reads
# like a broken key rather than a missing alias. Both spellings must land on
# the same tailnet HostName and the same User.
Host i9 i9.snugmarina.org
    HostName {{ op://Homelab/I9/tailnet_hostname }}
    User steven
