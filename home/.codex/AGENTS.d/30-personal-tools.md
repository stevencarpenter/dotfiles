## Local knowledge tools

This server is configured on this machine only. Use `mcp__hippo__*` for prior-attempt and lesson
recall; it ranks with the other MCP servers in the tool priority order.

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
