# gh-account.zsh: interactive conveniences for the GitHub CLI.
#
# ~/.local/bin/gh handles account routing for both interactive and subprocess calls.

# gh-axi runs with a GitHub write credential. The pin covers only this function; mise installs
# the CLI at `latest`. `dfm sync` adds the skill from upstream and its skills updater keeps it current.
# See docs/adopting-a-config.md#update-ownership for that update policy.
: ${GH_AXI_PIN:=0.1.35}

gh-axi() {
  emulate -L zsh
  command npx -y "gh-axi@${GH_AXI_PIN}" "$@"
}
