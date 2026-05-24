#!/usr/bin/env zsh

# Update all the AI CLI tools like a degenerate
alias burp='brew update && brew upgrade && claude update && opencode upgrade'

# Jump into the long-lived tmux session on the i9 home server. mosh survives
# laptop sleep / network roam; `tmux new -A -s main` attaches-or-creates so you
# always land back where you left off. Plain `ssh i9` (see ~/.ssh/config.d/homelab)
# stays available for one-off / scp / non-interactive use.
alias i9='mosh i9 -- tmux new -A -s main'

# Load Hippo CLI functions (only when installed; not on the home-lab box yet)
if [[ -f "$HOME/.local/share/hippo-brain/shell/hippo.zsh" ]]; then
    source "$HOME/.local/share/hippo-brain/shell/hippo-env.zsh"
    source "$HOME/.local/share/hippo-brain/shell/hippo.zsh"
fi

# ghcup (Haskell toolchain manager) why am I even doing this in 2026
#[ -f "$HOME/.ghcup/env" ] && . "$HOME/.ghcup/env" # ghcup-env

# Mill build tool completions
#source ~/.local/share/mill/completion/mill-completion.sh # MILL_SOURCE_COMPLETION_LINE
