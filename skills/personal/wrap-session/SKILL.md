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

Record the event with the most accurate type:

```bash
agent-note --tool claude --event start --summary "<starting context>"
agent-note --tool claude --event change --summary "<change made>"
agent-note --tool claude --event blocker --summary "<blocker>"
agent-note --tool claude --event verify --summary "<verification result>"
agent-note --tool claude --event finish --summary "<wrap-up>"
agent-journal digest --quiet
```

Run only the relevant `agent-note` command, then digest once. Keep summaries short and evidence-based.
