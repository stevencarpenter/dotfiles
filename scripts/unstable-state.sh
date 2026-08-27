#!/usr/bin/env bash
# Readers for the nixpkgs-unstable soak state: the flake.nix pin and the
# first-seen candidate file.
#
# Shared by the fail-LOUD promoter (scripts/update-unstable.sh) and the
# fail-SILENT due-promotion reminder (scripts/unstable-reminder.sh) so the two
# halves of the soak policy — what counts as a valid candidate, and when it is
# due — are defined once and cannot drift. Callers keep their own failure
# modes: each reader prints what it parsed and returns nonzero on invalid
# input, and the caller decides whether that is an error or silence.
#
# The contract test scripts/test-nix-review-regressions.sh deliberately keeps
# its own independent copies of these reads: a contract test that sourced the
# implementation's reader would ratify the reader's bugs.
#
# Sourced, not executed — no exec bit, per scripts/test-exec-bits.sh.
# shellcheck shell=bash

# Print the rev that the flake.nix at $1 pins nixpkgs-unstable to. The raw
# extraction is printed either way, so a fail-loud caller can name the bad
# value in its error message; the return status says whether it is a 40-hex
# rev.
unstable_pinned_rev() {
	local rev
	rev="$(sed -n 's|.*nixpkgs-unstable\.url = "github:NixOS/nixpkgs/\([^"]*\)".*|\1|p' "$1")"
	printf '%s\n' "${rev}"
	[[ "${rev}" =~ ^[0-9a-f]{40}$ ]]
}

# Validate the soak candidate at $1 and print its fields as one TSV line:
#   status  rev  channelCommitDate  firstSeen  firstSeenEpoch  soakDays
# Returns nonzero on any malformed field (jq -e then emits no row); stderr is
# suppressed so the caller owns all messaging.
unstable_read_candidate() {
	jq -er '
	  select(.schema == 1)
	  | select(.channel == "nixpkgs-unstable")
	  | select(.status == "pending" or .status == "promoted")
	  | select(.rev | type == "string" and test("^[0-9a-f]{40}$"))
	  | select(.channelCommitDate | type == "string" and (fromdateiso8601 | type == "number"))
	  | select(.firstSeen | type == "string" and (fromdateiso8601 | type == "number"))
	  | select(.soakDays | type == "number" and floor == . and . >= 0 and . <= 3650)
	  | [.status, .rev, .channelCommitDate, .firstSeen,
	     (.firstSeen | fromdateiso8601 | tostring), (.soakDays | tostring)]
	  | @tsv
	' "$1" 2>/dev/null
}
