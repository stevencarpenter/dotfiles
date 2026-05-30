---
name: uv-tool-loop
description: Run the correct per-tool uv lint/type-check/test loop for the 3 vendored Python tools on the first try, and guard that tests never write real machine state. USE THIS SKILL whenever you edit or test a file under `token_auditor/`, `mcp_sync/`, or `aws_config_gen/`; whenever you need to lint/type-check/test a vendored tool before opening a PR; whenever you hit "ModuleNotFoundError: No module named mcp_sync.skills", "ImportError: cannot import ..." in a just-added test, "I001 Import block is un-sorted" on a test file, or "No module named toml" (system python, not the venv); whenever the user asks "run the tests for the python tools", "which uv invocation does this tool use", "token_auditor coverage", or says "the tests wrote a real config file". Bias toward triggering on edits to these three trees: each tool has a DIFFERENT invocation (token_auditor: `cd token_auditor && uv sync --locked --group dev` then `uv run ty check . && uv run pytest` at a 100%-coverage gate; mcp_sync / aws_config_gen: `uv run --project <tool> --group dev <cmd>`, NO ty step, NO coverage gate). Enforce TDD ordering (create+export the module symbol BEFORE importing it in tests), run `ruff check --fix && ruff format` on new files BEFORE pytest, and assert tool tests use tmp_path / monkeypatched HOME and NEVER touch real `~/.aws` or other live `$HOME` state. All uv calls run with the sandbox disabled (see sandbox-preflight).
---

# uv tool loop

Three uv projects ride along in this repo and they do **not** share an invocation. Run the
right lint/type/test sequence for the tool you touched, in the right order, with tests
isolated from real machine state.

## Why this skill exists

CLAUDE.md lists the commands, yet sessions still (a) used the wrong invocation form, (b) ran
**system python** (`python -c 'import toml'` → `No module named toml`), (c) imported a symbol
before the module exported it (`ModuleNotFoundError: No module named mcp_sync.skills`, four
collection errors), (d) tripped `I001 Import block is un-sorted` on a just-written test, and
— most damaging — (e) wrote a **real `~/.aws/config`** with duplicate prod profiles from a
test (*"if the tests are creating real config files that is a massive problem"*). The facts
are documented but not converting to first-try behavior; this skill makes the per-tool recipe
and the isolation guard explicit.

> `mcp-sync-verify` covers the mcp_sync **fan-out pipeline** (sandbox-HOME dry-run + diff).
> This skill covers the **dev loop** (lint/type/test) for all three tools. Different jobs.

## The recipe (per tool)

Print the exact sequence for a changed path:

```bash
bash .claude/skills/uv-tool-loop/scripts/tool_ci.sh <path-under-a-tool>
```

| Tool | Invocation | ty? | coverage gate |
|---|---|:---:|---|
| `token_auditor` | `cd token_auditor && uv sync --locked --group dev`, then `uv run ruff check .` / `uv run ruff format --check .` / `uv run ty check .` / `uv run pytest -v` | **yes** | **100% required** |
| `mcp_sync` | `uv run --project mcp_sync --group dev ruff check mcp_sync/src mcp_sync/tests` / `uv run --project mcp_sync --group dev ruff format --check mcp_sync/src mcp_sync/tests` / `uv run --project mcp_sync --group dev pytest mcp_sync/tests --cov=mcp_sync --cov-report=term-missing` | no | report only |
| `aws_config_gen` | `uv run --project aws_config_gen --group dev ruff check aws_config_gen/src aws_config_gen/tests` / `uv run --project aws_config_gen --group dev ruff format --check aws_config_gen/src aws_config_gen/tests` / `uv run --project aws_config_gen --group dev pytest aws_config_gen/tests --cov=aws_config_gen --cov-report=term-missing` | no | report only |

All `uv` calls write `~/.cache/uv`, which the sandbox blocks — run them with
`dangerouslyDisableSandbox: true` (see [sandbox-preflight](../sandbox-preflight/SKILL.md)).
Note the dependency group is `--group dev` (PEP 735), **not** the older `--extra dev`.

## Ordering rules that prevent the recurring errors

1. **Module before import.** Create *and export* the symbol (in `__init__.py` / the module)
   before a test imports it, or pytest collection fails before a single test runs.
2. **Lint-fix before test.** Run `ruff check --fix && ruff format` on new/edited files
   *before* `pytest`, so `I001` import-sort never fails the run.
3. **Never system python.** `python -c ...` resolves the wrong interpreter (no deps). Run
   module checks via `uv run` inside the project, or rely on the `claade` wrapper's venv.

## Test-isolation guard (the `~/.aws` incident)

Tool tests must write only to `tmp_path` / a monkeypatched `HOME` — **never** real
`~/.aws`, `~/.config`, or other live `$HOME` state. Lint for violations:

```bash
bash .claude/skills/uv-tool-loop/scripts/assert_no_home_writes.sh
# flags test files that reference Path.home()/expanduser/~/.aws without tmp_path or monkeypatch
```

## When NOT to use this skill

- The mcp_sync **fan-out** verification (generated per-tool configs, sandbox-HOME diff) —
  use [mcp-sync-verify](../mcp-sync-verify/SKILL.md).
- Generic Python work outside these three trees — use the language-agnostic `tdd` skill.
- Authoring a brand-new tool/`SyncTarget` — that's a code change, not this loop.

## Common failure modes

| Error | Cause | Action |
|---|---|---|
| `ModuleNotFoundError: No module named mcp_sync.skills` | test imports a symbol the module doesn't export yet | export it first (module-before-import) |
| `I001 Import block is un-sorted` | ran pytest before ruff | `ruff check --fix && ruff format` then re-run |
| `No module named toml` | used system python | run via `uv run` inside the project |
| tests wrote real `~/.aws/config` | missing `tmp_path`/`monkeypatch` HOME | fix the test; run `assert_no_home_writes.sh` |
| `Failed to initialize cache at ~/.cache/uv` | sandbox | disable sandbox (sandbox-preflight) |

## Reference

- `scripts/tool_ci.sh` — print the exact CI command sequence for a changed path.
- `scripts/assert_no_home_writes.sh` — authoring lint for tests touching real `$HOME`.
- CLAUDE.md § *Commands* — the canonical per-tool invocations this skill encodes.
