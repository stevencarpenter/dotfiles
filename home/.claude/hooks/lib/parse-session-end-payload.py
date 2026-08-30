#!/usr/bin/python3
"""Print the team-directory segment of a Claude Code SessionEnd session id.

Reads the hook's JSON payload on stdin and prints the first dash-separated
segment of ``session_id``. Team directories are named by that segment
(session 8b5ffff0-9e14-... -> ~/.claude/teams/session-8b5ffff0), so the full
uuid would never match. A malformed payload prints nothing and exits 0.

Runs under macOS's system /usr/bin/python3 (3.9). The shebang matches the
interpreter the reap hooks exec, so a manual run hits the same runtime.
"""

import json
import sys

try:
    data = json.load(sys.stdin)
except Exception:
    sys.exit(0)

sid = data.get("session_id") or ""
print(sid.split("-", 1)[0])
