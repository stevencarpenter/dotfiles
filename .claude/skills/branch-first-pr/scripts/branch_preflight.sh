#!/usr/bin/env bash
# branch_preflight.sh — report whether HEAD is on the repo's default branch and, if so,
# print the guardrail-safe recovery recipe (no `reset --hard`, which git-guardrails blocks).
# Resolves the default branch dynamically from origin/HEAD so it works whether the default
# is `main` or `master`.
set -euo pipefail

default_ref="$(git symbolic-ref --quiet refs/remotes/origin/HEAD 2>/dev/null || true)"
default="${default_ref#refs/remotes/origin/}"
if [ -z "$default" ]; then
  # Fall back: ask the remote, else guess main.
  default="$(
    git remote show origin 2>/dev/null | sed -n 's/.*HEAD branch: //p' | head -1 || true
  )"
  default="${default:-main}"
fi
head="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo UNKNOWN)"

printf 'default-branch: %s\n' "$default"
printf 'current HEAD:   %s\n' "$head"

if [ "$head" = "$default" ]; then
  cat <<EOF
STATUS: ON_DEFAULT_BRANCH — cut a feature branch before committing.

If you have NOT committed yet:
  git switch -c <type>/<short-desc>

If you ALREADY committed to ${default} (rewind onto a branch, guardrail-safe):
  git switch -c <type>/<short-desc>          # carries your commits onto the new branch
  git branch -f ${default} origin/${default} # move ${default} back WITHOUT reset --hard
  git log --oneline origin/${default}..${default}   # must print nothing
EOF
  exit 0
fi

printf "STATUS: OK — on feature branch '%s'.\n" "$head"
