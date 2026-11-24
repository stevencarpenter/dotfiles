# MCP (Model Context Protocol) Setup Guide

## Overview

This dotfiles repo fans a layered MCP config out to every AI development tool automatically. The
fan-out is handled by the `mcp_sync/` Python tool, which `scripts/hooks-sync.sh` runs on every
`dfm sync` (through the `side-channels` updater). It skips a host that has no machine overlay.

## How It Works

Configs are merged in this order (later layers win), then transformed into each tool's format:

1. **Base templates**: `mcp_sync/src/mcp_sync/templates/<tool>.base.{json,toml}`: static per-tool
   scaffolding (only `codex` and `opencode` have one today).
2. **Master config**: `home/.config/mcp/mcp-master.json`: servers shared across *all* machine types.
   Currently **empty**: nothing is deployed everywhere (see below).
3. **Machine overlay**: `~/.config/mcp/machine/<identity>.json`: servers added for the host's
   identity (`scripts/host-capability.sh --identity`). The `personal` module links
   `home/.config/mcp/machine/personal.json`; an external bundle's identity module links its own
   (`docs/external-bundles.md`).
4. **Per-tool overrides**: each target reads `~/.config/mcp/overrides/<key>.json` at sync time to
   add/override servers for one tool. Wired in `sync.py`; no override files are managed in-repo yet
   (the deployed `~/.config/mcp/overrides/` dir exists but is empty).

The step is mcpSync in `scripts/hooks-sync.sh`; it reports a failure without failing the apply.

## Current MCP Servers

The master config is intentionally empty: no server is deployed to every machine. GitHub is no
longer an MCP server in this sync, and the `core.claude-settings` resource of
`dfm-module-core.toml` declares no Claude Code GitHub plugin. The retired `github` and `xcode` MCP server names are
scrubbed from generated targets and old in-place configs during sync. Railway was removed. All
remaining servers live in machine overlays:

| Server | Machine(s) | Package / command | Purpose |
|--------|-----------|-------------------|---------|
| **AWS CCAPI** | work | `uvx awslabs.ccapi-mcp-server --readonly` | AWS resource management (read-only) |
| **hippo** | personal | `uv run --no-sync --project ~/.local/share/hippo-brain hippo-mcp` | Local knowledge base / brain |
| **grafana** | personal, lab | `uvx mcp-grafana --disable-write` | Local Grafana (read-only). The master entry uses `localhost:3000`. The personal overlay sets `localhost:3030`, the hippo OTel stack. |
| **grafana-homelab** | personal | `uvx mcp-grafana --disable-write` | Homelab Grafana on i9 at `grafana.snugmarina.org`, tailnet only (read-only) |
| **grafana-cloud** | personal | `uvx mcp-grafana --disable-write` | Grafana Cloud stack `daringdate906.grafana.net` (read-only) |
| **codegraph** | personal | `codegraph serve --mcp` | Local code-intelligence index |

## Sync Targets

After the sync, the merged config is written to:

| Tool | Destination |
|------|-------------|
| GitHub Copilot CLI | `~/.copilot/mcp-config.json` |
| GitHub Copilot (IDE) | `~/.config/github-copilot/mcp.json` |
| IntelliJ Copilot | `~/.config/github-copilot/intellij/mcp.json` |
| Cursor | `~/.cursor/mcp.json` |
| VS Code | `~/Library/Application Support/Code/User/mcp.json` |
| Junie | `~/.junie/mcp/mcp.json` |
| LM Studio | `~/.lmstudio/mcp.json` |
| Codex CLI | `~/.codex/config.toml` (MCP servers patched in place; Codex owns the file) |
| Claude Code | `~/.claude.json` (servers patched in place; tool-owned file) |
| OpenCode | `~/.config/opencode/opencode.json` |

## Adding a New MCP Server

Add it to the layer that matches its scope:

- **All machines** → `home/.config/mcp/mcp-master.json` (`servers` object).
- **One identity** → `home/.config/mcp/machine/personal.json`, or the external bundle's overlay.
- **One tool only** → `~/.config/mcp/overrides/<tool-key>.json` (e.g. `claude.json`, `cursor.json`).

The files are links into the checkout, so an edit takes effect at the next `just mcp-sync`.

A server entry uses the standard MCP shape (`type`, `command`, `args`, `env`, …). The repo also
honours two sync-gate fields that are stripped before output: `enabled: true|false` (the canonical
convention) and `disabled: true|false` (foreign-schema compat): see `_is_server_enabled` in
`sync.py`.

## Manual Sync

```bash
uv run --project ~/.dotfiles/mcp_sync sync-mcp-configs
```

## Authentication / Credentials

- **AWS CCAPI**: reads `${AWS_PROFILE}` (expanded by the MCP client at launch); SSO config comes
  from the external `aws-config-gen` tool (owned by the work wrapper). No long-lived secret in the config.
- **hippo / grafana**: no credentials: local stdio servers talking to localhost.
- **grafana-homelab / grafana-cloud**: each reads a Grafana service account token (Viewer role)
  from `${GRAFANA_HOMELAB_SA_TOKEN}` or `${GRAFANA_CLOUD_SA_TOKEN}`. The entry uses the
  `${VAR:-}` form, so an unset variable gives an empty token and the server returns 401.
  Only a client that expands `${VAR}` in `env` can use these two servers.
- **GitHub** (the plugin, not an MCP server here): authenticates via the Claude Code plugin /
  `gh` keychain token, not via this sync.

Any secret-bearing env vars referenced by a server (`${VAR}`) come from the 1Password-rendered
`~/.config/zsh/.personal.env` (or the external bundle's own secret) and are sourced at shell startup.

## Troubleshooting

**Sync not running after apply?**
- Verify `uv` is installed: `which uv`
- Confirm the overlay exists: `ls ~/.config/mcp/machine/` lists `<identity>.json`
- Check the sync step: mcpSync in `scripts/hooks-sync.sh`

**Server not appearing in a tool?**
- Check for a per-tool override that excludes it: `ls ~/.config/mcp/overrides/`
- Confirm the server is `enabled` (or not `disabled`) in its layer
- Verify the tool's config was written: check the destination path from the table above

**Testing sync changes:**
```bash
uv run --project mcp_sync --group dev pytest mcp_sync/tests -v
```
