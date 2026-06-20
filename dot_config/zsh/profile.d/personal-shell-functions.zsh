#!/usr/bin/env zsh

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

# Jump into the long-lived tmux session on the i9 home server. mosh survives
# laptop sleep / network roam; `tmux new -A -s main` attaches-or-creates so you
# always land back where you left off. Plain `ssh i9` (Host i9 in ~/.ssh/config)
# stays available for one-off / scp / non-interactive use.
alias i9='mosh i9 -- tmux new -A -s main'

# Load Hippo CLI functions (only when installed; not on the home-lab box yet)
if [[ -f "$HOME/.local/share/hippo-brain/shell/hippo.zsh" ]]; then
    source "$HOME/.local/share/hippo-brain/shell/hippo-env.zsh"
    source "$HOME/.local/share/hippo-brain/shell/hippo.zsh"
fi
# Hippo CLI end

# pnpm
export PNPM_HOME="/Users/carpenter/.local/share/pnpm"
case ":$PATH:" in
  *":$PNPM_HOME/bin:"*) ;;
  *) export PATH="$PNPM_HOME/bin:$PATH" ;;
esac
# pnpm end

# ghcup (Haskell toolchain manager) why am I even doing this in 2026
#[ -f "$HOME/.ghcup/env" ] && . "$HOME/.ghcup/env" # ghcup-env

# Mill build tool completions
#source ~/.local/share/mill/completion/mill-completion.sh # MILL_SOURCE_COMPLETION_LINE

# Verify key dev toolchain binaries are native ARM64 (not Rosetta-translated)
check-arch() {
  local tools=(node python3 go rustc java ruby)
  local found_issue=0
  for t in "${tools[@]}"; do
    local bin
    bin=$(command -v "$t" 2>/dev/null) || continue
    local arch
    arch=$(file "$bin" | grep -o 'arm64\|x86_64' | head -1)
    if [[ "$arch" == "x86_64" ]]; then
      echo "⚠️  $t ($bin): x86_64 — running under Rosetta"
      found_issue=1
    elif [[ "$arch" == "arm64" ]]; then
      echo "✅ $t ($bin): arm64"
    else
      echo "?  $t ($bin): unknown arch ($arch)"
    fi
  done
  if (( found_issue == 0 )); then
    echo "All checked binaries are native ARM64."
  fi
}
