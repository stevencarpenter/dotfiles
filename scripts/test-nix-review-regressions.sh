#!/usr/bin/env bash
# Semantic checks for review findings that plain flake evaluation cannot see.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

login_activation="$(
  nix eval --raw \
    '.#darwinConfigurations.personal-mac.config.system.activationScripts.postActivation.text'
)"
if ! rg -Fq 'UserShell' <<<"$login_activation" || ! rg -Fq '/bin/zsh' <<<"$login_activation"; then
  echo "emitted system activation does not enforce UserShell=/bin/zsh" >&2
  exit 1
fi

agenix_launchd_enabled="$(
  nix eval --json \
    '.#darwinConfigurations.work-mac.config.home-manager.users.carpenter.launchd.agents.activate-agenix.enable'
)"
if [ "$agenix_launchd_enabled" != false ]; then
  echo "work secrets still decrypt through the asynchronous agenix launchd agent" >&2
  exit 1
fi

agenix_after="$(
  nix eval --json \
    '.#darwinConfigurations.work-mac.config.home-manager.users.carpenter.home.activation.agenixDecrypt.after'
)"
aws_after="$(
  nix eval --json \
    '.#darwinConfigurations.work-mac.config.home-manager.users.carpenter.home.activation.awsConfigGen.after'
)"
skills_after="$(
  nix eval --json \
    '.#darwinConfigurations.work-mac.config.home-manager.users.carpenter.home.activation.skillsSync.after'
)"
if ! jq -e 'index("writeBoundary") != null' <<<"$agenix_after" >/dev/null; then
  echo "agenixDecrypt is not ordered after writeBoundary" >&2
  exit 1
fi
if ! jq -e 'index("agenixDecrypt") != null' <<<"$aws_after" >/dev/null; then
  echo "awsConfigGen is not ordered after synchronous agenix decryption" >&2
  exit 1
fi
if ! jq -e 'index("agenixDecrypt") != null' <<<"$skills_after" >/dev/null; then
  echo "work skillsSync is not ordered after synchronous agenix decryption" >&2
  exit 1
fi

echo "login-shell and agenix/AWS activation ordering contracts are emitted"
