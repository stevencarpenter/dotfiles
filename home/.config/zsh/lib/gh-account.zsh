# gh-account.zsh: interactive conveniences for the GitHub CLI.
#
# ~/.local/bin/gh handles account routing for both interactive and subprocess calls.

# Keep this pin aligned with skills/personal/gh-axi/SKILL.md after release review.
# gh-axi runs with a GitHub write credential, so unreviewed releases are unsafe.
: ${GH_AXI_PIN:=0.1.23}

# Use the pinned npx invocation required by the gh-axi skill.
gh-axi() {
  emulate -L zsh
  command npx -y "gh-axi@${GH_AXI_PIN}" "$@"
}
