---
name: machine-capability-audit
description: Audit chezmoi machine-capability gating. USE THIS SKILL whenever the user adds a capability to `.chezmoidata/machines.toml`, adds a new machine row, migrates a `hasPrefix` gate to the capability table, or asks any of "is this capability used?", "are there orphan capabilities?", "verify capability gating", "what gates does X have?", "audit capabilities", "find prefix gates I should migrate", "did I forget to wire this up?". Triggers on edits to `machines.toml`, on PRs that add `(index .machines .machine).<cap>` references, and any time the user is reasoning about whether a chezmoi gate is consistent across the repo. Bias toward triggering: a 30-second audit is cheap; shipping a defined-but-unwired capability is a silent bug.
---

# Machine capability audit

Static-analysis pass over the chezmoi capability gating system. Detects orphans (capabilities defined but unused), undefined gates (used but not in the table), and `hasPrefix` gates that should migrate to the capability table per the repo's stated preference.

## When this fires

- User edits `.chezmoidata/machines.toml` (adds a row, adds a column, removes either).
- User adds or removes `(index .machines .machine).<capability>` somewhere.
- User asks any verification question about capability gating.
- Before merging a PR that touches gating logic.

## Run

```bash
bash dot_claude/skills/machine-capability-audit/scripts/audit.sh
```

The script roots itself via `chezmoi source-path` (or `REPO_ROOT=…` override), so it works from anywhere. It exits non-zero when orphans or undefined gates are found — handy if this is later wired into the Justfile or a pre-commit hook.

## Output shape

```
# Capabilities defined: atuin, aws_sso, dev, gui, hippo, mcp, tiling
# Per capability:
##  atuin: 1 consumers (.chezmoiignore:115)
##  aws_sso: 0 consumers — ORPHAN
##  dev: 0 consumers — ORPHAN
##  gui: 1 consumers (dot_config/homebrew/Brewfile.tmpl:85)
##  hippo: 2 consumers (.chezmoiignore:129, dot_claude/modify_settings.json.tmpl:13)
##  mcp: 3 consumers (.chezmoiignore:122, dot_config/homebrew/Brewfile.tmpl:55, .chezmoiscripts/run_after_sync-mcp.sh.tmpl:12)
##  tiling: 3 consumers (.chezmoiignore:106, dot_config/homebrew/Brewfile.tmpl:69, dot_config/homebrew/Brewfile.tmpl:108)
# Prefix-based gates that could migrate:
##  dot_config/dot_copilot/config.json.tmpl:11 (hasPrefix "personal")
##  ...
```

## How to interpret

| Finding              | What it means                                                      | Typical fix                                                                                                                                              |
|----------------------|--------------------------------------------------------------------|----------------------------------------------------------------------------------------------------------------------------------------------------------|
| **N consumers**      | Capability is wired into N gate sites.                             | Healthy — no action.                                                                                                                                     |
| **ORPHAN**           | Capability defined in the table but referenced by nothing.         | Either wire it up at the intended gate site, or delete it from every row in `machines.toml`. Empty capabilities silently rot.                            |
| **Undefined gate**   | A `(index .machines .machine).<cap>` reference points at no key.   | Typo, or the capability was removed without updating consumers. Either restore the row or fix the reference.                                             |
| **Prefix candidate** | A `hasPrefix "personal"` / `"work"` / `"lab"` site.                | If the gate is identity/secret-flavored (work-only credentials, personal email), prefix is fine. If it gates a *behavior*, migrate to a capability key.  |

## When NOT to migrate a prefix gate

Some prefix gates are correct as-is:

- `.chezmoi.toml.tmpl` — bootstrap-time, before the capability table is loadable. **Always exclude.** (The script already excludes this file.)
- Identity/ownership splits — `work-secrets.zsh`, `aws-config-gen/overrides.json`. The capability *is* "is this the work machine," and the prefix expresses that directly.
- One-off scripts that genuinely depend on machine name, not capability — rare, but possible.

If you're not sure, ask yourself: "If I added a fourth machine, would I want this gate to apply to it based on a boolean, or based on its name?" Boolean → migrate. Name → keep.

## Adding a new capability — recommended flow

1. Add the key to *every* row in `.chezmoidata/machines.toml` (orphan-by-design until step 2).
2. Wire it at one or more gate sites — `.chezmoiignore`, a `.tmpl`, or a `.chezmoiscripts/*` hook.
3. Run this audit. Expect zero orphans and zero undefined gates.
4. `chezmoi diff` to confirm the gate behaves as intended on this machine.

## Adding a new machine — recommended flow

1. Add the row in `.chezmoidata/machines.toml` with capabilities flipped to taste.
2. Add the name to the prompt hint in `.chezmoi.toml.tmpl`.
3. Run this audit. The output won't change — capabilities are unchanged — but it confirms no row was missed.

## Not for

- Verifying *runtime* template behavior (`chezmoi diff` / `chezmoi execute-template` are the right tools).
- Catching syntactic template errors (chezmoi will surface those at `apply` time).
- Detecting whether a capability *should* exist — that's a design call, not a static-analysis call.
