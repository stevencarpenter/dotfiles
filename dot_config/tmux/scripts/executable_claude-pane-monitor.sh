#!/usr/bin/env bash
# claude-pane-monitor.sh — detects Claude Code state per tmux window
# Called from status-right via #(), outputs nothing (runs for side effects only)
#
# 1. Re-applies window-status-format with Claude state colors
#    (theme plugins overwrite config-level overrides, so we force it here)
# 2. Sets @claude_state per window: idle | working | (empty)
#
# Everforest stoplight colors:
#   green  #a7c080 = idle    (waiting for input, ✳ in pane title)
#   yellow #dbbc7f = working (braille spinner in pane title)
set -euo pipefail

# ── Re-apply window formats (theme plugins overwrite post-TPM config) ──────

# Inactive: Claude state color, fallback to everforest grey
tmux set-option -gq window-status-format \
  '#{?#{==:#{@claude_state},idle},#[fg=#a7c080],#{?#{==:#{@claude_state},working},#[fg=#dbbc7f],#[fg=#{@everforest_grey0}]}}#[bg=#{@everforest_bg0}] #I  #W '

# Active: Claude state as powerline tab bg, fallback to everforest bg_green
tmux set-option -gq window-status-current-format \
  '#[fg=#{@everforest_bg0},bg=#{?#{==:#{@claude_state},idle},#a7c080,#{?#{==:#{@claude_state},working},#dbbc7f,#{@everforest_bg_green}}}]#[fg=#{?#{@claude_state},#{@everforest_bg0},#{@everforest_fg}},bg=#{?#{==:#{@claude_state},idle},#a7c080,#{?#{==:#{@claude_state},working},#dbbc7f,#{@everforest_bg_green}}}] #I  #[bold]#W #[fg=#{?#{==:#{@claude_state},idle},#a7c080,#{?#{==:#{@claude_state},working},#dbbc7f,#{@everforest_bg_green}}},bg=#{@everforest_bg0},nobold]'

# ── Update per-window Claude state ─────────────────────────────────────────

for win_id in $(tmux list-windows -F '#{window_id}' 2>/dev/null); do
    title=$(tmux display-message -t "$win_id" -p '#{pane_title}' 2>/dev/null) || continue

    # Non-Claude panes have directory paths as titles
    if [[ "$title" == ~* || "$title" == /* || -z "$title" ]]; then
        tmux set-option -wq -t "$win_id" @claude_state ""
        continue
    fi

    # Claude pane — detect state from pane title
    # ✳ = idle/waiting for input, braille spinner = actively working
    if [[ "$title" == *✳* ]]; then
        tmux set-option -wq -t "$win_id" @claude_state "idle"
    else
        tmux set-option -wq -t "$win_id" @claude_state "working"
    fi
done
