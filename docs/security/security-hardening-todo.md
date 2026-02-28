# Security Hardening TODO (Branch Execution)

## Objectives

- Close high/medium risks from TM-001 through TM-007.
- Keep defaults secure and fail-closed.
- Preserve practical usability for personal multi-machine dotfiles.

## Checklist

- [x] TM-001: Add strict validation gate for master config and generated target configs.
- [x] TM-001/TM-002: Enforce command allowlist and npx package allowlist in sync pipeline.
- [x] TM-002: Pin MCP package versions in `dot_config/mcp/mcp-master.json`.
- [x] TM-004: Add strict merge mode to prune unmanaged Claude MCP servers.
- [x] TM-005: Add Copilot backup integrity hash verification before restoring auth state.
- [x] TM-006: Fail closed on malformed/unreadable master config with explicit non-zero return.
- [x] TM-007: Tighten generated file permissions (`0600`) for synced config artifacts.
- [x] TM-007: Reduce broad shell export blast radius with explicit export allowlist mode.
- [x] TM-003: Add server allowlist mode to isolate risky MCPs by profile at sync time.
- [x] Cross-cutting: Add audit/diff baseline support for server and output drift.
- [x] Cross-machine guardrails: Add versioned pre-commit hook under `.githooks`.

## Operational Follow-ups (still required)

- [ ] Roll out `core.hooksPath=.githooks` on each machine clone.
- [ ] Decide default `DOTFILES_EXPORT_ALL_ENV` posture per machine (secure default is `0`).
- [ ] Adopt per-client approval settings to require confirmation for sensitive tool actions.
- [ ] Add periodic token rotation cadence for high-value credentials.

## Files touched in this branch

- `mcp_sync/src/mcp_sync/sync.py`
- `mcp_sync/src/mcp_sync/cli.py`
- `mcp_sync/src/mcp_sync/__init__.py`
- `mcp_sync/tests/test_sync_mcp_configs.py`
- `dot_config/mcp/mcp-master.json`
- `dot_config/zsh/dot_zshrc`
- `.githooks/pre-commit`
- `docs/security/security-hardening-todo.md`
