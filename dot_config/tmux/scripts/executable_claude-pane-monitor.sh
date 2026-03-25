#!/usr/bin/env bash
# claude-pane-monitor.sh — detects Claude Code state per tmux window
# Called from dotbar's status-right via #(), outputs nothing (side effects only)
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
