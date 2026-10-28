# Hippo Model Experiment

This runbook covers comparing hippo enrichment models, quantizations, temperatures and thinking
on/off on the same recorded requests. The run is unattended: start it in the morning and read the
report when you come back.

- `scripts/hippo-model-eval.py`: records real brain requests; single ad hoc comparisons.
- `scripts/hippo-model-experiment.py`: the unattended matrix run (`just hippo-experiment`).
- `scripts/hippo-model-experiment.toml`: the candidates. Edit it to add or drop models.

## Before the day of the run

1. **Get every model into oMLX** under the IDs the matrix names. `just hippo-experiment plan`
   lists anything oMLX does not serve. The 6-bit Heretic is optional and has no upload. Either
   convert it from the Heretic bf16, or start with `--skip-missing` to run without it:

   ```bash
   mlx_lm.convert --hf-path <heretic-bf16-source> -q --q-bits 6 --q-group-size 64 \
     --mlx-path <omlx-models-dir>/Qwen3.6-35B-A3B-Uncensored-Heretic-MLX-6bit
   ```

2. **Record cases** while you use the machine normally. The brain is pointed at a local proxy and
   restored (and restarted) however recording ends:

   ```bash
   scripts/hippo-model-eval.py record --switch-brain --limit 200
   scripts/hippo-model-eval.py inspect   # shows whether production runs with thinking on
   ```

   Recording edits `home/.config/hippo/config.toml` in the checkout while it runs. If the process
   is killed with `kill -9`, restore it with `git checkout home/.config/hippo/config.toml`.

3. **Check oMLX can hold two models at once.** The brain keeps enriching with the production model
   during the run. If oMLX keeps only one model loaded, each brain request evicts the candidate,
   and latency and power become meaningless. Raise oMLX's loaded-model limit (and memory cap) to
   hold the production model plus the largest candidate.

## Start (morning, about two minutes at the keyboard)

```bash
just hippo-experiment plan            # every line "ok"; prints calls and a rough duration
just hippo-experiment start --power   # asks for sudo once, then detaches
```

`start` fails while you are still there if a model is missing, cases are absent or oMLX is
down. `--skip-missing` runs without the missing models. `--power` starts one `powermetrics` for
the whole run and needs no further sudo.

The worker runs under `caffeinate -ims`, which keeps the Mac awake **only on AC power**. Leave it
plugged in. Closing the lid without an external display still sleeps it.

The shipped matrix is 14 variants x 150 cases = 2,100 calls, roughly 3 to 9 hours. Variants run
in rounds of 25 cases, so if the run is still going at 5pm, `stop` leaves a fair comparison of
every variant on the cases finished so far.

## During the day

```bash
just hippo-experiment status   # done/total, current variant, ETA
just hippo-experiment stop     # finishes the current call, writes the report
just hippo-experiment resume   # continues; finished cases are never re-run
```

A run started with `--power` asks for sudo again on `resume` and keeps sampling, so energy per
case stays comparable across the stop.

The worker survives oMLX restarts. On a dropped connection it waits up to 15 minutes, then
retries. A model that answers 404 is marked failed and the run continues without it.

## Reading the results

A macOS notification fires when the run ends. The run directory is
`~/.local/share/hippo/model-eval/runs/<timestamp>/`:

- `report.md` has one row per variant, sorted by agreement with production:
  - `json_valid` and `truncated` are pass/fail for enrichment.
  - `completion_tokens` and `reasoning_chars` show what thinking costs.
  - `p50_s` is latency per case.
  - `watts` and `joules_per_case` show the fan and battery cost.
- `blind.md` holds 12 cases with production's output plus every variant's, shuffled and lettered.
  Judge quality there before opening `blind-key.json`.
- `summary.json` holds the same table as data. `results/*.jsonl` holds every output.

Agreement measures closeness to the current setup, not correctness. A variant can disagree because
it is better. Use the blind sample for quality, then pick the cheapest variant whose outputs you
would accept.

Latency and power include your workday and live hippo traffic. Compare variants within one run,
not across runs.
