#!/usr/bin/env zsh

# Update all the AI CLI tools like a degenerate
alias burp='brew update && brew upgrade && claude update && opencode upgrade'

# Load Hippo CLI functions (only when installed; not on the home-lab box yet)
if [[ -f "$HOME/.local/share/hippo-brain/shell/hippo.zsh" ]]; then
    source "$HOME/.local/share/hippo-brain/shell/hippo-env.zsh"
    source "$HOME/.local/share/hippo-brain/shell/hippo.zsh"
fi

# ghcup (Haskell toolchain manager) why am I even doing this in 2026
#[ -f "$HOME/.ghcup/env" ] && . "$HOME/.ghcup/env" # ghcup-env

# Mill build tool completions
#source ~/.local/share/mill/completion/mill-completion.sh # MILL_SOURCE_COMPLETION_LINE
