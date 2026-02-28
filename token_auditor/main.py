"""Token and cost auditing CLI for local Codex and Claude session transcripts."""

import argparse
import json
import logging
import os
import re
import sys
from collections.abc import Sequence
from pathlib import Path
from typing import SupportsIndex, SupportsInt

from _logging import configure

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

PROJECT_NAME = "token-auditor"
CODEX_SESSION_GLOB = "sessions/*/*/*/rollout-*.jsonl"
CLAUDE_SESSION_GLOB = "projects/*/*.jsonl"

TOKEN_PRICING_USD_PER_1M: dict[str, dict[str, dict[str, float]]] = {
    "codex": {
        # OpenAI API pricing source:
        # https://openai.com/api/pricing
        "gpt-5-codex": {
            "input_tokens": 1.250,
            "cached_input_tokens": 0.125,
            "output_tokens": 10.000,
            "cache_creation_input_tokens": 0.0,
        },
        "gpt-5.1-codex": {
            "input_tokens": 1.750,
            "cached_input_tokens": 0.175,
            "output_tokens": 14.000,
            "cache_creation_input_tokens": 0.0,
        },
        "gpt-5.1-codex-mini": {
            "input_tokens": 0.400,
            "cached_input_tokens": 0.040,
            "output_tokens": 3.200,
            "cache_creation_input_tokens": 0.0,
        },
        "gpt-5.2-codex": {
            "input_tokens": 1.750,
            "cached_input_tokens": 0.175,
            "output_tokens": 14.000,
            "cache_creation_input_tokens": 0.0,
        },
        "gpt-5.2-codex-mini": {
            "input_tokens": 0.400,
            "cached_input_tokens": 0.040,
            "output_tokens": 3.200,
            "cache_creation_input_tokens": 0.0,
        },
        "gpt-5.3-codex": {
            "input_tokens": 1.750,
            "cached_input_tokens": 0.175,
            "output_tokens": 14.000,
            "cache_creation_input_tokens": 0.0,
        },
    },
    "claude": {
        # Anthropic API pricing source:
        # https://www.anthropic.com/pricing
        "claude-opus-4-6": {
            "input_tokens": 5.00,
            "cached_input_tokens": 0.50,
            "cache_creation_input_tokens": 6.25,
            "output_tokens": 25.00,
        },
        "claude-sonnet-4-6": {
            "input_tokens": 3.00,
            "cached_input_tokens": 0.30,
            "cache_creation_input_tokens": 3.75,
            "output_tokens": 15.00,
        },
        "claude-haiku-4-5": {
            "input_tokens": 1.00,
            "cached_input_tokens": 0.10,
            "cache_creation_input_tokens": 1.25,
            "output_tokens": 5.00,
        },
    },
}

MODEL_PRICING_ALIASES: dict[str, dict[str, str]] = {
    "codex": {
        # Temporary fallback for snapshot models not yet listed on pricing page.
        "gpt-5.3-codex-mini": "gpt-5.2-codex-mini",
    },
    "claude": {
        "claude-opus-4-5": "claude-opus-4-6",
        "claude-sonnet-4-5": "claude-sonnet-4-6",
        "claude-haiku-4-5-20251001": "claude-haiku-4-5",
    },
}

MODEL_PRICING_PREFIX_ALIASES: dict[str, tuple[tuple[str, str], ...]] = {
    "codex": (),
    "claude": (
        ("claude-opus-4-5", "claude-opus-4-6"),
        ("claude-sonnet-4-5", "claude-sonnet-4-6"),
        ("claude-haiku-4-5", "claude-haiku-4-5"),
    ),
}

# Reasoning tokens are billed as output tokens.
# Source: https://platform.openai.com/docs/guides/reasoning
REASONING_EFFORT_MULTIPLIER: dict[str, float] = {
    "none": 1.0,
    "low": 1.0,
    "medium": 1.0,
    "high": 1.0,
    "xhigh": 1.0,
}

# Everforest-inspired terminal colors (ANSI 256-color palette approximations).
EVERFOREST_HEADER_COLOR_256 = 108
EVERFOREST_SECTION_COLOR_256 = 109
EVERFOREST_MUTED_COLOR_256 = 245
EVERFOREST_GRADIENT_256 = (108, 109, 110, 142, 143, 150, 179, 180, 181)

# ---------------------------------------------------------------------------
# Logging
# ---------------------------------------------------------------------------

log = logging.getLogger(__name__)


class SessionParseError(Exception):
    """Signal that a session JSONL transcript cannot be decoded into valid events."""


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------


def build_parser() -> argparse.ArgumentParser:
    """Build the command-line parser used by the token auditor executable.

    Returns:
        argparse.ArgumentParser: Configured parser with provider selection,
            path overrides, output format controls, and logging options.
    """
    parser = argparse.ArgumentParser(description="Print token usage audit for Codex/Claude sessions.")
    parser.add_argument(
        "--provider",
        choices=("codex", "claude"),
        default="codex",
        help="Session provider to audit (default: codex).",
    )
    parser.add_argument(
        "--codex-home",
        default="~/.codex",
        help="Codex home directory (default: ~/.codex).",
    )
    parser.add_argument(
        "--claude-home",
        default="~/.claude",
        help="Claude home directory (default: ~/.claude).",
    )
    parser.add_argument(
        "--cwd",
        default=str(Path.cwd()),
        help="Current workspace path for provider-specific session lookup.",
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
    """Parse command-line arguments into a namespace consumed by runtime logic.

    Args:
        argv (Sequence[str] | None): Optional explicit argument sequence.
            When omitted, arguments are read from ``sys.argv``.

    Returns:
        argparse.Namespace: Parsed values for provider, session lookup, and
            output formatting settings.
    """
    return build_parser().parse_args(argv)


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------


def _safe_int(value: str | bytes | bytearray | SupportsInt | SupportsIndex) -> int:
    """Convert a dynamic value to an integer while guarding against bad inputs.

    Args:
        value (str | bytes | bytearray | SupportsInt | SupportsIndex): Input
            value that may be numeric already or safely coercible to an int.

    Returns:
        int: Parsed integer value, or ``0`` when conversion fails.
    """
    try:
        return int(value)
    except TypeError, ValueError:
        return 0


def _find_latest_session_file(base_dir: Path, session_glob: str) -> Path | None:
    """Return the newest session file that matches a provider-specific glob.

    Args:
        base_dir (Path): Root directory containing session subdirectories.
        session_glob (str): Glob pattern used to discover JSONL session files.

    Returns:
        Path | None: Most recently modified matching file, or ``None`` when no
            matching session logs are found under ``base_dir``.
    """
    files = sorted(base_dir.glob(session_glob), key=lambda path: path.stat().st_mtime)
    return files[-1] if files else None


def _claude_project_slug(cwd: Path) -> str:
    """Convert a workspace path into Claude's filesystem-safe project slug.

    Args:
        cwd (Path): Workspace directory to normalize for Claude storage paths.

    Returns:
        str: Slugified representation of the resolved workspace path.
    """
    normalized = str(cwd.expanduser().resolve())
    return re.sub(r"[^A-Za-z0-9]", "-", normalized)


def _find_latest_claude_session_file(claude_home: Path, cwd: Path) -> Path | None:
    """Find the latest Claude session preferring current project logs first.

    Args:
        claude_home (Path): Base Claude home directory containing ``projects``.
        cwd (Path): Current workspace used to determine project-specific logs.

    Returns:
        Path | None: Latest project-local session file, or the latest global
            Claude session file when project-local files are unavailable.
    """
    project_dir = claude_home / "projects" / _claude_project_slug(cwd)
    project_files = sorted(project_dir.glob("*.jsonl"), key=lambda path: path.stat().st_mtime) if project_dir.exists() else []
    if project_files:
        return project_files[-1]
    return _find_latest_session_file(claude_home, CLAUDE_SESSION_GLOB)


def _resolve_pricing_model(provider: str, model: str) -> str:
    """Resolve a model name to the canonical key used in pricing tables.

    Args:
        provider (str): Provider name (``"codex"`` or ``"claude"``) selecting
            provider-specific aliases and prefix-matching behavior.
        model (str): Raw model string captured from a session transcript.

    Returns:
        str: Canonical pricing model key when a mapping is known; otherwise an
            empty string indicating that the model has no pricing entry.
    """
    normalized = model.strip().lower()
    if not normalized:
        return ""

    provider_pricing = TOKEN_PRICING_USD_PER_1M.get(provider, {})
    if normalized in provider_pricing:
        return normalized

    provider_aliases = MODEL_PRICING_ALIASES.get(provider, {})
    if normalized in provider_aliases:
        return provider_aliases[normalized]

    for prefix, target in MODEL_PRICING_PREFIX_ALIASES.get(provider, ()):
        if normalized.startswith(prefix):
            return target

    if provider == "codex":
        for priced_model in provider_pricing:
            if normalized.startswith(f"{priced_model}-"):
                return priced_model

    return ""


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
    """Compute cost components from token counts using provider pricing rules.

    Args:
        provider (str): Provider that determines billing semantics.
        pricing_model (str): Canonical model key used to lookup rate tables.
        reasoning_effort (str): Reasoning effort level affecting output billing.
        input_tokens (int): Total input tokens reported by usage metadata.
        cached_input_tokens (int): Input tokens billed at cached rates.
        cache_creation_input_tokens (int): Input tokens for cache creation.
        output_tokens (int): Total output tokens reported by usage metadata.
        reasoning_output_tokens (int): Output tokens attributed to reasoning.

    Returns:
        dict[str, float]: USD cost breakdown for each token category and the
            aggregate session total.
    """
    provider_pricing = TOKEN_PRICING_USD_PER_1M.get(provider, {})
    if pricing_model not in provider_pricing:
        return {
            "input_cost_usd": 0.0,
            "cached_input_cost_usd": 0.0,
            "cache_creation_input_cost_usd": 0.0,
            "output_cost_usd": 0.0,
            "reasoning_output_cost_usd": 0.0,
            "session_total_cost_usd": 0.0,
        }

    pricing = provider_pricing[pricing_model]
    effort_multiplier = REASONING_EFFORT_MULTIPLIER.get(reasoning_effort, 1.0)

    billable_input_tokens = max(0, input_tokens - cached_input_tokens - cache_creation_input_tokens) if provider == "codex" else max(0, input_tokens)

    non_reasoning_output_tokens = max(0, output_tokens - reasoning_output_tokens)

    input_cost = billable_input_tokens * (pricing["input_tokens"] / 1_000_000)
    cached_input_cost = cached_input_tokens * (pricing["cached_input_tokens"] / 1_000_000)
    cache_creation_input_cost = cache_creation_input_tokens * (pricing["cache_creation_input_tokens"] / 1_000_000)
    output_cost = non_reasoning_output_tokens * (pricing["output_tokens"] / 1_000_000)
    reasoning_output_cost = reasoning_output_tokens * (pricing["output_tokens"] / 1_000_000) * effort_multiplier
    session_total_cost = input_cost + cached_input_cost + cache_creation_input_cost + output_cost + reasoning_output_cost

    return {
        "input_cost_usd": input_cost,
        "cached_input_cost_usd": cached_input_cost,
        "cache_creation_input_cost_usd": cache_creation_input_cost,
        "output_cost_usd": output_cost,
        "reasoning_output_cost_usd": reasoning_output_cost,
        "session_total_cost_usd": session_total_cost,
    }


# ---------------------------------------------------------------------------
# Audits
# ---------------------------------------------------------------------------


def parse_codex_session_usage(session_file: Path) -> dict[str, str | int | float] | None:
    """Parse Codex session JSONL events into a normalized audit payload.

    Args:
        session_file (Path): JSONL transcript containing Codex session events.

    Returns:
        dict[str, str | int | float] | None: Structured token and cost summary
            for the session, or ``None`` if no token usage events are present.

    Raises:
        SessionParseError: Raised when any line in the session file is invalid
            JSON and therefore cannot be parsed into an event payload.
    """
    session_id = ""
    timestamp = ""
    model = ""
    reasoning_effort = ""
    usage: dict[str, int] | None = None

    with session_file.open("r", encoding="utf-8", errors="ignore") as handle:
        for line_number, line in enumerate(handle, start=1):
            try:
                event = json.loads(line)
            except json.JSONDecodeError as exc:
                raise SessionParseError(f"Malformed JSON in session file: {session_file} (line {line_number})") from exc

            if event.get("type") == "session_meta":
                payload = event.get("payload") or {}
                session_id = str(payload.get("id", session_id))

            if event.get("type") == "turn_context":
                payload = event.get("payload") or {}
                model = str(payload.get("model", model))
                collaboration_mode = payload.get("collaboration_mode") or {}
                settings = collaboration_mode.get("settings") or {}
                reasoning_effort = str(settings.get("reasoning_effort", payload.get("effort", reasoning_effort)))

            if event.get("type") == "event_msg":
                payload = event.get("payload") or {}
                if payload.get("type") != "token_count":
                    continue

                info = payload.get("info") or {}
                total_usage = info.get("total_token_usage") or {}
                if not total_usage:
                    continue

                usage = {
                    "input_tokens": _safe_int(total_usage.get("input_tokens", 0)),
                    "cached_input_tokens": _safe_int(total_usage.get("cached_input_tokens", 0)),
                    "cache_creation_input_tokens": _safe_int(total_usage.get("cache_creation_input_tokens", 0)),
                    "output_tokens": _safe_int(total_usage.get("output_tokens", 0)),
                    "reasoning_output_tokens": _safe_int(total_usage.get("reasoning_output_tokens", 0)),
                    "total_tokens": _safe_int(total_usage.get("total_tokens", 0)),
                }
                timestamp = str(event.get("timestamp", timestamp))

    if usage is None:
        return None

    if usage["total_tokens"] == 0:
        usage["total_tokens"] = usage["input_tokens"] + usage["cached_input_tokens"] + usage["cache_creation_input_tokens"] + usage["output_tokens"]

    pricing_model = _resolve_pricing_model("codex", model)
    costs = _calculate_costs(
        provider="codex",
        pricing_model=pricing_model,
        reasoning_effort=reasoning_effort,
        input_tokens=usage["input_tokens"],
        cached_input_tokens=usage["cached_input_tokens"],
        cache_creation_input_tokens=usage["cache_creation_input_tokens"],
        output_tokens=usage["output_tokens"],
        reasoning_output_tokens=usage["reasoning_output_tokens"],
    )

    return {
        "provider": "codex",
        "session_id": session_id,
        "session_file": str(session_file),
        "timestamp": timestamp,
        "model": model,
        "reasoning_effort": reasoning_effort,
        "pricing_model": pricing_model,
        **usage,
        **costs,
    }


def parse_claude_session_usage(session_file: Path) -> dict[str, str | int | float] | None:
    """Parse Claude session JSONL logs into a provider-aligned audit payload.

    Args:
        session_file (Path): JSONL transcript containing Claude message events.

    Returns:
        dict[str, str | int | float] | None: Aggregated token and cost summary
            for deduplicated Claude messages, or ``None`` when usage is absent.

    Raises:
        SessionParseError: Raised when any JSONL line cannot be decoded into a
            valid event record.
    """
    session_id = ""
    deduped_messages: dict[str, dict[str, str | int]] = {}

    with session_file.open("r", encoding="utf-8", errors="ignore") as handle:
        for line_number, line in enumerate(handle, start=1):
            try:
                event = json.loads(line)
            except json.JSONDecodeError as exc:
                raise SessionParseError(f"Malformed JSON in session file: {session_file} (line {line_number})") from exc

            session_id = str(event.get("sessionId", session_id))
            message = event.get("message")
            if not isinstance(message, dict):
                continue

            usage = message.get("usage")
            if not isinstance(usage, dict):
                continue

            message_id = str(message.get("id") or f"line-{line_number}")
            deduped_messages[message_id] = {
                "model": str(message.get("model", "")),
                "timestamp": str(event.get("timestamp", "")),
                "input_tokens": _safe_int(usage.get("input_tokens", 0)),
                "cached_input_tokens": _safe_int(usage.get("cache_read_input_tokens", 0)),
                "cache_creation_input_tokens": _safe_int(usage.get("cache_creation_input_tokens", 0)),
                "output_tokens": _safe_int(usage.get("output_tokens", 0)),
            }

    if not deduped_messages:
        return None

    input_tokens = sum(int(message["input_tokens"]) for message in deduped_messages.values())
    cached_input_tokens = sum(int(message["cached_input_tokens"]) for message in deduped_messages.values())
    cache_creation_input_tokens = sum(int(message["cache_creation_input_tokens"]) for message in deduped_messages.values())
    output_tokens = sum(int(message["output_tokens"]) for message in deduped_messages.values())

    timestamps = sorted(str(message["timestamp"]) for message in deduped_messages.values())
    timestamp = timestamps[-1] if timestamps else ""

    models = sorted({str(message["model"]) for message in deduped_messages.values() if str(message["model"])})
    if len(models) == 1:
        model = models[0]
        pricing_model = _resolve_pricing_model("claude", model)
    elif len(models) > 1:
        model = "mixed"
        pricing_model = "mixed"
    else:
        model = ""
        pricing_model = ""

    if pricing_model != "mixed":
        costs = _calculate_costs(
            provider="claude",
            pricing_model=pricing_model,
            reasoning_effort="",
            input_tokens=input_tokens,
            cached_input_tokens=cached_input_tokens,
            cache_creation_input_tokens=cache_creation_input_tokens,
            output_tokens=output_tokens,
            reasoning_output_tokens=0,
        )
    else:
        costs = {
            "input_cost_usd": 0.0,
            "cached_input_cost_usd": 0.0,
            "cache_creation_input_cost_usd": 0.0,
            "output_cost_usd": 0.0,
            "reasoning_output_cost_usd": 0.0,
            "session_total_cost_usd": 0.0,
        }
        for message in deduped_messages.values():
            message_model = str(message["model"])
            message_pricing_model = _resolve_pricing_model("claude", message_model)
            message_costs = _calculate_costs(
                provider="claude",
                pricing_model=message_pricing_model,
                reasoning_effort="",
                input_tokens=int(message["input_tokens"]),
                cached_input_tokens=int(message["cached_input_tokens"]),
                cache_creation_input_tokens=int(message["cache_creation_input_tokens"]),
                output_tokens=int(message["output_tokens"]),
                reasoning_output_tokens=0,
            )
            for key, value in message_costs.items():
                costs[key] += value

    return {
        "provider": "claude",
        "session_id": session_id,
        "session_file": str(session_file),
        "timestamp": timestamp,
        "model": model,
        "reasoning_effort": "",
        "pricing_model": pricing_model,
        "input_tokens": input_tokens,
        "cached_input_tokens": cached_input_tokens,
        "cache_creation_input_tokens": cache_creation_input_tokens,
        "output_tokens": output_tokens,
        "reasoning_output_tokens": 0,
        "total_tokens": input_tokens + cached_input_tokens + cache_creation_input_tokens + output_tokens,
        **costs,
    }


# ---------------------------------------------------------------------------
# Output
# ---------------------------------------------------------------------------


def _should_use_color(stream: object | None = None) -> bool:
    """Determine whether ANSI color output should be enabled for this run.

    Args:
        stream (object | None): Optional output stream override. When omitted,
            the function inspects ``sys.stdout`` for terminal capabilities.

    Returns:
        bool: ``True`` when color output is explicitly enabled or supported by
            the active terminal configuration, otherwise ``False``.
    """
    color_mode = os.getenv("TOKEN_AUDITOR_COLOR", "auto").strip().lower()
    if color_mode == "always":
        return True
    if color_mode == "never" or os.getenv("NO_COLOR") is not None:
        return False

    output_stream = stream if stream is not None else sys.stdout
    is_tty = bool(getattr(output_stream, "isatty", lambda: False)())
    return is_tty and os.getenv("TERM", "").lower() != "dumb"


def _paint(text: str, color_code_256: int, enabled: bool) -> str:
    """Wrap text with ANSI 256-color escape codes when color output is active.

    Args:
        text (str): Plain text to colorize for terminal output.
        color_code_256 (int): ANSI 256-color palette index to apply.
        enabled (bool): Flag indicating whether colorization should occur.

    Returns:
        str: Colorized text when enabled, or the original text unchanged.
    """
    return f"\x1b[38;5;{color_code_256}m{text}\x1b[0m" if enabled else text


def _format_usd(value: float) -> str:
    """Format a USD monetary value using compact, human-readable precision.

    Args:
        value (float): Numeric cost value denominated in United States dollars.

    Returns:
        str: Dollar-prefixed value with trailing zeros trimmed for readability.
    """
    return f"${value:,.9f}".rstrip("0").rstrip(".")


def _format_tokens(value: int) -> str:
    """Format token counts with separators and a consistent ``tokens`` suffix.

    Args:
        value (int): Raw token count value from usage metrics.

    Returns:
        str: Human-friendly token count string with thousands separators.
    """
    return f"{value:,} tokens"


def _print_rows(rows: Sequence[tuple[str, str]], use_color: bool, color_offset: int = 0) -> None:
    """Render aligned label/value rows with optional gradient-based colors.

    Args:
        rows (Sequence[tuple[str, str]]): Ordered list of label/value display
            pairs to render.
        use_color (bool): Whether ANSI colors should be applied to labels.
        color_offset (int): Gradient index offset used to vary section colors.

    Returns:
        None: The function writes formatted rows directly to standard output.
    """
    for idx, (label, value) in enumerate(rows):
        label_color = EVERFOREST_GRADIENT_256[(idx + color_offset) % len(EVERFOREST_GRADIENT_256)]
        print(f"  {_paint(f'{label:<20}', label_color, use_color)} {value}")


def _print_text_audit(audit: dict[str, str | int | float]) -> None:
    """Print a rich, human-readable audit report with token and cost sections.

    Args:
        audit (dict[str, str | int | float]): Normalized audit payload produced
            by one of the provider-specific parsing functions.

    Returns:
        None: The function emits formatted report text to standard output.
    """
    use_color = _should_use_color()
    provider = str(audit["provider"]).capitalize()
    title = f"{provider} Token Audit"
    print(_paint(title, EVERFOREST_HEADER_COLOR_256, use_color))
    print(_paint("-" * len(title), EVERFOREST_MUTED_COLOR_256, use_color))

    summary_rows = (
        ("Session ID", str(audit["session_id"])),
        ("Session File", str(audit["session_file"])),
        ("Timestamp", str(audit["timestamp"])),
        ("Model", str(audit["model"])),
        ("Pricing Model", str(audit["pricing_model"])),
        ("Reasoning Effort", str(audit["reasoning_effort"]) or "n/a"),
    )
    _print_rows(summary_rows, use_color)
    print()

    print(_paint("Token Usage", EVERFOREST_SECTION_COLOR_256, use_color))
    token_rows = (
        ("Input Tokens", _format_tokens(int(audit["input_tokens"]))),
        ("Cached Input", _format_tokens(int(audit["cached_input_tokens"]))),
        ("Cache Creation", _format_tokens(int(audit["cache_creation_input_tokens"]))),
        ("Output Tokens", _format_tokens(int(audit["output_tokens"]))),
        ("Reasoning Output", _format_tokens(int(audit["reasoning_output_tokens"]))),
        ("Total Tokens", _format_tokens(int(audit["total_tokens"]))),
    )
    _print_rows(token_rows, use_color, color_offset=1)
    print()

    print(_paint("Estimated Cost (USD)", EVERFOREST_SECTION_COLOR_256, use_color))
    cost_rows = (
        ("Input Cost", _format_usd(float(audit["input_cost_usd"]))),
        ("Cached Input", _format_usd(float(audit["cached_input_cost_usd"]))),
        ("Cache Creation", _format_usd(float(audit["cache_creation_input_cost_usd"]))),
        ("Output Cost", _format_usd(float(audit["output_cost_usd"]))),
        ("Reasoning Output", _format_usd(float(audit["reasoning_output_cost_usd"]))),
        ("Total Cost", _format_usd(float(audit["session_total_cost_usd"]))),
    )
    _print_rows(cost_rows, use_color, color_offset=2)


def _resolve_session_file(args: argparse.Namespace) -> Path | None:
    """Resolve which session file should be audited from parsed CLI options.

    Args:
        args (argparse.Namespace): Parsed command-line arguments for provider
            selection, optional explicit session path, and home directories.

    Returns:
        Path | None: Explicit path or discovered latest session file, or
            ``None`` when no matching session logs can be found.
    """
    if args.session_file:
        return Path(args.session_file).expanduser()

    if args.provider == "claude":
        claude_home = Path(args.claude_home).expanduser()
        cwd = Path(args.cwd).expanduser()
        return _find_latest_claude_session_file(claude_home, cwd)

    codex_home = Path(args.codex_home).expanduser()
    return _find_latest_session_file(codex_home, CODEX_SESSION_GLOB)


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------


def main(argv: Sequence[str] | None = None) -> int:
    """Run the token-auditor CLI flow and return a process-style exit code.

    Args:
        argv (Sequence[str] | None): Optional argument vector override. When
            omitted, arguments are parsed from ``sys.argv``.

    Returns:
        int: ``0`` on success, or ``1`` when session discovery/parsing fails.
    """
    args = parse_args(argv)
    configure(args.log_level)
    log.debug("Starting %s", PROJECT_NAME)

    session_file = _resolve_session_file(args)
    if session_file is None:
        if args.provider == "claude":
            print("No Claude session files found.", file=sys.stderr)
        else:
            print("No Codex session files found.", file=sys.stderr)
        return 1

    if not session_file.exists():
        print(f"Session file not found: {session_file}", file=sys.stderr)
        return 1

    try:
        audit = parse_claude_session_usage(session_file) if args.provider == "claude" else parse_codex_session_usage(session_file)
    except SessionParseError as exc:
        print(str(exc), file=sys.stderr)
        return 1

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
