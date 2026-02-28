# Repository Guidelines

## Project Structure & Module Organization

This repository is a chezmoi-managed dotfiles source. Top-level `dot_*` and `dot_config/...` paths map to files under `$HOME` when applied.

- `dot_config/`: primary tool configs (zsh, nvim, tmux, mise, mcp, dev-container, yazi).
- `.chezmoiscripts/`: automation hooks run during apply/update.
- `mcp_sync/`: Python package for MCP config synchronization (`src/mcp_sync`, `tests/`).
- `docs/` and `arch/`: setup guides and platform scripts.

## Build, Test, and Development Commands

Use these commands from repo root unless noted:

- `chezmoi diff`: preview changes before applying.
- `chezmoi apply -v`: apply dotfiles and run sync hooks.
- `uv run --project ~/.local/share/chezmoi/mcp_sync sync-mcp-configs`: manual MCP sync.
- `cd mcp_sync && uv run pytest -v`: run Python tests.
- `cd mcp_sync && uv run ruff check src tests`: lint Python code.
- `pre-commit run --all-files`: run repo-wide YAML/TOML/JSON and hygiene checks.

## Coding Style & Naming Conventions

- Python: 4-space indentation, `snake_case` for modules/functions, `PascalCase` for classes.
- Tests: `test_*.py` filenames and `test_*` function names (enforced by pre-commit).
- Chezmoi source naming: keep `dot_` prefixes for managed dotfiles and `encrypted_` for age-encrypted sources.
- Prefer small, focused edits; keep scripts idempotent and safe to re-run.

## Testing Guidelines

- Primary framework: `pytest` (see `mcp_sync/tests/`).
- Add/adjust tests for behavior changes in sync logic, template rendering, or CLI flags.
- Run `uv run pytest -v` before opening a PR; use `-k <pattern>` for targeted checks while iterating.

## Commit & Pull Request Guidelines

History favors Conventional Commit-style prefixes: `feat:`, `fix:`, `chore:`, `docs:`.

- Commit format: `type: short imperative summary` (optionally include PR/issue like `(#12)`).
- Keep commits scoped to one concern.
- PRs should include: purpose, key changed paths, test/lint evidence, and any config/security impact (especially secrets, MCP, or shell startup behavior).
- Include screenshots only when UI/docs rendering changes require visual confirmation.
