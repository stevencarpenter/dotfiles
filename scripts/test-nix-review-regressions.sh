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
# Anchored on the actual dscl commands, not on the words appearing somewhere.
# The previous form checked only that 'UserShell' and '/bin/zsh' occurred in
# the emitted text — and 'UserShell' also occurs in the block's own comment and
# in a prefix strip, so changing the dscl read to a different attribute left
# the assertion green (found by mutation testing, 2026-07-28). A contract test
# has to match the line that does the work.
# shellcheck disable=SC2016  # these are literals in the EMITTED script, not expansions here
for shell_contract in \
  '_login_shell="/bin/zsh"' \
  '/usr/bin/dscl . -read "$_ds_user" UserShell' \
  '/usr/bin/dscl . -create "$_ds_user" UserShell "$_login_shell"'; do
  if ! rg -Fq "$shell_contract" <<<"$login_activation"; then
    echo "emitted system activation lacks login-shell contract: $shell_contract" >&2
    exit 1
  fi
done

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

# Atuin sync POLICY.
#
# The wiring assertion further down derives its expectations FROM
# lib/machines.nix, so it is blind by construction to the capability itself
# being set wrong — flip a row and the expectation flips with it. This
# invariant is the missing half: a machine whose identity is "work" must never
# sync shell history to the self-hosted server. Stated as a rule over identity
# rather than a hardcoded host list, so it covers rows that do not exist yet
# and names no machine.
sync_policy_violations="$(
  # shellcheck disable=SC2016  # ${n} is Nix interpolation, not shell expansion
  nix eval --raw --file lib/machines.nix --apply \
    'm: builtins.concatStringsSep " " (builtins.filter (s: s != "") (map (n:
       if m.${n}.identity == "work" && m.${n}.caps.atuin then n else ""
     ) (builtins.attrNames m)))'
)"
if [ -n "$sync_policy_violations" ]; then
  echo "work-identity machines must not enable atuin sync: $sync_policy_violations" >&2
  exit 1
fi

# Atuin config variant WIRING.
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

echo "login-shell, Homebrew pin, agenix ordering, atuin sync policy, and atuin variant wiring contracts are emitted"
