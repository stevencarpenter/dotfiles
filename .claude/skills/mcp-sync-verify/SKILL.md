---
name: mcp-sync-verify
description: Verify the dotfiles MCP sync pipeline is healthy after editing master/overlay/override configs or sync code. USE THIS SKILL whenever the user edits anything under `home/.config/mcp/` (mcp-master.json, machine/work.json, machine/personal.json, machine/lab.json, overrides/*.json, templates), edits anything under `mcp_sync/` (sync.py, cli.py, templates/*.base.json|.toml, tests), or asks any of "sync MCP configs", "verify MCP", "did the MCP sync break", "did mcp-master change anything", "what changed in opencode/cursor/claude.json", "preview the MCP fan-out", "dry run mcp_sync", "I edited mcp/machine/*.json — does it still apply cleanly", "is codex/cursor/junie/lmstudio still in sync". Bias toward triggering after edits to the MCP source-of-truth files even if the user does not explicitly ask — this skill never writes to deployed paths, so the cost of an unnecessary trigger is one tmpdir.
---

# MCP sync verify

Lint, test, and dry-run the `mcp_sync` pipeline against a sandbox HOME, then diff the
generated tool configs against the currently-deployed copies. Surfaces drift introduced
by edits to `home/.config/mcp/mcp-master.json`, machine overlays, per-tool overrides,
templates, or `mcp_sync/src/`.

Read the repo CLAUDE.md for the full master → machine → override merge order before
fixing anything this skill flags.

## Run order

Run from the repo root (`/Users/carpenter/.dotfiles`). All commands are
non-destructive — none of them write to `~/.codex/`, `~/.claude.json`, `~/.cursor/`, etc.

### 1. Lint

```bash
uv run --project mcp_sync --group dev ruff check mcp_sync/src mcp_sync/tests
uv run --project mcp_sync --group dev ruff format --check mcp_sync/src mcp_sync/tests
```

If formatting fails, run `ruff format mcp_sync/src mcp_sync/tests` and re-check.

### 2. Test

```bash
uv run --project mcp_sync --group dev pytest mcp_sync/tests --cov=mcp_sync --cov-report=term-missing
```

The test suite covers transform functions, deep-merge, override loading, and
per-tool format expectations. A failure here means the dry-run below is meaningless —
fix the test first.

### 3. List the deployment targets (sanity check before diffing)

```bash
.claude/skills/mcp-sync-verify/scripts/list_targets.py
```

Targets come from `mcp_sync.sync.sync_destinations`: `_build_targets` (wholesale
files, including Copilot CLI at `~/.copilot/mcp-config.json`) plus the Codex TOML
patch plus `patch_specs` (`~/.claude.json`). This list will not go stale when a
target is added in `sync.py`.

### 4. Dry-run + diff

`mcp_sync` has **no `--dry-run` flag** (see `mcp_sync/src/mcp_sync/cli.py`). The
sandbox approach below redirects all writes via `--home <tmpdir>`:

```bash
bash .claude/skills/mcp-sync-verify/scripts/dry_run_diff.sh
```

What the script does:

1. `mktemp -d` a sandbox HOME.
2. Seed the sandbox with `home/.config/mcp/mcp-master.json` + `home/.config/mcp/overrides/*`
   from the repo (so `_load_override` finds them).
3. Auto-detect the deployed machine overlay at `~/.config/mcp/machine/*.json` and pass
   it via `--machine-config` (matching what the `mcpSync` activation hook in
   `modules/home/sync-hooks.nix` does at rebuild time). Override by passing a path: `bash .../dry_run_diff.sh /path/to/overlay.json`.
4. Mirror in-place patch targets (`~/.claude.json`, `~/.codex/config.toml`) into the
   sandbox so the patchers have something to rewrite.
5. Run `uv run --project mcp_sync sync-mcp-configs --home "$SANDBOX" --machine-config ...`.
6. `diff -u` every generated path against the deployed copy under `$HOME`.

A clean run prints `==> All deployed configs match what mcp_sync would generate.`
Any diff output is what would change at the next `just mcp-sync` / rebuild.

### 5. (Optional) Apply for real

Only after the diff looks correct:

```bash
just mcp-sync
```

(Or `just rebuild` — the `mcpSync` activation hook in `modules/home/sync-hooks.nix`
re-runs `sync-mcp-configs` against the real `$HOME` after every switch.)

## Reading the diff output

- **`+++ (path) only in sandbox, not yet deployed`** — a new tool target was added or the
  destination doesn't exist on this machine yet. Expected when adding a tool template.
- **`--- (path) only deployed, not regenerated`** — the tool isn't in `_build_targets`
  on this run (e.g., capability-gated or removed). Verify intent.
- **JSON diff in `mcpServers`/`mcp`/`servers`** — the user's master/overlay/override
  edit propagated. Confirm it matches intent.
- **Diff inside `~/.claude.json` outside `mcpServers`** — should be empty; the patcher
  only touches `mcpServers`. If other keys differ, investigate `patch_claude_code_config`.
- **`environment` vs `env`** — opencode uses `environment`; everywhere else is `env`.
  Format-shaping is in `transform_to_opencode_format`.

## Common drift sources

- Forgot to set `enabled: false` on a server you wanted gated to one machine. Use the
  machine overlay (`home/.config/mcp/machine/{work,personal,lab}.json`) instead of editing
  the master.
- Added a server with both `command` and `url` — `transform_to_opencode_format` and
  `_render_codex_mcp_section` prefer `url` and silently drop `command`. Pick one.
- Edited a `.base.json` template and broke shape for a single tool (e.g., dropped the
  `$schema` key). Re-run pytest — the per-tool transform tests catch this.
- Added a `disabled: true` field from a foreign schema — `_is_server_enabled` honors
  it, but `enabled` always wins on collision. See the docstring in `sync.py`.

## Not for

- Editing the actual MCP master config — this skill is a *verifier*. To add a server,
  edit `home/.config/mcp/mcp-master.json` (or the appropriate machine overlay) and then
  run this skill.
- Authoring new tool templates — this skill diffs against existing targets; adding a
  new `SyncTarget` requires a code change in `mcp_sync/src/mcp_sync/sync.py`.
- Verifying that the deployed configs are *correct* in the eyes of each downstream
  tool — this skill only verifies that what `mcp_sync` would emit matches what is
  currently on disk. To confirm a tool actually picks up its config, launch the tool.

## Reference files

- `.claude/skills/mcp-sync-verify/scripts/list_targets.py` — print all deployment paths via `sync_destinations`.
- `.claude/skills/mcp-sync-verify/scripts/print_target_paths.py` — same set, one path per line.
- `.claude/skills/mcp-sync-verify/scripts/dry_run_diff.sh` — sandbox sync + per-target diff.
