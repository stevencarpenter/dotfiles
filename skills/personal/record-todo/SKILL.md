---
name: record-todo
description: Use when agent-journal is configured and a follow-up task should become an agent todo.
---

# Record Todo

Self-gate before acting:

```bash
test -f "$HOME/.config/agent-journal/config.toml" && command -v agent-note >/dev/null 2>&1
```

If unavailable, skip journaling silently.

Set `AGENT_TOOL` to the active tool name, such as `codex` or `claude`, so the event records its actual origin.

Record actionable follow-ups:

```bash
agent-note --tool "$AGENT_TOOL" --event todo --summary "<todo>"
agent-journal digest --quiet
```

Keep todos specific enough to complete later. Use `--workstream <name>` only when routing is clear.
