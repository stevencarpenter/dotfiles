"""Tests for the skill synchronization module."""

from __future__ import annotations

import json
from pathlib import Path

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
from mcp_sync.skills import run_skills_sync


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


def test_work_and_lab_overlays_disable_all_git_sourced_skills():
    repo = Path(__file__).resolve().parents[2]
    manifest = load_skills_manifest(
        repo / "dot_config" / "skills" / "skills-master.json"
    )
    git_skills = {
        name
        for name, entry in manifest["skills"].items()
        if entry is not False and manifest["sources"][entry["source"]]["type"] == "git"
    }
    for overlay_name in ("work.json", "lab.json"):
        overlay = json.loads(
            (repo / "dot_config" / "skills" / "machine" / overlay_name).read_text()
        )
        disabled = {name for name, value in overlay["skills"].items() if value is False}
        assert disabled == git_skills


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


@pytest.mark.parametrize(
    "bad_name",
    ["", ".", "..", "../escaped", "nested/name", "/tmp/owned", "space name"],
)
def test_resolve_skills_rejects_unsafe_skill_names(bad_name):
    manifest = _manifest()
    manifest["skills"] = {
        bad_name: {"source": "personal", "path": "skills/personal/refactor"}
    }
    with pytest.raises(ValueError, match="unsafe skill name"):
        resolve_skills(manifest)


@pytest.mark.parametrize(
    "bad_path", ["../outside", "/tmp/outside", "skills/../outside"]
)
def test_resolve_skills_rejects_unsafe_explicit_paths(bad_path):
    manifest = _manifest()
    manifest["skills"]["refactor"] = {"source": "personal", "path": bad_path}
    with pytest.raises(ValueError, match="unsafe skill path"):
        resolve_skills(manifest)


def test_resolve_skills_rejects_unsafe_local_source_path():
    manifest = _manifest()
    manifest["sources"]["personal"]["path"] = "../outside"
    with pytest.raises(ValueError, match="unsafe source path"):
        resolve_skills(manifest)


def test_resolve_skills_rejects_git_source_without_url():
    manifest = _manifest()
    del manifest["sources"]["mattpocock"]["url"]
    with pytest.raises(ValueError, match="missing required 'url'"):
        resolve_skills(manifest)


def test_resolve_skills_rejects_local_source_without_path():
    manifest = _manifest()
    del manifest["sources"]["personal"]["path"]
    with pytest.raises(ValueError, match="missing required 'path'"):
        resolve_skills(manifest)


def test_resolve_skills_rejects_unsafe_git_skill_path():
    manifest = _manifest()
    manifest["skills"]["tdd"] = {"source": "mattpocock", "path": "../outside"}
    with pytest.raises(ValueError, match="unsafe skill path"):
        resolve_skills(manifest)


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
    monkeypatch.setattr(skills_mod, "_git", lambda *a, **k: calls.append((a, k)))
    cache_root = tmp_path / "cache"
    source = {"type": "git", "url": "https://example.com/x", "ref": "main"}
    state = {"deployed": {}, "sources": {}}
    result = ensure_git_source("mattpocock", source, cache_root, state, now=1000.0)
    assert result == cache_root / "mattpocock"
    cache_dir = cache_root / "mattpocock"
    assert calls[0] == (
        ("clone", "https://example.com/x", str(cache_dir)),
        {},
    )
    assert (("fetch", "origin", "main"), {"cwd": cache_dir}) in calls
    assert (("reset", "--hard", "FETCH_HEAD"), {"cwd": cache_dir}) in calls
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
    monkeypatch.setattr(skills_mod, "_git", lambda *a, **k: calls.append((a, k)))
    cache_root = tmp_path / "cache"
    (cache_root / "mattpocock").mkdir(parents=True)
    source = {"type": "git", "url": "u", "ref": "v2", "refreshPeriod": "1h"}
    state = {"sources": {"mattpocock": {"last_fetch": 1000.0}}}
    ensure_git_source("mattpocock", source, cache_root, state, now=1000.0 + 99999)
    cache_dir = cache_root / "mattpocock"
    assert (("fetch", "origin", "v2"), {"cwd": cache_dir}) in calls
    assert (("reset", "--hard", "FETCH_HEAD"), {"cwd": cache_dir}) in calls
    assert state["sources"]["mattpocock"]["last_fetch"] == 1000.0 + 99999


def test_ensure_git_source_refetches_when_ref_changes_even_if_fresh(
    tmp_path, monkeypatch
):
    calls = []
    monkeypatch.setattr(skills_mod, "_git", lambda *a, **k: calls.append((a, k)))
    cache_root = tmp_path / "cache"
    (cache_root / "mp").mkdir(parents=True)
    source = {"type": "git", "url": "u", "ref": "v2", "refreshPeriod": "168h"}
    state = {"sources": {"mp": {"last_fetch": 1000.0, "url": "u", "ref": "v1"}}}
    ensure_git_source("mp", source, cache_root, state, now=1000.0 + 60)
    assert any(args == ("fetch", "origin", "v2") for args, _ in calls)
    assert state["sources"]["mp"]["ref"] == "v2"
    assert state["sources"]["mp"]["url"] == "u"


def test_ensure_git_source_updates_origin_when_url_changes(tmp_path, monkeypatch):
    calls = []
    monkeypatch.setattr(skills_mod, "_git", lambda *a, **k: calls.append((a, k)))
    cache_root = tmp_path / "cache"
    (cache_root / "mp").mkdir(parents=True)
    source = {"type": "git", "url": "new-url", "ref": "main", "refreshPeriod": "168h"}
    state = {"sources": {"mp": {"last_fetch": 1000.0, "url": "old-url", "ref": "main"}}}
    ensure_git_source("mp", source, cache_root, state, now=1000.0 + 60)
    assert any(args == ("remote", "set-url", "origin", "new-url") for args, _ in calls)
    assert any(args == ("fetch", "origin", "main") for args, _ in calls)


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


def test_deploy_skill_copy_failure_keeps_existing_target(tmp_path, monkeypatch):
    src = _make_skill(tmp_path / "src", "tdd")
    target = tmp_path / "claude" / "skills" / "tdd"
    target.mkdir(parents=True)
    (target / "SKILL.md").write_text("# old")

    def fail_copytree(*args, **kwargs):
        raise OSError("disk full")

    monkeypatch.setattr(skills_mod.shutil, "copytree", fail_copytree)
    with pytest.raises(OSError, match="disk full"):
        deploy_skill(src, target, "copy")
    assert (target / "SKILL.md").read_text() == "# old"


def test_deploy_skill_copy_cleanup_failure_does_not_mask_success(tmp_path, monkeypatch):
    src = _make_skill(tmp_path / "src", "tdd")
    target = tmp_path / "claude" / "skills" / "tdd"
    target.mkdir(parents=True)
    (target / "SKILL.md").write_text("# old")
    real_rmtree = skills_mod.shutil.rmtree

    def flaky_rmtree(path, *args, **kwargs):
        # The post-rename cleanup of the backup directory fails transiently.
        if ".bak-" in str(path):
            raise OSError("cleanup boom")
        return real_rmtree(path, *args, **kwargs)

    monkeypatch.setattr(skills_mod.shutil, "rmtree", flaky_rmtree)
    deploy_skill(src, target, "copy")  # must not raise
    assert (target / "SKILL.md").read_text() == "# tdd"


def test_deploy_skill_copy_rejects_symlink_inside_source(tmp_path):
    src = _make_skill(tmp_path / "src", "tdd")
    outside = tmp_path / "outside-secret"
    outside.write_text("secret")
    (src / "leak").symlink_to(outside)
    target = tmp_path / "claude" / "skills" / "tdd"
    with pytest.raises(ValueError, match="symlink"):
        deploy_skill(src, target, "copy")
    assert not target.exists()


def test_deploy_skill_copy_rejects_symlinked_directory(tmp_path):
    # A symlinked *directory* must be reported, not descended into — the scan
    # never follows it, so a symlink loop cannot stall the safety check.
    src = _make_skill(tmp_path / "src", "tdd")
    (src / "loop").symlink_to(src)
    target = tmp_path / "claude" / "skills" / "tdd"
    with pytest.raises(ValueError, match="symlink"):
        deploy_skill(src, target, "copy")
    assert not target.exists()


def test_garbage_collect_removes_orphaned_symlink(tmp_path):
    target_root = tmp_path / "skills"
    target_root.mkdir()
    real = tmp_path / "real"
    real.mkdir()
    (target_root / "old").symlink_to(real)
    previous = {
        "old": {"mode": "symlink", "source": "personal", "target": str(real)}
    }
    removed = garbage_collect(previous, set(), target_root)
    assert removed == ["old"]
    assert not (target_root / "old").is_symlink()


def test_garbage_collect_keeps_replaced_symlink(tmp_path):
    # The user (or a plugin) repointed our symlink at their own directory.
    target_root = tmp_path / "skills"
    target_root.mkdir()
    ours = tmp_path / "ours"
    ours.mkdir()
    theirs = tmp_path / "theirs"
    theirs.mkdir()
    link = target_root / "old"
    link.symlink_to(theirs)
    previous = {
        "old": {"mode": "symlink", "source": "personal", "target": str(ours)}
    }
    removed = garbage_collect(previous, set(), target_root)
    assert removed == []
    assert link.is_symlink()


def test_garbage_collect_skips_symlink_without_recorded_target(tmp_path):
    # Pre-feature state has no recorded target — treat conservatively, keep it.
    target_root = tmp_path / "skills"
    target_root.mkdir()
    real = tmp_path / "real"
    real.mkdir()
    (target_root / "old").symlink_to(real)
    previous = {"old": {"mode": "symlink", "source": "personal"}}
    removed = garbage_collect(previous, set(), target_root)
    assert removed == []
    assert (target_root / "old").is_symlink()


def test_garbage_collect_removes_copy_with_matching_marker(tmp_path):
    target_root = tmp_path / "skills"
    copied = target_root / "old"
    copied.mkdir(parents=True)
    (copied / "SKILL.md").write_text("# old")
    (copied / ".mcp-sync-managed").write_text("mcp-sync-managed-v1\n")
    previous = {
        "old": {
            "mode": "copy",
            "source": "mattpocock",
            "marker": "mcp-sync-managed-v1",
        }
    }
    removed = garbage_collect(previous, set(), target_root)
    assert removed == ["old"]
    assert not copied.exists()


def test_garbage_collect_keeps_replaced_copy_without_marker(tmp_path):
    target_root = tmp_path / "skills"
    replaced = target_root / "old"
    replaced.mkdir(parents=True)
    (replaced / "SKILL.md").write_text("# user replacement")
    previous = {
        "old": {
            "mode": "copy",
            "source": "mattpocock",
            "marker": "mcp-sync-managed-v1",
        }
    }
    removed = garbage_collect(previous, set(), target_root)
    assert removed == []
    assert replaced.exists()


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


def test_garbage_collect_removes_broken_orphaned_symlink(tmp_path):
    target_root = tmp_path / "skills"
    target_root.mkdir()
    real = tmp_path / "real"
    real.mkdir()
    link = target_root / "old"
    link.symlink_to(real)
    real.rmdir()
    assert not link.exists()
    assert link.is_symlink()
    previous = {
        "old": {"mode": "symlink", "source": "personal", "target": str(real)}
    }
    removed = garbage_collect(previous, set(), target_root)
    assert removed == ["old"]
    assert not link.is_symlink()


def test_garbage_collect_skips_unsafe_state_name(tmp_path):
    target_root = tmp_path / "skills"
    target_root.mkdir()
    escaped = tmp_path / "escaped"
    escaped.mkdir()
    previous = {"../escaped": {"mode": "copy", "source": "personal"}}
    removed = garbage_collect(previous, set(), target_root)
    assert removed == []
    assert escaped.exists()


def _write_json(path, payload):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(payload))


def test_run_skills_sync_deploys_local_and_vendored(tmp_path):
    home = tmp_path / "home"
    repo = tmp_path / "repo"
    personal = repo / "skills" / "personal" / "refactor"
    personal.mkdir(parents=True)
    (personal / "SKILL.md").write_text("# refactor")
    # Pre-populate the git cache so no network access is needed.
    cached = (
        home
        / ".cache"
        / "mcp-sync"
        / "skills"
        / "mattpocock"
        / "skills"
        / "engineering"
        / "tdd"
    )
    cached.mkdir(parents=True)
    (cached / "SKILL.md").write_text("# tdd")
    state = home / ".local" / "state" / "mcp-sync" / "skills-state.json"
    _write_json(
        state, {"deployed": {}, "sources": {"mattpocock": {"last_fetch": 5000.0}}}
    )
    manifest = home / ".config" / "skills" / "skills-master.json"
    _write_json(
        manifest,
        {
            "sources": {
                "mattpocock": {"type": "git", "url": "u", "refreshPeriod": "168h"},
                "personal": {"type": "local", "path": "skills/personal"},
            },
            "skills": {
                "tdd": {"source": "mattpocock", "path": "skills/engineering/tdd"},
                "refactor": {"source": "personal"},
            },
        },
    )
    rc = run_skills_sync(home=home, repo_root=repo, now=5000.0 + 3600)
    assert rc == 0
    skills_dir = home / ".claude" / "skills"
    assert (skills_dir / "tdd" / "SKILL.md").read_text() == "# tdd"
    assert (skills_dir / "refactor").is_symlink()
    written = json.loads(state.read_text())
    assert written["deployed"]["tdd"] == {
        "mode": "copy",
        "source": "mattpocock",
        "marker": "mcp-sync-managed-v1",
    }
    assert (skills_dir / "tdd" / ".mcp-sync-managed").is_file()
    assert written["deployed"]["refactor"] == {
        "mode": "symlink",
        "source": "personal",
        "target": str(repo / "skills" / "personal" / "refactor"),
    }


def test_run_skills_sync_garbage_collects_dropped_skill(tmp_path):
    home = tmp_path / "home"
    repo = tmp_path / "repo"
    refactor = repo / "skills" / "personal" / "refactor"
    refactor.mkdir(parents=True)
    (refactor / "SKILL.md").write_text("# refactor")
    orphan = home / ".claude" / "skills" / "old-skill"
    orphan.mkdir(parents=True)
    (orphan / "SKILL.md").write_text("# old")
    (orphan / ".mcp-sync-managed").write_text("mcp-sync-managed-v1\n")
    state = home / ".local" / "state" / "mcp-sync" / "skills-state.json"
    _write_json(
        state,
        {
            "deployed": {
                "old-skill": {
                    "mode": "copy",
                    "source": "mattpocock",
                    "marker": "mcp-sync-managed-v1",
                }
            },
            "sources": {},
        },
    )
    manifest = home / ".config" / "skills" / "skills-master.json"
    _write_json(
        manifest,
        {
            "sources": {"personal": {"type": "local", "path": "skills/personal"}},
            "skills": {"refactor": {"source": "personal"}},
        },
    )
    rc = run_skills_sync(home=home, repo_root=repo, now=1.0)
    assert rc == 0
    assert not orphan.exists()


def test_run_skills_sync_missing_manifest_returns_1(tmp_path):
    assert run_skills_sync(home=tmp_path / "empty", repo_root=tmp_path) == 1


def test_run_skills_sync_machine_overlay_disables_skill(tmp_path):
    home = tmp_path / "home"
    repo = tmp_path / "repo"
    for name in ("refactor", "extra"):
        directory = repo / "skills" / "personal" / name
        directory.mkdir(parents=True)
        (directory / "SKILL.md").write_text(f"# {name}")
    manifest = home / ".config" / "skills" / "skills-master.json"
    _write_json(
        manifest,
        {
            "sources": {"personal": {"type": "local", "path": "skills/personal"}},
            "skills": {
                "refactor": {"source": "personal"},
                "extra": {"source": "personal"},
            },
        },
    )
    overlay = home / ".config" / "skills" / "machine" / "work.json"
    _write_json(overlay, {"skills": {"extra": False}})
    rc = run_skills_sync(
        home=home, repo_root=repo, machine_config_path=overlay, now=1.0
    )
    assert rc == 0
    assert (home / ".claude" / "skills" / "refactor").exists()
    assert not (home / ".claude" / "skills" / "extra").exists()


def test_ensure_git_source_force_bypasses_freshness(tmp_path, monkeypatch):
    calls = []
    monkeypatch.setattr(skills_mod, "_git", lambda *a, **k: calls.append(a))
    cache_root = tmp_path / "cache"
    (cache_root / "mp").mkdir(parents=True)
    source = {"type": "git", "url": "u", "ref": "main", "refreshPeriod": "168h"}
    state = {"sources": {"mp": {"last_fetch": 1000.0}}}
    ensure_git_source("mp", source, cache_root, state, now=1000.0 + 60, force=True)
    assert ("fetch", "origin", "main") in calls


def test_run_skills_sync_refetches_skill_absent_from_fresh_cache(tmp_path, monkeypatch):
    home = tmp_path / "home"
    repo = tmp_path / "repo"
    cache_mp = home / ".cache" / "mcp-sync" / "skills" / "mp"
    cache_mp.mkdir(parents=True)  # cache exists but does NOT contain the skill

    def fake_git(*args, **kwargs):
        # Simulate a fetch bringing the skill into the cache.
        if args and args[0] == "fetch":
            d = cache_mp / "skills" / "engineering" / "tdd"
            d.mkdir(parents=True, exist_ok=True)
            (d / "SKILL.md").write_text("# tdd")

    monkeypatch.setattr(skills_mod, "_git", fake_git)
    state = home / ".local" / "state" / "mcp-sync" / "skills-state.json"
    _write_json(state, {"deployed": {}, "sources": {"mp": {"last_fetch": 5000.0}}})
    manifest = home / ".config" / "skills" / "skills-master.json"
    _write_json(
        manifest,
        {
            "sources": {"mp": {"type": "git", "url": "u", "refreshPeriod": "168h"}},
            "skills": {"tdd": {"source": "mp", "path": "skills/engineering/tdd"}},
        },
    )
    # now is within the refresh window, so the cache is "time-fresh".
    rc = run_skills_sync(home=home, repo_root=repo, now=5000.0 + 3600)
    assert rc == 0
    assert (home / ".claude" / "skills" / "tdd" / "SKILL.md").read_text() == "# tdd"


def test_run_skills_sync_skips_skill_with_unexpected_error_and_continues(tmp_path):
    home = tmp_path / "home"
    repo = tmp_path / "repo"
    good = repo / "skills" / "personal" / "good"
    good.mkdir(parents=True)
    (good / "SKILL.md").write_text("# good")
    # A vendored skill whose cached source smuggles in a symlink — deploy
    # raises ValueError, which must be logged-and-skipped, not abort the run.
    cached = home / ".cache" / "mcp-sync" / "skills" / "mp" / "skills" / "bad"
    cached.mkdir(parents=True)
    (cached / "SKILL.md").write_text("# bad")
    (cached / "leak").symlink_to(tmp_path)
    state = home / ".local" / "state" / "mcp-sync" / "skills-state.json"
    _write_json(state, {"deployed": {}, "sources": {"mp": {"last_fetch": 5000.0}}})
    manifest = home / ".config" / "skills" / "skills-master.json"
    _write_json(
        manifest,
        {
            "sources": {
                "mp": {"type": "git", "url": "u", "refreshPeriod": "168h"},
                "personal": {"type": "local", "path": "skills/personal"},
            },
            "skills": {
                "bad": {"source": "mp", "path": "skills/bad"},
                "good": {"source": "personal"},
            },
        },
    )
    rc = run_skills_sync(home=home, repo_root=repo, now=5000.0 + 3600)
    assert rc == 1
    assert (home / ".claude" / "skills" / "good" / "SKILL.md").read_text() == "# good"
    assert not (home / ".claude" / "skills" / "bad").exists()
    # State is still written despite the per-skill failure.
    assert state.is_file()


def test_run_skills_sync_skips_failed_skill_and_continues(tmp_path):
    home = tmp_path / "home"
    repo = tmp_path / "repo"
    good = repo / "skills" / "personal" / "good"
    good.mkdir(parents=True)
    (good / "SKILL.md").write_text("# good")
    # "bad" has a manifest entry but no source directory on disk.
    manifest = home / ".config" / "skills" / "skills-master.json"
    _write_json(
        manifest,
        {
            "sources": {"personal": {"type": "local", "path": "skills/personal"}},
            "skills": {
                "good": {"source": "personal"},
                "bad": {"source": "personal"},
            },
        },
    )
    rc = run_skills_sync(home=home, repo_root=repo, now=1.0)
    assert rc == 1  # the run reports failure
    assert (home / ".claude" / "skills" / "good" / "SKILL.md").read_text() == "# good"
    assert not (home / ".claude" / "skills" / "bad").exists()


def test_run_skills_sync_keeps_prior_copy_of_failed_resolved_skill(tmp_path):
    home = tmp_path / "home"
    repo = tmp_path / "repo"
    # "x" was deployed by a prior run; its source directory is now missing.
    prior_x = home / ".claude" / "skills" / "x"
    prior_x.mkdir(parents=True)
    (prior_x / "SKILL.md").write_text("# old x")
    state = home / ".local" / "state" / "mcp-sync" / "skills-state.json"
    _write_json(
        state,
        {
            "deployed": {"x": {"mode": "copy", "source": "personal"}},
            "sources": {},
        },
    )
    manifest = home / ".config" / "skills" / "skills-master.json"
    _write_json(
        manifest,
        {
            "sources": {"personal": {"type": "local", "path": "skills/personal"}},
            "skills": {"x": {"source": "personal"}},  # still in the manifest
        },
    )
    rc = run_skills_sync(home=home, repo_root=repo, now=1.0)
    assert rc == 1
    # x failed to deploy but is still resolved — its prior copy must survive.
    assert (prior_x / "SKILL.md").read_text() == "# old x"
    written = json.loads(state.read_text())
    assert written["deployed"]["x"] == {"mode": "copy", "source": "personal"}


def test_run_skills_sync_git_failure_still_deploys_local_skill(tmp_path, monkeypatch):
    home = tmp_path / "home"
    repo = tmp_path / "repo"
    local = repo / "skills" / "personal" / "refactor"
    local.mkdir(parents=True)
    (local / "SKILL.md").write_text("# refactor")
    manifest = home / ".config" / "skills" / "skills-master.json"
    _write_json(
        manifest,
        {
            "sources": {
                "mp": {"type": "git", "url": "u", "ref": "main"},
                "personal": {"type": "local", "path": "skills/personal"},
            },
            "skills": {
                "tdd": {"source": "mp", "path": "skills/engineering/tdd"},
                "refactor": {"source": "personal"},
            },
        },
    )

    def fail_git(*args, **kwargs):
        raise skills_mod.subprocess.CalledProcessError(128, ["git", *args])

    monkeypatch.setattr(skills_mod, "_git", fail_git)
    rc = run_skills_sync(home=home, repo_root=repo, now=1.0)
    assert rc == 1
    assert (home / ".claude" / "skills" / "refactor").is_symlink()


def test_run_skills_sync_non_object_manifest_returns_1(tmp_path):
    home = tmp_path / "home"
    manifest = home / ".config" / "skills" / "skills-master.json"
    _write_json(manifest, [])
    assert run_skills_sync(home=home, repo_root=tmp_path, now=1.0) == 1


def test_run_skills_sync_non_object_overlay_returns_1(tmp_path):
    home = tmp_path / "home"
    repo = tmp_path / "repo"
    refactor = repo / "skills" / "personal" / "refactor"
    refactor.mkdir(parents=True)
    (refactor / "SKILL.md").write_text("# refactor")
    manifest = home / ".config" / "skills" / "skills-master.json"
    _write_json(
        manifest,
        {
            "sources": {"personal": {"type": "local", "path": "skills/personal"}},
            "skills": {"refactor": {"source": "personal"}},
        },
    )
    overlay = home / ".config" / "skills" / "machine" / "work.json"
    _write_json(overlay, [])
    assert (
        run_skills_sync(home=home, repo_root=repo, machine_config_path=overlay, now=1.0)
        == 1
    )


def test_run_skills_sync_prunes_dropped_source_from_state(tmp_path):
    home = tmp_path / "home"
    repo = tmp_path / "repo"
    refactor = repo / "skills" / "personal" / "refactor"
    refactor.mkdir(parents=True)
    (refactor / "SKILL.md").write_text("# refactor")
    state = home / ".local" / "state" / "mcp-sync" / "skills-state.json"
    _write_json(
        state,
        {"deployed": {}, "sources": {"deadsource": {"last_fetch": 999.0}}},
    )
    manifest = home / ".config" / "skills" / "skills-master.json"
    _write_json(
        manifest,
        {
            "sources": {"personal": {"type": "local", "path": "skills/personal"}},
            "skills": {"refactor": {"source": "personal"}},
        },
    )
    rc = run_skills_sync(home=home, repo_root=repo, now=1.0)
    assert rc == 0
    written = json.loads(state.read_text())
    # "deadsource" is referenced by nothing in the manifest — pruned.
    assert written["sources"] == {}
