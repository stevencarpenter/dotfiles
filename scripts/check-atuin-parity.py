#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.14"
# dependencies = []
# ///
"""Check shared Atuin history filters, tmux settings, and distinct sync policies.

Parse both variants with tomllib. Mutation checks verify the assertions reject
broken configurations.
"""

import sys
from pathlib import Path
from urllib.parse import urlsplit

import tomllib

SYNC_PATH = "home/.config/atuin/config.sync.toml"
LOCAL_PATH = "home/.config/atuin/config.local.toml"


def check(sync_text: str, local_text: str) -> list[str]:
    """Return the list of parity failures between the two config variants.

    Args:
        sync_text: Full contents of the syncing variant.
        local_text: Full contents of the non-syncing variant.

    Returns:
        Every violation found, one human-readable string per check that
        failed. Empty means the variants pass parity.
    """
    failures: list[str] = []
    try:
        sync = tomllib.loads(sync_text)
    except tomllib.TOMLDecodeError as exc:
        failures.append(f"{SYNC_PATH} does not parse: {exc}")
        sync = {}
    try:
        local = tomllib.loads(local_text)
    except tomllib.TOMLDecodeError as exc:
        failures.append(f"{LOCAL_PATH} does not parse: {exc}")
        local = {}

    # Equally empty or malformed filter lists must not pass parity.
    sync_filter = sync.get("history_filter")
    local_filter = local.get("history_filter")
    for label, value in ((SYNC_PATH, sync_filter), (LOCAL_PATH, local_filter)):
        if (
            not isinstance(value, list)
            or not value
            or any(
                not isinstance(pattern, str) or not pattern.strip() for pattern in value
            )
        ):
            failures.append(
                f"{label} needs a nonempty history_filter of nonempty strings"
            )
    if isinstance(sync_filter, list) and isinstance(local_filter, list):
        if sync_filter != local_filter:
            failures.append("history_filter blocks have drifted between the variants")

    # Popup preference is optional, but an explicit setting must be boolean.
    for label, cfg in ((SYNC_PATH, sync), (LOCAL_PATH, local)):
        tmux = cfg.get("tmux", {})
        if not isinstance(tmux, dict) or (
            "enabled" in tmux and not isinstance(tmux["enabled"], bool)
        ):
            failures.append(
                f"{label} needs a [tmux] table with boolean enabled when present"
            )

    # Sync stanzas: the variants must differ, explicitly. The non-syncing
    # variant must refuse sync EXPLICITLY: atuin defaults to
    # sync_address = https://api.atuin.sh with auto_sync = true, so a bare
    # "no sync_address" leaves the PUBLIC server configured.
    if local.get("auto_sync") is not False:
        failures.append(
            f"{LOCAL_PATH} must set top-level auto_sync = false"
            " (atuin defaults it to true)"
        )
    if "sync_address" in local:
        failures.append(
            f"{LOCAL_PATH} assigns a top-level sync_address"
            " (it is the non-syncing variant)"
        )
    address = sync.get("sync_address")
    try:
        endpoint = urlsplit(address) if isinstance(address, str) else None
        valid_address = (
            endpoint is not None
            and endpoint.scheme == "https"
            and bool(endpoint.hostname)
            and endpoint.port != 0
            and not any(character.isspace() for character in address)
        )
    except ValueError:
        valid_address = False
    if not valid_address:
        failures.append(f"{SYNC_PATH} needs an explicit top-level HTTPS sync_address")

    # Cache-invalidation insurance: zcached stamps inputs as "mtime:size" at
    # second resolution, so switching variants must change the file size or
    # cached `atuin init zsh` output survives the switch.
    if len(sync_text.encode()) == len(local_text.encode()):
        failures.append(
            "the two variants are identical in byte size: identical size"
            " can defeat zcached's mtime:size stamp when switching variants"
        )
    return failures


def _mutations() -> list[tuple[str, str, str, bool]]:
    """Exercise safety and parity contracts using independent TOML fixtures.

    Returns:
        Tuples of audit name, sync text, local text, and expected failure.
    """
    filters = 'history_filter = ["SECRET"]\n'
    sync_text = 'sync_address = "https://sync.example.test"\n' + filters
    local_text = "auto_sync = false\n" + filters
    cases = [
        ("minimal configs", sync_text, local_text, False),
        (
            "alternate host and filters",
            sync_text.replace("sync.example.test", "other.example.test").replace(
                '["SECRET"]', '["PASSWORD", "TOKEN"]'
            ),
            local_text.replace('["SECRET"]', '["PASSWORD", "TOKEN"]'),
            False,
        ),
        (
            "tmux disabled",
            sync_text + "[tmux]\nenabled = false\n",
            local_text,
            False,
        ),
        (
            "tmux enabled",
            sync_text,
            local_text + "[tmux]\nenabled = true\n",
            False,
        ),
        ("malformed TOML", sync_text + "[", local_text, True),
        (
            "filter drift",
            sync_text,
            local_text.replace("SECRET", "OTHER"),
            True,
        ),
        (
            "local sync enabled",
            sync_text,
            local_text.replace("false", "true"),
            True,
        ),
        ("local sync policy missing", sync_text, filters, True),
        ("local sync endpoint", sync_text, sync_text + "auto_sync = false\n", True),
        ("sync endpoint missing", filters, local_text, True),
        (
            "identical byte sizes",
            sync_text,
            local_text + "#" * (len(sync_text.encode()) - len(local_text.encode())),
            True,
        ),
    ]
    for malformed in ("[]", '[""]', '[" "]', "[1]", '"SECRET"'):
        cases.append(
            (
                f"invalid filters {malformed}",
                sync_text.replace('["SECRET"]', malformed),
                local_text.replace('["SECRET"]', malformed),
                True,
            )
        )
    for malformed in ('tmux = "yes"\n', '[tmux]\nenabled = "true"\n'):
        cases.append(("invalid tmux setting", sync_text, local_text + malformed, True))
    for address in (
        "http://sync.example.test",
        "https://",
        "https://[bad",
        "https://a:bad",
    ):
        cases.append(
            (
                f"invalid endpoint {address}",
                sync_text.replace("https://sync.example.test", address),
                local_text,
                True,
            )
        )
    return cases


def main() -> int:
    """Run the parity checks on the repo files, then the mutation audit.

    Returns:
        0 when parity and the mutation audit both hold, 1 otherwise.
    """
    repo_root = Path(__file__).resolve().parent.parent
    sync_text = (repo_root / SYNC_PATH).read_text()
    local_text = (repo_root / LOCAL_PATH).read_text()

    real = check(sync_text, local_text)
    for failure in real:
        print(f"FAIL: {failure}", file=sys.stderr)
    if real:
        return 1

    # Mutation audit: every regression must trip the guard; valid inputs
    # must not. A guard that cannot fail is worse than no guard.
    bad = 0
    for name, s, lcl, should_fail in _mutations():
        caught = bool(check(s, lcl))
        if caught != should_fail:
            print(
                f"FAIL: mutation audit: '{name}'"
                f" {'was NOT caught' if should_fail else 'tripped a valid input'}",
                file=sys.stderr,
            )
            bad += 1
    if bad:
        return 1
    print(
        "atuin config parity OK"
        " (filters identical and nonempty; optional tmux settings typed;"
        " sync stanzas distinct; mutation audit green)"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
