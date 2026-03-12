"""Constants shared by pure token_auditor core modules."""

PROJECT_NAME = "token-auditor"
CODEX_SESSION_GLOB = "sessions/*/*/*/rollout-*.jsonl"
CLAUDE_SESSION_GLOB = "projects/*/*.jsonl"
OPENCODE_DB_DEFAULT = "~/.local/share/opencode/opencode.db"

TOKEN_PRICING_USD_PER_1M: dict[str, dict[str, dict[str, float]]] = {
    "codex": {
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
    "opencode": {},
}

MODEL_PRICING_ALIASES: dict[str, dict[str, str]] = {
    "codex": {
        "gpt-5.3-codex-mini": "gpt-5.2-codex-mini",
    },
    "claude": {
        "claude-opus-4-5": "claude-opus-4-6",
        "claude-sonnet-4-5": "claude-sonnet-4-6",
        "claude-haiku-4-5-20251001": "claude-haiku-4-5",
    },
    "opencode": {},
}

MODEL_PRICING_PREFIX_ALIASES: dict[str, tuple[tuple[str, str], ...]] = {
    "codex": (),
    "claude": (
        ("claude-opus-4-5", "claude-opus-4-6"),
        ("claude-sonnet-4-5", "claude-sonnet-4-6"),
        ("claude-haiku-4-5", "claude-haiku-4-5"),
    ),
    "opencode": (),
}

REASONING_EFFORT_MULTIPLIER: dict[str, float] = {
    "none": 1.0,
    "low": 1.0,
    "medium": 1.0,
    "high": 1.0,
    "xhigh": 1.0,
}

LONG_CONTEXT_INPUT_THRESHOLD: int = 200_000

LONG_CONTEXT_PRICING_USD_PER_1M: dict[str, dict[str, float]] = {
    "claude-opus-4-6": {
        "input_tokens": 10.00,
        "cached_input_tokens": 1.00,
        "cache_creation_input_tokens": 12.50,
        "output_tokens": 37.50,
    },
    "claude-sonnet-4-6": {
        "input_tokens": 6.00,
        "cached_input_tokens": 0.60,
        "cache_creation_input_tokens": 7.50,
        "output_tokens": 22.50,
    },
}

# Not wired into computation. JSONL model IDs do not distinguish fast from standard mode.
# Fast mode is 6x standard rates and includes 1M context at no additional charge.
FAST_MODE_PRICING_USD_PER_1M: dict[str, dict[str, float]] = {
    "claude-opus-4-6": {
        "input_tokens": 30.00,
        "cached_input_tokens": 3.00,
        "cache_creation_input_tokens": 37.50,
        "output_tokens": 150.00,
    },
}

# Not wired into computation. Default 5min (1.25x) cache write rates are used.
# If Claude Code uses 1hr cache TTL, cache_creation_input_tokens rates should be updated
# to 2.0x base input instead of the current 1.25x.
CACHE_WRITE_1HR_MULTIPLIER: float = 2.0

# Not wired into computation. Applies when inference_geo is set to US-only.
# Not detectable from JSONL session data.
DATA_RESIDENCY_MULTIPLIER: float = 1.1

EVERFOREST_HEADER_COLOR_256 = 108
EVERFOREST_SECTION_COLOR_256 = 109
EVERFOREST_MUTED_COLOR_256 = 245
EVERFOREST_GRADIENT_256 = (108, 109, 110, 142, 143, 150, 179, 180, 181)
