# gh-account.zsh — interactive conveniences for the GitHub CLI.
#
# ACCOUNT ROUTING NO LONGER LIVES HERE. It moved to ~/.local/bin/gh, a real
# script on PATH — read that file for the problem statement and the safety
# posture around the token.
#
# Why it moved: a shell function only ever existed for hand-typed `gh`. It does
# not exist for any subprocess, so every non-zsh caller silently bypassed it,
# most importantly coding agents (which run tools through a non-interactive
# bash shell) and gh-axi (which shells out to the `gh` BINARY). Both hit the
# CreatePullRequest permission error the routing was written to prevent, and
# the function could not have fixed either — the fix has to be on PATH.
#
# Keeping a `gh()` function here as well would be two implementations of one
# rule, drifting apart. There is exactly one now.

# Pinned gh-axi release. MUST match the pin in skills/personal/gh-axi/SKILL.md,
# which is the source of truth and explains why it is pinned at all: gh-axi runs
# with a full-write GitHub credential in scope, so `npx -y gh-axi` (unpinned)
# would execute whatever was published most recently. Bump both together, after
# reviewing the release.
: ${GH_AXI_PIN:=0.1.23}

# gh-axi is deliberately NOT installed — its skill says to invoke it as
# `npx -y gh-axi@<pin>`. This is a typing convenience only; it no longer needs
# to inject a token, because gh-axi shells out to `gh`, which is now the router
# on PATH. Invoking the npx form directly is equally well routed.
gh-axi() {
  emulate -L zsh
  command npx -y "gh-axi@${GH_AXI_PIN}" "$@"
}
