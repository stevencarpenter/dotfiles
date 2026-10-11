# common-env.zsh: non-secret environment flags common to all machines.
# Replaces the former agenix `zsh-env` secret (~/.config/zsh/.env), whose only
# content was this non-secret flag. Sourced by the profile.d loop in .zshrc.
export ENABLE_TOOL_SEARCH=true
# Replaces nix-darwin environment.variables.EDITOR.
export EDITOR=nvim
