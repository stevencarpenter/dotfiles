#!/usr/bin/env bash
# Network and SSH provisioning outside darwin-rebuild activation.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
git_bin="${GIT_BIN:-git}"
uv_bin="${UV_BIN:-uv}"
mise_bin="${MISE_BIN:-mise}"
capability_bin="${HOST_CAPABILITY_BIN:-$repo_root/scripts/host-capability.sh}"
token_auditor_version="$(
  printf '%s' "${TOKEN_AUDITOR_VERSION:-$(tr -d '\n' <"$repo_root/versions/token-auditor")}"
)"
if [ -z "$token_auditor_version" ] || [ "$token_auditor_version" = "latest" ]; then
  echo "error: token-auditor requires an immutable release tag" >&2
  exit 1
fi

# Install tools declared in ~/.config/mise/config.toml.
if command -v "$mise_bin" >/dev/null 2>&1; then
  echo "==> Installing mise-managed tools"
  "$mise_bin" install
else
  echo "error: mise not found; cannot install declared global tools" >&2
  exit 1
fi

# Render personal secrets before the agent-registry clone needs ~/.ssh/config.
# Rendering requires network and interactive 1Password authorization, unavailable
# during sudo activation. Activation only runs op-render --warn-stale-only.
identity="$("$capability_bin" --identity)"
if [ "$identity" = "personal" ]; then
  render_bin="${OP_RENDER_BIN:-$repo_root/home/.local/bin/op-render}"
  if [ -x "$render_bin" ]; then
    # Refresh expired sessions only with a TTY; headless signin can block.
    # Evaluate op's exported session in this subshell so op-render inherits it,
    # but subsequent Git and third-party build processes do not.
    # Never log or persist the session token.
    echo "==> Rendering op:// secrets"
    (
      if [ -t 0 ]; then
        # Capture exported session variables; keep prompts and errors visible on stderr.
        signin_out=""
        if signin_out="$("${OP_BIN:-op}" signin)"; then
          eval "$signin_out"
        else
          echo "warning: op signin failed (see op's message above); rendering anyway" >&2
        fi
      fi
      "$render_bin"
    ) || echo "warning: op-render did not complete; existing secrets left intact" >&2
  else
    echo "warning: op-render not executable at $render_bin; skipping" >&2
  fi
else
  echo "==> Skipping op-render (identity: $identity)"
fi

# Refresh tpm from its public HTTPS repository on each sync.
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

# Install hooks during sync because this writes the checkout's .git directory.
if command -v lefthook >/dev/null 2>&1; then
  echo "==> Installing git hooks (lefthook)"
  # Hook installation failure must not abort the remaining sync.
  (cd "$repo_root" && lefthook install) ||
    echo "warning: lefthook install failed; git hooks not wired" >&2
else
  echo "warning: lefthook not found; git hooks not installed (run 'just sync' after a rebuild)" >&2
fi

# token-auditor: standalone uv tool from its own public repo. --force makes
# re-install idempotent and upgrades in place on a version bump.
if command -v "$uv_bin" >/dev/null 2>&1; then
  ref="git+https://github.com/stevencarpenter/token-auditor@${token_auditor_version}"
  echo "==> Installing token-auditor (${ref})"
  "$uv_bin" tool install --force "$ref"
else
  echo "error: uv not found; cannot install token-auditor" >&2
  exit 1
fi

# Install agent-reap from this checkout on every host; it is inert without tmux.
# --reinstall prevents uv from reusing a cached wheel when the version is unchanged.
if command -v "$uv_bin" >/dev/null 2>&1; then
  echo "==> Installing agent-reap (${repo_root}/agent_reap)"
  "$uv_bin" tool install --force --reinstall "$repo_root/agent_reap"
else
  echo "error: uv not found; cannot install agent-reap" >&2
  exit 1
fi

# Codex owns this plugin's configuration and cache; ensure it during sync.
# Installation failure is nonfatal. Hooks require node on PATH and approval
# through /hooks in a Codex session after installation.
if command -v codex >/dev/null 2>&1; then
  echo "==> Ensuring ponytail Codex plugin"
  codex plugin marketplace list 2>/dev/null | grep -q "ponytail" ||
    codex plugin marketplace add DietrichGebert/ponytail ||
    echo "warning: ponytail marketplace add failed" >&2
  plugin_list="$(codex plugin list 2>/dev/null)" || plugin_list=""
  if ! printf '%s\n' "$plugin_list" | awk '$1 == "ponytail@ponytail" && $2 == "installed," { found = 1 } END { exit !found }'; then
    codex plugin add ponytail@ponytail ||
      echo "warning: ponytail plugin add failed" >&2
  fi
else
  echo "warning: codex not found; ponytail Codex plugin not ensured" >&2
fi
