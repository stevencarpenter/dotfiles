# Hippo MCP Relevance Evaluation — 2026-05-30

A controlled evaluation of how useful the **hippo** knowledge-base MCP server is as a
source of truth about *working on this dotfiles repo*, run as a side-experiment to the
"top-4 skills" analysis.

## Why this log exists

The skill-mining task was instructed to use hippo **only** as an auxiliary source whose
*usefulness itself* is under test — **not** as an input to the skill recommendations.
This log records every hippo MCP call made, what it returned, and a relevance score
graded against an **independently derived answer key**.

### Firewall (how contamination was avoided)

- The skill recommendations are derived from a separate, **hippo-blind** expert-panel
  workflow that read only the distilled Claude/Codex/OpenCode session corpora. No hippo
  output was passed to any panel agent.
- The "answer key" for scoring hippo is the ground-truth theme set derived *first* from
  the raw session corpora (138 Claude human turns + 117 error results, 112 Codex turns,
  12 OpenCode turns). Hippo was queried *after* the answer key existed, so it is a
  **blind-graded subject**, never an input.

### Relevance rubric (0–5)

| Score | Meaning |
|------:|---------|
| 5 | Directly surfaces a confirmed ground-truth theme with specific, actionable detail |
| 4 | Surfaces a real theme, mostly actionable; minor noise or generic phrasing |
| 3 | Adjacent/partial — real signal but needs work to use |
| 2 | Degraded/tangential — retrieval ran but output unusable, or mostly noise |
| 1 | Near-miss / empty despite known data existing |
| 0 | Empty / error / irrelevant |

Ground-truth themes (the answer key): **(T1)** git branch/commit/PR discipline,
**(T2)** PR review-response loop (Codex/Copilot bots + CI), **(T3)** Python uv-tool
dev loop (uv/ruff/ty/pytest/coverage, pyright venv), **(T4)** secrets / age-encryption,
**(T5)** sandbox friction (gh + git-config writes need `dangerouslyDisableSandbox`),
**(T6)** work/personal machine templating + capability gating.

## Usage log (every hippo MCP call, in order)

| # | Tool | Args (key) | Scope | Result summary | Theme | Score |
|--:|------|-----------|-------|----------------|:-----:|:-----:|
| 1 | `list_projects` | limit=50 | — | Correctly identified `stevencarpenter/dotfiles` ↔ `/Users/.../chezmoi` with a usable scoping handle. Also ~20 path-mangled duplicate `cwd_root` entries (`-Users-carpenter--local-share-chezmoi`, bare `chezmoi`) and ingested workflow runs (`wf_…`) as "projects" = noise. Captured *this very evaluation's* workflow run in real time. | discovery | **4** |
| 2 | `get_lessons` | repo=`stevencarpenter/dotfiles` | — | **One** lesson: `{path_prefix:".github", summary:": in .github", occurrences:18, fix_hint:null}`. Malformed/empty summary, no actionable fix. Weakly gestures at recurring CI/.github churn but is non-actionable. | (T2) | **1** |
| 3 | `search_hybrid` | "git branch commit PR review workflow…" | project=chezmoi | 8 on-repo hits: one-branch-one-PR consolidation, PR reconciliation, applying review feedback to `workflows` branch (with rich `design_decisions`: reviewer cited wrong path; `--init` drops `.chezmoidata`), `gmfp` branch-after-refresh shell fn, commit-message generation. | T1 | **5** |
| 4 | `search_knowledge` | "age encrypt secret leak…" (semantic) | project=chezmoi | **Empty `[]`.** Flagged as a *mode artifact*, not absence of data (see #5). Not used to penalize T4. | T4 | **0\*** |
| 5 | `search_hybrid` | "age encrypt secret 1password encrypted_dot_env plaintext leak" | project=chezmoi | 8 dead-on hits: `private_`→`encrypted_` SSH refactor (matches the real "make ssh config encrypted not private" turn) w/ `design_decisions` incl. sandbox-stdin workaround; P1 finding that pre-commit lacks gitleaks/detect-secrets; the **`admin:<redacted>` Grafana creds leak** (exact match to a real human turn); `chezmoi edit-encrypted` vs `edit`. | T4 | **5** |
| 6 | `search_hybrid` | "sandbox operation not permitted gh dangerouslyDisableSandbox git config OSStatus" | project=chezmoi | 8 hits: pre-commit `PermissionError [Errno 1] Operation not permitted /Users/.../.cache/pre-commit/`; PR #67/#64 review using `gh … dangerouslyDisableSandbox`; repeated `ca`/`gcamp`/commit exit-1 failures. Some generic apply-failure noise. | T5 | **4.5** |
| 7 | `search_hybrid` | "uv run pytest ruff ty coverage … token_auditor pyright venv claade" | project=chezmoi | 8 bullseyes: `pyrightconfig.json` multi-project venv resolution (matches the real pyright-venv turns) w/ `design_decisions`; the `_run_with_token_audit`→`_with_project_venv` refactor (exact match to a real turn); coverage gates (`token_auditor 71/71 @ 100% cov`); reveals canonical uv flag evolved `--extra dev`→`--group dev` (PEP 735). | T3 | **5** |
| 8 | `search_hybrid` | "work personal machine capability gating templating tmpl machines.toml" | project=chezmoi | 8 bullseyes: prefix→capability migrations (copilot trusted_folders, mise infra, aws_sso gate), `$personal` conditional plugins, multi-machine isolation design (matches the OpenCode "separating work/personal" turns), capability audit. Note: much of this is the *audit/migrate* side already owned by `machine-capability-audit`. | T6 | **5** |
| 9 | `ask` | "What recurring problems/procedures…skill could capture?" | project=chezmoi | **Degraded.** Local inference LLM (`Qwen3.6-35B` @ `localhost:8000`) threw `RemoteProtocolError` (peer closed connection). Retrieval found 12 relevant sources; **synthesis failed** — no prose answer. | all | **2** |
| 10 | `search_events` | "uv run pytest ruff coverage", source=shell | project=chezmoi | **Empty `[]`** despite abundant known pytest/ruff activity — query/source-filter sensitivity. | T3 | **1** |
| 11 | `search_events` | "chezmoi apply" | project=chezmoi | **Overflowed** (77 KB raw, unranked) — too much data, no relevance ranking, unusable without post-filtering. Confirms the events surface *has* data but is hard to target. | — | **2** |

\* #4 superseded by #5; the empty semantic result is a query-mode artifact and was **not**
counted against hippo's coverage of T4.

## Per-surface aggregate

| Surface | Calls | Mean | Verdict |
|---------|:-----:|:----:|---------|
| `search_hybrid` | 5 | **4.9** | **Standout.** On-repo, specific, carries `design_decisions`. The reliable retriever. |
| `list_projects` | 1 | 4.0 | Good for discovery/scoping; some duplicate/`wf_` noise. |
| `get_lessons` | 1 | 1.0 | **Broken for this repo** — one malformed, non-actionable lesson. The surface that *should* be most useful for skill-mining is the weakest. |
| `ask` | 1 | 2.0 | Retrieval fine; **synthesis depends on a flaky local LLM** that failed. Prefer structured retrievers. |
| `search_events` | 2 | 1.5 | Data present but poorly targetable — empties on specific queries, floods on broad ones. |
| `search_knowledge` (semantic) | 1 | 0.0\* | Mode-sensitive miss; hybrid mode found the same data richly. |

## Meta-findings on hippo's usefulness

1. **Hybrid retrieval corroborates the ground truth almost perfectly.** Every major theme
   (T1, T3, T4, T5, T6) was independently confirmed by real captured sessions, several
   matching specific human turns *verbatim* (the SSH `encrypted_` refactor, the
   `admin:<redacted>` leak, the `_run_with_token_audit` refactor, the pyright-venv work). As a
   *corroborating cross-session memory*, hippo is genuinely useful here.
2. **Use `search_hybrid`, not `ask`/`search_knowledge`-semantic/`search_events`, for this
   kind of question.** The skill's own guidance ("prefer structured retrievers") is borne
   out: hybrid mode hits the embedded keyword soup that narrow semantic queries miss.
3. **`get_lessons` is the biggest disappointment.** It is the purpose-built "what mistakes
   recur" surface — exactly what skill-mining wants — yet it returned a single malformed
   lesson. The distilled-lessons pipeline is not producing usable output for this repo
   (likely enrichment/graduation gaps). If improved, it would be the highest-value surface.
4. **`ask` has an availability dependency** (local inference server) that failed mid-eval.
   Treat `ask` as best-effort; do not build workflows that depend on its synthesis.
5. **Knowledge nodes bundle multiple co-occurring themes** (one node spans secrets +
   sandbox + git-history-rewrite + "Strip Co-Authored-By"). This is signal, not noise: it
   reflects that these frictions genuinely co-occur — independent support for clustering
   them into skills.
6. **Data hygiene noise** in `list_projects`: path-mangled duplicates and `wf_*` workflow
   runs surface as distinct "projects."

## Did hippo influence the skill recommendations?

**No.** The four recommended skills are derived solely from the hippo-blind expert panel
over the raw session corpora. Hippo's role here was strictly as the graded subject of this
evaluation. Where hippo's hybrid-search results *happen to corroborate* the panel's themes,
that is reported as evidence of hippo's usefulness — not used as a reason for any
recommendation.
