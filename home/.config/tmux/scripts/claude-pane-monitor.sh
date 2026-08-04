#!/usr/bin/env bash
# claude-pane-monitor.sh — detects Claude Code state per tmux window
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

# Update per-window Claude state
for win_id in $(tmux list-windows -F '#{window_id}' 2>/dev/null); do
    title=$(tmux display-message -t "$win_id" -p '#{pane_title}' 2>/dev/null) || continue

    # Non-Claude panes have directory paths as titles
    if [[ "$title" == ~* || "$title" == /* || -z "$title" ]]; then
        tmux set-option -wq -t "$win_id" @claude_state ""
        continue
    fi

    # Claude pane — detect state from pane title
    # ✳ = waiting for input (yellow), braille spinner = actively working (green)
    if [[ "$title" == *✳* ]]; then
        tmux set-option -wq -t "$win_id" @claude_state "idle"
    else
        tmux set-option -wq -t "$win_id" @claude_state "working"
    fi
done

# ── Teammate census ──────────────────────────────────────────────────────────
# Agent-team teammates are panes that nothing ever closes, so they pile up
# unseen. They were never hidden — `tmux list-panes -a` showed all 20 the whole
# time — they were just in a window nobody was looking at. So the fix is to put
# the count somewhere always visible rather than to hunt for them.
#
# ONE `ps` call, deliberately. This runs every status-interval (5s), so calling
# `agent-reap` here would spawn a Python process 12x/minute to diagnose a problem
# that is itself about wasted processes. awk does the counting instead.
#
# Thresholds are env-overridable so a machine that legitimately runs big teams can
# raise them without editing this script.
readonly WARN_AT="${CLAUDE_TEAMMATE_WARN:-4}"
readonly ALARM_AT="${CLAUDE_TEAMMATE_ALARM:-8}"

# The `$2 !~ /(^|\/)tmux$/` guard is load-bearing, not defensive noise: when a
# team is launched via `tmux new-window <claude --agent-id ...>`, the tmux SERVER's
# own argv contains a teammate's command line, so a naive match counts a phantom
# teammate that no pane corresponds to. Verified: 5 real teammates reported as 6.
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
    # Red past the alarm threshold, yellow before it — same stoplight vocabulary
    # the per-window colors already use, so it reads without a legend.
    if (( count >= ALARM_AT )); then
        colour="#e67e80"
    else
        colour="#dbbc7f"
    fi
    # Scale the unit: a run of small teammates rendering as "0.0G" reads as
    # "nothing to see here", which is the opposite of the point.
    if (( rss_kb >= 1048576 )); then
        size=$(awk -v k="$rss_kb" 'BEGIN{ printf "%.1fG", k/1048576 }')
    else
        size=$(awk -v k="$rss_kb" 'BEGIN{ printf "%dM", k/1024 }')
    fi
    printf '#[fg=%s]⚑%d agents %s#[default] ' "$colour" "$count" "$size"
fi
