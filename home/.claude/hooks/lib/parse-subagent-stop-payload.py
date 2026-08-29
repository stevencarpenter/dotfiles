#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.9"
# dependencies = []
# ///
"""Extract the reap target from a Claude Code SubagentStop hook payload.

Reads the hook's JSON payload on stdin and prints "<session>\\t<agent-name>"
when the event names a completed teammate of a live team. Any payload that is
malformed, of another event type, or whose ids fail validation produces no
output and exit status 0, so the calling hook stays best-effort.

The parent session is the live team id. SubagentStop's ``session_id`` is the
subagent's own transcript id, so ``parent_session_id`` is preferred, falling
back to the ``team_name``/``agent_id`` forms emitted by older Claude versions.

Runs under macOS's system /usr/bin/python3 (3.9): the hook must not depend on
uv or any interpreter installed by this repo. The PEP 723 header above only
makes standalone `uv run --script` invocation possible for manual testing.
"""

import json
import re
import sys

try:
    data = json.load(sys.stdin)
except Exception:
    sys.exit(0)

event = data.get("hook_event_name")
if event not in (None, "", "SubagentStop"):
    sys.exit(0)

agent_id = data.get("agent_id")
if not isinstance(agent_id, str):
    sys.exit(0)
agent_name, marker, agent_session = agent_id.partition("@session-")
if not marker or not agent_name or not agent_session:
    sys.exit(0)

parent = data.get("parent_session_id") or data.get("team_name")
if not isinstance(parent, str) or not parent:
    sys.exit(0)
if parent.startswith("session-"):
    parent = parent[len("session-") :]
session = parent.split("-", 1)[0]
agent_session = agent_session.split("-", 1)[0]
if agent_session != session:
    sys.exit(0)
if not re.fullmatch(r"[A-Za-z0-9]+", session):
    sys.exit(0)
if not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9_.-]*", agent_name):
    sys.exit(0)
print(f"{session}\t{agent_name}")
