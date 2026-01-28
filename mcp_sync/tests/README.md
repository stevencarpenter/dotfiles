# MCP Sync Configuration Tests

This directory contains comprehensive tests for the `mcp_sync` CLI, which syncs MCP configuration files.

## Test Structure

- **`conftest.py`** - Pytest fixtures and shared test configuration
- **`test_sync_mcp_configs.py`** - Unit tests for individual functions
- **`test_integration_sync_mcp.py`** - Integration tests for complete workflows
- **`test_data/`** - Sample configuration files for testing

## Running Tests

### Prerequisites

Install test dependencies:

```bash
uv pip install pytest pytest-cov
```

### Run All Tests

```bash
# Run all tests with verbose output
uv run pytest tests/ -v

# Run with coverage report
uv run pytest tests/ -v --cov=mcp_sync --cov-report=html
```

### uv helper commands

- Run the sync tool via the uv project entrypoint:

  ```bash
  uv run sync-mcp-configs
  ```

- Lint and format Python sources:

  ```bash
uv run ruff check mcp_sync tests
  ```

### Run Specific Test Suites

```bash
# Unit tests only
uv run pytest tests/test_sync_mcp_configs.py -v

# Integration tests only
uv run pytest tests/test_integration_sync_mcp.py -v

# Specific test
uv run pytest tests/test_sync_mcp_configs.py::test_load_master_config_valid -v
```

### Run with Markers

```bash
# Run only tests matching a pattern
uv run pytest tests/ -k "serena" -v

# Run tests excluding a pattern
uv run pytest tests/ -k "not opencode" -v
```

## Test Coverage

### Unit Tests (`test_sync_mcp_configs.py`)

Tests individual functions in isolation:

- **Config Loading**
  - `test_load_master_config_valid` - Valid config file loading
  - `test_load_master_config_missing` - Missing file error handling
  - `test_load_master_config_malformed_json` - JSON parsing errors

- **Format Transformations**
  - `test_transform_to_copilot_format` - GitHub Copilot format
  - `test_transform_to_generic_mcp_format` - Generic MCP standard format
  - `test_transform_to_mcpservers_format` - mcpServers format
  - `test_transform_to_opencode_format` - OpenCode format with env vars

- **Serena Context Handling**
  - `test_set_serena_context_servers_format` - servers format context injection
  - `test_set_serena_context_mcp_servers_format` - mcpServers format context
  - `test_set_serena_context_opencode_format` - OpenCode format context
  - `test_set_serena_context_replaces_existing` - Context replacement logic
  - `test_set_serena_context_missing_serena` - Missing Serena handling

- **File Operations**
  - `test_sync_to_locations_creates_parent_dirs` - Directory creation
  - `test_sync_to_locations_with_legacy` - Legacy path mirroring
  - `test_ensure_codex_serena_server_creates_section` - TOML section creation
  - `test_ensure_codex_serena_server_updates_existing` - TOML section updates

- **Claude Code Integration**
  - `test_patch_claude_code_config_missing` - Missing config handling
  - `test_patch_claude_code_config_merges_servers` - MCP server merging
  - `test_patch_claude_code_config_sets_serena_context` - Serena context setting

- **Edge Cases**
  - `test_empty_master_config_handling` - Empty servers handling
  - `test_none_servers_handling` - Null servers handling
  - `test_edge_case_special_chars_in_args` - Special character preservation

### Integration Tests (`test_integration_sync_mcp.py`)

Tests the complete workflow and interactions:

- **Full Workflow**
  - `test_full_sync_workflow_all_targets` - All targets created and valid
  - `test_full_sync_missing_master_config` - Graceful failure handling

- **Format Validation**
  - `test_full_sync_copilot_format_has_tools_array` - Copilot has tools array
  - `test_full_sync_generic_mcp_has_schema` - Generic MCP has schema field

- **Context Assignment**
  - `test_full_sync_ide_context_applied` - IDE tools get IDE context
  - `test_junie_gets_agent_context` - Junie gets agent context
  - `test_lmstudio_gets_desktop_context` - LM Studio gets desktop context

- **Legacy Support**
  - `test_full_sync_cursor_legacy_mirror` - Cursor legacy mirroring

- **Environment Variables**
  - `test_full_sync_env_vars_preserved` - Env vars preserved in all formats

- **Existing Config Handling**
  - `test_sync_with_existing_claude_config` - Claude config merging
  - `test_sync_with_existing_opencode_config` - OpenCode config updates
  - `test_sync_with_codex_config` - Codex config creation

- **Idempotency**
  - `test_sync_idempotency` - Multiple runs produce identical results

## Test Fixtures

Available fixtures in `conftest.py`:

- **`temp_home`** - Temporary home directory for isolated testing
- **`master_config`** - Sample master MCP configuration dict
- **`master_config_file`** - Master config file in temp home
- **`claude_config_template`** - Sample Claude Code config
- **`opencode_config_template`** - Sample OpenCode config
- **`monkeypatch_home`** - Monkeypatch that replaces `Path.home()`

## Test Data

Sample configuration files in `test_data/`:

- **`sample_master_config.json`** - Full master configuration example
- **`malformed_json.json`** - Invalid JSON for error testing
- **`codex_config_before.toml`** - Codex config before Serena sync
- **`claude_config_sample.json`** - Claude Code config example
- **`opencode_config_sample.json`** - OpenCode config example

## Debugging Tests

### Verbose Output

```bash
uv run pytest tests/ -vv --tb=long
```

### Stop on First Failure

```bash
uv run pytest tests/ -x
```

### Drop into Debugger on Failure

```bash
uv run pytest tests/ --pdb
```

### Run Single Test with Print Statements

```bash
# Print statements are captured by default, use -s to see them
uv run pytest tests/test_sync_mcp_configs.py::test_load_master_config_valid -s
```

## Coverage Goals

Current coverage targets:
- **Line Coverage**: >90%
- **Branch Coverage**: >85%

View HTML coverage report:

```bash
uv run pytest tests/ --cov=mcp_sync --cov-report=html
open htmlcov/index.html
```

## Known Limitations

1. **Import Strategy**: Tests import the `mcp_sync` package directly, which is simple because the project root is available to pytest.

2. **Mocking**: Tests use `monkeypatch` from pytest and temporary directories to avoid filesystem side effects.

3. **File I/O**: All file operations are performed in temporary directories to ensure test isolation.

## Contributing New Tests

When adding new tests:

1. Decide if it's a unit test (single function) or integration test (multiple functions)
2. Use appropriate fixtures from `conftest.py` or create new ones
3. Use temporary directories via `temp_home` fixture
4. Mock `Path.home()` with `monkeypatch_home` for filesystem operations
5. Add descriptive docstrings explaining what and why you're testing
6. Verify the test fails without the feature it tests
7. Keep tests focused on one behavior per test

## Continuous Integration

These tests are designed to run in CI/CD pipelines:

```bash
# In CI environment
uv run pytest tests/ -v --tb=short --junit-xml=test-results.xml
```

## Related Documentation

- Main module: `mcp_sync`
- CLI entrypoint: `sync-mcp-configs`
- MCP setup: `docs/ai-tools/serena-mcp-setup.md`
- CLAUDE.md: Project guidelines and architecture
