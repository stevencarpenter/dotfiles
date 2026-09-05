# Pi runtime notes (appended to the shared global instructions)

The shared instructions above were written for Codex. Where they name a
capability pi does not have, substitute the pi-native equivalent below.
Do not report the shared instructions as wrong; they are shared on purpose.

- Built-in tools are `read`, `write`, `edit`, `bash` (plus `grep`, `find`,
  `ls`).
- MCP is available through the `pi-mcp-adapter` package, not through a
  native MCP client. Servers come from `~/.config/mcp/mcp.json`, which
  `mcp_sync` generates from the same master + machine overlay that feeds
  Claude, Codex, Cursor, and the rest. Never hand-edit that file; edit
  `home/.config/mcp/mcp-master.json` (or the machine overlay) and run
  `just mcp-sync`.
- Adapter tools: `mcp` is a proxy. Call `mcp({ search: "..." })` to
  discover a tool and describe it before calling. Per-server tools are namespaced with
  underscores, not hyphens: `mcp__codebase_memory_mcp`, `mcp__codegraph`,
  `mcp__grafana`, `mcp__hippo`. Servers are lazy and only connect on first
  use, so the tool-priority rules in the shared instructions apply here as
  written.
- `mcp__idea__*` and `mcp__railway__*` genuinely do not exist in pi. They
  are Claude Code plugin-supplied, not `mcp_sync`-managed, so they are
  absent from `~/.config/mcp/mcp.json`. Use the CLI directly (`rg`,
  `gh-axi`, `git`, `jj`, `railway`) in their place.
- `mcp__kaneo` requires an interactive OAuth grant (`/mcp-auth kaneo`) that
  does not survive into a fresh machine. If a kaneo call fails to connect,
  say so rather than falling back to a guess.
- Skills live in `~/.pi/agent/skills/` (same SKILL.md format as Claude).
  Check `/skill:name` before starting a task, exactly as the shared
  instructions require for skills.
- There are no sub-agents, plan mode, permission popups, or background
  shell. Run multi-step work sequentially in this session; use tmux
  directly when a command needs to outlive the turn.
- Config edits under `~/.dotfiles/home/.pi/` take effect after `/reload`
  (prompts, skills, extensions) or after a Nix switch (symlinked files).
  Sessions and trust decisions under `~/.pi/` are pi-owned state: never
  commit them. `settings.json` is the exception: it is repo-managed AND
  written by `pi install`, so a package install shows up as a tracked diff.
