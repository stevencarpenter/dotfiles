# token-auditor

CLI utility that prints token and cost audits for local Codex and Claude sessions.

## Setup

```bash
uv sync
```

## CLI Usage

Canonical entrypoint:

```bash
uv run --project . token-auditor
```

Compatibility alias (same behavior):

```bash
uv run --project . codax
```

Common examples:

```bash
uv run --project . token-auditor --provider codex
uv run --project . token-auditor --provider claude
uv run --project . token-auditor --provider claude --cwd "$PWD"
uv run --project . token-auditor --session-file /path/to/session.jsonl
uv run --project . token-auditor --json
```

Supported flags:

- `--provider {codex,claude}`: provider to audit (default: `codex`).
- `--codex-home`: Codex home for session discovery (default: `~/.codex`).
- `--claude-home`: Claude home for session discovery (default: `~/.claude`).
- `--cwd`: workspace path used for Claude project-scoped lookup (default: current working directory).
- `--session-file`: explicit JSONL file path override. When present, discovery is skipped.
- `--json`: emit machine-readable JSON output instead of text.
- `--log-level`: logging verbosity (`DEBUG`, `INFO`, `WARNING`, `ERROR`, `CRITICAL`).

## Session Discovery

- Codex defaults to latest `~/.codex/sessions/*/*/*/rollout-*.jsonl`.
- Claude defaults to latest project-scoped file first:
  `~/.claude/projects/<cwd-slug>/*.jsonl`.
- If no Claude project-scoped file exists, it falls back to latest
  `~/.claude/projects/*/*.jsonl`.

## Output Schema

Text and JSON output include:

- Identity: `provider`, `session_id`, `session_file`, `timestamp`, `model`, `pricing_model`, `reasoning_effort`.
- Token counts (integer tokens): `input_tokens`, `cached_input_tokens`, `cache_creation_input_tokens`, `output_tokens`, `reasoning_output_tokens`,
  `total_tokens`.
- Costs (USD): `input_cost_usd`, `cached_input_cost_usd`, `cache_creation_input_cost_usd`, `output_cost_usd`, `reasoning_output_cost_usd`,
  `session_total_cost_usd`.

Codex token semantics:

- In Codex session logs, `input_tokens` already includes cached tokens.
- `cached_input_tokens` is a subset of `input_tokens`.
- Billable uncached input for pricing is calculated as:
  `input_tokens - cached_input_tokens - cache_creation_input_tokens`.
- Codex CLI's inline footer can show a smaller `total` because it commonly reports `uncached_input + output`, while this auditor reports the session usage
  values from the log.

## Architecture

`token_auditor` follows a pure-core/impure-shell split:

- `core/`: pure parsing, reduction, pricing, rendering, and session-selection logic.
- `shell/`: filesystem, environment, and terminal capability adapters only.
- `main.py`: thin CLI orchestration plus compatibility wrappers:
  `parse_codex_session_usage`, `parse_claude_session_usage`, and `main`.

This keeps side effects at process boundaries while preserving the existing CLI and output contract.

## Color Output

Text output supports an Everforest-inspired ANSI palette.

- `TOKEN_AUDITOR_COLOR=auto` (default): color only when stdout is a TTY.
- `TOKEN_AUDITOR_COLOR=always`: force color output.
- `TOKEN_AUDITOR_COLOR=never`: disable color output.
- `NO_COLOR` also disables color output.

## zsh Wrappers

`dot_config/zsh/dot_zshrc` defines:

- `codax`: runs `codex "$@"`, then runs:
  `uv run --project ~/.local/share/chezmoi/token_auditor token-auditor --provider codex`
- `claade`: runs `claude "$@"`, then runs:
  `uv run --project ~/.local/share/chezmoi/token_auditor token-auditor --provider claude --cwd "$PWD"`
- The `claade` function name is intentional to mirror `codax` naming and avoid clobbering the `claude` command name.
- Both wrappers preserve the original `codex`/`claude` exit code and print a warning if audit invocation fails.

## Development

```bash
uv sync --group dev
uv run pytest -v
uv run ruff check .
uv run ruff format .
uv run ty check .
```

### Docstring Standard

- Use verbose Google-style docstrings for classes and functions.
- Include typed `Args:` and `Returns:` sections for callables.
- Include a typed `Raises:` section when exceptions are part of behavior.
- `tests/test_main.py` enforces this for `main.py` and `_logging.py`.
