"""Token and cost auditing CLI for local Codex, Claude, and OpenCode transcripts."""

import argparse
import json
import logging
import sqlite3
import sys
from collections.abc import Callable, Sequence
from pathlib import Path
from typing import SupportsIndex, SupportsInt

from token_auditor._logging import configure
from token_auditor.core.claude import parse_claude_events
from token_auditor.core.codex import parse_codex_events
from token_auditor.core.constants import CODEX_SESSION_GLOB, OPENCODE_DB_DEFAULT, PROJECT_NAME
from token_auditor.core.jsonl import decode_jsonl_lines
from token_auditor.core.opencode import parse_opencode_rows
from token_auditor.core.pricing import calculate_costs, resolve_pricing_model
from token_auditor.core.render import decide_color_enabled, format_tokens, format_usd, paint, render_json_audit, render_text_audit
from token_auditor.core.session_resolution import choose_claude_session_path, claude_project_dir, claude_project_slug, latest_path
from token_auditor.core.types import AuditRecord, SessionParseError
from token_auditor.core.utils import safe_int
from token_auditor.shell.io_adapters import env_value, glob_paths, has_env, is_tty, path_exists, read_lines, sorted_paths_by_mtime

log = logging.getLogger(__name__)


def build_parser() -> argparse.ArgumentParser:
    """Build the command-line parser used by the token auditor executable.

    Returns:
        argparse.ArgumentParser: Configured parser with provider selection,
            path overrides, output format controls, and logging options.
    """
    parser = argparse.ArgumentParser(description="Print token usage audits for local Codex/Claude/OpenCode sessions.")
    parser.add_argument(
        "--provider",
        choices=("codex", "claude", "opencode", "copilot"),
        default="codex",
        help="Session provider to audit (default: codex).",
    )
    parser.add_argument("--codex-home", default="~/.codex", help="Codex home directory (default: ~/.codex).")
    parser.add_argument("--claude-home", default="~/.claude", help="Claude home directory (default: ~/.claude).")
    parser.add_argument("--opencode-db", default=OPENCODE_DB_DEFAULT, help=f"OpenCode SQLite database path (default: {OPENCODE_DB_DEFAULT}).")
    parser.add_argument("--cwd", default=str(Path.cwd()), help="Current workspace path for provider-specific session lookup.")
    parser.add_argument("--session-file", help="Specific provider session source path to audit.")
    parser.add_argument("--json", action="store_true", help="Output JSON instead of key/value text.")
    parser.add_argument(
        "--log-level",
        default="WARNING",
        choices=("DEBUG", "INFO", "WARNING", "ERROR", "CRITICAL"),
        help="Logging level (default: WARNING).",
    )
    return parser


def parse_args(argv: Sequence[str] | None = None) -> argparse.Namespace:
    """Parse command-line arguments into a namespace consumed by runtime logic.

    Args:
        argv (Sequence[str] | None): Optional explicit argument sequence.
            When omitted, arguments are read from ``sys.argv``.

    Returns:
        argparse.Namespace: Parsed values for provider, session lookup, and
            output formatting settings.
    """
    return build_parser().parse_args(argv)


def _safe_int(value: str | bytes | bytearray | SupportsInt | SupportsIndex) -> int:
    """Compatibility wrapper around core integer coercion helpers.

    Args:
        value (str | bytes | bytearray | SupportsInt | SupportsIndex): Dynamic
            value that may be integer-like and safe to coerce.

    Returns:
        int: Parsed integer value, or ``0`` on coercion failures.
    """
    return safe_int(value)


def _find_latest_session_file(base_dir: Path, session_glob: str) -> Path | None:
    """Find the newest matching session file under a base directory.

    Args:
        base_dir (Path): Root directory containing provider session logs.
        session_glob (str): Glob pattern used to discover candidate sessions.

    Returns:
        Path | None: Latest matching session file or ``None`` when no matches
            exist for the provided glob pattern.
    """
    candidates = sorted_paths_by_mtime(glob_paths(base_dir, session_glob))
    return latest_path(candidates, lambda path: path.stat().st_mtime)


def _claude_project_slug(cwd: Path) -> str:
    """Compatibility wrapper that exposes Claude project slug normalization.

    Args:
        cwd (Path): Workspace path to normalize into Claude slug format.

    Returns:
        str: Filesystem-safe Claude project slug derived from the path.
    """
    return claude_project_slug(cwd)


def _find_latest_claude_session_file(claude_home: Path, cwd: Path) -> Path | None:
    """Find the most recent Claude session using project-first resolution.

    Args:
        claude_home (Path): Base Claude home directory containing projects.
        cwd (Path): Current workspace path used to derive project slug.

    Returns:
        Path | None: Latest project-specific session, or latest global session
            when project-local transcripts are unavailable.
    """
    project_dir = claude_project_dir(claude_home, cwd)
    project_paths = sorted_paths_by_mtime(glob_paths(project_dir, "*.jsonl")) if path_exists(project_dir) else ()
    return choose_claude_session_path(project_paths, lambda path: path.stat().st_mtime)


def _resolve_pricing_model(provider: str, model: str) -> str:
    """Compatibility wrapper for pure pricing-model resolution.

    Args:
        provider (str): Provider name selecting pricing table namespaces.
        model (str): Raw model identifier as reported in session logs.

    Returns:
        str: Canonical pricing model key when known, otherwise ``""``.
    """
    return resolve_pricing_model(provider, model)


def _calculate_costs(
    provider: str,
    pricing_model: str,
    reasoning_effort: str,
    input_tokens: int,
    cached_input_tokens: int,
    cache_creation_input_tokens: int,
    output_tokens: int,
    reasoning_output_tokens: int,
) -> dict[str, float]:
    """Compatibility wrapper for pure pricing arithmetic helpers.

    Args:
        provider (str): Provider namespace for pricing semantics.
        pricing_model (str): Canonical model key in provider pricing tables.
        reasoning_effort (str): Reasoning effort that may affect output billing.
        input_tokens (int): Total input tokens from provider usage metadata.
        cached_input_tokens (int): Input tokens billed at cached rates.
        cache_creation_input_tokens (int): Input tokens used to create cache.
        output_tokens (int): Total output tokens from provider usage metadata.
        reasoning_output_tokens (int): Output tokens attributed to reasoning.

    Returns:
        dict[str, float]: Detailed USD cost breakdown for the session.
    """
    return calculate_costs(
        provider=provider,
        pricing_model=pricing_model,
        reasoning_effort=reasoning_effort,
        input_tokens=input_tokens,
        cached_input_tokens=cached_input_tokens,
        cache_creation_input_tokens=cache_creation_input_tokens,
        output_tokens=output_tokens,
        reasoning_output_tokens=reasoning_output_tokens,
    )


def parse_codex_session_usage(session_file: Path) -> AuditRecord | None:
    """Parse a Codex JSONL session file into the normalized audit payload.

    Args:
        session_file (Path): Path to a Codex session JSONL transcript.

    Returns:
        AuditRecord | None: Normalized usage/cost audit payload, or ``None``
            when no token usage events are present.

    Raises:
        SessionParseError: Raised when any session line fails JSON decoding.
    """
    lines = read_lines(session_file)
    events = decode_jsonl_lines(lines, session_file)
    return parse_codex_events(events, session_file)


def parse_claude_session_usage(session_file: Path) -> AuditRecord | None:
    """Parse a Claude JSONL session file into the normalized audit payload.

    Args:
        session_file (Path): Path to a Claude session JSONL transcript.

    Returns:
        AuditRecord | None: Normalized usage/cost audit payload, or ``None``
            when no usage-bearing assistant messages are present.

    Raises:
        SessionParseError: Raised when any session line fails JSON decoding.
    """
    lines = read_lines(session_file)
    events = decode_jsonl_lines(lines, session_file)
    return parse_claude_events(events, session_file)


def parse_opencode_session_usage(session_file: Path, cwd: Path) -> AuditRecord | None:
    """Parse an OpenCode SQLite message store into the normalized audit payload.

    Args:
        session_file (Path): Path to the OpenCode SQLite database.
        cwd (Path): Current workspace path used for OpenCode session scoping.

    Returns:
        AuditRecord | None: Normalized usage/cost audit payload, or ``None``
            when no usage-bearing assistant rows are present.

    Raises:
        SessionParseError: Raised when any OpenCode message row contains
            malformed JSON payload data.
    """
    rows: list[dict[str, object]] = []
    connection = sqlite3.connect(str(session_file))
    try:
        cursor = connection.execute(
            """
            SELECT session_id, time_created, data
            FROM message
            ORDER BY time_created ASC
            """
        )
        for session_id, time_created, data in cursor.fetchall():
            try:
                parsed_data = json.loads(str(data))
            except json.JSONDecodeError as exc:
                raise SessionParseError(f"Malformed JSON in OpenCode message row ({session_file}): {exc}") from exc
            rows.append(
                {
                    "session_id": str(session_id),
                    "time_created": int(time_created),
                    "data": parsed_data,
                }
            )
    except sqlite3.DatabaseError as exc:
        raise SessionParseError(f"Failed to read OpenCode database ({session_file}): {exc}") from exc
    finally:
        connection.close()

    return parse_opencode_rows(tuple(rows), session_file, cwd)


def _should_use_color(stream: object | None = None) -> bool:
    """Compute color mode using environment and stream capabilities.

    Args:
        stream (object | None): Optional stream override for TTY detection.

    Returns:
        bool: ``True`` when ANSI color output should be enabled.
    """
    output_stream = stream if stream is not None else sys.stdout
    return decide_color_enabled(
        color_mode=env_value("TOKEN_AUDITOR_COLOR", "auto"),
        no_color=has_env("NO_COLOR"),
        is_tty=is_tty(output_stream),
        term=env_value("TERM", ""),
    )


def _paint(text: str, color_code_256: int, enabled: bool) -> str:
    """Compatibility wrapper around the pure ANSI painter.

    Args:
        text (str): Text payload to colorize when enabled.
        color_code_256 (int): ANSI 256-color palette index to apply.
        enabled (bool): Whether ANSI styling should be applied.

    Returns:
        str: Styled text when enabled, otherwise the original text.
    """
    return paint(text, color_code_256, enabled)


def _format_usd(value: float) -> str:
    """Compatibility wrapper around USD formatting helper.

    Args:
        value (float): Numeric cost value denominated in US dollars.

    Returns:
        str: Human-readable USD representation with commas and trimmed zeros.
    """
    return format_usd(value)


def _format_tokens(value: int) -> str:
    """Compatibility wrapper around token count formatting helper.

    Args:
        value (int): Raw token count value.

    Returns:
        str: Human-readable token count string with separators.
    """
    return format_tokens(value)


def _print_text_audit(audit: AuditRecord) -> None:
    """Render and emit the human-readable audit report to standard output.

    Args:
        audit (AuditRecord): Normalized token/cost audit payload.

    Returns:
        None: The rendered report is printed to standard output.
    """
    print(render_text_audit(audit, _should_use_color()))


def _resolve_session_file(args: argparse.Namespace) -> Path | None:
    """Resolve the session file path for the provider and lookup options.

    Args:
        args (argparse.Namespace): Parsed CLI arguments controlling resolution.

    Returns:
        Path | None: Explicit path override or discovered latest session file.
    """
    if args.session_file:
        return Path(args.session_file).expanduser()

    if args.provider == "claude":
        claude_home = Path(args.claude_home).expanduser()
        cwd = Path(args.cwd).expanduser()
        return _find_latest_claude_session_file(claude_home, cwd)

    if args.provider == "opencode":
        return Path(args.opencode_db).expanduser()

    codex_home = Path(args.codex_home).expanduser()
    return _find_latest_session_file(codex_home, CODEX_SESSION_GLOB)


def main(argv: Sequence[str] | None = None) -> int:
    """Run the token-auditor CLI orchestration and return process exit code.

    Args:
        argv (Sequence[str] | None): Optional argument vector override.

    Returns:
        int: ``0`` on success, ``1`` when discovery or parsing fails.
    """
    args = parse_args(argv)
    configure(args.log_level)
    log.debug("Starting %s", PROJECT_NAME)

    if args.provider == "copilot":
        print(
            "Copilot provider is not supported: no stable structured local usage/cost schema exists for completed sessions. "
            "Re-enable only when Copilot exposes deterministic machine-readable usage fields.",
            file=sys.stderr,
        )
        return 1

    session_file = _resolve_session_file(args)
    if session_file is None:
        if args.provider == "claude":
            print("No Claude session files found.", file=sys.stderr)
        else:
            print("No Codex session files found.", file=sys.stderr)
        return 1

    if not path_exists(session_file):
        if args.provider == "opencode":
            print(f"OpenCode database not found: {session_file}", file=sys.stderr)
        else:
            print(f"Session file not found: {session_file}", file=sys.stderr)
        return 1

    cwd = Path(args.cwd).expanduser()
    parsers: dict[str, Callable[[Path], AuditRecord | None]] = {
        "codex": parse_codex_session_usage,
        "claude": parse_claude_session_usage,
        "opencode": lambda source: parse_opencode_session_usage(source, cwd),
    }

    try:
        audit = parsers[args.provider](session_file)
    except SessionParseError as exc:
        print(str(exc), file=sys.stderr)
        return 1

    if audit is None:
        print(f"No token usage data found in session file: {session_file}", file=sys.stderr)
        return 1

    serializer: Callable[[AuditRecord], str] = render_json_audit if args.json else (lambda payload: render_text_audit(payload, _should_use_color()))
    print(serializer(audit))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
