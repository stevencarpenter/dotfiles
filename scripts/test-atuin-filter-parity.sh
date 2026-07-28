#!/usr/bin/env bash
# Assert the two atuin config variants stay in sync where they must, and stay
# different where they must.
#
# Why: caps.atuin used to gate the whole config file, so machines with the
# capability off got no atuin config at all and ran on atuin's defaults — no
# history_filter, and no [tmux].enabled (which makes `atuin init zsh` emit
# ATUIN_TMUX_POPUP=false, rendering ctrl-r and up-arrow inline instead of in a
# popup). Splitting the file fixed that but duplicated the filter list, so the
# redaction patterns can now drift between variants. This test makes that
# drift a CI failure.
#
# Assertions are TOML-table-aware on purpose. An earlier draft matched bare
# substrings and was defeated by three realistic edits: moving `enabled = true`
# out of [tmux] (which reproduces the original bug verbatim — atuin silently
# ignores unknown top-level keys), deleting history_filter from BOTH files
# (identical absence still compares equal), and reformatting `enabled=true`
# without spaces.
#
# See docs/superpowers/specs/2026-07-27-atuin-config-split-design.md.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
sync_config="${repo_root}/home/.config/atuin/config.sync.toml"
local_config="${repo_root}/home/.config/atuin/config.local.toml"

failures=0

fail() {
  echo "FAIL: $1" >&2
  failures=$((failures + 1))
}

rel() { echo "${1#"${repo_root}/"}"; }

for file in "${sync_config}" "${local_config}"; do
  if [[ ! -f "${file}" ]]; then
    fail "$(rel "${file}") is missing (renamed? update modules/home/dotfiles.nix too)"
    echo "${failures} check(s) failed" >&2
    exit 1
  fi
done

# Print the value of a top-level-or-tabled TOML key, or return 1 if the key is
# not assigned in that table. Pass "" as the table for top level.
#
# Single pass with inline table tracking — no process substitution and no
# mktemp, both of which are blocked under the Claude Code sandbox and would
# turn a real assertion into a silent skip.
toml_assignment() {
  local file="$1" want_table="$2" key="$3"
  local current="" line trimmed lhs value
  while IFS= read -r line || [[ -n "${line}" ]]; do
    trimmed="${line#"${line%%[![:space:]]*}"}"
    [[ "${trimmed}" == '#'* ]] && continue
    if [[ "${trimmed}" == '['*']'* ]]; then
      current="${trimmed%%]*}"
      current="${current#[}"
      continue
    fi
    [[ "${current}" == "${want_table}" ]] || continue
    # Split on the first `=` and compare the trimmed left-hand side, rather
    # than pattern-matching `key[[:space:]]*=`. In glob syntax `*` is a
    # wildcard, NOT a repetition quantifier, so `[[:space:]]*` demands at
    # least one space and silently rejects the valid TOML `key=value`.
    [[ "${trimmed}" == *=* ]] || continue
    lhs="${trimmed%%=*}"
    lhs="${lhs%"${lhs##*[![:space:]]}"}" # rtrim
    lhs="${lhs#[\"\']}"                  # a quoted key is still that key
    lhs="${lhs%[\"\']}"
    [[ "${lhs}" == "${key}" ]] || continue
    value="${trimmed#*=}"
    value="${value%%#*}"                       # drop trailing comment
    value="${value#"${value%%[![:space:]]*}"}" # ltrim
    value="${value%"${value##*[![:space:]]}"}" # rtrim
    printf '%s\n' "${value}"
    return 0
  done <"${file}"
  return 1
}

extract_filter() {
  sed -n '/^# --- BEGIN history_filter/,/^# --- END history_filter/p' "$1"
}

# ---- history_filter: must exist, be non-trivial, and match -----------------

for file in "${sync_config}" "${local_config}"; do
  if ! toml_assignment "${file}" "" history_filter >/dev/null; then
    fail "$(rel "${file}") has no top-level history_filter assignment — redaction would not apply on machines using this variant"
  fi

  # Guards against both files being emptied in lockstep, which the parity
  # comparison alone reports as "identical, therefore fine".
  pattern_count="$(extract_filter "${file}" | grep -c '^[[:space:]]*"' || true)"
  if ((pattern_count < 5)); then
    fail "$(rel "${file}") history_filter has only ${pattern_count} pattern(s) — expected at least 5"
  fi
done

sync_filter="$(extract_filter "${sync_config}")"
local_filter="$(extract_filter "${local_config}")"

[[ -n "${sync_filter}" ]] ||
  fail "config.sync.toml has no '# --- BEGIN history_filter' sentinel block"
[[ -n "${local_filter}" ]] ||
  fail "config.local.toml has no '# --- BEGIN history_filter' sentinel block"

if [[ -n "${sync_filter}" && -n "${local_filter}" && "${sync_filter}" != "${local_filter}" ]]; then
  fail "history_filter blocks have drifted between the two atuin configs"
  # Print both blocks rather than diffing them. `diff` would need either
  # process substitution or mktemp, and both are blocked under the Claude Code
  # sandbox — which would swallow the only useful output this failure has.
  {
    echo "--- config.sync.toml -------------------------------------------"
    printf '%s\n' "${sync_filter}"
    echo "--- config.local.toml ------------------------------------------"
    printf '%s\n' "${local_filter}"
    echo "----------------------------------------------------------------"
  } >&2
fi

# ---- tmux popup: must be enabled INSIDE the [tmux] table ------------------

# Scoped deliberately. `enabled` at top level, or under [daemon]/[dotfiles]
# (both real atuin tables with an `enabled` key), does nothing for the popup —
# and atuin accepts unknown top-level keys without complaint, so the
# regression would be silent in the tool as well as in CI.
for file in "${sync_config}" "${local_config}"; do
  if [[ "$(toml_assignment "${file}" tmux enabled || true)" != 'true' ]]; then
    fail "$(rel "${file}") does not set 'enabled = true' inside [tmux] — search UI will render inline, not as a popup"
  fi
done

# ---- sync stanzas: must differ, explicitly --------------------------------

# The non-syncing variant must refuse sync EXPLICITLY, not by omission: atuin
# defaults to sync_address = https://api.atuin.sh with auto_sync = true, so a
# bare "no sync_address" leaves the PUBLIC server configured.
if [[ "$(toml_assignment "${local_config}" "" auto_sync || true)" != 'false' ]]; then
  fail "config.local.toml must set top-level auto_sync = false (atuin defaults it to true)"
fi

if toml_assignment "${local_config}" "" sync_address >/dev/null; then
  fail "config.local.toml assigns a top-level sync_address — it is the non-syncing variant"
fi

if [[ "$(toml_assignment "${sync_config}" "" sync_address || true)" \
  != '"https://logbook.snugmarina.org"' ]]; then
  fail "config.sync.toml lost its top-level self-hosted sync_address assignment"
fi

# ---- cache-invalidation insurance -----------------------------------------

# zcached stamps each input as "mtime:size" at second resolution. Switching
# variants (a rebuild flipping caps.atuin) must change that stamp, or the
# cached `atuin init zsh` output survives the switch and the popup setting
# silently doesn't take. Two files written in the same second differ only by
# size, so identical sizes would defeat it. They differ by ~240 bytes today;
# this keeps a future edit from accidentally converging them.
sync_bytes="$(wc -c <"${sync_config}")"
local_bytes="$(wc -c <"${local_config}")"
if ((sync_bytes == local_bytes)); then
  fail "the two variants are both ${sync_bytes} bytes — identical size can defeat zcached's mtime:size stamp when switching variants"
fi

if ((failures > 0)); then
  echo "${failures} check(s) failed" >&2
  exit 1
fi

echo "atuin config parity OK (history_filter identical + non-trivial; [tmux].enabled set in both; sync stanzas distinct)"
