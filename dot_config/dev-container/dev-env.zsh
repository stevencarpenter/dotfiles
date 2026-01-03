# Convenience wrappers for the dev container orchestrator.
export DEV_CONTAINER_ROOT="${XDG_CONFIG_HOME:-$HOME/.config}/dev-container"
if [ -d "$DEV_CONTAINER_ROOT/bin" ]; then
  path=("$DEV_CONTAINER_ROOT/bin" "${path[@]}")
fi

de() { dev-env "$@"; }
if (( ${+functions[compdef]} )); then
  compdef _gnu_generic dev-env de 2>/dev/null || true
fi
