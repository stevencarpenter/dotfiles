# Token Auditor Pricing Fixes — Design Spec

**Date:** 2026-03-11
**Scope:** `token_auditor/` — addresses 5 pricing gaps identified in the validation report

---

## Problem

The token_auditor underreports Claude costs by ~35% ($448 of $1,266 in the March 2026 dataset) because it does not account for long context (1M) premium pricing. Secondary gaps exist for cache TTL variants, fast mode, and data residency multipliers.

## Approach

Approach A: pricing tier selection in `calculate_costs()`. The caller determines whether each message exceeds the 200K threshold and passes a `long_context` flag. `calculate_costs()` selects from standard or long-context pricing tables accordingly. Pricing logic stays centralized in `pricing.py`; threshold detection lives in `claude.py`.

Issues #3-#5 are documented as constants but not wired into computation until detection becomes possible.

---

## Section 1: Constants — New Pricing Tables

**File:** `core/constants.py`

### New constants

`LONG_CONTEXT_INPUT_THRESHOLD = 200_000` — per-request input token threshold. A message's total input is `input_tokens + cached_input_tokens + cache_creation_input_tokens`.

`LONG_CONTEXT_PRICING_USD_PER_1M` — mirrors `TOKEN_PRICING_USD_PER_1M["claude"]` structure with 2x input / 1.5x output rates, cache multipliers stacked on the long-context base:

| Model | input | cached (0.1x) | cache_write_5min (1.25x) | output |
|-------|-------|---------------|--------------------------|--------|
| claude-opus-4-6 | $10.00 | $1.00 | $12.50 | $37.50 |
| claude-sonnet-4-6 | $6.00 | $0.60 | $7.50 | $22.50 |

Haiku excluded — no 1M context tier.

`FAST_MODE_PRICING_USD_PER_1M` — 6x standard rates, documented but not wired in:

| Model | input | cached (0.1x) | cache_write_5min (1.25x) | output |
|-------|-------|---------------|--------------------------|--------|
| claude-opus-4-6 | $30.00 | $3.00 | $37.50 | $150.00 |

Fast mode includes 1M context at no additional charge — no separate long-context fast-mode table needed.

`CACHE_WRITE_1HR_MULTIPLIER = 2.0` — documented with comment that the default 5min (1.25x) is used until we determine which TTL Claude Code uses. Not wired into computation.

`DATA_RESIDENCY_MULTIPLIER = 1.1` — documented with comment that it applies when `inference_geo` is US-only. Not wired into computation.

---

## Section 2: Pricing — `calculate_costs()` Changes

**File:** `core/pricing.py`

### Parameter addition

`calculate_costs()` gains one new parameter: `long_context: bool = False`. Default `False` means codex/opencode callers are unaffected.

### Behavior

When `long_context=True` and provider is `"claude"`:
- Look up rates from `LONG_CONTEXT_PRICING_USD_PER_1M` instead of `TOKEN_PRICING_USD_PER_1M["claude"]`
- If the model isn't in the long-context table (e.g., Haiku), fall back to standard rates

All other arithmetic (codex input deduction, reasoning effort multiplier) stays identical.

### `zero_costs()` change

Add `"long_context_premium_usd": 0.0` to the zero-cost breakdown so the field is always present.

---

## Section 3: Claude Pipeline — Per-Message Computation

**File:** `core/claude.py`

### `compute_claude_costs()` rewrite

The single-model aggregate shortcut is removed. Both single-model and mixed-model sessions use the same per-message iteration path:

```
for each message in deduped_snapshots:
    total_input = input_tokens + cached_input_tokens + cache_creation_input_tokens
    long_context = total_input > LONG_CONTEXT_INPUT_THRESHOLD
    pricing_model = resolve per message
    costs = calculate_costs(..., long_context=long_context)
    accumulate costs
```

### Return type change

`compute_claude_costs()` returns `tuple[CostBreakdown, float]` where the float is `long_context_premium_usd` — the difference between what was charged at long-context rates and what would have been charged at standard rates for those same messages. Computed by calculating costs at both tiers for messages exceeding 200K and accumulating the delta.

### `finalize_claude_audit()` changes

The audit record gets one new field: `"long_context_premium_usd"` surfacing the premium explicitly.

### `aggregate_claude_usage()` unchanged

Token aggregation is fine — only costing needs to be per-message.

---

## Section 4: Types and Render

### Types (`core/types.py`)

No structural changes. `CostBreakdown` (`dict[str, float]`) and `AuditRecord` (`dict[str, AuditValue]`) accommodate new keys without modification.

### Render (`core/render.py`)

`format_cost_rows()` — add a "Long Context Premium" row showing `long_context_premium_usd` when > 0. Omitted when zero to keep output clean. Positioned between existing cost rows and "Total Cost".

JSON output — no changes needed. `render_json_audit()` includes all dict keys automatically.

---

## Section 5: Testing

### New tests in `test_pricing.py`

- `test_calculate_costs_long_context_applies_premium_rates` — Opus with `long_context=True`, verify 2x input / 1.5x output with stacked cache multipliers
- `test_calculate_costs_long_context_falls_back_for_haiku` — Haiku with `long_context=True` gets standard rates
- `test_calculate_costs_long_context_false_uses_standard_rates` — Explicit `False` matches pre-change behavior

### New tests in `test_claude_core.py`

- `test_compute_claude_costs_applies_long_context_for_messages_over_200k` — Single-model session, one message under 200K, one over. Verify correct tier selection per message and `long_context_premium_usd` is the delta.
- `test_compute_claude_costs_single_model_matches_per_message_sum` — Regression: new per-message path produces same results as old aggregate path when all messages are under 200K.
- `test_parse_claude_events_includes_long_context_premium_field` — End-to-end audit record contains the field.

### Updated existing tests in `test_claude_core.py`

- `test_parse_claude_events_deduplicates_and_prices_single_model_sessions` — assert `long_context_premium_usd == 0.0`
- `test_parse_claude_events_prices_mixed_models_per_message` — assert `long_context_premium_usd == 0.0`

### New tests in `test_render.py`

- `test_format_cost_rows_includes_long_context_premium_when_nonzero`
- `test_format_cost_rows_omits_long_context_premium_when_zero`

---

## Section 6: Issues #3-#5 — Documented Constants

These get constants and documentation in code but no computation path changes.

**Issue #3 (Cache TTL):** `CACHE_WRITE_1HR_MULTIPLIER` constant with comment explaining 5min rates are the default until Claude Code's TTL is confirmed.

**Issue #4 (Fast Mode):** `FAST_MODE_PRICING_USD_PER_1M` table with comment explaining JSONL model IDs don't distinguish fast from standard.

**Issue #5 (Data Residency):** `DATA_RESIDENCY_MULTIPLIER` constant with comment explaining it applies to US-only `inference_geo` and isn't detectable from JSONL.

---

## Files Modified

| File | Change |
|------|--------|
| `core/constants.py` | Add 5 new constants/tables |
| `core/pricing.py` | Add `long_context` param to `calculate_costs()`, update `zero_costs()` |
| `core/claude.py` | Rewrite `compute_claude_costs()` to always iterate per-message, return premium |
| `core/render.py` | Add conditional "Long Context Premium" row to `format_cost_rows()` |
| `tests/test_pricing.py` | 3 new tests |
| `tests/test_claude_core.py` | 3 new tests, 2 updated |
| `tests/test_render.py` | 2 new tests |

No new files created. No changes to `types.py`, `main.py`, `jsonl.py`, codex, or opencode paths.
