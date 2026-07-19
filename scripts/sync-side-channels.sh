#!/usr/bin/env bash
# Network/SSH provisioning kept deliberately outside darwin-rebuild activation.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
git_bin="${GIT_BIN:-git}"
uv_bin="${UV_BIN:-uv}"
capability_bin="${HOST_CAPABILITY_BIN:-$repo_root/scripts/host-capability.sh}"
token_auditor_version="${TOKEN_AUDITOR_VERSION:-latest}"

# tpm (tmux plugin manager) — public https clone, weekly refresh upstream.
tpm_dir="$HOME/.config/tmux/plugins/tpm"
if [ -d "$tpm_dir/.git" ]; then
  echo "==> Refreshing tpm"
  "$git_bin" -C "$tpm_dir" pull --ff-only || echo "warning: tpm pull failed" >&2
else
  echo "==> Cloning tpm"
  "$git_bin" clone https://github.com/tmux-plugins/tpm.git "$tpm_dir"
fi

# The agent registry is personal content. Fail closed: only touch its SSH
# remote when the selected host's canonical agents capability is true.
agents_enabled="$($capability_bin agents)"
if [ "$agents_enabled" = "1" ]; then
  reg_dir="$HOME/.local/share/agent-registry"
  if [ -d "$reg_dir/.git" ]; then
    echo "==> Refreshing agent-registry"
    "$git_bin" -C "$reg_dir" pull --ff-only || echo "warning: agent-registry pull failed" >&2
  else
    echo "==> Cloning agent-registry (SSH)"
    "$git_bin" clone git@github.com:stevencarpenter/agents.git "$reg_dir" \
      || echo "warning: agent-registry clone failed (SSH key/network?)" >&2
  fi
else
  echo "==> Skipping personal agent-registry (agents capability disabled)"
fi

# token-auditor — standalone uv tool from its own public repo. --force makes
# re-install idempotent and upgrades in place on a version bump.
if command -v "$uv_bin" >/dev/null 2>&1; then
  ref="git+https://github.com/stevencarpenter/token-auditor"
  if [ "$token_auditor_version" != "latest" ]; then
    ref="${ref}@${token_auditor_version}"
  fi
  echo "==> Installing token-auditor (${ref})"
  "$uv_bin" tool install --force "$ref" || echo "warning: token-auditor install failed" >&2
else
  echo "warning: uv not found; skipping token-auditor install" >&2
fi
