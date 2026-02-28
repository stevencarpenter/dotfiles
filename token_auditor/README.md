# token-auditor

CLI utility that prints a token/cost audit for local Codex and Claude sessions.

## Setup

```bash
uv sync
```

## Usage

Canonical command:

```bash
uv run --project . token-auditor
uv run --project . token-auditor --provider codex
uv run --project . token-auditor --provider claude
uv run --project . token-auditor --provider claude --cwd "$PWD"
uv run --project . token-auditor --json
uv run --project . token-auditor --session-file /path/to/session.jsonl
```

Compatibility alias:

```bash
uv run --project . codax
```

Text and JSON output include:

- `provider`, `model`, `reasoning_effort`, `pricing_model`
- `input_tokens`, `cached_input_tokens`, `cache_creation_input_tokens`, `output_tokens`, `reasoning_output_tokens`, `total_tokens`
- `input_cost_usd`, `cached_input_cost_usd`, `cache_creation_input_cost_usd`, `output_cost_usd`, `reasoning_output_cost_usd`, `session_total_cost_usd`

## Development

```bash
uv sync --group dev
uv run python -m pytest  # run tests
uv run ruff check .    # lint
uv run ruff format .   # format
uv run ty check .      # type check
```

### Docstring Standard

- Use verbose Google-style docstrings for classes and functions.
- Include typed `Args:` and `Returns:` sections for callables.
- Include a typed `Raises:` section when exceptions are part of behavior.
- `tests/test_main.py` enforces this for `main.py` and `_logging.py`.

## zsh Wrappers

`dot_config/zsh/dot_zshrc` defines:

1. `codax`: runs `codex "$@"`, then audits latest Codex session via
   `uv run --project ~/.local/share/chezmoi/token_auditor token-auditor --provider codex`
2. `claade`: runs `claude "$@"`, then audits latest Claude session for current workspace via
   `uv run --project ~/.local/share/chezmoi/token_auditor token-auditor --provider claude --cwd "$PWD"`
