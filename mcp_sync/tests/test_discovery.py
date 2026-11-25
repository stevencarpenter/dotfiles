"""Tests for opt-in live model discovery."""

from __future__ import annotations

import copy
import io
import json

from mcp_sync import discovery
from mcp_sync.sync import (
    SyncTarget,
    transform_to_mcpservers_format,
    transform_to_opencode_format,
)

BASE = "http://example.invalid/v1"


class _Reader(io.BytesIO):
    def __enter__(self) -> _Reader:
        return self

    def __exit__(self, *args: object) -> bool:
        return False


def _provider(**extra: object) -> dict[str, object]:
    return {
        "options": {"baseURL": BASE},
        "models": {"Model-A": {"name": "old"}},
        **extra,
    }


def _opencode_target(tmp_path) -> SyncTarget:
    return SyncTarget(
        name="opencode",
        destination=tmp_path / "opencode.json",
        transform=transform_to_opencode_format,
        template_key="opencode",
        override_key="opencode",
    )


def _no_request(*args: object, **kwargs: object) -> object:
    raise AssertionError("no request must be sent")


def test_is_chat_model_filters_non_chat() -> None:
    """Embedding/rerank/document/TTS IDs are excluded; chat IDs pass."""
    assert not discovery.is_chat_model("nomicai-modernbert-embed-base-8bit")
    assert not discovery.is_chat_model("MarkItDown")
    assert not discovery.is_chat_model("rerank-model")
    assert not discovery.is_chat_model("text-embedding-ada-002")
    assert not discovery.is_chat_model("my-reranker")
    assert not discovery.is_chat_model("WHISPER-large")
    assert not discovery.is_chat_model("voice-tts-hd")
    assert not discovery.is_chat_model("EMBED-base")
    assert discovery.is_chat_model("Qwen3.8-Flash-Next-MLX-4bit")
    assert discovery.is_chat_model("batts-model")


def test_discover_returns_chat_ids(monkeypatch) -> None:
    """Live /models data is filtered to chat IDs; the key is sent as a bearer."""
    payload = {
        "data": [{"id": "Chat-Model"}, {"id": "embed-model"}, {"id": "MarkItDown"}]
    }
    seen: dict[str, object] = {}

    def fake_urlopen(req: object, timeout: object = None) -> _Reader:
        seen["url"] = req.full_url  # type: ignore[union-attr]
        seen["auth"] = req.get_header("Authorization")  # type: ignore[union-attr]
        seen["timeout"] = timeout
        return _Reader(json.dumps(payload).encode())

    monkeypatch.setattr(discovery.urllib.request, "urlopen", fake_urlopen)
    assert discovery.discover_model_ids(BASE + "/", "secret") == ["Chat-Model"]
    assert seen == {"url": BASE + "/models", "auth": "Bearer secret", "timeout": 3.0}


def test_discover_sends_no_auth_without_key(monkeypatch) -> None:
    """Without an API key no Authorization header is sent."""
    seen: dict[str, object] = {}

    def fake_urlopen(req: object, timeout: object = None) -> _Reader:
        seen["auth"] = req.get_header("Authorization")  # type: ignore[union-attr]
        return _Reader(json.dumps({"data": [{"id": "M"}]}).encode())

    monkeypatch.setattr(discovery.urllib.request, "urlopen", fake_urlopen)
    assert discovery.discover_model_ids(BASE) == ["M"]
    assert seen["auth"] is None


def test_discover_falls_back_on_error(monkeypatch) -> None:
    """Server errors yield an empty list (the declared list applies)."""

    def boom(*args: object, **kwargs: object) -> object:
        raise ConnectionError("down")

    monkeypatch.setattr(discovery.urllib.request, "urlopen", boom)
    assert discovery.discover_model_ids(BASE) == []


def test_discover_treats_malformed_bodies_as_fallback(monkeypatch) -> None:
    """Non-dict bodies, non-list data, and bad entries yield []."""
    for body in (
        json.dumps({}).encode(),
        json.dumps({"data": "x"}).encode(),
        json.dumps([1, 2]).encode(),
        json.dumps({"data": [{"id": 1}, {}, {"id": ""}]}).encode(),
        b"{broken",
    ):
        monkeypatch.setattr(
            discovery.urllib.request,
            "urlopen",
            lambda req, timeout=None, body=body: _Reader(body),
        )
        assert discovery.discover_model_ids(BASE) == []


def test_discover_rejects_non_http_base_url(monkeypatch) -> None:
    """A non-http base URL yields fallback and never sends a request."""
    monkeypatch.setattr(discovery.urllib.request, "urlopen", _no_request)
    assert discovery.discover_model_ids("gopher://evil/v1", "secret") == []


def test_refresh_unions_live_over_declared(monkeypatch) -> None:
    """Live IDs are added, declared entries survive, and the marker is removed."""
    calls: list[tuple[str, str | None]] = []

    def fake(base_url: str, api_key: str | None = None) -> list[str]:
        calls.append((base_url, api_key))
        return ["Model-B"]

    monkeypatch.setattr(discovery, "discover_model_ids", fake)
    config = {"provider": {"p": _provider(discover=True), "q": _provider()}}
    out = discovery.refresh_provider_models(config)
    assert out["provider"]["p"] == {
        "options": {"baseURL": BASE},
        "models": {"Model-A": {"name": "old"}, "Model-B": {"name": "Model-B"}},
    }
    assert out["provider"]["q"] == _provider()
    assert calls == [(BASE, None)]
    assert config["provider"]["p"]["discover"] is True


def test_refresh_without_marker_returns_input(monkeypatch) -> None:
    """No marker: no request, and the input object itself is returned."""
    monkeypatch.setattr(discovery.urllib.request, "urlopen", _no_request)
    config = {"provider": {"p": _provider()}}
    assert discovery.refresh_provider_models(config) is config
    assert discovery.refresh_provider_models({"mcp": {}}) == {"mcp": {}}


def test_refresh_live_false_strips_marker_only(monkeypatch) -> None:
    """live=False and a false marker strip the marker and send no request."""
    monkeypatch.setattr(discovery.urllib.request, "urlopen", _no_request)
    config = {
        "provider": {"p": _provider(discover=True), "q": _provider(discover=False)}
    }
    out = discovery.refresh_provider_models(config, live=False)
    assert out["provider"] == {"p": _provider(), "q": _provider()}
    assert discovery.refresh_provider_models(
        {"provider": {"q": _provider(discover=False)}}
    ) == {"provider": {"q": _provider()}}


def test_refresh_sends_only_literal_keys(monkeypatch) -> None:
    """An opencode {env:...} reference is template text and is never sent."""
    keys: list[str | None] = []
    monkeypatch.setattr(
        discovery,
        "discover_model_ids",
        lambda base_url, api_key=None: keys.append(api_key) or [],
    )
    for key in ("{env:TOKEN}", "literal"):
        provider = _provider(discover=True)
        provider["options"] = {"baseURL": BASE, "apiKey": key}
        discovery.refresh_provider_models({"provider": {"p": provider}})
    assert keys == [None, "literal"]


def test_refresh_keeps_declared_when_down(monkeypatch) -> None:
    """Empty discovery leaves the declared list untouched."""
    monkeypatch.setattr(discovery, "discover_model_ids", lambda *a, **k: [])
    config = {"provider": {"p": _provider(discover=True)}}
    before = copy.deepcopy(config)
    out = discovery.refresh_provider_models(config)
    assert out["provider"]["p"] == _provider()
    assert config == before


def test_build_applies_live_refresh(tmp_path, monkeypatch, synthetic_templates) -> None:
    """The opencode target unions live IDs over an opted-in block."""
    monkeypatch.setattr(discovery, "discover_model_ids", lambda *a, **k: ["Live-Model"])
    config = _opencode_target(tmp_path).build({"servers": {}}, home=tmp_path)
    assert "Live-Model" in config["provider"]["fixture"]["models"]
    assert "discover" not in config["provider"]["fixture"]


def test_build_falls_back_when_refresh_raises(
    tmp_path, monkeypatch, synthetic_templates
) -> None:
    """A refresh failure keeps the declared block, without the marker."""
    import mcp_sync.sync as sync_mod

    real = discovery.refresh_provider_models

    def boom(config: dict, live: bool = True) -> dict:
        if live:
            raise RuntimeError("discovery exploded")
        return real(config, live=False)

    monkeypatch.setattr(sync_mod, "refresh_provider_models", boom)
    config = _opencode_target(tmp_path).build({"servers": {}}, home=tmp_path)
    assert config["provider"]["fixture"] == {
        "options": {"baseURL": "http://fixture.invalid/v1"},
        "models": {"Fixture-Model": {"name": "fixture"}},
    }


def test_build_without_providers_makes_no_request(
    tmp_path, monkeypatch, synthetic_templates
) -> None:
    """Targets without an opted-in provider never touch the network."""
    monkeypatch.setattr(discovery.urllib.request, "urlopen", _no_request)
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
    """Drift/capture (live=False) never touch the network and see no marker."""
    monkeypatch.setattr(discovery.urllib.request, "urlopen", _no_request)
    config = _opencode_target(tmp_path).build(
        {"servers": {}}, home=tmp_path, live=False
    )
    assert config["provider"]["fixture"]["models"] == {
        "Fixture-Model": {"name": "fixture"}
    }
    assert "discover" not in config["provider"]["fixture"]
