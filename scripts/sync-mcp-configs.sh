#!/usr/bin/env bash
# Synchronize MCP configurations across different AI tool formats
# This ensures all tools use the same MCP server definitions

set -euo pipefail

# Source directory for master config
MCP_CONFIG_DIR="${HOME}/.config/mcp"
MASTER_CONFIG="${MCP_CONFIG_DIR}/mcp-master.json"

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_success() { echo -e "${GREEN}✓${NC} $1"; }
log_info() { echo -e "${YELLOW}→${NC} $1"; }

# Check if jq is installed
if ! command -v jq &> /dev/null; then
    echo "Error: jq is required but not installed. Install with: brew install jq"
    exit 1
fi

# Check if master config exists
if [[ ! -f "${MASTER_CONFIG}" ]]; then
    echo "Error: Master config not found at ${MASTER_CONFIG}"
    echo "Run 'chezmoi apply' to deploy dotfiles first"
    exit 1
fi

log_info "Syncing MCP configurations from master..."

# 1. Copilot (GitHub Copilot) - mcpServers format with tools array
COPILOT_CONFIG="${HOME}/.config/.copilot/mcp-config.json"
mkdir -p "$(dirname "${COPILOT_CONFIG}")"
jq '{mcpServers: (.servers | to_entries | map({
    key: .key,
    value: (.value + {tools: ["*"]} + if .value.type then {type: .value.type} else {type: "local"} end)
}) | from_entries)}' "${MASTER_CONFIG}" > "${COPILOT_CONFIG}"
log_success "Synced: ${COPILOT_CONFIG}"

# 2. GitHub Copilot (IntelliJ) - servers format (same as master)
INTELLIJ_COPILOT_CONFIG="${HOME}/.config/github-copilot/intellij/mcp.json"
mkdir -p "$(dirname "${INTELLIJ_COPILOT_CONFIG}")"
cp "${MASTER_CONFIG}" "${INTELLIJ_COPILOT_CONFIG}"
log_success "Synced: ${INTELLIJ_COPILOT_CONFIG}"

# 3. GitHub Copilot (general) - servers format (same as master)
GITHUB_COPILOT_CONFIG="${HOME}/.config/github-copilot/mcp.json"
mkdir -p "$(dirname "${GITHUB_COPILOT_CONFIG}")"
cp "${MASTER_CONFIG}" "${GITHUB_COPILOT_CONFIG}"
log_success "Synced: ${GITHUB_COPILOT_CONFIG}"

# 4. Generic MCP config (for other tools) - servers format
GENERIC_MCP_CONFIG="${HOME}/.config/mcp/mcp_config.json"
jq '{
    "$schema": "https://modelcontextprotocol.io/schema/config.json",
    mcpServers: (.servers | to_entries | map({
        key: .key,
        value: .value
    }) | from_entries)
}' "${MASTER_CONFIG}" > "${GENERIC_MCP_CONFIG}"
log_success "Synced: ${GENERIC_MCP_CONFIG}"

# 5. Codex CLI - TOML format (requires manual conversion for now)
CODEX_CONFIG="${HOME}/.codex/config.toml"
if [[ -f "${CODEX_CONFIG}" ]]; then
    log_info "Note: ${CODEX_CONFIG} requires manual sync (TOML format)"
    log_info "  Update [mcp_servers.*] sections to match master config"
else
    log_info "Skipping: ${CODEX_CONFIG} (file not found)"
fi

echo ""
log_success "MCP configuration sync complete!"
echo ""
echo "Next steps:"
echo "  1. Restart AI tools to pick up new configurations"
echo "  2. Verify with: cat ~/.config/.copilot/mcp-config.json"
