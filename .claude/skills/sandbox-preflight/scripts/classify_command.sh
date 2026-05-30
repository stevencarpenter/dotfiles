#!/usr/bin/env bash
# classify_command.sh — decide whether a command must run with the Claude Code sandbox
# disabled in THIS repo. Deterministic and testable: prints one of
#   DISABLE_SANDBOX <reason-class>
#   SANDBOX_OK      local-or-allowlisted
#
# Reason classes: gh-network git-network git-config uv-cache ssh-controlmaster mktemp-outside-tmpdir
#
# Usage: classify_command.sh '<command string>'
set -euo pipefail

cmd="${*:-}"
if [ -z "$cmd" ]; then
  echo "usage: classify_command.sh '<command string>'" >&2
  exit 2
fi

emit() { printf 'DISABLE_SANDBOX\t%s\n' "$1"; exit 0; }

# GitHub network (gh CLI hits api.github.com -> TLS fails OSStatus -26276 under sandbox)
if printf '%s' "$cmd" | grep -Eq '(^|[;&|[:space:]])gh([[:space:]]|$)'; then emit gh-network; fi

# git operations that write .git/config (branch rename, remote url, config, init)
if printf '%s' "$cmd" | grep -Eq 'git[[:space:]]+(config|init)([[:space:]]|$)|git[[:space:]]+branch[[:space:]]+(-m|--move)|git[[:space:]]+remote[[:space:]]+(set-url|add|rename)'; then emit git-config; fi

# git operations that hit the GitHub network
if printf '%s' "$cmd" | grep -Eq 'git[[:space:]]+(push|fetch|pull|clone|ls-remote)([[:space:]]|$)'; then emit git-network; fi

# uv / python tool cache writes (~/.cache/uv is NOT in the sandbox allowWrite pre-seed)
if printf '%s' "$cmd" | grep -Eq '(^|[;&|[:space:]])(uv|uvx|ruff|pytest|ty)([[:space:]]|$)'; then emit uv-cache; fi

# ssh ControlMaster / control-socket bind under ~/.ssh
if printf '%s' "$cmd" | grep -Eq '(^|[;&|[:space:]])ssh([[:space:]]|$)|ControlMaster|ControlPath'; then emit ssh-controlmaster; fi

# mktemp/mkdtemp targeting a non-allowlisted dir (use $TMPDIR instead)
if printf '%s' "$cmd" | grep -Eq 'mk(d)?temp[^|;&]*(/tmp|/var/folders|/var/tmp)'; then emit mktemp-outside-tmpdir; fi

printf 'SANDBOX_OK\t%s\n' "local-or-allowlisted"
