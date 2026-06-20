---
name: record-decision
description: Use when agent-journal is configured and a durable project or workflow decision should be recorded.
---

# Record Decision

Self-gate before acting:

```bash
test -f "$HOME/.config/agent-journal/config.toml" && command -v agent-note >/dev/null 2>&1
```

If unavailable, skip journaling silently.

Record concise, durable decisions:

```bash
agent-note --tool claude --event decision --summary "<decision>"
agent-journal digest --quiet
```

Use `--scope daily` only for daily context that should not become a project note. Use `--workstream <name>` only when the user or repo context gives a clear workstream name.
