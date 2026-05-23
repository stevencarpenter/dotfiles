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
effort=$(echo "$input"     | jq -r '.effort.level // empty')

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

# ── Effort Level ─────────────────────────────────────────────
# .effort.level is present when the active model supports a reasoning-effort
# parameter (Opus / Sonnet / Haiku 4.x). Absent for older models. Color
# escalates with the spend level so a glance tells you when you're running
# the meter.
effort_part=""
if [ -n "$effort" ]; then
  case "$effort" in
    low)    eff_color="${FG_GRAY}"    ;;
    medium) eff_color="${FG_CYAN}"    ;;
    high)   eff_color="${FG_YELLOW}"  ;;
    xhigh)  eff_color="${FG_MAGENTA}" ;;
    max)    eff_color="${FG_RED}"     ;;
    *)      eff_color="${FG_GRAY}"    ;;
  esac
  effort_part="${eff_color} ${effort}${RESET}"
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

# ── Machine ──────────────────────────────────────────────────
# Source: ~/.config/chezmoi/chezmoi.toml line `machine = "<name>"`. Reading
# this directly with awk is ~1-2ms; `chezmoi data` would shell out to a Go
# binary and add ~100ms+ per status tick — too expensive.
machine_part=""
machine=""
if [ -r "$HOME/.config/chezmoi/chezmoi.toml" ]; then
  machine=$(awk -F'"' '/^machine[[:space:]]*=/ { print $2; exit }' "$HOME/.config/chezmoi/chezmoi.toml" 2>/dev/null)
fi
if [ -n "$machine" ]; then
  case "$machine" in
    personal-mac) m_icon=" "; m_color="${FG_GREEN}"; m_short="personal" ;;
    work-mac)     m_icon=" "; m_color="${FG_BLUE}";  m_short="work"     ;;
    lab-mac)      m_icon=" "; m_color="${FG_CYAN}";  m_short="lab"      ;;
    *)            m_icon=" "; m_color="${FG_GRAY}";  m_short="$machine" ;;
  esac
  machine_part="${m_color}${m_icon}${m_short}${RESET}"
fi

# ── Hippo Daemon ─────────────────────────────────────────────
# Cheap liveness probe: socket file existence at the well-known path. A real
# RTT ping would be more accurate (catches stale socket files left by a
# crashed daemon) but would require either `nc -U` with a timeout or a CLI
# subprocess on every tick — too costly. Only shown on personal-mac (the
# machine that runs the hippo brain; hippo is personal-only).
hippo_part=""
if [ "$machine" = "personal-mac" ]; then
  if [ -S "$HOME/.local/share/hippo/daemon.sock" ]; then
    hippo_part="${FG_GREEN}hp✓${RESET}"
  else
    hippo_part="${FG_RED}hp✗${RESET}"
  fi
fi

# ── Tree State ───────────────────────────────────────────────
# Surface dirty-tree count when in a git repo. Replaces a Stop-event
# pre-commit-run hook (rejected as too slow + always-fires-regardless-of-cwd)
# with a passive indicator: ±N marks N files modified/staged/untracked.
# One extra git invocation per status tick (~5-15ms); only shown when dirty.
tree_part=""
git_root=$(git -C "${cwd/#\~/$HOME}" rev-parse --show-toplevel 2>/dev/null)
if [ -n "$git_root" ]; then
  dirty=$(git -C "$git_root" status --porcelain 2>/dev/null | wc -l | tr -d ' ')
  if [ "$dirty" -gt 0 ]; then
    tree_part="${FG_YELLOW}±${dirty}${RESET}"
  fi
fi

# ── Assemble ─────────────────────────────────────────────────
line="${dir_display}"

if [ -n "$git_part" ];     then line="${line}${SEP}${git_part}"; fi
if [ -n "$model_part" ];   then line="${line}${SEP}${model_part}"; fi
if [ -n "$effort_part" ];  then line="${line}${SEP}${effort_part}"; fi
if [ -n "$ctx_part" ];     then line="${line}${SEP}${ctx_part}"; fi
if [ -n "$limits_part" ];  then line="${line}${SEP}${limits_part}"; fi
if [ -n "$vim_part" ];     then line="${line}${SEP}${vim_part}"; fi
if [ -n "$session_part" ]; then line="${line}${SEP}${session_part}"; fi
if [ -n "$machine_part" ]; then line="${line}${SEP}${machine_part}"; fi
if [ -n "$hippo_part" ];   then line="${line}${SEP}${hippo_part}"; fi
if [ -n "$tree_part" ];    then line="${line}${SEP}${tree_part}"; fi

printf '%b' "${line}"
