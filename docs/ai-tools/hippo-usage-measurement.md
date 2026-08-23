# Hippo Usage Measurement

On 2026-08-23 the global agent instructions (`home/.claude/CLAUDE.md` and `home/.codex/AGENTS.md`)
gained a rule requiring a `mcp__hippo__*` recall check after every new idea. This document records
the baseline taken that day, the scheduled re-measures, and the data-source constraints that make
the numbers comparable.

## Scheduled re-measures

| Date | Purpose | Command |
| --- | --- | --- |
| 2026-08-30 | One week after the change | `bash ~/.local/share/hippo/metrics/hippo_usage_baseline.sh --as-of 2026-08-31 --snapshot` |
| 2026-09-23 | One month after the change | `bash ~/.local/share/hippo/metrics/hippo_usage_baseline.sh --as-of 2026-09-24 --snapshot` |

`--as-of` is an exclusive upper bound. Set it to the day after the last full day to count.
`--snapshot` writes `baseline-<as-of>.txt` beside the script, so a comparison is a diff of two
snapshot files. The baseline is `baseline-2026-08-24.txt`.

The one-week reading will not be conclusive. At 28 calls and 8 sessions per 30 days, and a
denominator that swings between 6,724 and 32,244 tool calls per week for unrelated reasons,
week-over-week movement is dominated by noise. The one-month reading is the meaningful comparison.

## Baseline values (2026-08-23)

Excluding the subagent that produced the baseline:

- 30-day: 28 hippo calls against 86,036 tool calls, 0.325 per 1,000.
- 90-day: 81 against 225,915, 0.359 per 1,000.
- The clean rate is flat between 0.33 and 0.36 across every window, so that band is the number to
  beat.
- Session penetration: 8 of 2,438 claude-code sessions in 30 days, 0.33 percent.
- All-time 178 hippo calls, every one from claude-code. Codex is exactly 0 across 28,941 tool calls
  despite `[mcp_servers.hippo]` being present in its config.
- `mcp__hippo__get_context` and `mcp__hippo__query_memory_history` have never been called.

## Instruments

Both live in `~/.local/share/hippo/metrics/`, which is runtime data and is not managed by Nix.

- `hippo_usage_baseline.sh` is the primary instrument. It reads hippo's own
  `agentic_sessions.tool_calls_json` and opens the database with `sqlite3 -readonly`.
- `exclusions.txt` holds session ids whose hippo calls are measurement artifacts rather than real
  usage. Query Q5 in the script surfaces candidates on every run.
- `hippo_usage_metrics.py` is a secondary cross-check that counts `"name":"mcp__hippo__*"` in raw
  Claude and Codex transcripts. It is retention-limited (see below) and should not be used as the
  headline source.

## Exclusion rule

Exclude a session only when it exists to measure hippo. Never exclude a session that used hippo to
answer a real question. The 2026-08-14 session that produced 18 calls was recalling a skill idea the
user had forgotten, which is the intended use, so it stays counted. The 2026-08-23 subagent
`agent-a4dc6d7efe4f24483` existed only to build this baseline, so it is excluded.

## Data-source constraints

These took real work to establish and should not be re-derived.

- Use `agentic_sessions.tool_calls_json`. Do not use the `events` table: it is a partial capture
  holding 12 hippo calls all-time against 178 in `tool_calls_json`.
- `tool_calls_json` was validated lossless against a raw Claude transcript (135 calls, per-tool
  counts identical). Session segments have disjoint time ranges, so summing across them is correct.
- Timestamps in `agentic_sessions` are integer unix epoch **milliseconds**, not seconds and not ISO
  text. Convert with `datetime(start_time/1000,'unixepoch','localtime')`.
- Cursor collapses every MCP call to the tool name `CallMcpTool`, so cursor hippo usage cannot be
  attributed to a specific tool. Opencode records no tool calls at all. Both are invisible to this
  metric.
- Hippo's database is a better source than raw transcripts because it retains 252,988 claude-code
  tool calls back to 2026-03-12, while Claude Code prunes transcripts to roughly two dense weeks
  (25,025 calls). An all-time count from transcripts silently changes meaning between runs.
- The hippo-repo confounder is absent. Excluding `cwd LIKE '%hippo%'` slightly raises the
  penetration percentage, because hippo calls happen mostly outside the hippo repo.

## What the metric cannot show

The denominator is total tool calls, which is a proxy. The real target, how many new ideas occurred,
is not recorded anywhere. A hippo call the model chose to make cannot be distinguished from one a
skill or agent definition forced; `is_subagent` is the only available lever and it is coarse. Calls
carry no per-call timestamp and are bucketed by their segment's start time, which is negligible at
weekly granularity but fuzzy at day boundaries.
