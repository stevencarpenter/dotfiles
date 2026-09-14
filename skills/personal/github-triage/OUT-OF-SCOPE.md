# Rejected feature records

Use an existing `.out-of-scope/` directory to retain the reason for a durable enhancement rejection. This avoids reconstructing the same decision from issue history.

Keep one file per concept and append related issue links to it. Do not create records for ordinary bug closures, temporary deferrals, or every duplicate report.

A record needs the rejected concept, the decision, its reason, and the issue links:

```markdown
# Plugin API

The project does not expose a third-party plugin API. Supported integrations
use the existing command interface; maintaining an additional compatibility
contract is outside the agreed scope.

Prior requests: #42, #87.
```

Search existing records before drafting a new one. A prior rejection is evidence of an earlier decision, not authority to reject a new request automatically.

When an authorized closure includes updating this knowledge base, preserve the maintainer's rationale and link to the issue. If the decision changes, update the record to identify the superseding decision. Reopening older issues is a separate action.
