---
name: wrap-session
description: Use when agent-journal is configured and a session milestone or issue should be recorded.
---

# Wrap Session

Self-gate before acting:

```bash
test -f "$HOME/.config/agent-journal/config.toml" && command -v agent-note >/dev/null 2>&1
```

If unavailable, skip journaling silently.

Set `AGENT_TOOL` to the active tool name, such as `pi`, `codex`, or `claude`, so
the event records its actual origin.

Record the outcome, not the activity:

```bash
agent-note --tool "$AGENT_TOOL" --event milestone --summary "<what reached a done state>"
agent-note --tool "$AGENT_TOOL" --event issue --summary "<what is blocked or broken>"
agent-journal digest --quiet
```

Run only the relevant `agent-note` command, then digest once.

`--event` is advisory. The recorded type comes from the summary's substance, so
a milestone describing blocked work is recorded as an issue. That is not an
error. An entry judged to belong in no section is not recorded at all.

Record one event per completed unit of work, at the end. Do not record the
start of a session, intermediate checkpoints, or a passing test run that
shipped nothing. Keep summaries short and evidence-based.
