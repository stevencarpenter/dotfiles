"""Tests for the sync-skills CLI."""

from __future__ import annotations

from mcp_sync.skills_cli import build_parser, cli


def test_parser_accepts_all_flags():
    args = build_parser().parse_args(
        [
            "--manifest",
            "/m.json",
            "--machine-config",
            "/o.json",
            "--home",
            "/h",
            "--repo-root",
            "/r",
        ]
    )
    assert args.manifest.name == "m.json"
    assert args.machine_config.name == "o.json"
    assert args.home.name == "h"
    assert args.repo_root.name == "r"


def test_cli_returns_1_on_missing_manifest(tmp_path):
    assert cli(["--home", str(tmp_path), "--repo-root", str(tmp_path)]) == 1
