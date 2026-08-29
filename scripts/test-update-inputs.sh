#!/usr/bin/env bash
# Hermetic coverage for the default rolling-input updater: 26.05 flake inputs,
# the unstable soak script, and Homebrew — never a switch, never a bare
# `nix flake update`, never `nix flake update nixpkgs-unstable`.
#
# Production change that fails this test: coordinating those steps with a
# nameless `nix flake update`, updating the unstable lock node directly, or
# invoking darwin-rebuild/switch.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
fixture="$(mktemp -d)"
trap 'rm -rf "${fixture}"' EXIT

mkdir -p "${fixture}/scripts" "${fixture}/versions" "${fixture}/bin"
cp "${repo_root}/scripts/update-inputs.sh" "${fixture}/scripts/update-inputs.sh"
chmod +x "${fixture}/scripts/update-inputs.sh"

unstable_rev="cccccccccccccccccccccccccccccccccccccccc"
cat >"${fixture}/flake.nix" <<EOF
{
  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-26.05-darwin";
  inputs.nix-darwin.url = "github:nix-darwin/nix-darwin/nix-darwin-26.05";
  inputs.home-manager.url = "github:nix-community/home-manager/release-26.05";
  inputs.nixpkgs-unstable.url = "github:NixOS/nixpkgs/${unstable_rev}"; # nixpkgs-unstable @ 2026-07-31
}
EOF
cat >"${fixture}/flake.lock" <<EOF
{
  "nodes": {
    "home-manager": {"locked": {"rev": "old-home-manager"}},
    "nix-darwin": {"locked": {"rev": "old-nix-darwin"}},
    "nixpkgs": {"locked": {"rev": "old-nixpkgs"}},
    "nixpkgs-unstable": {"locked": {"rev": "${unstable_rev}"}}
  }
}
EOF
printf '%s\n' '{"schema":1,"channel":"nixpkgs-unstable","status":"pending","rev":"pendingcandidate"}' \
	>"${fixture}/versions/nixpkgs-unstable-candidate.json"

cat >"${fixture}/scripts/update-unstable.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >>"${TEST_UNSTABLE_LOG}"
EOF
chmod +x "${fixture}/scripts/update-unstable.sh"

cat >"${fixture}/bin/nix" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >>"${TEST_NIX_LOG}"
case "$*" in
"flake update nixpkgs nix-darwin home-manager")
  tmp="$(mktemp)"
  jq '
    .nodes.nixpkgs.locked.rev = "new-nixpkgs"
    | .nodes["nix-darwin"].locked.rev = "new-nix-darwin"
    | .nodes["home-manager"].locked.rev = "new-home-manager"
  ' flake.lock >"${tmp}"
  mv "${tmp}" flake.lock
  ;;
*)
  echo "unexpected nix command: $*" >&2
  exit 1
  ;;
esac
EOF

cat >"${fixture}/bin/brew" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >>"${TEST_BREW_LOG}"
printf 'HOMEBREW_NO_ANALYTICS=%s\n' "${HOMEBREW_NO_ANALYTICS-}" >>"${TEST_BREW_ENV_LOG}"
printf 'HOMEBREW_NO_ENV_HINTS=%s\n' "${HOMEBREW_NO_ENV_HINTS-}" >>"${TEST_BREW_ENV_LOG}"
EOF

cat >"${fixture}/bin/git" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >>"${TEST_GIT_LOG}"
# Real git diff exits 1 when the lock changed. The coordinator must still
# exit 0 after a successful update.
if [ "${1:-}" = "diff" ] || [ "${1:-}" = "--no-pager" ]; then
  exit 1
fi
echo "unexpected git command: $*" >&2
exit 1
EOF
chmod +x "${fixture}/bin/nix" "${fixture}/bin/brew" "${fixture}/bin/git"

export PATH="${fixture}/bin:${PATH}"
export TEST_NIX_LOG="${fixture}/nix.log"
export TEST_BREW_LOG="${fixture}/brew.log"
export TEST_BREW_ENV_LOG="${fixture}/brew.env.log"
export TEST_UNSTABLE_LOG="${fixture}/unstable.log"
export TEST_GIT_LOG="${fixture}/git.log"

run_update() {
	(
		cd "${fixture}"
		scripts/update-inputs.sh "$@"
	)
}

run_update 14

if ! rg -Fxq "flake update nixpkgs nix-darwin home-manager" "${TEST_NIX_LOG}"; then
	echo "coordinator did not update the 26.05 flake inputs together" >&2
	exit 1
fi
if [ "$(wc -l <"${TEST_NIX_LOG}")" -ne 1 ]; then
	echo "coordinator invoked nix more than the one named flake update" >&2
	exit 1
fi
if ! rg -Fxq "14" "${TEST_UNSTABLE_LOG}"; then
	echo "coordinator did not forward soak days to update-unstable.sh" >&2
	exit 1
fi
if [ "$(wc -l <"${TEST_UNSTABLE_LOG}")" -ne 1 ]; then
	echo "coordinator invoked update-unstable.sh more than once" >&2
	exit 1
fi
if ! rg -Fxq "update" "${TEST_BREW_LOG}"; then
	echo "coordinator missed brew update" >&2
	exit 1
fi
if ! rg -Fxq "bundle install --upgrade" "${TEST_BREW_LOG}"; then
	echo "coordinator missed brew bundle install --upgrade" >&2
	exit 1
fi
if [ "$(wc -l <"${TEST_BREW_LOG}")" -ne 2 ]; then
	echo "coordinator invoked brew with unexpected extra commands" >&2
	exit 1
fi
if ! rg -Fq "HOMEBREW_NO_ANALYTICS=1" "${TEST_BREW_ENV_LOG}"; then
	echo "brew update/upgrade ran with analytics enabled" >&2
	exit 1
fi
if ! rg -Fq "HOMEBREW_NO_ENV_HINTS=1" "${TEST_BREW_ENV_LOG}"; then
	echo "brew update/upgrade ran without HOMEBREW_NO_ENV_HINTS" >&2
	exit 1
fi

if rg -Fqi "switch" "${TEST_NIX_LOG}" "${TEST_GIT_LOG}" "${TEST_UNSTABLE_LOG}"; then
	echo "coordinator invoked a switch" >&2
	exit 1
fi
if rg -Fqi "darwin-rebuild" "${TEST_NIX_LOG}" "${TEST_UNSTABLE_LOG}"; then
	echo "coordinator invoked darwin-rebuild" >&2
	exit 1
fi

if ! rg -Fq "github:NixOS/nixpkgs/${unstable_rev}" "${fixture}/flake.nix"; then
	echo "coordinator moved the nixpkgs-unstable flake.nix pin without the soak script" >&2
	exit 1
fi
if [ "$(jq -r '.nodes["nixpkgs-unstable"].locked.rev' "${fixture}/flake.lock")" != "${unstable_rev}" ]; then
	echo "coordinator moved the nixpkgs-unstable lock node without the soak script" >&2
	exit 1
fi
if [ "$(jq -r '.nodes.nixpkgs.locked.rev' "${fixture}/flake.lock")" != "new-nixpkgs" ] \
	|| [ "$(jq -r '.nodes["nix-darwin"].locked.rev' "${fixture}/flake.lock")" != "new-nix-darwin" ] \
	|| [ "$(jq -r '.nodes["home-manager"].locked.rev' "${fixture}/flake.lock")" != "new-home-manager" ]; then
	echo "26.05 lock nodes were not updated" >&2
	exit 1
fi

echo "rolling-input updater updates 26.05 + soak + brew and never moves unstable itself"
