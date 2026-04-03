#!/usr/bin/env bash
# Claude Code status line command — pimped out edition
# Reads JSON from stdin and outputs a styled, information-dense status line

input=$(cat)

cwd=$(echo "$input"        | jq -r '.workspace.current_dir // .cwd // empty')
model=$(echo "$input"      | jq -r '.model.display_name // empty')
used=$(echo "$input"       | jq -r '.context_window.used_percentage // empty')
five_h=$(echo "$input"     | jq -r '.rate_limits.five_hour.used_percentage // empty')
seven_d=$(echo "$input"    | jq -r '.rate_limits.seven_day.used_percentage // empty')
# remaining=$(echo "$input"  | jq -r '.context_window.remaining_percentage // empty')
session=$(echo "$input"    | jq -r '.session_name // empty')
vim_mode=$(echo "$input"   | jq -r '.vim.mode // empty')
worktree=$(echo "$input"   | jq -r '.worktree.branch // empty')

# user=$(whoami)
# host=$(hostname -s)

# Shorten home directory to ~
cwd="${cwd/#$HOME/~}"

# ANSI colors (dim-friendly — bold + bright colors readable even when dimmed)
RESET='\033[0m'
BOLD='\033[1m'

# Foreground colors
# FG_WHITE='\033[97m'
FG_CYAN='\033[96m'
FG_GREEN='\033[92m'
FG_YELLOW='\033[93m'
FG_MAGENTA='\033[95m'
FG_BLUE='\033[94m'
FG_RED='\033[91m'
FG_GRAY='\033[90m'

# Dim separator color
SEP_COLOR='\033[90m'
SEP="${SEP_COLOR}  ${RESET}"

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
  short_model="${short_model/Claude /}"          # strip "Claude " prefix
  model_part="${FG_YELLOW} ${BOLD}${short_model}${RESET}"
fi

# ── Context Progress Bar ─────────────────────────────────────
ctx_part=""
if [ -n "$used" ]; then
  used_int=${used%.*}

  # Build an 8-block progress bar
  filled=$(( used_int * 8 / 100 ))
  empty=$(( 8 - filled ))

  bar=""
  for (( i=0; i<filled; i++ ));  do bar="${bar}█"; done
  for (( i=0; i<empty; i++ ));   do bar="${bar}░"; done

  # Color the bar based on usage level
  if   [ "$used_int" -ge 85 ]; then bar_color="${FG_RED}"
  elif [ "$used_int" -ge 60 ]; then bar_color="${FG_YELLOW}"
  else                               bar_color="${FG_GREEN}"
  fi

  ctx_part="${FG_GRAY} ${bar_color}${bar}${RESET}${FG_GRAY} ${used_int}%${RESET}"
fi

# ── Rate Limits ─────────────────────────────────────────────
limits_part=""
limit_bits=""
if [ -n "$five_h" ]; then
  five_int=$(printf '%.0f' "$five_h")
  if   [ "$five_int" -ge 85 ]; then lc="${FG_RED}"
  elif [ "$five_int" -ge 60 ]; then lc="${FG_YELLOW}"
  else                               lc="${FG_GREEN}"
  fi
  limit_bits="${lc}5h:${five_int}%${RESET}"
fi
if [ -n "$seven_d" ]; then
  seven_int=$(printf '%.0f' "$seven_d")
  if   [ "$seven_int" -ge 85 ]; then lc="${FG_RED}"
  elif [ "$seven_int" -ge 60 ]; then lc="${FG_YELLOW}"
  else                                lc="${FG_GREEN}"
  fi
  limit_bits="${limit_bits:+${limit_bits} }${lc}7d:${seven_int}%${RESET}"
fi
if [ -n "$limit_bits" ]; then
  limits_part="${FG_GRAY} ${limit_bits}"
fi

# ── Vim Mode ─────────────────────────────────────────────────
vim_part=""
if [ -n "$vim_mode" ]; then
  if [ "$vim_mode" = "NORMAL" ]; then
    vim_part="${FG_CYAN}${BOLD} NORMAL${RESET}"
  else
    vim_part="${FG_GREEN}${BOLD} INSERT${RESET}"
  fi
fi

# ── Session Name ─────────────────────────────────────────────
session_part=""
if [ -n "$session" ]; then
  session_part="${FG_GRAY} ${session}${RESET}"
fi

# ── Assemble ─────────────────────────────────────────────────
line="${dir_display}"

if [ -n "$git_part" ];     then line="${line}${SEP}${git_part}"; fi
if [ -n "$model_part" ];   then line="${line}${SEP}${model_part}"; fi
if [ -n "$ctx_part" ];     then line="${line}${SEP}${ctx_part}"; fi
if [ -n "$limits_part" ];  then line="${line}${SEP}${limits_part}"; fi
if [ -n "$vim_part" ];     then line="${line}${SEP}${vim_part}"; fi
if [ -n "$session_part" ]; then line="${line}${SEP}${session_part}"; fi

printf '%b' "${line}"
