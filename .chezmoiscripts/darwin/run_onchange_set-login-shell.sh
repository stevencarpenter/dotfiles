#!/usr/bin/env bash
# Pin the login shell to the system zsh on every machine.
#
# Background — the one piece of shell config chezmoi did NOT own.
# Everything *inside* zsh is already arch-aware: dot_config/zsh/dot_zshrc
# probes /opt/homebrew/bin/brew then /usr/local/bin/brew and uses
# ${HOMEBREW_PREFIX:-/opt/homebrew} everywhere, so the same dotfiles work on
# Apple Silicon (personal-mac) and Intel (lab-mac, the 2019 i9). But the login
# *shell binary* — the Directory Services UserShell — was set out of band by a
# manual `chsh`, outside chezmoi. A stray `chsh -s /opt/homebrew/bin/zsh` (the
# Apple-Silicon path) on the Intel lab-mac left `login` exec'ing a path that
# does not exist there, and it fails BEFORE any .zshenv/.zshrc — and thus the
# brew probe — is ever read. Result: no shell, SSH also dead, recover only via
# Screen Share.
#
# Fix: standardize the login shell on /bin/zsh across all machines. It is
# always present, in /etc/shells by default (so no sudo to register it), and
# immune to Homebrew cellar/prefix churn — so "can I log in" no longer depends
# on "is Homebrew healthy". The z4h setup in ~/.config/zsh runs identically
# under it. Homebrew's zsh, if wanted interactively, stays a deliberate choice,
# never the default that can brick login.
#
# Idempotent: a no-op (no sudo prompt) once the shell already matches.
set -euo pipefail

[[ "$(uname)" == "Darwin" ]] || exit 0

target="/bin/zsh"
user="$(id -un)"
current="$(dscl . -read "/Users/$user" UserShell 2>/dev/null | awk '{print $2}' || true)"

if [[ "$current" != "$target" ]]; then
    printf 'login shell is %s; changing to %s (sudo may prompt once)\n' "${current:-unset}" "$target"
    sudo chsh -s "$target" "$user"
else
    printf 'login shell already %s\n' "$target"
fi

# Clear any stale `launchctl setenv SHELL <path>` override (e.g. a hardcoded
# Homebrew Cellar path like /opt/homebrew/Cellar/zsh/5.9.1/bin/zsh) so the
# SHELL env var that GUI-launched apps inherit tracks the login shell instead
# of a versioned path that vanishes on the next `brew upgrade zsh`.
launchctl_shell="$(launchctl getenv SHELL 2>/dev/null || true)"
if [[ -n "$launchctl_shell" && "$launchctl_shell" != "$target" ]]; then
    printf 'clearing stale launchctl SHELL override (%s)\n' "$launchctl_shell"
    launchctl unsetenv SHELL || true
fi
