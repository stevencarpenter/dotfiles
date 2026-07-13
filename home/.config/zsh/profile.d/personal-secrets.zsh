# personal-secrets.zsh — sourced only on personal machines (profile.d loop).
# Loads ~/.config/zsh/.personal.env, which op-render materializes from op://
# templates (WS1). The file is 0600 plaintext at rest; op is the source.
if [[ -r "$XDG_CONFIG_HOME/zsh/.personal.env" ]]; then
  set -a
  source -- "$XDG_CONFIG_HOME/zsh/.personal.env"
  set +a
fi
