# Token Auditor Pricing Fixes Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix the 35% cost underreporting caused by missing long context (1M) premium pricing, and document gaps for cache TTL, fast mode, and data residency.

**Architecture:** Add per-message cost computation to the Claude pipeline (replacing session-level aggregation), with a `long_context` flag on `calculate_costs()` that selects between standard and long-context pricing tables. Issues #3-#5 add constants only, no computation changes.

**Tech Stack:** Python 3.14+, pytest, ruff, uv

**Spec:** `docs/superpowers/specs/2026-03-11-token-auditor-pricing-fixes-design.md`

**Test command (all):** `uv run --project token_auditor --group dev pytest token_auditor/tests -v`

**Test command (single):** `uv run --project token_auditor --group dev pytest token_auditor/tests/<file>::<test_name> -v`

**Lint:** `uv run --project token_auditor --group dev ruff check token_auditor/src token_auditor/tests && uv run --project token_auditor --group dev ruff format --check token_auditor/src token_auditor/tests`

---

## Chunk 1: Constants and Pricing Tier Selection

### Task 1: Add long context constants to `constants.py`

**Files:**
- Modify: `token_auditor/src/token_auditor/core/constants.py:91-98`

- [ ] **Step 1: Add all new constants**

Insert after `REASONING_EFFORT_MULTIPLIER` (line 98) and before the Everforest color constants (line 100):

```python
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
```

- [ ] **Step 2: Run lint to verify**

Run: `uv run --project token_auditor --group dev ruff check token_auditor/src/token_auditor/core/constants.py`
Expected: PASS (no errors)

- [ ] **Step 3: Run existing tests to verify no regressions**

Run: `uv run --project token_auditor --group dev pytest token_auditor/tests -v`
Expected: All existing tests PASS

- [ ] **Step 4: Commit**

```bash
git add token_auditor/src/token_auditor/core/constants.py
git commit -m "feat(token-auditor): add long context, fast mode, cache TTL, and data residency constants"
```

---

### Task 2: Add `long_context` parameter to `calculate_costs()`

**Files:**
- Modify: `token_auditor/src/token_auditor/core/pricing.py:1-4,45-60`
- Test: `token_auditor/tests/test_pricing.py`

- [ ] **Step 1: Write the failing test for long context Opus rates**

Append to `token_auditor/tests/test_pricing.py`:

```python
def test_calculate_costs_long_context_applies_premium_rates() -> None:
    costs = calculate_costs(
        provider="claude",
        pricing_model="claude-opus-4-6",
        reasoning_effort="",
        input_tokens=1000,
        cached_input_tokens=500_000,
        cache_creation_input_tokens=100_000,
        output_tokens=5000,
        reasoning_output_tokens=0,
        long_context=True,
    )

    # Long context Opus: input=$10/M, cached=$1/M, cache_creation=$12.5/M, output=$37.5/M
    assert costs["input_cost_usd"] == pytest.approx(0.01)
    assert costs["cached_input_cost_usd"] == pytest.approx(0.50)
    assert costs["cache_creation_input_cost_usd"] == pytest.approx(1.25)
    assert costs["output_cost_usd"] == pytest.approx(0.1875)
    assert costs["session_total_cost_usd"] == pytest.approx(1.9475)
```

- [ ] **Step 2: Run test to verify it fails**

Run: `uv run --project token_auditor --group dev pytest token_auditor/tests/test_pricing.py::test_calculate_costs_long_context_applies_premium_rates -v`
Expected: FAIL — `calculate_costs()` does not accept `long_context` parameter

- [ ] **Step 3: Write the failing test for Haiku fallback**

Append to `token_auditor/tests/test_pricing.py`:

```python
def test_calculate_costs_long_context_falls_back_for_haiku() -> None:
    costs = calculate_costs(
        provider="claude",
        pricing_model="claude-haiku-4-5",
        reasoning_effort="",
        input_tokens=36,
        cached_input_tokens=165811,
        cache_creation_input_tokens=62198,
        output_tokens=1357,
        reasoning_output_tokens=0,
        long_context=True,
    )

    # Haiku has no long context tier — falls back to standard rates
    assert costs["input_cost_usd"] == pytest.approx(0.000036)
    assert costs["cached_input_cost_usd"] == pytest.approx(0.0165811)
    assert costs["cache_creation_input_cost_usd"] == pytest.approx(0.0777475)
    assert costs["output_cost_usd"] == pytest.approx(0.006785)
    assert costs["session_total_cost_usd"] == pytest.approx(0.1011496)
```

- [ ] **Step 4: Write the failing test for explicit long_context=False**

Append to `token_auditor/tests/test_pricing.py`:

```python
def test_calculate_costs_long_context_false_uses_standard_rates() -> None:
    costs = calculate_costs(
        provider="claude",
        pricing_model="claude-opus-4-6",
        reasoning_effort="",
        input_tokens=1000,
        cached_input_tokens=500_000,
        cache_creation_input_tokens=100_000,
        output_tokens=5000,
        reasoning_output_tokens=0,
        long_context=False,
    )

    # Standard Opus: input=$5/M, cached=$0.5/M, cache_creation=$6.25/M, output=$25/M
    assert costs["input_cost_usd"] == pytest.approx(0.005)
    assert costs["cached_input_cost_usd"] == pytest.approx(0.25)
    assert costs["cache_creation_input_cost_usd"] == pytest.approx(0.625)
    assert costs["output_cost_usd"] == pytest.approx(0.125)
    assert costs["session_total_cost_usd"] == pytest.approx(1.005)
```

- [ ] **Step 5: Implement the `long_context` parameter in `calculate_costs()`**

In `token_auditor/src/token_auditor/core/pricing.py`:

1. Add `LONG_CONTEXT_PRICING_USD_PER_1M` to the import from constants (line 3).

2. Add `long_context: bool = False` parameter to `calculate_costs()` (after `reasoning_output_tokens`).

3. Replace the pricing lookup logic (lines 56-60) with:

```python
    provider_pricing = TOKEN_PRICING_USD_PER_1M.get(provider, {})
    if long_context and provider == "claude" and pricing_model in LONG_CONTEXT_PRICING_USD_PER_1M:
        pricing = LONG_CONTEXT_PRICING_USD_PER_1M[pricing_model]
    elif pricing_model not in provider_pricing:
        return zero_costs()
    else:
        pricing = provider_pricing[pricing_model]
```

- [ ] **Step 6: Run all pricing tests to verify**

Run: `uv run --project token_auditor --group dev pytest token_auditor/tests/test_pricing.py -v`
Expected: All 10 tests PASS (7 existing + 3 new)

- [ ] **Step 7: Run full test suite**

Run: `uv run --project token_auditor --group dev pytest token_auditor/tests -v`
Expected: All tests PASS (existing tests unaffected because `long_context` defaults to `False`)

- [ ] **Step 8: Commit**

```bash
git add token_auditor/src/token_auditor/core/pricing.py token_auditor/tests/test_pricing.py
git commit -m "feat(token-auditor): add long_context tier selection to calculate_costs()"
```

---

## Chunk 2: Per-Message Cost Computation in Claude Pipeline

### Task 3: Rewrite `compute_claude_costs()` for per-message iteration

**Files:**
- Modify: `token_auditor/src/token_auditor/core/claude.py:1-9,85-149`
- Test: `token_auditor/tests/test_claude_core.py`

- [ ] **Step 1: Write the failing test for long context threshold detection**

Append to `token_auditor/tests/test_claude_core.py`. Add `compute_claude_costs` to the import on line 7, and add `reduce_message_snapshots` if not already imported.

```python
def test_compute_claude_costs_applies_long_context_for_messages_over_200k() -> None:
    """Single-model Opus session: one message under 200K, one over."""
    under = extract_claude_message_snapshot(
        {
            "timestamp": "t1",
            "message": {
                "id": "m1",
                "model": "claude-opus-4-6",
                "usage": {
                    "input_tokens": 100,
                    "cache_read_input_tokens": 50_000,
                    "cache_creation_input_tokens": 10_000,
                    "output_tokens": 500,
                },
            },
        },
        1,
    )
    over = extract_claude_message_snapshot(
        {
            "timestamp": "t2",
            "message": {
                "id": "m2",
                "model": "claude-opus-4-6",
                "usage": {
                    "input_tokens": 1000,
                    "cache_read_input_tokens": 250_000,
                    "cache_creation_input_tokens": 50_000,
                    "output_tokens": 2000,
                },
            },
        },
        2,
    )
    assert under is not None
    assert over is not None
    deduped = reduce_message_snapshots((under, over))
    costs, premium = compute_claude_costs(deduped)

    # m1 (60,100 total input — standard): $0.1005
    # m2 (301,000 total input — long context): $0.96
    assert costs["session_total_cost_usd"] == pytest.approx(1.0605)

    # Premium = long_context_cost - standard_cost for m2 = $0.96 - $0.4925
    assert premium == pytest.approx(0.4675)
```

- [ ] **Step 2: Run test to verify it fails**

Run: `uv run --project token_auditor --group dev pytest token_auditor/tests/test_claude_core.py::test_compute_claude_costs_applies_long_context_for_messages_over_200k -v`
Expected: FAIL — `compute_claude_costs()` has wrong signature (expects 3 args)

- [ ] **Step 3: Write the failing test for mixed model + long context**

```python
def test_compute_claude_costs_mixed_model_with_long_context() -> None:
    """Opus over 200K + Haiku under 200K — both model resolution and threshold detection."""
    opus = extract_claude_message_snapshot(
        {
            "timestamp": "t1",
            "message": {
                "id": "o1",
                "model": "claude-opus-4-6",
                "usage": {
                    "input_tokens": 500,
                    "cache_read_input_tokens": 200_000,
                    "cache_creation_input_tokens": 100_000,
                    "output_tokens": 1000,
                },
            },
        },
        1,
    )
    haiku = extract_claude_message_snapshot(
        {
            "timestamp": "t2",
            "message": {
                "id": "h1",
                "model": "claude-haiku-4-5",
                "usage": {
                    "input_tokens": 100,
                    "cache_read_input_tokens": 40_000,
                    "cache_creation_input_tokens": 10_000,
                    "output_tokens": 500,
                },
            },
        },
        2,
    )
    assert opus is not None
    assert haiku is not None
    deduped = reduce_message_snapshots((opus, haiku))
    costs, premium = compute_claude_costs(deduped)

    # Opus (300,500 input — long context): $1.4925
    # Haiku (50,100 input — standard, no long context tier): $0.0191
    assert costs["session_total_cost_usd"] == pytest.approx(1.5116)

    # Premium = opus_lc - opus_std = $1.4925 - $0.7525
    assert premium == pytest.approx(0.74)
```

- [ ] **Step 4: Write the regression test for single-model under 200K**

```python
def test_compute_claude_costs_single_model_matches_per_message_sum() -> None:
    """Per-message path produces same result as old aggregate path for under-200K sessions."""
    m1 = extract_claude_message_snapshot(
        {
            "timestamp": "t1",
            "message": {
                "id": "m1",
                "model": "claude-sonnet-4-6",
                "usage": {
                    "input_tokens": 20,
                    "cache_read_input_tokens": 4,
                    "cache_creation_input_tokens": 6,
                    "output_tokens": 8,
                },
            },
        },
        1,
    )
    m2 = extract_claude_message_snapshot(
        {
            "timestamp": "t2",
            "message": {
                "id": "m2",
                "model": "claude-sonnet-4-6",
                "usage": {
                    "input_tokens": 5,
                    "cache_read_input_tokens": 0,
                    "cache_creation_input_tokens": 0,
                    "output_tokens": 2,
                },
            },
        },
        2,
    )
    assert m1 is not None
    assert m2 is not None
    deduped = reduce_message_snapshots((m1, m2))
    costs, premium = compute_claude_costs(deduped)

    # Same expected value as test_parse_claude_events_deduplicates_and_prices_single_model_sessions
    assert costs["session_total_cost_usd"] == pytest.approx(0.0002487)
    assert premium == pytest.approx(0.0)
```

- [ ] **Step 5: Implement the rewritten `compute_claude_costs()`**

In `token_auditor/src/token_auditor/core/claude.py`:

1. Add `LONG_CONTEXT_INPUT_THRESHOLD` to imports (line 1 area — add to a new import from constants):

```python
from token_auditor.core.constants import LONG_CONTEXT_INPUT_THRESHOLD
```

2. Replace `compute_claude_costs()` (lines 85-118) with:

```python
def compute_claude_costs(
    deduped_snapshots: Mapping[str, ClaudeMessageSnapshot],
) -> tuple[CostBreakdown, float]:
    """Compute Claude costs per-message with long context threshold detection."""
    accumulated = zero_costs()
    long_context_premium = 0.0

    for snapshot in deduped_snapshots.values():
        message_pricing_model = resolve_pricing_model("claude", snapshot.model)
        total_input = (
            snapshot.usage.input_tokens
            + snapshot.usage.cached_input_tokens
            + snapshot.usage.cache_creation_input_tokens
        )
        is_long_context = total_input > LONG_CONTEXT_INPUT_THRESHOLD

        message_costs = calculate_costs(
            provider="claude",
            pricing_model=message_pricing_model,
            reasoning_effort="",
            input_tokens=snapshot.usage.input_tokens,
            cached_input_tokens=snapshot.usage.cached_input_tokens,
            cache_creation_input_tokens=snapshot.usage.cache_creation_input_tokens,
            output_tokens=snapshot.usage.output_tokens,
            reasoning_output_tokens=0,
            long_context=is_long_context,
        )
        for key, value in message_costs.items():
            accumulated[key] += value

        if is_long_context:
            standard_costs = calculate_costs(
                provider="claude",
                pricing_model=message_pricing_model,
                reasoning_effort="",
                input_tokens=snapshot.usage.input_tokens,
                cached_input_tokens=snapshot.usage.cached_input_tokens,
                cache_creation_input_tokens=snapshot.usage.cache_creation_input_tokens,
                output_tokens=snapshot.usage.output_tokens,
                reasoning_output_tokens=0,
                long_context=False,
            )
            long_context_premium += message_costs["session_total_cost_usd"] - standard_costs["session_total_cost_usd"]

    return accumulated, long_context_premium
```

3. Update `finalize_claude_audit()` (lines 121-149). Change the call site and add the new field:

Replace:
```python
    costs = compute_claude_costs(deduped_snapshots, aggregate, pricing_model)
```

With:
```python
    costs, long_context_premium = compute_claude_costs(deduped_snapshots)
```

And in the return dict, add after `**costs,`:
```python
        "long_context_premium_usd": long_context_premium,
```

4. Remove the now-unused `CostBreakdown` from the imports on line 8 if the type is no longer referenced directly (it's still used via `zero_costs()` return type, but check). Actually, `CostBreakdown` is still used in the return type annotation of `compute_claude_costs`, so keep it.

- [ ] **Step 6: Run the new claude core tests**

Run: `uv run --project token_auditor --group dev pytest token_auditor/tests/test_claude_core.py -v`
Expected: New tests PASS. Some existing tests may fail because they don't assert `long_context_premium_usd` yet (but they should still pass since we're only adding a field).

- [ ] **Step 7: Update existing tests to assert new field**

In `test_parse_claude_events_deduplicates_and_prices_single_model_sessions` (line 160), add after the `session_total_cost_usd` assertion:

```python
    assert usage["long_context_premium_usd"] == 0.0
```

In `test_parse_claude_events_prices_mixed_models_per_message` (line 201), add after the `session_total_cost_usd` assertion:

```python
    assert usage["long_context_premium_usd"] == 0.0
```

- [ ] **Step 8: Write the end-to-end test for premium in audit record**

Append to `token_auditor/tests/test_claude_core.py`:

```python
def test_parse_claude_events_includes_long_context_premium_field() -> None:
    usage = parse_claude_events(
        (
            {
                "sessionId": "lc-session",
                "timestamp": "2026-03-11T10:00:00Z",
                "message": {
                    "id": "lc1",
                    "model": "claude-opus-4-6",
                    "usage": {
                        "input_tokens": 100,
                        "cache_read_input_tokens": 250_000,
                        "cache_creation_input_tokens": 0,
                        "output_tokens": 500,
                    },
                },
            },
        ),
        Path("/tmp/claude-long-context.jsonl"),
    )

    assert usage is not None
    # 250,100 total input > 200K threshold
    # Long context Opus: input=100*10/M=0.001, cached=250000*1.0/M=0.25, output=500*37.5/M=0.01875
    assert usage["session_total_cost_usd"] == pytest.approx(0.26975)
    # Standard would be: input=0.0005, cached=0.125, output=0.0125 = 0.138
    assert usage["long_context_premium_usd"] == pytest.approx(0.13175)
```

- [ ] **Step 9: Run full test suite**

Run: `uv run --project token_auditor --group dev pytest token_auditor/tests -v`
Expected: All tests PASS

- [ ] **Step 10: Run lint**

Run: `uv run --project token_auditor --group dev ruff check token_auditor/src token_auditor/tests && uv run --project token_auditor --group dev ruff format --check token_auditor/src token_auditor/tests`
Expected: PASS

- [ ] **Step 11: Commit**

```bash
git add token_auditor/src/token_auditor/core/claude.py token_auditor/tests/test_claude_core.py
git commit -m "feat(token-auditor): per-message cost computation with long context threshold detection"
```

---

## Chunk 3: Render and Final Verification

### Task 4: Add conditional "Long Context Premium" row to render output

**Files:**
- Modify: `token_auditor/src/token_auditor/core/render.py:60-75`
- Test: `token_auditor/tests/test_render.py`

- [ ] **Step 1: Write the failing test for premium row when nonzero**

Append to `token_auditor/tests/test_render.py`:

```python
def test_format_cost_rows_includes_long_context_premium_when_nonzero() -> None:
    audit = {**AUDIT, "long_context_premium_usd": 0.13175}
    rows = format_cost_rows(audit)
    labels = [r[0] for r in rows]
    assert "Long Ctx Premium" in labels
    total_idx = labels.index("Total Cost")
    premium_idx = labels.index("Long Ctx Premium")
    assert premium_idx < total_idx
```

- [ ] **Step 2: Run test to verify it fails**

Run: `uv run --project token_auditor --group dev pytest token_auditor/tests/test_render.py::test_format_cost_rows_includes_long_context_premium_when_nonzero -v`
Expected: FAIL — "Long Ctx Premium" not in labels

- [ ] **Step 3: Write the failing test for premium row omitted when zero**

Append to `token_auditor/tests/test_render.py`:

```python
def test_format_cost_rows_omits_long_context_premium_when_zero() -> None:
    audit = {**AUDIT, "long_context_premium_usd": 0.0}
    rows = format_cost_rows(audit)
    labels = [r[0] for r in rows]
    assert "Long Ctx Premium" not in labels
```

- [ ] **Step 4: Implement the conditional row in `format_cost_rows()`**

In `token_auditor/src/token_auditor/core/render.py`, replace the `format_cost_rows()` function (lines 60-75) with:

```python
def format_cost_rows(audit: AuditRecord) -> tuple[tuple[str, str], ...]:
    """Build USD cost rows formatted for human-readable text output."""
    rows = [
        ("Input Cost", format_usd(float(audit["input_cost_usd"]))),
        ("Cached Input", format_usd(float(audit["cached_input_cost_usd"]))),
        ("Cache Creation", format_usd(float(audit["cache_creation_input_cost_usd"]))),
        ("Output Cost", format_usd(float(audit["output_cost_usd"]))),
        ("Reasoning Output", format_usd(float(audit["reasoning_output_cost_usd"]))),
    ]
    long_context_premium = float(audit.get("long_context_premium_usd", 0.0))
    if long_context_premium > 0:
        rows.append(("Long Ctx Premium", format_usd(long_context_premium)))
    rows.append(("Total Cost", format_usd(float(audit["session_total_cost_usd"]))))
    provider_billed_unit = str(audit.get("provider_billed_unit", ""))
    if provider_billed_unit:
        provider_billed_total = float(audit.get("provider_billed_total", 0.0))
        billed_value = format_usd(provider_billed_total) if provider_billed_unit == "usd" else f"{provider_billed_total:g} {provider_billed_unit}"
        rows.append(("Provider Billed", billed_value))
    return tuple(rows)
```

- [ ] **Step 5: Run render tests**

Run: `uv run --project token_auditor --group dev pytest token_auditor/tests/test_render.py -v`
Expected: All tests PASS (existing + 2 new)

- [ ] **Step 6: Run full test suite**

Run: `uv run --project token_auditor --group dev pytest token_auditor/tests -v`
Expected: All tests PASS

- [ ] **Step 7: Run lint**

Run: `uv run --project token_auditor --group dev ruff check token_auditor/src token_auditor/tests && uv run --project token_auditor --group dev ruff format --check token_auditor/src token_auditor/tests`
Expected: PASS

- [ ] **Step 8: Commit**

```bash
git add token_auditor/src/token_auditor/core/render.py token_auditor/tests/test_render.py
git commit -m "feat(token-auditor): show long context premium in text output when nonzero"
```

---

### Task 5: Final verification

- [ ] **Step 1: Run full test suite with coverage**

Run: `uv run --project token_auditor --group dev pytest token_auditor/tests -v`
Expected: All tests PASS, coverage ≥ 100% (enforced by pyproject.toml `addopts = "--cov=token_auditor --cov-fail-under=100"`, applied automatically)

- [ ] **Step 2: Run lint and format check**

Run: `uv run --project token_auditor --group dev ruff check token_auditor/src token_auditor/tests && uv run --project token_auditor --group dev ruff format --check token_auditor/src token_auditor/tests`
Expected: PASS

- [ ] **Step 3: Verify all 5 issues are addressed**

Manual checklist:
- Issue #1 (Long context pricing): `LONG_CONTEXT_PRICING_USD_PER_1M` table in constants, `long_context` param in `calculate_costs()`
- Issue #2 (Per-message computation): `compute_claude_costs()` always iterates per-message, checks 200K threshold
- Issue #3 (Cache TTL): `CACHE_WRITE_1HR_MULTIPLIER` constant with explanatory comment
- Issue #4 (Fast mode): `FAST_MODE_PRICING_USD_PER_1M` table with explanatory comment
- Issue #5 (Data residency): `DATA_RESIDENCY_MULTIPLIER` constant with explanatory comment
