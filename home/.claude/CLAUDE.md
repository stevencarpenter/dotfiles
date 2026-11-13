# Global Claude Instructions

## Scope Discipline

- Keep working on the requested task when an unrelated issue appears. Report the
  unrelated issue briefly, without expanding the implementation to include it.
- Resolve defects necessary to complete the authorized task. Obtain authorization
  before designing, implementing, testing, or publishing a separate task.

## Communication Style

### Accuracy and judgment

- Check the user's claims before accepting them.
- State evidence that contradicts a user claim before acting on that claim.
- State uncertainty and identify the evidence that would resolve it.
- Do not default to agreement.
- Distinguish verified facts, inferences, and recommendations.
- Base recommendations on evidence and engineering constraints, not on the user's stated preference.
- Assume the user has senior engineering knowledge.
- Add background only when it affects the decision or the user asks for it.

@~/.config/agents/output-policy.md

The `~/.claude/hooks/no-em-dash-commit.sh` hook checks commits and GitHub prose.
Use `ALLOW_EM_DASH=1` only to preserve a verbatim quote.

## Configured Tool Priority

Use the highest-priority configured tool that supports the required operation. Do not use a
lower-priority tool when a higher-priority tool provides the same operation.

### Tool Priority Order (highest to lowest)

1. **Specialized agents.** Delegate a bounded, independent subtask to the Agent subtype whose
   description matches it. Handle a single cohesive task directly.
2. **Skills.** Check available skills before starting each task. Invoke a matching skill before acting.
3. **MCP servers.** Use `mcp__codebase-memory-mcp__*` for structural code questions,
   `mcp__idea__*` for IntelliJ operations, `mcp__grafana__*` for Grafana operations, and
   `mcp__hippo__*` for prior-attempt and lesson recall.
4. **Built-in tools** (Read, Grep, Glob, Edit, Write, Bash). Use these when no specialized agent,
   skill, or MCP server covers the operation.

### Git Operations

- Use `gh-axi` for GitHub and `chrome-devtools-axi` for browser automation.
- Never sign commits as being created by an AI agent, assistant, or coding harness.
- Never add a reference to an AI agent, assistant, harness, model, or tool to a commit message.

### Symbol and structure lookup

Use this order for finding a symbol, its callers and callees, and change impact:

1. codebase-memory: `search_graph`, then `trace_path`. It resolves calls written as qualified
   paths and reports index coverage.
2. codegraph: `codegraph_explore` to read the source of an area in one call. Do not rely on
   `codegraph_callers` for a complete caller list; it misses qualified-path calls.
3. IntelliJ `mcp__idea__get_symbol_info` or LSP for type, hover, and definition information at a
   known position, and for repositories that are not indexed.
4. `rg` for literals, configuration, and files the graphs do not index.

### IntelliJ MCP substitutions (when the project is open in IntelliJ)

The `idea` tools work only for projects open in IntelliJ. Pass `projectPath`; if the project is
not open, use the built-in tool.

| Instead of                  | Prefer                                                               |
| --------------------------- | -------------------------------------------------------------------- |
| `Read` on a project file    | `mcp__idea__read_file`                                               |
| `Grep` for code/text search | `mcp__idea__search_text` or `mcp__idea__search_regex`                |
| `Glob` for file discovery   | `mcp__idea__search_file`                                             |
| Manual lint/error checking  | `mcp__idea__get_file_problems`                                       |
| Running tests/builds        | `mcp__idea__execute_run_configuration` or `mcp__idea__build_project` |

Use LSP for type checking, hover, and go-to-definition at a known position.

- Python (`pyright`), Go (`gopls`), and Rust (`rust-analyzer`) are enabled on every machine.
- Swift, TypeScript, and Lua are enabled on machines with the `dev` capability.

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

### Shell tooling

- Use `rg` (ripgrep) instead of `grep` in commands and pipelines.
- Use `grep` only in scripts that must run on a machine without ripgrep.
- The interactive shell aliases `sed` to `gsed` (GNU sed). In commands for the user to run, use
  GNU syntax: `sed -i 's/a/b/' file`, with no `''` after `-i`.

### Experimental Agent Teams (`CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1`)

- Agent teams use tmux mode (`teammateMode: tmux`).
- Each agent runs in its own tmux window.
- Use `TeamCreate` when two or more independent subtasks are each large enough to need their own context.

Call `ToolSearch` before using `mcp__idea__*`, `LSP`, `TeamCreate`, or another deferred tool.

## Agent Journaling

If `agent-journal` is configured, use its skills to record material decisions, todos, blockers,
completed changes, and session summaries. Do not journal secrets, credentials, or routine commands.
