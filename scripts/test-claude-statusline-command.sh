#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
script="${repo_root}/dot_claude/executable_statusline-command.sh"
workdir="$(mktemp -d "${TMPDIR:-/tmp}/claude-statusline.XXXXXX")"
trap 'rm -rf "${workdir}"' EXIT

managed_source="$(chezmoi --source="${repo_root}" source-path "$HOME/.claude/statusline-command.sh" 2>/dev/null || true)"
if [[ "${managed_source}" != "${script}" ]]; then
  {
    echo "~/.claude/statusline-command.sh is not managed by the expected source"
    echo "expected: ${script}"
    echo "actual: ${managed_source:-<not managed>}"
  } >&2
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
assert_contains "perm:auto"
assert_contains "ctx:92% left"
assert_contains "5h:24%"
assert_contains "7d:41%"
assert_contains "v2.1.90"
assert_contains "tok:16.7k"
assert_contains "in:15.5k"
assert_contains "out:1.2k"
assert_contains "Δ+156/-23"
assert_contains "±1"
assert_contains "NORMAL"
assert_contains "agent:builder"
assert_contains "task:ship-statusline"
assert_not_contains "fast"

everforest_fg=$'\033[38;2;211;198;170m'
everforest_green=$'\033[38;2;167;192;128m'
everforest_teal=$'\033[38;2;127;187;179m'
everforest_yellow=$'\033[38;2;219;188;127m'

assert_raw_contains "${everforest_fg} ctx:92% left"
assert_raw_contains "${everforest_fg} v2.1.90"
assert_raw_contains "${everforest_fg} tok:16.7k"
assert_raw_contains "${everforest_fg} task:ship-statusline"
assert_raw_contains "${everforest_green} perm:auto"
assert_raw_contains "${everforest_teal} ${workdir}"
assert_raw_contains "${everforest_yellow} "$'\033[1m'"Opus 4.8"
assert_raw_contains "${everforest_green}5h:24%"
assert_raw_not_contains $'\033[90m'

echo "claude statusline renders codex-parity segments"
