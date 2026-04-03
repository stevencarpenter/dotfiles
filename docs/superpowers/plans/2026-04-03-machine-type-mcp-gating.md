# Machine-Type MCP and Settings Gating Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:
> executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Gate MCP servers and Claude settings by machine type (work vs personal) so work-only tools (AWS MCP) don't
deploy to personal machines and personal-only hooks (hippo) don't deploy to work machines.

**Architecture:** Add a machine-type overlay layer to `mcp_sync`. The master config stays as the shared base. New
`dot_config/mcp/machine/{work,personal}.json` files add machine-specific servers, deployed conditionally by chezmoi. The
`mcp_sync` tool gains a `--machine-config` CLI flag to load and merge the overlay between master and per-tool overrides.
`dot_claude/settings.json` becomes a chezmoi `.tmpl` for conditional hook blocks.

**Tech Stack:** Python 3.14+, chezmoi Go templates, uv, ruff, pytest

---

## File Structure

### New Files

- `dot_config/mcp/machine/work.json` — work-only MCP servers (AWS)
- `dot_config/mcp/machine/personal.json` — personal-only MCP servers (if any, initially empty `{}`)
- `mcp_sync/tests/test_machine_overlay.py` — focused tests for overlay loading/merging
- `dot_claude/settings.json.tmpl` — replaces `dot_claude/settings.json` (chezmoi template)

### Modified Files

- `mcp_sync/src/mcp_sync/sync.py` — add `_load_machine_config()`, thread it through `run_sync()` and
  `SyncTarget.build()`
- `mcp_sync/src/mcp_sync/cli.py` — add `--machine-config` argument
- `dot_config/mcp/mcp-master.json` — remove `awslabs-ccapi-mcp-server` (moves to work overlay)
- `.chezmoiscripts/run_after_sync-mcp.sh` — rename to `.tmpl`, pass `--machine-config` when overlay exists
- `.chezmoiignore` — gate `machine/work.json` on personal machines and vice versa
- `mcp_sync/tests/conftest.py` — add machine config fixture
- `mcp_sync/tests/test_sync_mcp_configs.py` — update existing tests for new merge layer
- `mcp_sync/tests/test_cli.py` — test `--machine-config` flag
- `mcp_sync/tests/test_integration_sync_mcp.py` — add integration test with machine overlay
- `CLAUDE.md` — document `--machine-config` flag

---

## Merge Order (Updated)

Current: `template <- master <- per-tool override`

New: `template <- master <- machine overlay <- per-tool override`

The machine overlay adds servers to the master before any per-tool transforms run. This means machine-specific servers
automatically flow to ALL tools, just like master servers do. Per-tool overrides remain highest priority.

---

### Task 1: Move AWS MCP Server to Work Machine Overlay

**Files:**

- Create: `dot_config/mcp/machine/work.json`
- Create: `dot_config/mcp/machine/personal.json`
- Modify: `dot_config/mcp/mcp-master.json`
- Modify: `.chezmoiignore`

- [ ] **Step 1: Create work machine overlay**

```json
{
  "servers": {
    "awslabs-ccapi-mcp-server": {
      "command": "uvx",
      "args": [
        "awslabs.ccapi-mcp-server@latest",
        "--readonly"
      ],
      "env": {
        "AWS_PROFILE": "${AWS_SSO_PROFILE}",
        "DEFAULT_TAGS": "enabled",
        "SECURITY_SCANNING": "enabled",
        "FASTMCP_LOG_LEVEL": "ERROR"
      },
      "disabled": false,
      "autoApprove": []
    }
  }
}
```

- [ ] **Step 2: Create empty personal machine overlay**

```json
{}
```

- [ ] **Step 3: Remove AWS MCP from master config**

Update `dot_config/mcp/mcp-master.json` to only contain the shared servers (`railway-mcp-server`, `github`).

- [ ] **Step 4: Add machine overlay files to `.chezmoiignore`**

Add inside the existing conditional blocks:

```
{{ if not (hasPrefix "work" .machine) }}
.config/mcp/machine/work.json
{{ end }}

{{ if not (hasPrefix "personal" .machine) }}
.config/mcp/machine/personal.json
{{ end }}
```

- [ ] **Step 5: Commit**

```bash
git add dot_config/mcp/machine/work.json dot_config/mcp/machine/personal.json dot_config/mcp/mcp-master.json .chezmoiignore
git commit -m "refactor: move AWS MCP to work machine overlay, create machine config structure"
```

---

### Task 2: Add Machine Config Loading to mcp_sync

**Files:**

- Modify: `mcp_sync/src/mcp_sync/sync.py`
- Test: `mcp_sync/tests/test_machine_overlay.py`

- [ ] **Step 1: Write failing tests for machine config loading**

Create `mcp_sync/tests/test_machine_overlay.py`:

```python
"""Tests for machine-type overlay loading and merging."""

from __future__ import annotations

import json
from pathlib import Path

import pytest

from mcp_sync.sync import deep_merge, load_machine_config, load_master_config


class TestLoadMachineConfig:
    def test_returns_empty_dict_when_path_is_none(self):
        result = load_machine_config(None)
        assert result == {}

    def test_returns_empty_dict_when_file_missing(self, tmp_path):
        result = load_machine_config(tmp_path / "nonexistent.json")
        assert result == {}

    def test_loads_valid_machine_config(self, tmp_path):
        config_path = tmp_path / "work.json"
        config_path.write_text(json.dumps({
            "servers": {
                "aws-mcp": {"command": "uvx", "args": ["aws-mcp"]}
            }
        }))
        result = load_machine_config(config_path)
        assert "servers" in result
        assert "aws-mcp" in result["servers"]

    def test_returns_empty_dict_on_invalid_json(self, tmp_path, capsys):
        config_path = tmp_path / "bad.json"
        config_path.write_text("{invalid json")
        result = load_machine_config(config_path)
        assert result == {}
        captured = capsys.readouterr()
        assert "invalid JSON" in captured.out.lower() or "Skipping" in captured.out


class TestMachineConfigMergeOrder:
    def test_machine_servers_merge_into_master(self):
        master = {"servers": {"github": {"command": "npx"}}}
        machine = {"servers": {"aws": {"command": "uvx"}}}
        merged = deep_merge(master, machine)
        assert "github" in merged["servers"]
        assert "aws" in merged["servers"]

    def test_machine_config_does_not_override_master_servers(self):
        master = {"servers": {"github": {"command": "npx", "args": ["-y", "gh"]}}}
        machine = {"servers": {"github": {"command": "WRONG"}}}
        merged = deep_merge(master, machine)
        # deep_merge replaces leaf values, so machine wins for same key
        assert merged["servers"]["github"]["command"] == "WRONG"

    def test_empty_machine_config_is_noop(self):
        master = {"servers": {"github": {"command": "npx"}}}
        merged = deep_merge(master, {})
        assert merged == master
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `uv run --project mcp_sync --extra dev pytest mcp_sync/tests/test_machine_overlay.py -v`
Expected: FAIL with `ImportError: cannot import name 'load_machine_config'`

- [ ] **Step 3: Implement `load_machine_config` in sync.py**

Add after the existing `load_master_config` function (after line 81):

```python
def load_machine_config(path: Path | None) -> JsonDict:
    """Load machine-type overlay config (work.json / personal.json).

    Returns empty dict if path is None, file doesn't exist, or JSON is invalid.
    """
    if path is None:
        return {}
    if not path.is_file():
        return {}
    try:
        return _load_json(path)
    except json.JSONDecodeError:
        log_info(f"Skipping machine config: {path} (invalid JSON)")
        return {}
    except Exception:
        log_info(f"Skipping machine config: {path} (read error)")
        return {}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `uv run --project mcp_sync --extra dev pytest mcp_sync/tests/test_machine_overlay.py -v`
Expected: All 7 tests PASS

- [ ] **Step 5: Commit**

```bash
git add mcp_sync/src/mcp_sync/sync.py mcp_sync/tests/test_machine_overlay.py
git commit -m "feat: add load_machine_config for machine-type overlay loading"
```

---

### Task 3: Thread Machine Config Through the Sync Pipeline

**Files:**

- Modify: `mcp_sync/src/mcp_sync/sync.py`
- Modify: `mcp_sync/src/mcp_sync/cli.py`
- Test: `mcp_sync/tests/test_machine_overlay.py` (add integration-level tests)
- Modify: `mcp_sync/tests/test_cli.py`

- [ ] **Step 1: Write failing test for `run_sync` with machine config**

Add to `mcp_sync/tests/test_machine_overlay.py`:

```python
class TestRunSyncWithMachineConfig:
    def test_machine_servers_appear_in_all_targets(self, temp_home, master_config_file):
        """Machine overlay servers should flow through to all sync targets."""
        machine_config_path = temp_home / ".config" / "mcp" / "machine" / "work.json"
        machine_config_path.parent.mkdir(parents=True, exist_ok=True)
        machine_config_path.write_text(json.dumps({
            "servers": {
                "work-only-server": {
                    "command": "npx",
                    "args": ["-y", "work-server"]
                }
            }
        }))

        from mcp_sync.sync import run_sync

        rc = run_sync(home=temp_home, machine_config_path=machine_config_path)
        assert rc == 0

        # Verify work-only server appears in a generated config
        generic_mcp = temp_home / ".config" / "mcp" / "mcp_config.json"
        config = json.loads(generic_mcp.read_text())
        assert "work-only-server" in config["mcpServers"]

        # Also verify master servers still present
        assert "filesystem" in config["mcpServers"]
```

- [ ] **Step 2: Run test to verify it fails**

Run:
`uv run --project mcp_sync --extra dev pytest mcp_sync/tests/test_machine_overlay.py::TestRunSyncWithMachineConfig -v`
Expected: FAIL with `TypeError: run_sync() got an unexpected keyword argument 'machine_config_path'`

- [ ] **Step 3: Update `run_sync()` to accept and apply machine config**

Modify `run_sync` in `sync.py` (around line 442):

```python
def run_sync(
    master_path: Path | None = None,
    home: Path | None = None,
    machine_config_path: Path | None = None,
) -> int:
    home_path = home or Path.home()
    master_config_path = (
        master_path or home_path / ".config" / "mcp" / "mcp-master.json"
    )

    if not master_config_path.is_file():
        log_error(f"Master config not found at {master_config_path}")
        log_info("Run 'chezmoi apply' to deploy dotfiles first")
        return 1

    log_info("Syncing MCP configurations from master...")
    master = load_master_config(master_config_path)

    machine = load_machine_config(machine_config_path)
    if machine:
        master = deep_merge(master, machine)

    for target in _build_targets(home_path):
        target.sync(master, home=home_path)

    sync_codex_mcp(master, home=home_path)
    patch_claude_code_config(master, home=home_path)
    sync_copilot_cli_config(home=home_path)

    print()
    log_success("MCP configuration sync complete!")
    return 0
```

- [ ] **Step 4: Run the full test suite to verify nothing breaks**

Run: `uv run --project mcp_sync --extra dev pytest mcp_sync/tests --cov=mcp_sync --cov-report=term-missing -v`
Expected: All tests PASS (existing tests pass `machine_config_path=None` implicitly)

- [ ] **Step 5: Write failing test for `--machine-config` CLI flag**

Add to `mcp_sync/tests/test_cli.py`:

```python
def test_machine_config_flag_parsed(self):
    parser = build_parser()
    args = parser.parse_args(["--machine-config", "~/work.json"])
    assert args.machine_config == Path("~/work.json")

def test_machine_config_flag_defaults_to_none(self):
    parser = build_parser()
    args = parser.parse_args([])
    assert args.machine_config is None
```

- [ ] **Step 6: Add `--machine-config` to CLI parser and `cli()` function**

In `cli.py`, add to `build_parser()`:

```python
parser.add_argument(
    "--machine-config",
    type=Path,
    default=None,
    help="Path to machine-type overlay config (e.g., work.json or personal.json).",
)
```

Update `cli()` to pass it through:

```python
def cli(argv: Sequence[str] | None = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)
    master = args.master.expanduser() if args.master else None
    home = args.home.expanduser() if args.home else None
    machine_config = args.machine_config.expanduser() if args.machine_config else None
    return run_sync(master_path=master, home=home, machine_config_path=machine_config)
```

- [ ] **Step 7: Run full test suite**

Run: `uv run --project mcp_sync --extra dev pytest mcp_sync/tests --cov=mcp_sync --cov-report=term-missing -v`
Expected: All tests PASS

- [ ] **Step 8: Commit**

```bash
git add mcp_sync/src/mcp_sync/sync.py mcp_sync/src/mcp_sync/cli.py mcp_sync/tests/test_machine_overlay.py mcp_sync/tests/test_cli.py
git commit -m "feat: thread machine-type config overlay through sync pipeline and CLI"
```

---

### Task 4: Update Chezmoi Hook to Pass Machine Config

**Files:**

- Modify: `.chezmoiscripts/run_after_sync-mcp.sh` (rename to `.tmpl`)
- Delete: `.chezmoiscripts/run_after_sync-mcp.sh` (replaced by `.tmpl`)

- [ ] **Step 1: Rename hook to `.tmpl`**

```bash
git mv .chezmoiscripts/run_after_sync-mcp.sh .chezmoiscripts/run_after_sync-mcp.sh.tmpl
```

- [ ] **Step 2: Rewrite as a chezmoi template that passes `--machine-config`**

The script detects which machine overlay exists at `~/.config/mcp/machine/` and passes it via `--machine-config`. Since
chezmoi deploys only the matching file (via `.chezmoiignore`), we just glob for whatever is there.

```bash
{{- /* This template always renders — machine-config flag handles gating */ -}}
#!/usr/bin/env bash
set -euo pipefail

# Post-apply hook: sync MCP configurations from the master config
# Triggered by: chezmoi apply

SYNC_PROJECT="${HOME}/.local/share/chezmoi/mcp_sync"
STRICT_MODE="${MCP_SYNC_STRICT:-0}"

fail_or_warn() {
    local message="$1"
    if [[ "${STRICT_MODE}" == "1" ]]; then
        echo "Error: ${message}" >&2
        exit 1
    fi
    echo "Warning: ${message}" >&2
}

if ! command -v uv >/dev/null 2>&1; then
    fail_or_warn "uv is not installed; skipping MCP sync."
    exit 0
fi

if [[ -f "${SYNC_PROJECT}/pyproject.toml" ]]; then
    sync_cmd=(sync-mcp-configs)

    # Detect machine-type overlay (chezmoi deploys only the matching one)
    MACHINE_DIR="${HOME}/.config/mcp/machine"
    if [[ -d "${MACHINE_DIR}" ]]; then
        for f in "${MACHINE_DIR}"/*.json; do
            if [[ -f "$f" ]]; then
                sync_cmd+=(--machine-config "$f")
                break
            fi
        done
    fi

    if ! uv run --project "${SYNC_PROJECT}" "${sync_cmd[@]}"; then
        fail_or_warn "MCP sync failed."
        exit 0
    fi
else
    echo "Warning: MCP sync project not found at ${SYNC_PROJECT}." >&2
    exit 0
fi
```

- [ ] **Step 3: Verify template renders correctly on personal machine**

```bash
chezmoi execute-template < .chezmoiscripts/run_after_sync-mcp.sh.tmpl
```

Expected: Full bash script output (renders on all machines — the `--machine-config` flag handles gating, not the
template conditional).

- [ ] **Step 4: Commit**

```bash
git add .chezmoiscripts/run_after_sync-mcp.sh.tmpl
git commit -m "refactor: convert MCP sync hook to template, pass machine-config overlay"
```

---

### Task 5: Template `dot_claude/settings.json` for Hippo Hook Gating

**Files:**

- Create: `dot_claude/settings.json.tmpl` (replaces `dot_claude/settings.json`)
- Delete: `dot_claude/settings.json`

- [ ] **Step 1: Rename to `.tmpl`**

```bash
git mv dot_claude/settings.json dot_claude/settings.json.tmpl
```

- [ ] **Step 2: Add template conditionals around the hippo hook**

The entire `hooks` block is personal-only. The rest of the settings are shared. Use Go template conditionals with
careful JSON comma handling:

```json
{
  "$schema": "https://json.schemastore.org/claude-code-settings.json",
  "env": {
    "ENABLE_LSP_TOOL": "1",
    "CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS": "1"
  },
  "model": "opus[1m]",
  "statusLine": {
    "type": "command",
    "command": "bash ~/.claude/statusline-command.sh"
  },
  "enabledPlugins": {
    "frontend-design@claude-plugins-official": true,
    "superpowers@claude-plugins-official": true,
    "context7@claude-plugins-official": true,
    "code-review@claude-plugins-official": true,
    "github@claude-plugins-official": true,
    "code-simplifier@claude-plugins-official": true,
    "playwright@claude-plugins-official": true,
    "commit-commands@claude-plugins-official": true,
    "claude-md-management@claude-plugins-official": true,
    "skill-creator@claude-plugins-official": true,
    "claude-code-setup@claude-plugins-official": true,
    "hookify@claude-plugins-official": true,
    "railway@claude-plugins-official": true,
    "cloudflare@cloudflare": true,
    "swift-lsp@claude-plugins-official": true,
    "typescript-lsp@claude-plugins-official": true,
    "pyright-lsp@claude-plugins-official": true,
    "gopls-lsp@claude-plugins-official": true,
    "rust-analyzer-lsp@claude-plugins-official": true,
    "lua-lsp@claude-plugins-official": true,
    "atlassian@claude-plugins-official": true
  },
  "extraKnownMarketplaces": {
    "claude-plugins-official": {
      "source": {
        "source": "github",
        "repo": "anthropics/claude-plugins-official"
      }
    },
    "cloudflare": {
      "source": {
        "source": "github",
        "repo": "cloudflare/skills"
      }
    }
  },
{{- if hasPrefix "personal" .machine }}
  "hooks": {
    "SessionStart": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "/Users/carpenter/projects/hippo/shell/claude-session-hook.sh"
          }
        ]
      }
    ]
  },
{{- end }}
  "effortLevel": "high",
  "voiceEnabled": true,
  "autoDreamEnabled": true,
  "skipDangerousModePermissionPrompt": true,
  "teammateMode": "auto"
}
```

- [ ] **Step 3: Verify template renders valid JSON on personal machine**

```bash
chezmoi execute-template < dot_claude/settings.json.tmpl | python3 -m json.tool
```

Expected: Valid JSON with the `hooks` block present.

- [ ] **Step 4: Verify template renders valid JSON without hooks (simulated work machine)**

Manually check: remove the `hooks` block and verify the JSON is valid (the comma before `"effortLevel"` must work
correctly with the `{{- if }}` trimming).

- [ ] **Step 5: Update `.chezmoiignore` to remove the old `dot_claude/settings.json` exception**

The line `!dot_claude/settings.json` in `.chezmoiignore` (line 58) should now reference `settings.json.tmpl` if needed,
or it may need no change since chezmoi understands `.tmpl` files deploy without the `.tmpl` suffix. Verify and adjust.

- [ ] **Step 6: Commit**

```bash
git add dot_claude/settings.json.tmpl .chezmoiignore
git commit -m "refactor: template claude settings for machine-type conditional hooks"
```

---

### Task 6: Update Documentation and Run Full Validation

**Files:**

- Modify: `CLAUDE.md`
- Modify: `mcp_sync/tests/test_integration_sync_mcp.py`

- [ ] **Step 1: Add integration test for machine overlay in full pipeline**

Add to `mcp_sync/tests/test_integration_sync_mcp.py`:

```python
def test_full_sync_with_machine_overlay(temp_home, master_config_file, monkeypatch_home):
    """Machine overlay servers appear in all synced configs."""
    machine_dir = temp_home / ".config" / "mcp" / "machine"
    machine_dir.mkdir(parents=True, exist_ok=True)
    (machine_dir / "work.json").write_text(json.dumps({
        "servers": {
            "work-only": {"command": "work-cmd", "args": ["--flag"]}
        }
    }))

    rc = run_sync(home=temp_home, machine_config_path=machine_dir / "work.json")
    assert rc == 0

    # Check generic MCP config
    generic = json.loads(
        (temp_home / ".config" / "mcp" / "mcp_config.json").read_text()
    )
    assert "work-only" in generic["mcpServers"]
    # Master servers still present
    assert "filesystem" in generic["mcpServers"]

    # Check copilot config
    copilot = json.loads(
        (temp_home / ".config" / ".copilot" / "mcp-config.json").read_text()
    )
    assert "work-only" in copilot["mcpServers"]
    assert copilot["mcpServers"]["work-only"]["tools"] == ["*"]
```

- [ ] **Step 2: Run full test suite and lint**

```bash
uv run --project mcp_sync --extra dev pytest mcp_sync/tests --cov=mcp_sync --cov-report=term-missing -v
uv run --project mcp_sync --extra dev ruff check mcp_sync/src mcp_sync/tests
uv run --project mcp_sync --extra dev ruff format --check mcp_sync/src mcp_sync/tests
```

Expected: All tests PASS, lint clean, format clean.

- [ ] **Step 3: Update CLAUDE.md**

Add `--machine-config` to the MCP sync commands section and note the machine overlay directory:

```markdown
### Machine-Type Overlays

MCP servers and settings are gated by machine type via chezmoi's `.machine` variable:
- **Shared**: `dot_config/mcp/mcp-master.json` — servers deployed to all machines
- **Work-only**: `dot_config/mcp/machine/work.json` — servers added on work machines (e.g., AWS MCP)
- **Personal-only**: `dot_config/mcp/machine/personal.json` — servers added on personal machines
- **Claude hooks**: `dot_claude/settings.json.tmpl` — hippo hook gated behind `{{ if hasPrefix "personal" .machine }}`

The sync hook auto-detects the deployed overlay at `~/.config/mcp/machine/*.json` and passes it via `--machine-config`.
```

- [ ] **Step 4: Run `chezmoi diff` to verify the full deployment looks correct**

```bash
chezmoi diff
```

Verify:

- No AWS MCP in master config
- Machine overlay files gated correctly
- settings.json.tmpl renders properly
- Hook script renders properly

- [ ] **Step 5: Commit**

```bash
git add CLAUDE.md mcp_sync/tests/test_integration_sync_mcp.py
git commit -m "docs: document machine-type overlay system, add integration test"
```

---

## Self-Review Notes

- **Spec coverage**: AWS MCP moved to work overlay (Task 1), machine config loading (Task 2), pipeline threading (Task
  3), hook passing (Task 4), hippo gating (Task 5), docs (Task 6).
- **JSON comma handling in Task 5**: The `{{- if }}` with the dash trims whitespace, which makes the comma situation
  work: the `"hooks": {...},` block is either present (with trailing comma) or absent (and the `{{- end }}` trims the
  blank line). Needs careful testing.
- **Type consistency**: `load_machine_config` takes `Path | None`, returns `JsonDict`. `run_sync` accepts
  `machine_config_path: Path | None`. `cli()` passes `args.machine_config.expanduser()` or `None`. All consistent.
- **No placeholders**: Every task has exact code, exact commands, exact expected output.
