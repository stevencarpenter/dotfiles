---
name: blind-review
description: "PoC/experimental. Paired code review that separates what code DOES from what its comments CLAIM: strip all comments/docstrings/docs from a diff, run a context-blind correctness+exploitation review on the bare code in parallel with the normal full-context review, then merge and surface comment/code divergence. Use when the user asks for a blind review, an unbiased/no-context review, a comment-vs-code check, to 'blind-review this diff/PR', or asks whether the comments are lying; also usable as a silent sidecar on other review tasks to collect paired findings data."
---

# Blind Review (PoC)

**Status: proof of concept.** This skill tests a hypothesis: comments and
docstrings bias LLM reviewers — a reviewer who reads "// bounds-checked
above" tends to believe it. A reviewer who cannot see the claim judges only
executable semantics. The paired output (and the JSONL pair log) exists to
measure whether that is true, not yet to be a polished tool. Say so in your
report: findings from this flow are experimental.

## Modes

- **Primary** (default): run both passes, present the merged report.
- **Sidecar** (when hitched onto another task, or the user says "collect
  blind-review data"): run both passes read-only, log the pair record,
  and give only a one-line summary — do not editorialize on the primary
  task's review.

## Workflow

### 1. Determine the target

Default: the working diff against `HEAD` (in jj-colocated repos `git diff`
still reads fine — this flow never mutates the repo). The user may name a
base ref, branch, or PR instead; resolve PRs to a local ref first.

### 2. Strip

```bash
python3 <this-skill-dir>/scripts/strip_context.py diff \
  --repo <repo> --base <ref> --out <scratchpad>/blind-review-<short-id>
```

The out dir MUST be outside the reviewed repo (the session scratchpad is
right) — strip output inside the worktree shows up as untracked files in
the context pass, revealing the experiment and contaminating the control
arm. This writes `base/`, `head/`, `stripped.diff`, and `manifest.json`
into the out dir. Line and column numbers are preserved (comments become spaces,
docstrings become `""`), so stripped findings cite real source locations.
Check `manifest.json`: files marked `copied-verbatim` were NOT stripped
(unknown language or parse error) — tell the blind reviewer to skip them
and disclose the gap in the report.

### 3. Run both passes in parallel — one message, two agents

**Blind pass** — spawn the `blind-reviewer` agent (fall back to a
general-purpose read-only agent carrying the same brief if unregistered).
Give it ONLY the out dir: review `head/` with `stripped.diff` as the
change under review. Never mention the original repo path, repo name, or
branch — the isolation is the experiment. It cannot be hard-sandboxed, so
the prompt must not leak paths it could follow back.

**Context pass** — the status-quo control arm: use the superpowers
requesting-code-review flow or /code-review conventions, or a
language-appropriate reviewer agent on the real repo with full context.
Do not tell the context reviewer about the blind pass, and confirm its
prompt and environment carry zero trace of the experiment (no strip
output, no scratch paths, no experiment vocabulary). Give BOTH arms the
identical review-priority checklist — if only the blind arm gets a
structured checklist, any blind-arm lift may just be "checklist beats
freeform review", not de-biasing.

Model cap for both passes: Sonnet 5 at high effort. Merge and divergence
below are mechanical comparison — use Haiku / low effort.

### 4. Merge into four buckets

- **[both]** — found by both passes: highest confidence, lead with these.
- **[blind-only]** — candidates for "the comments talked the reviewer out
  of it" — or blind-pass noise. Do not discard; step 5 adjudicates.
- **[context-only]** — findings that required docs/comments/repo context.
- **[divergence]** — produced by step 5.

Match findings across passes by file:line proximity and described failure
mode, not exact wording.

### 5. Divergence pass (the payoff)

For each [blind-only] finding and each finding the blind pass tagged
`assumption:`, read the ORIGINAL file at those lines and compare the
comments/docstrings against the blind description of what the code does.
A comment that asserts what the code demonstrably does not do —
"validated above" with no validation, "cannot overflow" with an
unchecked add — is a **[divergence]** finding: usually the highest-value
output, and evidence the context pass was talked out of a real bug.

### 6. Log the pair record (both modes, including sidecar)

```bash
python3 <this-skill-dir>/scripts/log_pair.py <record.json>
```

Record shape (append-only JSONL at `~/.local/share/blind-review/pairs.jsonl`):

```json
{
  "run_id": "<id>", "repetition_index": 0,
  "repo": "<name>", "base": "<ref>", "target": "<diff|files>",
  "diff_hash": "<sha256 of the reviewed diff>",
  "strip_manifest_ref": "<path — exclude copied-verbatim files from analysis>",
  "models": {"blind": "...", "context": "..."},
  "cost": {"blind_tokens": 0, "context_tokens": 0},
  "traps": [{"id": "...", "file_line": "...", "category": "...",
             "description": "...", "proof": "<executable check ref>"}],
  "blind_findings": [{"file_line": "...", "claim": "...",
                      "matched_trap_id": null, "verdict": "hit|partial|miss"}],
  "context_findings": [...],
  "buckets": {"both": 0, "blind_only": 0, "context_only": 0, "divergence": 0},
  "grader_blinded": true,
  "notes": "<anything anomalous>"
}
```

`traps[]` + per-finding `matched_trap_id`/`verdict` are what make the log
analyzable (detection rates, paired 2×2) instead of descriptive — omit
them only for non-synthetic runs with no ground truth. When grading
against ground truth, blind the grader: normalize findings (strip
provenance tags like `assumption:`, arm-specific formatting tells),
shuffle across arms, grade against the trap key, and only then rejoin the
arm mapping. An unblinded grader credits the arm it expects to win.

### 7. Report

Severity-ordered, provenance-tagged findings; state the PoC caveat; name
any files the stripper could not process. In sidecar mode: one line
("blind-review sidecar: N blind-only, M divergence — logged").

## Known PoC limitations (disclose when relevant)

- Identifier names still bias the blind pass (`sanitize_input` suggests
  its purpose); anonymizing identifiers is the planned v2 knob.
- Lexer edge cases: Rust raw strings (`r#"..."#`), JS regex literals
  containing `//` or `/*`, and Python f-strings with nested quotes may
  strip imperfectly — such files fall back to `copied-verbatim` only on
  hard parse errors, so spot-check `manifest.json` on exotic code.
- Blind isolation is prompt-level, not sandbox-level.
- Scope bundling: the context arm has comments AND repo-wide tools
  (grep, history, other files), so blind-vs-context differences measure
  "does more information of any kind help", not purely comment bias. The
  clean causal claim needs a third arm (full files, no comments, no
  repo-wide tools) — not built yet; don't overclaim.
- Diff-length asymmetry: stripped files are shorter; less to read is its
  own advantage independent of de-biasing.
- The merge pass does free-text matching of findings across arms —
  mismatches inflate [blind-only]/[context-only]. Hand-check its matches
  on early runs.
- Single runs are noise: model nondeterminism means a finding appearing
  in one arm once is weak evidence. For measurement use ≥3 repetitions
  per arm and analyze as paired binary outcomes per trap.
