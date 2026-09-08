#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.14"
# dependencies = []
# ///
"""Assert the two atuin config variants stay in sync where they must and
different where they must.

Why: caps.atuin used to gate the file, so machines with the cap off ran with
no history_filter + no [tmux].enabled (ctrl-r/up-arrow rendered inline, not in
a popup). Splitting fixed that but duplicated the filter list — now it can
drift. This test makes that drift a CI failure.

Both files are parsed with tomllib (stdlib), so quoting, comments, table
scoping, and reformatting are handled by the parser instead of hand-rolled
text matching. A built-in mutation self-check re-runs the assertions against
deliberately broken copies, so a guard that cannot fail is itself a CI
failure (the original bash guard's first version PASSED while the defect it
was written to catch was reproducible).
"""

import sys
from pathlib import Path

import tomllib

SYNC_PATH = "home/.config/atuin/config.sync.toml"
LOCAL_PATH = "home/.config/atuin/config.local.toml"
EXPECTED_SYNC_ADDRESS = "https://logbook.snugmarina.org"


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

    # history_filter: must exist, be non-trivial, and be identical. The
    # non-trivial floor guards against both files being emptied in lockstep,
    # which plain list equality alone reports as "identical, therefore fine".
    sync_filter = sync.get("history_filter")
    local_filter = local.get("history_filter")
    for label, value in ((SYNC_PATH, sync_filter), (LOCAL_PATH, local_filter)):
        if not isinstance(value, list) or len(value) < 5:
            failures.append(
                f"{label} has no non-trivial history_filter (need >= 5 patterns)"
            )
    if isinstance(sync_filter, list) and isinstance(local_filter, list):
        if sync_filter != local_filter:
            failures.append("history_filter blocks have drifted between the variants")

    # tmux popup: enabled must be true INSIDE the [tmux] table. Top-level or
    # [daemon]/[dotfiles] does nothing for the popup and atuin silently
    # accepts unknown keys, so the regression would be invisible upstream.
    for label, cfg in ((SYNC_PATH, sync), (LOCAL_PATH, local)):
        tmux = cfg.get("tmux")
        if not isinstance(tmux, dict) or tmux.get("enabled") is not True:
            failures.append(
                f"{label} does not set 'enabled = true' inside [tmux]"
                " — search UI will render inline, not as a popup"
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
            " — it is the non-syncing variant"
        )
    if sync.get("sync_address") != EXPECTED_SYNC_ADDRESS:
        failures.append(
            f"{SYNC_PATH} lost its top-level self-hosted sync_address"
            f" ({EXPECTED_SYNC_ADDRESS!r})"
        )

    # Cache-invalidation insurance: zcached stamps inputs as "mtime:size" at
    # second resolution, so switching variants must change the file size or
    # cached `atuin init zsh` output survives the switch.
    if len(sync_text.encode()) == len(local_text.encode()):
        failures.append(
            "the two variants are identical in byte size — identical size"
            " can defeat zcached's mtime:size stamp when switching variants"
        )
    return failures


def _mutations(sync_text: str, local_text: str) -> list[tuple[str, str, str, bool]]:
    """One regression (or valid variant) per tuple for the built-in audit.

    Each entry is (name, mutated sync text, mutated local text, should_fail);
    the audit asserts the guard fails exactly when should_fail is true.
    """

    def line(text: str, needle: str) -> str:
        """Drop every line containing ``needle``."""
        return "\n".join(line for line in text.split("\n") if needle not in line)

    def sub(text: str, old: str, new: str) -> str:
        return text.replace(old, new)

    def shrink(text: str, n: int) -> str:
        body = ["history_filter = ["] + [f'    "PAT{i}",' for i in range(n)] + ["]"]
        lines = text.split("\n")
        b = next(i for i, x in enumerate(lines) if x.startswith("history_filter"))
        e = next(i for i, x in enumerate(lines) if x == "]")
        return "\n".join(lines[:b] + body + lines[e + 1 :])

    def pad_to(text: str, size: int) -> str:
        return text + "#" + " " * (size - len(text.encode()) - 2) + "\n"

    return [
        (
            "history_filter removed from both",
            shrink(sync_text, 0),
            shrink(local_text, 0),
            True,
        ),
        ("both filters shrunk to 4", shrink(sync_text, 4), shrink(local_text, 4), True),
        (
            "both filters at the 5 floor (valid)",
            shrink(sync_text, 5),
            shrink(local_text, 5),
            False,
        ),
        (
            "pattern added to sync only",
            sub(sync_text, '    "AKIA', '    "MUTATION_ONLY",\n    "AKIA'),
            local_text,
            True,
        ),
        (
            "pattern weakened in local",
            sync_text,
            sub(local_text, '"ghp_[A-Za-z0-9]+",', '"ghp_[A-Za-z]+",'),
            True,
        ),
        (
            "pattern reordered in local",
            sync_text,
            sub(
                local_text,
                '    "DIUN_TOKEN",\n    "NTFY_PASSWORD",',
                '    "NTFY_PASSWORD",\n    "DIUN_TOKEN",',
            ),
            True,
        ),
        ("[tmux] header deleted", sync_text, line(local_text, "[tmux]"), True),
        (
            "[tmux] renamed to [daemon]",
            sync_text,
            sub(local_text, "[tmux]", "[daemon]"),
            True,
        ),
        (
            "[tmux] enabled as a string",
            sync_text,
            sub(local_text, "enabled = true", 'enabled = "true"'),
            True,
        ),
        (
            "enabled=true without spaces (valid)",
            sync_text,
            sub(local_text, "enabled = true", "enabled=true"),
            False,
        ),
        (
            "local auto_sync flipped on",
            sync_text,
            sub(local_text, "auto_sync = false", "auto_sync = true"),
            True,
        ),
        (
            "local auto_sync removed",
            sync_text,
            line(local_text, "auto_sync = false"),
            True,
        ),
        (
            "sync_address inside local's [tmux] (valid, atuin ignores it)",
            sync_text,
            sub(local_text, "enabled = true", 'enabled = true\nsync_address = "x"'),
            False,
        ),
        (
            "local gains top-level sync_address",
            sync_text,
            sub(
                local_text,
                "auto_sync = false",
                'auto_sync = false\nsync_address = "https://logbook.snugmarina.org"',
            ),
            True,
        ),
        (
            "sync address repointed",
            sub(sync_text, EXPECTED_SYNC_ADDRESS, '"https://evil.example.com"'),
            local_text,
            True,
        ),
        ("sync address removed", line(sync_text, "sync_address ="), local_text, True),
        (
            "variants padded to identical size",
            sync_text,
            pad_to(local_text, len(sync_text.encode())),
            True,
        ),
    ]


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
    for name, s, lcl, should_fail in _mutations(sync_text, local_text):
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
        " (filter identical + non-trivial; [tmux].enabled set in both;"
        " sync stanzas distinct; mutation audit green)"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
