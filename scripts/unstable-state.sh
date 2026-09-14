#!/usr/bin/env bash
# Readers for the nixpkgs-unstable soak state: the flake.nix pin and the
# first-seen candidate file.
#
# Shared by update-unstable.sh and unstable-reminder.sh. Readers print parsed
# values and return nonzero on invalid input; callers choose whether to report errors.
#
# test-nix-review-regressions.sh reads independently to detect bugs in these readers.
#
# Sourced, not executed: no exec bit, per scripts/test-exec-bits.sh.
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
