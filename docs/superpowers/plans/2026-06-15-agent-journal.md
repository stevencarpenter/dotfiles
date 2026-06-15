# Agent Journal Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a dotfiles-managed, dependency-free Python tool (`agent_journal`) that records agent work as workstream-centered Obsidian notes and regenerates a daily Standup Draft, deployed only on `agent_journal`-capable machines.

**Architecture:** A new strict uv project (`agent_journal/`, mirroring `token_auditor`: hatchling, `ty`, 100% branch coverage, explicit ruff). Two executables — `agent-note` (agents append structured JSONL events) and `agent-journal` (subcommands `ingest`/`digest`/`standup`/`status`). All logic is *pure functions of injected inputs* (paths, file contents, and a `now: datetime`) so the 100% coverage gate is achievable with fixtures. Passive Codex + Claude Code adapters enrich explicit events; OpenCode/Copilot are out of v1. chezmoi gates everything behind a new `agent_journal` capability and a launchd LaunchAgent runs the hourly cycle.

**Tech Stack:** Python 3.14 (stdlib only: `argparse`, `tomllib`, `json`, `re`, `glob`, `dataclasses`, `pathlib`, `datetime`), uv, pytest + pytest-cov, ruff, ty, chezmoi templates, launchd.

---

## Repo-Specific Gotchas (read before starting)

These will break the build or block commits if ignored:

1. **Secret scanners block redaction-test fixtures.** `.pre-commit-config.yaml` runs `gitleaks`, `detect-private-key`, and `detect-aws-credentials`. The redaction tests *must* contain secret-shaped strings. Assemble every fixture token via concatenation so no complete pattern is a literal: `"ghp_" + "0123456789abcdefghijklmnopqrstuvwxyz1234"`, `"AKIA" + "IOSFODNN7EXAMPLE"`, `"-----BEGIN RSA " + "PRIVATE KEY-----"`. Never write a whole token/key on one literal line.
2. **`name-tests-test --pytest-test-first`** — test files MUST be named `test_*.py` (not `*_test.py`).
3. **`machine-capability-audit`** runs on `.chezmoidata/machines.toml`, `.chezmoiignore`, and `*.tmpl`. A capability must be both *defined* (in every `machines.toml` row) and *gated* (referenced via `(index .machines .machine).agent_journal`). Land both together (Task 17).
4. **`.chezmoiignore` must list `agent_journal`** alongside `mcp_sync`/`aws_config_gen`/`token_auditor`, or the source package leaks into `~` on every apply (Task 1).
5. **`pyrightconfig.json` `extraPaths`** must gain `agent_journal/src` or repo-root LSP can't resolve imports (Task 1).
6. **`uv.lock` is committed and CI runs `uv sync --locked`** (strict pattern). Generate it during scaffold.
7. **Chezmoi `.toml.tmpl` files are NOT linted by `check-toml`** (extension is `.tmpl`), so `{{ ... }}` is fine there. But `agent_journal/pyproject.toml` and the CI `.yml` ARE linted — keep them valid.
8. **`run_after_*` scripts still execute even when `.chezmoiignore` skips the dotfiles** — they MUST self-gate at the top (Task 19).
9. **`com.user.*` is the repo's plist label convention** (only existing plist is `com.user.xcode-mcp-proxy`). The spec sketched `org.stevec.agent-journal`; this plan uses `com.user.agent-journal` for repo consistency. (Flag for the user; trivially renamable.)

## File Structure

New uv project (source-only, never deployed to `~`):

```text
agent_journal/
  pyproject.toml                       # strict: hatchling + ty + 100% cov + explicit ruff
  .python-version                      # 3.14
  uv.lock                              # committed
  README.md
  src/agent_journal/
    __init__.py                        # __version__
    events.py                          # Event schema, validation, JSONL append/read
    redaction.py                       # secret/token redaction
    config.py                          # config.toml + workstreams.toml -> dataclasses
    state.py                           # state dir, watermarks, json helpers
    obsidian.py                        # daily-note paths, idempotent section replace, note IO
    resolver.py                        # workstream resolution + jira extraction
    adapters/
      __init__.py
      base.py                          # Adapter protocol, NormalizedSession, bounding helper
      codex.py                         # Codex archived_sessions adapter
      claude_code.py                   # Claude Code projects adapter + workflow-journal exclusion
    ingest.py                          # explicit events + adapters -> normalized snapshot + watermarks
    digest.py                          # update workstream/session notes + daily Agent Activity
    standup.py                         # regenerate automation-owned ## Standup Draft
    status.py                          # report skipped sessions + adapter health + last runs
    cli_note.py                        # agent-note entry point
    main.py                            # agent-journal entry point (subcommand dispatch)
  tests/
    conftest.py
    test_events.py  test_redaction.py  test_config.py  test_state.py
    test_obsidian.py  test_resolver.py  test_adapter_base.py
    test_adapter_codex.py  test_adapter_claude_code.py
    test_ingest.py  test_digest.py  test_standup.py  test_status.py
    test_cli_note.py  test_main.py
```

chezmoi-managed deployment (gated on `agent_journal`):

```text
.chezmoidata/machines.toml                                 # + agent_journal row per machine
.chezmoiignore                                             # + tool-dir entry, + capability gate, + darwin gate
pyrightconfig.json                                         # + agent_journal/src
dot_config/agent-journal/config.toml.tmpl
dot_config/agent-journal/workstreams.toml.tmpl
dot_local/bin/executable_agent-note
dot_local/bin/executable_agent-journal-run
.chezmoiscripts/run_after_sync-agent-journal.sh.tmpl
Library/LaunchAgents/com.user.agent-journal.plist.tmpl
.github/workflows/agent-journal-ci.yml
docs/ai-tools/agent-journal.md
CLAUDE.md                                                  # + commands + capability bullet
```

## Shared Data Model (locked interfaces — every task references these exact names)

```python
# events.py
EVENT_TYPES = ("start", "decision", "change", "verification", "blocker", "carry_forward", "finish")
class EventValidationError(ValueError): ...
@dataclass(frozen=True)
class Event:
    time: str; machine: str; tool: str; cwd: str; event: str; summary: str
    workstream: str | None = None
    links: tuple[str, ...] = (); repos: tuple[str, ...] = ()

# config.py
class ConfigError(ValueError): ...
@dataclass(frozen=True)
class Workstream:
    name: str; jira: str | None; context: str | None
    aliases: tuple[str, ...]; repos: tuple[str, ...]
@dataclass(frozen=True)
class VaultConfig:
    path: Path; daily_dir: str; daily_note_path_format: str
    workstreams_dir: str; sessions_dir: str
@dataclass(frozen=True)
class CodexAdapterConfig: sessions_glob: str
@dataclass(frozen=True)
class ClaudeAdapterConfig: projects_dir: Path
@dataclass(frozen=True)
class Config:
    machine: str; context: str; vault: VaultConfig; state_dir: Path
    enabled_adapters: tuple[str, ...]
    codex: CodexAdapterConfig | None; claude_code: ClaudeAdapterConfig | None
    redaction_extra: tuple[str, ...]; standup_hour: int

# state.py
@dataclass
class Watermark:
    source_key: str; offset: int = 0; last_id: str | None = None; last_time: str | None = None

# resolver.py
@dataclass(frozen=True)
class Resolution:
    status: str          # "matched" | "ambiguous" | "unknown"
    workstream: str | None; candidates: tuple[str, ...]; reason: str

# adapters/base.py
@dataclass(frozen=True)
class NormalizedSession:
    tool: str; machine: str; session_id: str
    cwd: str | None; branch: str | None; repo_url: str | None
    title: str | None; started_at: str | None; last_time: str | None
    narrative: tuple[str, ...]; new_message_count: int; new_offset: int; source_path: str
class Adapter(Protocol):
    name: str
    def discover(self) -> list[Path]: ...
    def parse(self, path: Path, previous_offset: int) -> NormalizedSession | None: ...
```

State file layout under `state_dir` (default `$XDG_STATE_HOME/agent-journal` or `~/.local/state/agent-journal`):
- `events.jsonl` — append-only explicit events (written by `agent-note`).
- `watermarks.json` — `{source_key: {offset, last_id, last_time}}`.
- `sessions.json` — latest normalized adapter sessions (written by `ingest`, read by `digest`).
- `runs.json` — `{last_ingest, last_digest, last_standup, adapter_health}` timestamps/health.
- `skipped.json` — unresolved sessions/events awaiting classification (written by `digest`, read by `status`).

---

## Task 1: Scaffold the strict uv project

**Files:**
- Create: `agent_journal/pyproject.toml`, `agent_journal/.python-version`, `agent_journal/README.md`
- Create: `agent_journal/src/agent_journal/__init__.py`, `agent_journal/src/agent_journal/adapters/__init__.py`
- Create: `agent_journal/tests/conftest.py`, `agent_journal/tests/test_smoke.py`
- Modify: `.chezmoiignore` (add `agent_journal` to the in-repo tool-dir list)
- Modify: `pyrightconfig.json` (add `agent_journal/src` to `extraPaths`)

- [ ] **Step 1: Create `agent_journal/pyproject.toml`** (mirrors `token_auditor`, names swapped)

```toml
[project]
name = "agent-journal"
version = "0.1.0"
description = "Record agent work as workstream-centered Obsidian notes and a daily standup draft."
readme = "README.md"
requires-python = ">=3.14"
dependencies = []

[project.scripts]
agent-journal = "agent_journal.main:main"
agent-note = "agent_journal.cli_note:cli"

[dependency-groups]
dev = [
    "pytest>=9.0.3",
    "pytest-cov>=6",
    "ruff>=0.9",
    "ty>=0.0.1a1",
]

[tool.uv]
managed = true

[tool.pytest.ini_options]
addopts = "--cov=agent_journal --cov-report=term-missing --cov-fail-under=100"

[tool.ruff]
target-version = "py314"
line-length = 180

[tool.ruff.lint]
select = ["E", "F", "I", "UP", "B", "SIM"]

[tool.coverage.run]
branch = true

[tool.coverage.report]
exclude_lines = ["if __name__ == .__main__.:"]

[tool.hatch.build.targets.wheel]
packages = ["src/agent_journal"]

[tool.hatch.build.targets.sdist]
include = [
    "src/agent_journal/**/*.py",
    "tests/**/*.py",
    "README.md",
    "pyproject.toml",
    "uv.lock",
]

[build-system]
requires = ["hatchling"]
build-backend = "hatchling.build"
```

- [ ] **Step 2: Create supporting files**

`agent_journal/.python-version`:
```text
3.14
```

`agent_journal/src/agent_journal/__init__.py`:
```python
"""Agent journal package."""

__version__ = "0.1.0"
```

`agent_journal/src/agent_journal/adapters/__init__.py`:
```python
"""Passive transcript/session adapters for the agent journal."""
```

`agent_journal/README.md`:
```markdown
# agent-journal

Records agent work as workstream-centered Obsidian notes and regenerates a daily
standup draft. Deployed via chezmoi behind the `agent_journal` machine capability.

- `agent-note` — agents append structured JSONL events (the explicit contract).
- `agent-journal ingest|digest|standup|status` — normalize, write notes, refresh
  the automation-owned `## Standup Draft`, and report unclassified work.

See `docs/ai-tools/agent-journal.md` in the dotfiles repo for usage.
```

`agent_journal/tests/conftest.py`:
```python
"""Shared pytest helpers for agent_journal tests."""

from __future__ import annotations

import json
from datetime import datetime
from pathlib import Path
from typing import Any


def write_jsonl(path: Path, rows: list[dict[str, Any]]) -> None:
    """Write a list of dicts as newline-delimited JSON."""
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text("".join(f"{json.dumps(row)}\n" for row in rows), encoding="utf-8")


def fixed_now() -> datetime:
    """Deterministic timestamp used across tests (Mon 2026-06-15 08:45 local)."""
    return datetime(2026, 6, 15, 8, 45, 0)
```

`agent_journal/tests/test_smoke.py`:
```python
"""Smoke test proving the package imports and exposes a version."""

import agent_journal


def test_version_is_exposed() -> None:
    assert agent_journal.__version__ == "0.1.0"
```

- [ ] **Step 3: Add `agent_journal` to the in-repo tool-dir ignore list**

In `.chezmoiignore`, find the block listing the tool dirs and add `agent_journal`:
```text
# In-repo Python tool projects — these live in the source tree only.
aws_config_gen
mcp_sync
token_auditor
agent_journal
```

- [ ] **Step 4: Add `agent_journal/src` to pyright `extraPaths`**

In `pyrightconfig.json`, extend `extraPaths`:
```json
  "extraPaths": [
    "token_auditor/src",
    "mcp_sync/src",
    "aws_config_gen/src",
    "agent_journal/src"
  ],
```

- [ ] **Step 5: Generate the lockfile and verify the toolchain**

Run:
```bash
cd agent_journal && uv sync --group dev
```
Expected: creates `agent_journal/.venv` and `agent_journal/uv.lock`.

```bash
cd agent_journal && uv run pytest -q
```
Expected: `1 passed` (smoke test), coverage 100% (only `__init__.py` executed).

```bash
cd agent_journal && uv run ruff check . && uv run ruff format --check . && uv run ty check .
```
Expected: all clean.

- [ ] **Step 6: Commit**

```bash
git add agent_journal/pyproject.toml agent_journal/.python-version agent_journal/README.md \
        agent_journal/src agent_journal/tests agent_journal/uv.lock \
        .chezmoiignore pyrightconfig.json
git commit -m "feat(agent-journal): scaffold strict uv project"
```

---

## Task 2: Event schema, validation, and JSONL store (`events.py`)

**Files:**
- Create: `agent_journal/src/agent_journal/events.py`
- Test: `agent_journal/tests/test_events.py`

- [ ] **Step 1: Write the failing tests**

```python
"""Unit tests for the explicit event schema and JSONL store."""

from pathlib import Path

import pytest

from agent_journal.events import (
    Event,
    EventValidationError,
    append_event,
    event_to_dict,
    read_events,
    validate_event,
)


def _valid_payload() -> dict[str, object]:
    return {
        "time": "2026-06-15T14:00:00-06:00",
        "machine": "work",
        "tool": "codex",
        "cwd": "/repo/foo",
        "event": "verification",
        "summary": "Ran terraform plan; drift expected.",
        "workstream": "LA-3141 databricks compute plane",
        "links": [],
        "repos": ["terraform", "k8s-config"],
    }


def test_validate_event_accepts_full_payload() -> None:
    event = validate_event(_valid_payload())
    assert event.event == "verification"
    assert event.repos == ("terraform", "k8s-config")
    assert event.workstream == "LA-3141 databricks compute plane"


def test_validate_event_defaults_optional_fields() -> None:
    payload = _valid_payload()
    del payload["workstream"]
    del payload["links"]
    del payload["repos"]
    event = validate_event(payload)
    assert event.workstream is None
    assert event.links == ()
    assert event.repos == ()


def test_validate_event_rejects_unknown_event_type() -> None:
    payload = _valid_payload()
    payload["event"] = "exploded"
    with pytest.raises(EventValidationError, match="unknown event type"):
        validate_event(payload)


@pytest.mark.parametrize("field", ["time", "machine", "tool", "cwd", "event", "summary"])
def test_validate_event_requires_string_fields(field: str) -> None:
    payload = _valid_payload()
    del payload[field]
    with pytest.raises(EventValidationError, match=f"missing required field: {field}"):
        validate_event(payload)


def test_validate_event_rejects_non_string_required_field() -> None:
    payload = _valid_payload()
    payload["summary"] = 42
    with pytest.raises(EventValidationError, match="must be a string: summary"):
        validate_event(payload)


def test_validate_event_rejects_non_list_repos() -> None:
    payload = _valid_payload()
    payload["repos"] = "terraform"
    with pytest.raises(EventValidationError, match="must be a list of strings: repos"):
        validate_event(payload)


def test_event_to_dict_roundtrips_through_validate() -> None:
    event = validate_event(_valid_payload())
    again = validate_event(event_to_dict(event))
    assert again == event


def test_append_and_read_events(tmp_path: Path) -> None:
    path = tmp_path / "state" / "events.jsonl"
    first = validate_event(_valid_payload())
    second_payload = _valid_payload()
    second_payload["event"] = "finish"
    second = validate_event(second_payload)

    append_event(path, first)
    append_event(path, second)

    events = read_events(path)
    assert [e.event for e in events] == ["verification", "finish"]


def test_read_events_missing_file_returns_empty(tmp_path: Path) -> None:
    assert read_events(tmp_path / "nope.jsonl") == []


def test_read_events_skips_blank_lines(tmp_path: Path) -> None:
    path = tmp_path / "events.jsonl"
    path.write_text('\n  \n{"time":"t","machine":"m","tool":"x","cwd":"/c","event":"start","summary":"s"}\n', encoding="utf-8")
    assert len(read_events(path)) == 1


def test_read_events_raises_on_malformed_line(tmp_path: Path) -> None:
    path = tmp_path / "events.jsonl"
    path.write_text("{not json}\n", encoding="utf-8")
    with pytest.raises(EventValidationError, match=r"malformed JSON .*line 1"):
        read_events(path)


def test_event_is_hashable() -> None:
    event = validate_event(_valid_payload())
    assert event in {event}
```

- [ ] **Step 2: Run to verify failure**

Run: `cd agent_journal && uv run pytest tests/test_events.py -q`
Expected: FAIL — `ModuleNotFoundError: No module named 'agent_journal.events'`.

- [ ] **Step 3: Implement `events.py`**

```python
"""Explicit agent event schema, validation, and append-only JSONL store."""

from __future__ import annotations

import json
from collections.abc import Mapping
from dataclasses import dataclass, field
from pathlib import Path

EVENT_TYPES: tuple[str, ...] = (
    "start",
    "decision",
    "change",
    "verification",
    "blocker",
    "carry_forward",
    "finish",
)

_REQUIRED_STR_FIELDS: tuple[str, ...] = ("time", "machine", "tool", "cwd", "event", "summary")
_LIST_FIELDS: tuple[str, ...] = ("links", "repos")


class EventValidationError(ValueError):
    """Raised when an event payload fails schema validation."""


@dataclass(frozen=True)
class Event:
    """A single explicit event emitted by an agent via ``agent-note``.

    Attributes:
        time: ISO-8601 timestamp (with offset) of the event.
        machine: Machine context label (e.g. ``work`` or ``personal``).
        tool: Originating agent tool (e.g. ``codex``, ``claude``).
        cwd: Working directory the agent operated in.
        event: One of :data:`EVENT_TYPES`.
        summary: Short human-written description (source material, not Slack prose).
        workstream: Optional explicit workstream name.
        links: Obsidian wiki-links supplied by the agent.
        repos: Repositories touched in this event.
    """

    time: str
    machine: str
    tool: str
    cwd: str
    event: str
    summary: str
    workstream: str | None = None
    links: tuple[str, ...] = field(default_factory=tuple)
    repos: tuple[str, ...] = field(default_factory=tuple)


def _coerce_str_list(value: object, name: str) -> tuple[str, ...]:
    """Validate and convert a JSON list-of-strings field into a tuple.

    Args:
        value: The raw value from the payload.
        name: Field name, used in error messages.

    Returns:
        The values as a tuple of strings.

    Raises:
        EventValidationError: If the value is not a list of strings.
    """
    if not isinstance(value, list) or not all(isinstance(item, str) for item in value):
        raise EventValidationError(f"must be a list of strings: {name}")
    return tuple(value)


def validate_event(data: Mapping[str, object]) -> Event:
    """Validate a raw payload and build an :class:`Event`.

    Args:
        data: Mapping parsed from JSON or constructed by the CLI.

    Returns:
        A validated, frozen :class:`Event`.

    Raises:
        EventValidationError: If required fields are missing, mistyped, or the
            event type is not in :data:`EVENT_TYPES`.
    """
    for name in _REQUIRED_STR_FIELDS:
        if name not in data:
            raise EventValidationError(f"missing required field: {name}")
        if not isinstance(data[name], str):
            raise EventValidationError(f"must be a string: {name}")

    event_type = data["event"]
    if event_type not in EVENT_TYPES:
        raise EventValidationError(f"unknown event type: {event_type!r} (allowed: {', '.join(EVENT_TYPES)})")

    workstream = data.get("workstream")
    if workstream is not None and not isinstance(workstream, str):
        raise EventValidationError("must be a string: workstream")

    return Event(
        time=str(data["time"]),
        machine=str(data["machine"]),
        tool=str(data["tool"]),
        cwd=str(data["cwd"]),
        event=str(event_type),
        summary=str(data["summary"]),
        workstream=workstream,
        links=_coerce_str_list(data.get("links", []), "links"),
        repos=_coerce_str_list(data.get("repos", []), "repos"),
    )


def event_to_dict(event: Event) -> dict[str, object]:
    """Serialize an :class:`Event` into a JSON-ready dict."""
    return {
        "time": event.time,
        "machine": event.machine,
        "tool": event.tool,
        "cwd": event.cwd,
        "event": event.event,
        "summary": event.summary,
        "workstream": event.workstream,
        "links": list(event.links),
        "repos": list(event.repos),
    }


def append_event(path: Path, event: Event) -> None:
    """Append one event as a JSON line, creating parent directories."""
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("a", encoding="utf-8") as handle:
        handle.write(json.dumps(event_to_dict(event)) + "\n")


def read_events(path: Path) -> list[Event]:
    """Read and validate all events from a JSONL file.

    Args:
        path: Path to the events JSONL file.

    Returns:
        Validated events in file order. Missing file yields an empty list;
        blank lines are skipped.

    Raises:
        EventValidationError: On malformed JSON or invalid event payloads,
            annotated with the 1-based line number.
    """
    if not path.exists():
        return []
    events: list[Event] = []
    for lineno, raw in enumerate(path.read_text(encoding="utf-8").splitlines(), start=1):
        if not raw.strip():
            continue
        try:
            payload = json.loads(raw)
        except json.JSONDecodeError as exc:
            raise EventValidationError(f"malformed JSON in {path} (line {lineno})") from exc
        events.append(validate_event(payload))
    return events
```

- [ ] **Step 4: Run to verify pass**

Run: `cd agent_journal && uv run pytest tests/test_events.py -q`
Expected: PASS, 100% coverage for `events.py`.

- [ ] **Step 5: Lint, type-check, commit**

```bash
cd agent_journal && uv run ruff check . && uv run ruff format --check . && uv run ty check .
git add agent_journal/src/agent_journal/events.py agent_journal/tests/test_events.py
git commit -m "feat(agent-journal): add explicit event schema and JSONL store"
```

---

## Task 3: Secret redaction (`redaction.py`)

**Files:**
- Create: `agent_journal/src/agent_journal/redaction.py`
- Test: `agent_journal/tests/test_redaction.py`

> **CRITICAL:** Assemble every secret-shaped fixture via concatenation so the
> file contains no complete secret literal (Gotcha #1). Do not "fix" the tests
> by writing whole tokens — that will block the commit on gitleaks.

- [ ] **Step 1: Write the failing tests**

```python
"""Unit tests for secret/token redaction.

All secret-shaped fixtures are assembled via concatenation so this file
contains no complete secret literal (gitleaks / detect-private-key would
otherwise block the commit).
"""

import re

from agent_journal.redaction import REDACTION_PLACEHOLDER, compile_patterns, redact


def test_redacts_github_token() -> None:
    token = "ghp_" + ("a1B2c3" * 6) + "abcd"  # 40 chars after prefix
    assert token not in redact(f"export TOKEN={token}")
    assert REDACTION_PLACEHOLDER in redact(f"export TOKEN={token}")


def test_redacts_openai_key() -> None:
    key = "sk-" + ("A9b8C7d6" * 6)
    assert key not in redact(f"key={key}")


def test_redacts_aws_access_key_id() -> None:
    akid = "AKIA" + "IOSFODNN7EXAMPLE"
    assert akid not in redact(f"aws_access_key_id = {akid}")


def test_redacts_slack_token() -> None:
    token = "xoxb-" + "123456789012-1234567890123-" + ("Ab3" * 8)
    assert token not in redact(token)


def test_redacts_private_key_header() -> None:
    block = "-----BEGIN RSA " + "PRIVATE KEY-----"
    assert "PRIVATE KEY" not in redact(block)


def test_redacts_bearer_token() -> None:
    header = "Authorization: Bearer " + ("xY9" * 12)
    redacted = redact(header)
    assert ("xY9" * 12) not in redacted


def test_redacts_jwt() -> None:
    jwt = "eyJ" + "abc.eyJ" + "def.sig" + ("Z9" * 10)
    assert jwt not in redact(jwt)


def test_leaves_ordinary_text_untouched() -> None:
    text = "Ran terraform plan; remaining drift is expected."
    assert redact(text) == text


def test_extra_patterns_are_applied() -> None:
    patterns = compile_patterns(extra=[r"SEKRIT-\d+"])
    assert "SEKRIT-42" not in redact("value SEKRIT-42 here", patterns)


def test_compile_patterns_returns_compiled_regexes() -> None:
    patterns = compile_patterns()
    assert patterns and all(isinstance(p, re.Pattern) for p in patterns)


def test_redact_uses_default_patterns_when_none_passed() -> None:
    akid = "AKIA" + "IOSFODNN7EXAMPLE"
    assert akid not in redact(akid, None)
```

- [ ] **Step 2: Run to verify failure**

Run: `cd agent_journal && uv run pytest tests/test_redaction.py -q`
Expected: FAIL — module missing.

- [ ] **Step 3: Implement `redaction.py`**

```python
"""Redact obvious secrets and high-risk tokens before any summarization.

The patterns target common credential shapes. They are intentionally
conservative — better to over-redact a transcript excerpt than to leak a key
into a long-lived Obsidian note.
"""

from __future__ import annotations

import re
from collections.abc import Sequence

REDACTION_PLACEHOLDER = "[REDACTED]"

_DEFAULT_PATTERN_SOURCES: tuple[str, ...] = (
    r"-----BEGIN[ A-Z]*PRIVATE KEY-----",          # PEM private key header
    r"\bAKIA[0-9A-Z]{16}\b",                        # AWS access key id
    r"\bghp_[A-Za-z0-9]{36,}\b",                    # GitHub personal token
    r"\bgh[opsu]_[A-Za-z0-9]{36,}\b",               # other GitHub tokens
    r"\bsk-[A-Za-z0-9]{20,}\b",                     # OpenAI-style key
    r"\bxox[baprs]-[A-Za-z0-9-]{10,}\b",            # Slack token
    r"\beyJ[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{4,}\.[A-Za-z0-9_-]{4,}\b",  # JWT
    r"(?i)\bBearer\s+[A-Za-z0-9._\-]{12,}",         # bearer auth header
)


def compile_patterns(extra: Sequence[str] = ()) -> tuple[re.Pattern[str], ...]:
    """Compile the built-in patterns plus any extra regex sources.

    Args:
        extra: Additional regex source strings from configuration.

    Returns:
        A tuple of compiled patterns, built-ins first.
    """
    sources = (*_DEFAULT_PATTERN_SOURCES, *extra)
    return tuple(re.compile(src) for src in sources)


_DEFAULT_PATTERNS: tuple[re.Pattern[str], ...] = compile_patterns()


def redact(text: str, patterns: Sequence[re.Pattern[str]] | None = None) -> str:
    """Replace every secret-shaped match with :data:`REDACTION_PLACEHOLDER`.

    Args:
        text: Input text (a transcript excerpt or event summary).
        patterns: Compiled patterns to apply; defaults to the built-ins.

    Returns:
        The text with all matches replaced.
    """
    active = _DEFAULT_PATTERNS if patterns is None else patterns
    for pattern in active:
        text = pattern.sub(REDACTION_PLACEHOLDER, text)
    return text
```

- [ ] **Step 4: Run to verify pass**

Run: `cd agent_journal && uv run pytest tests/test_redaction.py -q`
Expected: PASS, 100% coverage.

- [ ] **Step 5: Lint, type-check, commit**

```bash
cd agent_journal && uv run ruff check . && uv run ruff format --check . && uv run ty check .
git add agent_journal/src/agent_journal/redaction.py agent_journal/tests/test_redaction.py
git commit -m "feat(agent-journal): add secret redaction"
```

---

## Task 4: Config + workstreams loading (`config.py`)

**Files:**
- Create: `agent_journal/src/agent_journal/config.py`
- Test: `agent_journal/tests/test_config.py`

- [ ] **Step 1: Write the failing tests**

```python
"""Unit tests for config.toml and workstreams.toml loading."""

from pathlib import Path

import pytest

from agent_journal.config import ConfigError, load_config, load_workstreams


def _write(path: Path, text: str) -> Path:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text, encoding="utf-8")
    return path


def test_load_config_full(tmp_path: Path) -> None:
    cfg_path = _write(
        tmp_path / "config.toml",
        """
        machine = "work-mac"
        context = "work"
        standup_hour = 9

        [vault]
        path = "/vault"
        daily_dir = "Daily"
        daily_note_path_format = "%Y/%m/%d-%a"
        workstreams_dir = "Workstreams"
        sessions_dir = "Agent Sessions"

        [state]
        dir = "/state/agent-journal"

        [adapters]
        enabled = ["codex", "claude_code"]

        [adapters.codex]
        sessions_glob = "/home/.codex/archived_sessions/*.jsonl"

        [adapters.claude_code]
        projects_dir = "/home/.claude/projects"

        [redaction]
        extra_patterns = ["SEKRIT-\\\\d+"]
        """,
    )
    cfg = load_config(cfg_path)
    assert cfg.machine == "work-mac"
    assert cfg.context == "work"
    assert cfg.standup_hour == 9
    assert cfg.vault.path == Path("/vault")
    assert cfg.state_dir == Path("/state/agent-journal")
    assert cfg.enabled_adapters == ("codex", "claude_code")
    assert cfg.codex is not None and cfg.codex.sessions_glob.endswith("*.jsonl")
    assert cfg.claude_code is not None and cfg.claude_code.projects_dir == Path("/home/.claude/projects")
    assert cfg.redaction_extra == ("SEKRIT-\\d+",)


def test_load_config_applies_defaults(tmp_path: Path) -> None:
    cfg_path = _write(tmp_path / "config.toml", '[vault]\npath = "/vault"\n')
    cfg = load_config(cfg_path)
    assert cfg.vault.daily_dir == "Daily"
    assert cfg.vault.daily_note_path_format == "%Y/%m/%d-%a"
    assert cfg.vault.workstreams_dir == "Workstreams"
    assert cfg.vault.sessions_dir == "Agent Sessions"
    assert cfg.enabled_adapters == ("codex", "claude_code")
    assert cfg.standup_hour == 8
    assert cfg.state_dir.name == "agent-journal"
    assert cfg.redaction_extra == ()


def test_load_config_disabled_adapter_is_none(tmp_path: Path) -> None:
    cfg_path = _write(
        tmp_path / "config.toml",
        '[vault]\npath = "/vault"\n[adapters]\nenabled = ["codex"]\n[adapters.codex]\nsessions_glob = "/g/*.jsonl"\n',
    )
    cfg = load_config(cfg_path)
    assert cfg.codex is not None
    assert cfg.claude_code is None


def test_load_config_missing_file(tmp_path: Path) -> None:
    with pytest.raises(ConfigError, match="config not found"):
        load_config(tmp_path / "absent.toml")


def test_load_config_requires_vault_path(tmp_path: Path) -> None:
    cfg_path = _write(tmp_path / "config.toml", "machine = \"x\"\n")
    with pytest.raises(ConfigError, match="vault.path is required"):
        load_config(cfg_path)


def test_load_workstreams(tmp_path: Path) -> None:
    ws_path = _write(
        tmp_path / "workstreams.toml",
        """
        [[workstream]]
        name = "LA-3141 databricks compute plane"
        jira = "LA-3141"
        context = "work"
        aliases = ["databricks compute"]
        repos = ["terraform", "k8s-config"]

        [[workstream]]
        name = "dotfiles"
        aliases = ["chezmoi"]
        repos = ["dotfiles"]
        """,
    )
    workstreams = load_workstreams(ws_path)
    assert [w.name for w in workstreams] == ["LA-3141 databricks compute plane", "dotfiles"]
    assert workstreams[0].jira == "LA-3141"
    assert workstreams[1].jira is None
    assert workstreams[1].context is None
    assert workstreams[0].aliases == ("databricks compute",)


def test_load_workstreams_missing_file_returns_empty(tmp_path: Path) -> None:
    assert load_workstreams(tmp_path / "absent.toml") == []


def test_load_workstreams_requires_name(tmp_path: Path) -> None:
    ws_path = _write(tmp_path / "workstreams.toml", "[[workstream]]\njira = \"X-1\"\n")
    with pytest.raises(ConfigError, match="workstream requires a name"):
        load_workstreams(ws_path)
```

- [ ] **Step 2: Run to verify failure**

Run: `cd agent_journal && uv run pytest tests/test_config.py -q`
Expected: FAIL — module missing.

- [ ] **Step 3: Implement `config.py`**

```python
"""Load and validate ``config.toml`` and ``workstreams.toml`` into dataclasses."""

from __future__ import annotations

import tomllib
from collections.abc import Mapping, Sequence
from dataclasses import dataclass
from pathlib import Path


class ConfigError(ValueError):
    """Raised when configuration is missing or malformed."""


@dataclass(frozen=True)
class Workstream:
    """A known workstream used for resolution."""

    name: str
    jira: str | None
    context: str | None
    aliases: tuple[str, ...]
    repos: tuple[str, ...]


@dataclass(frozen=True)
class VaultConfig:
    """Obsidian vault layout configuration."""

    path: Path
    daily_dir: str
    daily_note_path_format: str
    workstreams_dir: str
    sessions_dir: str


@dataclass(frozen=True)
class CodexAdapterConfig:
    """Codex adapter configuration."""

    sessions_glob: str


@dataclass(frozen=True)
class ClaudeAdapterConfig:
    """Claude Code adapter configuration."""

    projects_dir: Path


@dataclass(frozen=True)
class Config:
    """Top-level agent-journal configuration."""

    machine: str
    context: str
    vault: VaultConfig
    state_dir: Path
    enabled_adapters: tuple[str, ...]
    codex: CodexAdapterConfig | None
    claude_code: ClaudeAdapterConfig | None
    redaction_extra: tuple[str, ...]
    standup_hour: int


def _str_tuple(value: object) -> tuple[str, ...]:
    """Coerce a TOML array into a tuple of strings (empty for non-lists)."""
    if isinstance(value, list):
        return tuple(str(item) for item in value)
    return ()


def load_config(path: Path) -> Config:
    """Load and validate the main configuration file.

    Args:
        path: Path to ``config.toml``.

    Returns:
        A populated :class:`Config`.

    Raises:
        ConfigError: If the file is absent or ``[vault].path`` is missing.
    """
    if not path.exists():
        raise ConfigError(f"config not found: {path}")
    data: Mapping[str, object] = tomllib.loads(path.read_text(encoding="utf-8"))

    vault_raw = data.get("vault")
    vault_map = vault_raw if isinstance(vault_raw, Mapping) else {}
    vault_path = vault_map.get("path")
    if not isinstance(vault_path, str) or not vault_path:
        raise ConfigError("vault.path is required")

    vault = VaultConfig(
        path=Path(vault_path),
        daily_dir=str(vault_map.get("daily_dir", "Daily")),
        daily_note_path_format=str(vault_map.get("daily_note_path_format", "%Y/%m/%d-%a")),
        workstreams_dir=str(vault_map.get("workstreams_dir", "Workstreams")),
        sessions_dir=str(vault_map.get("sessions_dir", "Agent Sessions")),
    )

    state_raw = data.get("state")
    state_map = state_raw if isinstance(state_raw, Mapping) else {}
    state_dir = Path(str(state_map.get("dir", str(Path.home() / ".local" / "state" / "agent-journal"))))

    adapters_raw = data.get("adapters")
    adapters_map = adapters_raw if isinstance(adapters_raw, Mapping) else {}
    enabled = _str_tuple(adapters_map.get("enabled", ["codex", "claude_code"]))

    codex_cfg: CodexAdapterConfig | None = None
    codex_map = adapters_map.get("codex")
    if "codex" in enabled and isinstance(codex_map, Mapping):
        codex_cfg = CodexAdapterConfig(sessions_glob=str(codex_map.get("sessions_glob", "")))

    claude_cfg: ClaudeAdapterConfig | None = None
    claude_map = adapters_map.get("claude_code")
    if "claude_code" in enabled and isinstance(claude_map, Mapping):
        claude_cfg = ClaudeAdapterConfig(projects_dir=Path(str(claude_map.get("projects_dir", ""))))

    redaction_raw = data.get("redaction")
    redaction_map = redaction_raw if isinstance(redaction_raw, Mapping) else {}

    return Config(
        machine=str(data.get("machine", "")),
        context=str(data.get("context", "personal")),
        vault=vault,
        state_dir=state_dir,
        enabled_adapters=enabled,
        codex=codex_cfg,
        claude_code=claude_cfg,
        redaction_extra=_str_tuple(redaction_map.get("extra_patterns", [])),
        standup_hour=int(data.get("standup_hour", 8)),  # type: ignore[call-overload]
    )


def load_workstreams(path: Path) -> list[Workstream]:
    """Load known workstreams from ``workstreams.toml``.

    Args:
        path: Path to ``workstreams.toml``.

    Returns:
        Workstreams in file order; an empty list if the file is absent.

    Raises:
        ConfigError: If a ``[[workstream]]`` entry lacks a name.
    """
    if not path.exists():
        return []
    data = tomllib.loads(path.read_text(encoding="utf-8"))
    raw_entries = data.get("workstream", [])
    entries: Sequence[Mapping[str, object]] = raw_entries if isinstance(raw_entries, list) else []
    workstreams: list[Workstream] = []
    for entry in entries:
        name = entry.get("name")
        if not isinstance(name, str) or not name:
            raise ConfigError("workstream requires a name")
        jira = entry.get("jira")
        context = entry.get("context")
        workstreams.append(
            Workstream(
                name=name,
                jira=jira if isinstance(jira, str) else None,
                context=context if isinstance(context, str) else None,
                aliases=_str_tuple(entry.get("aliases", [])),
                repos=_str_tuple(entry.get("repos", [])),
            )
        )
    return workstreams
```

- [ ] **Step 4: Run to verify pass**

Run: `cd agent_journal && uv run pytest tests/test_config.py -q`
Expected: PASS, 100% coverage. (If `ty` flags the `standup_hour` cast, keep the `# type: ignore` comment.)

- [ ] **Step 5: Lint, type-check, commit**

```bash
cd agent_journal && uv run ruff check . && uv run ruff format --check . && uv run ty check .
git add agent_journal/src/agent_journal/config.py agent_journal/tests/test_config.py
git commit -m "feat(agent-journal): add config and workstreams loading"
```

---

## Task 5: State directory, watermarks, JSON helpers (`state.py`)

**Files:**
- Create: `agent_journal/src/agent_journal/state.py`
- Test: `agent_journal/tests/test_state.py`

- [ ] **Step 1: Write the failing tests**

```python
"""Unit tests for state persistence: watermarks and JSON helpers."""

from pathlib import Path

from agent_journal.state import (
    Watermark,
    default_state_dir,
    load_watermarks,
    read_json,
    save_watermarks,
    write_json,
)


def test_default_state_dir_uses_xdg(monkeypatch, tmp_path: Path) -> None:
    monkeypatch.setenv("XDG_STATE_HOME", str(tmp_path / "xdg"))
    assert default_state_dir() == tmp_path / "xdg" / "agent-journal"


def test_default_state_dir_falls_back_to_home(monkeypatch, tmp_path: Path) -> None:
    monkeypatch.delenv("XDG_STATE_HOME", raising=False)
    monkeypatch.setattr(Path, "home", classmethod(lambda cls: tmp_path / "home"))
    assert default_state_dir() == tmp_path / "home" / ".local" / "state" / "agent-journal"


def test_watermarks_roundtrip(tmp_path: Path) -> None:
    path = tmp_path / "watermarks.json"
    marks = {
        "codex:abc": Watermark(source_key="codex:abc", offset=42, last_id="t9", last_time="2026-06-15T08:00:00"),
        "claude:def": Watermark(source_key="claude:def", offset=7),
    }
    save_watermarks(path, marks)
    loaded = load_watermarks(path)
    assert loaded["codex:abc"].offset == 42
    assert loaded["codex:abc"].last_id == "t9"
    assert loaded["claude:def"].offset == 7
    assert loaded["claude:def"].last_id is None


def test_load_watermarks_missing_file(tmp_path: Path) -> None:
    assert load_watermarks(tmp_path / "absent.json") == {}


def test_read_json_missing_returns_default(tmp_path: Path) -> None:
    assert read_json(tmp_path / "absent.json", {"k": 1}) == {"k": 1}


def test_write_then_read_json(tmp_path: Path) -> None:
    path = tmp_path / "nested" / "data.json"
    write_json(path, {"hello": "world"})
    assert read_json(path, {}) == {"hello": "world"}
```

- [ ] **Step 2: Run to verify failure**

Run: `cd agent_journal && uv run pytest tests/test_state.py -q`
Expected: FAIL — module missing.

- [ ] **Step 3: Implement `state.py`**

```python
"""Local state: state-dir resolution, watermarks, and JSON read/write helpers."""

from __future__ import annotations

import json
import os
from collections.abc import Mapping
from dataclasses import dataclass
from pathlib import Path
from typing import Any


@dataclass
class Watermark:
    """Per-source progress marker so repeated runs summarize only new material.

    Attributes:
        source_key: Stable identity of the source (e.g. ``codex:<session-id>``).
        offset: Number of source records already consumed (line count).
        last_id: Optional last-seen record id (turn/uuid) for cross-checks.
        last_time: Optional ISO timestamp of the last consumed record.
    """

    source_key: str
    offset: int = 0
    last_id: str | None = None
    last_time: str | None = None


def default_state_dir() -> Path:
    """Return the default state directory, honoring ``$XDG_STATE_HOME``."""
    xdg = os.environ.get("XDG_STATE_HOME")
    base = Path(xdg) if xdg else Path.home() / ".local" / "state"
    return base / "agent-journal"


def read_json(path: Path, default: Any) -> Any:
    """Read JSON from ``path`` or return ``default`` if it does not exist."""
    if not path.exists():
        return default
    return json.loads(path.read_text(encoding="utf-8"))


def write_json(path: Path, data: Any) -> None:
    """Write ``data`` as pretty JSON, creating parent directories."""
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(data, indent=2, sort_keys=True) + "\n", encoding="utf-8")


def load_watermarks(path: Path) -> dict[str, Watermark]:
    """Load watermarks keyed by source identity."""
    raw: Mapping[str, Mapping[str, object]] = read_json(path, {})
    result: dict[str, Watermark] = {}
    for key, value in raw.items():
        result[key] = Watermark(
            source_key=key,
            offset=int(value.get("offset", 0)),  # type: ignore[arg-type]
            last_id=value.get("last_id"),  # type: ignore[arg-type]
            last_time=value.get("last_time"),  # type: ignore[arg-type]
        )
    return result


def save_watermarks(path: Path, marks: Mapping[str, Watermark]) -> None:
    """Persist watermarks as JSON."""
    serializable = {
        key: {"offset": mark.offset, "last_id": mark.last_id, "last_time": mark.last_time}
        for key, mark in marks.items()
    }
    write_json(path, serializable)
```

- [ ] **Step 4: Run to verify pass**

Run: `cd agent_journal && uv run pytest tests/test_state.py -q`
Expected: PASS, 100% coverage.

- [ ] **Step 5: Lint, type-check, commit**

```bash
cd agent_journal && uv run ruff check . && uv run ruff format --check . && uv run ty check .
git add agent_journal/src/agent_journal/state.py agent_journal/tests/test_state.py
git commit -m "feat(agent-journal): add state dir, watermarks, json helpers"
```

---

## Task 6: Obsidian paths and idempotent section writing (`obsidian.py`)

**Files:**
- Create: `agent_journal/src/agent_journal/obsidian.py`
- Test: `agent_journal/tests/test_obsidian.py`

- [ ] **Step 1: Write the failing tests**

```python
"""Unit tests for Obsidian path calculation and idempotent section writing."""

from datetime import date
from pathlib import Path

from agent_journal.obsidian import (
    append_activity_line,
    daily_note_path,
    read_section,
    read_text,
    replace_section,
    write_text,
)


def test_daily_note_path() -> None:
    path = daily_note_path(Path("/vault"), "Daily", "%Y/%m/%d-%a", date(2026, 6, 15))
    assert path == Path("/vault/Daily/2026/06/15-Mon.md")


def test_replace_section_replaces_existing_only() -> None:
    content = "## A\nkeep a\n\n## Standup Draft\nold\n\n## B\nkeep b\n"
    out = replace_section(content, "## Standup Draft", "new line\n")
    assert "new line" in out
    assert "old" not in out
    assert "keep a" in out and "keep b" in out
    # Idempotent: replacing with the same body twice is stable.
    assert replace_section(out, "## Standup Draft", "new line\n") == out


def test_replace_section_appends_when_missing() -> None:
    content = "## A\nkeep a\n"
    out = replace_section(content, "## Standup Draft", "fresh\n")
    assert out.endswith("## Standup Draft\nfresh\n")
    assert "keep a" in out


def test_replace_section_does_not_match_subheaders_or_other_sections() -> None:
    content = "## Standup Draft\nbody\n### Standup Draft\nsub\n## Other\nx\n"
    out = replace_section(content, "## Standup Draft", "Z\n")
    assert "### Standup Draft" in out  # subheader untouched
    assert "## Other\nx" in out


def test_read_section_returns_body_or_none() -> None:
    content = "## Decisions\n- d1\n- d2\n## Notes\nn\n"
    assert read_section(content, "## Decisions") == "- d1\n- d2"
    assert read_section(content, "## Absent") is None


def test_append_activity_line_creates_section_and_dedupes() -> None:
    content = "## Notes\nn\n"
    once = append_activity_line(content, "14:00", "LA-3141 compute", "updated terraform", "Workstreams")
    assert "## Agent Activity" in once
    assert "- 14:00 [[Workstreams/LA-3141 compute]]: updated terraform" in once
    twice = append_activity_line(once, "14:00", "LA-3141 compute", "updated terraform AGAIN", "Workstreams")
    # Same time+workstream key already present -> no duplicate line added.
    assert twice.count("[[Workstreams/LA-3141 compute]]") == 1


def test_append_activity_line_adds_distinct_entries() -> None:
    content = append_activity_line("", "14:00", "WS-A", "did a", "Workstreams")
    content = append_activity_line(content, "15:00", "WS-A", "did b", "Workstreams")
    assert content.count("[[Workstreams/WS-A]]") == 2


def test_read_text_and_write_text(tmp_path: Path) -> None:
    path = tmp_path / "a" / "b.md"
    assert read_text(path) == ""
    write_text(path, "hello\n")
    assert read_text(path) == "hello\n"
```

- [ ] **Step 2: Run to verify failure**

Run: `cd agent_journal && uv run pytest tests/test_obsidian.py -q`
Expected: FAIL — module missing.

- [ ] **Step 3: Implement `obsidian.py`**

```python
"""Obsidian vault IO: daily-note paths and idempotent markdown section editing.

Section editing is line-based (never raw regex over the whole document) so that
``## Standup Draft`` is replaced without disturbing ``### Standup Draft`` or any
other ``## Section``. All writers are idempotent: running twice is a no-op.
"""

from __future__ import annotations

from datetime import date
from pathlib import Path

_ACTIVITY_HEADER = "## Agent Activity"


def daily_note_path(vault: Path, daily_dir: str, fmt: str, day: date) -> Path:
    """Compute the daily note path for ``day``.

    Args:
        vault: Vault root.
        daily_dir: Subdirectory holding daily notes (e.g. ``Daily``).
        fmt: ``strftime`` pattern (``%Y/%m/%d-%a`` == Obsidian ``YYYY/MM/DD-ddd``).
        day: The calendar day.

    Returns:
        Absolute path to the ``.md`` daily note.
    """
    return vault / daily_dir / f"{day.strftime(fmt)}.md"


def _section_bounds(lines: list[str], header: str) -> tuple[int, int] | None:
    """Find the [start, end) line indices of a section's region (header + body).

    The region ends at the next line beginning with ``## `` at the same level,
    or end-of-file. Returns ``None`` if the header is absent.
    """
    start: int | None = None
    for index, line in enumerate(lines):
        if start is None:
            if line.rstrip() == header:
                start = index
            continue
        if line.startswith("## "):
            return (start, index)
    if start is None:
        return None
    return (start, len(lines))


def replace_section(content: str, header: str, body: str) -> str:
    """Replace the body under ``header`` with ``body`` (append the section if absent).

    Args:
        content: Full markdown document.
        header: Exact section header line, e.g. ``## Standup Draft``.
        body: New body text (the header line is added automatically).

    Returns:
        Updated document. Idempotent for a fixed ``body``.
    """
    new_block = f"{header}\n{body}" if body.endswith("\n") else f"{header}\n{body}\n"
    lines = content.splitlines(keepends=True)
    bounds = _section_bounds(lines, header)
    if bounds is None:
        prefix = content if content == "" or content.endswith("\n") else content + "\n"
        return prefix + new_block
    start, end = bounds
    return "".join(lines[:start]) + new_block + "".join(lines[end:])


def read_section(content: str, header: str) -> str | None:
    """Return the trimmed body under ``header``, or ``None`` if absent."""
    lines = content.splitlines(keepends=True)
    bounds = _section_bounds(lines, header)
    if bounds is None:
        return None
    start, end = bounds
    body = "".join(lines[start + 1 : end])
    return body.strip()


def append_activity_line(content: str, time_str: str, workstream: str, summary: str, workstreams_dir: str) -> str:
    """Append a compact, deduplicated entry to the daily ``## Agent Activity`` section.

    Args:
        content: Daily note markdown.
        time_str: ``HH:MM`` timestamp.
        workstream: Workstream name (linked to ``<workstreams_dir>/<name>``).
        summary: Short index summary.
        workstreams_dir: Vault subdirectory holding workstream notes.

    Returns:
        Updated markdown. Dedupes on the ``HH:MM [[dir/name]]`` key so re-running
        the digest never duplicates an entry.
    """
    link = f"[[{workstreams_dir}/{workstream}]]"
    key = f"- {time_str} {link}"
    body = read_section(content, _ACTIVITY_HEADER)
    if body is not None and key in body:
        return content
    new_line = f"{key}: {summary}"
    if body is None:
        return replace_section(content, _ACTIVITY_HEADER, new_line + "\n")
    merged = (body + "\n" + new_line).strip() + "\n"
    return replace_section(content, _ACTIVITY_HEADER, merged)


def read_text(path: Path) -> str:
    """Read a file, returning an empty string if it does not exist."""
    if not path.exists():
        return ""
    return path.read_text(encoding="utf-8")


def write_text(path: Path, content: str) -> None:
    """Write ``content`` to ``path``, creating parent directories."""
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(content, encoding="utf-8")
```

- [ ] **Step 4: Run to verify pass**

Run: `cd agent_journal && uv run pytest tests/test_obsidian.py -q`
Expected: PASS, 100% coverage.

- [ ] **Step 5: Lint, type-check, commit**

```bash
cd agent_journal && uv run ruff check . && uv run ruff format --check . && uv run ty check .
git add agent_journal/src/agent_journal/obsidian.py agent_journal/tests/test_obsidian.py
git commit -m "feat(agent-journal): add Obsidian paths and idempotent section writing"
```

---

## Task 7: Workstream resolver (`resolver.py`)

**Files:**
- Create: `agent_journal/src/agent_journal/resolver.py`
- Test: `agent_journal/tests/test_resolver.py`

- [ ] **Step 1: Write the failing tests**

```python
"""Unit tests for workstream resolution."""

from agent_journal.config import Workstream
from agent_journal.resolver import Resolution, extract_jira_keys, resolve_workstream

WS = [
    Workstream(name="LA-3141 databricks compute plane", jira="LA-3141", context="work",
               aliases=("databricks compute",), repos=("terraform", "k8s-config")),
    Workstream(name="dotfiles", jira=None, context="personal",
               aliases=("chezmoi",), repos=("dotfiles",)),
]


def test_extract_jira_keys() -> None:
    assert extract_jira_keys("fix LA-3141 and ABC-12", None, "branch/LA-3141") == ["LA-3141", "ABC-12"]
    assert extract_jira_keys(None) == []


def test_explicit_match_is_authoritative() -> None:
    res = resolve_workstream(explicit="anything new", cwd=None, branch=None, repo_url=None, prompt=None, workstreams=WS)
    assert res == Resolution(status="matched", workstream="anything new", candidates=("anything new",), reason="explicit")


def test_explicit_resolves_to_known_name_via_alias() -> None:
    res = resolve_workstream(explicit="chezmoi", cwd=None, branch=None, repo_url=None, prompt=None, workstreams=WS)
    assert res.status == "matched"
    assert res.workstream == "dotfiles"
    assert res.reason == "explicit-alias"


def test_jira_branch_match() -> None:
    res = resolve_workstream(explicit=None, cwd=None, branch="feature/LA-3141-compute",
                             repo_url=None, prompt=None, workstreams=WS)
    assert res.status == "matched"
    assert res.workstream == "LA-3141 databricks compute plane"
    assert res.reason == "jira"


def test_repo_match_from_cwd() -> None:
    res = resolve_workstream(explicit=None, cwd="/Users/x/projects/dotfiles", branch=None,
                             repo_url=None, prompt=None, workstreams=WS)
    assert res.status == "matched"
    assert res.workstream == "dotfiles"
    assert res.reason == "repo"


def test_repo_match_from_repo_url() -> None:
    res = resolve_workstream(explicit=None, cwd=None, branch=None,
                             repo_url="git@github.com:org/k8s-config.git", prompt=None, workstreams=WS)
    assert res.status == "matched"
    assert res.workstream == "LA-3141 databricks compute plane"


def test_alias_in_prompt_match() -> None:
    res = resolve_workstream(explicit=None, cwd=None, branch=None, repo_url=None,
                             prompt="working on databricks compute today", workstreams=WS)
    assert res.status == "matched"
    assert res.reason == "alias"


def test_ambiguous_when_multiple_candidates() -> None:
    res = resolve_workstream(explicit=None, cwd="/x/dotfiles", branch="LA-3141",
                             repo_url=None, prompt=None, workstreams=WS)
    assert res.status == "ambiguous"
    assert set(res.candidates) == {"dotfiles", "LA-3141 databricks compute plane"}
    assert res.workstream is None


def test_unknown_when_no_signal() -> None:
    res = resolve_workstream(explicit=None, cwd="/x/unrelated", branch="main",
                             repo_url=None, prompt="hello", workstreams=WS)
    assert res.status == "unknown"
    assert res.candidates == ()


def test_unknown_with_empty_workstreams() -> None:
    res = resolve_workstream(explicit=None, cwd="/x/dotfiles", branch=None,
                             repo_url=None, prompt=None, workstreams=[])
    assert res.status == "unknown"
```

- [ ] **Step 2: Run to verify failure**

Run: `cd agent_journal && uv run pytest tests/test_resolver.py -q`
Expected: FAIL — module missing.

- [ ] **Step 3: Implement `resolver.py`**

```python
"""Resolve agent activity to a known workstream using layered signals.

Order of authority: an explicit workstream (from ``agent-note``) always wins.
Otherwise candidates are gathered from Jira keys, repo names (cwd / git remote),
and alias mentions. Exactly one candidate is a confident match; multiple is
ambiguous; none is unknown. Ambiguous/unknown never trigger a durable write —
they surface in ``agent-journal status`` for manual classification.
"""

from __future__ import annotations

import re
from collections.abc import Sequence
from dataclasses import dataclass

from agent_journal.config import Workstream

_JIRA_RE = re.compile(r"\b([A-Z][A-Z0-9]+-\d+)\b")


@dataclass(frozen=True)
class Resolution:
    """Outcome of workstream resolution."""

    status: str
    workstream: str | None
    candidates: tuple[str, ...]
    reason: str


def extract_jira_keys(*texts: str | None) -> list[str]:
    """Extract unique Jira-style keys (e.g. ``LA-3141``) preserving first-seen order."""
    seen: list[str] = []
    for text in texts:
        if not text:
            continue
        for match in _JIRA_RE.findall(text):
            if match not in seen:
                seen.append(match)
    return seen


def _repo_tokens(cwd: str | None, repo_url: str | None) -> set[str]:
    """Collect candidate repo identifiers from cwd basename and git remote."""
    tokens: set[str] = set()
    if cwd:
        tokens.add(cwd.rstrip("/").rsplit("/", 1)[-1])
    if repo_url:
        tail = repo_url.rstrip("/").rsplit("/", 1)[-1]
        tokens.add(tail.removesuffix(".git"))
    return {t for t in tokens if t}


def _match_explicit(explicit: str, workstreams: Sequence[Workstream]) -> Resolution:
    """Resolve an explicit workstream string, mapping aliases to canonical names."""
    lowered = explicit.lower()
    for ws in workstreams:
        if ws.name.lower() == lowered:
            return Resolution("matched", ws.name, (ws.name,), "explicit")
    for ws in workstreams:
        if lowered in {alias.lower() for alias in ws.aliases}:
            return Resolution("matched", ws.name, (ws.name,), "explicit-alias")
    return Resolution("matched", explicit, (explicit,), "explicit")


def resolve_workstream(
    *,
    explicit: str | None,
    cwd: str | None,
    branch: str | None,
    repo_url: str | None,
    prompt: str | None,
    workstreams: Sequence[Workstream],
) -> Resolution:
    """Resolve activity to a workstream.

    Returns:
        A :class:`Resolution`. ``matched`` carries the resolved name; ``ambiguous``
        carries every candidate; ``unknown`` carries no candidates.
    """
    if explicit:
        return _match_explicit(explicit, workstreams)

    jira_keys = set(extract_jira_keys(branch, prompt))
    repo_tokens = _repo_tokens(cwd, repo_url)
    prompt_lower = (prompt or "").lower()

    candidates: list[tuple[str, str]] = []  # (workstream name, reason)
    for ws in workstreams:
        if ws.jira and ws.jira in jira_keys:
            candidates.append((ws.name, "jira"))
            continue
        if repo_tokens & set(ws.repos):
            candidates.append((ws.name, "repo"))
            continue
        if prompt_lower and any(alias.lower() in prompt_lower for alias in ws.aliases):
            candidates.append((ws.name, "alias"))

    unique = list(dict.fromkeys(name for name, _ in candidates))
    if len(unique) == 1:
        reason = next(reason for name, reason in candidates if name == unique[0])
        return Resolution("matched", unique[0], (unique[0],), reason)
    if len(unique) > 1:
        return Resolution("ambiguous", None, tuple(unique), "multiple-candidates")
    return Resolution("unknown", None, (), "no-signal")
```

- [ ] **Step 4: Run to verify pass**

Run: `cd agent_journal && uv run pytest tests/test_resolver.py -q`
Expected: PASS, 100% coverage.

- [ ] **Step 5: Lint, type-check, commit**

```bash
cd agent_journal && uv run ruff check . && uv run ruff format --check . && uv run ty check .
git add agent_journal/src/agent_journal/resolver.py agent_journal/tests/test_resolver.py
git commit -m "feat(agent-journal): add workstream resolver"
```

---

## Task 8: Adapter protocol and bounding helper (`adapters/base.py`)

**Files:**
- Create: `agent_journal/src/agent_journal/adapters/base.py`
- Test: `agent_journal/tests/test_adapter_base.py`

- [ ] **Step 1: Write the failing tests**

```python
"""Unit tests for the adapter base types and bounding helper."""

from agent_journal.adapters.base import NormalizedSession, bounded


def test_bounded_caps_item_count_and_chars() -> None:
    result = bounded(["a" * 100, "b" * 100, "c" * 100], max_items=2, max_chars=10)
    assert len(result) == 2
    assert all(len(item) <= 10 for item in result)


def test_bounded_skips_blank_entries() -> None:
    assert bounded(["", "  ", "real"], max_items=5, max_chars=50) == ("real",)


def test_normalized_session_is_frozen_and_hashable() -> None:
    session = NormalizedSession(
        tool="codex", machine="work", session_id="abc", cwd="/r", branch="main",
        repo_url=None, title="t", started_at="2026-06-15T13:00:00", last_time="2026-06-15T13:30:00",
        narrative=("did x",), new_message_count=1, new_offset=10, source_path="/p.jsonl",
    )
    assert session in {session}
    assert session.new_offset == 10
```

- [ ] **Step 2: Run to verify failure**

Run: `cd agent_journal && uv run pytest tests/test_adapter_base.py -q`
Expected: FAIL — module missing.

- [ ] **Step 3: Implement `adapters/base.py`**

```python
"""Adapter protocol and shared normalized-session model.

Each adapter discovers candidate session files and parses one into a
:class:`NormalizedSession` given the previously consumed offset (watermark). The
``Adapter`` protocol is the single seam OpenCode plugs into later without
touching ingest/digest.
"""

from __future__ import annotations

from collections.abc import Iterable
from dataclasses import dataclass
from pathlib import Path
from typing import Protocol


@dataclass(frozen=True)
class NormalizedSession:
    """A passive session normalized across tools.

    Attributes:
        tool: Source tool (``codex`` / ``claude``).
        machine: Machine context label.
        session_id: Stable per-session id.
        cwd: Working directory (last seen).
        branch: Git branch (last seen).
        repo_url: Git remote URL if known.
        title: Human-friendly session title if known.
        started_at: ISO timestamp of the first record.
        last_time: ISO timestamp of the last consumed record.
        narrative: Redacted, length-bounded message excerpts (new material only).
        new_message_count: Number of new messages consumed this run.
        new_offset: Updated watermark offset (total records consumed).
        source_path: Absolute path to the source file.
    """

    tool: str
    machine: str
    session_id: str
    cwd: str | None
    branch: str | None
    repo_url: str | None
    title: str | None
    started_at: str | None
    last_time: str | None
    narrative: tuple[str, ...]
    new_message_count: int
    new_offset: int
    source_path: str


class Adapter(Protocol):
    """Protocol implemented by every passive session adapter."""

    name: str

    def discover(self) -> list[Path]:
        """Return candidate session files (workflow journals excluded)."""
        ...

    def parse(self, path: Path, previous_offset: int) -> NormalizedSession | None:
        """Parse new records from ``path`` beyond ``previous_offset``."""
        ...


def bounded(texts: Iterable[str], *, max_items: int, max_chars: int) -> tuple[str, ...]:
    """Truncate a stream of excerpts to keep notes compact (never raw dumps).

    Args:
        texts: Candidate excerpt strings.
        max_items: Maximum number of excerpts to keep (most recent are caller's responsibility).
        max_chars: Per-excerpt character cap.

    Returns:
        Cleaned, capped tuple of non-blank excerpts.
    """
    result: list[str] = []
    for text in texts:
        stripped = text.strip()
        if not stripped:
            continue
        result.append(stripped[:max_chars])
        if len(result) >= max_items:
            break
    return tuple(result)
```

- [ ] **Step 4: Run to verify pass**

Run: `cd agent_journal && uv run pytest tests/test_adapter_base.py -q`
Expected: PASS, 100% coverage.

- [ ] **Step 5: Lint, type-check, commit**

```bash
cd agent_journal && uv run ruff check . && uv run ruff format --check . && uv run ty check .
git add agent_journal/src/agent_journal/adapters/base.py agent_journal/tests/test_adapter_base.py
git commit -m "feat(agent-journal): add adapter protocol and bounding helper"
```

---

## Task 9: Codex adapter (`adapters/codex.py`)

**Files:**
- Create: `agent_journal/src/agent_journal/adapters/codex.py`
- Test: `agent_journal/tests/test_adapter_codex.py`

Codex format (verified on-disk): one JSONL per session. First line is
`{"type":"session_meta","payload":{"id","cwd","git":{"branch","repository_url"},"timestamp"}}`;
subsequent lines are `{"type":"event_msg","timestamp","payload":{"type":"user_message"|"agent_message","message":"..."}}`.

- [ ] **Step 1: Write the failing tests**

```python
"""Unit tests for the Codex session adapter."""

from pathlib import Path

from agent_journal.adapters.codex import CodexAdapter
from agent_journal.redaction import compile_patterns
from tests.conftest import write_jsonl

# Assembled via concatenation so the file holds no complete secret literal (Gotcha #1).
_SECRET = "sk-" + "A" * 24


def _session(path: Path) -> None:
    write_jsonl(path, [
        {"type": "session_meta", "timestamp": "2026-06-15T19:00:00.000Z",
         "payload": {"id": "sess-1", "cwd": "/repo/foo", "timestamp": "2026-06-15T19:00:00.000Z",
                     "git": {"branch": "feature/LA-3141", "repository_url": "git@github.com:o/foo.git"}}},
        {"type": "event_msg", "timestamp": "2026-06-15T19:01:00.000Z",
         "payload": {"type": "user_message", "message": "Run terraform plan"}},
        {"type": "event_msg", "timestamp": "2026-06-15T19:02:00.000Z",
         "payload": {"type": "agent_message", "message": f"Planning now; token {_SECRET} leaked"}},
        {"type": "event_msg", "timestamp": "2026-06-15T19:03:00.000Z",
         "payload": {"type": "reasoning", "message": "internal"}},
    ])


def test_discover_globs_sessions(tmp_path: Path) -> None:
    _session(tmp_path / "rollout-1.jsonl")
    adapter = CodexAdapter(sessions_glob=str(tmp_path / "*.jsonl"), machine="work", patterns=compile_patterns())
    assert [p.name for p in adapter.discover()] == ["rollout-1.jsonl"]


def test_parse_extracts_metadata_and_redacted_narrative(tmp_path: Path) -> None:
    path = tmp_path / "rollout-1.jsonl"
    _session(path)
    adapter = CodexAdapter(sessions_glob=str(tmp_path / "*.jsonl"), machine="work", patterns=compile_patterns())
    session = adapter.parse(path, previous_offset=0)
    assert session is not None
    assert session.session_id == "sess-1"
    assert session.cwd == "/repo/foo"
    assert session.branch == "feature/LA-3141"
    assert session.repo_url == "git@github.com:o/foo.git"
    assert session.new_offset == 4
    assert session.new_message_count == 2  # user + agent (reasoning excluded)
    assert any("[REDACTED]" in line for line in session.narrative)
    assert not any(_SECRET in line for line in session.narrative)


def test_parse_respects_watermark_offset(tmp_path: Path) -> None:
    path = tmp_path / "rollout-1.jsonl"
    _session(path)
    adapter = CodexAdapter(sessions_glob=str(tmp_path / "*.jsonl"), machine="work", patterns=compile_patterns())
    session = adapter.parse(path, previous_offset=4)
    assert session is not None
    assert session.new_message_count == 0
    assert session.new_offset == 4


def test_parse_returns_none_without_session_meta(tmp_path: Path) -> None:
    path = tmp_path / "broken.jsonl"
    write_jsonl(path, [{"type": "event_msg", "payload": {"type": "user_message", "message": "hi"}}])
    adapter = CodexAdapter(sessions_glob=str(tmp_path / "*.jsonl"), machine="work", patterns=compile_patterns())
    assert adapter.parse(path, previous_offset=0) is None


def test_parse_skips_blank_and_malformed_lines(tmp_path: Path) -> None:
    path = tmp_path / "rollout-2.jsonl"
    path.write_text(
        '{"type":"session_meta","payload":{"id":"s2","timestamp":"t","cwd":"/c","git":{}}}\n'
        "\n"
        "{bad json}\n"
        '{"type":"event_msg","timestamp":"t2","payload":{"type":"agent_message","message":"ok"}}\n',
        encoding="utf-8",
    )
    adapter = CodexAdapter(sessions_glob=str(tmp_path / "*.jsonl"), machine="work", patterns=compile_patterns())
    session = adapter.parse(path, previous_offset=0)
    assert session is not None
    assert session.branch is None
    assert session.new_message_count == 1
```

- [ ] **Step 2: Run to verify failure**

Run: `cd agent_journal && uv run pytest tests/test_adapter_codex.py -q`
Expected: FAIL — module missing.

- [ ] **Step 3: Implement `adapters/codex.py`**

```python
"""Codex session adapter: parse ``~/.codex/archived_sessions/*.jsonl`` rollouts."""

from __future__ import annotations

import glob
import json
import re
from pathlib import Path

from agent_journal.adapters.base import NormalizedSession, bounded

_MESSAGE_TYPES = ("user_message", "agent_message")
_MAX_NARRATIVE_ITEMS = 12
_MAX_NARRATIVE_CHARS = 280


class CodexAdapter:
    """Adapter for Codex CLI session rollouts."""

    name = "codex"

    def __init__(self, sessions_glob: str, machine: str, patterns: tuple[re.Pattern[str], ...]) -> None:
        """Initialize with the session glob, machine label, and redaction patterns."""
        self._glob = sessions_glob
        self._machine = machine
        self._patterns = patterns

    def discover(self) -> list[Path]:
        """Return Codex session files matching the configured glob, sorted."""
        return sorted(Path(p) for p in glob.glob(self._glob))

    def parse(self, path: Path, previous_offset: int) -> NormalizedSession | None:
        """Parse new records beyond ``previous_offset`` into a normalized session."""
        from agent_journal.redaction import redact

        lines = path.read_text(encoding="utf-8").splitlines()
        meta: dict[str, object] | None = None
        messages: list[str] = []
        started_at: str | None = None
        last_time: str | None = None
        new_count = 0

        for index, raw in enumerate(lines):
            if not raw.strip():
                continue
            try:
                record = json.loads(raw)
            except json.JSONDecodeError:
                continue
            rtype = record.get("type")
            payload = record.get("payload", {})
            if rtype == "session_meta" and meta is None:
                meta = payload
                started_at = payload.get("timestamp") or record.get("timestamp")
            elif rtype == "event_msg" and index >= previous_offset:
                if payload.get("type") in _MESSAGE_TYPES:
                    new_count += 1
                    text = str(payload.get("message", ""))
                    messages.append(redact(text, self._patterns))
                    last_time = record.get("timestamp", last_time)

        if meta is None:
            return None

        git = meta.get("git", {}) if isinstance(meta.get("git"), dict) else {}
        return NormalizedSession(
            tool="codex",
            machine=self._machine,
            session_id=str(meta.get("id", path.stem)),
            cwd=meta.get("cwd"),
            branch=git.get("branch"),
            repo_url=git.get("repository_url"),
            title=None,
            started_at=started_at,
            last_time=last_time,
            narrative=bounded(messages, max_items=_MAX_NARRATIVE_ITEMS, max_chars=_MAX_NARRATIVE_CHARS),
            new_message_count=new_count,
            new_offset=len(lines),
            source_path=str(path),
        )
```

- [ ] **Step 4: Run to verify pass**

Run: `cd agent_journal && uv run pytest tests/test_adapter_codex.py -q`
Expected: PASS, 100% coverage.

- [ ] **Step 5: Lint, type-check, commit**

```bash
cd agent_journal && uv run ruff check . && uv run ruff format --check . && uv run ty check .
git add agent_journal/src/agent_journal/adapters/codex.py agent_journal/tests/test_adapter_codex.py
git commit -m "feat(agent-journal): add Codex session adapter"
```

---

## Task 10: Claude Code adapter + workflow-journal exclusion (`adapters/claude_code.py`)

**Files:**
- Create: `agent_journal/src/agent_journal/adapters/claude_code.py`
- Test: `agent_journal/tests/test_adapter_claude_code.py`

Claude Code format (verified): `~/.claude/projects/<ENCODED_PATH>/<sessionId>.jsonl`.
Each line carries `type`, `uuid`, `timestamp`, `cwd`, `gitBranch`, `sessionId`, and
`message.{role,content}` where content is a string OR a list of content blocks.
**Workflow-journal exclusion:** sub-agent/workflow transcripts live under nested
`subagents/`/`workflows/` directories — only top-level `*.jsonl` are interactive sessions.

- [ ] **Step 1: Write the failing tests**

```python
"""Unit tests for the Claude Code adapter and workflow-journal exclusion."""

from pathlib import Path

from agent_journal.adapters.claude_code import ClaudeCodeAdapter
from agent_journal.redaction import compile_patterns
from tests.conftest import write_jsonl

# Assembled via concatenation so the file holds no complete secret literal (Gotcha #1).
_SECRET = "ghp_" + "A" * 36


def _project(projects_dir: Path) -> Path:
    proj = projects_dir / "-Users-x-projects-foo"
    write_jsonl(proj / "sess-1.jsonl", [
        {"type": "user", "uuid": "u1", "timestamp": "2026-06-15T13:00:00Z", "cwd": "/Users/x/projects/foo",
         "gitBranch": "main", "sessionId": "sess-1", "message": {"role": "user", "content": "do the thing"}},
        {"type": "assistant", "uuid": "a1", "timestamp": "2026-06-15T13:01:00Z", "cwd": "/Users/x/projects/foo",
         "gitBranch": "main", "sessionId": "sess-1",
         "message": {"role": "assistant", "content": [{"type": "text", "text": f"done; key {_SECRET}"}]}},
        {"type": "system", "uuid": "s1", "timestamp": "2026-06-15T13:02:00Z", "cwd": "/Users/x/projects/foo",
         "gitBranch": "main", "sessionId": "sess-1", "message": {"role": "system", "content": "noise"}},
    ])
    # A workflow/subagent journal that MUST be excluded:
    write_jsonl(proj / "subagents" / "workflows" / "agent-9.jsonl", [
        {"type": "user", "uuid": "w1", "timestamp": "t", "cwd": "/Users/x/projects/foo",
         "gitBranch": "main", "sessionId": "wf-9", "message": {"role": "user", "content": "workflow noise"}},
    ])
    return proj


def test_discover_excludes_workflow_journals(tmp_path: Path) -> None:
    _project(tmp_path)
    adapter = ClaudeCodeAdapter(projects_dir=tmp_path, machine="personal", patterns=compile_patterns())
    discovered = [p.name for p in adapter.discover()]
    assert discovered == ["sess-1.jsonl"]


def test_parse_extracts_metadata_and_redacts(tmp_path: Path) -> None:
    proj = _project(tmp_path)
    adapter = ClaudeCodeAdapter(projects_dir=tmp_path, machine="personal", patterns=compile_patterns())
    session = adapter.parse(proj / "sess-1.jsonl", previous_offset=0)
    assert session is not None
    assert session.session_id == "sess-1"
    assert session.cwd == "/Users/x/projects/foo"
    assert session.branch == "main"
    assert session.new_message_count == 2  # user + assistant; system excluded
    assert session.new_offset == 3
    assert not any(_SECRET in line for line in session.narrative)


def test_parse_respects_offset(tmp_path: Path) -> None:
    proj = _project(tmp_path)
    adapter = ClaudeCodeAdapter(projects_dir=tmp_path, machine="personal", patterns=compile_patterns())
    session = adapter.parse(proj / "sess-1.jsonl", previous_offset=3)
    assert session is not None
    assert session.new_message_count == 0


def test_parse_returns_none_for_empty_file(tmp_path: Path) -> None:
    proj = tmp_path / "p"
    (proj).mkdir(parents=True)
    (proj / "empty.jsonl").write_text("\n", encoding="utf-8")
    adapter = ClaudeCodeAdapter(projects_dir=tmp_path, machine="personal", patterns=compile_patterns())
    assert adapter.parse(proj / "empty.jsonl", previous_offset=0) is None


def test_parse_skips_malformed_lines(tmp_path: Path) -> None:
    proj = tmp_path / "p"
    proj.mkdir(parents=True)
    (proj / "s.jsonl").write_text(
        '{bad}\n{"type":"user","uuid":"u","timestamp":"t","cwd":"/c","gitBranch":"b","sessionId":"s",'
        '"message":{"role":"user","content":"ok"}}\n',
        encoding="utf-8",
    )
    adapter = ClaudeCodeAdapter(projects_dir=tmp_path, machine="personal", patterns=compile_patterns())
    session = adapter.parse(proj / "s.jsonl", previous_offset=0)
    assert session is not None
    assert session.new_message_count == 1


def test_discover_handles_missing_projects_dir(tmp_path: Path) -> None:
    adapter = ClaudeCodeAdapter(projects_dir=tmp_path / "absent", machine="personal", patterns=compile_patterns())
    assert adapter.discover() == []
```

- [ ] **Step 2: Run to verify failure**

Run: `cd agent_journal && uv run pytest tests/test_adapter_claude_code.py -q`
Expected: FAIL — module missing.

- [ ] **Step 3: Implement `adapters/claude_code.py`**

```python
"""Claude Code adapter: parse ``~/.claude/projects/<proj>/<sessionId>.jsonl``.

Sub-agent and workflow transcripts live under nested ``subagents``/``workflows``
directories; they are excluded so only interactive sessions are journaled.
"""

from __future__ import annotations

import json
import re
from pathlib import Path

from agent_journal.adapters.base import NormalizedSession, bounded

_MESSAGE_ROLES = ("user", "assistant")
_EXCLUDED_DIR_PARTS = {"subagents", "workflows"}
_MAX_NARRATIVE_ITEMS = 12
_MAX_NARRATIVE_CHARS = 280


def _content_text(content: object) -> str:
    """Flatten a Claude message ``content`` (string or block list) into text."""
    if isinstance(content, str):
        return content
    if isinstance(content, list):
        parts = [block.get("text", "") for block in content if isinstance(block, dict) and block.get("type") == "text"]
        return " ".join(part for part in parts if part)
    return ""


class ClaudeCodeAdapter:
    """Adapter for Claude Code per-project session transcripts."""

    name = "claude_code"

    def __init__(self, projects_dir: Path, machine: str, patterns: tuple[re.Pattern[str], ...]) -> None:
        """Initialize with the projects directory, machine label, and redaction patterns."""
        self._projects_dir = projects_dir
        self._machine = machine
        self._patterns = patterns

    def discover(self) -> list[Path]:
        """Return interactive session files, excluding workflow/sub-agent journals."""
        if not self._projects_dir.exists():
            return []
        result: list[Path] = []
        for path in sorted(self._projects_dir.glob("*/*.jsonl")):
            if _EXCLUDED_DIR_PARTS & set(path.parts):
                continue
            result.append(path)
        return result

    def parse(self, path: Path, previous_offset: int) -> NormalizedSession | None:
        """Parse new transcript records beyond ``previous_offset``."""
        from agent_journal.redaction import redact

        lines = path.read_text(encoding="utf-8").splitlines()
        records: list[dict[str, object]] = []
        for raw in lines:
            if not raw.strip():
                continue
            try:
                records.append(json.loads(raw))
            except json.JSONDecodeError:
                continue

        if not records:
            return None

        first, last = records[0], records[-1]
        messages: list[str] = []
        new_count = 0
        last_time: str | None = None
        for index, record in enumerate(records):
            if index < previous_offset:
                continue
            message = record.get("message", {})
            if isinstance(message, dict) and message.get("role") in _MESSAGE_ROLES:
                text = _content_text(message.get("content"))
                if text:
                    new_count += 1
                    messages.append(redact(text, self._patterns))
                    last_time = record.get("timestamp", last_time)  # type: ignore[assignment]

        return NormalizedSession(
            tool="claude",
            machine=self._machine,
            session_id=str(first.get("sessionId", path.stem)),
            cwd=last.get("cwd") or first.get("cwd"),  # type: ignore[arg-type]
            branch=last.get("gitBranch") or first.get("gitBranch"),  # type: ignore[arg-type]
            repo_url=None,
            title=None,
            started_at=first.get("timestamp"),  # type: ignore[arg-type]
            last_time=last_time,
            narrative=bounded(messages, max_items=_MAX_NARRATIVE_ITEMS, max_chars=_MAX_NARRATIVE_CHARS),
            new_message_count=new_count,
            new_offset=len(records),
            source_path=str(path),
        )
```

- [ ] **Step 4: Run to verify pass**

Run: `cd agent_journal && uv run pytest tests/test_adapter_claude_code.py -q`
Expected: PASS, 100% coverage.

- [ ] **Step 5: Lint, type-check, commit**

```bash
cd agent_journal && uv run ruff check . && uv run ruff format --check . && uv run ty check .
git add agent_journal/src/agent_journal/adapters/claude_code.py agent_journal/tests/test_adapter_claude_code.py
git commit -m "feat(agent-journal): add Claude Code adapter with workflow-journal exclusion"
```

---

## Task 11: Ingest orchestration (`ingest.py`)

**Files:**
- Create: `agent_journal/src/agent_journal/ingest.py`
- Test: `agent_journal/tests/test_ingest.py`

Reads explicit events + runs enabled adapters, advances watermarks, and persists
`sessions.json` + `runs.json`. Adapters are injectable for testing.

- [ ] **Step 1: Write the failing tests**

```python
"""Unit tests for ingest orchestration."""

from datetime import datetime
from pathlib import Path

from agent_journal.adapters.base import NormalizedSession
from agent_journal.config import ClaudeAdapterConfig, CodexAdapterConfig, Config, VaultConfig
from agent_journal.ingest import build_adapters, ingest, session_from_dict, session_to_dict
from agent_journal.state import read_json


def _cfg(tmp_path: Path) -> Config:
    return Config(
        machine="work-mac", context="work",
        vault=VaultConfig(tmp_path / "vault", "Daily", "%Y/%m/%d-%a", "Workstreams", "Agent Sessions"),
        state_dir=tmp_path / "state", enabled_adapters=("codex", "claude_code"),
        codex=CodexAdapterConfig(str(tmp_path / "codex" / "*.jsonl")),
        claude_code=ClaudeAdapterConfig(tmp_path / "claude"),
        redaction_extra=(), standup_hour=8,
    )


class _FakeAdapter:
    name = "fake"

    def __init__(self, sessions, error_paths=()):
        self._sessions = sessions
        self._error_paths = set(error_paths)

    def discover(self):
        return [Path(f"/fake/{i}.jsonl") for i in range(len(self._sessions) + len(self._error_paths))]

    def parse(self, path, previous_offset):
        if path in self._error_paths:
            raise ValueError("boom")
        index = int(path.stem)
        return self._sessions[index] if index < len(self._sessions) else None


def _session(sid: str) -> NormalizedSession:
    return NormalizedSession("codex", "work", sid, "/r", "main", None, None,
                             "2026-06-15T13:00:00", "2026-06-15T13:05:00", ("did x",), 2, 5, f"/p/{sid}.jsonl")


def test_session_dict_roundtrip() -> None:
    session = _session("s1")
    assert session_from_dict(session_to_dict(session)) == session


def test_build_adapters_respects_config(tmp_path: Path) -> None:
    adapters = build_adapters(_cfg(tmp_path), patterns=())
    assert sorted(a.name for a in adapters) == ["claude_code", "codex"]


def test_ingest_collects_sessions_and_advances_watermarks(tmp_path: Path) -> None:
    cfg = _cfg(tmp_path)
    fake = _FakeAdapter([_session("s0")])
    result = ingest(cfg, now=datetime(2026, 6, 15, 8, 45), adapters=[fake])
    assert result.health[0].discovered == 1
    assert result.health[0].parsed == 1
    persisted = read_json(cfg.state_dir / "sessions.json", [])
    assert persisted[0]["session_id"] == "s0"
    runs = read_json(cfg.state_dir / "runs.json", {})
    assert runs["last_ingest"].startswith("2026-06-15")


def test_ingest_records_parse_errors(tmp_path: Path) -> None:
    cfg = _cfg(tmp_path)
    fake = _FakeAdapter([], error_paths=[Path("/fake/0.jsonl")])
    result = ingest(cfg, now=datetime(2026, 6, 15, 8, 45), adapters=[fake])
    assert result.health[0].errors and "boom" in result.health[0].errors[0]


def test_ingest_counts_explicit_events(tmp_path: Path) -> None:
    cfg = _cfg(tmp_path)
    (cfg.state_dir).mkdir(parents=True)
    (cfg.state_dir / "events.jsonl").write_text(
        '{"time":"t","machine":"work","tool":"codex","cwd":"/c","event":"start","summary":"s"}\n',
        encoding="utf-8",
    )
    result = ingest(cfg, now=datetime(2026, 6, 15, 8, 45), adapters=[])
    assert result.event_count == 1
```

- [ ] **Step 2: Run to verify failure**

Run: `cd agent_journal && uv run pytest tests/test_ingest.py -q`
Expected: FAIL — module missing.

- [ ] **Step 3: Implement `ingest.py`**

```python
"""Normalize explicit events + passive adapter sessions; advance watermarks."""

from __future__ import annotations

import re
from collections.abc import Sequence
from dataclasses import dataclass
from datetime import datetime

from agent_journal.adapters.base import Adapter, NormalizedSession
from agent_journal.adapters.claude_code import ClaudeCodeAdapter
from agent_journal.adapters.codex import CodexAdapter
from agent_journal.config import Config
from agent_journal.events import read_events
from agent_journal.redaction import compile_patterns
from agent_journal.state import Watermark, load_watermarks, read_json, save_watermarks, write_json


@dataclass(frozen=True)
class AdapterHealth:
    """Per-adapter run health."""

    name: str
    discovered: int
    parsed: int
    errors: tuple[str, ...]


@dataclass(frozen=True)
class IngestResult:
    """Result of an ingest run."""

    event_count: int
    sessions: tuple[NormalizedSession, ...]
    health: tuple[AdapterHealth, ...]


def session_to_dict(session: NormalizedSession) -> dict[str, object]:
    """Serialize a normalized session to JSON-ready dict."""
    return {
        "tool": session.tool, "machine": session.machine, "session_id": session.session_id,
        "cwd": session.cwd, "branch": session.branch, "repo_url": session.repo_url,
        "title": session.title, "started_at": session.started_at, "last_time": session.last_time,
        "narrative": list(session.narrative), "new_message_count": session.new_message_count,
        "new_offset": session.new_offset, "source_path": session.source_path,
    }


def session_from_dict(data: dict[str, object]) -> NormalizedSession:
    """Deserialize a normalized session from a dict."""
    return NormalizedSession(
        tool=str(data["tool"]), machine=str(data["machine"]), session_id=str(data["session_id"]),
        cwd=data.get("cwd"), branch=data.get("branch"), repo_url=data.get("repo_url"),  # type: ignore[arg-type]
        title=data.get("title"), started_at=data.get("started_at"), last_time=data.get("last_time"),  # type: ignore[arg-type]
        narrative=tuple(data.get("narrative", [])), new_message_count=int(data["new_message_count"]),  # type: ignore[arg-type]
        new_offset=int(data["new_offset"]), source_path=str(data["source_path"]),  # type: ignore[arg-type]
    )


def build_adapters(cfg: Config, patterns: tuple[re.Pattern[str], ...]) -> list[Adapter]:
    """Construct enabled adapters from config."""
    adapters: list[Adapter] = []
    if cfg.codex is not None:
        adapters.append(CodexAdapter(cfg.codex.sessions_glob, cfg.context, patterns))
    if cfg.claude_code is not None:
        adapters.append(ClaudeCodeAdapter(cfg.claude_code.projects_dir, cfg.context, patterns))
    return adapters


def ingest(cfg: Config, *, now: datetime, adapters: Sequence[Adapter] | None = None) -> IngestResult:
    """Run ingest: read events, parse adapter sessions, persist snapshot + watermarks.

    Args:
        cfg: Loaded configuration.
        now: Injected current time (for the run timestamp).
        adapters: Adapters to run; defaults to those built from config.

    Returns:
        An :class:`IngestResult` summarizing the run.
    """
    patterns = compile_patterns(cfg.redaction_extra)
    active = list(adapters) if adapters is not None else build_adapters(cfg, patterns)

    events = read_events(cfg.state_dir / "events.jsonl")
    watermarks = load_watermarks(cfg.state_dir / "watermarks.json")

    sessions: list[NormalizedSession] = []
    health: list[AdapterHealth] = []
    for adapter in active:
        discovered = adapter.discover()
        errors: list[str] = []
        parsed = 0
        for path in discovered:
            key = f"{adapter.name}:{path}"
            previous = watermarks.get(key)
            try:
                session = adapter.parse(path, previous.offset if previous else 0)
            except (OSError, ValueError) as exc:
                errors.append(f"{path.name}: {exc}")
                continue
            if session is None:
                continue
            parsed += 1
            sessions.append(session)
            watermarks[key] = Watermark(key, session.new_offset, session.session_id, session.last_time)
        health.append(AdapterHealth(adapter.name, len(discovered), parsed, tuple(errors)))

    save_watermarks(cfg.state_dir / "watermarks.json", watermarks)
    write_json(cfg.state_dir / "sessions.json", [session_to_dict(s) for s in sessions])

    runs = read_json(cfg.state_dir / "runs.json", {})
    runs["last_ingest"] = now.isoformat()
    runs["adapter_health"] = [
        {"name": h.name, "discovered": h.discovered, "parsed": h.parsed, "errors": list(h.errors)}
        for h in health
    ]
    write_json(cfg.state_dir / "runs.json", runs)

    return IngestResult(len(events), tuple(sessions), tuple(health))
```

- [ ] **Step 4: Run to verify pass**

Run: `cd agent_journal && uv run pytest tests/test_ingest.py -q`
Expected: PASS, 100% coverage. (Add tests if any branch is uncovered.)

- [ ] **Step 5: Lint, type-check, commit**

```bash
cd agent_journal && uv run ruff check . && uv run ruff format --check . && uv run ty check .
git add agent_journal/src/agent_journal/ingest.py agent_journal/tests/test_ingest.py
git commit -m "feat(agent-journal): add ingest orchestration"
```

---

## Task 12: Digest — write workstream/session notes + daily activity (`digest.py`)

**Files:**
- Create: `agent_journal/src/agent_journal/digest.py`
- Test: `agent_journal/tests/test_digest.py`

Resolves each explicit event and normalized session to a workstream. Matched →
durable writes (workstream note section, session note, daily `Agent Activity`).
Ambiguous/unknown → recorded in `skipped.json`, **no durable write**. Idempotent.

- [ ] **Step 1: Write the failing tests**

```python
"""Unit tests for the digest stage."""

from datetime import datetime
from pathlib import Path

from agent_journal.config import Config, VaultConfig, Workstream
from agent_journal.digest import digest, hhmm
from agent_journal.events import Event, append_event
from agent_journal.ingest import session_to_dict
from agent_journal.adapters.base import NormalizedSession
from agent_journal.obsidian import read_text
from agent_journal.state import read_json, write_json


def _cfg(tmp_path: Path) -> Config:
    return Config(
        machine="work-mac", context="work",
        vault=VaultConfig(tmp_path / "vault", "Daily", "%Y/%m/%d-%a", "Workstreams", "Agent Sessions"),
        state_dir=tmp_path / "state", enabled_adapters=(),
        codex=None, claude_code=None, redaction_extra=(), standup_hour=8,
    )


WS = [Workstream("LA-3141 compute", "LA-3141", "work", ("databricks",), ("terraform",))]


def test_hhmm_parses_iso() -> None:
    assert hhmm("2026-06-15T14:05:00-06:00") == "14:05"
    assert hhmm("garbage") == "??:??"


def test_digest_writes_matched_event_to_workstream_and_daily(tmp_path: Path) -> None:
    cfg = _cfg(tmp_path)
    append_event(cfg.state_dir / "events.jsonl", Event(
        time="2026-06-15T14:00:00-06:00", machine="work", tool="codex", cwd="/repo/terraform",
        event="decision", summary="Use v2 provider", workstream="LA-3141 compute"))
    result = digest(cfg, WS, now=datetime(2026, 6, 15, 14, 0))
    assert "LA-3141 compute" in result.written_workstreams
    ws_note = read_text(cfg.vault.path / "Workstreams" / "LA-3141 compute.md")
    assert "## Decisions" in ws_note and "Use v2 provider" in ws_note
    daily = read_text(cfg.vault.path / "Daily" / "2026" / "06" / "15-Mon.md")
    assert "[[Workstreams/LA-3141 compute]]" in daily


def test_digest_is_idempotent(tmp_path: Path) -> None:
    cfg = _cfg(tmp_path)
    append_event(cfg.state_dir / "events.jsonl", Event(
        time="2026-06-15T14:00:00-06:00", machine="work", tool="codex", cwd="/repo/terraform",
        event="decision", summary="Use v2 provider", workstream="LA-3141 compute"))
    digest(cfg, WS, now=datetime(2026, 6, 15, 14, 0))
    first = read_text(cfg.vault.path / "Daily" / "2026" / "06" / "15-Mon.md")
    digest(cfg, WS, now=datetime(2026, 6, 15, 14, 0))
    assert read_text(cfg.vault.path / "Daily" / "2026" / "06" / "15-Mon.md") == first


def test_digest_skips_ambiguous_and_unknown_sessions(tmp_path: Path) -> None:
    cfg = _cfg(tmp_path)
    session = NormalizedSession("codex", "work", "s1", "/repo/unrelated", "main", None, None,
                                "2026-06-15T13:00:00", "2026-06-15T13:05:00", ("hi",), 1, 5, "/p.jsonl")
    write_json(cfg.state_dir / "sessions.json", [session_to_dict(session)])
    result = digest(cfg, WS, now=datetime(2026, 6, 15, 14, 0))
    assert result.skipped and result.skipped[0].reason == "no-signal"
    skipped = read_json(cfg.state_dir / "skipped.json", [])
    assert skipped[0]["identifier"] == "s1"


def test_digest_writes_session_note_for_matched_session(tmp_path: Path) -> None:
    cfg = _cfg(tmp_path)
    session = NormalizedSession("codex", "work", "s1", "/repo/terraform", "feature/LA-3141", None, None,
                                "2026-06-15T13:00:00", "2026-06-15T13:05:00", ("ran plan",), 1, 5, "/p.jsonl")
    write_json(cfg.state_dir / "sessions.json", [session_to_dict(session)])
    result = digest(cfg, WS, now=datetime(2026, 6, 15, 14, 0))
    assert "LA-3141 compute" in result.written_workstreams
    sessions_dir = cfg.vault.path / "Agent Sessions" / "work"
    notes = list(sessions_dir.glob("*.md"))
    assert notes and "ran plan" in read_text(notes[0])


def test_digest_records_last_run(tmp_path: Path) -> None:
    cfg = _cfg(tmp_path)
    digest(cfg, WS, now=datetime(2026, 6, 15, 14, 0))
    runs = read_json(cfg.state_dir / "runs.json", {})
    assert runs["last_digest"].startswith("2026-06-15")
```

- [ ] **Step 2: Run to verify failure**

Run: `cd agent_journal && uv run pytest tests/test_digest.py -q`
Expected: FAIL — module missing.

- [ ] **Step 3: Implement `digest.py`**

```python
"""Digest: resolve activity to workstreams and write durable Obsidian notes.

Low-confidence (ambiguous/unknown) activity is never written durably — it is
recorded in ``skipped.json`` for manual classification via ``agent-journal status``.
"""

from __future__ import annotations

import re
from collections.abc import Sequence
from dataclasses import dataclass
from datetime import datetime

from agent_journal.config import Config, Workstream
from agent_journal.events import Event, read_events
from agent_journal.ingest import session_from_dict
from agent_journal.obsidian import append_activity_line, daily_note_path, read_text, replace_section, write_text
from agent_journal.resolver import resolve_workstream
from agent_journal.state import read_json, write_json

_SECTION_FOR_EVENT: dict[str, str] = {
    "decision": "## Decisions",
    "change": "## Repo Changes",
    "verification": "## Verification",
    "carry_forward": "## Carry Forward",
    "blocker": "## Carry Forward",
    "start": "## Running Narrative",
    "finish": "## Running Narrative",
}
_TIME_RE = re.compile(r"T(\d{2}:\d{2})")


@dataclass(frozen=True)
class Skipped:
    """An unresolved item awaiting classification."""

    kind: str
    identifier: str
    reason: str
    candidates: tuple[str, ...]
    time: str | None


@dataclass(frozen=True)
class DigestResult:
    """Result of a digest run."""

    written_workstreams: tuple[str, ...]
    activity_lines: int
    skipped: tuple[Skipped, ...]


def hhmm(iso: str) -> str:
    """Extract ``HH:MM`` from an ISO timestamp, or ``??:??`` if unparseable."""
    match = _TIME_RE.search(iso)
    return match.group(1) if match else "??:??"


def _scaffold_workstream(name: str) -> str:
    return (
        f"# {name}\n\n"
        "## Running Narrative\n\n## Decisions\n\n## Repo Changes\n\n"
        "## Verification\n\n## Standup-Relevant Notes\n\n## Carry Forward\n"
    )


def _append_bullet(content: str, header: str, bullet: str) -> str:
    """Append a deduplicated ``- bullet`` under ``header``."""
    from agent_journal.obsidian import read_section

    body = read_section(content, header)
    line = f"- {bullet}"
    if body is not None and line in body:
        return content
    merged = (line if body in (None, "") else f"{body}\n{line}") + "\n"
    return replace_section(content, header, merged)


def _apply_event(content: str, event: Event) -> str:
    header = _SECTION_FOR_EVENT.get(event.event, "## Running Narrative")
    prefix = "BLOCKER: " if event.event == "blocker" else ""
    return _append_bullet(content, header, f"{hhmm(event.time)} {prefix}{event.summary}")


def _session_stamp(started_at: str | None, tool: str, session_id: str) -> str:
    day = (started_at or "")[:10] or "0000-00-00"
    time = hhmm(started_at or "").replace(":", "")
    return f"{day} {time} {tool} {session_id}".strip()


def digest(cfg: Config, workstreams: Sequence[Workstream], *, now: datetime) -> DigestResult:
    """Resolve and write all pending activity. Returns a :class:`DigestResult`."""
    written: list[str] = []
    skipped: list[Skipped] = []
    daily_path = daily_note_path(cfg.vault.path, cfg.vault.daily_dir, cfg.vault.daily_note_path_format, now.date())
    daily = read_text(daily_path)
    activity_count = 0

    def touch_workstream(name: str) -> str:
        path = cfg.vault.path / cfg.vault.workstreams_dir / f"{name}.md"
        content = read_text(path)
        if not content:
            content = _scaffold_workstream(name)
        return content

    # Explicit events.
    for event in read_events(cfg.state_dir / "events.jsonl"):
        resolution = resolve_workstream(
            explicit=event.workstream, cwd=event.cwd, branch=None,
            repo_url=None, prompt=event.summary, workstreams=workstreams,
        )
        if resolution.status != "matched" or resolution.workstream is None:
            skipped.append(Skipped("event", event.time, resolution.reason, resolution.candidates, event.time))
            continue
        name = resolution.workstream
        ws_path = cfg.vault.path / cfg.vault.workstreams_dir / f"{name}.md"
        write_text(ws_path, _apply_event(touch_workstream(name), event))
        new_daily = append_activity_line(daily, hhmm(event.time), name, event.summary, cfg.vault.workstreams_dir)
        if new_daily != daily:
            activity_count += 1
            daily = new_daily
        if name not in written:
            written.append(name)

    # Passive sessions.
    for raw in read_json(cfg.state_dir / "sessions.json", []):
        session = session_from_dict(raw)
        resolution = resolve_workstream(
            explicit=None, cwd=session.cwd, branch=session.branch,
            repo_url=session.repo_url, prompt=session.title, workstreams=workstreams,
        )
        if resolution.status != "matched" or resolution.workstream is None:
            skipped.append(Skipped("session", session.session_id, resolution.reason, resolution.candidates, session.started_at))
            continue
        name = resolution.workstream
        stamp = _session_stamp(session.started_at, session.tool, session.session_id)
        narrative = "\n".join(f"- {line}" for line in session.narrative) or "- (no new narrative)"
        session_note = f"# {stamp}\n\nworkstream: [[{cfg.vault.workstreams_dir}/{name}]]\ncwd: {session.cwd}\n\n## Running Narrative\n{narrative}\n"
        write_text(cfg.vault.path / cfg.vault.sessions_dir / cfg.context / f"{stamp}.md", session_note)

        ws_path = cfg.vault.path / cfg.vault.workstreams_dir / f"{name}.md"
        link = f"session [[{cfg.vault.sessions_dir}/{cfg.context}/{stamp}]]"
        write_text(ws_path, _append_bullet(touch_workstream(name), "## Running Narrative", link))
        summary = session.narrative[0] if session.narrative else f"{session.tool} session"
        new_daily = append_activity_line(daily, hhmm(session.started_at or ""), name, summary, cfg.vault.workstreams_dir)
        if new_daily != daily:
            activity_count += 1
            daily = new_daily
        if name not in written:
            written.append(name)

    if daily.strip():
        write_text(daily_path, daily)
    write_json(cfg.state_dir / "skipped.json", [
        {"kind": s.kind, "identifier": s.identifier, "reason": s.reason,
         "candidates": list(s.candidates), "time": s.time} for s in skipped
    ])
    runs = read_json(cfg.state_dir / "runs.json", {})
    runs["last_digest"] = now.isoformat()
    write_json(cfg.state_dir / "runs.json", runs)

    return DigestResult(tuple(written), activity_count, tuple(skipped))
```

- [ ] **Step 4: Run to verify pass**

Run: `cd agent_journal && uv run pytest tests/test_digest.py -q`
Expected: PASS. Add tests until `--cov-fail-under=100` passes (cover the `start`/`finish` Running-Narrative branch, the empty-narrative branch, and the `_append_bullet` dedupe branch).

- [ ] **Step 5: Lint, type-check, commit**

```bash
cd agent_journal && uv run ruff check . && uv run ruff format --check . && uv run ty check .
git add agent_journal/src/agent_journal/digest.py agent_journal/tests/test_digest.py
git commit -m "feat(agent-journal): add digest stage for workstream/session/daily notes"
```

---

## Task 13: Standup synthesis (`standup.py`)

**Files:**
- Create: `agent_journal/src/agent_journal/standup.py`
- Test: `agent_journal/tests/test_standup.py`

Regenerates the automation-owned `## Standup Draft` in today's daily note from the
most recent prior daily note's `Agent Activity` (Yesterday), today's `Carry Forward`
(Today), and any blockers. Idempotent and replaceable by design.

- [ ] **Step 1: Write the failing tests**

```python
"""Unit tests for standup synthesis."""

from datetime import datetime
from pathlib import Path

from agent_journal.config import Config, VaultConfig
from agent_journal.obsidian import daily_note_path, read_section, read_text, write_text
from agent_journal.standup import render_standup, write_standup


def _cfg(tmp_path: Path) -> Config:
    return Config(
        machine="work-mac", context="work",
        vault=VaultConfig(tmp_path / "vault", "Daily", "%Y/%m/%d-%a", "Workstreams", "Agent Sessions"),
        state_dir=tmp_path / "state", enabled_adapters=(),
        codex=None, claude_code=None, redaction_extra=(), standup_hour=8,
    )


def test_render_standup_has_three_blocks() -> None:
    out = render_standup(yesterday=["did terraform"], today=["verify apply"], blockers=[], now=datetime(2026, 6, 15, 8, 45))
    assert "*Yesterday*" in out and "*Today*" in out and "*Blockers*" in out
    assert "did terraform" in out and "verify apply" in out
    assert "* None" in out  # empty blockers
    assert "_Generated: 2026-06-15 08:45" in out


def test_render_standup_defaults_when_empty() -> None:
    out = render_standup(yesterday=[], today=[], blockers=["k8s access down"], now=datetime(2026, 6, 15, 8, 45))
    assert "Nothing recorded" in out
    assert "k8s access down" in out


def test_write_standup_replaces_only_that_section(tmp_path: Path) -> None:
    cfg = _cfg(tmp_path)
    today = daily_note_path(cfg.vault.path, "Daily", "%Y/%m/%d-%a", datetime(2026, 6, 15).date())
    write_text(today, "## Todo\nkeep\n## Standup Draft\nOLD\n## Notes\nn\n")
    # Prior day with agent activity.
    yest = daily_note_path(cfg.vault.path, "Daily", "%Y/%m/%d-%a", datetime(2026, 6, 14).date())
    write_text(yest, "## Agent Activity\n- 14:00 [[Workstreams/WS]]: shipped feature\n## Carry Forward\n- follow up on tests\n")
    write_standup(cfg, now=datetime(2026, 6, 15, 8, 45))
    out = read_text(today)
    assert "keep" in out and "## Notes\nn" in out
    assert "OLD" not in out
    assert "shipped feature" in out
    assert "follow up on tests" in out  # carry forward -> today


def test_write_standup_creates_section_when_daily_missing(tmp_path: Path) -> None:
    cfg = _cfg(tmp_path)
    write_standup(cfg, now=datetime(2026, 6, 15, 8, 45))
    today = daily_note_path(cfg.vault.path, "Daily", "%Y/%m/%d-%a", datetime(2026, 6, 15).date())
    assert read_section(read_text(today), "## Standup Draft") is not None
```

- [ ] **Step 2: Run to verify failure**

Run: `cd agent_journal && uv run pytest tests/test_standup.py -q`
Expected: FAIL — module missing.

- [ ] **Step 3: Implement `standup.py`**

```python
"""Regenerate the automation-owned ``## Standup Draft`` in the daily note."""

from __future__ import annotations

from collections.abc import Sequence
from datetime import datetime, timedelta

from agent_journal.config import Config
from agent_journal.obsidian import daily_note_path, read_section, read_text, replace_section, write_text

_HEADER = "## Standup Draft"
_MAX_LOOKBACK_DAYS = 7


def _bullets(body: str | None) -> list[str]:
    """Extract bullet texts (without the leading ``- ``) from a section body."""
    if not body:
        return []
    return [line[2:].strip() for line in body.splitlines() if line.strip().startswith("- ")]


def _activity_summaries(body: str | None) -> list[str]:
    """Reduce ``Agent Activity`` bullets to their summary clause (after the colon)."""
    summaries: list[str] = []
    for bullet in _bullets(body):
        summaries.append(bullet.split(": ", 1)[1] if ": " in bullet else bullet)
    return summaries


def render_standup(*, yesterday: Sequence[str], today: Sequence[str], blockers: Sequence[str], now: datetime) -> str:
    """Render the standup draft markdown block.

    Args:
        yesterday: Bullets describing prior-day work.
        today: Bullets describing planned/carry-forward work.
        blockers: Blocker bullets (empty means "None").
        now: Injected current time for the generated-at header.

    Returns:
        The full ``## Standup Draft`` section text.
    """
    def block(items: Sequence[str], empty: str) -> str:
        return "\n".join(f"* {item}" for item in items) if items else f"* {empty}"

    header = f"_Generated: {now.strftime('%Y-%m-%d %H:%M')} from Decisions, Agent Activity, Carry Forward, and linked workstreams._"
    return (
        f"{header}\n\n"
        f"*Yesterday*\n{block(yesterday, 'Nothing recorded.')}\n\n"
        f"*Today*\n{block(today, 'Nothing planned.')}\n\n"
        f"*Blockers*\n{block(blockers, 'None')}\n"
    )


def _previous_daily(cfg: Config, now: datetime) -> str:
    """Return the contents of the most recent prior daily note within the lookback window."""
    for delta in range(1, _MAX_LOOKBACK_DAYS + 1):
        day = (now - timedelta(days=delta)).date()
        path = daily_note_path(cfg.vault.path, cfg.vault.daily_dir, cfg.vault.daily_note_path_format, day)
        content = read_text(path)
        if content:
            return content
    return ""


def write_standup(cfg: Config, *, now: datetime) -> str:
    """Regenerate and write today's ``## Standup Draft``; return the new daily content."""
    today_path = daily_note_path(cfg.vault.path, cfg.vault.daily_dir, cfg.vault.daily_note_path_format, now.date())
    today_content = read_text(today_path)
    prev = _previous_daily(cfg, now)

    yesterday = _activity_summaries(read_section(prev, "## Agent Activity"))
    carry = _bullets(read_section(prev, "## Carry Forward"))
    today_items = carry or _bullets(read_section(today_content, "## Todo"))
    blockers = [b for b in carry if b.upper().startswith("BLOCKER")]

    body = render_standup(yesterday=yesterday, today=today_items, blockers=blockers, now=now)
    updated = replace_section(today_content, _HEADER, body)
    write_text(today_path, updated)
    return updated
```

- [ ] **Step 4: Run to verify pass**

Run: `cd agent_journal && uv run pytest tests/test_standup.py -q`
Expected: PASS. Add tests until 100% (cover the `today_items` fallback-to-Todo branch and the no-prior-daily branch).

- [ ] **Step 5: Lint, type-check, commit**

```bash
cd agent_journal && uv run ruff check . && uv run ruff format --check . && uv run ty check .
git add agent_journal/src/agent_journal/standup.py agent_journal/tests/test_standup.py
git commit -m "feat(agent-journal): add standup synthesis"
```

---

## Task 14: Status report (`status.py`)

**Files:**
- Create: `agent_journal/src/agent_journal/status.py`
- Test: `agent_journal/tests/test_status.py`

- [ ] **Step 1: Write the failing tests**

```python
"""Unit tests for the status report."""

from datetime import datetime
from pathlib import Path

from agent_journal.config import Config, VaultConfig
from agent_journal.state import write_json
from agent_journal.status import status_report


def _cfg(tmp_path: Path) -> Config:
    return Config(
        machine="work-mac", context="work",
        vault=VaultConfig(tmp_path / "vault", "Daily", "%Y/%m/%d-%a", "Workstreams", "Agent Sessions"),
        state_dir=tmp_path / "state", enabled_adapters=(),
        codex=None, claude_code=None, redaction_extra=(), standup_hour=8,
    )


def test_status_reports_skipped_and_health(tmp_path: Path) -> None:
    cfg = _cfg(tmp_path)
    write_json(cfg.state_dir / "skipped.json", [
        {"kind": "session", "identifier": "s1", "reason": "multiple-candidates",
         "candidates": ["A", "B"], "time": "2026-06-15T13:00:00"},
    ])
    write_json(cfg.state_dir / "runs.json", {
        "last_ingest": "2026-06-15T08:00:00", "last_digest": "2026-06-15T08:01:00",
        "adapter_health": [{"name": "codex", "discovered": 3, "parsed": 2, "errors": ["x.jsonl: boom"]}],
    })
    report = status_report(cfg, now=datetime(2026, 6, 15, 8, 45))
    assert "s1" in report and "multiple-candidates" in report and "A, B" in report
    assert "codex" in report and "3" in report and "boom" in report
    assert "last_ingest" in report and "2026-06-15T08:00:00" in report


def test_status_reports_clean_state(tmp_path: Path) -> None:
    cfg = _cfg(tmp_path)
    report = status_report(cfg, now=datetime(2026, 6, 15, 8, 45))
    assert "No unclassified" in report
    assert "never" in report.lower()
```

- [ ] **Step 2: Run to verify failure**

Run: `cd agent_journal && uv run pytest tests/test_status.py -q`
Expected: FAIL — module missing.

- [ ] **Step 3: Implement `status.py`**

```python
"""Human-readable status: unclassified work, adapter health, last run times."""

from __future__ import annotations

from datetime import datetime

from agent_journal.config import Config
from agent_journal.state import read_json


def status_report(cfg: Config, *, now: datetime) -> str:
    """Build a human-readable status report string.

    Args:
        cfg: Loaded configuration.
        now: Injected current time (header only).

    Returns:
        A multi-line report covering skipped items, adapter health, and last runs.
    """
    lines: list[str] = [f"agent-journal status @ {now.strftime('%Y-%m-%d %H:%M')}", ""]

    skipped = read_json(cfg.state_dir / "skipped.json", [])
    lines.append("Unclassified work:")
    if not skipped:
        lines.append("  No unclassified sessions or events.")
    else:
        for item in skipped:
            candidates = ", ".join(item.get("candidates", [])) or "—"
            lines.append(f"  [{item['kind']}] {item['identifier']} ({item['reason']}; candidates: {candidates})")
    lines.append("")

    runs = read_json(cfg.state_dir / "runs.json", {})
    lines.append("Last runs:")
    for key in ("last_ingest", "last_digest", "last_standup"):
        lines.append(f"  {key}: {runs.get(key, 'never')}")
    lines.append("")

    lines.append("Adapter health:")
    health = runs.get("adapter_health", [])
    if not health:
        lines.append("  (no ingest run recorded)")
    else:
        for entry in health:
            lines.append(f"  {entry['name']}: discovered {entry['discovered']}, parsed {entry['parsed']}")
            for error in entry.get("errors", []):
                lines.append(f"    error: {error}")
    return "\n".join(lines)
```

- [ ] **Step 4: Run to verify pass**

Run: `cd agent_journal && uv run pytest tests/test_status.py -q`
Expected: PASS, 100% coverage.

- [ ] **Step 5: Lint, type-check, commit**

```bash
cd agent_journal && uv run ruff check . && uv run ruff format --check . && uv run ty check .
git add agent_journal/src/agent_journal/status.py agent_journal/tests/test_status.py
git commit -m "feat(agent-journal): add status report"
```

---

## Task 15: `agent-note` CLI (`cli_note.py`)

**Files:**
- Create: `agent_journal/src/agent_journal/cli_note.py`
- Test: `agent_journal/tests/test_cli_note.py`

Thin explicit-event capture. Resolves the events path from config (default
`~/.config/agent-journal/config.toml`), falling back to the default state dir.

- [ ] **Step 1: Write the failing tests**

```python
"""Unit tests for the agent-note CLI."""

from pathlib import Path

from agent_journal.cli_note import cli
from agent_journal.events import read_events


def _config(tmp_path: Path) -> Path:
    cfg = tmp_path / "config.toml"
    cfg.write_text(f'machine = "work-mac"\ncontext = "work"\n[vault]\npath = "/v"\n[state]\ndir = "{tmp_path / "state"}"\n', encoding="utf-8")
    return cfg


def test_cli_appends_event(tmp_path: Path, capsys) -> None:
    cfg = _config(tmp_path)
    rc = cli(["--config", str(cfg), "--tool", "codex", "--event", "decision",
              "--summary", "use v2", "--workstream", "LA-3141", "--repo", "terraform",
              "--cwd", "/repo/terraform", "--time", "2026-06-15T14:00:00-06:00"])
    assert rc == 0
    events = read_events(tmp_path / "state" / "events.jsonl")
    assert events[0].event == "decision"
    assert events[0].machine == "work"  # from config context
    assert events[0].repos == ("terraform",)
    assert "recorded" in capsys.readouterr().out.lower()


def test_cli_rejects_bad_event_type(tmp_path: Path) -> None:
    cfg = _config(tmp_path)
    # argparse exits non-zero on invalid choice.
    try:
        cli(["--config", str(cfg), "--tool", "x", "--event", "boom", "--summary", "s"])
    except SystemExit as exc:
        assert exc.code != 0
    else:  # pragma: no cover
        raise AssertionError("expected SystemExit")


def test_cli_falls_back_to_default_state_when_no_config(tmp_path: Path, monkeypatch) -> None:
    monkeypatch.setenv("XDG_STATE_HOME", str(tmp_path / "xdg"))
    rc = cli(["--config", str(tmp_path / "absent.toml"), "--tool", "codex",
              "--event", "start", "--summary", "begin", "--machine", "personal"])
    assert rc == 0
    events = read_events(tmp_path / "xdg" / "agent-journal" / "events.jsonl")
    assert events[0].machine == "personal"


def test_cli_defaults_cwd_and_time(tmp_path: Path) -> None:
    cfg = _config(tmp_path)
    rc = cli(["--config", str(cfg), "--tool", "codex", "--event", "start", "--summary", "begin"])
    assert rc == 0
    events = read_events(tmp_path / "state" / "events.jsonl")
    assert events[0].cwd  # defaulted to os.getcwd()
    assert events[0].time  # defaulted to now
```

- [ ] **Step 2: Run to verify failure**

Run: `cd agent_journal && uv run pytest tests/test_cli_note.py -q`
Expected: FAIL — module missing.

- [ ] **Step 3: Implement `cli_note.py`**

```python
"""``agent-note`` — append a structured explicit event to the agent journal."""

from __future__ import annotations

import argparse
import os
from collections.abc import Sequence
from datetime import datetime
from pathlib import Path

from agent_journal.config import ConfigError, load_config
from agent_journal.events import EVENT_TYPES, Event, append_event
from agent_journal.state import default_state_dir


def build_parser() -> argparse.ArgumentParser:
    """Build the ``agent-note`` argument parser."""
    parser = argparse.ArgumentParser(prog="agent-note", description="Append a structured event to the agent journal.")
    parser.add_argument("--config", type=Path, default=Path.home() / ".config" / "agent-journal" / "config.toml")
    parser.add_argument("--tool", required=True, help="Originating agent tool (e.g. codex, claude).")
    parser.add_argument("--event", required=True, choices=EVENT_TYPES, help="Event type.")
    parser.add_argument("--summary", required=True, help="Short description (source material, not Slack prose).")
    parser.add_argument("--workstream", default=None, help="Explicit workstream name.")
    parser.add_argument("--machine", default=None, help="Machine context label; defaults to config context.")
    parser.add_argument("--cwd", default=None, help="Working directory; defaults to current.")
    parser.add_argument("--time", default=None, help="ISO timestamp; defaults to now.")
    parser.add_argument("--repo", action="append", default=[], help="Repository touched (repeatable).")
    parser.add_argument("--link", action="append", default=[], help="Obsidian wiki-link (repeatable).")
    return parser


def _resolve_paths(config_path: Path, machine_override: str | None) -> tuple[Path, str]:
    """Return ``(events_path, machine_label)`` from config, with safe fallbacks."""
    try:
        cfg = load_config(config_path)
        return cfg.state_dir / "events.jsonl", machine_override or cfg.context
    except ConfigError:
        return default_state_dir() / "events.jsonl", machine_override or "unknown"


def cli(argv: Sequence[str] | None = None) -> int:
    """Run the ``agent-note`` CLI. Returns process exit code."""
    args = build_parser().parse_args(argv)
    events_path, machine = _resolve_paths(args.config, args.machine)
    event = Event(
        time=args.time or datetime.now().astimezone().isoformat(),
        machine=machine,
        tool=args.tool,
        cwd=args.cwd or os.getcwd(),
        event=args.event,
        summary=args.summary,
        workstream=args.workstream,
        links=tuple(args.link),
        repos=tuple(args.repo),
    )
    append_event(events_path, event)
    print(f"recorded {event.event} event -> {events_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(cli())
```

> **Coverage note:** `datetime.now()` and `os.getcwd()` defaults are exercised by
> `test_cli_defaults_cwd_and_time`. The `if __name__` line is excluded by config.

- [ ] **Step 4: Run to verify pass**

Run: `cd agent_journal && uv run pytest tests/test_cli_note.py -q`
Expected: PASS, 100% coverage.

- [ ] **Step 5: Lint, type-check, commit**

```bash
cd agent_journal && uv run ruff check . && uv run ruff format --check . && uv run ty check .
git add agent_journal/src/agent_journal/cli_note.py agent_journal/tests/test_cli_note.py
git commit -m "feat(agent-journal): add agent-note CLI"
```

---

## Task 16: `agent-journal` CLI dispatch (`main.py`)

**Files:**
- Create: `agent_journal/src/agent_journal/main.py`
- Test: `agent_journal/tests/test_main.py`

- [ ] **Step 1: Write the failing tests**

```python
"""Unit tests for the agent-journal CLI dispatch."""

from pathlib import Path

import pytest

from agent_journal.main import main


def _setup(tmp_path: Path) -> tuple[Path, Path]:
    cfg = tmp_path / "config.toml"
    cfg.write_text(
        f'machine = "work-mac"\ncontext = "work"\nstandup_hour = 8\n'
        f'[vault]\npath = "{tmp_path / "vault"}"\n[state]\ndir = "{tmp_path / "state"}"\n'
        f'[adapters]\nenabled = []\n',
        encoding="utf-8",
    )
    ws = tmp_path / "workstreams.toml"
    ws.write_text('[[workstream]]\nname = "WS"\naliases = ["ws"]\nrepos = ["vault"]\n', encoding="utf-8")
    return cfg, ws


@pytest.mark.parametrize("subcommand", ["ingest", "digest", "standup", "status"])
def test_each_subcommand_runs(tmp_path: Path, subcommand: str, capsys) -> None:
    cfg, ws = _setup(tmp_path)
    rc = main([subcommand, "--config", str(cfg), "--workstreams", str(ws)])
    assert rc == 0
    assert capsys.readouterr().out  # each prints a summary


def test_missing_config_returns_error(tmp_path: Path, capsys) -> None:
    rc = main(["ingest", "--config", str(tmp_path / "absent.toml")])
    assert rc == 1
    assert "error" in capsys.readouterr().err.lower()


def test_no_subcommand_prints_help(capsys) -> None:
    rc = main([])
    assert rc == 2
```

- [ ] **Step 2: Run to verify failure**

Run: `cd agent_journal && uv run pytest tests/test_main.py -q`
Expected: FAIL — module missing.

- [ ] **Step 3: Implement `main.py`**

```python
"""``agent-journal`` — subcommand dispatch for ingest / digest / standup / status."""

from __future__ import annotations

import argparse
from collections.abc import Sequence
from datetime import datetime
from pathlib import Path

from agent_journal.config import ConfigError, load_config, load_workstreams
from agent_journal.digest import digest
from agent_journal.ingest import ingest
from agent_journal.standup import write_standup
from agent_journal.state import read_json, write_json
from agent_journal.status import status_report

_DEFAULT_CONFIG = Path.home() / ".config" / "agent-journal" / "config.toml"
_DEFAULT_WORKSTREAMS = Path.home() / ".config" / "agent-journal" / "workstreams.toml"


def build_parser() -> argparse.ArgumentParser:
    """Build the ``agent-journal`` parser with one subparser per command."""
    parser = argparse.ArgumentParser(prog="agent-journal", description="Record agent work into Obsidian.")
    sub = parser.add_subparsers(dest="command")
    for name, help_text in (
        ("ingest", "Normalize explicit events + adapter sessions."),
        ("digest", "Write workstream/session notes and daily Agent Activity."),
        ("standup", "Regenerate the automation-owned Standup Draft."),
        ("status", "Report unclassified work, adapter health, and last runs."),
    ):
        child = sub.add_parser(name, help=help_text)
        child.add_argument("--config", type=Path, default=_DEFAULT_CONFIG)
        child.add_argument("--workstreams", type=Path, default=_DEFAULT_WORKSTREAMS)
    return parser


def main(argv: Sequence[str] | None = None) -> int:
    """Run the ``agent-journal`` CLI. Returns process exit code."""
    parser = build_parser()
    args = parser.parse_args(argv)
    if args.command is None:
        parser.print_help()
        return 2

    try:
        cfg = load_config(args.config)
    except ConfigError as exc:
        print(f"Error: {exc}", file=__import__("sys").stderr)
        return 1

    now = datetime.now().astimezone()
    workstreams = load_workstreams(args.workstreams)

    if args.command == "ingest":
        result = ingest(cfg, now=now)
        print(f"ingest: {result.event_count} events, {len(result.sessions)} sessions")
    elif args.command == "digest":
        result = digest(cfg, workstreams, now=now)
        print(f"digest: wrote {len(result.written_workstreams)} workstreams, "
              f"{result.activity_lines} activity lines, {len(result.skipped)} skipped")
    elif args.command == "standup":
        write_standup(cfg, now=now)
        runs = read_json(cfg.state_dir / "runs.json", {})
        runs["last_standup"] = now.isoformat()
        write_json(cfg.state_dir / "runs.json", runs)
        print("standup: regenerated ## Standup Draft")
    else:  # status
        print(status_report(cfg, now=now))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
```

> Use `import sys` at module top instead of `__import__("sys")` if ruff prefers;
> the inline form avoids an unused-import lint when only the error path uses it.
> Either is fine — pick whichever passes `ruff check` cleanly.

- [ ] **Step 4: Run to verify pass**

Run: `cd agent_journal && uv run pytest tests/test_main.py -q`
Expected: PASS, 100% coverage. Then run the full suite:
```bash
cd agent_journal && uv run pytest -q
```
Expected: all pass, **coverage 100%**.

- [ ] **Step 5: Lint, type-check, CLI smoke, commit**

```bash
cd agent_journal && uv run ruff check . && uv run ruff format --check . && uv run ty check .
cd agent_journal && uv run agent-journal --help >/dev/null && uv run agent-note --help >/dev/null
git add agent_journal/src/agent_journal/main.py agent_journal/tests/test_main.py
git commit -m "feat(agent-journal): add agent-journal CLI dispatch"
```

---

## Task 17: Add the `agent_journal` capability + `.chezmoiignore` gates

**Files:**
- Modify: `.chezmoidata/machines.toml` (capability doc + key on every row)
- Modify: `.chezmoiignore` (capability gate block + darwin gate for the plist)

> The `machine-capability-audit` pre-commit hook fails if the capability is defined
> but not gated, so this task lands the gates too.

- [ ] **Step 1: Add the capability doc comment in `machines.toml`**

In the capability comment block (after the `infra` paragraph, before the VPN note), add:
```text
#   agent_journal — deploy the agent journal tool config (~/.config/agent-journal/),
#            the agent-note / agent-journal-run bin wrappers, the post-apply
#            sync hook, and the launchd LaunchAgent that records agent work into
#            the Obsidian vault. On for personal + work; off on lab (no agent-heavy
#            work there). Gated in .chezmoiignore and in
#            .chezmoiscripts/run_after_sync-agent-journal.sh.tmpl (self-gates).
```

- [ ] **Step 2: Add `agent_journal` to every machine row**

`[machines.personal-mac]` — add `agent_journal = true` (after `infra = false`).
`[machines.work-mac]` — add `agent_journal = true` (after `infra = true`).
`[machines.lab-mac]` — add `agent_journal = false` (after `infra = false`).

- [ ] **Step 3: Add the capability gate block to `.chezmoiignore`**

At the end of the file (after the `skills` capability block), append:
```text
# Skip the agent-journal config + bin wrappers + LaunchAgent on machines that
# don't run the agent journal. The post-apply sync hook self-gates on the same
# capability, so it becomes a no-op without these source files.
{{ if not (index .machines .machine).agent_journal }}
.config/agent-journal
.local/bin/agent-note
.local/bin/agent-journal-run
Library/LaunchAgents/com.user.agent-journal.plist
{{ end }}

# The agent-journal LaunchAgent is macOS-only (launchd). Skip its plist on any
# non-darwin host even where the capability is on.
{{ if ne .chezmoi.os "darwin" }}
Library/LaunchAgents/com.user.agent-journal.plist
{{ end }}
```

- [ ] **Step 4: Verify the capability audit and rendering**

```bash
pre-commit run machine-capability-audit --files .chezmoidata/machines.toml .chezmoiignore
chezmoi execute-template < .chezmoiignore >/dev/null && echo "renders OK"
```
Expected: audit passes; template renders without error.

- [ ] **Step 5: Commit** (defer to Task 20's commit, or commit now)

```bash
git add .chezmoidata/machines.toml .chezmoiignore
git commit -m "feat(agent-journal): add agent_journal capability and ignore gates"
```

---

## Task 18: Config templates

**Files:**
- Create: `dot_config/agent-journal/config.toml.tmpl`
- Create: `dot_config/agent-journal/workstreams.toml.tmpl`

- [ ] **Step 1: Create `dot_config/agent-journal/config.toml.tmpl`**

```text
# agent-journal configuration. Rendered by chezmoi; gated on the
# `agent_journal` machine capability. The tool lives in agent_journal/.
machine = {{ .machine | quote }}
context = "{{ if hasPrefix "work" .machine }}work{{ else }}personal{{ end }}"
standup_hour = 8

[vault]
path = "{{ .chezmoi.homeDir }}/projects/obsidian"
daily_dir = "Daily"
# Python strftime — equivalent to Obsidian's moment format YYYY/MM/DD-ddd.
daily_note_path_format = "%Y/%m/%d-%a"
workstreams_dir = "Workstreams"
sessions_dir = "Agent Sessions"

[state]
dir = "{{ .chezmoi.homeDir }}/.local/state/agent-journal"

[adapters]
# OpenCode/Copilot are intentionally out of v1 (insufficient/weak local state).
enabled = ["codex", "claude_code"]

[adapters.codex]
sessions_glob = "{{ .chezmoi.homeDir }}/.codex/archived_sessions/*.jsonl"

[adapters.claude_code]
projects_dir = "{{ .chezmoi.homeDir }}/.claude/projects"

[redaction]
extra_patterns = []
```

- [ ] **Step 2: Create `dot_config/agent-journal/workstreams.toml.tmpl`**

```text
# Known workstreams for resolution. Add a [[workstream]] block per ticket or
# project. `agent-journal status` lists unclassified sessions to add here.
{{- if hasPrefix "work" .machine }}
# Work tickets are dynamic — add them as you classify work. Example:
# [[workstream]]
# name = "LA-3141 databricks compute plane"
# jira = "LA-3141"
# context = "work"
# aliases = ["databricks compute", "compute plane"]
# repos = ["terraform", "k8s-config", "service-repo"]
{{- else }}
[[workstream]]
name = "dotfiles"
context = "personal"
aliases = ["chezmoi", "dotfiles"]
repos = ["dotfiles", "chezmoi"]

[[workstream]]
name = "stevectl"
context = "personal"
aliases = ["stevectl"]
repos = ["stevectl"]

[[workstream]]
name = "nuv"
context = "personal"
aliases = ["nuv"]
repos = ["nuv"]

[[workstream]]
name = "python_playa"
context = "personal"
aliases = ["python playa", "playa"]
repos = ["python_playa"]
{{- end }}
```

- [ ] **Step 3: Verify rendering for each machine**

```bash
chezmoi execute-template --init --promptString machine=work-mac < dot_config/agent-journal/config.toml.tmpl
chezmoi execute-template --init --promptString machine=personal-mac < dot_config/agent-journal/workstreams.toml.tmpl
```
Expected: valid TOML (work renders empty workstreams w/ comment; personal renders the four projects).

- [ ] **Step 4: Commit**

```bash
git add dot_config/agent-journal/config.toml.tmpl dot_config/agent-journal/workstreams.toml.tmpl
git commit -m "feat(agent-journal): add config and workstreams templates"
```

---

## Task 19: Post-apply hook (`run_after_sync-agent-journal.sh.tmpl`)

**Files:**
- Create: `.chezmoiscripts/run_after_sync-agent-journal.sh.tmpl`

Self-gates on the capability, warms the uv venv, ensures state/log dirs, and
(re)loads the LaunchAgent on darwin.

- [ ] **Step 1: Create the hook**

```bash
#!/usr/bin/env bash
set -euo pipefail

# Post-apply hook for the agent journal. Self-gates on the `agent_journal`
# machine capability — collapses to a no-op where the capability is off.
# (.chezmoiignore skips the dotfiles, but chezmoi scripts still execute, so the
# runtime gate here is required.) Warms the uv venv, ensures state/log dirs,
# and (re)loads the LaunchAgent on darwin.

{{ if not (index .machines .machine).agent_journal -}}
echo "agent-journal sync skipped (machine capability agent_journal=false)."
exit 0
{{- else -}}

PROJECT="${HOME}/.local/share/chezmoi/agent_journal"
STRICT_MODE="${AGENT_JOURNAL_STRICT:-0}"
LABEL="com.user.agent-journal"
PLIST_PATH="${HOME}/Library/LaunchAgents/${LABEL}.plist"

fail_or_warn() {
  local message="$1"
  if [[ "${STRICT_MODE}" == "1" ]]; then
    echo "Error: ${message}" >&2
    exit 1
  fi
  echo "Warning: ${message}" >&2
}

if ! command -v uv >/dev/null 2>&1; then
  fail_or_warn "uv is not installed; skipping agent-journal sync."
  exit 0
fi

if [[ ! -f "${PROJECT}/pyproject.toml" ]]; then
  echo "Warning: agent-journal project not found at ${PROJECT}." >&2
  exit 0
fi

# Warm the venv so launchd runs are fast and apply-time surfaces errors.
if ! uv sync --project "${PROJECT}" >/dev/null 2>&1; then
  fail_or_warn "agent-journal uv sync failed."
fi

mkdir -p "${HOME}/.local/state/agent-journal"
mkdir -p "${HOME}/Library/Logs"

{{ if eq .chezmoi.os "darwin" -}}
if [[ -f "${PLIST_PATH}" ]]; then
  DOMAIN="gui/$(id -u)"
  launchctl bootout "${DOMAIN}/${LABEL}" 2>/dev/null || true
  launchctl bootstrap "${DOMAIN}" "${PLIST_PATH}" || fail_or_warn "launchctl bootstrap failed for ${LABEL}."
  echo "agent-journal: LaunchAgent loaded (${DOMAIN}/${LABEL})."
else
  echo "agent-journal: plist not yet deployed at ${PLIST_PATH}; skipping load." >&2
fi
{{- end }}

{{- end }}
```

- [ ] **Step 2: Verify rendering both ways**

```bash
chezmoi execute-template --init --promptString machine=lab-mac < .chezmoiscripts/run_after_sync-agent-journal.sh.tmpl
chezmoi execute-template --init --promptString machine=work-mac < .chezmoiscripts/run_after_sync-agent-journal.sh.tmpl
```
Expected: lab renders the `exit 0` no-op; work renders the full body with the darwin load block.

- [ ] **Step 3: Commit**

```bash
git add .chezmoiscripts/run_after_sync-agent-journal.sh.tmpl
git commit -m "feat(agent-journal): add self-gating post-apply hook"
```

---

## Task 20: LaunchAgent plist + bin wrappers

**Files:**
- Create: `Library/LaunchAgents/com.user.agent-journal.plist.tmpl`
- Create: `dot_local/bin/executable_agent-note`
- Create: `dot_local/bin/executable_agent-journal-run`

- [ ] **Step 1: Create the plist** (`Library/LaunchAgents/com.user.agent-journal.plist.tmpl`)

```text
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.user.agent-journal</string>

    <key>ProgramArguments</key>
    <array>
        <string>/bin/zsh</string>
        <string>-lc</string>
        <string>exec "{{ .chezmoi.homeDir }}/.local/bin/agent-journal-run"</string>
    </array>

    <!-- Hourly during waking hours. All three subcommands are idempotent, so
         the Standup Draft (automation-owned) is simply kept fresh each run.
         Edit this array to change the cadence (intervals are configuration). -->
    <key>StartCalendarInterval</key>
    <array>
        {{- range $h := (list 8 9 10 11 12 13 14 15 16 17 18 19 20) }}
        <dict><key>Hour</key><integer>{{ $h }}</integer><key>Minute</key><integer>0</integer></dict>
        {{- end }}
    </array>

    <key>RunAtLoad</key>
    <false/>

    <key>ProcessType</key>
    <string>Background</string>

    <key>StandardOutPath</key>
    <string>{{ .chezmoi.homeDir }}/Library/Logs/agent-journal.out.log</string>

    <key>StandardErrorPath</key>
    <string>{{ .chezmoi.homeDir }}/Library/Logs/agent-journal.err.log</string>
</dict>
</plist>
```

- [ ] **Step 2: Create `dot_local/bin/executable_agent-note`**

```bash
#!/usr/bin/env bash
# Thin wrapper so agents can call `agent-note` from any shell/cwd without
# `uv run --project`. Appends a structured event to the agent journal.
set -euo pipefail
PROJECT="${HOME}/.local/share/chezmoi/agent_journal"
exec uv run --project "${PROJECT}" agent-note "$@"
```

- [ ] **Step 3: Create `dot_local/bin/executable_agent-journal-run`**

```bash
#!/usr/bin/env bash
# LaunchAgent entry point: ingest passive + explicit material, regenerate
# workstream/session notes, and refresh the automation-owned Standup Draft.
# Every subcommand is idempotent, so hourly runs are safe.
set -uo pipefail
PROJECT="${HOME}/.local/share/chezmoi/agent_journal"

if ! command -v uv >/dev/null 2>&1; then
  echo "agent-journal-run: uv not found on PATH" >&2
  exit 0
fi
if [[ ! -f "${PROJECT}/pyproject.toml" ]]; then
  echo "agent-journal-run: project missing at ${PROJECT}" >&2
  exit 0
fi

uv run --project "${PROJECT}" agent-journal ingest || true
uv run --project "${PROJECT}" agent-journal digest || true
uv run --project "${PROJECT}" agent-journal standup || true
```

- [ ] **Step 4: Verify plist rendering**

```bash
chezmoi execute-template --init --promptString machine=work-mac < Library/LaunchAgents/com.user.agent-journal.plist.tmpl | head -30
```
Expected: valid XML with 13 `StartCalendarInterval` entries (hours 8–20).

- [ ] **Step 5: Commit**

```bash
git add Library/LaunchAgents/com.user.agent-journal.plist.tmpl \
        dot_local/bin/executable_agent-note dot_local/bin/executable_agent-journal-run
git commit -m "feat(agent-journal): add LaunchAgent plist and bin wrappers"
```

---

## Task 21: CI workflow (`agent-journal-ci.yml`)

**Files:**
- Create: `.github/workflows/agent-journal-ci.yml`

Mirrors `token-auditor-ci.yml` exactly, with paths/names swapped.

- [ ] **Step 1: Create the workflow**

```yaml
name: Agent Journal CI

on:
  push:
    paths:
      - "agent_journal/**"
      - ".github/workflows/agent-journal-ci.yml"
  pull_request:
    paths:
      - "agent_journal/**"
      - ".github/workflows/agent-journal-ci.yml"
  workflow_dispatch:

jobs:
  quality:
    runs-on: ubuntu-latest
    defaults:
      run:
        working-directory: agent_journal

    steps:
      - name: Checkout
        uses: actions/checkout@v4

      - name: Set up Python
        id: setup-python
        uses: actions/setup-python@v5
        with:
          python-version-file: agent_journal/.python-version

      - name: Set up uv
        uses: astral-sh/setup-uv@v5

      - name: Restore uv cache
        uses: actions/cache@v4
        with:
          path: |
            ~/.cache/uv
            agent_journal/.venv
          key: agent-journal-${{ runner.os }}-${{ steps.setup-python.outputs.python-version }}-${{ hashFiles('agent_journal/uv.lock') }}
          restore-keys: |
            agent-journal-${{ runner.os }}-${{ steps.setup-python.outputs.python-version }}-
            agent-journal-${{ runner.os }}-

      - name: Sync dependencies
        run: uv sync --locked --group dev

      - name: Lint
        run: |
          uv run ruff check .
          uv run ruff format --check .

      - name: Type check
        run: uv run ty check .

      - name: CLI smoke test
        run: |
          uv run agent-journal --help > /dev/null
          uv run agent-note --help > /dev/null

      - name: Test
        run: uv run pytest -v
```

- [ ] **Step 2: Validate YAML + commit**

```bash
pre-commit run check-yaml --files .github/workflows/agent-journal-ci.yml
git add .github/workflows/agent-journal-ci.yml
git commit -m "ci(agent-journal): add lint/type/test workflow"
```

---

## Task 22: Documentation

**Files:**
- Create: `docs/ai-tools/agent-journal.md`
- Modify: `CLAUDE.md` (Commands subsection + capability bullet)

- [ ] **Step 1: Create `docs/ai-tools/agent-journal.md`**

````markdown
# Agent Journal

Records agent work as workstream-centered Obsidian notes and regenerates a daily
standup draft. Deployed via chezmoi behind the `agent_journal` machine capability
(personal + work; off on lab). Design: `docs/superpowers/specs/2026-06-15-agent-journal-design.md`.

## Components

- `agent_journal/` — strict uv project (hatchling, `ty`, 100% coverage).
- `agent-note` — agents append structured JSONL events (the explicit contract).
- `agent-journal ingest|digest|standup|status` — normalize, write notes, refresh
  `## Standup Draft`, and report unclassified work.
- LaunchAgent `com.user.agent-journal` runs the hourly cycle (waking hours).

## How agents call `agent-note`

Emit explicit events at material boundaries (start, decision, change,
verification, blocker, carry_forward, finish):

```bash
agent-note --tool codex --event decision \
  --summary "Use the v2 Databricks provider" \
  --workstream "LA-3141 databricks compute plane" \
  --repo terraform --repo k8s-config
```

`--workstream` is authoritative. Without it, the digest resolves a workstream
from Jira keys, repo names (cwd / git remote), and aliases in `workstreams.toml`.

## Manual CLI

```bash
uv run --project ~/.local/share/chezmoi/agent_journal agent-journal ingest
uv run --project ~/.local/share/chezmoi/agent_journal agent-journal digest
uv run --project ~/.local/share/chezmoi/agent_journal agent-journal standup
uv run --project ~/.local/share/chezmoi/agent_journal agent-journal status
```

## State, watermarks, logs

- State dir: `~/.local/state/agent-journal/` — `events.jsonl`, `watermarks.json`,
  `sessions.json`, `runs.json`, `skipped.json`.
- Logs: `~/Library/Logs/agent-journal.{out,err}.log`.

## Classifying skipped sessions

`agent-journal status` lists ambiguous/unknown work. To classify, add a
`[[workstream]]` block to `~/.config/agent-journal/workstreams.toml` (source:
`dot_config/agent-journal/workstreams.toml.tmpl`) with a matching `jira`,
`repos`, or `aliases`, then re-run `digest`. Unknown work is never auto-filed.

## Privacy

Secrets are redacted before any summarization; raw transcripts are never written
into Obsidian; work-machine processing stays local. No Slack auto-posting.
````

- [ ] **Step 2: Add a Commands subsection to `CLAUDE.md`**

After the Token Auditor commands block, add:
````markdown
### Agent Journal (`agent_journal/`)

```bash
cd agent_journal
uv sync --locked --group dev
uv run ruff check . && uv run ruff format --check .
uv run ty check .
uv run pytest -v          # 100% coverage required
uv run agent-journal --help   # subcommands: ingest, digest, standup, status
uv run agent-note --help      # explicit event capture for agents
```
````

- [ ] **Step 3: Add the capability bullet to `CLAUDE.md`**

In the "Current capabilities" list (after the `infra` bullet), add:
```markdown
- **`agent_journal`** — deploy the agent journal tool config
  (`~/.config/agent-journal/`), the `agent-note` / `agent-journal-run` bin
  wrappers, the post-apply sync hook, and the launchd LaunchAgent that records
  agent work into the Obsidian vault. On for personal + work; off on lab. Gated
  in `.chezmoiignore` and self-gated in
  `.chezmoiscripts/run_after_sync-agent-journal.sh.tmpl`.
```

Also add `agent_journal/` to the "Key Directories" list:
```markdown
- `agent_journal/` — Agent journal / standup automation (uv project, Python 3.14+, 100% coverage gate)
```

- [ ] **Step 4: Commit**

```bash
git add docs/ai-tools/agent-journal.md CLAUDE.md
git commit -m "docs(agent-journal): document capability, CLI, and agent contract"
```

---

## Self-Review (run before declaring done)

**Spec coverage:** Daily-note model (Task 6, 12, 13) · Workstream notes (Task 12) ·
Session notes (Task 12) · Explicit event schema (Task 2) · `agent-note` (Task 15) ·
`ingest`/`digest`/`standup`/`status` (Tasks 11–14, 16) · Codex + Claude adapters
(Tasks 9–10) · workflow-journal exclusion (Task 10) · watermarks (Task 5, 9–11) ·
workstream resolution incl. ambiguous/unknown → status, no durable write (Tasks 7,
12, 14) · secret redaction (Task 3) · capability gating (Task 17) · config templates
(Task 18) · post-apply hook self-gate (Task 19) · launchd (Task 20) · CI (Task 21) ·
docs (Task 22). **Deviations from spec (flag to user):** OpenCode deferred (data too
weak); plist label `com.user.agent-journal` (repo convention) not `org.stevec.*`;
summarization is deterministic (no-runtime-deps rule), model summarization is future
enrichment.

**Final gate:**
```bash
cd agent_journal && uv sync --locked --group dev && uv run ruff check . && \
  uv run ruff format --check . && uv run ty check . && uv run pytest -v
pre-commit run --all-files
```
Expected: all green, coverage 100%.
