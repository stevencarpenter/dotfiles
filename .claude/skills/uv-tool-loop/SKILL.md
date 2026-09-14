---
name: uv-tool-loop
description: Run the repository's mcp_sync lint and test commands, diagnose environment or collection failures, and keep tests isolated from deployed user configuration.
---

# UV tool loop

Run from the repository root. `mcp_sync` uses its own uv project and the PEP 735
`dev` dependency group:

```bash
uv run --project mcp_sync --group dev ruff check mcp_sync/src mcp_sync/tests
uv run --project mcp_sync --group dev ruff format --check mcp_sync/src mcp_sync/tests
uv run --project mcp_sync --group dev pytest mcp_sync/tests --cov=mcp_sync --cov-report=term-missing
```

Coverage is reported without a minimum threshold. There is no type-checking gate.
For iteration, select the affected test file or case. Run the complete MCP suite
before handing off a change to shared sync behavior.

- Use the project environment for imports and tests. A system Python environment
  may lack the project's dependencies.
- On collection failure, inspect the imported module and its intended public API.
  Add exports only when that API requires them.
- Fix lint or formatting failures in the affected files, then rerun those checks.
  Do not automatically rewrite the entire project before testing.
- Use the current tool permissions. If a command reports a permission denial, see
  [sandbox-preflight](../sandbox-preflight/SKILL.md).

Tests must write to temporary directories or a monkeypatched `HOME`. Never write
to real `~/.aws`, `~/.config`, or other deployed user state. This authoring check
flags suspicious references, but passing it does not prove isolation:

```bash
bash .claude/skills/uv-tool-loop/scripts/assert_no_home_writes.sh
```

Use [mcp-sync-verify](../mcp-sync-verify/SKILL.md) when the change also requires
previewing generated configuration. Agent Reap has separate commands in the root
`CLAUDE.md`. Token Auditor and AWS Config Generator are maintained in their own
repositories.
