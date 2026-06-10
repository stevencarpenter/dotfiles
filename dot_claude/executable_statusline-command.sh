#!/usr/bin/env bash
# Claude Code status line command — pimped out edition
# Reads JSON from stdin and outputs a styled, information-dense status line

# -u catches unset-variable bugs. No -e: the git probes below are expected to
# fail in non-repo cwds.
set -uo pipefail

input=$(cat)

# Single jq pass for every field (this script runs on each render tick).
# Fields are joined on the unit separator (\x1f): unlike tab, it is not IFS
# whitespace, so empty fields don't collapse and columns stay aligned.
IFS=$'\x1f' read -r cwd model used remaining total_input total_output \
	five_h seven_d worktree effort version pr_number pr_state agent \
	session_name lines_added lines_removed < <(
	echo "$input" | jq -r '[
		(.workspace.current_dir // .cwd // ""),
		(.model.display_name // ""),
		(.context_window.used_percentage // ""),
		(.context_window.remaining_percentage // ""),
		(.context_window.total_input_tokens // ""),
		(.context_window.total_output_tokens // ""),
		(.rate_limits.five_hour.used_percentage // ""),
		(.rate_limits.seven_day.used_percentage // ""),
		(.worktree.branch // ""),
		(.effort.level // ""),
		(.version // ""),
		(.pr.number // ""),
		(.pr.review_state // ""),
		(.agent.name // ""),
		(.session_name // ""),
		(.cost.total_lines_added // ""),
		(.cost.total_lines_removed // "")
	] | map(tostring) | join("\u001f")'
)

# Shorten home directory to ~
cwd="${cwd/#$HOME/~}"

# Everforest dark-hard truecolor palette. Using explicit RGB avoids Ghostty /
# tmux mapping secondary text to ANSI bright-black, which is too dim here.
RESET='\033[0m'
BOLD='\033[1m'

# Foreground colors
FG_CYAN='\033[38;2;131;192;146m'
FG_GREEN='\033[38;2;167;192;128m'
FG_YELLOW='\033[38;2;219;188;127m'
FG_MAGENTA='\033[38;2;214;153;182m'
FG_BLUE='\033[38;2;127;187;179m'
FG_RED='\033[38;2;230;126;128m'
FG_GRAY='\033[38;2;211;198;170m'

# Dim separator color
SEP_COLOR='\033[38;2;157;169;160m'
SEP="${SEP_COLOR}  ${RESET}"

format_count() {
	local value="$1"

	if [ -z "$value" ]; then
		return
	fi

	awk -v n="$value" 'BEGIN {
    if (n >= 1000000) printf "%.1fM", n / 1000000;
    else if (n >= 1000) printf "%.1fk", n / 1000;
    else printf "%d", n;
  }'
}

# ── User@Host ────────────────────────────────────────────────
# user_host="${BOLD}${FG_GREEN} ${user}${FG_GRAY}@${FG_CYAN}${host}${RESET}"

# ── Current Directory ────────────────────────────────────────
dir_display="${BOLD}${FG_BLUE} ${cwd}${RESET}"

# ── Git Branch ───────────────────────────────────────────────
git_part=""
# Try worktree branch first, then fall back to git command
if [ -n "$worktree" ]; then
	git_part="${FG_MAGENTA} ${worktree}${RESET}"
else
	branch=$(git -C "${cwd/#\~/$HOME}" rev-parse --abbrev-ref HEAD 2>/dev/null)
	if [ -n "$branch" ]; then
		git_part="${FG_MAGENTA} ${branch}${RESET}"
	fi
fi

# ── Model ────────────────────────────────────────────────────
model_part=""
if [ -n "$model" ]; then
	# Shorten verbose model names
	short_model="$model"
	short_model="${short_model/Claude /}" # strip "Claude " prefix
	model_part="${FG_YELLOW} ${BOLD}${short_model}${RESET}"
fi

# ── Effort Level ─────────────────────────────────────────────
# .effort.level is present when the active model supports a reasoning-effort
# parameter (Opus / Sonnet / Haiku 4.x). Absent for older models. Color
# escalates with the spend level so a glance tells you when you're running
# the meter.
effort_part=""
if [ -n "$effort" ]; then
	case "$effort" in
	low) eff_color="${FG_GRAY}" ;;
	medium) eff_color="${FG_CYAN}" ;;
	high) eff_color="${FG_YELLOW}" ;;
	xhigh) eff_color="${FG_MAGENTA}" ;;
	max) eff_color="${FG_RED}" ;;
	*) eff_color="${FG_GRAY}" ;;
	esac
	effort_part="${eff_color} effort:${effort}${RESET}"
fi

# ── Pull Request ─────────────────────────────────────────────
pr_part=""
if [ -n "$pr_number" ]; then
	case "$pr_state" in
	approved) pr_color="${FG_GREEN}" ;;
	changes_requested) pr_color="${FG_RED}" ;;
	draft) pr_color="${FG_GRAY}" ;;
	pending | "") pr_color="${FG_YELLOW}" ;;
	*) pr_color="${FG_GRAY}" ;;
	esac
	pr_label="PR#${pr_number}"
	if [ -n "$pr_state" ]; then
		pr_label="${pr_label}:${pr_state}"
	fi
	pr_part="${pr_color} ${pr_label}${RESET}"
fi

# ── Context Progress Bar ─────────────────────────────────────
ctx_part=""
if [ -n "$used" ]; then
	used_int=${used%.*}
	if [ -n "$remaining" ]; then
		remaining_int=$(printf '%.0f' "$remaining")
	else
		remaining_int=$((100 - used_int))
	fi

	# Build an 8-block progress bar
	filled=$((used_int * 8 / 100))
	empty=$((8 - filled))

	bar=""
	for ((i = 0; i < filled; i++)); do bar="${bar}█"; done
	for ((i = 0; i < empty; i++)); do bar="${bar}░"; done

	# Color the bar based on usage level
	if [ "$used_int" -ge 85 ]; then
		bar_color="${FG_RED}"
	elif [ "$used_int" -ge 60 ]; then
		bar_color="${FG_YELLOW}"
	else
		bar_color="${FG_GREEN}"
	fi

	ctx_part="${FG_GRAY} ctx:${remaining_int}% left ${bar_color}${bar}${RESET}"
fi

# ── Tokens ───────────────────────────────────────────────────
tokens_part=""
if [ -n "$total_input" ] || [ -n "$total_output" ]; then
	total_input_int=${total_input:-0}
	total_output_int=${total_output:-0}
	total_tokens=$((total_input_int + total_output_int))
	tokens_part="${FG_GRAY} tok:$(format_count "$total_tokens") in:$(format_count "$total_input_int") out:$(format_count "$total_output_int")${RESET}"
fi

# ── Rate Limits ─────────────────────────────────────────────
limits_part=""
limit_bits=""
if [ -n "$five_h" ]; then
	five_int=$(printf '%.0f' "$five_h")
	if [ "$five_int" -ge 85 ]; then
		lc="${FG_RED}"
	elif [ "$five_int" -ge 60 ]; then
		lc="${FG_YELLOW}"
	else
		lc="${FG_GREEN}"
	fi
	limit_bits="${lc}5h:${five_int}%${RESET}"
fi
if [ -n "$seven_d" ]; then
	seven_int=$(printf '%.0f' "$seven_d")
	if [ "$seven_int" -ge 85 ]; then
		lc="${FG_RED}"
	elif [ "$seven_int" -ge 60 ]; then
		lc="${FG_YELLOW}"
	else
		lc="${FG_GREEN}"
	fi
	limit_bits="${limit_bits:+${limit_bits} }${lc}7d:${seven_int}%${RESET}"
fi
if [ -n "$limit_bits" ]; then
	limits_part="${FG_GRAY} ${limit_bits}"
fi

# ── Agent ────────────────────────────────────────────────────
agent_part=""
if [ -n "$agent" ]; then
	agent_part="${FG_GRAY} agent:${agent}${RESET}"
fi

# ── Task (session name) ──────────────────────────────────────
task_part=""
if [ -n "$session_name" ]; then
	task_part="${FG_GRAY} task:${session_name}${RESET}"
fi

# ── Version ──────────────────────────────────────────────────
version_part=""
if [ -n "$version" ]; then
	version_part="${FG_GRAY} v${version}${RESET}"
fi

# ── Tree State ───────────────────────────────────────────────
# Surface dirty-tree count when in a git repo. Replaces a Stop-event
# pre-commit-run hook (rejected as too slow + always-fires-regardless-of-cwd)
# with a passive indicator: ±N marks N files modified/staged/untracked.
# One extra git invocation per status tick (~5-15ms); only shown when dirty.
tree_part=""
added_int=${lines_added:-0}
removed_int=${lines_removed:-0}
if [ "$added_int" -gt 0 ] || [ "$removed_int" -gt 0 ]; then
	tree_part="${FG_YELLOW}Δ+${added_int}/-${removed_int}${RESET}"
fi
git_root=$(git -C "${cwd/#\~/$HOME}" rev-parse --show-toplevel 2>/dev/null)
if [ -n "$git_root" ]; then
	dirty=$(git -C "$git_root" status --porcelain 2>/dev/null | wc -l | tr -d ' ')
	if [ "$dirty" -gt 0 ]; then
		if [ -n "$tree_part" ]; then
			tree_part="${tree_part}${FG_YELLOW} ±${dirty}${RESET}"
		else
			tree_part="${FG_YELLOW}±${dirty}${RESET}"
		fi
	fi
fi

# ── Assemble ─────────────────────────────────────────────────
line="${dir_display}"

if [ -n "$git_part" ]; then line="${line}${SEP}${git_part}"; fi
if [ -n "$model_part" ]; then line="${line}${SEP}${model_part}"; fi
if [ -n "$effort_part" ]; then line="${line}${SEP}${effort_part}"; fi
if [ -n "$pr_part" ]; then line="${line}${SEP}${pr_part}"; fi
if [ -n "$tree_part" ]; then line="${line}${SEP}${tree_part}"; fi
if [ -n "$ctx_part" ]; then line="${line}${SEP}${ctx_part}"; fi
if [ -n "$limits_part" ]; then line="${line}${SEP}${limits_part}"; fi
if [ -n "$version_part" ]; then line="${line}${SEP}${version_part}"; fi
if [ -n "$tokens_part" ]; then line="${line}${SEP}${tokens_part}"; fi
if [ -n "$agent_part" ]; then line="${line}${SEP}${agent_part}"; fi
if [ -n "$task_part" ]; then line="${line}${SEP}${task_part}"; fi

printf '%b' "${line}"
