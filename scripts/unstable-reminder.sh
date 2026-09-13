#!/usr/bin/env bash
# Print a notice when the pending nixpkgs-unstable soak candidate is due.
#
# rebuild.sh shows this reminder before switching; promotion requires update-unstable.sh.
#
# Contract: silent unless ALL of these hold: jq on PATH, candidate file
# present and valid per the shared reader (scripts/unstable-state.sh, the same
# validity the promoter enforces), status "pending", candidate rev differs
# from a parseable flake.nix pin, and firstSeen + soakDays elapsed. Every
# other state exits 0 without output; this must never block a routine
# rebuild.
#
# UPDATE_UNSTABLE_NOW_EPOCH (epoch seconds) overrides the clock for tests:
# the same seam scripts/update-unstable.sh uses.
set -uo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
candidate_file="${repo_root}/versions/nixpkgs-unstable-candidate.json"

# Pin/candidate readers shared with the fail-loud promoter; every reader
# failure below maps to the silent path instead of an error.
# shellcheck source=scripts/unstable-state.sh
source "${repo_root}/scripts/unstable-state.sh"

command -v jq >/dev/null 2>&1 || exit 0
[ -f "${candidate_file}" ] || exit 0

now_epoch="${UPDATE_UNSTABLE_NOW_EPOCH:-$(date -u +%s)}"
[[ "${now_epoch}" =~ ^[0-9]+$ ]] || exit 0

# An unparseable pin cannot establish whether the candidate was already promoted.
pinned_rev="$(unstable_pinned_rev "${repo_root}/flake.nix")" || exit 0
fields="$(unstable_read_candidate "${candidate_file}")" || exit 0
IFS=$'\t' read -r status rev _channel_date _first_seen first_seen_epoch soak_days <<<"${fields}"

[[ "${status}" == "pending" ]] || exit 0
[ "${pinned_rev}" != "${rev}" ] || exit 0

due_epoch=$((first_seen_epoch + soak_days * 86400))
[ "${now_epoch}" -ge "${due_epoch}" ] || exit 0
overdue_days=$(((now_epoch - due_epoch) / 86400))

printf 'note: nixpkgs-unstable candidate %s is due for promotion (%s day(s) overdue).\n' \
	"${rev}" "${overdue_days}"
printf '      run '"'"'just update-unstable'"'"' to promote it (builds + closure diff, never switches)\n'
exit 0
