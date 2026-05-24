---
name: claude-cost
description: Estimate AI coding-agent spend from local session logs — both Claude Code (Anthropic) and Codex (OpenAI) — broken down by provider and model with cache-aware pricing. Use when the user asks how much they've spent, their Claude/Codex/Anthropic/OpenAI API cost or token spend, a cost roundup, or burn rate over a day, week, month, or year.
---

# Claude Cost

Estimates what your AI coding-agent token usage **would cost at pay-as-you-go API rates**, from local logs: Claude Code (`~/.claude/projects`) and Codex (`~/.codex/sessions`). The result is an API-rate *equivalent*, **not an invoice** — a Max/Pro or ChatGPT subscription is a flat fee, not per-token.

## Quick start

```bash
python3 "$SKILL_DIR/scripts/cost.py"                 # current month, both providers
python3 "$SKILL_DIR/scripts/cost.py" day             # today
python3 "$SKILL_DIR/scripts/cost.py" week            # current ISO week
python3 "$SKILL_DIR/scripts/cost.py" year            # year to date
```

Pick a provider, an explicit period, a trailing window, or JSON:

```bash
python3 "$SKILL_DIR/scripts/cost.py" month --provider claude    # Claude Code only
python3 "$SKILL_DIR/scripts/cost.py" month --provider codex     # Codex only
python3 "$SKILL_DIR/scripts/cost.py" month 2026-04              # a specific month
python3 "$SKILL_DIR/scripts/cost.py" week 2026-W20             # a specific ISO week
python3 "$SKILL_DIR/scripts/cost.py" month --trailing          # rolling last 30 days
python3 "$SKILL_DIR/scripts/cost.py" year --json               # JSON for piping
```

Options: `--provider claude|codex|all` (default `all`), `--trailing` (1d/7d/30d/365d), `--utc` (default is system local tz), `--by-day`, `--dir PATH` (Claude logs), `--codex-dir PATH` (Codex base), `--rates FILE`, `--json`.

## What it reports

Per-provider sections (each model's token buckets, cost, and composition), a combined grand total, and a per-day (or per-month for `year`) breakdown across both providers.

## Methodology

Shared: window isolation by per-message/per-turn timestamp; system-local-tz bucketing (DST-correct via `zoneinfo`); unknown models warn rather than silently miscount.

**Claude Code (Anthropic):** global dedup by `message.id` (resumed/branched sessions replay lines; without dedup the total inflates ~2×), max-merging fields to recover final usage from partial-stream flushes. Cache-aware: input + output + cache read (0.1×) + 5m write (1.25×) + 1h write (2×). Applies `batch` (0.5×), `fast` (6×), `us-geo` (1.1×) modifiers when present.

**Codex (OpenAI):** scans `~/.codex/sessions` + `archived_sessions`, deduped by session UUID. Codex logs *cumulative* usage, so it sums per-turn `last_token_usage` (not `total_token_usage`) attributed by event timestamp — this also bills resumed/subagent threads correctly. Buckets: uncached input + cached input (discounted read; OpenAI has no cache-write cost or TTL) + output (reasoning tokens are already inside `output_tokens`). Applies the long-context (>272K input) tier where a model defines one.

## Updating prices

Rates are baked into `scripts/cost.py` (`ANTHROPIC_RATES`, `OPENAI_RATES`, `ANTH_CACHE`, `RATES_AS_OF`), matched by longest model-id prefix. Edit those constants when prices change, or override without touching code:

```bash
python3 "$SKILL_DIR/scripts/cost.py" month --rates my-rates.json
```

See `scripts/rates.example.json` for the override format (`anthropic` / `openai` / `_cache_multipliers`; entries merge over defaults). Verify against <https://platform.claude.com/docs/en/about-claude/pricing> and <https://developers.openai.com/api/docs/pricing> if `RATES_AS_OF` looks stale.
