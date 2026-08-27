#!/usr/bin/env bash
# Shared LocalHostName -> flake-config-name matcher.
#
# Sourced by every script that must resolve this machine's host row outside
# nix (bootstrap.sh, rebuild.sh, update-unstable.sh, host-capability.sh).
# This file is the SINGLE place to add a machine name; the nix-side source of
# truth is lib/machines.nix. Keep both in sync when adding a row.
#
# Usage:
#   # shellcheck source=scripts/host-detect.sh
#   source "${repo_root}/scripts/host-detect.sh"
#   host="$(detect_host || true)"   # returns 1 when nothing matches
detect_host() {
  case "$(scutil --get LocalHostName 2>/dev/null || true)" in
    personal-mac | Stevens-MacBook-Pro) echo personal-mac ;;
    *) return 1 ;;
  esac
}
