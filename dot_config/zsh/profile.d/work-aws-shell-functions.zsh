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

# _awsp_check_token <profile> — emit a warning to stderr if the SSO token for
# this profile's sso_session is missing or expired. Never blocks. Local-only
# (no network call). Returns 0 on valid token, 1 otherwise.
_awsp_check_token() {
    local profile="$1"
    local session
    session="$(aws configure get sso_session --profile "$profile" 2>/dev/null)"
    if [[ -z "$session" ]]; then
        # Profile has no sso_session (e.g. a static-credentials profile). Skip.
        return 0
    fi

    local hash cache expires now
    hash="$(printf '%s' "$session" | shasum -a 1 | awk '{print $1}')"
    cache="$HOME/.aws/sso/cache/${hash}.json"
    if [[ ! -f "$cache" ]]; then
        print -u2 -r -- "⚠ SSO token missing — run: aws sso login --sso-session $session"
        return 1
    fi

    expires="$(jq -r '.expiresAt // empty' "$cache" 2>/dev/null)"
    if [[ -z "$expires" ]]; then
        print -u2 -r -- "⚠ SSO token cache unreadable at $cache"
        return 1
    fi

    # date -j -f "%Y-%m-%dT%H:%M:%SZ" is macOS-specific; aws writes UTC ISO8601.
    # Strip fractional seconds if present.
    expires="${expires%%.*}"
    expires="${expires%Z}"
    local exp_epoch
    exp_epoch="$(date -j -u -f '%Y-%m-%dT%H:%M:%S' "$expires" +%s 2>/dev/null)"
    now="$(date -u +%s)"
    if [[ -z "$exp_epoch" || "$exp_epoch" -le "$now" ]]; then
        print -u2 -r -- "⚠ SSO token expired — run: aws sso login --sso-session $session"
        return 1
    fi

    return 0
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
    _awsp_check_token "$profile"  # warn on expired/missing token; do not block
    print -r -- "AWS_PROFILE=$AWS_PROFILE"
}
