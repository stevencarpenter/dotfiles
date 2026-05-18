"""Claude Code skill synchronization: vendored + personal, machine-gated."""

from __future__ import annotations

import json
import os
import re
import shutil
import subprocess
import time
import uuid
from dataclasses import dataclass
from pathlib import Path
from typing import Any

from .sync import deep_merge, log_error, log_info, log_success

type JsonDict = dict[str, Any]

_DURATION_UNITS = {"s": 1, "m": 60, "h": 3600, "d": 86400}
_DURATION_RE = re.compile(r"^(\d+)([smhd])$")

DEFAULT_REFRESH = "168h"
DEFAULT_REF = "main"

_SAFE_SKILL_NAME_RE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._-]*$")

# A marker file written into every copy-mode skill directory. Garbage
# collection of a copy-mode skill requires this marker to still match, proving
# the directory is one this tool deployed rather than a user/plugin replacement.
_MANAGED_MARKER = ".mcp-sync-managed"
_MANAGED_MARKER_VALUE = "mcp-sync-managed-v1"


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


def _validate_skill_name(name: str) -> None:
    """Reject skill names that could escape the managed skills directory.

    Args:
        name: A manifest skill key or a recorded state key.

    Raises:
        ValueError: If the name is not a safe single path component.
    """
    if not isinstance(name, str) or not _SAFE_SKILL_NAME_RE.fullmatch(name):
        raise ValueError(f"unsafe skill name: {name!r}")


def _validate_relative_manifest_path(path_text: str, *, label: str) -> None:
    """Reject manifest paths that are absolute or contain traversal segments.

    Args:
        path_text: A path string drawn from the manifest.
        label: Human-readable label used to phrase the error message.

    Raises:
        ValueError: If the path is absolute or contains ``.``, ``..``, or empty
            components.
    """
    path = Path(path_text)
    if path.is_absolute() or any(part in {"", ".", ".."} for part in path.parts):
        raise ValueError(f"unsafe {label}: {path_text!r}")


def _safe_target(root: Path, name: str) -> Path:
    """Resolve a skill target under ``root``, refusing names that escape it.

    Args:
        root: The managed ``~/.claude/skills/`` directory.
        name: The skill directory name.

    Returns:
        The validated ``root / name`` path.

    Raises:
        ValueError: If ``name`` is unsafe or resolves outside ``root``.
    """
    _validate_skill_name(name)
    # Resolve only the (trusted) root chain — never the leaf, since a
    # symlink-mode skill deliberately points outside the skills directory.
    root_resolved = root.resolve(strict=False)
    if (root_resolved / name).parent != root_resolved:
        raise ValueError(f"skill target escapes target root: {name!r}")
    return root / name


def resolve_skills(manifest: JsonDict) -> list[ResolvedSkill]:
    """Resolve the manifest's skill map into a deployable list.

    Args:
        manifest: The merged manifest (master config + machine overlay).

    Returns:
        Resolved skills sorted by name, excluding any disabled via an
        overlay ``false`` value.

    Raises:
        ValueError: If a skill name or path is unsafe, references an unknown
            source, omits a required field, or a source has an invalid type
            or omits its required ``url``/``path``.
    """
    sources = manifest.get("sources", {})
    resolved: list[ResolvedSkill] = []
    for name, entry in sorted(manifest.get("skills", {}).items()):
        _validate_skill_name(name)
        if entry is False:
            continue
        if not isinstance(entry, dict):
            raise ValueError(f"Skill {name!r} must be an object or false")
        source_name = entry.get("source")
        if not source_name:
            raise ValueError(f"Skill {name!r} is missing required 'source' field")
        if source_name not in sources:
            raise ValueError(
                f"Skill {name!r} references unknown source {source_name!r}"
            )
        source = sources[source_name]
        source_type = source.get("type")
        if not source_type:
            raise ValueError(f"Source {source_name!r} is missing required 'type' field")
        if source_type == "git":
            if not source.get("url"):
                raise ValueError(
                    f"Git source {source_name!r} is missing required 'url' field"
                )
            subpath = entry.get("path")
            if not subpath:
                raise ValueError(f"Git-sourced skill {name!r} requires a 'path'")
            _validate_relative_manifest_path(subpath, label="skill path")
            mode = "copy"
        elif source_type == "local":
            explicit = entry.get("path")
            if explicit:
                _validate_relative_manifest_path(explicit, label="skill path")
                subpath = explicit
            else:
                source_path = source.get("path")
                if not source_path:
                    raise ValueError(
                        f"Local source {source_name!r} is missing required 'path' field"
                    )
                _validate_relative_manifest_path(source_path, label="source path")
                subpath = f"{source_path}/{name}"
            mode = "symlink"
        else:
            raise ValueError(f"Source {source_name!r} has invalid type {source_type!r}")
        resolved.append(ResolvedSkill(name, source_name, source_type, subpath, mode))
    return resolved


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
    # Kept deliberately parallel to sync.py's _write_json; not shared because
    # that helper is private to that module and the duplication is trivial.
    path.parent.mkdir(parents=True, exist_ok=True)
    serialized = json.dumps(state, indent=2, sort_keys=True)
    path.write_text(serialized + "\n", encoding="utf-8")


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
    *,
    force: bool = False,
) -> Path:
    """Ensure a git source is cloned and current within its refresh period.

    Skips all network access when the cached clone was fetched more recently
    than ``refreshPeriod`` *and* its stored ``url``/``ref`` still match the
    manifest. A changed ``url`` or ``ref`` forces a refetch even within the
    refresh window. On a fetch, records ``last_fetch``, ``url``, and ``ref``
    in ``state["sources"][name]``.

    Args:
        name: Source name (also the cache subdirectory name).
        source: The source definition (``url``, optional ``ref`` and
            ``refreshPeriod``).
        cache_root: Root directory for source clones.
        state: The mutable sync state mapping.
        now: Current time as epoch seconds.
        force: When True, refetch even if the cache is within ``refreshPeriod``.

    Returns:
        Path to the cached clone.
    """
    cache_dir = cache_root / name
    url = source["url"]
    ref = source.get("ref", DEFAULT_REF)
    refresh_s = parse_duration(source.get("refreshPeriod", DEFAULT_REFRESH))
    prior = state.get("sources", {}).get(name, {})
    last_fetch = prior.get("last_fetch", 0)
    # A stored identity that no longer matches the manifest forces a refetch
    # regardless of the refresh timer. A missing stored identity (pre-feature
    # state) is treated as matching, so it never triggers a spurious fetch.
    identity_changed = prior.get("url", url) != url or prior.get("ref", ref) != ref

    if (
        not force
        and not identity_changed
        and cache_dir.is_dir()
        and (now - last_fetch) < refresh_s
    ):
        log_info(f"Source {name!r} cache is fresh; skipping fetch")
        return cache_dir

    if not cache_dir.is_dir():
        cache_dir.parent.mkdir(parents=True, exist_ok=True)
        log_info(f"Cloning source {name!r} from {url}")
        _git("clone", url, str(cache_dir))
    elif prior.get("url", url) != url:
        log_info(f"Source {name!r} URL changed; updating origin to {url}")
        _git("remote", "set-url", "origin", url, cwd=cache_dir)
    log_info(f"Fetching source {name!r} at ref {ref!r}")
    _git("fetch", "origin", ref, cwd=cache_dir)
    _git("reset", "--hard", "FETCH_HEAD", cwd=cache_dir)

    state.setdefault("sources", {})[name] = {
        "last_fetch": now,
        "url": url,
        "ref": ref,
    }
    return cache_dir


def _remove_path(path: Path) -> None:
    """Remove a file, symlink, or directory tree if it exists."""
    if path.is_symlink() or path.is_file():
        path.unlink()
    elif path.is_dir():
        shutil.rmtree(path)


def _assert_tree_has_no_symlinks(root: Path) -> None:
    """Reject a source tree that contains any symlink.

    Copy-mode deployment uses ``shutil.copytree`` with default settings, which
    follows symlinks — vendored third-party content could otherwise smuggle a
    link pointing anywhere on disk into ``~/.claude/skills/``.

    Args:
        root: The source skill directory about to be copied.

    Raises:
        ValueError: If any entry under ``root`` is a symlink.
    """
    for path in root.rglob("*"):
        if path.is_symlink():
            raise ValueError(f"Refusing to copy symlink from vendored skill: {path}")


def _replace_directory_from_copy(src: Path, target: Path) -> None:
    """Replace ``target`` with a fresh copy of ``src`` without an unsafe gap.

    The copy lands in a sibling temp directory first; only after it succeeds is
    the existing target renamed aside and the temp moved into place. A failed
    copy therefore leaves the previous target untouched.

    Args:
        src: Source skill directory.
        target: Destination directory.

    Raises:
        OSError: If the copy or rename fails; the prior target is restored.
    """
    target.parent.mkdir(parents=True, exist_ok=True)
    suffix = f"{os.getpid()}-{uuid.uuid4().hex}"
    tmp = target.parent / f".{target.name}.tmp-{suffix}"
    backup = target.parent / f".{target.name}.bak-{suffix}"
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
        _assert_tree_has_no_symlinks(src)
        _replace_directory_from_copy(src, target)
        (target / _MANAGED_MARKER).write_text(
            _MANAGED_MARKER_VALUE + "\n", encoding="utf-8"
        )
    else:
        raise ValueError(f"Unknown deploy mode: {mode!r}")


def garbage_collect(
    previous: JsonDict,
    current_names: set[str],
    target_root: Path,
) -> list[str]:
    """Remove skills deployed by a prior run but absent from this run.

    An entry is removed only when it still matches the shape the prior run
    recorded — a symlink we created, or a copied directory still carrying a
    matching ``.mcp-sync-managed`` ownership marker. If the user has since
    replaced it with something else (or it predates the marker), it is logged
    and left alone. Anything the sync never recorded is never inspected.

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
        try:
            path = _safe_target(target_root, name)
        except ValueError:
            log_info(f"Skipping GC of unsafe state entry: {name!r}")
            continue
        if not path.exists() and not path.is_symlink():
            continue
        mode = record.get("mode")
        if mode == "symlink" and path.is_symlink():
            path.unlink()
            removed.append(name)
        elif mode == "copy" and path.is_dir() and not path.is_symlink():
            marker = path / _MANAGED_MARKER
            expected = record.get("marker")
            if (
                expected
                and marker.is_file()
                and marker.read_text(encoding="utf-8").strip() == expected
            ):
                shutil.rmtree(path)
                removed.append(name)
            else:
                log_info(
                    f"Skipping GC of {name!r}: copy-mode ownership marker "
                    "missing or mismatched"
                )
        else:
            log_info(f"Skipping GC of {name!r}: no longer matches recorded mode")
    return removed


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
        0 on success, 1 on a configuration error or if any skill failed
        to deploy.
    """
    home_path = home or Path.home()
    repo = repo_root or home_path / ".local" / "share" / "chezmoi"
    now_ts = now if now is not None else time.time()
    manifest_file = (
        manifest_path or home_path / ".config" / "skills" / "skills-master.json"
    )
    if not manifest_file.is_file():
        log_error(f"Skills manifest not found at {manifest_file}")
        log_info("Run 'chezmoi apply' to deploy dotfiles first")
        return 1

    log_info("Syncing Claude skills from manifest...")
    try:
        manifest = load_skills_manifest(manifest_file)
    except (json.JSONDecodeError, OSError, ValueError) as exc:
        log_error(f"Manifest error: {exc}")
        return 1

    if machine_config_path and machine_config_path.is_file():
        try:
            with open(machine_config_path, encoding="utf-8") as handle:
                overlay = json.load(handle)
        except (json.JSONDecodeError, OSError) as exc:
            log_error(f"Machine overlay error: {exc}")
            return 1
        if not isinstance(overlay, dict):
            log_error(f"Machine overlay root must be an object: {machine_config_path}")
            return 1
        log_info(f"Applying machine overlay: {machine_config_path}")
        manifest = deep_merge(manifest, overlay)

    try:
        resolved = resolve_skills(manifest)
    except ValueError as exc:
        log_error(f"Manifest error: {exc}")
        return 1

    cache_root = home_path / ".cache" / "mcp-sync" / "skills"
    state_path = home_path / ".local" / "state" / "mcp-sync" / "skills-state.json"
    target_root = home_path / ".claude" / "skills"
    state = load_state(state_path)
    prior = dict(state.get("deployed", {}))
    sources = manifest["sources"]

    # Fetch each git source once. A git failure does not abort the run: if a
    # stale cache exists it is reused, otherwise the source is marked failed
    # and its skills are skipped so unrelated (local) skills still deploy.
    failed = False
    failed_sources: set[str] = set()
    git_caches: dict[str, Path] = {}
    for skill in resolved:
        if skill.source_type != "git" or skill.source_name in git_caches:
            continue
        if skill.source_name in failed_sources:
            continue
        try:
            git_caches[skill.source_name] = ensure_git_source(
                skill.source_name,
                sources[skill.source_name],
                cache_root,
                state,
                now_ts,
            )
        except subprocess.CalledProcessError as exc:
            log_error(f"Git source {skill.source_name!r} failed: {exc}")
            failed = True
            cache_dir = cache_root / skill.source_name
            if cache_dir.is_dir():
                log_info(f"Using stale cache for source {skill.source_name!r}")
                git_caches[skill.source_name] = cache_dir
            else:
                failed_sources.add(skill.source_name)

    # A resolved git skill missing from its (time-fresh) cache means the cache
    # predates a manifest change. Force one refetch per affected source so a
    # newly added skill deploys immediately rather than waiting out the
    # refresh period.
    refreshed: set[str] = set()
    for skill in resolved:
        if skill.source_type != "git" or skill.source_name in refreshed:
            continue
        if skill.source_name not in git_caches:
            continue
        if not (git_caches[skill.source_name] / skill.subpath).is_dir():
            log_info(
                f"Skill {skill.name!r} absent from cache; "
                f"refetching source {skill.source_name!r}"
            )
            try:
                git_caches[skill.source_name] = ensure_git_source(
                    skill.source_name,
                    sources[skill.source_name],
                    cache_root,
                    state,
                    now_ts,
                    force=True,
                )
            except subprocess.CalledProcessError as exc:
                log_error(f"Refetch of source {skill.source_name!r} failed: {exc}")
                failed = True
            refreshed.add(skill.source_name)

    # Deploy. A per-skill failure is logged and skipped; the run finishes the
    # remaining skills and reports failure via the exit code. A skill that
    # fails but was deployed by a prior run keeps that prior state record so
    # garbage collection stays accurate.
    deployed: JsonDict = {}
    for skill in resolved:
        if skill.source_type == "git" and skill.source_name in failed_sources:
            log_error(
                f"Skipping skill {skill.name!r}: "
                f"source {skill.source_name!r} unavailable"
            )
            failed = True
            if skill.name in prior:
                deployed[skill.name] = prior[skill.name]
            continue
        if skill.source_type == "git":
            src = git_caches[skill.source_name] / skill.subpath
        else:
            src = repo / skill.subpath
        target = _safe_target(target_root, skill.name)
        try:
            deploy_skill(src, target, skill.mode)
        except (OSError, ValueError) as exc:
            log_error(f"Failed to deploy skill {skill.name!r}: {exc}")
            failed = True
            if skill.name in prior:
                deployed[skill.name] = prior[skill.name]
            continue
        record: JsonDict = {"mode": skill.mode, "source": skill.source_name}
        if skill.mode == "copy":
            record["marker"] = _MANAGED_MARKER_VALUE
        deployed[skill.name] = record
        log_success(f"Deployed skill: {skill.name} ({skill.mode})")

    # Garbage-collect skills no longer in the manifest. A skill still resolved
    # but failed to deploy this run is intentionally NOT collected — its prior
    # copy is left in place.
    resolved_names = {skill.name for skill in resolved}
    for name in garbage_collect(prior, resolved_names, target_root):
        log_success(f"Removed orphaned skill: {name}")

    # Drop state records for sources no longer referenced by any skill.
    active_sources = {
        skill.source_name for skill in resolved if skill.source_type == "git"
    }
    state["sources"] = {
        name: record
        for name, record in state.get("sources", {}).items()
        if name in active_sources
    }
    state["deployed"] = deployed
    write_state(state_path, state)

    print()
    if failed:
        log_error("Skill sync completed with errors.")
        return 1
    log_success("Skill sync complete!")
    return 0
