"""Constants shared by pure token_auditor core modules."""

PROJECT_NAME = "token-auditor"
CODEX_SESSION_GLOB = "sessions/*/*/*/rollout-*.jsonl"
CLAUDE_SESSION_GLOB = "projects/*/*.jsonl"
AMP_THREAD_GLOB = "T-*.json"
OPENCODE_DB_DEFAULT = "~/.local/share/opencode/opencode.db"
AMP_THREADS_DIR_DEFAULT = "~/.local/share/amp/threads"

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
    "amp": {
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
    "amp": {
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
    "amp": (
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

EVERFOREST_HEADER_COLOR_256 = 108
EVERFOREST_SECTION_COLOR_256 = 109
EVERFOREST_MUTED_COLOR_256 = 245
EVERFOREST_GRADIENT_256 = (108, 109, 110, 142, 143, 150, 179, 180, 181)
