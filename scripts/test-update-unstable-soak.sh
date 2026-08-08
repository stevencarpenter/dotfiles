#!/usr/bin/env bash
# Hermetic regression coverage for the first-seen nixpkgs-unstable soak queue.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
fixture="$(mktemp -d)"
trap 'rm -rf "${fixture}"' EXIT

mkdir -p "${fixture}/scripts" "${fixture}/versions" "${fixture}/bin"
cp "${repo_root}/scripts/update-unstable.sh" "${fixture}/scripts/update-unstable.sh"
chmod +x "${fixture}/scripts/update-unstable.sh"

old_rev="cccccccccccccccccccccccccccccccccccccccc"
candidate_rev="aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
next_rev="bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
stale_rev="dddddddddddddddddddddddddddddddddddddddd"
cat >"${fixture}/flake.nix" <<EOF
{
  inputs.nixpkgs-unstable.url = "github:NixOS/nixpkgs/${old_rev}"; # nixpkgs-unstable @ 2026-07-01
}
EOF
cat >"${fixture}/flake.lock" <<EOF
{"nodes":{"nixpkgs-unstable":{"locked":{"rev":"${old_rev}"}}}}
EOF

cat >"${fixture}/bin/curl" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
url="${!#}"
case "${url}" in
*/commits/nixpkgs-unstable)
  jq -n --arg rev "${TEST_TIP_REV}" --arg date "${TEST_TIP_DATE}" \
    '{sha: $rev, commit: {committer: {date: $date}}}'
  ;;
*/compare/*)
  jq -n --arg status "${TEST_COMPARE_STATUS:-ahead}" '{status: $status}'
  ;;
*)
  echo "unexpected URL: ${url}" >&2
  exit 1
  ;;
esac
EOF

cat >"${fixture}/bin/nix" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >>"${TEST_NIX_LOG}"
case "$*" in
"flake update nixpkgs-unstable")
  tmp="$(mktemp)"
  jq --arg rev "${TEST_TIP_REV}" '.nodes["nixpkgs-unstable"].locked.rev = $rev' \
    flake.lock >"${tmp}"
  mv "${tmp}" flake.lock
  ;;
build*)
  if [ "${TEST_FAIL_BUILD:-0}" = 1 ]; then
    echo "simulated build failure" >&2
    exit 9
  fi
  printf '/nix/store/test-system\n'
  ;;
"store diff-closures"*) ;;
*)
  echo "unexpected nix command: $*" >&2
  exit 1
  ;;
esac
EOF
chmod +x "${fixture}/bin/curl" "${fixture}/bin/nix"

export PATH="${fixture}/bin:${PATH}"
export UPDATE_UNSTABLE_API_ROOT="https://fixture.invalid"
export UPDATE_UNSTABLE_TEST_MODE=1
export TEST_NIX_LOG="${fixture}/nix.log"
export TEST_TIP_REV="${candidate_rev}"
# Deliberately ancient: the defect used this metadata as if it were first-seen
# time, allowing a newly exposed backdated commit to skip the soak immediately.
export TEST_TIP_DATE="2000-01-01T00:00:00Z"
start_epoch=1786147200 # 2026-08-08T00:00:00Z

run_update() {
  local now="$1" days="${2:-7}"
  (
    cd "${fixture}"
    UPDATE_UNSTABLE_NOW_EPOCH="${now}" scripts/update-unstable.sh "${days}" personal-mac
  )
}

run_update "${start_epoch}" >/dev/null
jq -e \
  --arg rev "${candidate_rev}" \
  '.status == "pending" and .rev == $rev
   and .firstSeen == "2026-08-08T00:00:00Z" and .soakDays == 7' \
  "${fixture}/versions/nixpkgs-unstable-candidate.json" >/dev/null
if [ -e "${TEST_NIX_LOG}" ]; then
  echo "recording a candidate unexpectedly invoked nix" >&2
  exit 1
fi

# A backdated channel commit must still wait based on when this repo observed
# it, not the commit's year-2000 metadata.
run_update "$((start_epoch + 604799))" >/dev/null
if [ -e "${TEST_NIX_LOG}" ]; then
  echo "candidate promoted before seven elapsed days" >&2
  exit 1
fi
if ! rg -Fq "${old_rev}" "${fixture}/flake.nix"; then
  echo "flake input changed before the soak elapsed" >&2
  exit 1
fi

run_update "$((start_epoch + 604800))" >/dev/null
if ! rg -Fq "${candidate_rev}" "${fixture}/flake.nix"; then
  echo "mature candidate did not update flake.nix" >&2
  exit 1
fi
if [ "$(jq -r '.nodes["nixpkgs-unstable"].locked.rev' "${fixture}/flake.lock")" != "${candidate_rev}" ]; then
  echo "mature candidate did not update the exact lock node" >&2
  exit 1
fi
jq -e '.status == "promoted"' "${fixture}/versions/nixpkgs-unstable-candidate.json" >/dev/null
for expected in \
  "flake update nixpkgs-unstable" \
  "build --no-link --print-out-paths --no-update-lock-file" \
  "store diff-closures /run/current-system /nix/store/test-system"; do
  if ! rg -Fq "${expected}" "${TEST_NIX_LOG}"; then
    echo "promotion missed command contract: ${expected}" >&2
    exit 1
  fi
done

# Once the channel advances, begin a fresh queue instead of immediately
# ingesting the new tip through the already-aged state.
export TEST_TIP_REV="${next_rev}"
export TEST_TIP_DATE="2026-08-08T01:00:00Z"
run_update "$((start_epoch + 604900))" >/dev/null
jq -e \
  --arg rev "${next_rev}" \
  '.status == "pending" and .rev == $rev and .firstSeen == "2026-08-15T00:01:40Z"' \
  "${fixture}/versions/nixpkgs-unstable-candidate.json" >/dev/null

# If a force-push removes a pending candidate from channel ancestry, discard
# its accumulated age and start the replacement candidate at zero.
tmp="$(mktemp)"
jq \
  --arg rev "${stale_rev}" \
  '.rev = $rev | .firstSeen = "2026-08-01T00:00:00Z" | .status = "pending"' \
  "${fixture}/versions/nixpkgs-unstable-candidate.json" >"${tmp}"
mv "${tmp}" "${fixture}/versions/nixpkgs-unstable-candidate.json"
export TEST_COMPARE_STATUS=diverged
run_update "$((start_epoch + 604901))" >/dev/null
jq -e \
  --arg rev "${next_rev}" \
  '.status == "pending" and .rev == $rev and .firstSeen == "2026-08-15T00:01:41Z"' \
  "${fixture}/versions/nixpkgs-unstable-candidate.json" >/dev/null

# Persist the requested duration with the candidate. A later default invocation
# must not shorten an explicitly widened fourteen-day soak.
unset TEST_COMPARE_STATUS
extended_epoch="$((start_epoch + 604901))"
run_update "${extended_epoch}" 14 >/dev/null
jq -e '.soakDays == 14' "${fixture}/versions/nixpkgs-unstable-candidate.json" >/dev/null
flake_before="$(shasum -a 256 "${fixture}/flake.nix")"
lock_before="$(shasum -a 256 "${fixture}/flake.lock")"
log_lines_before="$(wc -l <"${TEST_NIX_LOG}")"
run_update "$((extended_epoch + 604800))" 7 >/dev/null
if [ "$(wc -l <"${TEST_NIX_LOG}")" -ne "${log_lines_before}" ]; then
  echo "a shorter later invocation bypassed the committed fourteen-day soak" >&2
  exit 1
fi

# Promotion is transactional: a failed build restores both reviewed inputs and
# leaves the candidate pending for a clean retry.
export TEST_FAIL_BUILD=1
if run_update "$((extended_epoch + 1209600))" 7 >/dev/null 2>&1; then
  echo "simulated failed promotion unexpectedly succeeded" >&2
  exit 1
fi
unset TEST_FAIL_BUILD
if [ "$(shasum -a 256 "${fixture}/flake.nix")" != "${flake_before}" ] \
  || [ "$(shasum -a 256 "${fixture}/flake.lock")" != "${lock_before}" ]; then
  echo "failed promotion left a partial flake pin/lock change" >&2
  exit 1
fi
jq -e '.status == "pending" and .soakDays == 14' \
  "${fixture}/versions/nixpkgs-unstable-candidate.json" >/dev/null

run_update "$((extended_epoch + 1209600))" 7 >/dev/null
jq -e --arg rev "${next_rev}" \
  '.status == "promoted" and .rev == $rev and .soakDays == 14' \
  "${fixture}/versions/nixpkgs-unstable-candidate.json" >/dev/null

# Numeric-looking input is still bounded before Bash arithmetic can overflow
# a negative duration and make every candidate appear mature.
if run_update "${start_epoch}" 9999999999999999999 >/dev/null 2>&1; then
  echo "overflow-sized soak duration unexpectedly succeeded" >&2
  exit 1
fi

echo "nixpkgs-unstable first-seen soak queue rejects backdated and unreachable candidates"
