# codax

CLI utility that prints a comprehensive Codex token audit for a session from local `~/.codex/sessions` logs.

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
