# eval-cache.zsh — cache the static output of `eval "$(tool init ...)"` calls.
#
# The four hot startup forks (brew shellenv, zoxide init, atuin init, wt shell
# init) each emit output that only changes when the tool binary changes. Fork
# them once, cache the script to disk keyed on the binary's mtime+size, and
# source the cache on every later shell. Measured on personal-mac (2026-07-17):
# these forks were ~50ms of an ~80ms p50 interactive startup.
#
# Usage: zcached <cache-name> <binary-path> <command...>
#   zcached brew-shellenv /opt/homebrew/bin/brew /opt/homebrew/bin/brew shellenv
#
# Invalidation: the cache embeds the binary's mtime+size on line 1; any
# upgrade/reinstall (new mtime) regenerates. Delete ~/.cache/zsh-eval-cache to
# force a full refresh.

zcached() {
  local name=$1 bin=$2
  shift 2
  [[ -x $bin ]] || return 0

  local cache_dir=${XDG_CACHE_HOME:-$HOME/.cache}/zsh-eval-cache
  local cache=$cache_dir/$name.zsh
  local -A st
  zmodload -F zsh/stat b:zstat 2>/dev/null
  zstat -H st -- $bin 2>/dev/null || st=(mtime 0 size 0)
  local stamp="# ${st[mtime]}:${st[size]}"

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
