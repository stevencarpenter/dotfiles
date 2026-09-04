# Pi runtime notes (appended to the shared global instructions)

The shared instructions above were written for Codex. Where they name a
capability pi does not have, substitute the pi-native equivalent below.
Do not report the shared instructions as wrong; they are shared on purpose.

- Built-in tools are `read`, `write`, `edit`, `bash` (plus `grep`, `find`,
  `ls`). There is no MCP layer: `mcp__idea__*`, `mcp__grafana__*`, and
  `mcp__hippo__*` do not exist here. Use the CLI directly (`rg`, `gh-axi`,
  `git`, `jj`) instead of an MCP call.
- Skills live in `~/.pi/agent/skills/` (same SKILL.md format as Claude).
  Check `/skill:name` before starting a task, exactly as the shared
  instructions require for skills.
- There are no sub-agents, plan mode, permission popups, or background
  shell. Run multi-step work sequentially in this session; use tmux
  directly when a command needs to outlive the turn.
- Config edits under `~/.dotfiles/home/.pi/` take effect after `/reload`
  (prompts, skills, extensions) or after a Nix switch (symlinked files).
  Sessions, packages, and trust decisions under `~/.pi/` are pi-owned
  state: never commit them.
