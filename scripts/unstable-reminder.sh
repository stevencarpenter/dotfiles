#!/usr/bin/env bash
# Print a notice when the pending nixpkgs-unstable soak candidate is due.
#
# scripts/update-unstable.sh promotes only when someone runs it; nothing else
# surfaces a due promotion, so an eligible candidate can sit unnoticed for
# weeks. rebuild.sh invokes this before switching so the operator who has to
# act sees it at the moment they act.
#
# Contract: silent unless ALL of these hold — jq on PATH, candidate file
# present and parseable, status "pending", candidate rev differs from the
# flake.nix pin, and firstSeen + soakDays elapsed. Every other state exits 0
# quietly: this must never block or noise a routine rebuild.
#
# UPDATE_UNSTABLE_NOW_EPOCH (epoch seconds) overrides the clock for tests —
# the same seam scripts/update-unstable.sh uses.
set -uo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
candidate_file="${repo_root}/versions/nixpkgs-unstable-candidate.json"
now_epoch="${UPDATE_UNSTABLE_NOW_EPOCH:-$(date -u +%s)}"

command -v jq >/dev/null 2>&1 || exit 0
[ -f "${candidate_file}" ] || exit 0
[[ "${now_epoch}" =~ ^[0-9]+$ ]] || exit 0

# One jq pass over the fields the decision needs; fromdateiso8601 doubles as
# the timestamp-format guard, so a malformed file lands in the silent path.
fields="$(jq -r '
  [.status, .rev, (.soakDays | tostring),
   (.firstSeen | fromdateiso8601 | tostring)]
  | @tsv
' "${candidate_file}" 2>/dev/null)" || exit 0

status="${fields%%$'\t'*}"
rest="${fields#*$'\t'}"
rev="${rest%%$'\t'*}"
rest="${rest#*$'\t'}"
soak_days="${rest%%$'\t'*}"
first_seen_epoch="${rest#*$'\t'}"

[[ "${status}" == "pending" ]] || exit 0
[[ "${rev}" =~ ^[0-9a-f]{40}$ ]] || exit 0
[[ "${soak_days}" =~ ^[0-9]+$ ]] || exit 0
[[ "${first_seen_epoch}" =~ ^[0-9]+$ ]] || exit 0

pinned_rev="$(sed -n 's|.*nixpkgs-unstable\.url = "github:NixOS/nixpkgs/\([^"]*\)".*|\1|p' "${repo_root}/flake.nix")"
[ "${pinned_rev}" != "${rev}" ] || exit 0

due_epoch=$((first_seen_epoch + soak_days * 86400))
[ "${now_epoch}" -ge "${due_epoch}" ] || exit 0
overdue_days=$(((now_epoch - due_epoch) / 86400))

printf 'note: nixpkgs-unstable candidate %s is due for promotion (%s day(s) overdue).\n' \
	"${rev}" "${overdue_days}"
printf '      run '"'"'just update-unstable'"'"' to promote it (builds + closure diff, never switches)\n'
exit 0
