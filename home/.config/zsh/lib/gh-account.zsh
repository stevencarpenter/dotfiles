# gh-account.zsh — route GitHub CLI calls to the account that owns the current repo.
#
# THE PROBLEM: `gh` has exactly one *active* account per host. There is no per-repo,
# per-directory, or config-file account selection (checked on gh 2.97: only `gh auth token
# --user` names an account; everything else follows the active one). On a machine logged
# into both a work and a personal account, whichever is active loses in the other's repos —
# and the failure is confusing rather than obvious, because git and gh disagree:
#
#   $ git push                 # works — the remote's SSH key decides
#   $ gh pr create             # GraphQL: <work-user> does not have the correct permissions
#
# Git authenticates per-remote via SSH; gh authenticates per-*account*. So a push can
# succeed against a repo whose PRs you cannot create.
#
# THE FIX: derive the owner from `origin`, and if it maps to a known account, hand `gh` that
# account's token for the single invocation. Nothing is exported: a GitHub token with full
# write scope in the ambient environment is readable by every same-user process, so it lives
# in one command's environment and dies with it — the same discipline the op-render path uses
# for OP_SESSION_*.
#
# WHY A SHELL FUNCTION AND NOT `gh auth switch`: switching is global and sticky. It would
# silently leave the wrong account active for the next repo you visit, which is the bug this
# fixes, one directory later.

# Owner -> gh account that can write to it. Owners absent from this map fall through to
# whatever account is active, so a work repo needs no entry and gets no surprises.
typeset -gA GH_ACCOUNT_BY_OWNER=(
  stevencarpenter stevencarpenter
)

# Pinned gh-axi release. MUST match the pin in skills/personal/gh-axi/SKILL.md, which is the
# source of truth and explains why it is pinned at all: gh-axi runs with a full-write GitHub
# credential in scope, so `npx -y gh-axi` (unpinned) would execute whatever was published
# most recently. Bump both together, after reviewing the release.
: ${GH_AXI_PIN:=0.1.23}

# Echo the token for the account owning $PWD's origin remote, or nothing.
_gh_account_token() {
  emulate -L zsh
  # NEVER name a local `path` here. zsh ties `path` to `$PATH` as a special array, so
  # `local path` blanks PATH for the whole function — `command git` and `command gh` stop
  # resolving, and with stderr redirected below it looks exactly like a repo with no
  # origin remote. Same trap applies to cdpath, fpath, and manpath.
  local url slug owner account
  url=$(command git remote get-url origin 2>/dev/null) || return 1
  [[ -n $url ]] || return 1
  # Strip the .git suffix BEFORE matching, and keep the pattern greedy-only. zsh's `=~` is
  # POSIX ERE, not PCRE: a lazy `+?` does not mean "non-greedy" here, it fails to COMPILE
  # ("repetition-operator operand invalid"), which a bare `|| return 1` then hides as a
  # silent no-match on every single call. Handles every remote spelling in use: scp-like
  # with or without user@ (github-dotfiles:owner/repo.git, git@github.com:owner/repo.git),
  # https://, and ssh://.
  slug=${url%.git}
  [[ $slug =~ '[:/]([^/:]+)/([^/:]+)$' ]] || return 1
  owner=$match[1]
  account=${GH_ACCOUNT_BY_OWNER[$owner]:-}
  [[ -n $account ]] || return 1
  # A machine may simply not be logged into the mapped account. That is not an error worth
  # interrupting a command over — fall through to the active account instead.
  command gh auth token --user "$account" 2>/dev/null
}

gh() {
  emulate -L zsh
  # `gh auth ...` must NOT see a forced GH_TOKEN: `auth switch`/`auth login` refuse to run
  # while it is set, and `auth status` would report the injected token instead of the real
  # account state. Managing accounts has to stay possible from inside a mapped repo.
  if [[ $1 == auth ]]; then
    command gh "$@"
    return
  fi
  local token
  token=$(_gh_account_token) || token=""
  if [[ -n $token ]]; then
    GH_TOKEN=$token command gh "$@"
  else
    command gh "$@"
  fi
}

# gh-axi is the preferred GitHub interface (see ~/.claude/CLAUDE.md) and is deliberately NOT
# installed — its skill says to invoke it as `npx -y gh-axi@<pin>`. It shells out to the `gh`
# BINARY, so the function above cannot reach it: a subprocess never sees a shell function.
# Wrapping it here is what makes the account routing apply to the agent path too, rather than
# only to hand-typed `gh`.
gh-axi() {
  emulate -L zsh
  local token
  token=$(_gh_account_token) || token=""
  if [[ -n $token ]]; then
    GH_TOKEN=$token command npx -y "gh-axi@${GH_AXI_PIN}" "$@"
  else
    command npx -y "gh-axi@${GH_AXI_PIN}" "$@"
  fi
}
