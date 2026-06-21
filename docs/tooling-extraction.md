# Extracting the vendored tools — shape, trade-offs, sequence

Decision aid for moving the regularly-used vendored tools out of this dotfiles repo so
others can use them. Adversarial on purpose: the goal is to find where the idea breaks,
not to cheerlead it.

## TL;DR

- **The "agents pattern" you liked is a *private-content-registry* pattern, not a
  tool-distribution pattern.** It clones a private SSH repo and runs an installer that fans
  *data* out to many tools. "Let others use this" needs the opposite: a *public, installable
  package*. Don't blanket-apply the agents pattern to the Python tools — it actively works
  against shareability.
- **Two of the tools are clean to extract** (`token_auditor`, `aws_config_gen` — zero chezmoi
  coupling). **One is two tools wearing one coat** (`mcp_sync` = portable MCP fan-out +
  chezmoi-bound skills sync). **The forgotten one is `aws_config_gen`.**
- **Extraction buys the dotfiles nothing operationally** — the tools already run fine via
  `uv run --project`, zero runtime deps. The *only* upside is shareability. So this is a
  publishing/maintenance commitment, not an engineering win. Decide it on that basis.
- **Recommended:** extract `token_auditor` first as a public, git-installable package (no
  PyPI yet); cut the skills seam out of `mcp_sync`; keep skills sync + personal skills as
  dotfiles glue (or, if anything, a *skills registry* is the only piece that fits the agents
  pattern). Leave `aws_config_gen` vendored unless you genuinely want to maintain it publicly.

## Two patterns, not one

| | Content registry (agents pattern) | Tool package (extraction-for-reuse) |
|---|---|---|
| What travels | Personal *data* + an installer | General-purpose *code* |
| Source repo | Private, SSH, fast-refresh (1h) | Public, tagged releases |
| Consumed by dotfiles via | `.chezmoiexternal` clone + `uv run --directory ... python -m ...` | `uv tool install` / `uvx` / PyPI |
| Consumed by *others* via | Can't — it's your private content | `pip install` / `uv tool install` |
| Fits | `agents` (done); maybe a future `skills` registry | `token_auditor`, `aws_config_gen`, MCP fan-out |

The agents external clone is gated `agents = true` — **personal-mac only**. `mcp` and
`skills` are `true` on **all three** machines (personal, work, lab). Work and lab cannot
clone your personal GitHub over SSH, so the literal "same pattern" (private external clone)
does **not** transplant onto mcp/skills without either forcing those repos public or breaking
two machines. This is the concrete reason "use the agents pattern for mcp/skills" fails as
stated.

## Per-tool readiness

| Tool | Chezmoi coupling | Personal data? | Value to others | Cleanest target |
|---|---|---|---|---|
| **token_auditor** | None | None | High — cross-tool (Claude/Codex/OpenCode) cost auditing is genuinely wanted | Public repo, `uv tool install git+https`; PyPI later |
| **aws_config_gen** | None | Work-only overrides (gitignored) | Low–med — crowded space (`aws-sso-util`, `granted`) | Extract only if you'll maintain it; else leave vendored |
| **mcp_sync → MCP fan-out** | Low | None (config is in dotfiles) | Med — many people juggle MCP configs across tools | Public repo after splitting skills out |
| **mcp_sync → skills sync** | **High** (`skills.py:512` hardcodes `~/.local/share/chezmoi`) | Yes (`skills/personal/`) | Low — it's chezmoi/dotfiles glue | Keep as dotfiles glue, or fold into a skills registry |

`token_auditor` is the standout first move: zero coupling, 100% coverage gate, its own
README, no post-apply hook, and no personal data — it's consumed only by the `codax`/`claade`/
`opencade` shell wrappers, so cutting it loose touches nothing structural.

## How the dotfiles consume an extracted tool

Five mechanisms, lean → heavy:

1. **`uvx <pkg>` at call time** — no install step, always current. Cost: network on cold
   cache, per-call resolution latency, less reproducible unless pinned.
2. **`uv tool install git+https://...@<tag>`** in a `run_onchange_` hook keyed on a pinned
   version file — lands a console script on PATH, lean, *this is how an external user installs
   it too*. Cost: a tag/bump dance per change. **Best default for the general tools.**
3. **`.chezmoiexternal` clone + `uv run --directory`** (the agents pattern) — already wired,
   pins a ref. Cost: clones the whole repo (tests/CI) to every machine just to run a CLI; and
   SSH-private breaks work/lab for mcp/skills. Right for *content registries*, wrong for tools.
4. **PyPI publish + (1) or (2)** — real `pip install`, discoverable. Cost: namespace,
   release pipeline, trusted-publishing setup, supply-chain responsibility. Do this only when
   external demand is demonstrated.
5. **Keep vendored (status quo)** — atomic edits, one CI, one `chezmoi apply`, zero cross-repo
   dance. Cost: not shareable; dotfiles carry ~6k LOC of tool tests.

## Pros & cons of extracting at all

**Pros**

- Others can actually use the tools (the stated goal).
- Forces clean public APIs / docs (token_auditor and aws_config_gen are already there).
- Shrinks the dotfiles repo; CI per tool runs only when that tool changes (already true via
  path filters, but a separate repo makes it absolute).
- Independent versioning and release cadence.

**Cons**

- **Maintenance tax, forever.** Today a change is one commit + one `chezmoi apply`. After
  extraction it's: commit to tool repo → tag/release → bump pin in dotfiles → apply. Every
  change pays the two-repo dance.
- **No operational benefit to the dotfiles.** The tools already work; extraction is purely
  for an audience that may or may not exist (be honest about token_auditor vs. the rest).
- **More surface to secure** if you go PyPI (2FA, trusted publishing, dependency hygiene on a
  public name).
- **`mcp_sync` can't be cut cleanly** until the skills seam is split — otherwise you publish
  a "general MCP tool" that secretly assumes a chezmoi checkout.
- **Loss of atomicity** for the tools that change alongside their config (mcp/skills) — those
  are exactly the ones that benefit *least* from leaving home.

## Recommended sequence

1. **`token_auditor` → its own public repo.** Consume back via `uv tool install
   git+https://github.com/<you>/token-auditor@<tag>` in a `run_onchange_` hook keyed on a
   pinned-version file. No PyPI yet. This proves the extraction loop on the lowest-risk tool.
2. **Split the skills seam out of `mcp_sync`.** Move `skills.py`/`skills_cli.py` to their own
   package (or keep them as dotfiles-internal glue). Now the MCP fan-out is a clean,
   publishable, chezmoi-free tool.
3. **Extract the MCP fan-out** (optional) the same way as token_auditor once the seam is cut.
4. **Skills sync stays home** as dotfiles glue. *If* you want the agents pattern here, the
   honest fit is a **skills registry**: a repo holding `skills/personal/` + the skills-sync
   installer, cloned via `.chezmoiexternal` and run by a hook — mirroring `agents` exactly.
   That's the *one* place "use the agents pattern" is actually right. But it's personal-only
   (matches `agents = true`), so it doesn't help work/lab and isn't "for others."
5. **`aws_config_gen`**: extract only if you'll commit to maintaining it publicly; the space
   is crowded and the marginal benefit is low. Otherwise leave it vendored — that's a fine
   resting state, not a failure.
6. **PyPI**: only when (and if) real external demand shows up.

## The decision that's actually yours

The engineering is easy; the commitment is the question. **"These tools work and are used
regularly" is an argument for leaving them alone, not for extracting them** — they work
*because* they're vendored and atomic. Extract the one with genuine external pull
(`token_auditor`), keep the dotfiles-shaped one (`skills sync`) at home, and treat
`aws_config_gen` / MCP fan-out as opt-in based on whether you actually want public projects to
maintain. The agents pattern stays in its lane: personal content registries, not tool
distribution.
