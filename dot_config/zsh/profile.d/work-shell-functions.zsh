#!/usr/bin/env zsh

# Update the brewed world + the AI CLI constellation via each tool's native
# self-update subcommand. Each step runs independently — a transient registry
# blip on one package shouldn't kill the rest of the chain. Failed steps are
# collected and printed at the end so a quick `burp` makes its own diagnostics
# obvious.
function burp() {
    local failed=()
    claude update    || failed+=('claude')
    codex update     || failed+=('codex')
    copilot update   || failed+=('copilot')
    brew update      || failed+=('brew update')
    brew upgrade -y  || failed+=('brew upgrade')

    if (( $#failed )); then
        print -u2 "burp: failed: ${failed[*]}"
        return 1
    fi
    print 'burp: ok'
}

# STS assume-role helper. Generic — requires existing AWS credentials in the
# environment for the source account (e.g. from aws-config-gen or any other
# profile mechanism).
function get_assumed_role_credentials() {
    if [ $# -lt 2 ]; then
        echo "Usage: get_assumed_role_credentials <role-arn> <session-name>"
        echo "You must already have credentials in your environment for the source account."
        return 1
    fi

    export $(printf "AWS_ACCESS_KEY_ID=%s AWS_SECRET_ACCESS_KEY=%s AWS_SESSION_TOKEN=%s" \
    $(aws sts assume-role \
    --role-arn $1 \
    --role-session-name $2 \
    --query "Credentials.[AccessKeyId,SecretAccessKey,SessionToken]" \
    --output text))
}
