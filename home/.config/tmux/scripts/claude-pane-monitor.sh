#!/usr/bin/env bash
# claude-pane-monitor.sh: detects Claude Code state per tmux window
# Called from dotbar's status-right via #(). Side effects, plus it prints the
# runaway-teammate badge (empty string when there is nothing to report).
# Sets @claude_state per window: idle | working | (empty for non-Claude)
# Dotbar's @tmux-dotbar-window-status-format reads @claude_state for text color:
#   green  #a7c080 = working  (actively running, braille spinner in pane title)
#   yellow #dbbc7f = idle     (waiting for input, ✳ in pane title)
set -euo pipefail

# Ensure all status bar backgrounds match Ghostty terminal bg (#2f383e)
tmux set-option -gq status-style "bg=#2f383e"
tmux set-option -gq status-bg "#2f383e"
tmux set-option -gq window-status-style "bg=#2f383e"
tmux set-option -gq window-status-current-style "bg=#2f383e"

# Override active tab format: underline + brighter text (dotbar has no underline option)
tmux set-option -gq window-status-current-format \
  '#[fg=#d3c6aa,bg=#2f383e,underscore,us=#83c092]#{?#{==:#{@claude_state},working},#[fg=#a7c080],#{?#{==:#{@claude_state},idle},#[fg=#dbbc7f],}} #W #[nounderscore]'

# Classify only leading Claude state markers; other programs also set pane titles.
for win_id in $(tmux list-windows -F '#{window_id}' 2>/dev/null); do
    title=$(tmux display-message -t "$win_id" -p '#{pane_title}' 2>/dev/null) || continue

    # Claude pane: detect state only from its leading state marker.
    # ✳ = waiting for input (yellow), braille spinner = actively working (green).
    if [[ "$title" == ✳* ]]; then
        tmux set-option -wq -t "$win_id" @claude_state "idle"
    elif [[ "$title" =~ ^[⠀-⣿][[:space:]] ]]; then
        tmux set-option -wq -t "$win_id" @claude_state "working"
    else
        tmux set-option -wq -t "$win_id" @claude_state ""
    fi
done

# Count teammates with one ps call per five-second status refresh.
# Override thresholds for machines that run larger teams.
readonly WARN_AT="${CLAUDE_TEAMMATE_WARN:-4}"
readonly ALARM_AT="${CLAUDE_TEAMMATE_ALARM:-8}"

# Exclude tmux itself: its server argv can contain the teammate launch command.
census=$(ps -eo rss=,command= 2>/dev/null |
    awk '/--agent-id [^ ]+@session-/ && $2 !~ /(^|\/)tmux$/ { n++; kb += $1 }
         END { print n+0, kb+0 }') || census="0 0"
count=${census% *}
rss_kb=${census#* }

# Publish for other consumers (sketchybar, `tmux show -gv @claude_teammates`)
# even when below the display threshold.
tmux set-option -gq @claude_teammates "$count"
tmux set-option -gq @claude_teammate_rss_kb "$rss_kb"

if (( count >= WARN_AT )); then
    if (( count >= ALARM_AT )); then
        colour="#e67e80"
    else
        colour="#dbbc7f"
    fi
    # Use MiB below 1 GiB so small processes do not display as 0.0G.
    if (( rss_kb >= 1048576 )); then
        size=$(awk -v k="$rss_kb" 'BEGIN{ printf "%.1fG", k/1048576 }')
    else
        size=$(awk -v k="$rss_kb" 'BEGIN{ printf "%dM", k/1024 }')
    fi
    printf '#[fg=%s]⚑%d agents %s#[default] ' "$colour" "$count" "$size"
fi
