# MCP (Model Context Protocol) Setup Guide

## Overview

This dotfiles repo fans a layered MCP config out to every AI development tool automatically. The
fan-out is handled by the `mcp_sync/` Python tool, which runs after every `chezmoi apply` (on
machines with the `mcp` capability).

## How It Works

Configs are merged in this order (later layers win), then transformed into each tool's format:

1. **Base templates** — `mcp_sync/src/mcp_sync/templates/<tool>.base.{json,toml}` — static per-tool
   scaffolding (only `codex` and `opencode` have one today).
2. **Master config** — `dot_config/mcp/mcp-master.json` — servers shared across *all* machine types.
   Currently **empty**: nothing is deployed everywhere (see below).
3. **Machine overlays** — `dot_config/mcp/machine/{work.json,personal.json.tmpl,lab.json.tmpl}` —
   servers added per machine type, selected by chezmoi's `.machine` variable.
4. **Per-tool overrides** — each target reads `~/.config/mcp/overrides/<key>.json` at sync time to
   add/override servers for one tool. Wired in `sync.py`; no override files are managed in-repo yet
   (the deployed `~/.config/mcp/overrides/` dir exists but is empty).

The hook is `.chezmoiscripts/run_after_sync-mcp.sh.tmpl`; on machines without the `mcp` capability
its body is a no-op.

## Current MCP Servers

The master config is intentionally empty — no server is deployed to every machine. GitHub is no
longer an MCP server here: it moved to the `github@claude-plugins-official` Claude Code plugin (a
remote HTTP server, enabled in `dot_claude/modify_settings.json.tmpl`). Railway was removed. All
remaining servers live in machine overlays:

| Server | Machine(s) | Package / command | Purpose |
|--------|-----------|-------------------|---------|
| **AWS CCAPI** | work | `uvx awslabs.ccapi-mcp-server --readonly` | AWS resource management (read-only) |
| **hippo** | personal | `uv run --project ~/projects/hippo/brain hippo-mcp` | Local knowledge base / brain |
| **grafana** | personal, lab | `uvx mcp-grafana --disable-write` | Home-ops dashboards (read-only) |
| **codegraph** | personal | `codegraph serve --mcp` | Local code-intelligence index |

## Sync Targets

After `chezmoi apply`, the merged config is written to:

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
| Generic MCP | `~/.config/mcp/mcp_config.json` |

## Adding a New MCP Server

Add it to the layer that matches its scope:

- **All machines** → `dot_config/mcp/mcp-master.json` (`servers` object).
- **One machine type** → the matching overlay in `dot_config/mcp/machine/`
  (`work.json`, `personal.json.tmpl`, or `lab.json.tmpl`).
- **One tool only** → `~/.config/mcp/overrides/<tool-key>.json` (e.g. `claude.json`, `cursor.json`).

```bash
chezmoi edit ~/.config/mcp/machine/personal.json   # or work.json / lab.json / mcp-master.json
chezmoi apply                                        # sync runs automatically
```

A server entry uses the standard MCP shape (`type`, `command`, `args`, `env`, …). The repo also
honours two sync-gate fields that are stripped before output: `enabled: true|false` (the canonical
convention) and `disabled: true|false` (foreign-schema compat) — see `_is_server_enabled` in
`sync.py`.

## Manual Sync

```bash
uv run --project ~/.local/share/chezmoi/mcp_sync sync-mcp-configs
```

## Authentication / Credentials

- **AWS CCAPI**: reads `${AWS_PROFILE}` (expanded by the MCP client at launch); SSO config comes
  from `aws_config_gen`. No long-lived secret in the config.
- **hippo / grafana**: no credentials — local stdio servers talking to localhost.
- **GitHub** (the plugin, not an MCP server here): authenticates via the Claude Code plugin /
  `gh` keychain token, not via this sync.

Any secret-bearing env vars referenced by a server (`${VAR}`) are stored encrypted in
`dot_config/zsh/encrypted_dot_env` and sourced at shell startup.

## Troubleshooting

**Sync not running after apply?**
- Verify `uv` is installed: `which uv`
- Confirm the machine has the `mcp` capability in `.chezmoidata/machines.toml` (the hook is a no-op otherwise)
- Check the sync hook: `.chezmoiscripts/run_after_sync-mcp.sh.tmpl`

**Server not appearing in a tool?**
- Check for a per-tool override that excludes it: `ls ~/.config/mcp/overrides/`
- Confirm the server is `enabled` (or not `disabled`) in its layer
- Verify the tool's config was written: check the destination path from the table above

**Testing sync changes:**
```bash
uv run --project mcp_sync --group dev pytest mcp_sync/tests -v
```
