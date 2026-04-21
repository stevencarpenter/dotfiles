#!/usr/bin/env zsh
# AWS profile session switcher — work-only.
# Provides `awsp` (set AWS_PROFILE in current shell) and `awsx` (dedicated
# subshell/tmux window with AWS_PROFILE pre-exported). Shell-startup default
# remains: no AWS_PROFILE set.

# _awsp_pick — internal helper. Prints the selected profile name to stdout,
# returns non-zero on cancel/empty list. Uses fzf with a preview pane that
# greps the profile block out of ~/.aws/config.
_awsp_pick() {
    local profiles
    profiles="$(aws configure list-profiles 2>/dev/null)"
    if [[ -z "$profiles" ]]; then
        print -u2 "No AWS profiles found. Have you run aws-config-gen?"
        return 1
    fi

    local preview='awk -v p="[profile {r}]" '\''
        $0 == p { inblock=1; print; next }
        /^\[/   { inblock=0 }
        inblock { print }
    '\'' "$HOME/.aws/config"'

    print -r -- "$profiles" | fzf \
        --prompt='aws profile> ' \
        --height=40% \
        --reverse \
        --preview "$preview" \
        --preview-window=right:50%:wrap
}

# awsp — set AWS_PROFILE in the current shell.
#   awsp              → fzf picker
#   awsp <profile>    → direct set
#   awsp -            → unset AWS_PROFILE only (leaves AWS_ACCESS_KEY_ID etc.)
awsp() {
    if [[ "$1" == "-" ]]; then
        unset AWS_PROFILE
        print -r -- "AWS_PROFILE unset."
        return 0
    fi

    local profile="$1"
    if [[ -z "$profile" ]]; then
        profile="$(_awsp_pick)" || return $?
    fi

    export AWS_PROFILE="$profile"
    print -r -- "AWS_PROFILE=$AWS_PROFILE"
}
