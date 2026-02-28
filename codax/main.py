import argparse
import json
import logging
import sys
from collections.abc import Sequence
from pathlib import Path

from _logging import configure

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

PROJECT_NAME = "codax"
SESSION_GLOB = "sessions/*/*/*/rollout-*.jsonl"

# ---------------------------------------------------------------------------
# Logging
# ---------------------------------------------------------------------------

log = logging.getLogger(__name__)


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Print Codex session token usage.")
    parser.add_argument(
        "--codex-home",
        default="~/.codex",
        help="Codex home directory (default: ~/.codex).",
    )
    parser.add_argument(
        "--session-file",
        help="Specific session JSONL file to audit.",
    )
    parser.add_argument(
        "--json",
        action="store_true",
        help="Output JSON instead of key/value text.",
    )
    parser.add_argument(
        "--log-level",
        default="WARNING",
        choices=("DEBUG", "INFO", "WARNING", "ERROR", "CRITICAL"),
        help="Logging level (default: WARNING).",
    )
    return parser


def parse_args(argv: Sequence[str] | None = None) -> argparse.Namespace:
    return build_parser().parse_args(argv)


# ---------------------------------------------------------------------------
# Audit
# ---------------------------------------------------------------------------


def _find_latest_session_file(codex_home: Path) -> Path | None:
    files = sorted(codex_home.glob(SESSION_GLOB), key=lambda path: path.stat().st_mtime)
    return files[-1] if files else None


def parse_session_usage(session_file: Path) -> dict[str, str | int] | None:
    session_id = ""
    timestamp = ""
    usage: dict[str, int] | None = None

    with session_file.open("r", encoding="utf-8", errors="ignore") as handle:
        for line in handle:
            event = json.loads(line)
            if event.get("type") == "session_meta":
                payload = event.get("payload") or {}
                session_id = str(payload.get("id", session_id))
            if event.get("type") == "event_msg":
                payload = event.get("payload") or {}
                if payload.get("type") == "token_count":
                    info = payload.get("info") or {}
                    total_usage = info.get("total_token_usage") or {}
                    if total_usage:
                        usage = {
                            "input_tokens": int(total_usage.get("input_tokens", 0)),
                            "cached_input_tokens": int(total_usage.get("cached_input_tokens", 0)),
                            "output_tokens": int(total_usage.get("output_tokens", 0)),
                            "reasoning_output_tokens": int(total_usage.get("reasoning_output_tokens", 0)),
                            "total_tokens": int(total_usage.get("total_tokens", 0)),
                        }
                        timestamp = str(event.get("timestamp", timestamp))

    if usage is None:
        return None

    return {
        "session_id": session_id,
        "session_file": str(session_file),
        "timestamp": timestamp,
        **usage,
    }


def _print_text_audit(audit: dict[str, str | int]) -> None:
    print(f"session_id: {audit['session_id']}")
    print(f"session_file: {audit['session_file']}")
    print(f"timestamp: {audit['timestamp']}")
    print(f"input_tokens: {audit['input_tokens']}")
    print(f"cached_input_tokens: {audit['cached_input_tokens']}")
    print(f"output_tokens: {audit['output_tokens']}")
    print(f"reasoning_output_tokens: {audit['reasoning_output_tokens']}")
    print(f"total_tokens: {audit['total_tokens']}")


def _resolve_session_file(args: argparse.Namespace) -> Path | None:
    if args.session_file:
        return Path(args.session_file).expanduser()
    codex_home = Path(args.codex_home).expanduser()
    return _find_latest_session_file(codex_home)


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------


def main(argv: Sequence[str] | None = None) -> int:
    args = parse_args(argv)
    configure(args.log_level)
    log.debug("Starting %s", PROJECT_NAME)

    session_file = _resolve_session_file(args)
    if session_file is None:
        print("No Codex session files found.", file=sys.stderr)
        return 1

    if not session_file.exists():
        print(f"Session file not found: {session_file}", file=sys.stderr)
        return 1

    audit = parse_session_usage(session_file)
    if audit is None:
        print(f"No token usage data found in session file: {session_file}", file=sys.stderr)
        return 1

    if args.json:
        print(json.dumps(audit, sort_keys=True))
    else:
        _print_text_audit(audit)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
