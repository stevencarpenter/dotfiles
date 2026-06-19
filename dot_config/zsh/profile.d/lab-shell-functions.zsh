#!/usr/bin/env zsh

# Lab-mac (2019 i9 home server) shell functions. Mirrors the per-machine
# pattern from personal-shell-functions.zsh and work-shell-functions.zsh;
# deployment is gated in .chezmoiignore on `.machine == "lab-mac"`.

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
    opencode upgrade || failed+=('opencode')
    brew update      || failed+=('brew update')
    brew upgrade -y  || failed+=('brew upgrade')

    if (( $#failed )); then
        print -u2 "burp: failed: ${failed[*]}"
        return 1
    fi
    print 'burp: ok'
}
