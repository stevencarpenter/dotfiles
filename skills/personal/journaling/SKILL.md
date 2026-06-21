---
name: journaling
description: Use when agent-journal is configured and material work should be captured in the user's journal.
---

# Journaling

Use this skill to decide whether to record agent work through `agent-journal`.

Before journaling, self-gate:

```bash
test -f "$HOME/.config/agent-journal/config.toml" && command -v agent-note >/dev/null 2>&1
```

If that check fails, do nothing and continue the user's task.

Record only material events:

- Decisions the user will care about later.
- Todos or follow-up tasks.
- Blockers, risks, or handoff context.
- Completed changes and verification results at session wrap-up.

Do not record secrets, credentials, private tokens, or trivial command chatter.

Use the narrower skills when they apply:

- `record-decision` for architectural or workflow decisions.
- `record-todo` for follow-up tasks.
- `wrap-session` for starts, finishes, blockers, changes, and verification.
