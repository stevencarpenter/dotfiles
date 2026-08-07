#!/usr/bin/env bash
# Bump the nixpkgs-unstable input to the channel rev as of N days ago, build the
# result WITHOUT switching, and print the closure diff for review.
#
# Why a soak window rather than the branch tip:
#
# flake.lock's narHash is content-addressing. It guarantees the tree you
# evaluate is byte-identical to the tree you locked, which defeats MITM and a
# retroactively force-pushed branch. It does NOT defend against malicious
# content that was already in nixpkgs at lock time — the lock would pin that
# faithfully and reproduce it identically on every machine. Reproducibility is
# not safety; it is consistent safety-or-unsafety.
#
# Nothing cryptographic closes that gap. Only time (someone else finds it
# first) and surface area (fewer things to be wrong) do. This script buys the
# time. `nixpkgs-unstable` already lags its own master by a few days because
# Hydra must build the jobset green before the branch pointer advances — that
# is a BUILD gate, not a security review, and this adds a disclosure window on
# top of it.
#
# Surface area is the other half, and it lives in modules/home/packages.nix:
# only the names in `fastMovingPackages` come from this input. Note that
# `pkgsFresh` is a full separate nixpkgs instantiation, so each of those
# packages brings its own unstable runtime closure rather than just a leaf
# derivation. Keep that list short and justified.
#
# Usage:
#   scripts/update-unstable.sh              # default 7-day soak
#   scripts/update-unstable.sh 14           # wider window
#   scripts/update-unstable.sh 7 personal-mac
#
# This script never switches. Applying the result is a separate, deliberate
# `./rebuild.sh`. To abandon a bump after reviewing it:
#   git checkout flake.nix flake.lock
set -euo pipefail

SOAK_DAYS="${1:-7}"
if ! [[ "${SOAK_DAYS}" =~ ^[0-9]+$ ]]; then
	echo "error: soak days must be a non-negative integer, got '${SOAK_DAYS}'" >&2
	exit 2
fi

# Lix 2.94 rejects a symlink as a flake root, so resolve the physical checkout
# the same way rebuild.sh does.
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
cd "${REPO_ROOT}"

# Host matcher duplicated from rebuild.sh rather than sourced: rebuild.sh ends
# in `exec sudo darwin-rebuild`, so it cannot be sourced without switching. Keep
# the two cases in sync when adding a machine.
detect_host() {
	case "$(scutil --get LocalHostName 2>/dev/null || true)" in
	personal-mac | Stevens-MacBook-Pro) echo personal-mac ;;
	*) return 1 ;;
	esac
}
HOST="${2:-${DOTFILES_HOST:-$(detect_host || true)}}"
if [ -z "${HOST:-}" ]; then
	echo "unknown host; pass explicitly: update-unstable.sh <days> <personal-mac>" >&2
	exit 1
fi

CUTOFF="$(date -u -v-"${SOAK_DAYS}"d +%Y-%m-%dT%H:%M:%SZ)"
echo "==> Resolving nixpkgs-unstable as of ${CUTOFF} (${SOAK_DAYS}-day soak)"

# The channel branch, not master: this is the rev Hydra last certified green.
API="https://api.github.com/repos/NixOS/nixpkgs/commits?sha=nixpkgs-unstable&until=${CUTOFF}&per_page=1"
response="$(curl -fsSL "${API}")" || {
	echo "error: could not reach the GitHub commits API" >&2
	exit 1
}
NEW_REV="$(jq -r '.[0].sha // empty' <<<"${response}")"
NEW_DATE="$(jq -r '.[0].commit.committer.date // empty' <<<"${response}")"
if [ -z "${NEW_REV}" ]; then
	echo "error: no nixpkgs-unstable commit found at or before ${CUTOFF}" >&2
	exit 1
fi
NEW_DATE="${NEW_DATE%%T*}"

OLD_REV="$(sed -n 's|.*nixpkgs-unstable\.url = "github:NixOS/nixpkgs/\([^"]*\)".*|\1|p' flake.nix)"
if [ -z "${OLD_REV}" ]; then
	echo "error: could not read the nixpkgs-unstable input from flake.nix" >&2
	exit 1
fi

# The lock is checked alongside flake.nix, not assumed to agree with it. A
# hand-edited flake.nix leaves the two out of step, and short-circuiting on
# flake.nix alone would then report "nothing to do" while the lock — the thing
# that actually decides what gets built — still pointed at the old rev. That is
# the exact silent-staleness failure this script exists to prevent, so it must
# not be able to cause it (found while first running this, 2026-08-07).
LOCKED_REV="$(
	jq -r '.nodes | to_entries[] | select(.key | test("unstable")) | .value.locked.rev' flake.lock
)"

echo "    flake.nix: ${OLD_REV}"
echo "    flake.lock: ${LOCKED_REV:-<unreadable>}"
echo "    target   : ${NEW_REV} (${NEW_DATE})"

if [ "${OLD_REV}" = "${NEW_REV}" ] && [ "${LOCKED_REV}" = "${NEW_REV}" ]; then
	echo "==> Already at the ${SOAK_DAYS}-day rev; nothing to do."
	exit 0
fi

# A branch name here means the soak policy was reverted — refuse rather than
# silently rewriting it back, so the reversion gets noticed and discussed.
if [[ "${OLD_REV}" =~ ^nixpkgs- ]] || [ "${#OLD_REV}" -ne 40 ]; then
	echo "error: flake.nix pins nixpkgs-unstable to '${OLD_REV}', which is not a" >&2
	echo "       40-char rev. The soak policy requires a rev pin — see the comment" >&2
	echo "       in flake.nix. Fix that by hand before running this." >&2
	exit 1
fi

if [ "${OLD_REV}" = "${NEW_REV}" ]; then
	echo "==> flake.nix already names the target; re-locking to match."
else
	echo "==> Rewriting flake.nix"
	tmp="$(mktemp)"
	trap 'rm -f "${tmp}"' EXIT
	sed \
		-e "s|nixpkgs-unstable\.url = \"github:NixOS/nixpkgs/[^\"]*\";.*|nixpkgs-unstable.url = \"github:NixOS/nixpkgs/${NEW_REV}\"; # nixpkgs-unstable @ ${NEW_DATE}|" \
		flake.nix >"${tmp}"

	# Guard the rewrite: exactly one line must have changed. A sed that matched
	# nothing exits 0 and emits an unchanged file, which would otherwise sail
	# through to a build that silently used the old rev.
	changed="$(diff flake.nix "${tmp}" | grep -c '^<' || true)"
	if [ "${changed}" -ne 1 ]; then
		echo "error: rewrite changed ${changed} lines, expected exactly 1 — aborting" >&2
		exit 1
	fi
	mv "${tmp}" flake.nix
	trap - EXIT
fi

echo "==> Re-locking"
nix flake lock

echo "==> Building ${HOST} (not switching)"
out="$(nix build --no-link --print-out-paths ".#darwinConfigurations.${HOST}.system")"

echo
echo "==> Closure diff vs the running system"
echo "    (an unexpected package name here is a real signal — review before switching)"
nix store diff-closures /run/current-system "${out}"

cat <<EOF

==> Built, not switched.
    Review the diff above and \`git diff flake.nix flake.lock\`, then apply with:
      ./rebuild.sh
    Or abandon the bump with:
      git checkout flake.nix flake.lock
EOF
