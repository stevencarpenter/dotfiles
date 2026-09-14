# ADR format

Follow the repository's existing decision-record location and format. When none exists, use `docs/adr/NNNN-slug.md` and create the directory only when a decision needs recording.

A short record can be one paragraph:

```markdown
# Used SQLite for the local event store

The daemon needs durable storage without a separate service. SQLite provides
transactions and ships with the supported systems. This keeps local setup
small but limits concurrent writers to the workload the daemon can serialize.
```

State the problem, chosen option, reason, and material consequence. Add rejected alternatives or status only when they help explain or revisit the decision.

For numbered records, increment the highest existing number. When superseding a decision, preserve its history and link to the replacement.
