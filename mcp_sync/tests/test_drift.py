"""Tests for drift detection (sync-mcp-configs --check)."""

from __future__ import annotations

import json

from mcp_sync.cli import cli
from mcp_sync.drift import drift_report, run_check
from mcp_sync.sync import load_master_config, run_sync


def _entries_by_name(entries):
    return {entry.name: entry for entry in entries}


def test_report_is_clean_immediately_after_sync(
    temp_home, monkeypatch_home, master_config_file
):
    """A freshly synced home has no drift anywhere."""
    assert run_sync(home=temp_home) == 0

    master = load_master_config(master_config_file)
    entries = _entries_by_name(drift_report(master, temp_home))

    assert set(entries) >= {"cursor", "opencode", "vscode", "codex", "claude", "gemini"}
    # ~/.claude.json and ~/.gemini/settings.json don't exist in the fixture
    # home; the sync skips them, so drift must report skipped, not missing.
    assert entries["claude"].status == "skipped"
    assert entries["gemini"].status == "skipped"
    for name, entry in entries.items():
        if name in ("claude", "gemini"):
            continue
        assert entry.status == "clean", f"{name}: {entry.status}\n{entry.diff}"


def test_deleted_target_file_reports_missing(
    temp_home, monkeypatch_home, master_config_file
):
    """Removing a generated file is drift: the next sync would recreate it."""
    run_sync(home=temp_home)
    (temp_home / ".cursor" / "mcp.json").unlink()

    master = load_master_config(master_config_file)
    entries = _entries_by_name(drift_report(master, temp_home))

    assert entries["cursor"].status == "missing"


def test_hand_edit_reports_drift_with_diff(
    temp_home, monkeypatch_home, master_config_file
):
    """A hand-edited generated file reports drift and shows the edit."""
    run_sync(home=temp_home)
    cursor_path = temp_home / ".cursor" / "mcp.json"
    config = json.loads(cursor_path.read_text(encoding="utf-8"))
    config["mcpServers"]["hand-added"] = {"command": "echo", "args": []}
    cursor_path.write_text(json.dumps(config, indent=2) + "\n", encoding="utf-8")

    master = load_master_config(master_config_file)
    entries = _entries_by_name(drift_report(master, temp_home))

    assert entries["cursor"].status == "drift"
    assert "hand-added" in entries["cursor"].diff


def test_claude_unmanaged_keys_are_not_drift(
    temp_home, monkeypatch_home, master_config_file, claude_config_template
):
    """Keys Claude Code owns in ~/.claude.json never count as drift."""
    claude_path = temp_home / ".claude.json"
    claude_path.write_text(json.dumps(claude_config_template), encoding="utf-8")
    run_sync(home=temp_home)

    config = json.loads(claude_path.read_text(encoding="utf-8"))
    config["someRuntimeState"] = {"lastProject": "/tmp/x"}
    claude_path.write_text(json.dumps(config, indent=2) + "\n", encoding="utf-8")

    master = load_master_config(master_config_file)
    entries = _entries_by_name(drift_report(master, temp_home))

    assert entries["claude"].status == "clean"


def test_claude_managed_server_edit_is_drift(
    temp_home, monkeypatch_home, master_config_file, claude_config_template
):
    """Hand edits to a managed server entry in ~/.claude.json are drift."""
    claude_path = temp_home / ".claude.json"
    claude_path.write_text(json.dumps(claude_config_template), encoding="utf-8")
    run_sync(home=temp_home)

    config = json.loads(claude_path.read_text(encoding="utf-8"))
    config["mcpServers"]["memory"]["args"] = ["--tweaked"]
    claude_path.write_text(json.dumps(config, indent=2) + "\n", encoding="utf-8")

    master = load_master_config(master_config_file)
    entries = _entries_by_name(drift_report(master, temp_home))

    assert entries["claude"].status == "drift"
    assert "--tweaked" in entries["claude"].diff


def test_codex_is_clean_after_sync_and_drifts_on_managed_edit(
    temp_home, monkeypatch_home, master_config_file
):
    """Codex managed block round-trips cleanly; edits inside it are drift."""
    run_sync(home=temp_home)
    master = load_master_config(master_config_file)

    entries = _entries_by_name(drift_report(master, temp_home))
    assert entries["codex"].status == "clean"

    codex_path = temp_home / ".codex" / "config.toml"
    text = codex_path.read_text(encoding="utf-8")
    codex_path.write_text(
        text.replace('command = "node"', 'command = "deno"'), encoding="utf-8"
    )
    entries = _entries_by_name(drift_report(master, temp_home))
    assert entries["codex"].status == "drift"


def test_run_check_exit_codes(temp_home, monkeypatch_home, master_config_file):
    """run_check is 0 when clean and 1 once anything drifts."""
    run_sync(home=temp_home)
    assert run_check(master_path=master_config_file, home=temp_home) == 0

    (temp_home / ".junie" / "mcp" / "mcp.json").unlink()
    assert run_check(master_path=master_config_file, home=temp_home) == 1


def test_cli_check_flag(temp_home, monkeypatch_home, master_config_file):
    """The --check flag runs drift detection instead of syncing."""
    run_sync(home=temp_home)
    lmstudio_path = temp_home / ".lmstudio" / "mcp.json"
    before = lmstudio_path.read_text(encoding="utf-8")
    lmstudio_path.unlink()

    exit_code = cli(
        ["--check", "--home", str(temp_home), "--master", str(master_config_file)]
    )

    assert exit_code == 1
    # --check must never write anything.
    assert not lmstudio_path.exists()
    # And a clean home passes.
    run_sync(home=temp_home)
    assert lmstudio_path.read_text(encoding="utf-8") == before
    exit_code = cli(
        ["--check", "--home", str(temp_home), "--master", str(master_config_file)]
    )
    assert exit_code == 0


def test_claude_serializer_differences_are_not_drift(
    temp_home, monkeypatch_home, master_config_file, claude_config_template
):
    """Claude Code's own serializer (literal UTF-8, no trailing newline) is
    not drift: two programs co-own the file, so only content may count."""
    claude_path = temp_home / ".claude.json"
    claude_path.write_text(json.dumps(claude_config_template), encoding="utf-8")
    run_sync(home=temp_home)

    config = json.loads(claude_path.read_text(encoding="utf-8"))
    config["companionPersonality"] = "no chill—screams about bugs · loudly"
    # Claude Code writes literal UTF-8 with no trailing newline.
    claude_path.write_text(
        json.dumps(config, indent=2, ensure_ascii=False), encoding="utf-8"
    )

    master = load_master_config(master_config_file)
    entries = _entries_by_name(drift_report(master, temp_home))

    assert entries["claude"].status == "clean"
