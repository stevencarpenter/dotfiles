"""Tests for live oMLX model discovery."""

from __future__ import annotations

import copy
import io
import json

from mcp_sync import omlx


def test_is_chat_model_filters_non_chat() -> None:
    """Embedding/rerank/document/TTS IDs are excluded; chat IDs pass."""
    assert not omlx.is_chat_model("nomicai-modernbert-embed-base-8bit")
    assert not omlx.is_chat_model("MarkItDown")
    assert not omlx.is_chat_model("rerank-model")
    assert not omlx.is_chat_model("text-embedding-ada-002")
    assert not omlx.is_chat_model("my-reranker")
    assert not omlx.is_chat_model("WHISPER-large")
    assert not omlx.is_chat_model("voice-tts-hd")
    assert not omlx.is_chat_model("EMBED-base")
    assert omlx.is_chat_model("Qwen3.8-Flash-Next-MLX-4bit")
    assert omlx.is_chat_model("batts-model")


def test_discover_returns_chat_ids(monkeypatch) -> None:
    """Live /v1/models data is filtered to chat IDs."""
    payload = {
        "data": [
            {"id": "Qwen3.8-Flash-Next-MLX-4bit"},
            {"id": "nomicai-modernbert-embed-base-8bit"},
            {"id": "MarkItDown"},
        ]
    }

    class Reader(io.BytesIO):
        def __enter__(self) -> Reader:
            return self

        def __exit__(self, *args: object) -> bool:
            return False

    seen: dict[str, object] = {}

    def fake_urlopen(req: object, timeout: object = None) -> Reader:
        seen["url"] = req.full_url  # type: ignore[union-attr]
        seen["auth"] = req.get_header("Authorization")  # type: ignore[union-attr]
        seen["timeout"] = timeout
        return Reader(json.dumps(payload).encode())

    monkeypatch.setattr(omlx.urllib.request, "urlopen", fake_urlopen)
    assert omlx.discover_model_ids() == ["Qwen3.8-Flash-Next-MLX-4bit"]
    assert seen["url"] == "http://localhost:42069/v1/models"
    assert seen["auth"] == "Bearer omlx"
    assert seen["timeout"] == 3.0


def test_discover_falls_back_on_error(monkeypatch) -> None:
    """Server errors yield an empty list (template fallback applies)."""

    def boom(*args: object, **kwargs: object) -> object:
        raise ConnectionError("down")

    monkeypatch.setattr(omlx.urllib.request, "urlopen", boom)
    assert omlx.discover_model_ids() == []


def _discover_with_body(monkeypatch: object, body: bytes) -> list[str]:
    """Run discovery against a canned raw response body."""

    class Reader(io.BytesIO):
        def __enter__(self) -> Reader:
            return self

        def __exit__(self, *args: object) -> bool:
            return False

    monkeypatch.setattr(  # type: ignore[union-attr]
        omlx.urllib.request, "urlopen", lambda req, timeout=None: Reader(body)
    )
    return omlx.discover_model_ids()


def test_discover_treats_malformed_bodies_as_fallback(monkeypatch) -> None:
    """Non-dict bodies, non-list data, and bad entries yield []."""
    assert _discover_with_body(monkeypatch, json.dumps({}).encode()) == []
    assert _discover_with_body(monkeypatch, json.dumps({"data": "x"}).encode()) == []
    assert _discover_with_body(monkeypatch, json.dumps([1, 2]).encode()) == []
    assert (
        _discover_with_body(
            monkeypatch,
            json.dumps({"data": [{"id": 1}, {}, {"id": ""}]}).encode(),
        )
        == []
    )
    assert _discover_with_body(monkeypatch, b"{broken") == []


def test_discover_honors_custom_env(monkeypatch) -> None:
    """Custom base URL is slash-stripped; custom key is sent."""
    monkeypatch.setenv("OMLX_BASE_URL", "http://example:1/v1/")
    monkeypatch.setenv("OMLX_API_KEY", "secret")
    seen: dict[str, object] = {}

    class Reader(io.BytesIO):
        def __enter__(self) -> Reader:
            return self

        def __exit__(self, *args: object) -> bool:
            return False

    def fake_urlopen(req: object, timeout: object = None) -> Reader:
        seen["url"] = req.full_url  # type: ignore[union-attr]
        seen["auth"] = req.get_header("Authorization")  # type: ignore[union-attr]
        return Reader(json.dumps({"data": [{"id": "M"}]}).encode())

    monkeypatch.setattr(omlx.urllib.request, "urlopen", fake_urlopen)
    assert omlx.discover_model_ids() == ["M"]
    assert seen["url"] == "http://example:1/v1/models"
    assert seen["auth"] == "Bearer secret"


def test_discover_rejects_non_http_base_url(monkeypatch) -> None:
    """A scheme-less or non-http base URL yields fallback, never a request."""
    monkeypatch.setenv("OMLX_BASE_URL", "gopher://evil/models")

    def boom(*args: object, **kwargs: object) -> object:
        raise AssertionError("no request must be sent")

    monkeypatch.setattr(omlx.urllib.request, "urlopen", boom)
    assert omlx.discover_model_ids() == []


def test_refresh_unions_live_over_template(monkeypatch) -> None:
    """Live IDs are added; template entries survive a partial live list."""
    monkeypatch.setattr(omlx, "discover_model_ids", lambda timeout=3.0: ["Model-B"])
    config = {"provider": {"omlx": {"models": {"Model-A": {"name": "old"}}}}}
    out = omlx.refresh_provider_models(config)
    assert out["provider"]["omlx"]["models"] == {
        "Model-A": {"name": "old"},
        "Model-B": {"name": "Model-B"},
    }
    assert config["provider"]["omlx"]["models"] == {"Model-A": {"name": "old"}}


def test_refresh_keeps_fallback_when_down(monkeypatch) -> None:
    """Empty discovery leaves the static template list untouched."""
    monkeypatch.setattr(omlx, "discover_model_ids", lambda timeout=3.0: [])
    config = {"provider": {"omlx": {"models": {"Model-A": {"name": "old"}}}}}
    before = copy.deepcopy(config)
    out = omlx.refresh_provider_models(config)
    assert out == before
    assert out == config


def test_build_applies_live_refresh(tmp_path, monkeypatch, synthetic_templates) -> None:
    """The opencode target unions live IDs over the template block."""
    from mcp_sync.sync import SyncTarget, transform_to_opencode_format

    monkeypatch.setattr(omlx, "discover_model_ids", lambda timeout=3.0: ["Live-Model"])
    target = SyncTarget(
        name="opencode",
        destination=tmp_path / "opencode.json",
        transform=transform_to_opencode_format,
        template_key="opencode",
        override_key="opencode",
    )
    config = target.build({"servers": {}}, home=tmp_path)
    assert "Live-Model" in config["provider"]["omlx"]["models"]


def test_build_falls_back_when_refresh_raises(
    tmp_path, monkeypatch, synthetic_templates
) -> None:
    """A refresh failure keeps the template block instead of failing sync."""
    import mcp_sync.sync as sync_mod

    def boom(config: object) -> object:
        raise RuntimeError("discovery exploded")

    monkeypatch.setattr(sync_mod, "refresh_provider_models", boom)
    target = sync_mod.SyncTarget(
        name="opencode",
        destination=tmp_path / "opencode.json",
        transform=sync_mod.transform_to_opencode_format,
        template_key="opencode",
        override_key="opencode",
    )
    config = target.build({"servers": {}}, home=tmp_path)
    assert config["provider"]["omlx"]["models"] == {
        "Fixture-Model": {"name": "fixture"}
    }


def test_build_without_omlx_block_makes_no_request(
    tmp_path, monkeypatch, synthetic_templates
) -> None:
    """Targets without an omlx block never touch the network."""

    def boom(*args: object, **kwargs: object) -> object:
        raise AssertionError("no request must be sent")

    monkeypatch.setattr(omlx.urllib.request, "urlopen", boom)
    from mcp_sync.sync import SyncTarget, transform_to_mcpservers_format

    target = SyncTarget(
        name="cursor",
        destination=tmp_path / "mcp.json",
        transform=transform_to_mcpservers_format,
        template_key="cursor",
        override_key="cursor",
    )
    target.build({"servers": {}}, home=tmp_path)


def test_build_live_false_skips_discovery(
    tmp_path, monkeypatch, synthetic_templates
) -> None:
    """Drift/capture (live=False) never touch the network."""

    def boom(*args: object, **kwargs: object) -> object:
        raise AssertionError("no request must be sent")

    monkeypatch.setattr(omlx.urllib.request, "urlopen", boom)
    from mcp_sync.sync import SyncTarget, transform_to_opencode_format

    target = SyncTarget(
        name="opencode",
        destination=tmp_path / "opencode.json",
        transform=transform_to_opencode_format,
        template_key="opencode",
        override_key="opencode",
    )
    config = target.build({"servers": {}}, home=tmp_path, live=False)
    assert config["provider"]["omlx"]["models"] == {
        "Fixture-Model": {"name": "fixture"}
    }
