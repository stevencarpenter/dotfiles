Global Copilot MCP Usage Policy

Goal: Always use every available MCP server and tool unless explicitly overridden.

Principles:
\- Default mode is exhaustive: connect to and index all discovered MCP servers and their tools.
\- Never silently ignore a server or tool; log any initialization failure with reason.
\- Only restrict usage when an explicit user directive or config allowlist/blocklist is present.

Discovery Order (merged):
1. Project-local `.mcp/` configs
2. Repository root `.mcp/` configs
3. User `~/.config/mcp/`
4. Environment variable references (e.g. `MCP_SERVERS`, `MCP_TOOLS`)
5. Dynamic runtime registrations

Connection Rules:
\- Attempt parallel connections to all servers.
\- Retry transient failures with exponential backoff.
\- Mark permanently failed servers as inactive but re-attempt on session refresh.

Tool Registration:
\- Index every tool from every active server.
\- Preserve full metadata (name, description, input schema).
\- No pre-filtering unless user specifies `ALLOW_TOOLS` or `BLOCK_TOOLS`.

Resolution Strategy:
\- When a user request matches multiple tools, surface a ranked disambiguation list (rank by explicit user preference > semantic relevance > recency).
\- Never auto-hide lower-ranked tools.

Override Mechanisms (highest precedence first):
1. Inline user instruction: `USE ONLY serverA,toolX` or `EXCLUDE toolY`
2. Session config flags
3. Environment variables: `COPILOT_MCP_POLICY=all|allowlist|blocklist`
4. Persistent config files

Safety / Performance:
\- Cache tool schemas per session; invalidate on server change.
\- Enforce per-tool timeout without global suppression.
\- Degrade gracefully: partial availability is acceptable; never switch to single-server mode unless explicitly commanded.

Logging / Transparency:
\- Maintain a session summary of: discovered servers, connected servers, failed servers, total tools indexed.
\- Provide a quick command `LIST MCP STATUS` to show current state.

User Commands (examples):
\- `LIST ALL TOOLS`
\- `LIST SERVERS`
\- `USE ONLY serverName`
\- `EXCLUDE toolName`
\- `RESET MCP CONTEXT`

Default: If no override is present, behave as though `COPILOT_MCP_POLICY=all`.

End of policy.
