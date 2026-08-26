#!/usr/bin/env bash
# Hermetic coverage for scripts/unstable-reminder.sh — the due-promotion
# notice rebuild.sh prints before switching. The reminder's contract is to be
# silent in every state except a pending candidate whose soak window has
# elapsed against a flake.nix pin that still differs from the candidate rev.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
fixture="$(mktemp -d)"
trap 'rm -rf "${fixture}"' EXIT

# Copy the script into the fixture so repo_root resolves there, mirroring how
# test-update-unstable-soak.sh isolates update-unstable.sh.
mkdir -p "${fixture}/scripts" "${fixture}/versions"
cp "${repo_root}/scripts/unstable-reminder.sh" "${fixture}/scripts/unstable-reminder.sh"
chmod +x "${fixture}/scripts/unstable-reminder.sh"

pin_rev="cccccccccccccccccccccccccccccccccccccccc"
cand_rev="aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"

fail() {
	echo "FAIL: $*" >&2
	exit 1
}

run_reminder() {
	local now="$1" pin="$2" candidate_json="${3:-}" out
	if [ -n "${candidate_json}" ]; then
		printf '%s\n' "${candidate_json}" \
			>"${fixture}/versions/nixpkgs-unstable-candidate.json"
	else
		rm -f "${fixture}/versions/nixpkgs-unstable-candidate.json"
	fi
	cat >"${fixture}/flake.nix" <<EOF
{
  inputs.nixpkgs-unstable.url = "github:NixOS/nixpkgs/${pin}";
}
EOF
	out="$(UPDATE_UNSTABLE_NOW_EPOCH="${now}" \
		bash "${fixture}/scripts/unstable-reminder.sh" 2>&1)"
	printf '%s' "${out}"
}

assert_silent() {
	[ -z "$1" ] || fail "expected silent output, got: ${1}"
}

assert_mentions() {
	case "$1" in
	*"$2"*) ;;
	*) fail "output missing '${2}': ${1}" ;;
	esac
}

candidate_json() {
	local status="$1" first_seen_iso="$2" soak_days="$3"
	jq -n \
		--arg status "${status}" \
		--arg rev "${cand_rev}" \
		--arg first_seen "${first_seen_iso}" \
		--argjson soak "${soak_days}" \
		'{schema: 1, channel: "nixpkgs-unstable", status: $status,
		  rev: $rev, channelCommitDate: "2026-08-01T00:00:00Z",
		  firstSeen: $first_seen, soakDays: $soak}'
}

epoch_of() {
	jq -rn --arg t "$1" '$t | fromdateiso8601'
}

now="$(date -u +%s)"
ten_days_ago_iso="$(jq -rn --argjson now "$((now - 10 * 86400))" '$now | strftime("%Y-%m-%dT%H:%M:%SZ")')"
three_days_ago_iso="$(jq -rn --argjson now "$((now - 3 * 86400))" '$now | strftime("%Y-%m-%dT%H:%M:%SZ")')"

# 1. Due pending candidate: must print, naming the rev and the action.
out="$(run_reminder "${now}" "${pin_rev}" \
	"$(candidate_json pending "${ten_days_ago_iso}" 7)")"
[ -n "${out}" ] || fail "due candidate produced no output"
assert_mentions "${out}" "${cand_rev}"
assert_mentions "${out}" "update-unstable"

# 2. Still soaking: silent.
out="$(run_reminder "${now}" "${pin_rev}" \
	"$(candidate_json pending "${three_days_ago_iso}" 7)")"
assert_silent "${out}"

# 3. Promoted candidate: silent (promotion is not the operator's next step).
out="$(run_reminder "${now}" "${pin_rev}" \
	"$(candidate_json promoted "${ten_days_ago_iso}" 7)")"
assert_silent "${out}"

# 4. Candidate already matches the flake.nix pin: silent.
out="$(run_reminder "${now}" "${cand_rev}" \
	"$(candidate_json pending "${ten_days_ago_iso}" 7)")"
assert_silent "${out}"

# 5. Missing candidate file: silent.
out="$(run_reminder "${now}" "${pin_rev}" "")"
assert_silent "${out}"

# 6. Malformed JSON: silent (never blocks a rebuild on a broken state file).
out="$(run_reminder "${now}" "${pin_rev}" '{"schema": 1, oops')"
assert_silent "${out}"

# 7. Bad timestamp format: silent.
out="$(run_reminder "${now}" "${pin_rev}" \
	"$(jq -rn --arg rev "${cand_rev}" \
		'{status: "pending", rev: $rev, soakDays: 7,
		  firstSeen: "not-a-timestamp"}')")"
assert_silent "${out}"

# 8. Invalid clock override: silent.
out="$(run_reminder "notanumber" "${pin_rev}" \
	"$(candidate_json pending "${ten_days_ago_iso}" 7)")"
assert_silent "${out}"

# 9. Boundary: elapsed exactly equals the window counts as due.
first_epoch="$(epoch_of "${ten_days_ago_iso}")"
out="$(run_reminder "$((first_epoch + 7 * 86400))" "${pin_rev}" \
	"$(candidate_json pending "${ten_days_ago_iso}" 7)")"
[ -n "${out}" ] || fail "exact-boundary soak did not fire"

echo "unstable-reminder: OK (9 contract cases)"
