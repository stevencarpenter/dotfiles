# Hippo Effectiveness Study: 8-bit vs 4-bit Enrichment

**Question:** since hippo moved from `Qwen3.6-35B-A3B-Uncensored-Heretic-MLX-8bit` to
`Qwen3.6-35B-A3B-Abliterated-Heretic-MLX-4bit` (about 2026-10-28), is hippo materially worse at
its job? It feels faster and no difference has been noticed, but nothing has measured it.

**Status:** Phase 0 is built (`just hippo-study-probe`). Phases 1 to 3 are proposed and not built.

## What "effectiveness" means here

A quantized model can degrade one layer while the others look fine, so each is measured
separately.

| Layer | Question | Strength of signal |
|---|---|---|
| Enrichment | Are knowledge nodes as accurate and complete as 8-bit's? | Strong |
| Retrieval | Do real queries still surface the right nodes? (Embeddings did not change, so any shift comes from node text or 4-bit query rewriting.) | Strong |
| Downstream | Does Claude use what hippo returns? | Weak, sanity check only |

## Phases

| Phase | What | Your time | Decides |
|---|---|---|---|
| 0. Probe (built) | Read-only scan of `hippo.db`: model provenance, retained inputs, whether hippo responses are stored, row counts per era | 1 command | Which later phases are possible |
| 1. Era report | Compare nodes before and after the cutover: failure and retry rates, latency, repetition, **grounding** | None | Cheap red flag; cannot clear 4-bit alone |
| 2. Controlled A/B | Re-enrich ~200 recent inputs with both models; blind pairwise judge plus grounding | ~30 min grading; one run with both models loaded | The quality answer |
| 3. Retrieval replay | Replay real `mcp__hippo__*` queries against an 8-bit-built and a 4-bit-built shadow index; judge top-5 relevance | None | Whether it matters in use |

Phase 4 (downstream signals in Claude transcripts) is optional. Claude Code prunes transcripts to
about two weeks (see [hippo usage measurement](./hippo-usage-measurement.md)), so the 8-bit era is
likely gone from them.

### Grounding: the main objective metric

Extract concrete identifiers from each enrichment (file paths, commands, repo and branch names,
error strings) and check each appears in the source input. Identifiers that do not appear are
fabricated. This is where lower-precision quants tend to slip first, and it needs no judge.

### Why Phase 1 cannot clear 4-bit

Workload and hippo code both changed across the cutover (for example #249). Phase 1 can show a
problem; only Phase 2, with identical inputs, can show there is none.

## Decision rule (agree before running)

Keep 4-bit if all hold:

- Phase 2: 4-bit wins or ties at least 45% of blind pairs (n ~ 200 gives about +/-7 points).
- Fabricated-identifier rate no more than 2 points above 8-bit's.
- Phase 3: nDCG@5 within 0.03 of 8-bit's.
- Enrichment failure rate not higher.

If 4-bit fails only on grounding, try the matrix's `presence_penalty = 1.5` variant before
reverting to 8-bit.

## Judge and calibration

The judge is Claude via local `claude -p`, so no API key is needed. It sees the source plus two
shuffled enrichments, picks one or a tie, and flags anything unsupported by the source. You
grade the same ~30 pairs blind; if your verdicts and the judge's disagree often, the judge's
results are not used.

## Privacy

- The probe and Phase 1 run locally and read `hippo.db` read-only.
- The probe report contains schema names and counts, never row text, so it is safe to share.
- The Phase 2 and 3 judge sends source text to Anthropic. Grounding stays local.

## Run Phase 0

```bash
just hippo-study-probe            # writes ~/.local/share/hippo/model-eval/study/probe.md
just hippo-study-probe --cutover 2026-10-28T12:00:00-06:00   # if the switch was later
```

The default cutover is the 4-bit switch commit (`bcdf7da`, 2026-10-27 23:47 -06:00). The brain
applies a config change on restart, so pass the restart time if you know it was later.

The report opens with three answers that pick the path forward:

1. **Model provenance:** if no column records the model, eras come from the cutover time, and
   hippo should start recording the model going forward.
2. **Raw input retained:** if not, Phase 2 uses freshly recorded cases
   (`scripts/hippo-model-eval.py record --switch-brain`) instead of historical ones.
3. **Hippo responses stored:** if not, Phase 3 regenerates results by replay, which it does
   anyway, and Phase 4 is dropped.
