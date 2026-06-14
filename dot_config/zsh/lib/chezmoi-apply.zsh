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
  local diff_output pending_scripts

  echo "Checking for conflicts between source and target..."

  diff_output="$(chezmoi diff --exclude=scripts --no-pager "$@" 2>&1)" || return $?

  if [[ -n "${diff_output}" ]]; then
    echo "Changes to be applied:"
    print -r -- "${diff_output}"
  else
    echo "Changes to be applied: (none — post-apply hooks will still run)"
  fi

  # Scripts are hidden from the diff above (by --exclude=scripts here and by the
  # repo's global [diff] exclude) so every apply isn't a wall of phantom "new
  # file" script diffs. But scripts ALWAYS run on apply, and --force below
  # suppresses chezmoi's own per-script prompts — so list which scripts will
  # execute. --exclude=none resets the global exclude (a plain --include=scripts
  # loses to it); full content: `chezmoi diff --exclude=none --include=scripts`.
  # This is run-log visibility, not a gate: with no target drift, apply runs
  # immediately after this — read the list, don't expect a pause.
  pending_scripts="$(chezmoi diff --exclude=none --include=scripts --no-pager "$@" 2>/dev/null \
    | sed -n 's#^diff --git a/.* b/#  #p')"
  if [[ -n "${pending_scripts}" ]]; then
    echo ""
    echo "Scripts that will run on apply:"
    print -r -- "${pending_scripts}"
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
