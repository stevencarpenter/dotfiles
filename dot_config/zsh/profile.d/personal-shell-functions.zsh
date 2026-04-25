#!/usr/bin/env zsh

# Update all the AI CLI tools like a degenerate
alias burp='brew update && brew upgrade && vp update -g @github/copilot && claude update && opencode upgrade'

# Load Hippo CLI functions
source "$HOME/.local/share/hippo-brain/shell/hippo-env.zsh"
source "$HOME/.local/share/hippo-brain/hippo.zsh"

# Vite Plus CLI functions
source "$HOME/.vite-plus/env"

# ghcup (Haskell toolchain manager) why am I even doing this in 2026
#[ -f "$HOME/.ghcup/env" ] && . "$HOME/.ghcup/env" # ghcup-env

# Mill build tool completions
#source ~/.local/share/mill/completion/mill-completion.sh # MILL_SOURCE_COMPLETION_LINE
