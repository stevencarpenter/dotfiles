#!/usr/bin/env zsh

# BEGIN_AWS_SSO_CLI
# AWS SSO requires `bashcompinit` which needs to be enabled once and
# only once in your shell. The autoload lines are at the top of the .zshrc
# that loads this file, so that they are available for all of the aws-sso
# CLI functions below.
# OUTSIDE of the BEGIN/END_AWS_SSO_CLI markers.

__aws_sso_profile_complete() {
     local _args=${AWS_SSO_HELPER_ARGS:- -L error}
    _multi_parts : "($(/opt/homebrew/bin/aws-sso ${=_args} list --csv Profile))"
}

__aws_profile_from_args() {
    emulate -L zsh
    local prev=''
    local arg=''
    for arg in "$@"; do
        if [[ "$prev" == "--profile" || "$prev" == "-p" ]]; then
            print -r -- "$arg"
            return 0
        fi
        case "$arg" in
            --profile=*)
                print -r -- "${arg#--profile=}"
                return 0
                ;;
            -p?*)
                print -r -- "${arg#-p}"
                return 0
                ;;
            --profile|-p)
                prev="$arg"
                continue
                ;;
        esac
        prev=''
    done
    return 1
}

aws-sso() {
    local _bin=/opt/homebrew/bin/aws-sso
    command "$_bin" "$@"
    local rc=$?
    if (( rc != 0 )); then
        return $rc
    fi

    if (( ${argv[(I)login]} )); then
        local profile
        profile="$(__aws_profile_from_args "$@")"
        if [[ -n "$profile" ]]; then
            export AWS_SSO_PROFILE="$profile"
        fi
        export AWS_DEFAULT_PROFILE=default
    elif (( ${argv[(I)logout]} || ${argv[(I)clear]} )); then
        unset AWS_SSO_PROFILE
        unset AWS_DEFAULT_PROFILE
    fi
}

aws-sso-profile() {
    local _args=${AWS_SSO_HELPER_ARGS:- -L error}
    if [ -n "$AWS_PROFILE" ]; then
        echo "Unable to assume a role while AWS_PROFILE is set"
        return 1
    fi

    if [ -z "$1" ]; then
        echo "Usage: aws-sso-profile <profile>"
        return 1
    fi

    eval $(/opt/homebrew/bin/aws-sso ${=_args} eval -p "$1")
    if [ "$AWS_SSO_PROFILE" != "$1" ]; then
        return 1
    fi
    export AWS_DEFAULT_PROFILE=default
}

aws-sso-clear() {
    local _args=${AWS_SSO_HELPER_ARGS:- -L error}
    if [ -z "$AWS_SSO_PROFILE" ]; then
        echo "AWS_SSO_PROFILE is not set"
        return 1
    fi
    eval $(""/opt/homebrew/bin/aws-sso ${=_args} eval -c)
    unset AWS_DEFAULT_PROFILE

  # Register completions for custom functions
  compdef _directories md
  local aws_sso_path
  aws_sso_path="$(command -v aws-sso 2>/dev/null)"
  if [[ -n "$aws_sso_path" ]]; then
    compdef __aws_sso_profile_complete aws-sso-profile
    complete -C "$aws_sso_path" aws-sso
  fi
}
# END_AWS_SSO_CLI

# AWS SSO profile management for role assumption. This is a helper function that
# uses the AWS CLI to assume a role and set the appropriate environment variables
# for the session. It requires that you already have credentials in your environment
# for the account you are assuming a role in, which can be managed using the
# aws-sso-profile function above.
function get_assumed_role_credentials() {
    if [ $# -lt 2 ]; then
        echo "Usage: get_assumed_role_credentials <role-arn> <session-name>"
        echo "You must already have credentials in your environment for the account you are assuming a role in."
        echo "Use aws-sso-profile, or asp if you are using my aliases, and select the role for the account via the autocompletion mechanism."
        return 1
    fi

    export $(printf "AWS_ACCESS_KEY_ID=%s AWS_SECRET_ACCESS_KEY=%s AWS_SESSION_TOKEN=%s" \
    $(aws sts assume-role \
    --role-arn $1 \
    --role-session-name $2 \
    --query "Credentials.[AccessKeyId,SecretAccessKey,SessionToken]" \
    --output text))
}
