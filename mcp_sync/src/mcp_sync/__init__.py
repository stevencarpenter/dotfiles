"""MCP configuration sync package."""

from __future__ import annotations

from .sync import (
    deep_merge,
    load_master_config,
    patch_claude_code_config,
    run_sync,
    main,
    set_serena_context,
    sync_codex_mcp,
    sync_copilot_cli_config,
    sync_opencode_mcp,
    sync_to_locations,
    transform_to_copilot_format,
    transform_to_generic_mcp_format,
    transform_to_mcpservers_format,
    transform_to_opencode_format,
)

__all__ = [
    "load_master_config",
    "deep_merge",
    "patch_claude_code_config",
    "run_sync",
    "main",
    "set_serena_context",
    "sync_codex_mcp",
    "sync_copilot_cli_config",
    "sync_opencode_mcp",
    "sync_to_locations",
    "transform_to_copilot_format",
    "transform_to_generic_mcp_format",
    "transform_to_mcpservers_format",
    "transform_to_opencode_format",
]

__version__ = "0.2.0"
