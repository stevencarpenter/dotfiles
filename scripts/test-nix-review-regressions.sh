#!/usr/bin/env bash
# Semantic checks for review findings that plain flake evaluation cannot see.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

# --no-eval-cache on this one call only: reading this value back OUT of nix's
# eval cache fails with "Bad String Context element ... !out!...-activation-
# carpenter.drv", so the script passed on a cold cache and failed on every
# rerun. Only this attribute is affected — it is a string with heavy
# derivation context; the .enable/.after/.source evals below cache fine and
# keep their caching. CI never saw this because runners start cold.
login_activation="$(
  nix eval --no-eval-cache --raw \
    '.#darwinConfigurations.personal-mac.config.system.activationScripts.postActivation.text'
)"
if ! rg -Fq 'UserShell' <<<"$login_activation" || ! rg -Fq '/bin/zsh' <<<"$login_activation"; then
  echo "emitted system activation does not enforce UserShell=/bin/zsh" >&2
  exit 1
fi

for pin_contract in \
  '/opt/homebrew/var/homebrew/pinned' \
  '/usr/bin/sudo -H -u carpenter' \
  '/usr/bin/env -u SUDO_USER -u SUDO_UID -u SUDO_GID -u SUDO_COMMAND' \
  'is installed but Homebrew could not pin it' \
  'was not installed after Homebrew activation'; do
  if ! rg -Fq "$pin_contract" <<<"$login_activation"; then
    echo "emitted system activation lacks Homebrew pin contract: $pin_contract" >&2
    exit 1
  fi
done

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
skills_after="$(
  nix eval --json \
    '.#darwinConfigurations.work-mac.config.home-manager.users.carpenter.home.activation.skillsSync.after'
)"
if ! jq -e 'index("writeBoundary") != null' <<<"$agenix_after" >/dev/null; then
  echo "agenixDecrypt is not ordered after writeBoundary" >&2
  exit 1
fi
if ! jq -e 'index("agenixDecrypt") != null' <<<"$skills_after" >/dev/null; then
  echo "work skillsSync is not ordered after synchronous agenix decryption" >&2
  exit 1
fi

# Atuin config variant wiring.
#
# modules/home/dotfiles.nix picks the deployed config with
# `if caps.atuin then "sync" else "local"`. Nothing else proves that ternary
# points the right way: the config files are valid either way, both host
# closures build either way, and test-atuin-filter-parity.sh only compares the
# two files against each other as static content. Inverting the ternary would
# therefore pass every other check while sending history to the sync server
# from machines meant to keep it local (found in review, 2026-07-28).
#
# Expectations are derived from lib/machines.nix rather than hardcoded, so a
# new machine row is covered the moment it is added.
expected_variants="$(
  # shellcheck disable=SC2016  # ${n} is Nix interpolation, not shell expansion
  nix eval --raw --file lib/machines.nix --apply \
    'm: builtins.concatStringsSep "\n" (map (n:
       n + " " + (if m.${n}.caps.atuin then "config.sync.toml" else "config.local.toml")
     ) (builtins.attrNames m))'
)"

while read -r host expected_variant; do
  [ -n "$host" ] || continue
  resolved="$(
    nix eval --raw \
      ".#darwinConfigurations.${host}.config.home-manager.users.carpenter.home.file.\".config/atuin/config.toml\".source"
  )"
  # home-manager names the out-of-store symlink derivation after the source
  # basename, so the store path records which variant was selected.
  case "$resolved" in
  *"$expected_variant") ;;
  *)
    echo "${host} deploys the wrong atuin config variant: expected ${expected_variant}, resolved ${resolved}" >&2
    exit 1
    ;;
  esac
done <<<"$expected_variants"

echo "login-shell, Homebrew pin, agenix activation ordering, and atuin variant wiring contracts are emitted"
