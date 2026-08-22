#!/usr/bin/env bash
# Assert: every Host block pinning its own IdentityFile also pins its own
# ControlPath, and no two resolve to the same socket.
#
# THE BUG: %C hashes %l%h%p%r (local host, RESOLVED hostname, port, remote
# user) — it does not vary by alias. So `Host github-dotfiles` (HostName
# github.com) and any block claiming `github.com` share one socket under the
# default `ControlPath ~/.ssh/cm-%C`. Two blocks meant to use different keys
# collapse onto one multiplexed connection; the first to authenticate wins.
#
# Symptom is remote and points away from the cause: GitHub answers as the wrong
# account and reports a readable repo as "Repository not found", while
# `ssh -G` shows the correct IdentityFile — config and live connection disagree.
#
# The fix must NOT use %n: it distinguishes aliases but reintroduces the 104-char
# unix-socket limit that %C exists to dodge — prefix + 40 hex < 67 chars;
# Teleport hostnames here are 44, and a literal prefix keeps it bounded.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cfg="${repo_root}/home/.ssh/config"
[ -r "${cfg}" ] || {
  echo "FAIL: ${cfg} not readable" >&2
  exit 1
}

failures=0

# Walk Host blocks, recording which set IdentityFile and which set ControlPath.
# Comments and the leading Include lines are ignored; only directive lines count.
current=""
declare -a pinning=()
declare -A has_cp=()
while IFS= read -r line; do
  line="${line%%#*}"
  # shellcheck disable=SC2001 # trimming both ends is clearer as two seds here
  line="$(printf '%s' "${line}" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')"
  [ -n "${line}" ] || continue
  case "${line}" in
  [Hh]ost\ *)
    current="${line#* }"
    ;;
  [Ii]dentity[Ff]ile\ *)
    # `Host *` legitimately sets no identity of its own; only named blocks count.
    [ "${current}" = "*" ] && continue
    case " ${pinning[*]} " in *" ${current} "*) ;; *) pinning+=("${current}") ;; esac
    ;;
  [Cc]ontrol[Pp]ath\ *)
    has_cp["${current}"]="${line#* }"
    ;;
  esac
done <"${cfg}"

for host in "${pinning[@]}"; do
  if [ -z "${has_cp[${host}]:-}" ]; then
    echo "FAIL: 'Host ${host}' pins IdentityFile but not ControlPath — it will" >&2
    echo "      share a multiplexed socket with any other block resolving to the" >&2
    echo "      same hostname/port/user, and the first identity to connect wins." >&2
    failures=$((failures + 1))
  else
    echo "ok: Host ${host} pins its own ControlPath"
  fi
done

# Distinctness + length, using ssh's own resolver rather than re-implementing it.
declare -A seen=()
for host in "${pinning[@]}" "*"; do
  probe="${host}"
  [ "${probe}" = "*" ] && probe="length-probe.example.com"
  path="$(ssh -F "${cfg}" -G "${probe}" 2>/dev/null | sed -n 's/^controlpath //p' | head -1)"
  [ -n "${path}" ] || continue
  path="${path/#\~/${HOME}}"
  if [ -n "${seen[${path}]:-}" ]; then
    echo "FAIL: '${host}' and '${seen[${path}]}' resolve to the SAME ControlPath:" >&2
    echo "      ${path}" >&2
    failures=$((failures + 1))
  fi
  seen["${path}"]="${host}"
  # macOS caps sun_path at 104 bytes; an over-long path fails at connect time.
  if [ "${#path}" -ge 104 ]; then
    echo "FAIL: ControlPath for '${host}' is ${#path} chars (limit 104): ${path}" >&2
    failures=$((failures + 1))
  fi
done
echo "ok: all ControlPaths distinct and within the 104-char limit"

if [ "${failures}" -ne 0 ]; then
  echo "${failures} check(s) failed" >&2
  exit 1
fi
echo "all ssh ControlPath checks passed"
