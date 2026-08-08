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
  nix eval --no-update-lock-file --no-eval-cache --raw \
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

# No age secrets anywhere.
#
# The old assertions here pinned the shape of the synchronous agenix decrypt
# node. That bridge is gone: no identity declares age.secrets, so the invariant
# worth guarding is now its absence. `age.secrets` is an option contributed by
# the agenix module — with the module unimported it does not exist at all, so a
# successful eval of the option is itself the regression.
# Only personal-mac remains in-repo. The external (work-identity) case is
# covered by scripts/test-external-overlay-contract.sh, which builds a real
# wrapper consumer and asserts zero age.secrets there.
for host in personal-mac; do
  # POSITIVE CONTROL FIRST. The assertion below is "this eval must fail", which
  # would also be satisfied by a typo in the attribute path, a renamed user, or
  # a broken flake — passing for entirely the wrong reason and silently stopping
  # covering its subject. So prove the surrounding path evaluates before
  # concluding anything from the failure of the age.secrets one.
  if ! nix eval --no-update-lock-file --json \
    ".#darwinConfigurations.${host}.config.home-manager.users.carpenter.home.stateVersion" \
    >/dev/null 2>&1; then
    echo "${host}: control eval failed — the attribute path is wrong, so the" >&2
    echo "  age.secrets assertion below would pass vacuously. Fix the path." >&2
    exit 1
  fi
  if nix eval --no-update-lock-file --json \
    ".#darwinConfigurations.${host}.config.home-manager.users.carpenter.age.secrets" \
    >/dev/null 2>&1; then
    echo "${host} still exposes age.secrets — the agenix module is imported again" >&2
    exit 1
  fi
done

# skillsSync must still be ordered after writeBoundary (home.file symlinks must
# exist before the fan-out reads them) — just no longer after a decrypt node.
skills_after="$(
  nix eval --no-update-lock-file --json \
    '.#darwinConfigurations.personal-mac.config.home-manager.users.carpenter.home.activation.skillsSync.after'
)"
if ! jq -e 'index("writeBoundary") != null' <<<"$skills_after" >/dev/null; then
  echo "skillsSync is not ordered after writeBoundary" >&2
  exit 1
fi
if jq -e 'index("agenixDecrypt") != null' <<<"$skills_after" >/dev/null; then
  echo "skillsSync still depends on the removed agenixDecrypt node" >&2
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
    nix eval --no-update-lock-file --raw \
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

# nixpkgs-unstable SOAK PIN.
#
# The input must name a 40-char rev, never a branch. Reverting it to
# "nixpkgs-unstable" is a one-word edit that silently removes two properties
# and breaks nothing observable: the flake still evaluates, both closures still
# build, and every other assertion here stays green. What it loses is (1) the
# disclosure-soak window — the lock would then track the branch tip, ingesting
# a compromised rev as soon as Hydra certifies it builds — and (2) the
# guarantee that a bare `nix flake update` cannot move this input, which is
# what keeps every bump a reviewable `git diff`. Neither is recoverable by
# inspection after the fact, so it is asserted rather than documented.
#
# Read from flake.nix rather than flake.lock: the lock records a rev either
# way, so it cannot distinguish a rev pin from a branch that merely resolved to
# one. The distinction only exists in the input URL.
unstable_ref="$(
  sed -n 's|.*nixpkgs-unstable\.url = "github:NixOS/nixpkgs/\([^"]*\)".*|\1|p' flake.nix
)"
if [ -z "$unstable_ref" ]; then
  echo "could not read the nixpkgs-unstable input URL from flake.nix" >&2
  exit 1
fi
if ! [[ "$unstable_ref" =~ ^[0-9a-f]{40}$ ]]; then
  echo "nixpkgs-unstable is pinned to '$unstable_ref', not a 40-char rev." >&2
  echo "  The soak window and the no-accidental-bump property both depend on a" >&2
  echo "  rev pin — see the comment in flake.nix. Bump with 'just update-unstable'." >&2
  exit 1
fi

# The URL pin and the exact lock node are one reviewed change. Without this
# comparison, Nix may repair a stale lock during evaluation and let CI validate
# a tree that is absent from the PR diff.
unstable_locked_ref="$(jq -r '.nodes["nixpkgs-unstable"].locked.rev // empty' flake.lock)"
if [ "$unstable_locked_ref" != "$unstable_ref" ]; then
  echo "nixpkgs-unstable pin/lock mismatch:" >&2
  echo "  flake.nix:  $unstable_ref" >&2
  echo "  flake.lock: ${unstable_locked_ref:-<missing>}" >&2
  echo "  Run 'nix flake update nixpkgs-unstable' and review both files." >&2
  exit 1
fi

candidate_file="versions/nixpkgs-unstable-candidate.json"
if ! jq -e '
  .schema == 1
  and .channel == "nixpkgs-unstable"
  and (.status == "pending" or .status == "promoted")
  and (.rev | type == "string" and test("^[0-9a-f]{40}$"))
  and (.channelCommitDate | fromdateiso8601 | type == "number")
  and (.firstSeen | fromdateiso8601 | type == "number")
  and (.soakDays | type == "number" and floor == . and . >= 0 and . <= 3650)
' "$candidate_file" >/dev/null 2>&1; then
  echo "$candidate_file does not contain valid first-seen soak state" >&2
  exit 1
fi
candidate_status="$(jq -r '.status' "$candidate_file")"
candidate_rev="$(jq -r '.rev' "$candidate_file")"
case "$candidate_status" in
promoted)
  if [ "$candidate_rev" != "$unstable_ref" ]; then
    echo "promoted nixpkgs-unstable candidate does not match the reviewed pin" >&2
    exit 1
  fi
  ;;
pending)
  if [ "$candidate_rev" = "$unstable_ref" ]; then
    echo "pending nixpkgs-unstable candidate already equals the reviewed pin" >&2
    echo "  This is an unsoaked or partially promoted state; refusing it." >&2
    exit 1
  fi
  ;;
esac

echo "login-shell, Homebrew pin, no-age-secrets, atuin sync policy, atuin variant wiring, and nixpkgs-unstable soak/pin/lock contracts are emitted"
