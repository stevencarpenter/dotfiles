---
name: sandbox-preflight
description: Pre-classify the command classes this repo's Claude Code sandbox blocks and run them with dangerouslyDisableSandbox on the FIRST attempt instead of looping on "Operation not permitted". USE THIS SKILL whenever a Bash command just failed with "Operation not permitted", "OSStatus -26276", "could not write config file .git/config", "Failed to initialize cache at `~/.cache/uv`", "Control socket connect ... Operation not permitted", or "mkdtemp/mktemp failed"; whenever you are ABOUT to run `uv`/`uvx`/`ruff`/`pytest`/`ty` in mcp_sync, aws_config_gen, or token_auditor; whenever you are about to run ANY `gh` API call or `git push`/`fetch`/`pull`/`remote set-url`/`config`/`branch -m` (anything that writes `.git/config` or hits the GitHub network); whenever you use git over ssh with ControlMaster; or whenever the user asks "should I disable the sandbox", "why does uv/gh/git keep failing", "the sandbox is blocking this". Bias toward triggering BEFORE the command: these failures are structural (only `~/.cache/pre-commit` and `$TMPDIR` are pre-allowed in `dot_claude/modify_settings.json.tmpl`; `~/.cache/uv`, `.git`, and `~/.ssh` are NOT), so a sandboxed first attempt is a guaranteed wasted round-trip. Also carries the rule to NOT co-batch a risky call with independent commands, since one sandbox failure cancels every sibling in a parallel batch.
---

# Sandbox preflight

Decide *before* you run a Bash command whether the Claude Code command sandbox will block
it, and pass `dangerouslyDisableSandbox: true` on the first attempt for the classes that
always fail. This turns the repo's single largest failure class into zero wasted retries.

## Why this skill exists

The sandbox allows reads broadly but only permits writes to a small allowlist (`.`,
`$TMPDIR`, and a few cache dirs). Verified against `dot_claude/modify_settings.json.tmpl`:
the only path pre-seeded into `sandbox.filesystem.allowWrite` is `~/.cache/pre-commit`.
`~/.cache/uv`, `.git/config`, and `~/.ssh` are **not** allowlisted, and the GitHub network
path fails certificate verification under the sandbox (`OSStatus -26276`). So `uv`, `gh`,
and config-writing `git` commands fail *deterministically* — yet the rule lives only in
CLAUDE.md prose, which does not convert to first-attempt behavior (sessions even
re-inject "for ANY uv call set dangerouslyDisableSandbox" by hand). This skill makes the
decision mechanical.

> This skill only decides the sandbox flag. It does not change *what* command to run — the
> calling skill (e.g. [branch-first-pr](../branch-first-pr/SKILL.md),
> [uv-tool-loop](../uv-tool-loop/SKILL.md)) owns that.

## The decision table

| Command pattern | Sandbox? | Reason class |
|---|---|---|
| `uv` / `uvx` / `ruff` / `pytest` / `ty` (any of the 3 tools) | **DISABLE** | writes `~/.cache/uv` (not allowlisted) |
| `gh ...` (any API call) | **DISABLE** | GitHub TLS fails — `OSStatus -26276` |
| `git push` / `fetch` / `pull` / `clone` / `ls-remote` | **DISABLE** | GitHub network |
| `git config` / `branch -m` / `remote set-url` / `init` | **DISABLE** | writes `.git/config` |
| `ssh` with ControlMaster, or any new control socket | **DISABLE** | binds `~/.ssh/cm-*` socket |
| `mktemp`/`mkdtemp` targeting `/tmp` or `/var` (not `$TMPDIR`) | **DISABLE** | write outside allowlist |
| plain `git status`/`diff`/`log`/`add`/`commit`/`switch`/`checkout` | OK | local `.git` writes are inside `.` |
| `chezmoi execute-template` / `diff` / `cat` | OK | reads + `$TMPDIR` only |
| anything writing only to `$TMPDIR` or `~/.cache/pre-commit` | OK | already allowlisted |

When unsure, run the classifier:

```bash
bash .claude/skills/sandbox-preflight/scripts/classify_command.sh '<the command string>'
# prints:  DISABLE_SANDBOX <reason>   or   SANDBOX_OK local-or-allowlisted
```

## Batching rule

Never co-batch a sandbox-risky call (`gh`/`uv`/networked `git push`/`fetch`/`pull`/`clone`/`ls-remote`) with independent
read-only commands in one parallel tool block. A single sandbox failure reports as
`Cancelled: parallel tool call ... errored` and takes its siblings down with it. Run risky
calls on their own, sandbox disabled.

## Reactive routing (a command already failed)

| Failure signature | Re-run the SAME command with |
|---|---|
| `Failed to initialize cache at ~/.cache/uv` | `dangerouslyDisableSandbox: true` |
| `tls: failed to verify certificate ... OSStatus -26276` | `dangerouslyDisableSandbox: true` |
| `could not write config file .git/config: Operation not permitted` | `dangerouslyDisableSandbox: true` |
| `Control socket connect(... ): Operation not permitted` | `dangerouslyDisableSandbox: true` |
| `PermissionError ... /Users/.../.cache/pre-commit` | already allowlisted — re-apply chezmoi (the pre-seed) or disable sandbox once |

## Structural cure (do this once, not per-command)

The `uv`-cache slice — the largest sub-cluster — can be killed at the source by extending
the same pre-seed that already handles pre-commit. In `dot_claude/modify_settings.json.tmpl`,
add `{{ .chezmoi.homeDir }}/.cache/uv` to the `sandbox.filesystem.allowWrite` merge exactly
as `~/.cache/pre-commit` is added. That removes every `uv`-cache failure without per-command
judgment. The irreducible classes remain (gh `OSStatus -26276` is a keychain cert-path
problem, not a writable-dir problem; `.git/config` and `~/.ssh` writes) — those always need
the flag, which is why this skill stays useful even after the pre-seed.

## When NOT to use this skill

- Plain local git (`status`, `diff`, `log`, `add`, `commit`, `switch`) — sandbox-safe; do
  not reflexively disable the sandbox for everything (that defeats its purpose).
- `chezmoi execute-template` / `chezmoi diff` — reads plus `$TMPDIR`, sandbox-safe. See
  [chezmoi-verify](../chezmoi-verify/SKILL.md).
- Commands writing only to `$TMPDIR` or `~/.cache/pre-commit`.

## Common failure modes

| Symptom | Cause | Action |
|---|---|---|
| `uv`/`ruff`/`pytest` "Operation not permitted (os error 1)" | `~/.cache/uv` not allowlisted | disable sandbox; consider the structural cure |
| `gh` GraphQL/REST TLS error `OSStatus -26276` | sandbox blocks keychain cert verification | disable sandbox for all `gh` |
| `git branch -m` / `push` fails "could not write config file" | `.git/config` write blocked | disable sandbox |
| whole parallel batch `Cancelled` | one risky call co-batched with siblings | split the risky call out, disable its sandbox |

## Reference

- `dot_claude/modify_settings.json.tmpl` — the `allowWrite` pre-seed (currently `~/.cache/pre-commit` only).
- `scripts/classify_command.sh` — deterministic SANDBOX_OK / DISABLE_SANDBOX classifier.
- CLAUDE.md § *Command sandbox* — the prose rule this skill operationalizes.
