## Local knowledge tools

These servers are configured on this machine only.

- Use `mcp__codebase-memory-mcp__*` for structural code questions and `mcp__hippo__*` for
  prior-attempt and lesson recall. Both rank with the other MCP servers in the tool priority order.
- In the symbol and structure lookup order, use codebase-memory first: `search_graph`, then
  `trace_path`. It resolves calls written as qualified paths and reports index coverage. Use
  codegraph after it.

### Codebase Memory (`mcp__codebase-memory-mcp__*`)

Use codebase-memory for structural code questions in indexed repositories. The `codebase-memory`
skill holds the tool routing table.

- If a repository is not indexed, run `index_repository` once. Keep `auto_index` disabled.
- Do not index scratch, temporary, or non-repository directories.
- Re-index manually after a large pull or generated-source update.
- Call `check_index_coverage` for every file that supports a conclusion. Do not make absence,
  exhaustive, or dead-code claims from the graph alone.

### Hippo for prior work and lessons (when `mcp__hippo__*` is configured)

- After forming a new idea, query hippo before implementing it. An idea includes a proposed
  approach, design, fix hypothesis, refactor direction, tool choice, or dependency choice.
- Ask both scopes: has this been tried in this project, and has it been tried anywhere else.
- Route the lookup through the `hippo-query` agent when the Agent tool is available; otherwise
  call the tools directly. Use `ask` for a synthesized answer, `search_hybrid` for raw matches,
  and `get_lessons` for recorded lessons.
- Report the result in one sentence: prior attempt and its outcome, an applicable lesson, or no
  prior record found.
- When hippo returns a relevant lesson, apply it or state why it does not apply here.
- Recheck at later checkpoints: before writing a plan, when a debugging hypothesis changes, and
  before adopting a new tool or dependency.
- Skip the check only on machines where the hippo server is not configured.
- Usage of this rule is measured. Read `~/.dotfiles/docs/ai-tools/hippo-usage-measurement.md`
  before re-measuring or before changing how hippo usage is counted.
