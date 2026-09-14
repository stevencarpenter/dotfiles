# ~/.ssh/config.d/10-homelab.conf: tier-2 personal-host fragment.
#
# op-render deploys this template only for the personal identity.
# Do not put literal 1Password reference schemes in comments: inject scans them.
# ~/.ssh/config includes *.conf before its shared Host defaults.

# i9: 2019 Intel MacBook Pro home server, via Tailscale MagicDNS.
# `ssh i9` for one-off / scp; the `i9` shell alias wraps this in mosh + tmux.
#
# Both names need the same User; otherwise the FQDN inherits the local username.
Host i9 i9.snugmarina.org
    HostName {{ op://Homelab/I9/tailnet_hostname }}
    User steven
