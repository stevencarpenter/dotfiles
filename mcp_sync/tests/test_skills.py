"""Tests for the skill synchronization module."""

from __future__ import annotations

import json

import pytest

from mcp_sync.skills import ResolvedSkill
from mcp_sync.skills import load_skills_manifest
from mcp_sync.skills import parse_duration
from mcp_sync.skills import resolve_skills


def test_parse_duration_hours():
    assert parse_duration("168h") == 604800


def test_parse_duration_days():
    assert parse_duration("7d") == 604800


def test_parse_duration_minutes_and_seconds():
    assert parse_duration("30m") == 1800
    assert parse_duration("45s") == 45


def test_parse_duration_rejects_garbage():
    with pytest.raises(ValueError, match="Invalid duration"):
        parse_duration("soon")


def test_load_skills_manifest_reads_sources_and_skills(tmp_path):
    path = tmp_path / "skills-master.json"
    path.write_text(
        json.dumps(
            {
                "sources": {"personal": {"type": "local", "path": "skills/personal"}},
                "skills": {"refactor": {"source": "personal"}},
            }
        )
    )
    manifest = load_skills_manifest(path)
    assert manifest["sources"]["personal"]["type"] == "local"
    assert manifest["skills"]["refactor"]["source"] == "personal"


def test_load_skills_manifest_defaults_missing_keys(tmp_path):
    path = tmp_path / "skills-master.json"
    path.write_text("{}")
    assert load_skills_manifest(path) == {"sources": {}, "skills": {}}


def test_load_skills_manifest_rejects_non_object_root(tmp_path):
    path = tmp_path / "skills-master.json"
    path.write_text("[]")
    with pytest.raises(ValueError, match="must be an object"):
        load_skills_manifest(path)


def _manifest():
    return {
        "sources": {
            "mattpocock": {"type": "git", "url": "https://example.com/x"},
            "personal": {"type": "local", "path": "skills/personal"},
        },
        "skills": {
            "tdd": {"source": "mattpocock", "path": "skills/engineering/tdd"},
            "refactor": {"source": "personal"},
        },
    }


def test_resolve_skills_git_entry_is_copy_mode():
    resolved = resolve_skills(_manifest())
    tdd = next(s for s in resolved if s.name == "tdd")
    assert tdd == ResolvedSkill(
        "tdd", "mattpocock", "git", "skills/engineering/tdd", "copy"
    )


def test_resolve_skills_local_entry_defaults_path_and_symlinks():
    resolved = resolve_skills(_manifest())
    refactor = next(s for s in resolved if s.name == "refactor")
    assert refactor == ResolvedSkill(
        "refactor", "personal", "local", "skills/personal/refactor", "symlink"
    )


def test_resolve_skills_drops_overlay_disabled_entries():
    manifest = _manifest()
    manifest["skills"]["tdd"] = False
    assert {s.name for s in resolve_skills(manifest)} == {"refactor"}


def test_resolve_skills_rejects_unknown_source():
    manifest = _manifest()
    manifest["skills"]["bad"] = {"source": "nope"}
    with pytest.raises(ValueError, match="unknown source"):
        resolve_skills(manifest)


def test_resolve_skills_rejects_git_entry_without_path():
    manifest = _manifest()
    manifest["skills"]["nopath"] = {"source": "mattpocock"}
    with pytest.raises(ValueError, match="requires a 'path'"):
        resolve_skills(manifest)
