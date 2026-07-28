# eval-cache.zsh — cache the static output of `eval "$(tool init ...)"` calls.
#
# The four hot startup forks (brew shellenv, zoxide init, atuin init, wt shell
# init) each emit output that only changes when the tool binary changes. Fork
# them once, cache the script to disk keyed on the binary's mtime+size, and
# source the cache on every later shell. Measured on personal-mac (2026-07-17):
# these forks were ~50ms of an ~80ms p50 interactive startup.
#
# Usage: zcached [-k <path>]... <cache-name> <binary-path> <command...>
#   zcached brew-shellenv /opt/homebrew/bin/brew /opt/homebrew/bin/brew shellenv
#   zcached -k ~/.config/atuin/config.toml atuin-init "$(command -v atuin)" atuin init zsh
#
# Invalidation: the cache embeds one "mtime:size" field per input on line 1;
# any upgrade/reinstall (new mtime) regenerates. Delete
# ~/.cache/zsh-eval-cache to force a full refresh.
#
# -k adds a file to the cache key beyond the binary. Needed when a tool's init
# output depends on a config file: `atuin init zsh` bakes the [tmux] setting
# into the script it emits, so a config-only edit MUST invalidate the cache or
# the change appears to do nothing — the stale script keeps exporting
# ATUIN_TMUX_POPUP=false long after the config that caused it was replaced
# (found 2026-07-27). The other three call sites genuinely depend only on
# their binary and pass no -k.
#
# A single-input caller's stamp is byte-identical to the pre-1-input format,
# so adding this flag does not invalidate anyone else's cache.

zcached() {
  local -a extra=()
  # Bail on a valueless trailing -k rather than looping. zsh's `shift 2` FAILS
  # without shifting when $# < 2, so `while [[ $1 == -k ]]; shift 2` spins
  # forever on `zcached -k` — and this runs from .zshrc, so that is an
  # interactive shell you can only escape with `zsh -f`. ${1-} keeps a
  # zero-arg call from dying under `setopt nounset` too.
  while [[ ${1-} == -k ]]; do
    if [[ -z ${2-} ]]; then
      print -u2 "zcached: -k requires a path argument"
      return 2
    fi
    extra+=("$2")
    shift 2
  done

  local name=${1-} bin=${2-}
  shift 2 2>/dev/null || return 2
  [[ -x $bin ]] || return 0

  local cache_dir=${XDG_CACHE_HOME:-$HOME/.cache}/zsh-eval-cache
  local cache=$cache_dir/$name.zsh

  # A missing -k path stamps as 0:0 rather than bailing, so a not-yet-deployed
  # config can't silently disable caching; it just reads as "absent", and the
  # stamp changes the moment it lands.
  local -a inputs=("$bin" "${extra[@]}")
  local -A st
  local stamp="#" p
  zmodload -F zsh/stat b:zstat 2>/dev/null
  for p in "${inputs[@]}"; do
    zstat -H st -- "$p" 2>/dev/null || st=(mtime 0 size 0)
    stamp+=" ${st[mtime]}:${st[size]}"
  done

  local first=
  [[ -r $cache ]] && IFS= read -r first < $cache
  if [[ $first != $stamp ]]; then
    mkdir -p $cache_dir
    if ! { echo $stamp; "$@" } > $cache.$$ 2>/dev/null; then
      # Generation failed — don't poison the cache; run uncached this once.
      command rm -f $cache.$$
      eval "$("$@")"
      return
    fi
    command mv -f $cache.$$ $cache
  fi
  source $cache
}
