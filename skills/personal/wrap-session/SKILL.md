---
name: wrap-session
description: Use when agent-journal is configured and a session milestone, blocker, change, verification, or finish should be recorded.
---

# Wrap Session

Self-gate before acting:

```bash
test -f "$HOME/.config/agent-journal/config.toml" && command -v agent-note >/dev/null 2>&1
```

If unavailable, skip journaling silently.

Set `AGENT_TOOL` to the active tool name, such as `codex` or `claude`, so the event records its actual origin.

Record the event with the most accurate type:

```bash
agent-note --tool "$AGENT_TOOL" --event start --summary "<starting context>"
agent-note --tool "$AGENT_TOOL" --event change --summary "<change made>"
agent-note --tool "$AGENT_TOOL" --event blocker --summary "<blocker>"
agent-note --tool "$AGENT_TOOL" --event verification --summary "<verification result>"
agent-note --tool "$AGENT_TOOL" --event finish --summary "<wrap-up>"
agent-journal digest --quiet
```

Run only the relevant `agent-note` command, then digest once. Keep summaries short and evidence-based.
