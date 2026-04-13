#!/usr/bin/env zsh

# Update all the AI CLI tools like a degenerate
alias burp='brew update && brew upgrade && vp update -g @github/copilot && claude update && opencode upgrade && amp update'

# Load Hippo CLI functions
source /Users/carpenter/projects/hippo/shell/hippo-env.zsh
source /Users/carpenter/projects/hippo/shell/hippo.zsh

# Vite Plus CLI functions
source "$HOME/.vite-plus/env"

# ghcup (Haskell toolchain manager) why am I even doing this in 2026
#[ -f "/Users/carpenter/.ghcup/env" ] && . "/Users/carpenter/.ghcup/env" # ghcup-env

# Mill build tool completions
#source ~/.local/share/mill/completion/mill-completion.sh # MILL_SOURCE_COMPLETION_LINE
