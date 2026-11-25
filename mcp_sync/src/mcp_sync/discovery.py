"""Live model discovery for OpenAI-compatible providers that opt in.

A provider block in a target config (today: opencode's ``provider.<name>``) opts
in with ``"discover": true``, normally from an identity's overrides file. At sync
time its ``options.baseURL`` + ``/models`` endpoint is queried and the live
chat-model IDs are unioned over the declared ``models`` block. The marker is
not an opencode key, so it is removed from every provider block whether or not
discovery runs. When the server is unreachable the declared list is kept.
"""

from __future__ import annotations

import copy
import http.client
import json
import re
import urllib.request
from typing import Any

type JsonDict = dict[str, Any]

DISCOVER_KEY = "discover"
NON_CHAT = re.compile(
    r"\b(embed(ding)?|rerank(er)?|markitdown|whisper|tts)\b", re.IGNORECASE
)


def is_chat_model(model_id: str) -> bool:
    """Check whether a model ID is chat-completable.

    Args:
        model_id: The model ID from ``/models``.

    Returns:
        True unless the ID looks like an embedding/rerank/document/TTS model.
    """
    return not NON_CHAT.search(model_id)


def _validated_base_url(base_url: str) -> str | None:
    """Return the base URL with no trailing slash, or None when it is unusable.

    Args:
        base_url: The provider's ``options.baseURL``.

    Returns:
        The normalized URL, or None when it has no http(s) scheme (a credential
        must not be sent to an arbitrary scheme).
    """
    url = base_url.strip().rstrip("/")
    if not url.lower().startswith(("http://", "https://")):
        return None
    return url


def discover_model_ids(
    base_url: str, api_key: str | None = None, timeout: float = 3.0
) -> list[str]:
    """Fetch live chat model IDs from an OpenAI-compatible server.

    Args:
        base_url: The provider base URL, ending at the API version (``.../v1``).
        api_key: Bearer credential, or None to send no Authorization header.
        timeout: HTTP timeout in seconds.

    Returns:
        Chat-completable model IDs, or an empty list when the server is
        unreachable, misconfigured, or returns no usable data.
    """
    url = _validated_base_url(base_url)
    if url is None:
        return []
    headers = {"Authorization": f"Bearer {api_key}"} if api_key else {}
    try:
        request = urllib.request.Request(f"{url}/models", headers=headers)
        with urllib.request.urlopen(request, timeout=timeout) as response:
            body = json.load(response)
    except (OSError, ValueError, http.client.HTTPException):
        return []
    ids: list[str] = []
    data = body.get("data") if isinstance(body, dict) else None
    for entry in data if isinstance(data, list) else []:
        model_id = entry.get("id") if isinstance(entry, dict) else None
        if isinstance(model_id, str) and model_id and is_chat_model(model_id):
            ids.append(model_id)
    return ids


def _literal_api_key(options: JsonDict) -> str | None:
    """Return ``options.apiKey`` when it is a literal value.

    An opencode ``{env:NAME}`` or ``{file:...}`` reference is template text, not
    a credential, so it is never sent.
    """
    key = options.get("apiKey")
    if isinstance(key, str) and key and "{" not in key:
        return key
    return None


def refresh_provider_models(config: JsonDict, live: bool = True) -> JsonDict:
    """Strip discovery markers and, when ``live``, refresh opted-in model lists.

    Args:
        config: A target config document. Never mutated.
        live: False removes the markers only and sends no request (drift and
            capture compare against this form).

    Returns:
        The input object itself when no provider carries a marker; otherwise a
        copy without markers, with live IDs unioned over each opted-in
        provider's declared models (declared entries survive a partial live
        list, so a transient response cannot delete configured models).
    """
    providers = config.get("provider")
    if not isinstance(providers, dict) or not any(
        isinstance(p, dict) and DISCOVER_KEY in p for p in providers.values()
    ):
        return config
    refreshed = copy.deepcopy(config)
    for provider in refreshed["provider"].values():
        if not isinstance(provider, dict) or DISCOVER_KEY not in provider:
            continue
        enabled = provider.pop(DISCOVER_KEY) is True
        models = provider.get("models")
        options = provider.get("options")
        if not (live and enabled and isinstance(models, dict)):
            continue
        if not isinstance(options, dict) or not isinstance(options.get("baseURL"), str):
            continue
        # ponytail: keep declared friendly names for known IDs; raw ID for new ones.
        for mid in discover_model_ids(options["baseURL"], _literal_api_key(options)):
            models.setdefault(mid, {"name": mid})
    return refreshed
