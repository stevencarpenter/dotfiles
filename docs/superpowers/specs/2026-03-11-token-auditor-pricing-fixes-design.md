# Token Auditor Pricing Fixes — Design Spec

**Date:** 2026-03-11
**Scope:** `token_auditor/` — addresses 5 pricing gaps identified in `token_auditor_issues.md`

**Issue numbering:** This spec uses the numbering from `token_auditor_issues.md` (#1-#5), which splits the validation report's Issue 1 into two (threshold detection and per-message computation). Mapping: issues #1/#2 here = validation report Issue 1; issue #3 = report Issue 2; issue #4 = report Issue 3; issue #5 = report Issue 4.

---

## Problem

The token_auditor underreports Claude costs by ~35% of corrected total ($448 of $1,266 in the March 2026 dataset) because it does not account for long context (1M) premium pricing. Secondary gaps exist for cache TTL variants, fast mode, and data residency multipliers.

## Approach

Approach A: pricing tier selection in `calculate_costs()`. The caller determines whether each message exceeds the 200K threshold and passes a `long_context` flag. `calculate_costs()` selects from standard or long-context pricing tables accordingly. Pricing logic stays centralized in `pricing.py`; threshold detection lives in `claude.py`.

Issues #3-#5 are documented as constants but not wired into computation until detection becomes possible.

---

## Section 1: Constants — New Pricing Tables

**File:** `core/constants.py`

### New constants

`LONG_CONTEXT_INPUT_THRESHOLD = 200_000` — per-request input token threshold. A message's total input is `input_tokens + cached_input_tokens + cache_creation_input_tokens`.

`LONG_CONTEXT_PRICING_USD_PER_1M` — a flat `dict[str, dict[str, float]]` (model -> rates), NOT nested under a provider key like `TOKEN_PRICING_USD_PER_1M`. Uses the same rate key names (`input_tokens`, `cached_input_tokens`, `cache_creation_input_tokens`, `output_tokens`). Rates are 2x input / 1.5x output, with cache multipliers stacked on the long-context base:

| Model | `input_tokens` | `cached_input_tokens` (0.1x) | `cache_creation_input_tokens` (1.25x) | `output_tokens` |
|-------|-------|---------------|--------------------------|--------|
| `claude-opus-4-6` | 10.00 | 1.00 | 12.50 | 37.50 |
| `claude-sonnet-4-6` | 6.00 | 0.60 | 7.50 | 22.50 |

Haiku excluded — no 1M context tier.

`FAST_MODE_PRICING_USD_PER_1M` — same flat structure. 6x standard rates, documented but not wired in:

| Model | `input_tokens` | `cached_input_tokens` (0.1x) | `cache_creation_input_tokens` (1.25x) | `output_tokens` |
|-------|-------|---------------|--------------------------|--------|
| `claude-opus-4-6` | 30.00 | 3.00 | 37.50 | 150.00 |

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
- Look up rates from `LONG_CONTEXT_PRICING_USD_PER_1M[pricing_model]` instead of `TOKEN_PRICING_USD_PER_1M["claude"][pricing_model]`
- If the model isn't in `LONG_CONTEXT_PRICING_USD_PER_1M` (e.g., Haiku), fall back to standard rates from `TOKEN_PRICING_USD_PER_1M["claude"]`
- `session_total_cost_usd` in the returned breakdown reflects the actual cost at whichever tier was selected (long-context when applicable). There is no separate premium field in the `CostBreakdown` — the premium is computed externally by `compute_claude_costs()`.

All other arithmetic (codex input deduction, reasoning effort multiplier) stays identical.

### `zero_costs()` unchanged

`zero_costs()` is NOT modified. The `long_context_premium_usd` field is computed in `compute_claude_costs()` and added to the audit record in `finalize_claude_audit()`, not as part of `CostBreakdown`.

---

## Section 3: Claude Pipeline — Per-Message Computation

**File:** `core/claude.py`

### `compute_claude_costs()` rewrite

**New signature:** `compute_claude_costs(deduped_snapshots) -> tuple[CostBreakdown, float]`. The `aggregate` and `pricing_model` parameters are removed — `aggregate` was only used for the now-deleted single-model shortcut, and `pricing_model` is now resolved per-message inside the function. The function returns a tuple: the accumulated `CostBreakdown` and a `float` for `long_context_premium_usd`.

The single-model aggregate shortcut is removed. Both single-model and mixed-model sessions use the same per-message iteration path:

```
accumulated = zero_costs()
long_context_premium = 0.0

for each message in deduped_snapshots:
    pricing_model = resolve_pricing_model("claude", snapshot.model)
    total_input = input_tokens + cached_input_tokens + cache_creation_input_tokens
    is_long_context = total_input > LONG_CONTEXT_INPUT_THRESHOLD
    costs = calculate_costs(..., long_context=is_long_context)
    accumulate costs into accumulated

    if is_long_context:
        standard_costs = calculate_costs(..., long_context=False)
        long_context_premium += costs["session_total_cost_usd"] - standard_costs["session_total_cost_usd"]

return (accumulated, long_context_premium)
```

`session_total_cost_usd` in the accumulated breakdown reflects the actual cost at the correct tier per message. `long_context_premium_usd` is purely informational — the delta between actual and standard-only pricing.

### `finalize_claude_audit()` changes

Destructures the new return type: `costs, long_context_premium = compute_claude_costs(deduped_snapshots)`. Adds `"long_context_premium_usd": long_context_premium` to the audit record alongside the existing `**costs` splat.

### `aggregate_claude_usage()` unchanged

Token aggregation is fine — only costing needs to be per-message.

---

## Section 4: Types and Render

### Types (`core/types.py`)

No structural changes. `CostBreakdown` (`dict[str, float]`) and `AuditRecord` (`dict[str, AuditValue]`) accommodate new keys without modification.

### Render (`core/render.py`)

`format_cost_rows()` — add a "Long Context Premium" row showing `long_context_premium_usd` when > 0. Omitted when zero to keep output clean. Inserted immediately before the "Total Cost" row (index 5 in the current list), before both "Total Cost" and the optional "Provider Billed" row. The premium is already included in the total cost (since `session_total_cost_usd` reflects actual per-tier pricing), so this row is informational.

JSON output — no changes needed. `render_json_audit()` includes all dict keys automatically.

---

## Section 5: Testing

### New tests in `test_pricing.py`

- `test_calculate_costs_long_context_applies_premium_rates` — Opus with `long_context=True`, verify 2x input / 1.5x output with stacked cache multipliers
- `test_calculate_costs_long_context_falls_back_for_haiku` — Haiku with `long_context=True` gets standard rates
- `test_calculate_costs_long_context_false_uses_standard_rates` — Explicit `False` matches pre-change behavior

### New tests in `test_claude_core.py`

- `test_compute_claude_costs_applies_long_context_for_messages_over_200k` — Single-model session, one message under 200K, one over. Verify correct tier selection per message and `long_context_premium_usd` is the delta.
- `test_compute_claude_costs_mixed_model_with_long_context` — Mixed-model session (e.g., Opus over 200K + Haiku under 200K). Verify both model resolution and long-context detection work correctly per-message.
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
| `core/pricing.py` | Add `long_context` param to `calculate_costs()` |
| `core/claude.py` | Rewrite `compute_claude_costs()` to always iterate per-message, return `(CostBreakdown, float)` tuple; update `finalize_claude_audit()` to destructure and add `long_context_premium_usd` |
| `core/render.py` | Add conditional "Long Context Premium" row to `format_cost_rows()` |
| `tests/test_pricing.py` | 3 new tests |
| `tests/test_claude_core.py` | 4 new tests, 2 updated |
| `tests/test_render.py` | 2 new tests |

No new files created. No changes to `types.py`, `main.py`, `jsonl.py`, codex, or opencode paths.
