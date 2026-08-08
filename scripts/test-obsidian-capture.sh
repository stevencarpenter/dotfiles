#!/usr/bin/env bash
# Exercise the AeroSpace -> obsidian-capture contract without starting Obsidian.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
capture="${repo_root}/home/.local/bin/obsidian-capture"
[ -x "${capture}" ] || { echo "FAIL: ${capture} is not executable" >&2; exit 1; }

personal_config="${repo_root}/home/.config/aerospace/aerospace.personal.toml"
work_config="${repo_root}/home/.config/aerospace/aerospace.work.toml"
rg -Fxq \
  "alt-shift-n = 'exec-and-forget /bin/sh -c \"\$HOME/.local/bin/obsidian-capture new --vault obsidian\"'" \
  "${personal_config}"
rg -Fxq \
  "alt-shift-d = 'exec-and-forget /bin/sh -c \"\$HOME/.local/bin/obsidian-capture daily --vault obsidian\"'" \
  "${personal_config}"
rg -Fxq \
  "alt-shift-n = 'exec-and-forget /bin/sh -c \"\$HOME/.local/bin/obsidian-capture new\"'" \
  "${work_config}"
rg -Fxq \
  "alt-shift-d = 'exec-and-forget /bin/sh -c \"\$HOME/.local/bin/obsidian-capture daily\"'" \
  "${work_config}"
if rg -n '^alt-shift-[nd].*(--vault|vault=|lumin)' "${work_config}"; then
  echo "FAIL: work AeroSpace config hard-coded a vault identity" >&2
  exit 1
fi

fixture="$(mktemp -d)"
trap 'rm -rf "${fixture}"' EXIT
mkdir -p "${fixture}/bin"

cat >"${fixture}/bin/open" <<'MOCK'
#!/usr/bin/env bash
printf 'open %s\n' "$*" >>"${CAPTURE_LOG}"
exit "${MOCK_OPEN_RC:-0}"
MOCK
cat >"${fixture}/bin/obsidian" <<'MOCK'
#!/usr/bin/env bash
printf 'obsidian %s\n' "$*" >>"${CAPTURE_LOG}"
count_file="${CAPTURE_LOG}.count"
count=0
[ ! -f "${count_file}" ] || count="$(cat "${count_file}")"
count=$((count + 1))
printf '%s' "${count}" >"${count_file}"
if [ "${count}" -lt "${MOCK_SUCCEED_ON:-1}" ]; then
  echo "mock CLI unavailable ${count}" >&2
  exit 1
fi
MOCK
cat >"${fixture}/bin/logger" <<'MOCK'
#!/usr/bin/env bash
printf 'logger %s\n' "$*" >>"${CAPTURE_LOG}"
MOCK
cat >"${fixture}/bin/sleep" <<'MOCK'
#!/usr/bin/env bash
printf 'sleep %s\n' "$*" >>"${CAPTURE_LOG}"
MOCK
chmod +x "${fixture}/bin/"*

run_capture() {
  local name="$1"
  shift
  CAPTURE_LOG="${fixture}/${name}.log" \
    OPEN_BIN="${fixture}/bin/open" \
    OBSIDIAN_BIN="${fixture}/bin/obsidian" \
    LOGGER_BIN="${fixture}/bin/logger" \
    SLEEP_BIN="${fixture}/bin/sleep" \
    MOCK_OPEN_RC="${MOCK_OPEN_RC:-0}" \
    MOCK_SUCCEED_ON="${MOCK_SUCCEED_ON:-1}" \
    OBSIDIAN_CAPTURE_ATTEMPTS="${OBSIDIAN_CAPTURE_ATTEMPTS:-3}" \
    OBSIDIAN_CAPTURE_DELAY=0 \
    "${capture}" "$@"
}

assert_line() {
  local expected="$1" file="$2"
  if ! rg -Fxq "${expected}" "${file}"; then
    echo "FAIL: missing '${expected}' in ${file}" >&2
    cat "${file}" >&2
    exit 1
  fi
}

MOCK_SUCCEED_ON=1 run_capture personal-new new --vault obsidian
assert_line "open -a Obsidian" "${fixture}/personal-new.log"
assert_line "obsidian command id=templater-obsidian:create-new-note-from-template vault=obsidian" \
  "${fixture}/personal-new.log"

# Work deliberately follows the vault brought to the foreground by `open` and
# must not inherit the personal vault name.
MOCK_SUCCEED_ON=1 run_capture work-daily daily
assert_line "obsidian daily" "${fixture}/work-daily.log"
if rg -Fq 'vault=' "${fixture}/work-daily.log"; then
  echo "FAIL: work capture hard-coded a vault" >&2
  exit 1
fi

MOCK_SUCCEED_ON=3 run_capture retry daily --vault obsidian
if [ "$(rg -c '^obsidian ' "${fixture}/retry.log")" -ne 3 ]; then
  echo "FAIL: capture did not retry until the third successful attempt" >&2
  exit 1
fi
if [ "$(rg -c '^sleep ' "${fixture}/retry.log")" -ne 2 ]; then
  echo "FAIL: capture slept after the wrong attempts" >&2
  exit 1
fi

if MOCK_SUCCEED_ON=99 OBSIDIAN_CAPTURE_ATTEMPTS=2 run_capture failure new --vault obsidian \
  >"${fixture}/failure.out" 2>"${fixture}/failure.err"; then
  echo "FAIL: exhausted capture unexpectedly succeeded" >&2
  exit 1
fi
assert_line "logger -t obsidian-capture -- Obsidian new capture failed for vault 'obsidian' after 2 attempts: mock CLI unavailable 2" \
  "${fixture}/failure.log"
if ! rg -Fq "capture failed for vault 'obsidian' after 2 attempts" "${fixture}/failure.err"; then
  echo "FAIL: exhausted capture did not report its error on stderr" >&2
  exit 1
fi

if MOCK_OPEN_RC=1 run_capture open-failure daily >"${fixture}/open.out" 2>"${fixture}/open.err"; then
  echo "FAIL: open failure unexpectedly succeeded" >&2
  exit 1
fi
if rg -q '^obsidian ' "${fixture}/open-failure.log"; then
  echo "FAIL: capture called the CLI after open failed" >&2
  exit 1
fi
assert_line "logger -t obsidian-capture -- Obsidian capture failed to open the app: unknown error" \
  "${fixture}/open-failure.log"

echo "all Obsidian capture checks passed"
