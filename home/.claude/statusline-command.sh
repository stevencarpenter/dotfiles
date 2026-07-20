#!/usr/bin/env bash
# Claude Code status line command — pimped out edition
# Reads JSON from stdin and outputs a styled, information-dense status line

# -u catches unset-variable bugs. No -e: the git probes below are expected to
# fail in non-repo cwds.
set -uo pipefail

input=$(cat)

# Single jq pass for every field (this script runs on each render tick).
# Fields are joined on the unit separator (\x1f): unlike tab, it is not IFS
# whitespace, so empty fields don't collapse and columns stay aligned. The
# per-field gsub strips CR/LF: `read` consumes a single line, so a newline in
# any value (e.g. a user-set session_name) would otherwise truncate that field
# and silently drop every field after it. `jq <<<` feeds stdin verbatim —
# unlike `echo`, which can interpret backslashes under some shell settings.
IFS=$'\x1f' read -r cwd model used remaining cost_usd duration_ms \
	five_h seven_d worktree effort version pr_number pr_state agent \
	session_name lines_added lines_removed < <(
	jq -r '[
		(.workspace.current_dir // .cwd // ""),
		(.model.display_name // ""),
		(.context_window.used_percentage // ""),
		(.context_window.remaining_percentage // ""),
		(.cost.total_cost_usd // ""),
		(.cost.total_duration_ms // ""),
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
	] | map(tostring | gsub("[\n\r]"; " ")) | join("\u001f")' <<<"$input"
)

# Shorten home directory to ~
cwd="${cwd/#$HOME/~}"

# Single git probe for the whole render: resolve repo root AND current branch in
# ONE shell-out (rev-parse prints --show-toplevel then --abbrev-ref on separate
# lines), reused by the branch and tree-state segments below. Was up to three
# `git` invocations per tick; now two (this + the `status --porcelain` count).
cwd_abs="${cwd/#\~/$HOME}"
git_info=$(git -C "$cwd_abs" rev-parse --show-toplevel --abbrev-ref HEAD 2>/dev/null)
git_root="${git_info%%$'\n'*}"
git_branch=""
if [ -n "$git_info" ]; then
	git_branch="${git_info#*$'\n'}"
fi

# Everforest dark-hard truecolor palette. Using explicit RGB avoids Ghostty /
# tmux mapping secondary text to ANSI bright-black, which is too dim here.
# ANSI-C quoting ($'...') stores real ESC bytes, so the final printf uses %s
# (not %b). A cwd or branch containing a literal "\t"/"\n" then renders as-is
# instead of being expanded into a tab/newline. Keep $'...' and %s in sync.
RESET=$'\033[0m'
BOLD=$'\033[1m'

# Foreground colors
FG_CYAN=$'\033[38;2;131;192;146m'
FG_GREEN=$'\033[38;2;167;192;128m'
FG_YELLOW=$'\033[38;2;219;188;127m'
FG_MAGENTA=$'\033[38;2;214;153;182m'
FG_BLUE=$'\033[38;2;127;187;179m'
FG_RED=$'\033[38;2;230;126;128m'
FG_GRAY=$'\033[38;2;211;198;170m'

# Dim separator color
SEP_COLOR=$'\033[38;2;157;169;160m'
SEP="${SEP_COLOR}  ${RESET}"

format_duration() {
	# Milliseconds → compact h/m/s. Echoes nothing for empty/non-integer input
	# (caller normalizes via to_int first, so junk degrades to a skipped segment).
	local ms="$1"
	if [ -z "$ms" ]; then
		return
	fi
	local secs=$((ms / 1000))
	if ((secs >= 3600)); then
		printf '%dh%dm' $((secs / 3600)) $(((secs % 3600) / 60))
	elif ((secs >= 60)); then
		printf '%dm%ds' $((secs / 60)) $((secs % 60))
	else
		printf '%ds' "$secs"
	fi
}

color_for_pct() {
	local pct="$1"
	local pct_int

	pct_int=$(printf '%.0f' "$pct")
	if [ "$pct_int" -ge 85 ]; then
		echo "$FG_RED"
	elif [ "$pct_int" -ge 60 ]; then
		echo "$FG_YELLOW"
	else
		echo "$FG_GREEN"
	fi
}

to_int() {
	# Echo a non-negative integer for integer or simple-decimal input (rounding
	# decimals); echo nothing for empty or non-numeric input. Claude Code emits
	# these fields as integers today, but a schema drift to a float or a string
	# like "NaN" would otherwise abort the whole render at the first $((...))
	# under `set -u`, blanking the entire status line before it prints.
	local v="$1"
	if [[ "$v" =~ ^[0-9]+$ ]]; then
		printf '%s' "$v"
	elif [[ "$v" =~ ^[0-9]+\.[0-9]+$ ]]; then
		printf '%.0f' "$v"
	fi
}

# Normalize every field that feeds arithmetic or an integer comparison below,
# so one malformed value degrades to a skipped segment instead of a blank line.
used="$(to_int "$used")"
remaining="$(to_int "$remaining")"
duration_ms="$(to_int "$duration_ms")"
five_h="$(to_int "$five_h")"
seven_d="$(to_int "$seven_d")"
lines_added="$(to_int "$lines_added")"
lines_removed="$(to_int "$lines_removed")"

# ── Current Directory ────────────────────────────────────────
dir_display="${BOLD}${FG_BLUE} ${cwd}${RESET}"

# ── Git Branch ───────────────────────────────────────────────
git_part=""
# Prefer the worktree branch from the payload; otherwise use the branch resolved
# by the single git probe above (no extra shell-out).
if [ -n "$worktree" ]; then
	git_part="${FG_MAGENTA} ${worktree}${RESET}"
elif [ -n "$git_branch" ]; then
	git_part="${FG_MAGENTA} ${git_branch}${RESET}"
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
if [ -n "$used" ] || [ -n "$remaining" ]; then
	# Both fields are already integers (to_int'd) or empty. Derive whichever the
	# payload omitted so the bar still renders from a single field — the segment
	# no longer vanishes if the schema ever drops `used_percentage`.
	if [ -n "$used" ]; then
		used_int="$used"
	else
		used_int=$((100 - remaining))
	fi
	if [ -n "$remaining" ]; then
		remaining_int="$remaining"
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
	bar_color="$(color_for_pct "$used_int")"

	ctx_part="${FG_GRAY} ctx:${remaining_int}% left ${bar_color}${bar}${RESET}"
fi

# ── Session Cost Meter ───────────────────────────────────────
# Claude Code exposes NO cumulative token count: as of v2.1.132 the
# context_window.total_{input,output}_tokens fields are a per-turn snapshot
# (output is the LAST response only), not a session total — so summing them
# was semantically wrong. The genuinely cumulative session signals live under
# `cost`: dollar spend + wall-clock. Show those instead.
cost_part=""
cost_bits=""
# cost_usd is fractional dollars (not run through to_int); validate before awk
# so a "NaN"/garbage value degrades to a skipped segment, not a "$nan" render.
if [[ "$cost_usd" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
	cost_bits="$(awk -v c="$cost_usd" 'BEGIN { printf "$%.2f", c }')"
fi
dur_fmt="$(format_duration "$duration_ms")"
if [ -n "$dur_fmt" ]; then
	cost_bits="${cost_bits:+${cost_bits} }⧗${dur_fmt}"
fi
if [ -n "$cost_bits" ]; then
	cost_part="${FG_GRAY} ${cost_bits}${RESET}"
fi

# ── Rate Limits ─────────────────────────────────────────────
limits_part=""
limit_bits=""
if [ -n "$five_h" ]; then
	lc="$(color_for_pct "$five_h")"
	limit_bits="${lc}5h:${five_h}%${RESET}"
fi
if [ -n "$seven_d" ]; then
	lc="$(color_for_pct "$seven_d")"
	limit_bits="${limit_bits:+${limit_bits} }${lc}7d:${seven_d}%${RESET}"
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
parts=("$dir_display")
[[ -n "$git_part" ]] && parts+=("$git_part")
[[ -n "$model_part" ]] && parts+=("$model_part")
[[ -n "$effort_part" ]] && parts+=("$effort_part")
[[ -n "$pr_part" ]] && parts+=("$pr_part")
[[ -n "$tree_part" ]] && parts+=("$tree_part")
[[ -n "$ctx_part" ]] && parts+=("$ctx_part")
[[ -n "$limits_part" ]] && parts+=("$limits_part")
[[ -n "$version_part" ]] && parts+=("$version_part")
[[ -n "$cost_part" ]] && parts+=("$cost_part")
[[ -n "$agent_part" ]] && parts+=("$agent_part")
[[ -n "$task_part" ]] && parts+=("$task_part")

line="${parts[0]}"
for part in "${parts[@]:1}"; do
	line="${line}${SEP}${part}"
done

printf '%s' "${line}"
