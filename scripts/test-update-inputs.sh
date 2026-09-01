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
"flake check --no-update-lock-file --no-build --all-systems")
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
# `git diff --stat` exits 0 whether or not anything differs; only --exit-code
# and --quiet return 1. Model the real behavior.
if [ "${1:-}" = "diff" ] || [ "${1:-}" = "--no-pager" ]; then
  exit 0
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
if ! rg -Fxq "flake check --no-update-lock-file --no-build --all-systems" "${TEST_NIX_LOG}"; then
	echo "coordinator did not evaluate the updated inputs before recommending a switch" >&2
	exit 1
fi
if [ "$(wc -l <"${TEST_NIX_LOG}")" -ne 2 ]; then
	echo "coordinator invoked nix beyond the named flake update and the check" >&2
	exit 1
fi
# The evaluation is worthless if it runs before the inputs move.
if [ "$(rg -n -Fx "flake update nixpkgs nix-darwin home-manager" "${TEST_NIX_LOG}" | cut -d: -f1)" \
	-gt "$(rg -n -Fx "flake check --no-update-lock-file --no-build --all-systems" "${TEST_NIX_LOG}" | cut -d: -f1)" ]; then
	echo "coordinator evaluated the inputs before updating them" >&2
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

# A non-numeric or oversized soak window must be refused BEFORE the lock moves;
# update-unstable.sh's own validation runs too late to prevent that.
for bad_arg in abc 4000 -1; do
	rm -f "${TEST_NIX_LOG}" "${TEST_BREW_LOG}"
	lock_before="$(cat "${fixture}/flake.lock")"
	if run_update "${bad_arg}" >/dev/null 2>&1; then
		echo "coordinator accepted an invalid soak window '${bad_arg}'" >&2
		exit 1
	fi
	if [ -s "${TEST_NIX_LOG}" ]; then
		echo "coordinator ran nix before validating soak window '${bad_arg}'" >&2
		exit 1
	fi
	if [ "$(cat "${fixture}/flake.lock")" != "${lock_before}" ]; then
		echo "coordinator mutated flake.lock before rejecting '${bad_arg}'" >&2
		exit 1
	fi
done

# A failing soak step must abort before Homebrew mutates the machine, and must
# still report what the Nix half already changed.
cat >"${fixture}/scripts/update-unstable.sh" <<'EOF'
#!/usr/bin/env bash
exit 3
EOF
chmod +x "${fixture}/scripts/update-unstable.sh"
rm -f "${TEST_BREW_LOG}"
: >"${TEST_BREW_LOG}"
failure_output="$(run_update 2>&1 || true)"
if [ -s "${TEST_BREW_LOG}" ]; then
	echo "coordinator upgraded Homebrew after the soak step failed" >&2
	exit 1
fi
if ! printf '%s' "${failure_output}" | rg -Fq "not switched"; then
	echo "coordinator failed mid-run without reporting the staged lock changes" >&2
	exit 1
fi

echo "rolling-input updater updates 26.05 + soak + brew and never moves unstable itself"
