# Pi runtime notes for this machine

- This machine also has the adapter tools `mcp__codebase_memory_mcp` and
  `mcp__hippo`.
- `mcp__railway__*` does not exist in pi. It is Claude Code plugin-supplied,
  not `mcp_sync`-managed. Use the `railway` and `jj` CLIs directly.
- `mcp__kaneo` requires an interactive OAuth grant (`/mcp-auth kaneo`) that
  does not survive into a fresh machine. If a kaneo call fails to connect,
  say so rather than falling back to a guess.
