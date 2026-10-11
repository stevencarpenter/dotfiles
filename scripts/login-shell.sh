#!/usr/bin/env bash
# Login shell pin (replaces the dscl block in modules/darwin/core.nix).
# Usage: login-shell.sh --check | --set
#   --check  Compare the Directory Services UserShell with /bin/zsh and report a
#            stale launchctl SHELL override. Exit 1 on a difference. Never writes.
#   --set    dscl -create UserShell (uses sudo when not root); unset a stale launchctl SHELL.
set -euo pipefail

want=/bin/zsh
user=$(id -un)
node="/Users/$user"

current=$(/usr/bin/dscl . -read "$node" UserShell 2>/dev/null || true)
current=${current#UserShell: }
override=$(/bin/launchctl getenv SHELL 2>/dev/null || true)

bad=0
if [[ $current != "$want" ]]; then
  echo "differs: UserShell live ${current:-<unset>}, want $want"; bad=1
else
  echo "ok: UserShell = $want"
fi
if [[ -n $override && $override != "$want" ]]; then
  echo "differs: launchctl SHELL override $override"; bad=1
else
  echo "ok: no stale launchctl SHELL override"
fi

case "${1:-}" in
  --check) exit "$bad" ;;
  --set)
    if [[ $current != "$want" ]]; then
      sudo=(); [[ $EUID -eq 0 ]] || sudo=(sudo)
      "${sudo[@]}" /usr/bin/dscl . -create "$node" UserShell "$want"
    fi
    if [[ -n $override && $override != "$want" ]]; then /bin/launchctl unsetenv SHELL; fi
    ;;
  *) echo "usage: $0 --check|--set" >&2; exit 2 ;;
esac
