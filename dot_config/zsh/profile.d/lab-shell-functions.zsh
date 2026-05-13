#!/usr/bin/env zsh

# Lab-mac (2019 i9 home server) shell functions. Mirrors the per-machine
# pattern from personal-shell-functions.zsh and work-shell-functions.zsh;
# deployment is gated in .chezmoiignore on `.machine == "lab-mac"`.

# Update-or-install the brewed world + the AI CLI constellation. Each step
# runs independently — a transient registry blip on one package shouldn't
# kill the rest of the chain. Failed steps are collected and printed at the
# end so a quick `burp` makes its own diagnostics obvious.
function burp() {
    local failed=()
    brew update                              || failed+=('brew update')
    brew upgrade                             || failed+=('brew upgrade')
    npm install -g @anthropic-ai/claude-code || failed+=('claude')
    npm install -g @openai/codex             || failed+=('codex')
    npm install -g @github/copilot           || failed+=('copilot')
    npm install -g opencode-ai               || failed+=('opencode')
    if (( $#failed )); then
        print -u2 "burp: failed: ${failed[*]}"
        return 1
    fi
    print 'burp: ok'
}
