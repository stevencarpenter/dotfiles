#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.11"
# dependencies = []
# ///
"""Unit tests for the SubagentStop payload parser.

The parser gates the whole live-team reap path: if it rejects a real payload
the feature is silently inert, and if it accepts a hostile one an attacker
chosen string reaches an agent-reap CLI flag. Both failures are invisible at
runtime, so the contract is pinned here.

The parser is exec'd by the reap hooks as ``/usr/bin/python3 <path>``, so these
tests drive it as a subprocess under that same interpreter rather than
importing it.
"""

from __future__ import annotations

import json
import subprocess
import unittest
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[1]
PARSER = REPO_ROOT / "home/.claude/hooks/lib/parse-subagent-stop-payload.py"
SYSTEM_PYTHON = "/usr/bin/python3"


def run_parser(payload: object) -> str:
    """Run the parser on a payload and return its stdout.

    Args:
        payload: Object serialized to JSON and written to the parser's stdin.
            A ``str`` is passed through verbatim so malformed JSON can be tested.

    Returns:
        The parser's stdout, stripped of the trailing newline.

    Raises:
        AssertionError: If the parser exits non-zero. It is best-effort by
            contract and must always exit 0.
    """
    text = payload if isinstance(payload, str) else json.dumps(payload)
    result = subprocess.run(
        [SYSTEM_PYTHON, str(PARSER)],
        input=text,
        capture_output=True,
        text=True,
        check=False,
    )
    assert result.returncode == 0, (
        f"parser exited {result.returncode}: {result.stderr}"
    )
    return result.stdout.strip()


class ParseSubagentStopPayloadTest(unittest.TestCase):
    """Accept only well-formed completion events for a matching parent."""

    def test_parent_session_id_form_is_accepted(self) -> None:
        """The current Claude payload shape yields session and agent name."""
        out = run_parser(
            {
                "hook_event_name": "SubagentStop",
                "agent_id": "docs-readme@session-abc123",
                "parent_session_id": "abc123",
            }
        )
        self.assertEqual(out, "abc123\tdocs-readme")

    def test_team_name_fallback_form_is_accepted(self) -> None:
        """Older payloads carry the parent as a session-prefixed team_name."""
        out = run_parser(
            {
                "agent_id": "api-review@session-abc123",
                "team_name": "session-abc123",
            }
        )
        self.assertEqual(out, "abc123\tapi-review")

    def test_mismatched_parent_session_is_rejected(self) -> None:
        """An agent belonging to another session is never a reap target."""
        self.assertEqual(
            run_parser(
                {
                    "agent_id": "docs-readme@session-zzz999",
                    "parent_session_id": "abc123",
                }
            ),
            "",
        )

    def test_agent_id_without_session_marker_is_rejected(self) -> None:
        """A bare agent id carries no session to scope the reap to."""
        self.assertEqual(
            run_parser({"agent_id": "docs-readme", "parent_session_id": "abc123"}),
            "",
        )

    def test_other_event_types_are_ignored(self) -> None:
        """Only SubagentStop authorizes a completion reap."""
        self.assertEqual(
            run_parser(
                {
                    "hook_event_name": "SessionEnd",
                    "agent_id": "docs-readme@session-abc123",
                    "parent_session_id": "abc123",
                }
            ),
            "",
        )

    def test_argument_injection_in_agent_name_is_rejected(self) -> None:
        """A leading dash would otherwise reach agent-reap as a flag."""
        for hostile in ("--kill@session-abc123", "-x@session-abc123"):
            with self.subTest(agent_id=hostile):
                self.assertEqual(
                    run_parser(
                        {"agent_id": hostile, "parent_session_id": "abc123"}
                    ),
                    "",
                )

    def test_shell_metacharacters_in_agent_name_are_rejected(self) -> None:
        """The name reaches a CLI flag, so its charset stays conservative."""
        for hostile in ("a b@session-abc123", "a;id@session-abc123"):
            with self.subTest(agent_id=hostile):
                self.assertEqual(
                    run_parser(
                        {"agent_id": hostile, "parent_session_id": "abc123"}
                    ),
                    "",
                )

    def test_non_alphanumeric_session_is_rejected(self) -> None:
        """The session id is a directory component and stays alphanumeric."""
        self.assertEqual(
            run_parser(
                {
                    "agent_id": "docs-readme@session-..",
                    "parent_session_id": "..",
                }
            ),
            "",
        )

    def test_missing_parent_is_rejected(self) -> None:
        """Without a parent there is no live team to scope the reap to."""
        self.assertEqual(run_parser({"agent_id": "docs-readme@session-abc123"}), "")

    def test_malformed_json_exits_quietly(self) -> None:
        """A truncated or absent payload must not fail the parent session."""
        self.assertEqual(run_parser("{not json"), "")
        self.assertEqual(run_parser(""), "")

    def test_non_string_agent_id_is_rejected(self) -> None:
        """A payload shape change must not raise, only decline."""
        self.assertEqual(
            run_parser({"agent_id": 42, "parent_session_id": "abc123"}), ""
        )


if __name__ == "__main__":
    unittest.main()
