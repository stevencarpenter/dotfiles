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
