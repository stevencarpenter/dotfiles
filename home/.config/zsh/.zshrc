# Personal Zsh configuration file. It is strongly recommended to keep all
# shell customization and configuration (including exported environment
# variables such as PATH) in this file or in files sourced from it.
#
# Documentation: https://github.com/romkatv/zsh4humans/blob/v5/README.md.

## Zshell profiling flags (uncomment to profile startup time)
#zmodload zsh/zprof

# ============================================================================
# PRE-INIT SETUP (before z4h init)
# ============================================================================

# Auto load zmv for mass renaming. This is needed before z4h init.
autoload -Uz zmv

# ── Recover from a dead $PWD (deleted-worktree inheritance) ──────────────────
# Agent/worktrunk flows spawn ephemeral git worktrees under projects/*/.git/wt/
# and delete them. A tmux pane parked in one leaves every NEW window/pane
# inheriting a now-deleted directory (our split/new-window binds pin no -c). zsh
# then can't getcwd(): PWD collapses to '.', so the p10k prompt shows '. ❯',
# gitstatus finds no repo, and completion hangs on the orphaned inode until
# Ctrl-C. The absolute path is already lost by now, so land in a known-good dir.
# Must run before `z4h init` so the prompt/compinit/gitstatus all see a real cwd.
#
# Detection note: DON'T test `[[ -d $PWD ]]`. macOS keeps a deleted directory's
# vnode alive for any process chdir'd into it, so `test -d .` still returns true
# in exactly this failure mode. The honest signal is the *shape* of $PWD: zsh
# only emits a relative '.' when getcwd() failed at startup, so a non-absolute
# $PWD means a dead cwd. (The `&& -d` arm also catches an absolute-but-vanished
# path, e.g. the worktree deleted while this very shell sat in it.)
[[ $PWD == /* && -d $PWD ]] || cd -q ~ 2>/dev/null

# === z4h configuration (zstyles) ===
# Periodic auto-update on Zsh startup: 'ask' or 'no'.
zstyle ':z4h:' auto-update      'yes'
zstyle ':z4h:' auto-update-days '28'

# Keyboard type: 'mac' or 'pc'.
zstyle ':z4h:bindkey' keyboard  'mac'

# Start tmux if not already in tmux.
#
# MUST be set explicitly. Leaving this commented out does NOT mean "no tmux" —
# z4h defaults to 'isolated' (main.zsh: `zstyle -a :z4h: start-tmux start_tmux ||
# start_tmux=(isolated)`), which appends the shell's PID to the socket path and so
# spins up a SEPARATE tmux server per terminal window. Measured cost of that
# default here: 11 socket files, 8 of them stale, 4 live servers, none intentional.
#
# That sprawl is not merely untidy — it makes cleanup silently wrong. `tmux
# kill-server` is socket-scoped, so run from one window it exits 0, detaches your
# client, and kills a server, while a runaway Claude team survives on a different
# socket. Silent success against the wrong target.
#
# 'system' execs plain `tmux -u` on the DEFAULT socket, which buys three things:
#   1. One server for every window, so kill-server / list-panes are unambiguous.
#   2. tmux stays in play, so z4h's startup prompt-at-bottom still fires (it is
#      gated on `-n $_Z4H_TMUX`; plain 'no' would silently drop it).
#   3. Windows load THIS repo's ~/.config/tmux/tmux.conf instead of z4h's minimal
#      one — so the everforest theme and claude-pane-monitor.sh (which publishes
#      the runaway-teammate badge) apply everywhere, not just in hand-started
#      sessions.
zstyle ':z4h:' start-tmux system

# Whether to move prompt to the bottom when zsh starts and on Ctrl+L.
zstyle ':z4h:' prompt-at-bottom 'yes'

# Mark up shell's output with semantic information.
zstyle ':z4h:' term-shell-integration 'yes'

# Right-arrow key accepts one character ('partial-accept') from
# command autosuggestions or the whole thing ('accept')?
zstyle ':z4h:autosuggestions' forward-char 'accept'

# Recursively traverse directories when TAB-completing files.
zstyle ':z4h:fzf-complete' recurse-dirs 'yes'

# Enable ('yes') or disable ('no') automatic teleportation of z4h over SSH.
zstyle ':z4h:ssh:example-hostname1'   enable 'yes'
zstyle ':z4h:ssh:*.example-hostname2' enable 'no'
zstyle ':z4h:ssh:*'                   enable 'no'

# Send these files over to the remote host when connecting over SSH.
# zstyle ':z4h:ssh:*' send-extra-files '~/$XDG_CONFIG_HOME/.nanorc' '~/.env.zsh'

# Clone additional Git repositories from GitHub (example).
# z4h install ohmyzsh/ohmyzsh || return
z4h install xs5871/p10k-jj-status || return

# ── Completion search path (MUST precede `z4h init`) ─────────────────────────
# `z4h init` runs compinit internally, so fpath is effectively frozen from that
# point on: a later `fpath+=` registers nothing, because the lazy-load hook in
# section 9 only re-runs compinit when ${+_comps} is unset — and z4h has already
# set it. That is why the nix profile's completions (_bat _delta _eza _fastfetch
# _fd _gh _git_extras _mise _rg _uv _yazi _yq _zoxide) belong here and not there.
#
# Probe the prefixes directly rather than reading $HOMEBREW_PREFIX: the brew
# shellenv block that exports it does not run until section 1, below. The (N-/)
# qualifier drops any entry that is not an existing directory, so this is inert
# on a machine without nix, without Homebrew, or on a non-darwin host.
fpath+=(
    /etc/profiles/per-user/$USER/share/zsh/site-functions(N-/)  # nix home-manager profile
    /run/current-system/sw/share/zsh/site-functions(N-/)        # nix-darwin system profile
    /opt/homebrew/share/zsh/site-functions(N-/)                 # brew (Apple Silicon)
    /usr/local/share/zsh/site-functions(N-/)                    # brew (Intel)
)
typeset -U fpath

# Install or update core components (fzf, zsh-autosuggestions, etc.) and
# initialize Zsh. After this point console I/O is unavailable until Zsh
# is fully initialized. Everything that requires user interaction or can
# perform network I/O must be done above. Everything else is best done below.
z4h init || return
z4h source xs5871/p10k-jj-status/p10k-jj-status.plugin.zsh

# ============================================================================
# POST-INIT CUSTOMIZATION (after z4h init)
# ============================================================================

# === 0. eval-cache helper (must precede any zcached call below) ===
# Caches static `tool init` output to ~/.cache/zsh-eval-cache, invalidated on
# binary mtime/size change. See lib/eval-cache.zsh for the mechanism.
source "${XDG_CONFIG_HOME:-$HOME/.config}/zsh/lib/eval-cache.zsh"

# === 1. Homebrew Setup (must be early, other tools depend on it) ===
# Apple Silicon installs to /opt/homebrew, Intel to /usr/local. Probe both so
# the same dotfiles work on either arch without diverging.
if [[ $OSTYPE == darwin* ]]; then
  for brew_bin in /opt/homebrew/bin/brew /usr/local/bin/brew; do
    if [[ -x $brew_bin ]]; then
      zcached brew-shellenv "$brew_bin" "$brew_bin" shellenv
      break
    fi
  done
  unset brew_bin
fi

# === 2. PATH Configuration (consolidated for clarity) ===
# Nix must outrank Homebrew. `brew shellenv` (section 1, above) PREPENDS
# /opt/homebrew/bin, while nix's profiles are exported much earlier by
# /etc/zshenv — so without an explicit re-order every tool this flake declares in
# modules/home/packages.nix (bat, git, rg, jq, fd, eza, uv, tmux, delta, gh,
# yazi, zoxide, btop, …) resolves to a brew copy instead, leaving home.packages
# pinning a version nothing actually executes.
#
# $HOME/.local/bin stays ahead of nix deliberately: it carries the uv tool shims
# (token-auditor / codax), op-adopt, and the agent-journal wrappers. A hand-built
# binary dropped there therefore still wins over nix — that is the trade, not a
# bug.
#
# ── mise shims: below ~/.local/bin, above nix and brew ───────────────────────
# The slot is forced by what actually collides, not by taste:
#   mise ∩ nix          = {}  — packages.nix ships no language runtimes, so the
#                              two inventories are disjoint by design; ordering
#                              against nix is free today and this keeps mise's
#                              per-project pin winning if that ever changes.
#   mise ∩ brew         = {node, npm, npx, goreleaser, swiftlint} — mise MUST
#                              win these, or the version pinned in
#                              ~/.config/mise/config.toml is not what runs.
#   mise ∩ ~/.local/bin = {stevectl} — the hand-built binary must win, per the
#                              paragraph directly above. The shim is also
#                              directory-sensitive (`mise which stevectl` fails
#                              with "not currently active" outside a project
#                              that uses it), so letting it shadow ~/.local/bin
#                              makes `stevectl` resolve differently per cwd.
#
# This used to be a blind `path=($HOME/.local/share/mise/shims $path)` at the
# very END of this file, which landed the shims at position 1 — ahead of
# ~/.local/bin and nix both, silently inverting the precedence declared here.
#
# The probe guards against a shim farm orphaned by a moved/removed mise binary:
# all ~105 shims point at whichever mise was current when `mise reshim` last
# ran, so they dangle as a group. A dangling shim is uniquely poisonous, because
# zsh disagrees with itself about whether the command exists — the command hash
# is filled from readdir(), so commands[terraform] IS set, while `=terraform`
# does a real access(X_OK) and fails. z4h's -z4h-compinit:86 runs exactly that
# pair, and a failed `=cmd` expansion is a FATAL zsh error that unwinds the
# whole call stack: compinit, zsh-autosuggestions, zsh-syntax-highlighting, the
# keybindings and the p10k prompt all die with it. One dead symlink presents as
# "terraform not found" plus a shell with no tab completion, no right-arrow
# accept, and a prompt that only settles when you press Enter.
#
# The probe MUST be an array assignment: `[[ -n <pattern> ]]` does not perform
# filename generation in zsh, so it would test the literal pattern, always pass,
# and silently defeat the guard. (N-*[1]) = nullglob / follow symlinks /
# executable / stop at the first hit, so this costs one stat when healthy.
_mise_shim_dir=$HOME/.local/share/mise/shims
_mise_shims_ok=($_mise_shim_dir/*(N-*[1]))    # at least one shim resolves
_mise_shims_any=($_mise_shim_dir/*(N[1]))     # dir holds any entry at all
_mise_shim_path=()
if (( ${#_mise_shims_ok} )); then
    _mise_shim_path=($_mise_shim_dir)
elif (( ${#_mise_shims_any} )); then
    # Entries exist but none resolve — stale farm. Warn and leave it off PATH;
    # staying silent would drop go/java/node/cargo/terraform and turn this into
    # a second-order "command not found" mystery. An empty/absent dir (fresh
    # machine) falls through quietly: there is nothing stale to report.
    print -u2 "mise: every shim in $_mise_shim_dir is broken — run 'mise reshim' (or remove the dir if mise is gone)"
fi

path=(
    $HOME/.opencode/bin
    $HOME/.local/bin
    $_mise_shim_path                        # mise shims (empty array if stale)
    /etc/profiles/per-user/$USER/bin(N-/)   # nix home-manager profile
    /run/current-system/sw/bin(N-/)         # nix-darwin system profile
    ${HOMEBREW_PREFIX:-/opt/homebrew}/opt/libpq/bin(N-/)
    "/Applications/IntelliJ IDEA.app/Contents/MacOS"
    $HOME/.lmstudio/bin
    $HOME/.amp/bin
    $HOME/go/bin
    $HOME/.bun/bin
    $path
)

# The nix dirs are already present in the inherited $path (from /etc/zshenv), and
# .zshrc is sourced for EVERY interactive shell, so the prepend above duplicates
# them and nested shells compound it. -U keeps the first occurrence and drops the
# rest, which is exactly the precedence we just declared.
typeset -U path

export PATH

unset _mise_shim_dir _mise_shims_ok _mise_shims_any _mise_shim_path

# === 3. Environment Variables ===
export GPG_TTY=$TTY
export ENABLE_LSP_TOOL=1

# ─── Limits ───────────────────────────────────────────────────────────────────
# Raise open file descriptor limit (launchd plist sets it at boot; this covers
# the current session and any tmux panes opened before a reboot).
ulimit -n 65536

# === 4. Source Local Files ===
z4h source ~/.env.zsh
# NOTE: the former ~/.config/zsh/.env source was removed in WS1 — its only
# content (ENABLE_TOOL_SEARCH) now loads from profile.d/common-env.zsh, and
# ~/.config/zsh/.personal.env loads from profile.d/personal-secrets.zsh (both
# sourced by the profile.d loop later in this file).

# === 5. Aliases ===
# Git aliases
alias gfp='git fetch --all && git pull'
alias gss='git status -sb'
alias gpl='gh pr list'

# Cargo: the full pre-commit check chain (fmt + check + clippy --fix + test)
alias crust='cargo fmt --all && cargo check --all && cargo clippy --all-targets --all-features --fix --allow-dirty -- -D warnings && cargo test --workspace'

# uv: sync dev deps and refresh lockfile
alias uvsl='uv sync --dev && uv lock'

# mise: short form for `mise run <task>`
alias mr='mise run'

# Docker aliases
alias docker-clean-unused='docker system prune --all --force --volumes'
alias docker-clean-all='docker stop $(docker container ls -a -q) 2>/dev/null; docker rm -f $(docker container ls -a -q) 2>/dev/null; docker system prune -a -f --volumes'

# Editor aliases
alias v='nvim'
alias vi='nvim'
alias vim='nvim'
alias nano='nvim'
alias emacs='nvim'

# Modern ls (eza)
if command -v eza >/dev/null 2>&1; then
  alias ls='eza --icons'
  alias la='eza -lah --icons --git'
  alias ll='eza -lah --icons --git --total-size'

  # Tree variants: hide gitignored files unless --all is passed.
  # If the target itself is gitignored (e.g. `lt target/`), bypass the
  # filter so build artifacts stay visible.
  # Always pass an explicit path — eza 0.23 returns empty with
  # --git-ignore when no path is given.
  _eza_tree() {
    local level=$1; shift
    local flags=() paths=() show_all=0 a
    for a in "$@"; do
      case $a in
        --all) show_all=1 ;;
        -*)    flags+=("$a") ;;
        *)     paths+=("$a") ;;
      esac
    done
    (( ${#paths[@]} == 0 )) && paths=(.)
    local target_ignored=0 p
    for p in "${paths[@]}"; do
      if git check-ignore -q "$p" 2>/dev/null; then
        target_ignored=1; break
      fi
    done
    local git_filter=()
    (( show_all || target_ignored )) || git_filter=(--git-ignore)
    eza -lah --icons --git --tree --level="$level" "${git_filter[@]}" "${flags[@]}" "${paths[@]}"
  }
  lt()  { _eza_tree 2 "$@"; }
  las() { _eza_tree 3 --sort=size --total-size "$@"; }
else
  alias ls='command ls'
fi

# Utility aliases
alias tree='tree -a -I .git'
alias sed='gsed'
alias teeclip='tee >(pbcopy)'

# Tool shortcuts
alias k='kubectl'
alias s='stevectl'
alias lzg='lazygit'
alias tig='git log --reverse'
alias lzd='lazydocker'
# Config editing
alias dots='cd ~/.dotfiles/'
alias zshrc='nvim $ZDOTDIR/.zshrc'
alias zprofile='nvim $ZDOTDIR/.zprofile'
alias ez='exec zsh'

# Worktrunk log viewer (tails the log file for a given hook)
function wtlog() { tail -f "$(wt config state logs get --hook="$1")"; }

# === 6. Key Bindings (z4h specific) ===
z4h bindkey z4h-backward-kill-word  Ctrl+Backspace     Ctrl+H
z4h bindkey z4h-backward-kill-zword Ctrl+Alt+Backspace

z4h bindkey undo Ctrl+/ Shift+Tab  # undo the last command line change
z4h bindkey redo Alt+/             # redo the last undone command line change

z4h bindkey z4h-cd-back    Alt+Left   # cd into the previous directory
z4h bindkey z4h-cd-forward Alt+Right  # cd into the next directory
z4h bindkey z4h-cd-up      Alt+Up     # cd into the parent directory
z4h bindkey z4h-cd-down    Alt+Down   # cd into a child directory

# === 7. Functions ===
# Simple utility functions

# Get complete command output with header and exit code, copied to clipboard (for easy sharing in chat, etc.)
function c() {
  emulate -L zsh
  setopt pipefail

  if (( $# == 0 )); then
    echo "Usage: c <command> [args...]" >&2
    return 2
  fi

  local tmpfile
  tmpfile="$(mktemp -t zshcap.XXXXXX)" || return 1

  local cmd="$*"
  local cwd="${PWD/#$HOME/~}"

  # Run command; capture stdout+stderr; still show live output
  "$@" 2>&1 | tee "$tmpfile"
  local rc=${pipestatus[1]}  # exit code of the command (not tee)

  # Copy Slack-safe text (no Nerd Font glyphs)
  {
    print -r -- "$cwd$ $cmd"
    cat "$tmpfile"
  } | pbcopy

  rm -f "$tmpfile"
  return $rc
}

function md() {
  if (( $# != 1 )); then
    echo "Usage: md <directory>" >&2
    return 2
  fi
  mkdir -p -- "$1" && cd -- "$1"
}

# Git "whoops" function: move the last N commits (default 1) onto a new branch, resetting the current branch back N.
# With --squash, combines the moved commits on the new branch into a single commit (opens editor for the message).
function goops() {
  local branch n=1 squash=0
  while (( $# )); do
    case "$1" in
      --squash) squash=1 ;;
      -*) echo "goops: unknown flag: $1" >&2; return 2 ;;
      *)
        if [[ -z "$branch" ]]; then
          branch="$1"
        elif [[ "$1" =~ ^[0-9]+$ ]]; then
          n="$1"
        else
          echo "goops: unexpected arg: $1" >&2; return 2
        fi
        ;;
    esac
    shift
  done
  if [[ -z "$branch" ]]; then
    echo "Usage: goops <new-branch> [N] [--squash]" >&2
    return 2
  fi
  if (( n < 1 )); then
    echo "goops: N must be >= 1" >&2
    return 2
  fi
  local source_branch
  source_branch=$(git symbolic-ref --short HEAD 2>/dev/null) || {
    echo "goops: not on a branch" >&2
    return 1
  }
  if ! git rev-parse --verify --quiet "HEAD~$n" >/dev/null; then
    echo "goops: cannot reach HEAD~$n on $source_branch" >&2
    return 1
  fi
  git branch "$branch" && git reset --hard "HEAD~$n" && git checkout "$branch" || return
  if (( squash )); then
    git reset --soft "$source_branch" && git commit
  fi
}

# Checkout the repo's default branch (main/master/etc.) and fetch+pull.
# With one arg, also creates a new branch off the freshly-pulled default.
function gmfp() {
  if (( $# > 1 )); then
    echo "Usage: gmfp [new-branch]" >&2
    return 2
  fi
  local default
  default=$(git symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null | sed 's|^origin/||')
  if [[ -z "$default" ]]; then
    for b in main master; do
      if git show-ref --verify --quiet "refs/remotes/origin/$b"; then
        default=$b
        break
      fi
    done
  fi
  if [[ -z "$default" ]]; then
    echo "gmfp: could not determine default branch" >&2
    return 1
  fi
  git checkout "$default" && git fetch --all && git pull || return
  if (( $# == 1 )); then
    git checkout -b "$1"
  fi
}

# Commit all tracked changes with an AI-generated message (uses `claude` directly to avoid
# claade's token-audit output contaminating the commit message via $()).
function gcam() {
  if ! command -v claude >/dev/null 2>&1; then
    echo "gcam: 'claude' CLI not found in PATH" >&2
    return 127
  fi
  local msg rc
  msg="$(claude -p "generate commit message and only return the message in plaintext with no quoting, newlines, emoji, or formatting. Strictly plaintext formatted for direct use as a conventional commit compliant git commit message. The commit should encompass all current changes in the repo, so consider all changed files and their diffs when generating the message. Keep it concise, ideally under 72 characters, but include enough detail to be informative. Do not include any metadata, explanations, or formatting—just the raw commit message text." 2>/dev/null))"
  rc=$?
  if (( rc != 0 )); then
    echo "gcam: claude exited with status $rc; aborting commit" >&2
    return $rc
  fi
  # Trim leading/trailing whitespace
  msg="${msg#"${msg%%[![:space:]]*}"}"
  msg="${msg%"${msg##*[![:space:]]}"}"
  if [[ -z "$msg" ]]; then
    echo "gcam: claude returned an empty message; aborting commit" >&2
    return 1
  fi
  git commit -am "$msg"
}

# Same as gcam, then push.
function gcamp() {
  gcam && git push
}

# Copy a file to the clipboard and also save it to disk (for easy sharing of files in chat, etc.)
function copyfile() {
  if ! tee "$1" >(pbcopy); then
    echo "Error: Failed to write file or copy to clipboard" >&2
    return 1
  fi
}

# AI CLI wrappers. Each runs the tool in the project's uv venv (so a language
# server it spawns — e.g. Claude Code's Pyright — resolves project deps), then
# prints a token-usage audit for the session. Two orthogonal helpers below are
# composed per tool; provider and whether to pass --cwd are set per tool.

# Run an AI CLI tool inside the project's uv venv when one exists (else run it
# as-is), scoped to a subshell so the caller's shell is untouched. The tool is
# resolved to an absolute path from the *current* (pre-venv) PATH up front, then
# the venv bin dir is prepended only inside the subshell. So a child the tool
# spawns (e.g. Claude Code's Pyright) resolves project deps via the venv, but a
# repo-controlled .venv/bin/<tool> shim cannot shadow the trusted entrypoint.
# Setting PATH/VIRTUAL_ENV directly (vs sourcing .venv/bin/activate) likewise
# avoids running a repo-controlled activate script on launch; these exports are
# activate's only functional effect, the rest being interactive-prompt cosmetics
# a one-shot subshell never uses. A stray .venv in a non-Python repo is still
# picked up for codex/opencode, but that only alters the confined subshell's env
# and the tool binary itself stays the trusted one — harmless.
# Args: $1 — tool name to resolve; $2.. — the tool's own args.
function _with_project_venv() {
  local bin
  bin=$(command -v -- "$1") || {
    echo "_with_project_venv: '$1' not found on PATH" >&2
    return 127
  }
  if [[ -x .venv/bin/python ]]; then
    (
      export VIRTUAL_ENV="$PWD/.venv"
      export PATH="$VIRTUAL_ENV/bin:$PATH"
      unset PYTHONHOME
      "$bin" "${@:2}"
    )
  else
    "$bin" "${@:2}"
  fi
}

# Print a token-usage audit for $provider's most recent session. Uses the
# standalone token-auditor uv tool (installed from
# github.com/stevencarpenter/token-auditor), so it is independent of any active venv.
function _audit_token_usage() {
  local wrapper_name="$1"
  local provider="$2"
  local use_cwd="$3"

  if ! command -v token-auditor >/dev/null 2>&1; then
    echo "${wrapper_name}: token-auditor not installed (uv tool install git+https://github.com/stevencarpenter/token-auditor)" >&2
    return 0
  fi

  local -a audit_cmd=(token-auditor --provider "$provider")
  if [[ "$use_cwd" == "1" ]]; then
    audit_cmd+=(--cwd "$PWD")
  fi
  "${audit_cmd[@]}" || echo "${wrapper_name}: failed to print session usage audit" >&2
}

function codax() {
  _with_project_venv codex "$@"
  local rc=$?
  _audit_token_usage codax codex 0
  return $rc
}

function claade() {
  # Claude Code writes "hooks": {} to settings.local.json when saving permissions,
  # which shadows global SessionStart hooks. Strip it before launch.
  local git_root s
  git_root="$(git rev-parse --show-toplevel 2>/dev/null)"
  if [[ -n "$git_root" ]]; then
    s="${git_root}/.claude/settings.local.json"
    if [[ -f "$s" ]] && jq -e '.hooks == {}' "$s" &>/dev/null; then
      jq 'del(.hooks)' "$s" > "${s}.tmp" && mv "${s}.tmp" "$s" || {
        rm -f "${s}.tmp"
        echo "claade: failed to strip empty hooks from $s" >&2
      }
    fi
  fi
  _with_project_venv claude "$@"
  local rc=$?
  _audit_token_usage claade claude 1
  return $rc
}

function opencade() {
  _with_project_venv opencode "$@"
  local rc=$?
  _audit_token_usage opencade opencode 1
  return $rc
}

# nix-darwin rebuild helper (replaces the retired chezmoi-apply `ca()` wrapper).
# Defines `rebuild` (darwin-rebuild switch for this host) + a transitional `ca` shim.
rebuild_helper="${XDG_CONFIG_HOME:-$HOME/.config}/zsh/lib/rebuild.zsh"
[[ -f "${rebuild_helper}" ]] && source "${rebuild_helper}"
unset rebuild_helper

# GitHub CLI account routing. `gh` has one active account per host and no per-repo
# selection, so on a machine logged into both work and personal accounts it picks the
# wrong one half the time. Defines `gh`/`gh-axi` wrappers that resolve the account from
# origin's owner. See lib/gh-account.zsh for why this is not `gh auth switch`.
gh_account_helper="${XDG_CONFIG_HOME:-$HOME/.config}/zsh/lib/gh-account.zsh"
[[ -f "${gh_account_helper}" ]] && source "${gh_account_helper}"
unset gh_account_helper

# Yazi TUI file manager wrapper (updates shell CWD on exit)
function y() {
	local tmp="$(mktemp -t "yazi-cwd.XXXXXX")" cwd
	command yazi "$@" --cwd-file="$tmp"
	IFS= read -r -d '' cwd < "$tmp"
	[ "$cwd" != "$PWD" ] && [ -d "$cwd" ] && builtin cd -- "$cwd"
	rm -f -- "$tmp"
}

# Triage SecureInput state on macOS (for debugging keylogger issues). Returns the PID of the process holding SecureInput, if any, and its command name.
function sip_holder() {
  local pid
  pid=$(ioreg -l -w 0 | rg -o 'kCGSSessionSecureInputPID"=([0-9]+)' -r '$1' | head -1)
  if [[ -n "$pid" && "$pid" != "0" ]]; then
    printf 'SecureInput held by PID %s: %s\n' "$pid" "$(ps -p "$pid" -o comm= 2>/dev/null)"
  else
    printf 'SecureInput: not held\n'
  fi
}

# === 8. Tool Initializations (after PATH is set) ===
# These tools need to be initialized after PATH is configured

# zoxide (smart cd)
command -v zoxide >/dev/null 2>&1 && zcached zoxide-init "$(command -v zoxide)" zoxide init --cmd cd zsh

# atuin (shell history) - skip silently on machines without atuin installed
[[ -f "$HOME/.local/bin/env" ]] && . "$HOME/.local/bin/env" || true
[[ -f "$HOME/.atuin/bin/env" ]] && . "$HOME/.atuin/bin/env" || true
# Scrub a stale ATUIN_TMUX_POPUP a long-lived tmux server may have frozen in;
# atuin's config.toml [tmux] block should be the only source of truth.
unset ATUIN_TMUX_POPUP
# -k on the config: `atuin init zsh` reads config.toml and bakes the [tmux]
# decision into the script it emits, so the config is a cache input alongside
# the binary. Without it, a config change never invalidates the cache.
command -v atuin >/dev/null 2>&1 &&
  zcached -k "${XDG_CONFIG_HOME:-$HOME/.config}/atuin/config.toml" \
    atuin-init "$(command -v atuin)" atuin init zsh

# === 9. Completions ===
# Defer custom completion registration until after first prompt.
# z4h calls compinit internally; we detect this via ${+_comps} and skip a redundant
# second call. The old guard (typeset -f compinit) was unreliable — z4h autoloads
# compinit so it always appeared defined before it had actually run.
#
# fpath is NOT extended here. It used to be (a bare
# `fpath+=${HOMEBREW_PREFIX}/share/zsh/site-functions`), but that line was dead:
# by this point z4h's compinit has already run and set ${+_comps}, so the guard
# below never fires and nothing appended here is ever scanned. Every completion
# directory — nix profile and Homebrew alike — is now added in the PRE-INIT
# section, immediately above `z4h init`.

_zsh_lazy_load_completions() {
  add-zsh-hook -d precmd _zsh_lazy_load_completions 2>/dev/null || true

  # Only call compinit if z4h hasn't already done so
  if (( ! ${+_comps} )); then
    autoload -Uz +X compinit && compinit
    autoload -Uz +X bashcompinit && bashcompinit
  fi

  # Register completions for custom functions
  compdef _directories md
}

autoload -Uz add-zsh-hook
add-zsh-hook precmd _zsh_lazy_load_completions

# === 10. Optional Integrations (last, least critical) ===
# OrbStack: command-line tools and integration
source ~/.orbstack/shell/init.zsh 2>/dev/null || :

# Source profile.d directory for machine-specific config (personal vs work aliases, functions, secrets)
if [[ -d "${ZDOTDIR}/profile.d" ]]; then
    for file in "${ZDOTDIR}"/profile.d/*.zsh(N); do
        source "$file"
    done
fi

# Dev container orchestrator (optional)
# Not using this right now but it is a nice convention for users who do use dev containers to have a standard file where they can put container-related environment variables and functions (e.g. to automatically detect if you are in a dev container and set up your prompt accordingly, or to set environment variables that point to containerized services, etc.)
#dev_env_file="${XDG_CONFIG_HOME:-$HOME/.config}/dev-container/dev-env.zsh"
#[[ -f "$dev_env_file" ]] && source "$dev_env_file" || true

# Worktrunk shell completions
if command -v wt >/dev/null 2>&1; then zcached wt-shell-init "$(command -v wt)" command wt config shell init zsh; fi

# mise (polyglot runtime manager) - lazy load with hook prevention
#
# The shims directory is NOT added here. It is declared in section 2 with the
# rest of the PATH precedence, because adding it at this point in the file put
# it at position 1 — ahead of ~/.local/bin and nix — which inverted the order
# section 2 goes to some length to establish. Precedence lives in one place.
if command -v mise >/dev/null 2>&1; then
  # Create wrapper function that activates on first use
  mise() {
    if [[ -z "${MISE_SHELL-}" ]]; then
      eval "$(command mise activate zsh)"
      # Remove this wrapper after activation
      unfunction mise 2>/dev/null || true
    fi
    command mise "$@"
  }
fi

# ============================================================================
# Profiling output (uncomment if you enabled zprof at the top)
#zprof
