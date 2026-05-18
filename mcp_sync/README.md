# MCP Sync

Modern, uv-native MCP configuration sync tool for keeping MCP server configs aligned across supported clients.

## Requirements

- Python 3.14+
- `uv`

## Usage

Run the sync using the uv entrypoint:

```bash
uv run sync-mcp-configs
```

Or run as a module:

```bash
python -m mcp_sync
```

Optional overrides:

```bash
uv run sync-mcp-configs --master /path/to/mcp-master.json --home /tmp/home
```

## What it syncs

- Copilot (xdg + IntelliJ)
- Cursor (xdg + legacy mirror)
- VS Code (xdg + legacy mirror)
- Junie
- LM Studio
- Codex CLI
- Claude Code
- OpenCode

## Enabling/Disabling Servers

You can enable or disable MCP servers by adding an `enabled` field to any server configuration:

```json
{
  "servers": {
    "active-server": {
      "command": "node",
      "args": ["server.js"],
      "enabled": true
    },
    "disabled-server": {
      "command": "node",
      "args": ["disabled.js"],
      "enabled": false
    },
    "default-enabled": {
      "command": "node",
      "args": ["default.js"]
    }
  }
}
```

**Behavior:**
- Servers with `enabled: true` are included in all synced configs
- Servers with `enabled: false` are excluded from all synced configs
- Servers without an `enabled` field default to enabled (backward compatible)

This works in all config files:
- Master config (`~/.config/mcp/mcp-master.json`)
- Machine overlays (`~/.config/mcp/machine/{work,personal}.json`)
- Per-tool overrides (`~/.config/mcp/overrides/<tool>.json`)

Machine overlays can disable servers from the master config:

```json
{
  "servers": {
    "some-master-server": {
      "enabled": false
    }
  }
}
```

See `examples/enabled-flag-example.json` for a complete example.

## Overrides

Add per-tool overrides under `~/.config/mcp/overrides/<tool>.json`.
Overrides are deep-merged after the base template and generated MCP config.

List append syntax: use a `+` suffix on a key to append unique items:

```json
{
  "enabledPlugins+": {
    "my-plugin@source": true
  }
}
```

## Development

Install dev deps and run checks:

```bash
uv sync --group dev
uv run ruff check src tests
uv run pytest -v
```

## Skill Sync (`sync-skills`)

`sync-skills` deploys Claude Code skills to `~/.claude/skills/`, mirroring how
`sync-mcp-configs` deploys MCP configs.

- **Manifest:** `~/.config/skills/skills-master.json` declares `sources` (git or
  local) and an explicit `skills` allow-list. A machine overlay in
  `~/.config/skills/machine/` disables a skill on that machine by setting it to
  `false` inside its `skills` object, e.g. `{ "skills": { "caveman": false } }`.
- **Vendored skills** (git sources) are cloned into `~/.cache/mcp-sync/skills/`
  and **copied** into place; re-fetched only after `refreshPeriod`.
- **Personal skills** come from a `local` source — the `personal` source's
  `path` (currently `skills/personal/` in the chezmoi repo) — deployed as a
  **symlink**, so edits to the source are live without re-running the sync.
- **Garbage collection:** `~/.local/state/mcp-sync/skills-state.json` records
  what each run deployed; skills dropped from the manifest are removed on the
  next run. Skills the sync never deployed are never touched.

Run manually with `uv run --project mcp_sync sync-skills`. It runs automatically
after `chezmoi apply` via `.chezmoiscripts/run_after_sync-skills.sh.tmpl`.

### One-time migration cleanup

Before this feature, `~/.claude/skills/` held symlinks into `~/.agents/skills/`.
After the first `chezmoi apply` with `sync-skills`, remove the stale state by
hand (destructive — review before running):

```bash
# Remove dangling symlinks that point into ~/.agents/skills/
for link in ~/.claude/skills/*; do
  [ -L "$link" ] && [ ! -e "$link" ] && rm -v "$link"
done
# Once skills/personal/ has replaced it, retire the old directory:
rm -rf ~/.agents
```
