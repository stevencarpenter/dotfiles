"""Workspace import shim for the ``mcp_sync`` src-layout package.

This repository stores the distributable package in ``mcp_sync/src/mcp_sync``.
When tools type-check from the monorepo root, ``import mcp_sync`` can resolve
to this directory instead of the src package. Re-exporting the public API here
keeps imports consistent for tests and static analysis.
"""

from __future__ import annotations

from .src.mcp_sync import (
    deep_merge,
    load_master_config,
    main,
    patch_claude_code_config,
    run_sync,
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
    "sync_codex_mcp",
    "sync_copilot_cli_config",
    "sync_opencode_mcp",
    "sync_to_locations",
    "transform_to_copilot_format",
    "transform_to_generic_mcp_format",
    "transform_to_mcpservers_format",
    "transform_to_opencode_format",
]
