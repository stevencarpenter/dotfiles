#!/usr/bin/env zsh
# Exercise the live gcampr function without committing, pushing, or creating a PR.
set -u

repo_root=${0:A:h:h}
source <(sed -n '/^typeset -ga _gcam_claude_args=(/,/^)/p' "$repo_root/home/.config/zsh/.zshrc")
source <(sed -n '/^function gcampr() {/,/^}/p' "$repo_root/home/.config/zsh/.zshrc")

fixture_branch=feature
fixture_changes=' M tracked-file'
fixture_prs=0
events=()
gcamp_calls=0
push_calls=0
pr_calls=0

function git() {
  case "$1 ${2-}" in
    'branch --show-current') print -r -- "$fixture_branch" ;;
    'status --porcelain') print -r -- "$fixture_changes" ;;
    'config --get') [[ "$3" == 'branch.feature.remote' ]] && print -r -- upstream ;;
    'push ') (( ++push_calls )); events+=(push) ;;
    'fetch --quiet') [[ "$3 $4" == 'upstream main' ]] && events+=(fetch) ;;
    'merge-base FETCH_HEAD') print -r -- abc123 ;;
    *) return 1 ;;
  esac
}
function gh() {
  [[ "$*" == 'repo view --json defaultBranchRef --jq .defaultBranchRef.name' ]] && print -r -- main
}
function gcamp() { (( ++gcamp_calls )); events+=(gcamp); }
function claude() {
  events+=(claude)
  [[ "${(j: :)@}" == *'abc123...HEAD'* ]] || return 1
  print -r -- $'fix: Correct example behavior\n\n- Explain the actual change.\n- Cover the full branch.'
}
function gh-axi() {
  if [[ "$1 $2" == 'pr list' ]]; then
    [[ "$3 $4 $5 $6 $7 $8" == '--state open --head feature --limit 2' ]] || return 1
    if (( fixture_prs == 0 )); then
      print -r -- 'count: 0'
      print -r -- 'pull_requests: []'
    else
      print -r -- "count: $fixture_prs"
      print -r -- "pull_requests[$fixture_prs]{number,title,state,author,draft,review}:"
      print -r -- '  42,"Existing PR",open,me,no,none'
      (( fixture_prs == 2 )) && print -r -- '  43,"Another PR",open,me,no,none'
    fi
    return 0
  fi
  events+=(pr)
  (( ++pr_calls ))
  if [[ "$2" == create ]]; then
    [[ "$1 $2 $3 $4 $5 $7" == 'pr create --base main --title --body-file' ]] &&
      [[ "$6" == 'fix: Correct example behavior' ]] &&
      [[ "$(<"$8")" == $'- Explain the actual change.\n- Cover the full branch.' ]]
  else
    [[ "$1 $2 $3 $4 $6" == 'pr edit 42 --title --body-file' ]] &&
      [[ "$5" == 'fix: Correct example behavior' ]] &&
      [[ "$(<"$7")" == $'- Explain the actual change.\n- Cover the full branch.' ]]
  fi
}

gcampr || exit 1
[[ "$gcamp_calls $push_calls $pr_calls ${(j: :)events}" == '1 0 1 gcamp fetch claude pr' ]] || exit 1

fixture_changes=''
fixture_prs=1
gcampr || exit 1
[[ "$gcamp_calls $push_calls $pr_calls ${(j: :)events}" == '1 1 2 gcamp fetch claude pr push fetch claude pr' ]] || exit 1

fixture_prs=2
if gcampr 2>/dev/null; then exit 1; fi
[[ "$pr_calls" == 2 ]] || exit 1

fixture_branch=main
if gcampr 2>/dev/null; then exit 1; fi
[[ "$gcamp_calls $push_calls $pr_calls" == '1 2 2' ]] || exit 1

fixture_branch=feature
fixture_prs=0
function claude() { print -r -- 'title only'; }
if gcampr 2>/dev/null; then exit 1; fi
[[ "$pr_calls" == 2 ]] || exit 1
print -r -- 'gcampr checks passed'
