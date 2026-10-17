#!/usr/bin/env bash
# Shared LocalHostName -> profile-name matcher.
#
# Sourced by every script that must resolve this machine's profile
# (bootstrap.sh, host-capability.sh). This file is the SINGLE place to add a
# machine name; the profile itself lives in dfm/profiles/<name>.toml.
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
