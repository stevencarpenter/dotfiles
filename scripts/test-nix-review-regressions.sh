#!/usr/bin/env bash
# Semantic checks for review findings that plain flake evaluation cannot see.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

# Exercise activation with explicit fixture capabilities, independent of the
# current machines' names, users, and enabled features.
host_expr="
let
  f = builtins.getFlake \"git+file://${repo_root}\";
  caps = builtins.listToAttrs (map (name: { inherit name; value = false; }) f.lib.canonicalCapKeys)
    // { tiling = true; skills = true; };
in (f.lib.mkHost \"contract-regressions\" {
  system = \"aarch64-darwin\";
  user = \"contract-test\";
  identity = \"personal\";
  inherit caps;
}).config
"
home_expr="(${host_expr}).home-manager.users.\"contract-test\""

# Parent checks must precede both collision handling and any activation writes.
nix eval --no-update-lock-file --impure --json --expr \
  "(${home_expr}).home.activation.checkLinkParents.before" \
  | jq -e 'index("checkLinkTargets") != null and index("writeBoundary") != null' >/dev/null
nix eval --no-update-lock-file --impure --json --expr \
  "(${host_expr}).home-manager.backupFileExtension" | jq -e '. == null' >/dev/null
bash scripts/test-home-link-parents.sh

# Parse the deployed AeroSpace configuration, then execute the emitted Home
# Manager activation against a recording Homebrew service manager.
for aerospace_config in home/.config/aerospace/aerospace.*.toml; do
  nix eval --impure --json --expr \
    "builtins.fromTOML (builtins.readFile ./${aerospace_config})" \
    | jq -e '.["after-startup-command"] | all(test("sketchybar") | not)' >/dev/null
done
fixture="$(mktemp -d)"
trap 'rm -rf "$fixture"' EXIT

# Execute the emitted hook as well as the standalone checker, so deleting its
# invocation cannot leave the regression test passing.
nix eval --no-update-lock-file --no-eval-cache --impure --raw --expr \
  "(${home_expr}).home.activation.checkLinkParents.data" >"$fixture/check-parents"
mkdir -p "$fixture/generation/home-files/.config/journal" "$fixture/home/.config" "$fixture/source"
ln -s "$fixture/source" "$fixture/home/.config/journal"
if HOME="$fixture/home" newGenPath="$fixture/generation" bash "$fixture/check-parents" >"$fixture/parent-error" 2>&1; then
  echo 'emitted parent guard accepted a stale directory link' >&2
  exit 1
fi
rg -Fq 'refuses to write through symlinked parent' "$fixture/parent-error"
rm "$fixture/home/.config/journal"
mkdir "$fixture/home/.config/journal"
HOME="$fixture/home" newGenPath="$fixture/generation" bash "$fixture/check-parents"

mkdir -p "$fixture/bin"
cat >"$fixture/bin/brew" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
[[ -z ${SUDO_USER+x}${SUDO_UID+x}${SUDO_GID+x}${SUDO_COMMAND+x} ]]
printf '%s\n' "$*" >>"$TEST_BREW_LOG"
[[ "$*" == 'services restart sketchybar' ]]
SH
cp "$fixture/bin/brew" "$fixture/bin/sketchybar"
chmod +x "$fixture/bin/"*
nix eval --no-update-lock-file --no-eval-cache --impure --raw --expr \
  "(${home_expr}).home.activation.startTilingStack.data" \
  | sed -e "s|/opt/homebrew/bin/|$fixture/bin/|g" \
    -e "s|/Applications/AeroSpace.app/Contents/MacOS/AeroSpace|$fixture/absent-aerospace|g" \
    >"$fixture/activate"
TEST_BREW_LOG="$fixture/brew.log" SUDO_USER=root SUDO_UID=0 SUDO_GID=0 SUDO_COMMAND=test \
  bash "$fixture/activate"
printf 'services restart sketchybar\n' >"$fixture/expected"
cmp "$fixture/expected" "$fixture/brew.log"

# This activation string's derivation context fails when read from the eval cache.
# Disable caching for this attribute only.
login_activation="$(
  nix eval --no-update-lock-file --no-eval-cache --impure --raw --expr \
    "(${host_expr}).system.activationScripts.postActivation.text"
)"
# Match executable dscl commands; matching words also accepts comments.
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
  '/usr/bin/sudo -H -u contract-test' \
  '/usr/bin/env -u SUDO_USER -u SUDO_UID -u SUDO_GID -u SUDO_COMMAND' \
  'is installed but Homebrew could not pin it' \
  'was not installed after Homebrew activation'; do
  if ! rg -Fq "$pin_contract" <<<"$login_activation"; then
    echo "emitted system activation lacks Homebrew pin contract: $pin_contract" >&2
    exit 1
  fi
done

# age.secrets must be undefined because agenix is not imported.
# The external work wrapper is checked by test-external-overlay-contract.sh.
machine_users="$(nix eval --json --file lib/machines.nix | jq -r 'to_entries[] | "\(.key) \(.value.user)"')"
while read -r host user; do
  # Verify the parent attribute first so unrelated eval failures cannot pass.
  if ! nix eval --no-update-lock-file --json \
    ".#darwinConfigurations.${host}.config.home-manager.users.${user}.home.stateVersion" \
    >/dev/null 2>&1; then
    echo "${host}: control eval failed: the attribute path is wrong, so the" >&2
    echo "  age.secrets assertion below would pass vacuously. Fix the path." >&2
    exit 1
  fi
  if nix eval --no-update-lock-file --json \
    ".#darwinConfigurations.${host}.config.home-manager.users.${user}.age.secrets" \
    >/dev/null 2>&1; then
    echo "${host} still exposes age.secrets: the agenix module is imported again" >&2
    exit 1
  fi
done <<<"$machine_users"

# skillsSync requires home.file symlinks created by writeBoundary.
skills_after="$(
  nix eval --no-update-lock-file --impure --json --expr \
    "(${home_expr}).home.activation.skillsSync.after"
)"
if ! jq -e 'index("writeBoundary") != null' <<<"$skills_after" >/dev/null; then
  echo "skillsSync is not ordered after writeBoundary" >&2
  exit 1
fi
if jq -e 'index("agenixDecrypt") != null' <<<"$skills_after" >/dev/null; then
  echo "skillsSync still depends on the removed agenixDecrypt node" >&2
  exit 1
fi

# Work identities must never sync history to the self-hosted Atuin server.
# Check this independently of capability-derived wiring expectations.
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

# Verify each host deploys the Atuin variant selected by caps.atuin.
# Both variants build successfully, so evaluation alone cannot detect inversion.
expected_variants="$(
  # shellcheck disable=SC2016  # ${n} is Nix interpolation, not shell expansion
  nix eval --raw --file lib/machines.nix --apply \
    'm: builtins.concatStringsSep "\n" (map (n:
       n + " " + m.${n}.user + " " + (if m.${n}.caps.atuin then "config.sync.toml" else "config.local.toml")
     ) (builtins.attrNames m))'
)"

while read -r host user expected_variant; do
  [ -n "$host" ] || continue
  resolved="$(
    nix eval --no-update-lock-file --raw \
      ".#darwinConfigurations.${host}.config.home-manager.users.${user}.home.file.\".config/atuin/config.toml\".source"
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

# Require a 40-character revision so nix flake update cannot bypass the soak.
# Inspect flake.nix; flake.lock records a revision even for branch inputs.
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
  echo "  rev pin: see the comment in flake.nix. Bump with 'just update-unstable'." >&2
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
