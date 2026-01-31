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

Install dev deps and run tests:

```bash
uv pip install -e .[dev]
uv run pytest -v
```
