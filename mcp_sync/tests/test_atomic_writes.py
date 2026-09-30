"""Publication failures must preserve existing client configurations."""

import json
import os
from pathlib import Path

import pytest

from mcp_sync.sync import _write_json, sync_codex_mcp


@pytest.mark.parametrize("kind", ["json", "codex"])
@pytest.mark.parametrize("operation", ["fsync", "replace"])
def test_publication_failure_preserves_config(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch, kind: str, operation: str
) -> None:
    """Keep existing bytes and remove temporary files after publication failure.

    Args:
        tmp_path: Isolated home directory.
        monkeypatch: Fixture injecting filesystem failures.
        kind: Configuration writer to exercise.
        operation: Filesystem operation that fails.

    Returns:
        None.
    """
    target = tmp_path / ".codex" / "config.toml"
    target.parent.mkdir()
    original = 'model = "existing"\n' if kind == "codex" else '{"existing": true}\n'
    target.write_text(original, encoding="utf-8")

    def fail(*args: object) -> None:
        """Raise a simulated filesystem error.

        Args:
            args: Ignored filesystem operation arguments.

        Raises:
            OSError: Always, to exercise failure preservation.
        """
        raise OSError("simulated publication failure")

    monkeypatch.setattr(f"mcp_sync.sync.os.{operation}", fail)
    with pytest.raises(OSError, match="simulated publication failure"):
        if kind == "codex":
            sync_codex_mcp({"servers": {}}, home=tmp_path)
        else:
            _write_json(target, {"replacement": True})

    assert target.read_text(encoding="utf-8") == original
    assert list(target.parent.iterdir()) == [target]


def test_json_publication_survives_short_raw_write(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    """Publish complete UTF-8 JSON when an unbuffered syscall writes partially.

    Args:
        tmp_path: Isolated output directory.
        monkeypatch: Fixture simulating the previously failing short syscall.

    Returns:
        None.
    """
    original_write = os.write

    def short_write(fd: int, data: bytes) -> int:
        """Write half the supplied bytes to simulate a legal partial write.

        Args:
            fd: Writable file descriptor.
            data: Bytes requested by the caller.

        Returns:
            Number of bytes written.
        """
        return original_write(fd, data[: max(1, len(data) // 2)])

    monkeypatch.setattr("mcp_sync.sync.os.write", short_write)
    target = tmp_path / "config.json"
    payload = {"value": "λ" * 100_000}
    _write_json(target, payload)
    assert json.loads(target.read_text(encoding="utf-8")) == payload
