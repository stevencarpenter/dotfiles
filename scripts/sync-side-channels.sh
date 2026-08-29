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
# here. Personal-only — work secrets are the external wrapper's custody, not
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
    # TTY-guarded: `op signin` blocks waiting for input, so it must not run in
    # CI, cron, or any other non-interactive invocation, where hanging is far
    # worse than skipping. (bootstrap.sh IS interactive and so does sign in —
    # the guard protects the headless callers, not that one.) With no TTY, fall
    # through and let op-render report whatever auth state it finds.
    #
    # Scoped to a subshell so OP_SESSION_* reaches op-render and NOTHING else.
    # The rest of this script clones over SSH and runs `uv tool install` on
    # third-party build code; none of that needs a 1Password session, and a
    # token in the environment is also readable by same-user processes.
    echo "==> Rendering op:// secrets"
    (
      if [ -t 0 ]; then
        # stdout is captured (op emits `export OP_SESSION_…` there), stderr is
        # deliberately NOT redirected: op writes both its prompts and its errors
        # there. Capturing it would hide a password prompt and look like a hang;
        # discarding it would recreate the swallowed-stderr anti-pattern that
        # made the original breakage unreadable for two weeks.
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

# lefthook — wire .git/hooks to lefthook.yml. Idempotent, and safe to re-run:
# `lefthook install` rewrites the hook files from the config every time. Done
# here rather than in home.activation because it writes into THIS checkout's
# .git, which activation has no business touching. A machine that never syncs
# simply has no hooks, which is the pre-existing behavior.
if command -v lefthook >/dev/null 2>&1; then
  echo "==> Installing git hooks (lefthook)"
  (cd "$repo_root" && lefthook install)
else
  echo "warning: lefthook not found; git hooks not installed (run 'just sync' after a rebuild)" >&2
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

# agent-reap — vendored in this repo, so it installs from the local path rather
# than a pinned remote release. Unconditional like token-auditor: it is inert on
# a machine with no tmux server and no teams, so a capability gate would buy
# nothing.
#
# --reinstall is REQUIRED, not belt-and-braces. With --force alone, uv reuses its
# cached wheel for this path while the version string is unchanged, so edits to
# the source deploy a STALE binary and the failure is silent — verified: a new
# code path was missing from the installed copy while `uv run` on the same tree
# had it. Since a vendored tool's version rarely bumps per edit, --reinstall is
# the only way to guarantee what is on PATH matches this checkout.
if command -v "$uv_bin" >/dev/null 2>&1; then
  echo "==> Installing agent-reap (${repo_root}/agent_reap)"
  "$uv_bin" tool install --force --reinstall "$repo_root/agent_reap"
else
  echo "error: uv not found; cannot install agent-reap" >&2
  exit 1
fi
