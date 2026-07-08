# personal-secrets.zsh — sourced only on personal machines via chezmoi
# Loads personal-specific encrypted environment variables.
if [[ -r "$XDG_CONFIG_HOME/zsh/.personal.env" ]]; then
  set -a
  source -- "$XDG_CONFIG_HOME/zsh/.personal.env"
  set +a
fi
