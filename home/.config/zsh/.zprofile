# Login-only environment. macOS /etc/zshrc needs these before .zshrc runs.
export SHELL_SESSION_DIR=$XDG_STATE_HOME/zsh/sessions
export SHELL_SESSION_FILE=$SHELL_SESSION_DIR/$TERM_SESSION_ID

# Put shared interactive setup in .zshrc so non-login tmux shells also load it.
