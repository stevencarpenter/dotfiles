"""Tests for the fail-closed dashboard manifest generator."""

from __future__ import annotations

import importlib.util
import json
from pathlib import Path
from typing import Any

import pytest

MODULE_PATH = Path(__file__).resolve().parents[1] / "generate.py"
MODULE_SPEC = importlib.util.spec_from_file_location(
    "dashboard_tabs_generate", MODULE_PATH
)
assert MODULE_SPEC is not None and MODULE_SPEC.loader is not None
generate = importlib.util.module_from_spec(MODULE_SPEC)
MODULE_SPEC.loader.exec_module(generate)


def write_json(path: Path, value: Any) -> None:
    """Write one JSON fixture."""
    path.write_text(json.dumps(value), encoding="utf-8")


def source_spec(
    directory: Path, *, group_id: str = "test", title: str = "Test"
) -> dict[str, Any]:
    """Build one source manifest fixture."""
    return {
        "id": group_id,
        "title": title,
        "color": "purple",
        "base_url": "http://localhost:3030",
        "dashboard_dir": str(directory),
        "first": ["overview"],
    }


def source_file(tmp_path: Path, groups: list[dict[str, Any]]) -> Path:
    """Write a complete sources.json fixture."""
    path = tmp_path / "sources.json"
    write_json(path, {"groups": groups})
    return path


def test_read_dashboard_accepts_bare_and_export_wrapped_files(tmp_path: Path) -> None:
    """Both Grafana dashboard export shapes produce the same identity."""
    bare = tmp_path / "bare.json"
    wrapped = tmp_path / "wrapped.json"
    write_json(bare, {"uid": "bare", "title": "Bare"})
    write_json(wrapped, {"dashboard": {"uid": "wrapped", "title": "Wrapped"}})
    non_dashboard = tmp_path / "non-dashboard.json"
    write_json(non_dashboard, {"name": "datasource"})

    assert generate.read_dashboard(bare) == ("bare", "Bare")
    assert generate.read_dashboard(wrapped) == ("wrapped", "Wrapped")
    assert generate.read_dashboard(non_dashboard) is None
    with pytest.raises(generate.DashboardSourceError, match="missing.json"):
        generate.read_dashboard(tmp_path / "missing.json")


def test_build_group_pins_then_sorts_remaining_titles(tmp_path: Path) -> None:
    """Pinned UIDs retain manifest order while remaining tabs sort by title."""
    directory = tmp_path / "dashboards"
    directory.mkdir()
    write_json(directory / "z.json", {"uid": "z", "title": "Zulu"})
    write_json(directory / "a.json", {"uid": "a", "title": "Alpha"})
    write_json(directory / "overview.json", {"uid": "overview", "title": "Overview"})

    group = generate.build_group(source_spec(directory))

    assert [tab["title"] for tab in group["tabs"]] == ["Overview", "Alpha", "Zulu"]
    with pytest.raises(generate.DashboardSourceError, match="not found"):
        generate.build_group({**source_spec(directory), "first": ["missing"]})


def test_duplicate_uid_is_fatal_and_names_both_files(tmp_path: Path) -> None:
    """Duplicate UIDs cannot produce duplicate browser tabs."""
    directory = tmp_path / "dashboards"
    directory.mkdir()
    first = directory / "first.json"
    second = directory / "second.json"
    write_json(first, {"uid": "same", "title": "First"})
    write_json(second, {"uid": "same", "title": "Second"})

    with pytest.raises(generate.DashboardSourceError, match="first.json.*second.json"):
        generate.build_group(source_spec(directory))


@pytest.mark.parametrize(
    "bad_contents",
    ["{truncated", {"uid": "valid", "title": 7}],
)
def test_bad_dashboard_input_refuses_to_replace_output(
    tmp_path: Path, bad_contents: str | dict[str, Any]
) -> None:
    """Malformed or invalid dashboard files leave the previous output intact."""
    directory = tmp_path / "dashboards"
    directory.mkdir()
    write_json(directory / "valid.json", {"uid": "valid", "title": "Valid"})
    bad = directory / "bad.json"
    if isinstance(bad_contents, str):
        bad.write_text(bad_contents, encoding="utf-8")
    else:
        write_json(bad, bad_contents)

    output = tmp_path / "extension" / "dashboards.json"
    output.parent.mkdir()
    output.write_text("previous\n", encoding="utf-8")
    sources = source_file(tmp_path, [source_spec(directory)])

    assert generate.main(sources, output) == 1
    assert output.read_text(encoding="utf-8") == "previous\n"


def test_missing_source_refuses_to_replace_output(tmp_path: Path) -> None:
    """A missing configured repository cannot silently drop a dashboard group."""
    present = tmp_path / "present"
    present.mkdir()
    write_json(present / "one.json", {"uid": "one", "title": "One"})
    missing = tmp_path / "missing"
    output = tmp_path / "extension" / "dashboards.json"
    output.parent.mkdir()
    output.write_text("previous\n", encoding="utf-8")
    sources = source_file(
        tmp_path, [source_spec(present), source_spec(missing, group_id="missing")]
    )

    assert generate.main(sources, output) == 1
    assert output.read_text(encoding="utf-8") == "previous\n"


def test_main_writes_group_ids_and_deterministic_output(tmp_path: Path) -> None:
    """A valid fixture generates the extension manifest atomically."""
    directory = tmp_path / "dashboards"
    directory.mkdir()
    write_json(directory / "one.json", {"uid": "one", "title": "One"})
    spec = source_spec(directory, group_id="fixture")
    spec["first"] = []
    sources = source_file(tmp_path, [spec])
    output = tmp_path / "extension" / "dashboards.json"

    assert generate.main(sources, output) == 0
    assert json.loads(output.read_text(encoding="utf-8")) == {
        "groups": [
            {
                "id": "fixture",
                "title": "Test",
                "color": "purple",
                "tabs": [{"title": "One", "url": "http://localhost:3030/d/one"}],
            }
        ]
    }


def test_committed_manifest_matches_the_checked_in_source_snapshot(
    tmp_path: Path,
) -> None:
    """CI detects hand-edited or stale generated dashboard output."""
    source_manifest = json.loads(
        (MODULE_PATH.parent / "sources.json").read_text(encoding="utf-8")
    )
    snapshot = json.loads(
        (
            MODULE_PATH.parent / "tests" / "fixtures" / "dashboard-snapshot.json"
        ).read_text(encoding="utf-8")
    )
    specs = []
    for original in source_manifest["groups"]:
        directory = tmp_path / original["id"]
        directory.mkdir()
        for dashboard_data in snapshot[original["id"]]:
            write_json(directory / f"{dashboard_data['uid']}.json", dashboard_data)
        spec = dict(original)
        spec["dashboard_dir"] = str(directory)
        specs.append(spec)

    generated = {"groups": [generate.build_group(spec) for spec in specs]}
    committed = json.loads(
        (MODULE_PATH.parent / "extension" / "dashboards.json").read_text()
    )
    assert generated == committed
