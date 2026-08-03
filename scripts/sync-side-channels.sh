#!/usr/bin/env bash
# Network/SSH provisioning kept deliberately outside darwin-rebuild activation.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
git_bin="${GIT_BIN:-git}"
uv_bin="${UV_BIN:-uv}"
capability_bin="${HOST_CAPABILITY_BIN:-$repo_root/scripts/host-capability.sh}"
token_auditor_version="$(
  printf '%s' "${TOKEN_AUDITOR_VERSION:-$(tr -d '\n' <"$repo_root/versions/token-auditor")}"
)"
if [ -z "$token_auditor_version" ] || [ "$token_auditor_version" = "latest" ]; then
  echo "error: token-auditor requires an immutable release tag" >&2
  exit 1
fi

# op-render — materialize ~/.ssh/config and ~/.config/zsh/.personal.env from
# op:// templates. Ordered FIRST on purpose: the agent-registry clone below
# talks to git@github.com over SSH and so depends on the ssh config rendered
# here. Personal-only — work secrets come from agenix during activation, not
# 1Password.
#
# This cannot live in home.activation. Rendering needs network plus an
# interactive approval: the 1Password desktop app authorizes CLI access by
# calling-process ancestry, and a `sudo darwin-rebuild` activation is not an
# approved one (its PATH does not even contain /opt/homebrew/bin/op). Run from
# a terminal, which is what `just sync` is for. Activation keeps only the
# staleness nag (`op-render --warn-stale-only`).
identity="$("$capability_bin" --identity)"
if [ "$identity" = "personal" ]; then
  render_bin="${OP_RENDER_BIN:-$repo_root/home/.local/bin/op-render}"
  if [ -x "$render_bin" ]; then
    # Establish a session before rendering. `op` sessions expire after ~30
    # minutes of inactivity, so the interactive command that needs one is the
    # right place to ask — that is this script, run from your terminal.
    # Idempotent: with a session already live, `op signin` just reprints the
    # export line and prompts for nothing.
    #
    # eval, because op emits `export OP_SESSION_<shorthand>="…"` on stdout for
    # the caller to apply; op-render then inherits it as a child process. The
    # token stays in this process's environment and is never logged or written.
    #
    # TTY-guarded: `op signin` blocks waiting for input, and this script also
    # runs from bootstrap.sh and non-interactive contexts where hanging is far
    # worse than skipping. With no TTY, fall through and let op-render report
    # the auth state it finds.
    if [ -t 0 ]; then
      eval "$("${OP_BIN:-op}" signin 2>/dev/null || true)"
    fi
    echo "==> Rendering op:// secrets"
    "$render_bin" ||
      echo "warning: op-render did not complete; existing secrets left intact" >&2
  else
    echo "warning: op-render not executable at $render_bin; skipping" >&2
  fi
else
  echo "==> Skipping op-render (identity: $identity)"
fi

# tpm (tmux plugin manager) — public https clone, weekly refresh upstream.
tpm_dir="$HOME/.config/tmux/plugins/tpm"
if [ -d "$tpm_dir/.git" ]; then
  echo "==> Refreshing tpm"
  "$git_bin" -C "$tpm_dir" pull --ff-only
else
  echo "==> Cloning tpm"
  "$git_bin" clone https://github.com/tmux-plugins/tpm.git "$tpm_dir"
fi

# The agent registry is personal content. Fail closed: only touch its SSH
# remote when the selected host's canonical agents capability is true.
agents_enabled="$($capability_bin agents)"
if [ "$agents_enabled" = "1" ]; then
  working_copy="$HOME/projects/agents"
  managed_copy="$HOME/.local/share/agent-registry"
  if [ -f "$working_copy/pyproject.toml" ]; then
    reg_dir="$working_copy"
    echo "==> Using agent-registry working copy ($reg_dir)"
  else
    reg_dir="$managed_copy"
    if [ -d "$reg_dir/.git" ]; then
      echo "==> Refreshing agent-registry"
      "$git_bin" -C "$reg_dir" pull --ff-only
    else
      echo "==> Cloning agent-registry (SSH)"
      "$git_bin" clone git@github.com:stevencarpenter/agents.git "$reg_dir"
    fi
  fi
  "$repo_root/scripts/install-agent-registry.sh" "$reg_dir"
else
  echo "==> Skipping personal agent-registry (agents capability disabled)"
fi

# token-auditor — standalone uv tool from its own public repo. --force makes
# re-install idempotent and upgrades in place on a version bump.
if command -v "$uv_bin" >/dev/null 2>&1; then
  ref="git+https://github.com/stevencarpenter/token-auditor@${token_auditor_version}"
  echo "==> Installing token-auditor (${ref})"
  "$uv_bin" tool install --force "$ref"
else
  echo "error: uv not found; cannot install token-auditor" >&2
  exit 1
fi
