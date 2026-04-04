function _ca_has_target_drift() {
  local line

  while IFS= read -r line; do
    [[ -z "${line}" ]] && continue

    # `chezmoi status` uses the first column for destination drift.
    [[ "${line[1]}" != " " ]] && return 0
  done

  return 1
}

# Chezmoi apply with intelligent conflict resolution.
# - Applies manual changes from source
# - Warns when destination files have manual drift
# - Shows what would be applied before doing so
function ca() {
  echo "Checking for conflicts between source and target..."

  echo "Changes to be applied:"
  chezmoi diff --exclude=scripts

  if chezmoi status --exclude=scripts | _ca_has_target_drift; then
    echo ""
    echo "   Target files have changes that differ from source."
    echo "   These will be preserved. Only source changes will be applied."
    echo ""
    read -q "reply?Proceed with applying source changes? [y/N] " || return 1
    echo ""
  fi

  echo "Applying changes..."
  # --exclude=scripts is intentionally omitted here: scripts run on apply.
  # diff/status above exclude scripts only to reduce visual noise.
  chezmoi apply "$@"
  echo "Done!"
}
