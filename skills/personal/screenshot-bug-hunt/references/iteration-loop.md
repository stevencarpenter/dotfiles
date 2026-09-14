# Verify a visual fix

Use this loop when the user has requested fixes. Preserve the baseline capture before editing so the result can be compared against the observed defect.

1. Reproduce the highest-priority in-scope defect.
2. Make the smallest change that addresses its cause.
3. Rebuild or refresh using the project's normal workflow.
4. Capture and inspect the affected page at the relevant viewport.
5. Recheck shared components or styles that the change can affect.

Batch independent copy changes when one capture can verify them. Inspect layout changes before adding another change that could obscure their effect.

## Limit capture scope

The bundled helper accepts a targets file:

```json
[{"slug": "home", "path": "/"}]
```

For one viewport:

```bash
node "$SKILL_DIR/scripts/shoot.mjs" --base "$SITE_URL" --targets "$TARGETS_FILE" --only desktop --out /tmp/after
```

Set the variables to the skill directory, running URL, and targets file. Use the helper's `--help` for viewport tags. Keep before and after captures in separate directories and confirm their timestamps.

## Missing baseline

If the earlier build is needed, use an isolated checkout at the known base revision. Do not stash, reset, or reverse-edit a shared working tree to recreate a screenshot. If that baseline cannot be reproduced, state what the current capture verifies.

A temporary browser style override can test a CSS hypothesis. Label it as an experiment; it does not prove what an earlier committed build rendered.

## Completion

Stop when the requested defects are verified and relevant regression checks pass. Report any remaining defect with its evidence and the reason it is unresolved. A final user sign-off is needed only when the user requested a subjective design decision or an approval workflow.
