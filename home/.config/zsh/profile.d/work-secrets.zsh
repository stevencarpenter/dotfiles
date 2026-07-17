# work-secrets.zsh — sourced only on work machines via chezmoi
# Loads work-specific encrypted environment variables.
if [[ -r "$XDG_CONFIG_HOME/zsh/.work.env" ]]; then
  set -a
  source -- "$XDG_CONFIG_HOME/zsh/.work.env"
  set +a
fi
