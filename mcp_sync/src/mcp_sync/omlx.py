"""Live oMLX model discovery shared by all sync targets.

Queries the oMLX server's OpenAI-compatible ``/v1/models`` endpoint and
returns chat-completable model IDs. Any target whose config carries a
``provider.omlx.models`` block (today: opencode) gets that block refreshed
at sync time; when the server is unreachable the template's static fallback
list is kept untouched.
"""

from __future__ import annotations

import copy
import http.client
import json
import os
import re
import urllib.request
from typing import Any

type JsonDict = dict[str, Any]

BASE_URL_DEFAULT = "http://localhost:42069/v1"
# Mirrors home/.pi/agent/extensions/omlx-discovery.ts NON_CHAT.
NON_CHAT = re.compile(
    r"\b(embed(ding)?|rerank(er)?|markitdown|whisper|tts)\b", re.IGNORECASE
)


def is_chat_model(model_id: str) -> bool:
    """Check whether a model ID is chat-completable.

    Args:
        model_id: The model ID from ``/v1/models``.

    Returns:
        True unless the ID looks like an embedding/rerank/document/TTS model.
    """
    return not NON_CHAT.search(model_id)


def _base_url() -> str:
    """Return the validated oMLX base URL with no trailing slash.

    Raises:
        ValueError: If ``OMLX_BASE_URL`` has no http(s) scheme (likely a
            typo or injection; the bearer credential must not be sent to
            an arbitrary scheme/host).
    """
    url = os.environ.get("OMLX_BASE_URL", BASE_URL_DEFAULT).strip().rstrip("/")
    # Base must end at /v1; /models is appended by the caller.
    if not url.lower().startswith(("http://", "https://")):
        raise ValueError(f"OMLX_BASE_URL has no http(s) scheme: {url!r}")
    return url


def discover_model_ids(timeout: float = 3.0) -> list[str]:
    """Fetch live chat model IDs from the oMLX server.

    Args:
        timeout: HTTP timeout in seconds.

    Returns:
        Chat-completable model IDs, or an empty list when the server is
        unreachable, misconfigured, or returns no usable data.
    """
    try:
        request = urllib.request.Request(
            f"{_base_url()}/models",
            headers={
                "Authorization": f"Bearer {os.environ.get('OMLX_API_KEY', 'omlx')}"
            },
        )
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


def refresh_provider_models(config: JsonDict) -> JsonDict:
    """Refresh any ``provider.omlx.models`` block with live discovery.

    Args:
        config: A target config document. Never mutated; a copy is returned.

    Returns:
        Live IDs unioned over the template entries when the server answers
        (template entries survive a partial live list, so a transient
        response cannot delete configured models). The input is never
        mutated; when nothing changes the input object itself is returned.
    """
    try:
        models = config["provider"]["omlx"]["models"]
    except (KeyError, TypeError):
        return config
    if not isinstance(models, dict):
        return config
    live = discover_model_ids()
    if not live:
        return config
    # ponytail: keep template friendly names for known IDs; raw ID for new ones.
    refreshed = copy.deepcopy(config)
    merged = refreshed["provider"]["omlx"]["models"]
    for mid in live:
        merged.setdefault(mid, {"name": mid})
    return refreshed
