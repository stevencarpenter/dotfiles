# eval-cache.zsh: cache the static output of `eval "$(tool init ...)"` calls.
#
# Cache init output by binary mtime and size to avoid repeated startup processes.
#
# Usage: zcached [-k <path>]... <cache-name> <binary-path> <command...>
#   zcached brew-shellenv /opt/homebrew/bin/brew /opt/homebrew/bin/brew shellenv
#   zcached -k ~/.config/atuin/config.toml atuin-init "$(command -v atuin)" atuin init zsh
#
# Invalidation: the cache embeds one "mtime:size" field per input on line 1;
# any upgrade/reinstall (new mtime) regenerates. Delete
# ~/.cache/zsh-eval-cache to force a full refresh.
#
# -k adds config files to the key. Atuin embeds [tmux] settings in init output,
# so its config must invalidate the cache even when the binary is unchanged.

zcached() {
  local -a extra=()
  # shift 2 leaves arguments unchanged when a -k value is missing, causing a loop.
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

  # Stamp missing inputs as 0:0 so creating them invalidates the cache.
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
      # Keep the previous cache after generation failure; run uncached this time.
      command rm -f $cache.$$
      eval "$("$@")"
      return
    fi
    command mv -f $cache.$$ $cache
  fi
  source $cache
}
