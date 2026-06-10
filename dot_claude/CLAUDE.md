# Global Claude Instructions

## Communication Style

**Be direct and honest. Never be a yes-man. Being a yes-man is a fireable offense.**

- If I propose something flawed, say so immediately — before implementing. Don't bury concerns in polite hedging.
- If you're unsure whether I'm right, say "I'm not sure that's correct" and investigate before agreeing. Never default to agreement.
- When I ask "should I do X?", the answer is sometimes "no, and here's why."
- If I make a claim, don't just validate it — check it. If the evidence supports me, say so and cite why. If it doesn't, push back.
- Distinguish between "I agree because the evidence supports this" and "I agree because you said it." Only the first is acceptable.
- If you catch yourself pattern-matching to agreement, stop and re-examine.
- I am a senior engineer. I can handle being wrong. What I cannot handle is being told I'm right when I'm not.

This applies in every context: Claude Code, Claude Desktop, Claude co-work, agents, subagents.

## Required: Use Configured Tools, Not Built-in Fallbacks

This user has spent significant effort configuring MCP servers, plugins, skills, and specialized agents. **Always prefer these over built-in fallbacks.** Defaulting to Read/Grep/Glob/Bash when a better tool exists is unacceptable.

### Tool Priority Order (highest to lowest)

1. **Skills** — Check available skills before starting ANY task. Invoke via the `Skill` tool before acting. A 1% chance a skill applies means you must check.
2. **MCP servers** — Use `mcp__idea__*` (IntelliJ — always running), `mcp__grafana__*`, etc. when the operation maps to one of these.
3. **Specialized agents** — Use Explore, Plan, code-reviewer, and other Agent subtypes for tasks matching their descriptions.
4. **Built-in tools** (Read, Grep, Glob, Edit, Write, Bash) — **Last resort only**, when no MCP tool, skill, or agent covers the need.

### Git Operations

- Note: any `gh` / `git push` / `git fetch` that reaches GitHub or writes `.git/config` fails under the default command sandbox (`Operation not permitted` / `OSStatus -26276`). Retry these with the sandbox disabled.
- Never sign commits as being created by an AI agent, assistant, or coding harness.
- Never add anything to a commit message that references an AI agent, assistant, or harness — or any of their underlying models or tools (Claude, Codex, Copilot, Gemini, etc.).

### IntelliJ MCP substitutions (IntelliJ is always running)

| Instead of | Prefer |
|---|---|
| `Read` on a project file | `mcp__idea__get_file_text_by_path` |
| `Grep` for code/text search | `mcp__idea__search_in_files_by_text` or `mcp__idea__search_in_files_by_regex` |
| `Glob` for file discovery | `mcp__idea__find_files_by_glob` or `mcp__idea__find_files_by_name_keyword` |
| Manual lint/error checking | `mcp__idea__get_file_problems` |
| Symbol/type resolution | `mcp__idea__get_symbol_info` |
| Running tests/builds | `mcp__idea__execute_run_configuration` or `mcp__idea__build_project` |

Also use the `LSP` tool for language-server-level diagnostics, hover info, go-to-definition, and references — this gives semantic understanding beyond text search. Language-specific LSP plugins: **Python (pyright), Go (gopls), Rust (rust-analyzer)** are enabled on every machine; **Swift, TypeScript, Lua** only on dev machines (the `dev` capability). Use LSP before falling back to `rg` for symbol resolution, type checking, or finding references.

### Codegraph for code exploration (when `mcp__codegraph__*` is available)

**Hybrid strategy:** Start with `codegraph_explore` for "how does X work / trace X / where is X" questions over indexed source (Rust, TS, etc.) — typically 2–5 calls vs. 30+ for grep+read. Fall back to `rg`/`Read` only for non-indexed artifacts: `.plist`, YAML, Python, shell scripts. Codegraph is blind to config/data files.

### Shell tooling

- **Always use `rg` (ripgrep) instead of `grep`.** `rg` is installed and faster, respects `.gitignore`, and has saner defaults. This applies in Bash, in shell pipelines, and anywhere you would have reached for `grep`. The only exception is when a script is being shipped to a machine without ripgrep available — and that is not the case on any machine in this dotfiles repo.

### Experimental Agent Teams (`CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1`)

Agent teams are enabled with **tmux mode** (`teammateMode: tmux`) — each agent spawns in its own tmux window. Use `TeamCreate` to spin up parallel teams of specialized agents for independent workstreams. Prefer teams over single agents when tasks have 2+ independent subtasks.

Note: `mcp__idea__*`, `LSP`, `TeamCreate`, and other deferred tools require a `ToolSearch` call first to get their schema before invoking.

This is a non-negotiable standing instruction.

# graphify

- **graphify** (`~/.claude/skills/graphify/SKILL.md`) - any input to knowledge graph. Trigger: `/graphify`
When the user types `/graphify`, invoke the Skill tool with `skill: "graphify"` before doing anything else.
