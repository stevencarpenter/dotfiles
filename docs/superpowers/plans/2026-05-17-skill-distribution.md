# Skill Distribution Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Extend `mcp_sync` with a `sync-skills` command that deploys Claude Code skills — vendored from mattpocock's repo and personal skills from this repo — to `~/.claude/skills/`, machine-gated and reproducible from `chezmoi apply`.

**Architecture:** A new `mcp_sync.skills` module reads `~/.config/skills/skills-master.json` (plus a machine overlay), clones git sources into `~/.cache/mcp-sync/skills/`, copies vendored skills and symlinks personal skills into `~/.claude/skills/`, and garbage-collects orphans via a state file at `~/.local/state/mcp-sync/skills-state.json`. A post-apply chezmoi hook runs it, gated on a new `skills` machine capability.

**Tech Stack:** Python 3.14, `uv`, `pytest`, `ruff`, chezmoi Go templates, bash.

**Reference:** Design spec at `docs/superpowers/specs/2026-05-17-skill-distribution-design.md`.

---

## File Structure

| File | Responsibility |
|------|----------------|
| `mcp_sync/src/mcp_sync/skills.py` | Core: manifest load, resolution, git/local sources, deploy, GC, orchestration |
| `mcp_sync/src/mcp_sync/skills_cli.py` | `sync-skills` argument parsing |
| `mcp_sync/tests/test_skills.py` | Unit + integration tests for `skills.py` |
| `mcp_sync/tests/test_skills_cli.py` | Tests for the CLI |
| `mcp_sync/pyproject.toml` | Adds the `sync-skills` entry point (modify) |
| `dot_config/skills/skills-master.json` | The skill manifest |
| `dot_config/skills/machine/{personal,work,lab}.json` | Machine overlays |
| `.chezmoiscripts/run_after_sync-skills.sh.tmpl` | Post-apply hook |
| `.chezmoidata/machines.toml` | New `skills` capability (modify) |
| `.chezmoiignore` | Ignore repo `skills/`, gate `.config/skills`, rewrite comment (modify) |
| `.github/workflows/mcp-sync-ci.yml` | Path filter for `dot_config/skills/**` (modify) |
| `mcp_sync/README.md` | Document `sync-skills` + one-time cleanup (modify) |
| `skills/personal/refactor/` | Migrated personal skill (move) |
| `.claude/skills/{chezmoi-verify,mcp-sync-verify,machine-capability-audit}/` | Migrated project skills (move) |

Commands run from the repo root `~/.local/share/chezmoi` unless noted. The Python test command is:
`uv run --project mcp_sync --group dev pytest mcp_sync/tests -v`

---

## Task 1: Duration parsing

**Files:**
- Create: `mcp_sync/src/mcp_sync/skills.py`
- Test: `mcp_sync/tests/test_skills.py`

- [ ] **Step 1: Write the failing test**

Create `mcp_sync/tests/test_skills.py`:

```python
"""Tests for the skill synchronization module."""

from __future__ import annotations

import pytest

from mcp_sync.skills import parse_duration


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
```

- [ ] **Step 2: Run test to verify it fails**

Run: `uv run --project mcp_sync --group dev pytest mcp_sync/tests/test_skills.py -v`
Expected: FAIL — `ModuleNotFoundError: No module named 'mcp_sync.skills'`

- [ ] **Step 3: Write minimal implementation**

Create `mcp_sync/src/mcp_sync/skills.py`:

```python
"""Claude Code skill synchronization: vendored + personal, machine-gated."""

from __future__ import annotations

import re

_DURATION_UNITS = {"s": 1, "m": 60, "h": 3600, "d": 86400}
_DURATION_RE = re.compile(r"^(\d+)([smhd])$")

DEFAULT_REFRESH = "168h"
DEFAULT_REF = "main"


def parse_duration(text: str) -> int:
    """Parse a single-unit duration (e.g. '168h', '7d') into seconds.

    Args:
        text: A duration string of the form ``<integer><unit>`` where unit is
            one of ``s``, ``m``, ``h``, ``d``.

    Returns:
        The duration expressed in seconds.

    Raises:
        ValueError: If the string is not a recognized duration.
    """
    match = _DURATION_RE.match(text.strip())
    if not match:
        raise ValueError(f"Invalid duration: {text!r}")
    amount, unit = match.groups()
    return int(amount) * _DURATION_UNITS[unit]
```

- [ ] **Step 4: Run test to verify it passes**

Run: `uv run --project mcp_sync --group dev pytest mcp_sync/tests/test_skills.py -v`
Expected: PASS (4 tests)

- [ ] **Step 5: Lint and commit**

```bash
uv run --project mcp_sync --group dev ruff check --fix mcp_sync/src mcp_sync/tests
uv run --project mcp_sync --group dev ruff format mcp_sync/src mcp_sync/tests
git add mcp_sync/src/mcp_sync/skills.py mcp_sync/tests/test_skills.py
git commit -m "feat: add duration parsing for skill sync (#57)"
```

---

## Task 2: Manifest loading

**Files:**
- Modify: `mcp_sync/src/mcp_sync/skills.py`
- Test: `mcp_sync/tests/test_skills.py`

- [ ] **Step 1: Write the failing test**

Add these lines to the import block at the top of `mcp_sync/tests/test_skills.py` (keep all imports at the top; `ruff check --fix` sorts them):

```python
import json

from mcp_sync.skills import load_skills_manifest
```

Then append these test functions to the end of the file:

```python
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
```

- [ ] **Step 2: Run test to verify it fails**

Run: `uv run --project mcp_sync --group dev pytest mcp_sync/tests/test_skills.py -v`
Expected: FAIL — `ImportError: cannot import name 'load_skills_manifest'`

- [ ] **Step 3: Write minimal implementation**

In `mcp_sync/src/mcp_sync/skills.py`, add `import json`, `from pathlib import Path`, and `from typing import Any` to the imports, add the `JsonDict` type alias after the imports, and append the function:

```python
type JsonDict = dict[str, Any]


def load_skills_manifest(path: Path) -> JsonDict:
    """Load and minimally validate the skills master manifest.

    Args:
        path: Path to ``skills-master.json``.

    Returns:
        The manifest with ``sources`` and ``skills`` keys guaranteed present.

    Raises:
        ValueError: If the JSON root is not an object.
    """
    with open(path, encoding="utf-8") as handle:
        data = json.load(handle)
    if not isinstance(data, dict):
        raise ValueError(f"Manifest root must be an object: {path}")
    data.setdefault("sources", {})
    data.setdefault("skills", {})
    return data
```

- [ ] **Step 4: Run test to verify it passes**

Run: `uv run --project mcp_sync --group dev pytest mcp_sync/tests/test_skills.py -v`
Expected: PASS (7 tests)

- [ ] **Step 5: Lint and commit**

```bash
uv run --project mcp_sync --group dev ruff check --fix mcp_sync/src mcp_sync/tests
uv run --project mcp_sync --group dev ruff format mcp_sync/src mcp_sync/tests
git add mcp_sync/src/mcp_sync/skills.py mcp_sync/tests/test_skills.py
git commit -m "feat: load skills manifest (#57)"
```

---

## Task 3: Skill resolution

**Files:**
- Modify: `mcp_sync/src/mcp_sync/skills.py`
- Test: `mcp_sync/tests/test_skills.py`

- [ ] **Step 1: Write the failing test**

Add this line to the import block at the top of `mcp_sync/tests/test_skills.py`:

```python
from mcp_sync.skills import ResolvedSkill, resolve_skills
```

Then append these test functions and helper to the end of the file:

```python
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
```

- [ ] **Step 2: Run test to verify it fails**

Run: `uv run --project mcp_sync --group dev pytest mcp_sync/tests/test_skills.py -v`
Expected: FAIL — `ImportError: cannot import name 'ResolvedSkill'`

- [ ] **Step 3: Write minimal implementation**

In `mcp_sync/src/mcp_sync/skills.py`, add `from dataclasses import dataclass` to the imports, and append:

```python
@dataclass(frozen=True, slots=True)
class ResolvedSkill:
    """A skill resolved from the manifest, ready to deploy.

    Attributes:
        name: Deployed directory name under ``~/.claude/skills/`` (manifest key).
        source_name: Name of the source this skill comes from.
        source_type: ``"git"`` or ``"local"``.
        subpath: For git sources, the skill directory within the cloned repo.
            For local sources, the path relative to the chezmoi repo root.
        mode: ``"copy"`` (git) or ``"symlink"`` (local).
    """

    name: str
    source_name: str
    source_type: str
    subpath: str
    mode: str


def resolve_skills(manifest: JsonDict) -> list[ResolvedSkill]:
    """Resolve the manifest's skill map into a deployable list.

    Args:
        manifest: The merged manifest (master config + machine overlay).

    Returns:
        Resolved skills sorted by name, excluding any disabled via an
        overlay ``false`` value.

    Raises:
        ValueError: If a skill references an unknown source, a git-sourced
            skill omits the required ``path``, or a source has an invalid type.
    """
    sources = manifest.get("sources", {})
    resolved: list[ResolvedSkill] = []
    for name, entry in sorted(manifest.get("skills", {}).items()):
        if entry is False:
            continue
        if not isinstance(entry, dict):
            raise ValueError(f"Skill {name!r} must be an object or false")
        source_name = entry.get("source")
        if source_name not in sources:
            raise ValueError(
                f"Skill {name!r} references unknown source {source_name!r}"
            )
        source = sources[source_name]
        source_type = source.get("type")
        if source_type == "git":
            subpath = entry.get("path")
            if not subpath:
                raise ValueError(f"Git-sourced skill {name!r} requires a 'path'")
            mode = "copy"
        elif source_type == "local":
            subpath = entry.get("path") or f"{source['path']}/{name}"
            mode = "symlink"
        else:
            raise ValueError(
                f"Source {source_name!r} has invalid type {source_type!r}"
            )
        resolved.append(
            ResolvedSkill(name, source_name, source_type, subpath, mode)
        )
    return resolved
```

- [ ] **Step 4: Run test to verify it passes**

Run: `uv run --project mcp_sync --group dev pytest mcp_sync/tests/test_skills.py -v`
Expected: PASS (12 tests)

- [ ] **Step 5: Lint and commit**

```bash
uv run --project mcp_sync --group dev ruff check --fix mcp_sync/src mcp_sync/tests
uv run --project mcp_sync --group dev ruff format mcp_sync/src mcp_sync/tests
git add mcp_sync/src/mcp_sync/skills.py mcp_sync/tests/test_skills.py
git commit -m "feat: resolve skill manifest entries (#57)"
```

---

## Task 4: State file load/write

**Files:**
- Modify: `mcp_sync/src/mcp_sync/skills.py`
- Test: `mcp_sync/tests/test_skills.py`

- [ ] **Step 1: Write the failing test**

Add this line to the import block at the top of `mcp_sync/tests/test_skills.py`:

```python
from mcp_sync.skills import load_state, write_state
```

Then append these test functions to the end of the file:

```python
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
```

- [ ] **Step 2: Run test to verify it fails**

Run: `uv run --project mcp_sync --group dev pytest mcp_sync/tests/test_skills.py -v`
Expected: FAIL — `ImportError: cannot import name 'load_state'`

- [ ] **Step 3: Write minimal implementation**

In `mcp_sync/src/mcp_sync/skills.py`, add `from mcp_sync.sync import log_info` to the imports, and append:

```python
def load_state(path: Path) -> JsonDict:
    """Load the sync state file, returning an empty skeleton if absent/invalid.

    Args:
        path: Path to ``skills-state.json``.

    Returns:
        A dict with ``deployed`` and ``sources`` keys guaranteed present.
    """
    if not path.is_file():
        return {"deployed": {}, "sources": {}}
    try:
        with open(path, encoding="utf-8") as handle:
            data = json.load(handle)
    except (json.JSONDecodeError, OSError):
        log_info(f"Ignoring unreadable state file: {path}")
        return {"deployed": {}, "sources": {}}
    data.setdefault("deployed", {})
    data.setdefault("sources", {})
    return data


def write_state(path: Path, state: JsonDict) -> None:
    """Persist the sync state file with deterministic key ordering.

    Args:
        path: Destination path; parent directories are created as needed.
        state: The state mapping to serialize.
    """
    path.parent.mkdir(parents=True, exist_ok=True)
    serialized = json.dumps(state, indent=2, sort_keys=True)
    path.write_text(serialized + "\n", encoding="utf-8")
```

- [ ] **Step 4: Run test to verify it passes**

Run: `uv run --project mcp_sync --group dev pytest mcp_sync/tests/test_skills.py -v`
Expected: PASS (15 tests)

- [ ] **Step 5: Lint and commit**

```bash
uv run --project mcp_sync --group dev ruff check --fix mcp_sync/src mcp_sync/tests
uv run --project mcp_sync --group dev ruff format mcp_sync/src mcp_sync/tests
git add mcp_sync/src/mcp_sync/skills.py mcp_sync/tests/test_skills.py
git commit -m "feat: persist skill sync state (#57)"
```

---

## Task 5: Git source fetching

**Files:**
- Modify: `mcp_sync/src/mcp_sync/skills.py`
- Test: `mcp_sync/tests/test_skills.py`

- [ ] **Step 1: Write the failing test**

Add these lines to the import block at the top of `mcp_sync/tests/test_skills.py`:

```python
import mcp_sync.skills as skills_mod
from mcp_sync.skills import ensure_git_source
```

Then append these test functions to the end of the file:

```python
def test_ensure_git_source_clones_when_cache_absent(tmp_path, monkeypatch):
    calls = []
    monkeypatch.setattr(skills_mod, "_git", lambda *a, **k: calls.append((a, k)))
    cache_root = tmp_path / "cache"
    source = {"type": "git", "url": "https://example.com/x", "ref": "main"}
    state = {"deployed": {}, "sources": {}}
    result = ensure_git_source("mattpocock", source, cache_root, state, now=1000.0)
    assert result == cache_root / "mattpocock"
    assert calls[0][0] == (
        "clone",
        "https://example.com/x",
        str(cache_root / "mattpocock"),
    )
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
```

- [ ] **Step 2: Run test to verify it fails**

Run: `uv run --project mcp_sync --group dev pytest mcp_sync/tests/test_skills.py -v`
Expected: FAIL — `ImportError: cannot import name 'ensure_git_source'`

- [ ] **Step 3: Write minimal implementation**

In `mcp_sync/src/mcp_sync/skills.py`, add `import subprocess` to the imports, and append:

```python
def _git(*args: str, cwd: Path | None = None) -> None:
    """Run a git command, raising ``CalledProcessError`` on failure.

    Args:
        *args: Arguments passed to ``git``.
        cwd: Working directory for the command.
    """
    subprocess.run(
        ["git", *args],
        cwd=cwd,
        check=True,
        capture_output=True,
        text=True,
    )


def ensure_git_source(
    name: str,
    source: JsonDict,
    cache_root: Path,
    state: JsonDict,
    now: float,
) -> Path:
    """Ensure a git source is cloned and current within its refresh period.

    Skips all network access when the cached clone was fetched more recently
    than ``refreshPeriod``. On a fetch, mutates
    ``state["sources"][name]["last_fetch"]`` to ``now``.

    Args:
        name: Source name (also the cache subdirectory name).
        source: The source definition (``url``, optional ``ref`` and
            ``refreshPeriod``).
        cache_root: Root directory for source clones.
        state: The mutable sync state mapping.
        now: Current time as epoch seconds.

    Returns:
        Path to the cached clone.
    """
    cache_dir = cache_root / name
    ref = source.get("ref", DEFAULT_REF)
    refresh_s = parse_duration(source.get("refreshPeriod", DEFAULT_REFRESH))
    last_fetch = state.get("sources", {}).get(name, {}).get("last_fetch", 0)

    if cache_dir.is_dir() and (now - last_fetch) < refresh_s:
        log_info(f"Source {name!r} cache is fresh; skipping fetch")
        return cache_dir

    if not cache_dir.is_dir():
        cache_dir.parent.mkdir(parents=True, exist_ok=True)
        log_info(f"Cloning source {name!r} from {source['url']}")
        _git("clone", source["url"], str(cache_dir))
    log_info(f"Fetching source {name!r} at ref {ref!r}")
    _git("fetch", "origin", ref, cwd=cache_dir)
    _git("reset", "--hard", "FETCH_HEAD", cwd=cache_dir)

    state.setdefault("sources", {})[name] = {"last_fetch": now}
    return cache_dir
```

- [ ] **Step 4: Run test to verify it passes**

Run: `uv run --project mcp_sync --group dev pytest mcp_sync/tests/test_skills.py -v`
Expected: PASS (18 tests)

- [ ] **Step 5: Lint and commit**

```bash
uv run --project mcp_sync --group dev ruff check --fix mcp_sync/src mcp_sync/tests
uv run --project mcp_sync --group dev ruff format mcp_sync/src mcp_sync/tests
git add mcp_sync/src/mcp_sync/skills.py mcp_sync/tests/test_skills.py
git commit -m "feat: fetch git skill sources with refresh period (#57)"
```

---

## Task 6: Skill deployment (copy / symlink)

**Files:**
- Modify: `mcp_sync/src/mcp_sync/skills.py`
- Test: `mcp_sync/tests/test_skills.py`

- [ ] **Step 1: Write the failing test**

Add this line to the import block at the top of `mcp_sync/tests/test_skills.py`:

```python
from mcp_sync.skills import deploy_skill
```

Then append these test functions and helper to the end of the file:

```python
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
```

- [ ] **Step 2: Run test to verify it fails**

Run: `uv run --project mcp_sync --group dev pytest mcp_sync/tests/test_skills.py -v`
Expected: FAIL — `ImportError: cannot import name 'deploy_skill'`

- [ ] **Step 3: Write minimal implementation**

In `mcp_sync/src/mcp_sync/skills.py`, add `import shutil` to the imports, and append:

```python
def _remove_path(path: Path) -> None:
    """Remove a file, symlink, or directory tree if it exists."""
    if path.is_symlink() or path.is_file():
        path.unlink()
    elif path.is_dir():
        shutil.rmtree(path)


def deploy_skill(src: Path, target: Path, mode: str) -> None:
    """Deploy one skill directory to its target under ``~/.claude/skills/``.

    Args:
        src: Source skill directory.
        target: Destination directory.
        mode: ``"copy"`` (vendored skills) or ``"symlink"`` (local skills).

    Raises:
        FileNotFoundError: If ``src`` does not exist.
        ValueError: If ``mode`` is neither ``"copy"`` nor ``"symlink"``.
    """
    if not src.is_dir():
        raise FileNotFoundError(f"Skill source not found: {src}")
    target.parent.mkdir(parents=True, exist_ok=True)
    if mode == "symlink":
        if target.is_symlink() and target.resolve() == src.resolve():
            return
        _remove_path(target)
        target.symlink_to(src)
    elif mode == "copy":
        _remove_path(target)
        shutil.copytree(src, target)
    else:
        raise ValueError(f"Unknown deploy mode: {mode!r}")
```

- [ ] **Step 4: Run test to verify it passes**

Run: `uv run --project mcp_sync --group dev pytest mcp_sync/tests/test_skills.py -v`
Expected: PASS (23 tests)

- [ ] **Step 5: Lint and commit**

```bash
uv run --project mcp_sync --group dev ruff check --fix mcp_sync/src mcp_sync/tests
uv run --project mcp_sync --group dev ruff format mcp_sync/src mcp_sync/tests
git add mcp_sync/src/mcp_sync/skills.py mcp_sync/tests/test_skills.py
git commit -m "feat: deploy skills via copy or symlink (#57)"
```

---

## Task 7: Garbage collection

**Files:**
- Modify: `mcp_sync/src/mcp_sync/skills.py`
- Test: `mcp_sync/tests/test_skills.py`

- [ ] **Step 1: Write the failing test**

Add this line to the import block at the top of `mcp_sync/tests/test_skills.py`:

```python
from mcp_sync.skills import garbage_collect
```

Then append these test functions to the end of the file:

```python
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
```

- [ ] **Step 2: Run test to verify it fails**

Run: `uv run --project mcp_sync --group dev pytest mcp_sync/tests/test_skills.py -v`
Expected: FAIL — `ImportError: cannot import name 'garbage_collect'`

- [ ] **Step 3: Write minimal implementation**

Append to `mcp_sync/src/mcp_sync/skills.py`:

```python
def garbage_collect(
    previous: JsonDict,
    current_names: set[str],
    target_root: Path,
) -> list[str]:
    """Remove skills deployed by a prior run but absent from this run.

    An entry is removed only when it still matches the shape the prior run
    recorded — a symlink we created, or a directory we copied. If the user
    has since replaced it with something else, it is logged and left alone.
    Anything the sync never recorded is never inspected.

    Args:
        previous: The prior run's ``state["deployed"]`` mapping.
        current_names: Skill names resolved in this run.
        target_root: The ``~/.claude/skills/`` directory.

    Returns:
        Names that were actually removed, sorted.
    """
    removed: list[str] = []
    for name, record in sorted(previous.items()):
        if name in current_names:
            continue
        path = target_root / name
        if not path.exists() and not path.is_symlink():
            continue
        mode = record.get("mode")
        if mode == "symlink" and path.is_symlink():
            path.unlink()
            removed.append(name)
        elif mode == "copy" and path.is_dir() and not path.is_symlink():
            shutil.rmtree(path)
            removed.append(name)
        else:
            log_info(
                f"Skipping GC of {name!r}: no longer matches recorded mode"
            )
    return removed
```

- [ ] **Step 4: Run test to verify it passes**

Run: `uv run --project mcp_sync --group dev pytest mcp_sync/tests/test_skills.py -v`
Expected: PASS (27 tests)

- [ ] **Step 5: Lint and commit**

```bash
uv run --project mcp_sync --group dev ruff check --fix mcp_sync/src mcp_sync/tests
uv run --project mcp_sync --group dev ruff format mcp_sync/src mcp_sync/tests
git add mcp_sync/src/mcp_sync/skills.py mcp_sync/tests/test_skills.py
git commit -m "feat: garbage-collect orphaned skills (#57)"
```

---

## Task 8: Sync orchestration

**Files:**
- Modify: `mcp_sync/src/mcp_sync/skills.py`
- Test: `mcp_sync/tests/test_skills.py`

- [ ] **Step 1: Write the failing test**

Add this line to the import block at the top of `mcp_sync/tests/test_skills.py`:

```python
from mcp_sync.skills import run_skills_sync
```

Then append these test functions and helper to the end of the file:

```python
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
        home / ".cache" / "mcp-sync" / "skills" / "mattpocock"
        / "skills" / "engineering" / "tdd"
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
    assert written["deployed"]["tdd"] == {"mode": "copy", "source": "mattpocock"}


def test_run_skills_sync_garbage_collects_dropped_skill(tmp_path):
    home = tmp_path / "home"
    repo = tmp_path / "repo"
    refactor = repo / "skills" / "personal" / "refactor"
    refactor.mkdir(parents=True)
    (refactor / "SKILL.md").write_text("# refactor")
    orphan = home / ".claude" / "skills" / "old-skill"
    orphan.mkdir(parents=True)
    (orphan / "SKILL.md").write_text("# old")
    state = home / ".local" / "state" / "mcp-sync" / "skills-state.json"
    _write_json(
        state,
        {
            "deployed": {"old-skill": {"mode": "copy", "source": "mattpocock"}},
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
```

- [ ] **Step 2: Run test to verify it fails**

Run: `uv run --project mcp_sync --group dev pytest mcp_sync/tests/test_skills.py -v`
Expected: FAIL — `ImportError: cannot import name 'run_skills_sync'`

- [ ] **Step 3: Write minimal implementation**

In `mcp_sync/src/mcp_sync/skills.py`, add `import time` to the imports and extend the sync import line to `from mcp_sync.sync import deep_merge, log_error, log_info, log_success`. Then append:

```python
def run_skills_sync(
    manifest_path: Path | None = None,
    machine_config_path: Path | None = None,
    home: Path | None = None,
    repo_root: Path | None = None,
    now: float | None = None,
) -> int:
    """Synchronize ``~/.claude/skills/`` from the skills manifest.

    Args:
        manifest_path: Override for the master manifest path.
        machine_config_path: Optional machine overlay JSON path.
        home: Override for the home directory (testing).
        repo_root: Override for the chezmoi repo root (testing).
        now: Override for the current time as epoch seconds (testing).

    Returns:
        0 on success, 1 on a configuration error.
    """
    home_path = home or Path.home()
    repo = repo_root or home_path / ".local" / "share" / "chezmoi"
    now_ts = now if now is not None else time.time()
    manifest_file = (
        manifest_path
        or home_path / ".config" / "skills" / "skills-master.json"
    )
    if not manifest_file.is_file():
        log_error(f"Skills manifest not found at {manifest_file}")
        log_info("Run 'chezmoi apply' to deploy dotfiles first")
        return 1

    log_info("Syncing Claude skills from manifest...")
    manifest = load_skills_manifest(manifest_file)

    if machine_config_path and machine_config_path.is_file():
        with open(machine_config_path, encoding="utf-8") as handle:
            overlay = json.load(handle)
        log_info(f"Applying machine overlay: {machine_config_path}")
        manifest = deep_merge(manifest, overlay)

    try:
        resolved = resolve_skills(manifest)
    except ValueError as exc:
        log_error(f"Manifest error: {exc}")
        return 1

    cache_root = home_path / ".cache" / "mcp-sync" / "skills"
    state_path = (
        home_path / ".local" / "state" / "mcp-sync" / "skills-state.json"
    )
    target_root = home_path / ".claude" / "skills"
    state = load_state(state_path)
    sources = manifest["sources"]

    git_caches: dict[str, Path] = {}
    for skill in resolved:
        if skill.source_type == "git" and skill.source_name not in git_caches:
            git_caches[skill.source_name] = ensure_git_source(
                skill.source_name,
                sources[skill.source_name],
                cache_root,
                state,
                now_ts,
            )

    deployed: JsonDict = {}
    for skill in resolved:
        if skill.source_type == "git":
            src = git_caches[skill.source_name] / skill.subpath
        else:
            src = repo / skill.subpath
        try:
            deploy_skill(src, target_root / skill.name, skill.mode)
        except FileNotFoundError as exc:
            log_error(str(exc))
            return 1
        deployed[skill.name] = {
            "mode": skill.mode,
            "source": skill.source_name,
        }
        log_success(f"Deployed skill: {skill.name} ({skill.mode})")

    for name in garbage_collect(state.get("deployed", {}), set(deployed), target_root):
        log_success(f"Removed orphaned skill: {name}")

    state["deployed"] = deployed
    write_state(state_path, state)

    print()
    log_success("Skill sync complete!")
    return 0
```

- [ ] **Step 4: Run test to verify it passes**

Run: `uv run --project mcp_sync --group dev pytest mcp_sync/tests/test_skills.py -v`
Expected: PASS (31 tests)

- [ ] **Step 5: Lint and commit**

```bash
uv run --project mcp_sync --group dev ruff check --fix mcp_sync/src mcp_sync/tests
uv run --project mcp_sync --group dev ruff format mcp_sync/src mcp_sync/tests
git add mcp_sync/src/mcp_sync/skills.py mcp_sync/tests/test_skills.py
git commit -m "feat: orchestrate end-to-end skill sync (#57)"
```

---

## Task 9: CLI and entry point

**Files:**
- Create: `mcp_sync/src/mcp_sync/skills_cli.py`
- Create: `mcp_sync/tests/test_skills_cli.py`
- Modify: `mcp_sync/pyproject.toml`

- [ ] **Step 1: Write the failing test**

Create `mcp_sync/tests/test_skills_cli.py`:

```python
"""Tests for the sync-skills CLI."""

from __future__ import annotations

from mcp_sync.skills_cli import build_parser, cli


def test_parser_accepts_all_flags():
    args = build_parser().parse_args(
        [
            "--manifest", "/m.json",
            "--machine-config", "/o.json",
            "--home", "/h",
            "--repo-root", "/r",
        ]
    )
    assert args.manifest.name == "m.json"
    assert args.machine_config.name == "o.json"
    assert args.home.name == "h"
    assert args.repo_root.name == "r"


def test_cli_returns_1_on_missing_manifest(tmp_path):
    assert cli(["--home", str(tmp_path), "--repo-root", str(tmp_path)]) == 1
```

- [ ] **Step 2: Run test to verify it fails**

Run: `uv run --project mcp_sync --group dev pytest mcp_sync/tests/test_skills_cli.py -v`
Expected: FAIL — `ModuleNotFoundError: No module named 'mcp_sync.skills_cli'`

- [ ] **Step 3: Write minimal implementation**

Create `mcp_sync/src/mcp_sync/skills_cli.py`:

```python
"""Command-line interface for skill synchronization."""

from __future__ import annotations

import argparse
from pathlib import Path
from typing import Sequence

from mcp_sync.skills import run_skills_sync


def build_parser() -> argparse.ArgumentParser:
    """Build the ``sync-skills`` argument parser."""
    parser = argparse.ArgumentParser(
        prog="sync-skills",
        description="Sync Claude Code skills to ~/.claude/skills/.",
    )
    parser.add_argument(
        "--manifest",
        type=Path,
        default=None,
        help="Path to skills-master.json "
        "(defaults to ~/.config/skills/skills-master.json).",
    )
    parser.add_argument(
        "--machine-config",
        type=Path,
        default=None,
        help="Path to the machine overlay JSON, deep-merged into the manifest.",
    )
    parser.add_argument(
        "--home",
        type=Path,
        default=None,
        help="Override home directory (useful for testing).",
    )
    parser.add_argument(
        "--repo-root",
        type=Path,
        default=None,
        help="Override the chezmoi repo root "
        "(defaults to ~/.local/share/chezmoi).",
    )
    return parser


def cli(argv: Sequence[str] | None = None) -> int:
    """Entry point for the ``sync-skills`` console script."""
    args = build_parser().parse_args(argv)
    return run_skills_sync(
        manifest_path=args.manifest.expanduser() if args.manifest else None,
        machine_config_path=(
            args.machine_config.expanduser() if args.machine_config else None
        ),
        home=args.home.expanduser() if args.home else None,
        repo_root=args.repo_root.expanduser() if args.repo_root else None,
    )


if __name__ == "__main__":
    raise SystemExit(cli())
```

Then modify `mcp_sync/pyproject.toml`. Find:

```toml
[project.scripts]
sync-mcp-configs = "mcp_sync.cli:cli"
```

Replace with:

```toml
[project.scripts]
sync-mcp-configs = "mcp_sync.cli:cli"
sync-skills = "mcp_sync.skills_cli:cli"
```

- [ ] **Step 4: Run test to verify it passes**

Run: `uv run --project mcp_sync --group dev pytest mcp_sync/tests/test_skills_cli.py -v`
Then verify the entry point resolves:
Run: `uv run --project mcp_sync sync-skills --help`
Expected: tests PASS (2 tests); `--help` prints the usage text with all four flags.

- [ ] **Step 5: Lint and commit**

```bash
uv run --project mcp_sync --group dev ruff check --fix mcp_sync/src mcp_sync/tests
uv run --project mcp_sync --group dev ruff format mcp_sync/src mcp_sync/tests
git add mcp_sync/src/mcp_sync/skills_cli.py mcp_sync/tests/test_skills_cli.py mcp_sync/pyproject.toml
git commit -m "feat: add sync-skills CLI entry point (#57)"
```

---

## Task 10: Add the `skills` capability and its chezmoiignore gates

**Files:**
- Modify: `.chezmoidata/machines.toml`
- Modify: `.chezmoiignore`

> The capability definition and its gates **must** ship in one commit. The
> `machine-capability-audit` pre-commit hook fails any commit that defines a
> capability with no gate (orphan) or references a gate with no definition
> (undefined). That is why this task ends with a single commit of both files.

- [ ] **Step 1: Add the capability description to the header comment**

In `.chezmoidata/machines.toml`, find the `#   hippo  — ...` capability description block and add this entry immediately after the `mcp` description (keep alphabetical-ish grouping with `mcp`):

```
#   skills — deploy ~/.config/skills/ (the skill manifest + machine overlays)
#            and run the post-apply sync-skills hook that populates
#            ~/.claude/skills/ from vendored (mattpocock) and personal
#            skills. Off on machines that don't run Claude Code skills.
```

- [ ] **Step 2: Add `skills = true` to every machine row**

In each of the three `[machines.*]` blocks (`personal-mac`, `work-mac`, `lab-mac`), add a `skills = true` line immediately after the existing `mcp = true` line. Example for `[machines.personal-mac]`:

```toml
[machines.personal-mac]
tiling = true
atuin = true
mcp = true
skills = true
hippo = true
gui = true
dev = true
aws_sso = false
infra = false
```

Apply the same `skills = true` insertion to `[machines.work-mac]` and `[machines.lab-mac]`.

- [ ] **Step 3: Verify the capability resolves**

Run: `chezmoi execute-template '{{ (index .machines .machine).skills }}'`
Expected: prints `true`

- [ ] **Step 4: Ignore the repo-root `skills/` directory**

In `.chezmoiignore`, find the block of non-dotfile ignores containing `docs` and `scripts`:

```
.github
.pre-commit-config.yaml
.envrc
.gitignore
README.md
CLAUDE.md
docs
scripts
private_dot_claude.json
```

Add `skills` on its own line after `scripts`:

```
.github
.pre-commit-config.yaml
.envrc
.gitignore
README.md
CLAUDE.md
docs
scripts
skills
private_dot_claude.json
```

- [ ] **Step 5: Rewrite the existing skills comment block**

Find this comment block:

```
# Skills under ~/.claude/skills/ are not tracked here. Skills installed by
# claude-plugins are symlinks to ~/.agents/skills/, and locally authored
# skills also live in ~/.agents/skills/ so they can be reused outside this
# repo. If a future skill ever needs to ride along with the dotfiles, add it
# back with a `!.claude/skills/<name>` un-ignore pattern.
```

Replace it entirely with:

```
# ~/.claude/skills/ is managed by mcp_sync's sync-skills command, not chezmoi.
# sync-skills copies vendored skills from a git cache and symlinks personal
# skills from skills/personal/ in this repo. chezmoi must not deploy into
# that directory. See docs/superpowers/specs/2026-05-17-skill-distribution-design.md.
```

- [ ] **Step 6: Add the `skills` capability gate**

Find the MCP capability gate block:

```
{{ if not (index .machines .machine).mcp }}
.config/mcp
{{ end }}
```

Add a parallel block immediately after it:

```
{{ if not (index .machines .machine).skills }}
.config/skills
{{ end }}
```

- [ ] **Step 7: Gate the machine overlay files**

In the `{{ if not (hasPrefix "work" .machine) }}` block, add this line alongside the existing `.config/mcp/machine/work.json` line:

```
.config/skills/machine/work.json
```

In the `{{ if not (hasPrefix "personal" .machine) }}` block, add alongside `.config/mcp/machine/personal.json`:

```
.config/skills/machine/personal.json
```

In the `{{ if ne .machine "lab-mac" }}` block, add alongside `.config/mcp/machine/lab.json`:

```
.config/skills/machine/lab.json
```

- [ ] **Step 8: Verify the template renders**

Run: `chezmoi execute-template < .chezmoiignore`
Expected: renders without a template error; output contains `.config/skills/machine/work.json` and `.config/skills/machine/lab.json` (on a personal machine these two are ignored, `personal.json` is not).

- [ ] **Step 9: Commit**

```bash
git add .chezmoidata/machines.toml .chezmoiignore
git commit -m "feat: add skills machine capability and gates (#57)"
```

---

## Task 11: Create the skills manifest and machine overlays

**Files:**
- Create: `dot_config/skills/skills-master.json`
- Create: `dot_config/skills/machine/personal.json`
- Create: `dot_config/skills/machine/work.json`
- Create: `dot_config/skills/machine/lab.json`

- [ ] **Step 1: Create the master manifest**

Create `dot_config/skills/skills-master.json`:

```json
{
  "sources": {
    "mattpocock": {
      "type": "git",
      "url": "https://github.com/mattpocock/skills",
      "ref": "main",
      "refreshPeriod": "168h"
    },
    "personal": {
      "type": "local",
      "path": "skills/personal"
    }
  },
  "skills": {
    "caveman": { "source": "mattpocock", "path": "skills/productivity/caveman" },
    "grill-me": { "source": "mattpocock", "path": "skills/productivity/grill-me" },
    "write-a-skill": { "source": "mattpocock", "path": "skills/productivity/write-a-skill" },
    "grill-with-docs": { "source": "mattpocock", "path": "skills/engineering/grill-with-docs" },
    "improve-codebase-architecture": { "source": "mattpocock", "path": "skills/engineering/improve-codebase-architecture" },
    "tdd": { "source": "mattpocock", "path": "skills/engineering/tdd" },
    "to-issues": { "source": "mattpocock", "path": "skills/engineering/to-issues" },
    "to-prd": { "source": "mattpocock", "path": "skills/engineering/to-prd" },
    "triage": { "source": "mattpocock", "path": "skills/engineering/triage" },
    "zoom-out": { "source": "mattpocock", "path": "skills/engineering/zoom-out" },
    "git-guardrails-claude-code": { "source": "mattpocock", "path": "skills/misc/git-guardrails-claude-code" },
    "migrate-to-shoehorn": { "source": "mattpocock", "path": "skills/misc/migrate-to-shoehorn" },
    "scaffold-exercises": { "source": "mattpocock", "path": "skills/misc/scaffold-exercises" },
    "setup-pre-commit": { "source": "mattpocock", "path": "skills/misc/setup-pre-commit" },
    "edit-article": { "source": "mattpocock", "path": "skills/personal/edit-article" },
    "obsidian-vault": { "source": "mattpocock", "path": "skills/personal/obsidian-vault" },
    "refactor": { "source": "personal" }
  }
}
```

- [ ] **Step 2: Create the three machine overlays**

Create `dot_config/skills/machine/personal.json`:

```json
{ "skills": {} }
```

Create `dot_config/skills/machine/work.json` with the same content:

```json
{ "skills": {} }
```

Create `dot_config/skills/machine/lab.json` with the same content:

```json
{ "skills": {} }
```

(Overlays start empty — the divergence mechanism is wired and ready. To disable a
skill on a machine, add `"skill-name": false` to that machine's overlay.)

- [ ] **Step 3: Verify the JSON is valid and resolves**

Run: `python3 -c "import json,sys; [json.load(open(p)) for p in sys.argv[1:]]" dot_config/skills/skills-master.json dot_config/skills/machine/*.json`
Then verify resolution against the real manifest:
Run: `uv run --project mcp_sync python3 -c "from mcp_sync.skills import load_skills_manifest, resolve_skills; m=load_skills_manifest(__import__('pathlib').Path('dot_config/skills/skills-master.json')); print(len(resolve_skills(m)), 'skills resolved')"`
Expected: no JSON errors; prints `17 skills resolved`

- [ ] **Step 4: Commit**

```bash
git add dot_config/skills/
git commit -m "feat: add skill manifest and machine overlays (#57)"
```

---

## Task 12: Post-apply hook

**Files:**
- Create: `.chezmoiscripts/run_after_sync-skills.sh.tmpl`

- [ ] **Step 1: Create the hook script**

Create `.chezmoiscripts/run_after_sync-skills.sh.tmpl`:

```bash
#!/usr/bin/env bash
set -euo pipefail

# Post-apply hook: sync Claude Code skills from the skills manifest.
# Triggered by: chezmoi apply
#
# Self-gates on the `skills` machine capability — on machines where
# skills=false the body collapses to a no-op. The .chezmoiignore already
# excludes ~/.config/skills/ on those machines.

{{ if not (index .machines .machine).skills -}}
echo "Skill sync skipped (machine capability skills=false)."
exit 0
{{- else -}}

SYNC_PROJECT="${HOME}/.local/share/chezmoi/mcp_sync"
STRICT_MODE="${MCP_SYNC_STRICT:-0}"

fail_or_warn() {
  local message="$1"
  if [[ "${STRICT_MODE}" == "1" ]]; then
    echo "Error: ${message}" >&2
    exit 1
  fi
  echo "Warning: ${message}" >&2
}

if ! command -v uv >/dev/null 2>&1; then
  fail_or_warn "uv is not installed; skipping skill sync."
  exit 0
fi

if [[ -f "${SYNC_PROJECT}/pyproject.toml" ]]; then
  sync_cmd=(sync-skills)

  # Detect machine-type overlay (chezmoi deploys only the matching one)
  MACHINE_DIR="${HOME}/.config/skills/machine"
  if [[ -d "${MACHINE_DIR}" ]]; then
    for f in "${MACHINE_DIR}"/*.json; do
      if [[ -f "$f" ]]; then
        sync_cmd+=(--machine-config "$f")
        break
      fi
    done
  fi

  if ! uv run --project "${SYNC_PROJECT}" "${sync_cmd[@]}"; then
    fail_or_warn "Skill sync failed."
    exit 0
  fi
else
  echo "Warning: skill sync project not found at ${SYNC_PROJECT}." >&2
  exit 0
fi

{{- end }}
```

- [ ] **Step 2: Verify the template renders to valid bash**

Run: `chezmoi execute-template < .chezmoiscripts/run_after_sync-skills.sh.tmpl | bash -n`
Expected: no output (bash syntax check passes)

- [ ] **Step 3: Commit**

```bash
git add .chezmoiscripts/run_after_sync-skills.sh.tmpl
git commit -m "feat: run sync-skills after chezmoi apply (#57)"
```

---

## Task 13: Migrate personal and project skills

**Files:**
- Move: `.agents/skills/refactor/` → `skills/personal/refactor/`
- Move: `.agents/skills/chezmoi-verify/` → `.claude/skills/chezmoi-verify/`
- Move: `.agents/skills/mcp-sync-verify/` → `.claude/skills/mcp-sync-verify/`
- Move: `.agents/skills/machine-capability-audit/` → `.claude/skills/machine-capability-audit/`

- [ ] **Step 1: Move the personal skill**

```bash
mkdir -p skills/personal
git mv .agents/skills/refactor skills/personal/refactor
```

- [ ] **Step 2: Move the three repo-specific skills to project scope**

```bash
mkdir -p .claude/skills
git mv .agents/skills/chezmoi-verify .claude/skills/chezmoi-verify
git mv .agents/skills/mcp-sync-verify .claude/skills/mcp-sync-verify
git mv .agents/skills/machine-capability-audit .claude/skills/machine-capability-audit
```

- [ ] **Step 3: Verify `.agents/` is now empty and gone**

Run: `ls -la .agents 2>&1; git status --short`
Expected: `.agents` no longer exists (git does not track empty directories); `git status` shows the moves staged.

- [ ] **Step 4: Verify the personal skill resolves and deploys in a dry run**

Run:
```bash
uv run --project mcp_sync python3 - <<'EOF'
from pathlib import Path
from mcp_sync.skills import load_skills_manifest, resolve_skills
m = load_skills_manifest(Path("dot_config/skills/skills-master.json"))
repo = Path.cwd()
for s in resolve_skills(m):
    if s.source_type == "local":
        src = repo / s.subpath
        assert src.is_dir(), f"missing local skill source: {src}"
        print("ok:", s.name, "->", src)
EOF
```
Expected: prints `ok: refactor -> .../skills/personal/refactor`

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "refactor: relocate skills out of .agents/ (#57)"
```

---

## Task 14: CI path filter and documentation

**Files:**
- Modify: `.github/workflows/mcp-sync-ci.yml`
- Modify: `mcp_sync/README.md`

- [ ] **Step 1: Extend the CI path filter**

In `.github/workflows/mcp-sync-ci.yml`, both the `push.paths` and `pull_request.paths` lists currently read:

```yaml
    paths:
      - "mcp_sync/**"
      - ".github/workflows/mcp-sync-ci.yml"
```

Add a `dot_config/skills/**` entry to **both** lists so manifest edits trigger CI:

```yaml
    paths:
      - "mcp_sync/**"
      - "dot_config/skills/**"
      - ".github/workflows/mcp-sync-ci.yml"
```

- [ ] **Step 2: Document `sync-skills` in the mcp_sync README**

Open `mcp_sync/README.md` and append a new top-level section at the end of the file (the outer fence below is 4 backticks so the inner bash block is unambiguous — copy only the inner content):

````markdown
## Skill Sync (`sync-skills`)

`sync-skills` deploys Claude Code skills to `~/.claude/skills/`, mirroring how
`sync-mcp-configs` deploys MCP configs.

- **Manifest:** `~/.config/skills/skills-master.json` declares `sources` (git or
  local) and an explicit `skills` allow-list. Machine overlays in
  `~/.config/skills/machine/` disable skills per machine (`"name": false`).
- **Vendored skills** (git sources) are cloned into `~/.cache/mcp-sync/skills/`
  and **copied** into place; re-fetched only after `refreshPeriod`.
- **Personal skills** (local source) live in `skills/personal/` in the chezmoi
  repo and are **symlinked**, so edits are live.
- **Garbage collection:** `~/.local/state/mcp-sync/skills-state.json` records
  what each run deployed; skills dropped from the manifest are removed on the
  next run. Skills the sync never deployed are never touched.

Run manually with `uv run --project mcp_sync sync-skills`. It runs automatically
after `chezmoi apply` via `.chezmoiscripts/run_after_sync-skills.sh.tmpl`.

### One-time migration cleanup

Before this feature, `~/.claude/skills/` held symlinks into `~/.agents/skills/`.
After the first `chezmoi apply` with `sync-skills`, remove the stale state by
hand (destructive — review before running):

```bash
# Remove dangling symlinks that point into ~/.agents/skills/
for link in ~/.claude/skills/*; do
  [ -L "$link" ] && [ ! -e "$link" ] && rm -v "$link"
done
# Once skills/personal/ has replaced it, retire the old directory:
rm -rf ~/.agents
```
````

- [ ] **Step 3: Verify**

Run: `python3 -c "import yaml,sys; yaml.safe_load(open('.github/workflows/mcp-sync-ci.yml'))"`
Expected: no error (the workflow YAML is valid).

- [ ] **Step 4: Commit**

```bash
git add .github/workflows/mcp-sync-ci.yml mcp_sync/README.md
git commit -m "docs: document sync-skills and CI coverage (#57)"
```

---

## Final verification

- [ ] **Run the full mcp_sync test + lint suite:**

```bash
uv run --project mcp_sync --group dev ruff check --fix mcp_sync/src mcp_sync/tests
uv run --project mcp_sync --group dev ruff format --check mcp_sync/src mcp_sync/tests
uv run --project mcp_sync --group dev pytest mcp_sync/tests --cov=mcp_sync --cov-report=term-missing
```
Expected: ruff clean; all tests pass (existing MCP tests plus 33 new skill tests).

- [ ] **Dry-run the chezmoi templates:**

```bash
chezmoi execute-template < .chezmoiignore > /dev/null
chezmoi execute-template < .chezmoiscripts/run_after_sync-skills.sh.tmpl | bash -n
chezmoi diff
```
Expected: templates render; `chezmoi diff` shows the new `~/.config/skills/` files and the hook script, and no unexpected deletions.

- [ ] **Live end-to-end check (optional, on the dev machine):**

```bash
chezmoi apply -v
ls -la ~/.claude/skills/ | head
cat ~/.local/state/mcp-sync/skills-state.json
```
Expected: `~/.claude/skills/` contains 16 copied mattpocock skill directories and a `refactor` symlink; the state file lists all 17 under `deployed`.

---

## Out of scope (follow-ups, not this plan)

- `screenshot-bug-hunt` — Astro/pnpm-coupled; belongs as a project skill in the
  whistlepost repo, or generalize its stack assumptions first. Different repo.
- The `find-skills` and the 4 deprecated mattpocock skills were intentionally
  dropped; re-add later as one-line manifest edits if wanted.
- Multi-tool skill fanout (Codex/Copilot).
