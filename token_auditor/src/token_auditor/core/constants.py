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
        # gpt-5.4 / 5.5 are logged bare (no -codex suffix) in current rollout logs.
        # gpt-5.5 also has a >272K-input long-context tier (2x) that is intentionally
        # NOT modeled: codex logs only cumulative session usage, not per-request input,
        # so the per-request threshold can't be detected (same reason batch/flex aren't
        # modeled). Standard rates are billed.
        "gpt-5.4": {
            "input_tokens": 2.500,
            "cached_input_tokens": 0.250,
            "output_tokens": 15.000,
            "cache_creation_input_tokens": 0.0,
        },
        "gpt-5.4-mini": {
            "input_tokens": 0.750,
            "cached_input_tokens": 0.075,
            "output_tokens": 4.500,
            "cache_creation_input_tokens": 0.0,
        },
        "gpt-5.5": {
            "input_tokens": 5.000,
            "cached_input_tokens": 0.500,
            "output_tokens": 30.000,
            "cache_creation_input_tokens": 0.0,
        },
    },
    "claude": {
        "claude-opus-4-7": {
            "input_tokens": 5.00,
            "cached_input_tokens": 0.50,
            "cache_creation_input_tokens": 6.25,
            "output_tokens": 25.00,
        },
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
        "claude-opus-4-7[1m]": "claude-opus-4-7",
        "claude-opus-4-5": "claude-opus-4-6",
        "claude-sonnet-4-5": "claude-sonnet-4-6",
        "claude-haiku-4-5-20251001": "claude-haiku-4-5",
        # Bare aliases are logged for some sessions (e.g. subagents); map each tier to
        # its current fleet member.
        "opus": "claude-opus-4-7",
        "sonnet": "claude-sonnet-4-6",
        "haiku": "claude-haiku-4-5",
    },
    "opencode": {},
}

MODEL_PRICING_PREFIX_ALIASES: dict[str, tuple[tuple[str, str], ...]] = {
    "codex": (),
    "claude": (
        ("claude-opus-4-7", "claude-opus-4-7"),
        ("claude-opus-4-5", "claude-opus-4-6"),
        ("claude-sonnet-4-5", "claude-sonnet-4-6"),
        ("claude-haiku-4-5", "claude-haiku-4-5"),
    ),
    "opencode": (),
}

LONG_CONTEXT_INPUT_THRESHOLD: int = 200_000

# Long-context (>200K input) pricing. As of Opus 4.6/4.7 and Sonnet 4.6, Anthropic
# bills the full 1M context window at *standard* rates — there is no >200K surcharge
# (https://platform.claude.com/docs/en/about-claude/pricing). These entries therefore
# mirror the standard table so billing is flat. The table is kept (rather than removed)
# so the long-context code path stays exercised and a future model that reintroduces a
# premium only needs its rates changed here.
LONG_CONTEXT_PRICING_USD_PER_1M: dict[str, dict[str, float]] = {
    "claude-opus-4-7": TOKEN_PRICING_USD_PER_1M["claude"]["claude-opus-4-7"],
    "claude-opus-4-6": TOKEN_PRICING_USD_PER_1M["claude"]["claude-opus-4-6"],
    "claude-sonnet-4-6": TOKEN_PRICING_USD_PER_1M["claude"]["claude-sonnet-4-6"],
}

# Not wired into computation. JSONL model IDs do not distinguish fast from standard mode.
# Fast mode is 6x standard rates and includes 1M context at no additional charge.
FAST_MODE_PRICING_USD_PER_1M: dict[str, dict[str, float]] = {
    "claude-opus-4-7": {
        "input_tokens": 30.00,
        "cached_input_tokens": 3.00,
        "cache_creation_input_tokens": 37.50,
        "output_tokens": 150.00,
    },
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
