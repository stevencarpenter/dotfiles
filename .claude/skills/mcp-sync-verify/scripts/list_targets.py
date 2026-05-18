"""Print the set of paths mcp_sync will (over)write, discovered dynamically.

Reads ``mcp_sync.sync._build_targets`` plus the three special-cased
sync functions (codex, claude.json patch, copilot-cli) so this never
goes stale when a new target is added in sync.py.

Usage:
    uv run --project mcp_sync python .claude/skills/mcp-sync-verify/scripts/list_targets.py
"""

from __future__ import annotations

from pathlib import Path

from mcp_sync.sync import _build_targets


def main() -> int:
    home = Path.home()
    print("# mcp_sync deployment targets")
    print()
    print("## Generated wholesale (from _build_targets):")
    for t in _build_targets(home):
        print(f"  - {t.name:<28} {t.destination}")
        if t.legacy_destination:
            print(f"    {'(legacy)':<28} {t.legacy_destination}")
    print()
    print("## Special-cased writers (see sync.py):")
    print(f"  - codex                        {home / '.codex' / 'config.toml'}")
    print(
        f"  - claude (patched in place)    {home / '.claude.json'} "
        "(only mcpServers key is touched)"
    )
    print(
        f"  - copilot-cli (auth preserved) {home / '.config' / '.copilot' / 'config.json'}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
