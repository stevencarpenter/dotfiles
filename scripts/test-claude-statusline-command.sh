#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# Under nix the statusline is a raw out-of-store symlink (dotfiles.nix,
# mkOutOfStoreSymlink) — no chezmoi source-path resolution to assert. Just
# exercise the source file directly for its rendering behavior.
script="${repo_root}/home/.claude/statusline-command.sh"
workdir="$(mktemp -d "${TMPDIR:-/tmp}/claude-statusline.XXXXXX")"
trap 'rm -rf "${workdir}"' EXIT

if [[ ! -f "${script}" ]]; then
  echo "statusline source not found at ${script}" >&2
  exit 1
fi

git -C "${workdir}" init -q
printf 'dirty\n' > "${workdir}/dirty.txt"

input="$(
  jq -n --arg cwd "${workdir}" '{
    cwd: $cwd,
    session_id: "abc123",
    session_name: "ship-statusline",
    transcript_path: "/tmp/transcript.jsonl",
    permission_mode: "auto",
    version: "2.1.90",
    model: {
      id: "claude-opus-4-8",
      display_name: "Claude Opus 4.8"
    },
    workspace: {
      current_dir: $cwd,
      project_dir: $cwd,
      added_dirs: [],
      repo: {
        host: "github.com",
        owner: "carpenter",
        name: "dotfiles"
      }
    },
    cost: {
      total_cost_usd: 0.42,
      total_duration_ms: 138000,
      total_lines_added: 156,
      total_lines_removed: 23
    },
    context_window: {
      total_input_tokens: 15500,
      total_output_tokens: 1200,
      context_window_size: 200000,
      used_percentage: 8,
      remaining_percentage: 92,
      current_usage: {
        input_tokens: 8500,
        output_tokens: 1200,
        cache_creation_input_tokens: 5000,
        cache_read_input_tokens: 2000
      }
    },
    effort: {
      level: "xhigh"
    },
    thinking: {
      enabled: true
    },
    rate_limits: {
      five_hour: {
        used_percentage: 23.5
      },
      seven_day: {
        used_percentage: 41.2
      }
    },
    vim: {
      mode: "NORMAL"
    },
    agent: {
      name: "builder"
    },
    pr: {
      number: 1234,
      url: "https://github.com/carpenter/dotfiles/pull/1234",
      review_state: "pending"
    },
    worktree: {
      branch: "feature/statusline"
    }
  }'
)"

output="$(printf '%s\n' "${input}" | bash "${script}")"
plain="$(printf '%b' "${output}" | perl -pe 's/\e\[[0-9;]*m//g')"

assert_contains() {
  local needle="$1"

  if [[ "${plain}" != *"${needle}"* ]]; then
    {
      echo "statusline did not include expected segment: ${needle}"
      echo "actual:"
      printf '%s\n' "${plain}"
    } >&2
    exit 1
  fi
}

assert_not_contains() {
  local needle="$1"

  if [[ "${plain}" == *"${needle}"* ]]; then
    {
      echo "statusline included unwanted segment: ${needle}"
      echo "actual:"
      printf '%s\n' "${plain}"
    } >&2
    exit 1
  fi
}

assert_raw_contains() {
  local needle="$1"

  if [[ "${output}" != *"${needle}"* ]]; then
    {
      echo "statusline did not include expected raw escape/text segment"
      printf 'expected raw segment: %q\n' "${needle}"
      printf 'actual raw output: %q\n' "${output}"
      echo "plain:"
      printf '%s\n' "${plain}"
    } >&2
    exit 1
  fi
}

assert_raw_not_contains() {
  local needle="$1"

  if [[ "${output}" == *"${needle}"* ]]; then
    {
      echo "statusline included unwanted raw escape/text segment"
      printf 'unwanted raw segment: %q\n' "${needle}"
      printf 'actual raw output: %q\n' "${output}"
      echo "plain:"
      printf '%s\n' "${plain}"
    } >&2
    exit 1
  fi
}

assert_contains "${workdir}"
assert_contains "feature/statusline"
assert_contains "Opus 4.8"
assert_contains "effort:xhigh"
assert_contains "PR#1234:pending"
assert_contains "ctx:92% left"
assert_contains "5h:24%"
assert_contains "7d:41%"
assert_contains "v2.1.90"
assert_contains '$0.42'
assert_contains "⧗2m18s"
assert_contains "Δ+156/-23"
assert_contains "±1"
assert_contains "agent:builder"
assert_contains "task:ship-statusline"
assert_not_contains "fast"
# Dropped segments (chore(statusline): drop vim mode and permission segments)
# must stay dropped even though the harness still sends the input fields.
assert_not_contains "perm:"
assert_not_contains "NORMAL"

everforest_fg=$'\033[38;2;211;198;170m'
everforest_green=$'\033[38;2;167;192;128m'
everforest_teal=$'\033[38;2;127;187;179m'
everforest_yellow=$'\033[38;2;219;188;127m'

assert_raw_contains "${everforest_fg} ctx:92% left"
assert_raw_contains "${everforest_fg} v2.1.90"
assert_raw_contains "${everforest_fg} \$0.42"
assert_raw_contains "${everforest_fg} task:ship-statusline"
assert_raw_contains "${everforest_teal} ${workdir}"
assert_raw_contains "${everforest_yellow} "$'\033[1m'"Opus 4.8"
assert_raw_contains "${everforest_green}5h:24%"
assert_raw_not_contains $'\033[90m'

# ── Edge cases: malformed / missing / fractional numeric fields ──────────────
# A bad field must degrade to a skipped segment, never abort the render — under
# `set -u` an aborted render blanks the ENTIRE status line, not just one piece.
render_dir_survives() {
  local label="$1" json="$2" out plain_out

  if ! out="$(printf '%s\n' "${json}" | bash "${script}")"; then
    echo "statusline aborted (non-zero exit) on: ${label}" >&2
    exit 1
  fi
  plain_out="$(printf '%b' "${out}" | perl -pe 's/\e\[[0-9;]*m//g')"
  if [[ "${plain_out}" != *"${workdir}"* ]]; then
    {
      echo "statusline blanked the dir segment on: ${label}"
      echo "actual: ${plain_out}"
    } >&2
    exit 1
  fi
}

# Non-numeric context percentage: was a hard crash ($((100 - NaN)) →
# "NaN: unbound variable") that blanked the whole line under set -u.
render_dir_survives "non-numeric used_percentage" \
  "$(jq -n --arg cwd "${workdir}" '{cwd: $cwd, context_window: {used_percentage: "NaN"}}')"

# Malformed cost fields: a non-numeric dollar value must skip the cost segment
# (the awk guard), and a non-integer duration must degrade via to_int — neither
# may abort the render under set -u.
render_dir_survives "malformed cost fields" \
  "$(jq -n --arg cwd "${workdir}" '{cwd: $cwd, cost: {total_cost_usd: "NaN", total_duration_ms: "oops"}}')"

# Sparse object: every numeric field absent — must still render the dir prefix.
render_dir_survives "sparse object" \
  "$(jq -n --arg cwd "${workdir}" '{cwd: $cwd}')"

# Empty object on stdin must not crash the shell.
if ! printf '%s' '{}' | bash "${script}" >/dev/null 2>&1; then
  echo "statusline aborted on empty object stdin" >&2
  exit 1
fi

# ── Regression: newline in a free-text field must not truncate the render ────
# `read` consumes one line, so before the per-field gsub a newline in
# session_name silently dropped every field ordered after it (the Δ tree count).
newline_plain="$(
  jq -n --arg cwd "${workdir}" \
    '{cwd: $cwd, session_name: "one\ntwo", cost: {total_lines_added: 7, total_lines_removed: 3}}' \
  | bash "${script}" | perl -pe 's/\e\[[0-9;]*m//g'
)"
if [[ "${newline_plain}" != *"task:one two"* ]]; then
  echo "newline in session_name was not scrubbed: ${newline_plain}" >&2
  exit 1
fi
if [[ "${newline_plain}" != *"Δ+7/-3"* ]]; then
  echo "field ordered after a newline field was dropped: ${newline_plain}" >&2
  exit 1
fi

# ── Regression: context bar renders from remaining_percentage alone ──────────
# The segment used to be gated solely on used_percentage, so a payload carrying
# only remaining_percentage rendered no context bar at all.
remaining_plain="$(
  jq -n --arg cwd "${workdir}" '{cwd: $cwd, context_window: {remaining_percentage: 73}}' \
  | bash "${script}" | perl -pe 's/\e\[[0-9;]*m//g'
)"
if [[ "${remaining_plain}" != *"ctx:73% left"* ]]; then
  echo "context bar vanished with a remaining-only payload: ${remaining_plain}" >&2
  exit 1
fi

echo "claude statusline renders codex-parity segments"
