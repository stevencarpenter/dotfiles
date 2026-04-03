"""SSO token cache reader."""

from __future__ import annotations

import hashlib
import json
from datetime import datetime, timezone
from pathlib import Path


class TokenExpiredError(Exception):
    """Raised when the cached SSO token has expired."""


class TokenNotFoundError(Exception):
    """Raised when no cached SSO token file is found."""


def load_sso_token(
    session_name: str,
    cache_dir: Path | None = None,
) -> str:
    """Load and validate an SSO access token from the AWS CLI cache.

    Computes the SHA-1 hash of the session name to locate the cache file,
    then validates the token has not expired.

    Raises:
        TokenNotFoundError: If the cache file does not exist.
        TokenExpiredError: If the token's expiresAt is in the past.
    """
    if cache_dir is None:
        cache_dir = Path.home() / ".aws" / "sso" / "cache"

    cache_key = hashlib.sha1(session_name.encode()).hexdigest()
    cache_file = cache_dir / f"{cache_key}.json"

    if not cache_file.exists():
        msg = f"No cached token for session '{session_name}': {cache_file}"
        raise TokenNotFoundError(msg)

    data = json.loads(cache_file.read_text())
    access_token: str = data["accessToken"]
    expires_at_str: str = data["expiresAt"]

    expires_at = datetime.fromisoformat(expires_at_str.replace("Z", "+00:00"))
    if expires_at <= datetime.now(timezone.utc):
        msg = f"Token for session '{session_name}' expired at {expires_at_str}"
        raise TokenExpiredError(msg)

    return access_token
