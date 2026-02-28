# codax

CLI utility that prints a comprehensive Codex token audit for a session from local `~/.codex/sessions` logs.
The audit includes model-aware estimated USD costs using OpenAI API pricing, with cached-input and reasoning-token handling.

## Setup

```bash
uv sync
```

## Usage

```bash
uv run --project . codax
uv run --project . codax --json
uv run --project . codax --session-file ~/.codex/sessions/2026/02/28/rollout-<id>.jsonl
```

Text and JSON output include token usage plus:

- `model`, `reasoning_effort`, `pricing_model`
- `input_cost_usd`, `cached_input_cost_usd`, `output_cost_usd`, `reasoning_output_cost_usd`
- `session_total_cost_usd`

## Development

```bash
uv run pytest          # run tests
uv run ruff check .    # lint
uv run ruff format .   # format
uv run ty check .      # type check
```

## zsh Wrapper

`dot_config/zsh/dot_zshrc` defines a `codax` shell function that:

1. runs `codex "$@"`
2. prints the token audit for the latest session via this tool (`uv run --project ~/.local/share/chezmoi/codax codax`)
