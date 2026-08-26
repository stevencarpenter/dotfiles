#!/usr/bin/env bash
# Advance nixpkgs-unstable through a first-seen soak queue, build the result
# WITHOUT switching, and print the closure diff for review.
#
# Why a first-seen queue rather than commit timestamps:
#
# flake.lock's narHash proves that fetched content matches the locked tree. It
# does not prove that the tree was benign when it was locked. Likewise, a
# commit's author/committer timestamp does not say when the nixpkgs-unstable
# channel first exposed that commit: timestamps can be old before a commit is
# added to the channel. A GitHub `commits?until=...` query therefore is not a
# soak window.
#
# This script uses two deliberate invocations instead:
#
#   1. Record the channel's current Hydra-certified tip and this machine's
#      first-seen time in versions/nixpkgs-unstable-candidate.json.
#   2. On a later invocation, promote that exact SHA only after the requested
#      elapsed time and only if it is still an ancestor of the channel tip.
#
# The state file is reviewable policy evidence, not a cryptographic timestamp
# authority. Do not hand-edit its firstSeen value. A hostile local operator can
# bypass any local policy; this control prevents accidental immediate adoption
# of a newly exposed, backdated channel commit.
#
# Only `fastMovingPackages` in modules/home/packages.nix consume this input.
# Keep that allowlist short: each package brings its unstable runtime closure.
#
# Usage:
#   scripts/update-unstable.sh              # record/promote with 7-day soak
#   scripts/update-unstable.sh 14           # wider window
#   scripts/update-unstable.sh 7 personal-mac
#
# A candidate-recording run does not evaluate or build. A promotion builds but
# never switches. Applying the built result remains a separate `./rebuild.sh`.
set -euo pipefail

SOAK_DAYS="${1:-7}"
if ! [[ "${SOAK_DAYS}" =~ ^[0-9]+$ ]]; then
	echo "error: soak days must be a non-negative integer, got '${SOAK_DAYS}'" >&2
	exit 2
fi
if [ "${SOAK_DAYS}" -gt 3650 ]; then
	echo "error: soak days must not exceed 3650, got '${SOAK_DAYS}'" >&2
	exit 2
fi

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
cd "${REPO_ROOT}"

# Pin/candidate readers shared with the fail-silent reminder; soak validity is
# defined once in the library so the two halves cannot drift.
# shellcheck source=scripts/unstable-state.sh
source "${REPO_ROOT}/scripts/unstable-state.sh"

CANDIDATE_FILE="versions/nixpkgs-unstable-candidate.json"
if { [ -n "${UPDATE_UNSTABLE_API_ROOT:-}" ] || [ -n "${UPDATE_UNSTABLE_NOW_EPOCH:-}" ]; } \
	&& [ "${UPDATE_UNSTABLE_TEST_MODE:-}" != 1 ]; then
	echo "error: UPDATE_UNSTABLE_API_ROOT/NOW_EPOCH are test-only overrides" >&2
	exit 2
fi
API_ROOT="${UPDATE_UNSTABLE_API_ROOT:-https://api.github.com}"
NOW_EPOCH="${UPDATE_UNSTABLE_NOW_EPOCH:-$(date -u +%s)}"
if ! [[ "${NOW_EPOCH}" =~ ^[0-9]+$ ]]; then
	echo "error: UPDATE_UNSTABLE_NOW_EPOCH must be an epoch integer" >&2
	exit 2
fi
NOW_ISO="$(jq -nr --argjson now "${NOW_EPOCH}" '$now | strftime("%Y-%m-%dT%H:%M:%SZ")')"

# The reader prints the raw extraction even on failure so this message can
# name it; the exit status carries valid/invalid.
if ! OLD_REV="$(unstable_pinned_rev flake.nix)"; then
	echo "error: flake.nix pins nixpkgs-unstable to '${OLD_REV}', not a 40-char rev" >&2
	exit 1
fi
LOCKED_REV="$(jq -r '.nodes["nixpkgs-unstable"].locked.rev // empty' flake.lock)"
if ! [[ "${LOCKED_REV}" =~ ^[0-9a-f]{40}$ ]]; then
	echo "error: flake.lock has no exact nixpkgs-unstable locked rev" >&2
	exit 1
fi
if [ "${OLD_REV}" != "${LOCKED_REV}" ]; then
	echo "error: nixpkgs-unstable pin/lock mismatch; refusing to queue or promote" >&2
	echo "       flake.nix=${OLD_REV}" >&2
	echo "       flake.lock=${LOCKED_REV}" >&2
	exit 1
fi

api_get() {
	local url="$1"
	local -a args=(-fsSL --retry 2 -H "Accept: application/vnd.github+json")
	if [ -n "${GITHUB_TOKEN:-}" ]; then
		args+=(-H "Authorization: Bearer ${GITHUB_TOKEN}")
	fi
	curl "${args[@]}" "${url}"
}

write_candidate() {
	local status="$1"
	local rev="$2"
	local channel_date="$3"
	local first_seen="$4"
	local soak_days="$5"
	local tmp

	mkdir -p "$(dirname "${CANDIDATE_FILE}")"
	tmp="$(mktemp "${CANDIDATE_FILE}.tmp.XXXXXX")"
	jq -n \
		--arg status "${status}" \
		--arg rev "${rev}" \
		--arg channel_date "${channel_date}" \
		--arg first_seen "${first_seen}" \
		--argjson soak_days "${soak_days}" \
		'{
          schema: 1,
          channel: "nixpkgs-unstable",
          status: $status,
          rev: $rev,
          channelCommitDate: $channel_date,
          firstSeen: $first_seen,
          soakDays: $soak_days
        }' >"${tmp}"
	mv "${tmp}" "${CANDIDATE_FILE}"
}

record_candidate() {
	local reason="$1"
	echo "==> ${reason}"
	if [ "${CURRENT_REV}" = "${OLD_REV}" ]; then
		write_candidate promoted "${CURRENT_REV}" "${CURRENT_DATE}" "${NOW_ISO}" "${SOAK_DAYS}"
		echo "    ${CURRENT_REV} is already the reviewed pin; marked promoted."
		return
	fi
	write_candidate pending "${CURRENT_REV}" "${CURRENT_DATE}" "${NOW_ISO}" "${SOAK_DAYS}"
	echo "    candidate : ${CURRENT_REV} (${CURRENT_DATE})"
	echo "    first seen: ${NOW_ISO}"
	echo "    No flake input changed. Commit the candidate state, then run this"
	echo "    command again after ${SOAK_DAYS} days to promote that exact rev."
}

TIP_RESPONSE="$(api_get "${API_ROOT}/repos/NixOS/nixpkgs/commits/nixpkgs-unstable")" || {
	echo "error: could not resolve the current nixpkgs-unstable channel tip" >&2
	exit 1
}
CURRENT_REV="$(jq -r '.sha // empty' <<<"${TIP_RESPONSE}")"
CURRENT_DATE="$(jq -r '.commit.committer.date // empty' <<<"${TIP_RESPONSE}")"
if ! [[ "${CURRENT_REV}" =~ ^[0-9a-f]{40}$ ]] || [ -z "${CURRENT_DATE}" ]; then
	echo "error: GitHub returned an invalid nixpkgs-unstable channel tip" >&2
	exit 1
fi

if [ ! -f "${CANDIDATE_FILE}" ]; then
	record_candidate "Recording the current Hydra-certified channel tip"
	exit 0
fi

if ! CANDIDATE_FIELDS="$(unstable_read_candidate "${CANDIDATE_FILE}")"; then
	echo "error: ${CANDIDATE_FILE} is malformed; refusing to replace or promote it" >&2
	exit 1
fi
IFS=$'\t' read -r CANDIDATE_STATUS CANDIDATE_REV CANDIDATE_DATE FIRST_SEEN FIRST_SEEN_EPOCH CANDIDATE_SOAK_DAYS <<<"${CANDIDATE_FIELDS}"

if [ "${FIRST_SEEN_EPOCH}" -gt "${NOW_EPOCH}" ]; then
	echo "error: candidate firstSeen ${FIRST_SEEN} is in the future" >&2
	exit 1
fi

case "${CANDIDATE_STATUS}" in
promoted)
	if [ "${CANDIDATE_REV}" != "${OLD_REV}" ]; then
		echo "error: promoted candidate does not match the reviewed pin" >&2
		exit 1
	fi
	;;
pending)
	if [ "${CANDIDATE_REV}" = "${OLD_REV}" ]; then
		echo "error: pending candidate already equals the reviewed pin; refusing bypass" >&2
		exit 1
	fi
	;;
esac

if [ "${CANDIDATE_STATUS}" = promoted ]; then
	if [ "${CURRENT_REV}" = "${CANDIDATE_REV}" ]; then
		echo "==> Channel has not advanced beyond promoted rev ${CANDIDATE_REV}; nothing to do."
		exit 0
	fi
	record_candidate "The channel advanced; recording its new tip"
	exit 0
fi

# Compare immutable SHAs so a branch movement between the tip lookup and this
# request cannot make the reachability answer refer to a different tree.
COMPARE_RESPONSE="$(api_get "${API_ROOT}/repos/NixOS/nixpkgs/compare/${CANDIDATE_REV}...${CURRENT_REV}")" || {
	echo "error: could not verify candidate reachability from the channel tip" >&2
	exit 1
}
COMPARE_STATUS="$(jq -r '.status // empty' <<<"${COMPARE_RESPONSE}")"
case "${COMPARE_STATUS}" in
ahead | identical) ;;
behind | diverged)
	record_candidate "The pending candidate left channel ancestry; resetting the soak"
	exit 0
	;;
*)
	echo "error: GitHub returned invalid compare status '${COMPARE_STATUS}'" >&2
	exit 1
	;;
esac

# A later invocation may make an existing policy stricter, but a shorter CLI
# argument never weakens the duration committed with the candidate.
if [ "${SOAK_DAYS}" -gt "${CANDIDATE_SOAK_DAYS}" ]; then
	CANDIDATE_SOAK_DAYS="${SOAK_DAYS}"
	write_candidate pending "${CANDIDATE_REV}" "${CANDIDATE_DATE}" "${FIRST_SEEN}" "${CANDIDATE_SOAK_DAYS}"
	echo "==> Extended candidate soak to ${CANDIDATE_SOAK_DAYS} days."
elif [ "${SOAK_DAYS}" -lt "${CANDIDATE_SOAK_DAYS}" ]; then
	echo "==> Candidate retains its committed ${CANDIDATE_SOAK_DAYS}-day soak; ignoring shorter ${SOAK_DAYS}-day request."
fi

AGE_SECONDS="$((NOW_EPOCH - FIRST_SEEN_EPOCH))"
SOAK_SECONDS="$((CANDIDATE_SOAK_DAYS * 86400))"
if [ "${AGE_SECONDS}" -lt "${SOAK_SECONDS}" ]; then
	REMAINING_SECONDS="$((SOAK_SECONDS - AGE_SECONDS))"
	echo "==> Candidate ${CANDIDATE_REV} is still soaking."
	echo "    first seen: ${FIRST_SEEN}"
	echo "    elapsed   : ${AGE_SECONDS}s"
	echo "    remaining : ${REMAINING_SECONDS}s"
	exit 0
fi

# Host detection shares the repo-wide matcher; add machines in
# scripts/host-detect.sh only.
# shellcheck source=scripts/host-detect.sh
source "${REPO_ROOT}/scripts/host-detect.sh"
HOST="${2:-${DOTFILES_HOST:-$(detect_host || true)}}"
if [ -z "${HOST:-}" ]; then
	echo "unknown host; pass explicitly: update-unstable.sh <days> <personal-mac>" >&2
	exit 1
fi

echo "==> Promoting first-seen candidate after ${CANDIDATE_SOAK_DAYS} days"
echo "    flake.nix: ${OLD_REV}"
echo "    flake.lock: ${LOCKED_REV}"
echo "    target    : ${CANDIDATE_REV} (${CANDIDATE_DATE})"
echo "    first seen: ${FIRST_SEEN}"

# Keep the reviewed pin and lock transactional. A failed lock update, build, or
# closure comparison restores both files and leaves the candidate pending.
promotion_tmp="$(mktemp -d "${TMPDIR:-/tmp}/update-unstable-promotion.XXXXXX")"
cp -p flake.nix "${promotion_tmp}/flake.nix"
cp -p flake.lock "${promotion_tmp}/flake.lock"
promotion_complete=0
finish_promotion() {
	local status="$?"
	if [ "${promotion_complete}" -ne 1 ]; then
		cp -p "${promotion_tmp}/flake.nix" flake.nix || true
		cp -p "${promotion_tmp}/flake.lock" flake.lock || true
	fi
	rm -rf -- "${promotion_tmp}"
	exit "${status}"
}
trap finish_promotion EXIT

if [ "${OLD_REV}" != "${CANDIDATE_REV}" ]; then
	tmp="${promotion_tmp}/flake.next"
	sed \
		-e "s|nixpkgs-unstable\.url = \"github:NixOS/nixpkgs/[^\"]*\";.*|nixpkgs-unstable.url = \"github:NixOS/nixpkgs/${CANDIDATE_REV}\"; # nixpkgs-unstable @ ${CANDIDATE_DATE%%T*}|" \
		flake.nix >"${tmp}"
	changed="$(diff flake.nix "${tmp}" | rg -c --include-zero '^<' || true)"
	if [ "${changed}" -ne 1 ]; then
		echo "error: rewrite changed ${changed} lines, expected exactly 1" >&2
		exit 1
	fi
	chmod 0644 "${tmp}"
	mv "${tmp}" flake.nix
fi

if [ "${LOCKED_REV}" != "${CANDIDATE_REV}" ]; then
	echo "==> Updating only the nixpkgs-unstable lock node"
	nix flake update nixpkgs-unstable
	LOCKED_REV="$(jq -r '.nodes["nixpkgs-unstable"].locked.rev // empty' flake.lock)"
	if [ "${LOCKED_REV}" != "${CANDIDATE_REV}" ]; then
		echo "error: flake.lock resolved ${LOCKED_REV:-<empty>}, expected ${CANDIDATE_REV}" >&2
		exit 1
	fi
fi

echo "==> Building ${HOST} (not switching)"
out="$(nix build --no-link --print-out-paths --no-update-lock-file ".#darwinConfigurations.${HOST}.system")"

echo
echo "==> Closure diff vs the running system"
echo "    (an unexpected package name here is a real signal — review before switching)"
nix store diff-closures /run/current-system "${out}"

write_candidate promoted "${CANDIDATE_REV}" "${CANDIDATE_DATE}" "${FIRST_SEEN}" "${CANDIDATE_SOAK_DAYS}"
promotion_complete=1

cat <<EOF

==> Built, not switched. Candidate marked promoted.
    Review the closure and \`git diff flake.nix flake.lock ${CANDIDATE_FILE}\`, then apply with:
      ./rebuild.sh
EOF
