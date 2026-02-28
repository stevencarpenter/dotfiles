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
TOKEN_PRICING_USD_PER_1M: dict[str, dict[str, float]] = {
    # OpenAI API pricing source:
    # https://openai.com/api/pricing
    "gpt-5-codex": {
        "input_tokens": 1.250,
        "cached_input_tokens": 0.125,
        "output_tokens": 10.000,
    },
    "gpt-5.1-codex": {
        "input_tokens": 1.750,
        "cached_input_tokens": 0.175,
        "output_tokens": 14.000,
    },
    "gpt-5.1-codex-mini": {
        "input_tokens": 0.400,
        "cached_input_tokens": 0.040,
        "output_tokens": 3.200,
    },
    "gpt-5.2-codex": {
        "input_tokens": 1.750,
        "cached_input_tokens": 0.175,
        "output_tokens": 14.000,
    },
    "gpt-5.2-codex-mini": {
        "input_tokens": 0.400,
        "cached_input_tokens": 0.040,
        "output_tokens": 3.200,
    },
    "gpt-5.3-codex": {
        "input_tokens": 1.750,
        "cached_input_tokens": 0.175,
        "output_tokens": 14.000,
    },
}
MODEL_PRICING_ALIASES: dict[str, str] = {
    # Temporary fallback for snapshot models not yet listed on pricing page.
    "gpt-5.3-codex-mini": "gpt-5.2-codex-mini",
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


def _resolve_pricing_model(model: str) -> str:
    normalized = model.strip().lower()
    if not normalized:
        return ""
    if normalized in TOKEN_PRICING_USD_PER_1M:
        return normalized
    if normalized in MODEL_PRICING_ALIASES:
        return MODEL_PRICING_ALIASES[normalized]
    for priced_model in TOKEN_PRICING_USD_PER_1M:
        if normalized.startswith(f"{priced_model}-"):
            return priced_model
    return ""


def _calculate_costs(
        pricing_model: str,
        reasoning_effort: str,
        input_tokens: int,
        cached_input_tokens: int,
        output_tokens: int,
        reasoning_output_tokens: int,
) -> dict[str, float]:
    if pricing_model not in TOKEN_PRICING_USD_PER_1M:
        return {
            "input_cost_usd": 0.0,
            "cached_input_cost_usd": 0.0,
            "output_cost_usd": 0.0,
            "reasoning_output_cost_usd": 0.0,
            "session_total_cost_usd": 0.0,
        }

    pricing = TOKEN_PRICING_USD_PER_1M[pricing_model]
    effort_multiplier = REASONING_EFFORT_MULTIPLIER.get(reasoning_effort, 1.0)
    uncached_input_tokens = max(0, input_tokens - cached_input_tokens)
    non_reasoning_output_tokens = max(0, output_tokens - reasoning_output_tokens)
    input_cost = uncached_input_tokens * (pricing["input_tokens"] / 1_000_000)
    cached_input_cost = cached_input_tokens * (pricing["cached_input_tokens"] / 1_000_000)
    output_cost = non_reasoning_output_tokens * (pricing["output_tokens"] / 1_000_000)
    reasoning_output_cost = (
            reasoning_output_tokens * (pricing["output_tokens"] / 1_000_000) * effort_multiplier
    )
    session_total_cost = input_cost + cached_input_cost + output_cost + reasoning_output_cost
    return {
        "input_cost_usd": input_cost,
        "cached_input_cost_usd": cached_input_cost,
        "output_cost_usd": output_cost,
        "reasoning_output_cost_usd": reasoning_output_cost,
        "session_total_cost_usd": session_total_cost,
    }


def parse_session_usage(session_file: Path) -> dict[str, str | int | float] | None:
    session_id = ""
    timestamp = ""
    model = ""
    reasoning_effort = ""
    usage: dict[str, int] | None = None

    with session_file.open("r", encoding="utf-8", errors="ignore") as handle:
        for line in handle:
            event = json.loads(line)
            if event.get("type") == "session_meta":
                payload = event.get("payload") or {}
                session_id = str(payload.get("id", session_id))
            if event.get("type") == "turn_context":
                payload = event.get("payload") or {}
                model = str(payload.get("model", model))
                collaboration_mode = payload.get("collaboration_mode") or {}
                settings = collaboration_mode.get("settings") or {}
                reasoning_effort = str(
                    settings.get("reasoning_effort", payload.get("effort", reasoning_effort))
                )
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

    pricing_model = _resolve_pricing_model(model)
    costs = _calculate_costs(
        pricing_model=pricing_model,
        reasoning_effort=reasoning_effort,
        input_tokens=usage["input_tokens"],
        cached_input_tokens=usage["cached_input_tokens"],
        output_tokens=usage["output_tokens"],
        reasoning_output_tokens=usage["reasoning_output_tokens"],
    )

    return {
        "session_id": session_id,
        "session_file": str(session_file),
        "timestamp": timestamp,
        "model": model,
        "reasoning_effort": reasoning_effort,
        "pricing_model": pricing_model,
        **usage,
        **costs,
    }


def _format_usd(value: float) -> str:
    return f"{value:.9f}".rstrip("0").rstrip(".")


def _print_text_audit(audit: dict[str, str | int | float]) -> None:
    print(f"session_id: {audit['session_id']}")
    print(f"session_file: {audit['session_file']}")
    print(f"timestamp: {audit['timestamp']}")
    print(f"model: {audit['model']}")
    print(f"reasoning_effort: {audit['reasoning_effort']}")
    print(f"pricing_model: {audit['pricing_model']}")
    print(f"input_tokens: {audit['input_tokens']}")
    print(f"cached_input_tokens: {audit['cached_input_tokens']}")
    print(f"output_tokens: {audit['output_tokens']}")
    print(f"reasoning_output_tokens: {audit['reasoning_output_tokens']}")
    print(f"total_tokens: {audit['total_tokens']}")
    print(f"input_cost_usd: {_format_usd(float(audit['input_cost_usd']))}")
    print(f"cached_input_cost_usd: {_format_usd(float(audit['cached_input_cost_usd']))}")
    print(f"output_cost_usd: {_format_usd(float(audit['output_cost_usd']))}")
    print(f"reasoning_output_cost_usd: {_format_usd(float(audit['reasoning_output_cost_usd']))}")
    print(f"session_total_cost_usd: {_format_usd(float(audit['session_total_cost_usd']))}")


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
