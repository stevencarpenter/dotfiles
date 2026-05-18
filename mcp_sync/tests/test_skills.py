"""Tests for the skill synchronization module."""

from __future__ import annotations

import json

import pytest

import mcp_sync.skills as skills_mod
from mcp_sync.skills import ResolvedSkill
from mcp_sync.skills import ensure_git_source
from mcp_sync.skills import load_skills_manifest
from mcp_sync.skills import load_state
from mcp_sync.skills import parse_duration
from mcp_sync.skills import resolve_skills
from mcp_sync.skills import deploy_skill
from mcp_sync.skills import garbage_collect
from mcp_sync.skills import write_state


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


def test_resolve_skills_rejects_entry_without_source():
    manifest = _manifest()
    manifest["skills"]["nosrc"] = {"path": "skills/x/nosrc"}
    with pytest.raises(ValueError, match="missing required 'source'"):
        resolve_skills(manifest)


def test_resolve_skills_rejects_source_without_type():
    manifest = _manifest()
    manifest["sources"]["typeless"] = {"url": "https://example.com/y"}
    manifest["skills"]["t"] = {"source": "typeless", "path": "skills/x/t"}
    with pytest.raises(ValueError, match="missing required 'type'"):
        resolve_skills(manifest)


def test_resolve_skills_local_entry_honors_explicit_path():
    manifest = _manifest()
    manifest["skills"]["aliased"] = {
        "source": "personal",
        "path": "skills/personal/custom-dir",
    }
    resolved = resolve_skills(manifest)
    aliased = next(s for s in resolved if s.name == "aliased")
    assert aliased == ResolvedSkill(
        "aliased", "personal", "local", "skills/personal/custom-dir", "symlink"
    )


def test_load_state_missing_returns_skeleton(tmp_path):
    assert load_state(tmp_path / "none.json") == {"deployed": {}, "sources": {}}


def test_write_then_load_state_roundtrips(tmp_path):
    path = tmp_path / "state" / "skills-state.json"
    state = {
        "deployed": {"tdd": {"mode": "copy", "source": "mattpocock"}},
        "sources": {"mattpocock": {"last_fetch": 123.0}},
    }
    write_state(path, state)
    assert load_state(path) == state


def test_load_state_invalid_json_returns_skeleton(tmp_path):
    path = tmp_path / "bad.json"
    path.write_text("{not json")
    assert load_state(path) == {"deployed": {}, "sources": {}}


def test_ensure_git_source_clones_when_cache_absent(tmp_path, monkeypatch):
    calls = []
    monkeypatch.setattr(skills_mod, "_git", lambda *a, **k: calls.append(a))
    cache_root = tmp_path / "cache"
    source = {"type": "git", "url": "https://example.com/x", "ref": "main"}
    state = {"deployed": {}, "sources": {}}
    result = ensure_git_source("mattpocock", source, cache_root, state, now=1000.0)
    assert result == cache_root / "mattpocock"
    assert calls[0] == (
        "clone",
        "https://example.com/x",
        str(cache_root / "mattpocock"),
    )
    assert ("fetch", "origin", "main") in calls
    assert ("reset", "--hard", "FETCH_HEAD") in calls
    assert state["sources"]["mattpocock"]["last_fetch"] == 1000.0


def test_ensure_git_source_skips_fetch_when_cache_fresh(tmp_path, monkeypatch):
    calls = []
    monkeypatch.setattr(skills_mod, "_git", lambda *a, **k: calls.append(a))
    cache_root = tmp_path / "cache"
    (cache_root / "mattpocock").mkdir(parents=True)
    source = {"type": "git", "url": "u", "refreshPeriod": "168h"}
    state = {"sources": {"mattpocock": {"last_fetch": 1000.0}}}
    ensure_git_source("mattpocock", source, cache_root, state, now=1000.0 + 3600)
    assert calls == []


def test_ensure_git_source_refetches_when_stale(tmp_path, monkeypatch):
    calls = []
    monkeypatch.setattr(skills_mod, "_git", lambda *a, **k: calls.append(a))
    cache_root = tmp_path / "cache"
    (cache_root / "mattpocock").mkdir(parents=True)
    source = {"type": "git", "url": "u", "ref": "v2", "refreshPeriod": "1h"}
    state = {"sources": {"mattpocock": {"last_fetch": 1000.0}}}
    ensure_git_source("mattpocock", source, cache_root, state, now=1000.0 + 99999)
    assert ("fetch", "origin", "v2") in calls
    assert ("reset", "--hard", "FETCH_HEAD") in calls
    assert state["sources"]["mattpocock"]["last_fetch"] == 1000.0 + 99999


def _make_skill(root, name):
    directory = root / name
    directory.mkdir(parents=True)
    (directory / "SKILL.md").write_text(f"# {name}")
    return directory


def test_deploy_skill_copy_creates_real_directory(tmp_path):
    src = _make_skill(tmp_path / "src", "tdd")
    target = tmp_path / "claude" / "skills" / "tdd"
    deploy_skill(src, target, "copy")
    assert (target / "SKILL.md").read_text() == "# tdd"
    assert not target.is_symlink()


def test_deploy_skill_symlink_points_at_source(tmp_path):
    src = _make_skill(tmp_path / "src", "refactor")
    target = tmp_path / "claude" / "skills" / "refactor"
    deploy_skill(src, target, "symlink")
    assert target.is_symlink()
    assert target.resolve() == src.resolve()


def test_deploy_skill_copy_replaces_stale_content(tmp_path):
    src = _make_skill(tmp_path / "src", "tdd")
    target = tmp_path / "claude" / "skills" / "tdd"
    target.mkdir(parents=True)
    (target / "stale.md").write_text("old")
    deploy_skill(src, target, "copy")
    assert not (target / "stale.md").exists()


def test_deploy_skill_symlink_is_idempotent(tmp_path):
    src = _make_skill(tmp_path / "src", "refactor")
    target = tmp_path / "claude" / "skills" / "refactor"
    deploy_skill(src, target, "symlink")
    deploy_skill(src, target, "symlink")
    assert target.resolve() == src.resolve()


def test_deploy_skill_missing_source_raises(tmp_path):
    with pytest.raises(FileNotFoundError):
        deploy_skill(tmp_path / "nope", tmp_path / "target", "copy")


def test_garbage_collect_removes_orphaned_symlink(tmp_path):
    target_root = tmp_path / "skills"
    target_root.mkdir()
    real = tmp_path / "real"
    real.mkdir()
    (target_root / "old").symlink_to(real)
    previous = {"old": {"mode": "symlink", "source": "personal"}}
    removed = garbage_collect(previous, set(), target_root)
    assert removed == ["old"]
    assert not (target_root / "old").is_symlink()


def test_garbage_collect_removes_orphaned_copy(tmp_path):
    target_root = tmp_path / "skills"
    (target_root / "old").mkdir(parents=True)
    previous = {"old": {"mode": "copy", "source": "mattpocock"}}
    removed = garbage_collect(previous, set(), target_root)
    assert removed == ["old"]
    assert not (target_root / "old").exists()


def test_garbage_collect_keeps_still_resolved_skills(tmp_path):
    target_root = tmp_path / "skills"
    (target_root / "keep").mkdir(parents=True)
    previous = {"keep": {"mode": "copy", "source": "mattpocock"}}
    removed = garbage_collect(previous, {"keep"}, target_root)
    assert removed == []
    assert (target_root / "keep").exists()


def test_garbage_collect_skips_entry_that_changed_shape(tmp_path):
    # Recorded as a copy, but now a symlink: the user replaced it. Leave it.
    target_root = tmp_path / "skills"
    target_root.mkdir()
    real = tmp_path / "real"
    real.mkdir()
    (target_root / "old").symlink_to(real)
    previous = {"old": {"mode": "copy", "source": "mattpocock"}}
    removed = garbage_collect(previous, set(), target_root)
    assert removed == []
    assert (target_root / "old").is_symlink()
