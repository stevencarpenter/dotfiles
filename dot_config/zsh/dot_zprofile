# ----------------------------------------------------------------------
# Zsh Profile Configuration:
# ----------------------------------------------------------------------
# Executed once for each login shell before the shell session starts.
# It's used for setting up environment variables and running commands
# that should be executed at login.
# ----------------------------------------------------------------------
# Safe-to-edit zone: add/change login-only env here. Keep z4h internals
# untouched (z4h lives in .zshenv/.zshrc). No z4h-managed content below.

# The following have to go in .zprofile, because they are used by
# macOS's /etc/zshrc file, which is sourced _before_ your`.zshrc`
# file.
export SHELL_SESSION_DIR=$XDG_STATE_HOME/zsh/sessions
export SHELL_SESSION_FILE=$SHELL_SESSION_DIR/$TERM_SESSION_ID

# NOTE: Most environment variables, functions, and tool setup should go in .zshrc instead,
# since .zprofile is ONLY sourced for login shells, not regular interactive shells (tmux, etc).
# .zshrc is sourced for ALL interactive shells (login and non-login).
#
# All functions, Homebrew setup, OrbStack integration, and profile.d sourcing have been
# moved to .zshrc so they're available in tmux and other non-login interactive shells.
