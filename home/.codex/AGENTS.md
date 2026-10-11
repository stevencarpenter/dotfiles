# Global Codex Instructions

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

The shared Simplified Technical English output policy is appended at activation
from `~/.codex/AGENTS.d/20-output-policy.md` (or the corresponding Pi fragment).

## Configured Tool Priority

Use the highest-priority configured tool that supports the required operation. Do not use a
lower-priority tool when a higher-priority tool provides the same operation.

### Tool Priority Order (highest to lowest)

1. **Skills.** Check available skills before starting a task. If a skill may apply, inspect it before acting.
2. **MCP servers.** Use `mcp__idea__*` for IntelliJ operations, `mcp__grafana__*` for Grafana
   operations, and `mcp__hippo__*` for prior-attempt and lesson recall.
3. **Specialized agents.** Use Explore, Plan, code-reviewer, and other Agent subtypes for tasks
   matching their descriptions.
4. **Built-in tools** (Read, Grep, Glob, Edit, Write, Bash). Use these when no skill, MCP server,
   or specialized agent covers the operation.

### Git Operations

- Use `gh-axi` for GitHub and `chrome-devtools-axi` for browser automation.
- Never sign commits as being created by an AI agent, assistant, or coding harness.
- Never add a reference to an AI agent, assistant, harness, model, or tool to a commit message.

### IntelliJ MCP substitutions (IntelliJ is always running)

| Instead of                  | Prefer                                                                        |
| --------------------------- | ----------------------------------------------------------------------------- |
| `Read` on a project file    | `mcp__idea__get_file_text_by_path`                                            |
| `Grep` for code/text search | `mcp__idea__search_in_files_by_text` or `mcp__idea__search_in_files_by_regex` |
| `Glob` for file discovery   | `mcp__idea__find_files_by_glob` or `mcp__idea__find_files_by_name_keyword`    |
| Manual lint/error checking  | `mcp__idea__get_file_problems`                                                |
| Symbol/type resolution      | `mcp__idea__get_symbol_info`                                                  |
| Running tests/builds        | `mcp__idea__execute_run_configuration` or `mcp__idea__build_project`          |

Use LSP before `rg` for symbol resolution, type checking, and references.

- Python (`pyright`), Go (`gopls`), and Rust (`rust-analyzer`) are enabled on every machine.
- Swift, TypeScript, and Lua are enabled on machines with the `dev` capability.

### Codegraph for code exploration (when `mcp__codegraph__*` is available)

- Use `codegraph_explore` for explanation, trace, and location questions over indexed source.
- Use `rg` or `Read` for non-indexed artifacts such as `.plist`, YAML, Python, and shell scripts.

### Hippo for prior work and lessons (when `mcp__hippo__*` is configured)

Hippo captures shell activity, Claude and Codex sessions, and browser history across all projects.
Its history answers whether an idea was already tried and what the attempt taught.

- After forming a new idea, query hippo before implementing it. An idea includes a proposed
  approach, design, fix hypothesis, refactor direction, tool choice, or dependency choice.
- Ask both scopes: has this been tried in this project, and has it been tried anywhere else.
- Use `ask` for a synthesized answer, `search_hybrid` for raw matches, and `get_lessons` for
  recorded lessons.
- Report the result in one sentence: prior attempt and its outcome, an applicable lesson, or no
  prior record found.
- When hippo returns a relevant lesson, apply it or state why it does not apply here.
- Recheck at later checkpoints: before writing a plan, when a debugging hypothesis changes, and
  before adopting a new tool or dependency.
- Skip the check only on machines where the hippo server is not configured.
- Usage of this rule is measured. The baseline, the scheduled re-measure dates, the instruments in
  `~/.local/share/hippo/metrics/`, and the query constraints are documented in
  `~/.dotfiles/docs/ai-tools/hippo-usage-measurement.md`. Read that file before re-measuring or
  before changing how hippo usage is counted.

### Shell tooling

- Use `rg` (ripgrep) instead of `grep` in commands and pipelines.
- Use `grep` only in scripts that must run on a machine without ripgrep.

### Experimental Agent Teams (`CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1`)

- Agent teams use tmux mode (`teammateMode: tmux`).
- Each agent runs in its own tmux window.
- Use `TeamCreate` for two or more independent subtasks.

Call `ToolSearch` before using `mcp__idea__*`, `LSP`, `TeamCreate`, or another deferred tool.

Confirm before destructive actions. After 3 failed fixes, stop and name the
doubtful assumption.
