# Skill Sync Review Remediation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Resolve every blocking review finding from PR #67's `sync-skills` review before merging the skill distribution feature.

**Architecture:** Keep the `sync-skills` feature in `mcp_sync`, but add explicit trust boundaries: safe skill names, confined source/target paths, rejected vendored symlinks, source identity tracking, non-destructive replacement, and predictable machine policy. The post-apply hook should use the intended machine overlay rather than whatever stale overlay file happens to sort first.

**Tech Stack:** Python 3.14, `uv`, `pytest`, `ruff`, Chezmoi templates, bash, JSON manifests.

---

## Review Finding Coverage

| Finding | Covered By |
|---|---|
| Skill names from manifest/state can escape `~/.claude/skills` and delete/write outside the managed tree | Task 1 |
| Vendored `copytree()` follows symlinks from third-party git content | Task 2 |
| Copy deployment deletes existing target before a successful replacement is ready | Task 3 |
| Git source cache freshness ignores `url` and `ref` changes | Task 4 |
| Git clone/fetch/reset failures traceback and block unrelated skills | Task 4 |
| Third-party skills float on upstream `main` and deploy to work/lab | Task 5 |
| Malformed/non-object manifest produces traceback from `run_skills_sync` | Task 6 |
| CI does not exercise the installed `sync-skills` entrypoint or production hook paths | Task 7 |
| `_git` tests do not verify `cwd`, allowing fetch/reset regressions | Task 7 |
| README cleanup deletes broader state than described | Task 8 |
| Hook chooses first stale overlay left on disk after machine type changes | Task 9 |
| GC deletes user/plugin replacement directories for previously managed copy-mode skills | Task 10 |

## Execution Rules

- Claim one task at a time and keep commits scoped to that task.
- Use TDD for Python behavior changes: write the failing test, run it, implement, rerun.
- Run the task-specific command listed in each task before committing.
- Do not weaken the reviewed safety boundary to preserve backward compatibility with unsafe state. Invalid state should be skipped or pruned safely, never used to build paths.
- Do not add `Co-Authored-By: Claude` or generated-by trailers.

## File Structure

| File | Responsibility |
|---|---|
| `mcp_sync/src/mcp_sync/skills.py` | Core skill resolution, source fetching, path safety, deploy, garbage collection |
| `mcp_sync/src/mcp_sync/skills_cli.py` | CLI wrapper for `sync-skills` |
| `mcp_sync/tests/test_skills.py` | Unit and integration tests for safety, deploy, source, and GC behavior |
| `mcp_sync/tests/test_skills_cli.py` | CLI parser/entry behavior tests |
| `dot_config/skills/skills-master.json` | Pinned skill source manifest |
| `dot_config/skills/machine/{personal,work,lab}.json` | Machine-specific allow/deny policy |
| `.chezmoiscripts/run_after_sync-skills.sh.tmpl` | Post-apply hook that invokes `sync-skills` |
| `.github/workflows/mcp-sync-ci.yml` | CI path filters and entrypoint verification |
| `mcp_sync/README.md` | Operator documentation and safe migration cleanup |

---

### Task 0: Baseline Verification

**Files:**
- Read: current branch only

- [ ] **Step 1: Confirm branch and clean worktree**

Run:

```bash
git status --short --branch
```

Expected: branch is `feat/skill-distribution`. If unrelated files are modified, stop and ask before touching them.

- [ ] **Step 2: Run current mcp_sync verification**

Run:

```bash
uv run --project mcp_sync --group dev ruff check mcp_sync/src mcp_sync/tests
uv run --project mcp_sync --group dev ruff format --check mcp_sync/src mcp_sync/tests
uv run --project mcp_sync --group dev pytest mcp_sync/tests --cov=mcp_sync --cov-report=term-missing
```

Expected: current baseline passes before changes.

---

### Task 1: Constrain Skill Names And Source/Target Paths

**Files:**
- Modify: `mcp_sync/src/mcp_sync/skills.py`
- Test: `mcp_sync/tests/test_skills.py`

- [ ] **Step 1: Write failing tests for unsafe manifest names**

Add tests like these to `mcp_sync/tests/test_skills.py`:

```python
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
```

- [ ] **Step 2: Write failing tests for unsafe state keys in garbage collection**

Add this test:

```python
def test_garbage_collect_skips_unsafe_state_name(tmp_path):
    target_root = tmp_path / "skills"
    target_root.mkdir()
    escaped = tmp_path / "escaped"
    escaped.mkdir()
    previous = {"../escaped": {"mode": "copy", "source": "personal"}}

    removed = garbage_collect(previous, set(), target_root)

    assert removed == []
    assert escaped.exists()
```

- [ ] **Step 3: Write failing tests for unsafe source subpaths**

Add these tests:

```python
@pytest.mark.parametrize("bad_path", ["../outside", "/tmp/outside", "skills/../outside"])
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
```

- [ ] **Step 4: Run tests to verify failure**

Run:

```bash
uv run --project mcp_sync --group dev pytest mcp_sync/tests/test_skills.py -k "unsafe" -v
```

Expected: new tests fail because validation does not exist yet.

- [ ] **Step 5: Implement safe validation helpers**

In `mcp_sync/src/mcp_sync/skills.py`, add helpers with these semantics:

```python
_SAFE_SKILL_NAME_RE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._-]*$")


def _validate_skill_name(name: str) -> None:
    if not isinstance(name, str) or not _SAFE_SKILL_NAME_RE.fullmatch(name):
        raise ValueError(f"unsafe skill name: {name!r}")


def _validate_relative_manifest_path(path_text: str, *, label: str) -> None:
    path = Path(path_text)
    if path.is_absolute() or any(part in {"", ".", ".."} for part in path.parts):
        raise ValueError(f"unsafe {label}: {path_text!r}")


def _safe_target(root: Path, name: str) -> Path:
    _validate_skill_name(name)
    target = root / name
    root_resolved = root.resolve(strict=False)
    target_resolved = target.resolve(strict=False)
    if root_resolved not in (target_resolved, *target_resolved.parents):
        raise ValueError(f"skill target escapes target root: {name!r}")
    return target
```

Use `_validate_skill_name()` for manifest keys in `resolve_skills()`. Use `_validate_relative_manifest_path()` for git skill paths, explicit local skill paths, and local source default paths. Use `_safe_target()` in `run_skills_sync()` and `garbage_collect()` before deleting or deploying.

- [ ] **Step 6: Make GC skip unsafe historical state**

In `garbage_collect()`, do not raise on invalid historical state keys. Log a message and continue:

```python
try:
    path = _safe_target(target_root, name)
except ValueError:
    log_info(f"Skipping GC of unsafe state entry: {name!r}")
    continue
```

- [ ] **Step 7: Run task verification**

Run:

```bash
uv run --project mcp_sync --group dev pytest mcp_sync/tests/test_skills.py -k "unsafe or garbage_collect" -v
uv run --project mcp_sync --group dev ruff check mcp_sync/src/mcp_sync/skills.py mcp_sync/tests/test_skills.py
```

Expected: all selected tests pass.

- [ ] **Step 8: Commit**

```bash
git add mcp_sync/src/mcp_sync/skills.py mcp_sync/tests/test_skills.py
git commit -m "fix: constrain skill sync paths (#57)"
```

---

### Task 2: Reject Symlinks In Vendored Git Skills

**Files:**
- Modify: `mcp_sync/src/mcp_sync/skills.py`
- Test: `mcp_sync/tests/test_skills.py`

- [ ] **Step 1: Write failing symlink-copy test**

Add this test:

```python
def test_deploy_skill_copy_rejects_symlink_inside_source(tmp_path):
    src = _make_skill(tmp_path / "src", "tdd")
    outside = tmp_path / "outside-secret"
    outside.write_text("secret")
    (src / "leak").symlink_to(outside)
    target = tmp_path / "claude" / "skills" / "tdd"

    with pytest.raises(ValueError, match="symlink"):
        deploy_skill(src, target, "copy")

    assert not target.exists()
```

- [ ] **Step 2: Run test to verify failure**

Run:

```bash
uv run --project mcp_sync --group dev pytest mcp_sync/tests/test_skills.py::test_deploy_skill_copy_rejects_symlink_inside_source -v
```

Expected: FAIL because `copytree()` currently follows symlinks.

- [ ] **Step 3: Implement symlink rejection for copy mode**

Add a helper:

```python
def _assert_tree_has_no_symlinks(root: Path) -> None:
    for path in root.rglob("*"):
        if path.is_symlink():
            raise ValueError(f"Refusing to copy symlink from vendored skill: {path}")
```

Call it before copy-mode deployment. Do not apply this rule to local skills deployed as a single symlink from the repo source to `~/.claude/skills/<name>`.

- [ ] **Step 4: Run task verification**

Run:

```bash
uv run --project mcp_sync --group dev pytest mcp_sync/tests/test_skills.py -k "symlink or deploy_skill" -v
uv run --project mcp_sync --group dev ruff check mcp_sync/src/mcp_sync/skills.py mcp_sync/tests/test_skills.py
```

Expected: selected tests pass.

- [ ] **Step 5: Commit**

```bash
git add mcp_sync/src/mcp_sync/skills.py mcp_sync/tests/test_skills.py
git commit -m "fix: reject vendored skill symlinks (#57)"
```

---

### Task 3: Replace Copied Skills Without Deleting The Old Copy First

**Files:**
- Modify: `mcp_sync/src/mcp_sync/skills.py`
- Test: `mcp_sync/tests/test_skills.py`

- [ ] **Step 1: Write failing test for copy failure preservation**

Add this test:

```python
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
```

- [ ] **Step 2: Run test to verify failure**

Run:

```bash
uv run --project mcp_sync --group dev pytest mcp_sync/tests/test_skills.py::test_deploy_skill_copy_failure_keeps_existing_target -v
```

Expected: FAIL because copy-mode currently removes `target` before copying.

- [ ] **Step 3: Implement staged directory replacement**

Use a sibling temp directory and backup directory under `target.parent`. Copy into temp before touching the target. Rename the existing target to backup only after copy succeeds. If the final rename fails, restore the backup.

Required behavior:

```python
def _replace_directory_from_copy(src: Path, target: Path) -> None:
    target.parent.mkdir(parents=True, exist_ok=True)
    tmp = target.parent / f".{target.name}.tmp-{os.getpid()}-{uuid.uuid4().hex}"
    backup = target.parent / f".{target.name}.bak-{os.getpid()}-{uuid.uuid4().hex}"
    try:
        shutil.copytree(src, tmp)
        if target.exists() or target.is_symlink():
            target.rename(backup)
        tmp.rename(target)
    except Exception:
        if not target.exists() and backup.exists():
            backup.rename(target)
        raise
    finally:
        _remove_path(tmp)
        _remove_path(backup)
```

Import `os` and `uuid`. Keep `_assert_tree_has_no_symlinks(src)` before the staged copy.

- [ ] **Step 4: Run task verification**

Run:

```bash
uv run --project mcp_sync --group dev pytest mcp_sync/tests/test_skills.py -k "copy or deploy_skill" -v
uv run --project mcp_sync --group dev ruff check mcp_sync/src/mcp_sync/skills.py mcp_sync/tests/test_skills.py
```

Expected: selected tests pass.

- [ ] **Step 5: Commit**

```bash
git add mcp_sync/src/mcp_sync/skills.py mcp_sync/tests/test_skills.py
git commit -m "fix: stage copied skill replacements (#57)"
```

---

### Task 4: Track Git Source Identity And Handle Git Failures Cleanly

**Files:**
- Modify: `mcp_sync/src/mcp_sync/skills.py`
- Test: `mcp_sync/tests/test_skills.py`

- [ ] **Step 1: Write failing test for ref changes bypassing freshness**

Add this test:

```python
def test_ensure_git_source_refetches_when_ref_changes_even_if_fresh(tmp_path, monkeypatch):
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
```

- [ ] **Step 2: Write failing test for URL changes updating origin**

Add this test:

```python
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
```

- [ ] **Step 3: Write failing orchestration test for git failure preserving local skills**

Add this test:

```python
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
```

- [ ] **Step 4: Run tests to verify failure**

Run:

```bash
uv run --project mcp_sync --group dev pytest mcp_sync/tests/test_skills.py -k "git_failure or ref_changes or url_changes" -v
```

Expected: new tests fail.

- [ ] **Step 5: Implement source identity tracking**

Update `ensure_git_source()` so source state includes `last_fetch`, `url`, and `ref`. Treat a changed `url` or `ref` as stale even when `refreshPeriod` has not expired. When an existing cache's URL changes, run:

```python
_git("remote", "set-url", "origin", url, cwd=cache_dir)
```

Then fetch/reset the requested ref and write:

```python
state.setdefault("sources", {})[name] = {
    "last_fetch": now,
    "url": url,
    "ref": ref,
}
```

- [ ] **Step 6: Implement clean git failure handling**

In `run_skills_sync()`, catch `subprocess.CalledProcessError` around `ensure_git_source()`. Required behavior:

```python
failed_sources: set[str] = set()
for skill in resolved:
    if skill.source_type == "git" and skill.source_name not in git_caches:
        try:
            git_caches[skill.source_name] = ensure_git_source(...)
        except subprocess.CalledProcessError as exc:
            log_error(f"Git source {skill.source_name!r} failed: {exc}")
            failed = True
            cache_dir = cache_root / skill.source_name
            if cache_dir.is_dir():
                log_info(f"Using stale cache for source {skill.source_name!r}")
                git_caches[skill.source_name] = cache_dir
            else:
                failed_sources.add(skill.source_name)
```

During deployment, if `skill.source_name in failed_sources`, log an error, keep prior state for that skill if present, and continue.

- [ ] **Step 7: Run task verification**

Run:

```bash
uv run --project mcp_sync --group dev pytest mcp_sync/tests/test_skills.py -k "git or source or run_skills_sync" -v
uv run --project mcp_sync --group dev ruff check mcp_sync/src/mcp_sync/skills.py mcp_sync/tests/test_skills.py
```

Expected: selected tests pass.

- [ ] **Step 8: Commit**

```bash
git add mcp_sync/src/mcp_sync/skills.py mcp_sync/tests/test_skills.py
git commit -m "fix: refresh changed skill sources safely (#57)"
```

---

### Task 5: Pin Third-Party Skills And Make Work/Lab Policy Explicit

**Files:**
- Modify: `dot_config/skills/skills-master.json`
- Modify: `dot_config/skills/machine/work.json`
- Modify: `dot_config/skills/machine/lab.json`
- Test: `mcp_sync/tests/test_skills.py`

- [ ] **Step 1: Pin the mattpocock source**

Change `dot_config/skills/skills-master.json` source `mattpocock.ref` from `main` to the reviewed SHA:

```json
"ref": "e74f0061bb67222181640effa98c675bdb2fdaa7"
```

This SHA was resolved from `https://github.com/mattpocock/skills` `main` on 2026-05-18 using:

```bash
git ls-remote https://github.com/mattpocock/skills HEAD refs/heads/main
```

- [ ] **Step 2: Disable third-party skills on work**

Replace `dot_config/skills/machine/work.json` with:

```json
{
  "skills": {
    "caveman": false,
    "edit-article": false,
    "git-guardrails-claude-code": false,
    "grill-me": false,
    "grill-with-docs": false,
    "improve-codebase-architecture": false,
    "migrate-to-shoehorn": false,
    "obsidian-vault": false,
    "scaffold-exercises": false,
    "setup-pre-commit": false,
    "tdd": false,
    "to-issues": false,
    "to-prd": false,
    "triage": false,
    "write-a-skill": false,
    "zoom-out": false
  }
}
```

- [ ] **Step 3: Disable third-party skills on lab**

Replace `dot_config/skills/machine/lab.json` with the same JSON object used for `work.json`.

- [ ] **Step 4: Keep personal policy explicit**

Leave `dot_config/skills/machine/personal.json` as:

```json
{ "skills": {} }
```

Personal machines receive the pinned third-party allow-list plus `refactor`.

- [ ] **Step 5: Add manifest policy regression test**

Add this test:

```python
def test_work_and_lab_overlays_disable_all_git_sourced_skills():
    repo = Path(__file__).resolve().parents[2]
    manifest = load_skills_manifest(repo / "dot_config" / "skills" / "skills-master.json")
    git_skills = {
        name
        for name, entry in manifest["skills"].items()
        if entry is not False
        and manifest["sources"][entry["source"]]["type"] == "git"
    }

    for overlay_name in ("work.json", "lab.json"):
        overlay = json.loads(
            (repo / "dot_config" / "skills" / "machine" / overlay_name).read_text()
        )
        disabled = {
            name for name, value in overlay["skills"].items() if value is False
        }
        assert disabled == git_skills
```

Add `from pathlib import Path` to the test imports if it is not already present.

- [ ] **Step 6: Run task verification**

Run:

```bash
python3 -m json.tool dot_config/skills/skills-master.json >/dev/null
python3 -m json.tool dot_config/skills/machine/work.json >/dev/null
python3 -m json.tool dot_config/skills/machine/lab.json >/dev/null
uv run --project mcp_sync --group dev pytest mcp_sync/tests/test_skills.py::test_work_and_lab_overlays_disable_all_git_sourced_skills -v
```

Expected: JSON is valid and the policy test passes.

- [ ] **Step 7: Commit**

```bash
git add dot_config/skills/skills-master.json dot_config/skills/machine/work.json dot_config/skills/machine/lab.json mcp_sync/tests/test_skills.py
git commit -m "fix: pin third-party skills policy (#57)"
```

---

### Task 6: Return Clean Errors For Bad Manifests And Overlays

**Files:**
- Modify: `mcp_sync/src/mcp_sync/skills.py`
- Test: `mcp_sync/tests/test_skills.py`

- [ ] **Step 1: Write failing bad-manifest orchestration test**

Add this test:

```python
def test_run_skills_sync_non_object_manifest_returns_1(tmp_path):
    home = tmp_path / "home"
    manifest = home / ".config" / "skills" / "skills-master.json"
    _write_json(manifest, [])

    assert run_skills_sync(home=home, repo_root=tmp_path, now=1.0) == 1
```

- [ ] **Step 2: Write failing bad-overlay orchestration test**

Add this test:

```python
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
        run_skills_sync(
            home=home, repo_root=repo, machine_config_path=overlay, now=1.0
        )
        == 1
    )
```

- [ ] **Step 3: Run tests to verify failure**

Run:

```bash
uv run --project mcp_sync --group dev pytest mcp_sync/tests/test_skills.py -k "non_object" -v
```

Expected: new tests fail with an uncaught exception.

- [ ] **Step 4: Catch config load/shape errors in `run_skills_sync()`**

Wrap master manifest and overlay loading so `json.JSONDecodeError`, `OSError`, and `ValueError` return `1` with `log_error(...)`. Validate overlay root is a dict before calling `deep_merge()`.

Required behavior:

```python
try:
    manifest = load_skills_manifest(manifest_file)
except (json.JSONDecodeError, OSError, ValueError) as exc:
    log_error(f"Manifest error: {exc}")
    return 1
```

For overlays:

```python
if not isinstance(overlay, dict):
    log_error(f"Machine overlay root must be an object: {machine_config_path}")
    return 1
```

- [ ] **Step 5: Run task verification**

Run:

```bash
uv run --project mcp_sync --group dev pytest mcp_sync/tests/test_skills.py -k "manifest or overlay or non_object" -v
uv run --project mcp_sync --group dev ruff check mcp_sync/src/mcp_sync/skills.py mcp_sync/tests/test_skills.py
```

Expected: selected tests pass.

- [ ] **Step 6: Commit**

```bash
git add mcp_sync/src/mcp_sync/skills.py mcp_sync/tests/test_skills.py
git commit -m "fix: report skill manifest errors cleanly (#57)"
```

---

### Task 7: Cover Real Entrypoints, CI Paths, And Git Working Directories

**Files:**
- Modify: `.github/workflows/mcp-sync-ci.yml`
- Modify: `mcp_sync/tests/test_skills.py`
- Modify: `mcp_sync/tests/test_skills_cli.py`

- [ ] **Step 1: Verify `_git` cwd in tests**

Update existing `ensure_git_source` tests to capture args and kwargs:

```python
calls = []
monkeypatch.setattr(skills_mod, "_git", lambda *a, **k: calls.append((a, k)))
```

Assert fetch/reset use the cache directory:

```python
assert (
    ("fetch", "origin", "main"),
    {"cwd": cache_root / "mattpocock"},
) in calls
assert (
    ("reset", "--hard", "FETCH_HEAD"),
    {"cwd": cache_root / "mattpocock"},
) in calls
```

- [ ] **Step 2: Add console-script smoke test**

Add this test to `mcp_sync/tests/test_skills_cli.py`:

```python
import subprocess


def test_sync_skills_console_script_is_installed():
    result = subprocess.run(
        ["sync-skills", "--help"],
        check=False,
        capture_output=True,
        text=True,
    )
    assert result.returncode == 0
    assert "Sync Claude Code skills" in result.stdout
```

This verifies the installed console script is available in the `uv run` environment. CI should also invoke the script directly in Step 4.

- [ ] **Step 3: Update mcp-sync CI path filters**

In `.github/workflows/mcp-sync-ci.yml`, add these paths to both `push.paths` and `pull_request.paths`:

```yaml
      - ".chezmoidata/machines.toml"
      - ".chezmoiignore"
      - ".chezmoiscripts/run_after_sync-skills.sh.tmpl"
      - "skills/**"
```

- [ ] **Step 4: Add installed entrypoint CI command**

In the CI test job, replace the single test command with:

```yaml
      - name: Run tests
        working-directory: mcp_sync
        run: |
          uv run --group dev pytest --cov=mcp_sync --cov-report=term-missing
          uv run --group dev sync-skills --help
```

- [ ] **Step 5: Run task verification**

Run:

```bash
uv run --project mcp_sync --group dev pytest mcp_sync/tests/test_skills.py mcp_sync/tests/test_skills_cli.py -v
pre-commit run check-yaml --files .github/workflows/mcp-sync-ci.yml
```

Expected: tests pass and workflow YAML parses.

- [ ] **Step 6: Commit**

```bash
git add .github/workflows/mcp-sync-ci.yml mcp_sync/tests/test_skills.py mcp_sync/tests/test_skills_cli.py
git commit -m "test: cover skill sync entrypoints (#57)"
```

---

### Task 8: Narrow README Migration Cleanup

**Files:**
- Modify: `mcp_sync/README.md`

- [ ] **Step 1: Replace broad dangling-symlink cleanup**

Replace the cleanup block with a target-checked version:

```bash
# Remove only dangling symlinks whose stored target points into ~/.agents/skills/.
for link in ~/.claude/skills/*; do
  [ -L "$link" ] || continue
  target="$(readlink "$link")"
  case "$target" in
    "$HOME/.agents/skills/"*|~/.agents/skills/*)
      [ -e "$link" ] || rm -v "$link"
      ;;
  esac
done
```

- [ ] **Step 2: Replace `rm -rf ~/.agents` with a reviewed move**

Use this text:

Do not delete `~/.agents` wholesale. After confirming nothing else uses it, move
the old skills directory aside first:

```bash
mv ~/.agents/skills ~/.agents/skills.retired-$(date +%Y%m%d)
```

- [ ] **Step 3: Run task verification**

Run:

```bash
rg -n "rm -rf ~/.agents|dangling" mcp_sync/README.md
```

Expected: no `rm -rf ~/.agents`; cleanup text says it only removes links targeting `~/.agents/skills/`.

- [ ] **Step 4: Commit**

```bash
git add mcp_sync/README.md
git commit -m "docs: narrow skill migration cleanup (#57)"
```

---

### Task 9: Select The Expected Machine Overlay In The Hook

**Files:**
- Modify: `.chezmoiscripts/run_after_sync-skills.sh.tmpl`

- [ ] **Step 1: Replace glob-first overlay detection**

Replace the `for f in "${MACHINE_DIR}"/*.json` block with a template-rendered expected overlay:

```bash
  MACHINE_OVERLAY=""
  {{- if hasPrefix "personal" .machine }}
  MACHINE_OVERLAY="${MACHINE_DIR}/personal.json"
  {{- else if hasPrefix "work" .machine }}
  MACHINE_OVERLAY="${MACHINE_DIR}/work.json"
  {{- else if eq .machine "lab-mac" }}
  MACHINE_OVERLAY="${MACHINE_DIR}/lab.json"
  {{- end }}

  if [[ -n "${MACHINE_OVERLAY}" && -f "${MACHINE_OVERLAY}" ]]; then
    sync_cmd+=(--machine-config "${MACHINE_OVERLAY}")
  fi
```

This avoids passing stale overlays left on disk from a prior machine type.

- [ ] **Step 2: Render hook for all current machines**

Run:

```bash
chezmoi execute-template --override-data '{"machine":"personal-mac"}' --file .chezmoiscripts/run_after_sync-skills.sh.tmpl | bash -n
chezmoi execute-template --override-data '{"machine":"work-mac"}' --file .chezmoiscripts/run_after_sync-skills.sh.tmpl | bash -n
chezmoi execute-template --override-data '{"machine":"lab-mac"}' --file .chezmoiscripts/run_after_sync-skills.sh.tmpl | bash -n
```

Expected: all render and pass `bash -n`.

- [ ] **Step 3: Commit**

```bash
git add .chezmoiscripts/run_after_sync-skills.sh.tmpl
git commit -m "fix: select expected skill overlay (#57)"
```

---

### Task 10: Make Copy-Mode GC Prove Ownership Before Deleting

**Files:**
- Modify: `mcp_sync/src/mcp_sync/skills.py`
- Test: `mcp_sync/tests/test_skills.py`

- [ ] **Step 1: Write failing test for replaced copied directory**

Add this test:

```python
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
```

- [ ] **Step 2: Write passing-target marker test**

Add this test:

```python
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
```

- [ ] **Step 3: Run tests to verify failure**

Run:

```bash
uv run --project mcp_sync --group dev pytest mcp_sync/tests/test_skills.py -k "marker or replaced_copy" -v
```

Expected: new marker behavior fails.

- [ ] **Step 4: Add copy ownership marker**

When deploying a copy-mode skill, write a marker file under the copied target:

```python
_MANAGED_MARKER = ".mcp-sync-managed"
_MANAGED_MARKER_VALUE = "mcp-sync-managed-v1"
```

After the staged copy is in place:

```python
(target / _MANAGED_MARKER).write_text(_MANAGED_MARKER_VALUE + "\n", encoding="utf-8")
```

Record the marker in state for copy-mode deployed skills:

```python
"marker": _MANAGED_MARKER_VALUE
```

- [ ] **Step 5: Require marker match before copy-mode GC**

In `garbage_collect()`, for `mode == "copy"`, delete only if:

```python
marker = path / _MANAGED_MARKER
marker.is_file()
and marker.read_text(encoding="utf-8").strip() == record.get("marker")
```

If the marker is absent or mismatched, log and skip deletion.

- [ ] **Step 6: Preserve backward safety**

Existing state entries without `marker` must not delete copy-mode directories. This is safer than trying to infer ownership from the old state shape.

- [ ] **Step 7: Run task verification**

Run:

```bash
uv run --project mcp_sync --group dev pytest mcp_sync/tests/test_skills.py -k "garbage_collect or deploy_skill or run_skills_sync" -v
uv run --project mcp_sync --group dev ruff check mcp_sync/src/mcp_sync/skills.py mcp_sync/tests/test_skills.py
```

Expected: selected tests pass.

- [ ] **Step 8: Commit**

```bash
git add mcp_sync/src/mcp_sync/skills.py mcp_sync/tests/test_skills.py
git commit -m "fix: prove copied skill ownership before gc (#57)"
```

---

### Task 11: Final Integration Verification

**Files:**
- Read: all changed files

- [ ] **Step 1: Run Python verification**

Run:

```bash
uv run --project mcp_sync --group dev ruff check mcp_sync/src mcp_sync/tests
uv run --project mcp_sync --group dev ruff format --check mcp_sync/src mcp_sync/tests
uv run --project mcp_sync --group dev pytest mcp_sync/tests --cov=mcp_sync --cov-report=term-missing
```

Expected: all pass.

- [ ] **Step 2: Run repo hygiene**

Run:

```bash
pre-commit run --all-files
```

Expected: all hooks pass.

- [ ] **Step 3: Render Chezmoi hook syntax**

Run:

```bash
chezmoi execute-template --override-data '{"machine":"personal-mac"}' --file .chezmoiscripts/run_after_sync-skills.sh.tmpl | bash -n
chezmoi execute-template --override-data '{"machine":"work-mac"}' --file .chezmoiscripts/run_after_sync-skills.sh.tmpl | bash -n
chezmoi execute-template --override-data '{"machine":"lab-mac"}' --file .chezmoiscripts/run_after_sync-skills.sh.tmpl | bash -n
```

Expected: all pass.

- [ ] **Step 4: Sandbox sync for personal policy**

Run:

```bash
tmp_home="$(mktemp -d -t skill-sync-personal.XXXXXX)"
mkdir -p "$tmp_home/.config/skills/machine"
cp dot_config/skills/skills-master.json "$tmp_home/.config/skills/skills-master.json"
cp dot_config/skills/machine/personal.json "$tmp_home/.config/skills/machine/personal.json"
uv run --project mcp_sync sync-skills --home "$tmp_home" --repo-root "$PWD" --machine-config "$tmp_home/.config/skills/machine/personal.json"
find "$tmp_home/.claude/skills" -maxdepth 1 -mindepth 1 -print | sort
rm -rf "$tmp_home"
```

Expected: personal sync deploys pinned third-party skills plus the `refactor` symlink.

- [ ] **Step 5: Sandbox sync for work policy**

Run:

```bash
tmp_home="$(mktemp -d -t skill-sync-work.XXXXXX)"
mkdir -p "$tmp_home/.config/skills/machine"
cp dot_config/skills/skills-master.json "$tmp_home/.config/skills/skills-master.json"
cp dot_config/skills/machine/work.json "$tmp_home/.config/skills/machine/work.json"
uv run --project mcp_sync sync-skills --home "$tmp_home" --repo-root "$PWD" --machine-config "$tmp_home/.config/skills/machine/work.json"
find "$tmp_home/.claude/skills" -maxdepth 1 -mindepth 1 -print | sort
rm -rf "$tmp_home"
```

Expected: work sync deploys only `refactor`; no mattpocock skills appear.

- [ ] **Step 6: Confirm review finding closure**

Run:

```bash
rg -n "main|rm -rf ~/.agents|for f in.*skills/machine|copytree\\(src, target\\)|target_root / name" dot_config/skills mcp_sync .chezmoiscripts
```

Expected: no unsafe floating `main`, broad cleanup, glob-first overlay detection, direct destructive copy, or direct `target_root / name` path construction remains.

- [ ] **Step 7: Commit final docs if updated**

If verification changes docs or comments:

```bash
git add .
git commit -m "docs: record skill sync remediation evidence (#57)"
```

---

## Handoff Notes

- The highest-risk tasks are Task 1, Task 2, Task 4, Task 5, and Task 10. Do those before merge.
- Task 5 intentionally keeps third-party skills on personal machines only. If work or lab should receive a specific third-party skill later, add that skill back explicitly in that machine overlay after reviewing the pinned source content.
- The final PR should mention that old copy-mode state without ownership markers is now treated conservatively and will not be garbage-collected automatically.
