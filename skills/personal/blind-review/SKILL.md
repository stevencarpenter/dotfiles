---
name: blind-review
description: "Experimental paired code review with comments and docstrings removed from one pass. Use for a requested blind review, comment-versus-code check, or paired review experiment."
---

# Blind Review (PoC)

**Status: proof of concept.** This skill tests whether comments and docstrings
bias LLM reviewers. The paired output and JSONL log compare reviews with and
without that context. State in the report that findings are experimental.

## Modes

- **Primary** (default): run both passes, present the merged report.
- **Sidecar** (when the user asks to collect paired data alongside another
  review): run both passes read-only, log the pair record,
  and give only a one-line summary: do not editorialize on the primary
  task's review.

## Workflow

### 1. Determine the target

Default: the working diff against `HEAD` (in jj-colocated repos `git diff`
still reads fine: this flow never mutates the repo). The user may name a
base ref, branch, or PR instead; resolve PRs to a local ref first.

### 2. Strip

```bash
<this-skill-dir>/scripts/strip_context.py diff \
  --repo <repo> --base <ref> --out <scratchpad>/blind-review-<short-id>
```

The out dir MUST be outside the reviewed repo, such as in the session scratchpad.
Strip output inside the worktree shows up as untracked files in
the context pass, revealing the experiment and contaminating the control
arm. This writes `base/`, `head/`, `stripped.diff`, and `manifest.json`
into the out dir. Line and column numbers are preserved (comments become spaces,
docstrings become `""`), so stripped findings cite real source locations.
Check `manifest.json`: files marked `copied-verbatim` were NOT stripped
(unknown language or parse error): tell the blind reviewer to skip them
and disclose the gap in the report.

### 3. Run both passes in parallel: one message, two agents

**Blind pass**: spawn the `blind-reviewer` agent (fall back to a
general-purpose read-only agent carrying the same brief if unregistered).
Start a fresh agent without inherited conversation or repository instructions.
Give it ONLY the out dir: review `head/` with `stripped.diff` as the
change under review. Never mention the original repo path, repo name, or
branch: the isolation is the experiment. It cannot be hard-sandboxed, so
the prompt must not leak paths it could follow back.

**Context pass**: use the superpowers
requesting-code-review flow or /code-review conventions, or a
language-appropriate reviewer agent on the real repo with full context.
Do not tell the context reviewer about the blind pass, and confirm its
prompt and environment carry zero trace of the experiment (no strip
output, no scratch paths, no experiment vocabulary). Give BOTH arms the
identical review-priority checklist: if only the blind arm gets a
structured checklist, any blind-arm lift may just be "checklist beats
freeform review", not de-biasing.

Keep both passes on the same model and effort: mismatched arms confound the
comparison. Verify candidate findings against the original source before reporting them.

### 4. Merge into four buckets

- **[both]**: found by both passes; still requires source verification.
- **[blind-only]**: found only by the blind pass. Verify whether the difference
  comes from misleading comments or a false positive in step 5.
- **[context-only]**: findings that required docs/comments/repo context.
- **[divergence]**: produced by step 5.

Match findings across passes by file:line proximity and described failure
mode, not exact wording.

### 5. Divergence pass

For each [blind-only] finding and each finding the blind pass tagged
`assumption:`, read the ORIGINAL file at those lines and compare the
comments/docstrings against the blind description of what the code does.
A comment that contradicts executable behavior is a **[divergence]** finding.
Examples include "validated above" with no validation or "cannot overflow"
with an unchecked add. A single pair does not establish why one reviewer missed it.

### 6. Log the pair record (both modes, including sidecar)

```bash
<this-skill-dir>/scripts/log_pair.py <record.json>
```

Record shape (append-only JSONL at `~/.local/share/blind-review/pairs.jsonl`):

```json
{
  "run_id": "<id>", "repetition_index": 0,
  "repo": "<name>", "base": "<ref>", "target": "<diff|files>",
  "diff_hash": "<sha256 of the reviewed diff>",
  "strip_manifest_ref": "<path: exclude copied-verbatim files from analysis>",
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
analyzable (detection rates, paired 2×2) instead of descriptive: omit
them only for non-synthetic runs with no ground truth. When grading
against ground truth, blind the grader: normalize findings (strip
provenance tags like `assumption:`, arm-specific formatting tells),
shuffle across arms, grade against the trap key, and only then rejoin the
arm mapping. An unblinded grader credits the arm it expects to win.

### 7. Report

Severity-ordered, provenance-tagged findings; state the PoC caveat; name
any files the stripper could not process. In sidecar mode: one line
("blind-review sidecar: N blind-only, M divergence: logged").

## Known PoC limitations (disclose when relevant)

- Identifier names still bias the blind pass (`sanitize_input` suggests
  its purpose).
- Lexer edge cases: Rust raw strings (`r#"..."#`) and other exotic
  literals may still strip imperfectly. Every strip is checked afterward
  against a space-mask contract (same length, same line count, only
  blanking) and, for Python, against `compile()`; anything that fails
  degrades to `copied-verbatim (strip validation failed: …)` in
  `manifest.json` rather than reaching the blind arm mangled. The check
  catches deletions and rewrites, not a comment that leaks through
  unstripped, so still skim `manifest.json` on exotic code.
- Only known languages are stripped (see the suffix tables and
  `HASH_STEMS` in `strip_context.py`). Anything else is flagged
  `copied-verbatim (unknown language)`, which means its comments reach
  the blind arm: check the manifest before trusting a run whose diff is
  mostly unsupported files.
- Blind isolation is prompt-level, not sandbox-level.
- Scope bundling: the context arm has comments AND repo-wide tools
  (grep, history, other files), so blind-vs-context differences measure
  "does more information of any kind help", not purely comment bias. The
  clean causal claim needs a third arm (full files, no comments, no
  repo-wide tools): not built yet; don't overclaim.
- Diff-length asymmetry: stripped files are shorter; less to read is its
  own advantage independent of de-biasing.
- The merge pass does free-text matching of findings across arms:
  mismatches inflate [blind-only]/[context-only]. Hand-check its matches
  on early runs.
- Single runs are noise: model nondeterminism means a finding appearing
  in one arm once is weak evidence. For measurement use ≥3 repetitions
  per arm and analyze as paired binary outcomes per trap.
