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
  local diff_output

  echo "Checking for conflicts between source and target..."

  diff_output="$(chezmoi diff --exclude=scripts --no-pager "$@" 2>&1)" || return $?

  if [[ -n "${diff_output}" ]]; then
    echo "Changes to be applied:"
    print -r -- "${diff_output}"
  else
    echo "Changes to be applied: (none — post-apply hooks will still run)"
  fi

  if chezmoi status --exclude=scripts --no-pager "$@" | _ca_has_target_drift; then
    echo ""
    echo "   Target files have changes that differ from source."
    echo "   Running chezmoi apply may overwrite those target-side changes."
    echo "   Review the diff above before proceeding."
    echo ""
    read -q "reply?Proceed with chezmoi apply? This may overwrite target changes. [y/N] " || return 1
    echo ""
  fi

  echo "Applying changes..."
  # --exclude=scripts is intentionally omitted here: scripts run on apply.
  # diff/status above exclude scripts only to reduce visual noise.
  # --no-pager: never pipe apply/diff output through less (silent hang).
  # --force: skip chezmoi's per-file overwrite prompts after ca already showed the diff.
  chezmoi apply --force --no-pager "$@"
  echo "Done!"
}
