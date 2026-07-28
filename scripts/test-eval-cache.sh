#!/usr/bin/env bash
# Behavior tests for zcached (home/.config/zsh/lib/eval-cache.zsh).
#
# Why this exists: zcached runs on EVERY interactive shell startup and caches
# the output of `<tool> init` scripts keyed on its inputs' mtime+size. Its
# realistic failure mode is silent — a stale cached script keeps being sourced
# after the thing it was generated from changed, with no error anywhere. That
# exact bug shipped once already (an `atuin init zsh` cache that kept exporting
# ATUIN_TMUX_POPUP=false after the config that caused it was replaced), which is
# why the `-k` flag exists. Nothing tested this file until 2026-07-28.
#
# Everything runs against throwaway dirs under $TMPDIR with XDG_CACHE_HOME
# redirected, so the real ~/.cache/zsh-eval-cache is never touched.
set -uo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
lib="${repo_root}/home/.config/zsh/lib/eval-cache.zsh"

if ! command -v zsh >/dev/null 2>&1; then
  echo "FAIL: zsh is required to test eval-cache.zsh but is not installed" >&2
  exit 1
fi
if [[ ! -r "${lib}" ]]; then
  echo "FAIL: ${lib} not found (moved? update this test)" >&2
  exit 1
fi

failures=0
fail() {
  echo "FAIL: $1" >&2
  failures=$((failures + 1))
}

work="$(mktemp -d "${TMPDIR:-/tmp}/eval-cache-test.XXXXXX")"
trap 'rm -rf "${work}"' EXIT

# Run a zsh snippet with the library sourced, in an isolated cache dir.
# perl's alarm supplies a portable timeout: a parsing regression in zcached's
# flag loop hangs forever, and a hang must fail this test rather than wedge CI.
zc() {
  local script="$1"
  perl -e 'alarm 20; exec @ARGV' -- \
    zsh -f -c "XDG_CACHE_HOME=${work}/cache; source ${lib}; ${script}"
}

new_tool() { # new_tool <path> <config-it-reads>
  # Two properties this shape buys, both load-bearing:
  #
  # 1. The run-counter is appended when the tool is FORKED; the script it emits
  #    only exports the marker. If the counter were written by the emitted
  #    script instead, sourcing the cache would look identical to re-running
  #    the tool and every cache-hit assertion would be vacuous.
  # 2. The emitted marker is read FROM THE CONFIG at fork time, so editing only
  #    the config changes the tool's output without touching the binary. That
  #    is what lets the -k assertion below isolate the config as the cache key
  #    — if the test also rewrote the binary, a single-input stamp would change
  #    too and the assertion would pass even with -k plumbing removed.
  {
    printf '#!/bin/sh\n'
    printf 'echo TOOL_RAN >> %s/runs.log\n' "${work}"
    # shellcheck disable=SC2016  # $(cat ...) must stay literal until the tool runs
    printf 'echo "export ZC_MARKER=$(cat %s)"\n' "$2"
  } >"$1"
  chmod +x "$1"
}

runs() { [[ -f "${work}/runs.log" ]] && wc -l <"${work}/runs.log" | tr -d ' ' || echo 0; }
reset_runs() { : >"${work}/runs.log"; }

tool="${work}/faketool"
conf="${work}/faketool.conf"

# ---------------------------------------------------------------------------
# 1. Cold cache: the tool runs, its output is sourced, the cache is written.
# ---------------------------------------------------------------------------
echo "config-v1" >"${conf}"
new_tool "${tool}" "${conf}"
reset_runs
out="$(zc "zcached -k ${conf} ft ${tool} ${tool}; echo MARKER=\$ZC_MARKER")"
[[ "${out}" == *"MARKER=config-v1"* ]] || fail "cold cache did not source the tool's output (got: ${out})"
[[ -f "${work}/cache/zsh-eval-cache/ft.zsh" ]] || fail "cold cache did not write a cache file"
[[ "$(runs)" == 1 ]] || fail "cold cache ran the tool $(runs) times, expected 1"

# ---------------------------------------------------------------------------
# 2. Warm cache, nothing changed: the tool is NOT re-run. This is the whole
#    point of the helper; if it regresses, startup silently gets slower.
# ---------------------------------------------------------------------------
reset_runs
out="$(zc "zcached -k ${conf} ft ${tool} ${tool}; echo MARKER=\$ZC_MARKER")"
[[ "${out}" == *"MARKER=config-v1"* ]] || fail "warm cache did not source the cached script"
[[ "$(runs)" == 0 ]] || fail "warm cache re-ran the tool $(runs) times, expected 0"

# ---------------------------------------------------------------------------
# 3. THE REGRESSION THIS FILE EXISTS FOR: a -k input changes, so the cache
#    must be regenerated. Without -k plumbing this silently serves stale output.
# ---------------------------------------------------------------------------
# ONLY the config changes here — the tool binary is deliberately left alone, so
# this can only pass if the -k path is genuinely part of the cache key.
echo "config-v2" >"${conf}"
touch -t 203001010101 "${conf}" # distinct mtime; the stamp is second-resolution
reset_runs
out="$(zc "zcached -k ${conf} ft ${tool} ${tool}; echo MARKER=\$ZC_MARKER")"
[[ "$(runs)" == 1 ]] || fail "a changed -k input did not invalidate the cache (tool ran $(runs) times)"
[[ "${out}" == *"MARKER=config-v2"* ]] || fail "stale cached output was served after the -k input changed (got: ${out})"

# 3b. The binary itself is still a cache key, with the config untouched.
new_tool "${tool}" "${conf}"
printf '# rebuilt\n' >>"${tool}"
touch -t 203001010102 "${tool}"
reset_runs
zc "zcached -k ${conf} ft ${tool} ${tool}" >/dev/null
[[ "$(runs)" == 1 ]] || fail "a changed binary did not invalidate the cache (tool ran $(runs) times)"

# ---------------------------------------------------------------------------
# 4. Single-input callers keep the ORIGINAL one-field stamp format. The other
#    three call sites pass no -k; if this changes they all refork needlessly.
# ---------------------------------------------------------------------------
solo="${work}/solotool"
new_tool "${solo}" "${conf}"
zc "zcached st ${solo} ${solo}" >/dev/null
stamp="$(head -1 "${work}/cache/zsh-eval-cache/st.zsh")"
if [[ ! "${stamp}" =~ ^\#\ [0-9]+:[0-9]+$ ]]; then
  fail "single-input stamp is not the original '# <mtime>:<size>' format: ${stamp}"
fi

# A -k caller must stamp MORE fields, otherwise the extra input is not keyed.
two_field="$(head -1 "${work}/cache/zsh-eval-cache/ft.zsh")"
if [[ ! "${two_field}" =~ ^\#\ [0-9]+:[0-9]+\ [0-9]+:[0-9]+$ ]]; then
  fail "-k caller stamp does not carry two inputs: ${two_field}"
fi

# ---------------------------------------------------------------------------
# 5. Argument-arity guards. A valueless trailing -k used to spin forever,
#    because zsh's `shift 2` FAILS WITHOUT SHIFTING when $# < 2 — from .zshrc
#    that is a shell only `zsh -f` can escape. The perl alarm in zc() turns a
#    regression here into a failed assertion instead of a hung job.
# ---------------------------------------------------------------------------
# rc is captured immediately: a bare `$?` inside the failure message would
# report the status of the `[[ ]]` test rather than of zcached (shellcheck
# SC2319), which is how an assertion ends up printing a misleading value.
zc "zcached -k; exit \$?" >/dev/null 2>&1
rc=$?
[[ ${rc} -eq 2 ]] || fail "a valueless trailing -k returned ${rc}, expected 2 (a 20s timeout here means it hung)"

zc "zcached; exit \$?" >/dev/null 2>&1
rc=$?
[[ ${rc} -ne 0 ]] || fail "a zero-argument zcached returned success"

zc "setopt nounset; zcached; exit \$?" >/dev/null 2>&1
rc=$?
[[ ${rc} -ne 0 ]] || fail "a zero-argument zcached under 'setopt nounset' returned success"

# ---------------------------------------------------------------------------
# 6. A missing -k path must stamp as absent rather than disable caching, so a
#    not-yet-deployed config does not quietly turn the cache off forever.
# ---------------------------------------------------------------------------
new_tool "${tool}" "${conf}"
reset_runs
zc "zcached -k ${work}/does-not-exist ghost ${tool} ${tool}" >/dev/null
[[ -f "${work}/cache/zsh-eval-cache/ghost.zsh" ]] ||
  fail "a missing -k path suppressed caching entirely"
ghost_stamp="$(head -1 "${work}/cache/zsh-eval-cache/ghost.zsh")"
[[ "${ghost_stamp}" == *" 0:0" ]] ||
  fail "a missing -k path did not stamp as 0:0 (got: ${ghost_stamp})"

# ---------------------------------------------------------------------------
# 7. A non-executable binary is a no-op, not an error, so a machine without the
#    tool installed still starts a shell.
# ---------------------------------------------------------------------------
zc "zcached absent ${work}/nope ${work}/nope; exit \$?" >/dev/null 2>&1
rc=$?
[[ ${rc} -eq 0 ]] || fail "zcached with a non-executable binary returned ${rc}, expected 0"

if ((failures > 0)); then
  echo "${failures} check(s) failed" >&2
  exit 1
fi

echo "eval-cache OK (cache hit/miss, -k invalidation, stamp formats, arity guards, absent inputs)"
