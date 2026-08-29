#!/usr/bin/env bash
# Assert that every directly-exec'd script under home/ keeps its executable
# bit in the git index (mode 100755).
#
# Why: the chezmoi port dropped the `executable_` filename convention, and the
# sketchybar plugins silently lost their x-bit — sketchybar exec's plugin
# scripts by path, so a 644 plugin fails with EACCES and every bar item
# renders frozen/empty (found 2026-07-17). Sourced files (zsh profile.d,
# sketchybar items/, icon_map.sh) do NOT need the bit and are not listed here.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${repo_root}"

# Exec'd-by-path scripts: sketchybar plugins (spawned by the bar's update
# loop), the aerospace exec-and-forget layout, and the tmux status #() monitor.
exec_scripts=(
  home/.config/sketchybar/plugins/aerospace.sh
  home/.config/sketchybar/plugins/app_badge.sh
  home/.config/sketchybar/plugins/battery.sh
  home/.config/sketchybar/plugins/clock.sh
  home/.config/sketchybar/plugins/volume.sh
  home/.config/sketchybar/plugins/wifi.sh
  home/.config/aerospace/layouts/workspace-8-comms.sh
  home/.config/tmux/scripts/claude-pane-monitor.sh
  home/.local/bin/gh
  home/.local/bin/obsidian-capture
  home/.local/bin/worktrunk-commit-generator
  # PEP 723 uv scripts exec'd by path (CI steps, the Justfile, lefthook jobs,
  # and the shell test wrappers all rely on the `uv run --script` shebang).
  home/.local/bin/op-adopt
  firefox-dashboard-tabs/generate.py
  scripts/test_op_adopt.py
  scripts/assert-railway-psql-errors.py
  scripts/assert-worktrunk-config.py
  scripts/atuin-parity-mutate.py
  scripts/check-agent-tools-allowlist.py
  scripts/validate-mcp-master.py
  scripts/hook-text-files.py
  .claude/skills/mcp-sync-verify/scripts/list_targets.py
  .claude/skills/mcp-sync-verify/scripts/print_target_paths.py
  scripts/host-capability.sh
  scripts/sync-side-channels.sh
  scripts/update-inputs.sh
  scripts/update-unstable.sh
  scripts/test-gh-account-routing.sh
  scripts/test-obsidian-capture.sh
  scripts/test-worktrunk-commit-generator.sh
  scripts/test-ssh-controlpath-identity.sh
  scripts/test-atuin-filter-parity.sh
  scripts/test-atuin-filter-parity-mutations.sh
  scripts/test-eval-cache.sh
  scripts/test-bootstrap-clt-gate.sh
  scripts/test-external-overlay-contract.sh
  scripts/test-nix-review-regressions.sh
  scripts/test-railway-psql-errors.sh
  scripts/test-sync-capability-gating.sh
  scripts/test-tmux-lifecycle-contract.sh
  scripts/test-update-inputs.sh
  scripts/test-lefthook-hooks.sh
  scripts/test-update-unstable-soak.sh
  scripts/test-unstable-reminder.sh
  scripts/unstable-reminder.sh
)

failures=0
for script in "${exec_scripts[@]}"; do
  mode="$(git ls-files -s -- "${script}" | awk '{print $1}')"
  if [[ -z "${mode}" ]]; then
    echo "FAIL: ${script} is not tracked (moved/deleted? update this list)" >&2
    failures=$((failures + 1))
  elif [[ "${mode}" != "100755" ]]; then
    echo "FAIL: ${script} has git mode ${mode}, expected 100755 (chmod +x it)" >&2
    failures=$((failures + 1))
  fi
done

# Catch NEW plugins added without the bit: every plugin except sourced-only
# icon_map.sh must be 100755.
while IFS=$'\t' read -r mode path; do
  case "${path}" in
  home/.config/sketchybar/plugins/icon_map.sh) continue ;;
  esac
  if [[ "${mode}" != "100755" ]]; then
    echo "FAIL: ${path} has git mode ${mode}, expected 100755 (chmod +x it)" >&2
    failures=$((failures + 1))
  fi
done < <(git ls-files -s -- 'home/.config/sketchybar/plugins/*.sh' | awk '{print $1 "\t" $4}')

if [[ "${failures}" -gt 0 ]]; then
  echo "test-exec-bits: ${failures} failure(s)" >&2
  exit 1
fi
echo "test-exec-bits: OK (all exec'd scripts are 100755)"
