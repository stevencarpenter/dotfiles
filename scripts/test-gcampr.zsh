#!/usr/bin/env zsh
# Exercise the live gcampr function without committing, pushing, or creating a PR.
set -u

repo_root=${0:A:h:h}
source <(sed -n '/^function gcampr() {/,/^}/p' "$repo_root/home/.config/zsh/.zshrc")

fixture_branch=feature
events=()
gcamp_calls=0
pr_calls=0

function git() {
  case "$1 $2" in
    'branch --show-current') print -r -- "$fixture_branch" ;;
    'config --get') [[ "$3" == 'branch.feature.remote' ]] && print -r -- upstream ;;
    'fetch --quiet') [[ "$3 $4" == 'upstream main' ]] && events+=(fetch) ;;
    'merge-base FETCH_HEAD') print -r -- abc123 ;;
    *) return 1 ;;
  esac
}
function gh() {
  [[ "$*" == 'repo view --json defaultBranchRef --jq .defaultBranchRef.name' ]] && print -r -- main
}
function gcamp() { (( ++gcamp_calls )); events+=(gcamp); }
function codex() {
  events+=(codex)
  [[ "${(j: :)@}" == *'abc123...HEAD'* ]] || return 1
  while [[ "$1" != '--output-last-message' ]]; do shift; done
  print -r -- $'fix: Correct example behavior\n\n- Explain the actual change.' > "$2"
}
function gh-axi() {
  events+=(pr)
  (( ++pr_calls ))
  [[ "$1 $2 $3 $4 $5 $7" == 'pr create --base main --title --body' ]] &&
    [[ "$6" == 'fix: Correct example behavior' && "$8" == '- Explain the actual change.' ]]
}

gcampr || exit 1
[[ "$gcamp_calls $pr_calls ${(j: :)events}" == '1 1 gcamp fetch codex pr' ]] || exit 1

fixture_branch=main
if gcampr 2>/dev/null; then exit 1; fi
[[ "$gcamp_calls $pr_calls" == '1 1' ]] || exit 1

fixture_branch=feature
function codex() {
  while [[ "$1" != '--output-last-message' ]]; do shift; done
  print -r -- 'title only' > "$2"
}
if gcampr 2>/dev/null; then exit 1; fi
[[ "$pr_calls" == 1 ]] || exit 1
print -r -- 'gcampr checks passed'
