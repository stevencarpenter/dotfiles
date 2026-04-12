#!/usr/bin/env zsh

# Update all the AI CLI tools like a degenerate
alias burp='brew update && brew upgrade && npm install -g @github/copilot && npm install -g @openai/codex && claude update'

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
