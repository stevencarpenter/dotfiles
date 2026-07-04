# Work Decoupling & 1Password Secret Migration Plan

> **Status:** roadmap + decision record, not a single linear plan. It spans several
> independently-shippable workstreams; you can stop after any one and be strictly better
> off. Checkbox (`- [ ]`) steps are for the workstreams that are ready to execute.
>
> **Origin:** captures decisions from the 2026-07-01/02 exploration sessions that started in
> the personal `agents` repo but drifted into dotfiles/chezmoi territory (secret custody,
> per-machine identity, work/personal separation). Recorded here because this is where the
> work lives, not in `~/projects/agents`.
>
> **Companion docs:** [`docs/tooling-extraction.md`](../../tooling-extraction.md) (prior
> adversarial analysis of extracting the vendored tools — its conclusions hold and this plan
> builds on them), and [`docs/superpowers/plans/2026-05-17-skill-distribution.md`](2026-05-17-skill-distribution.md).

**Goal:** Decouple the *work-flavored* AI-tooling surface from the personal dotfiles so it can
live in a company-GitHub repo with a work-1Password-managed key, separate from personal
secrets — while (a) getting personal-mac and lab-mac out of the work-secret blast radius, and
(b) producing something teammates can actually consume. Simultaneously migrate the whole
age-encrypted secret surface to 1Password management and stop leaking a work email into git
history.

**Tech stack:** chezmoi (plain-git source, branch/PR workflow — pushed from *both*
personal-mac and work-mac), age → 1Password (`op` CLI v2.34.1, already installed everywhere;
1Password SSH agent already the system-wide SSH auth), Python 3.14 / `uv` (`mcp_sync`,
`agent_registry`), bash chezmoi hooks.

---

## Why this is bigger than "move 5 skills"

The encrypted surface is **30 files = 9 logical secrets**, all under a **single age
recipient** (`age1462h0…`) whose private key sits on all three machines including lab-mac
(weakest posture, still being stood up). The secrets split cleanly by destination vault:

| Logical secret | Files | Class | Destination |
|---|---|---|---|
| 5 work Claude skills (databricks-tf, kafka-connect, schema-drift, spark-forensics, terraform-gauntlet) | 25 | Work / customer-specific | **Work vault + company repo** |
| `dot_config/zsh/encrypted_dot_work.env.age` | 1 | Work | **Work vault** (or company repo) |
| `dot_config/aws-config-gen/encrypted_overrides.json.age` | 1 | Work (AWS account/role mappings) | **Work vault** |
| `dot_config/zsh/encrypted_dot_personal.env.age` | 1 | Personal | **Personal vault, in place** |
| `dot_config/zsh/encrypted_dot_env.age` (base/shared) | 1 | **Unknown — may straddle** | Split first, then route |
| `private_dot_ssh/encrypted_private_config.age` | 1 | **Unknown — may straddle** (host aliases) | Split first, then route |

**The key simplification:** the 7 work secrets' 1Password migration *is* the company-repo
move — one workstream, not two. Only 2–3 personal secrets need an in-place age→`op://` swap.

Auto-encrypt globs live in `.chezmoiencrypt.toml` (`**/secret*`, `**/password*`,
`**/*token*`, plus the explicit zsh env files and `.envrc`) — anything migrated out of age
must also drop out of these globs or it'll be re-encrypted on the next `chezmoi add`.

**No `op://` templating exists in the repo yet** — this migration establishes the pattern
from scratch (greenfield; nothing to stay consistent with).

## Chosen architecture: Thin Split + Separate Team Repo

Treat the two goals as separate problems, each solved with the smallest sufficient change
(this is the winner of a 4-way judged bakeoff; it took 3 of 5 lenses — custody/blast-radius,
weekly-maintenance, and least-disruption-to-personal-mac — and 2nd on the other two). It also
agrees with `tooling-extraction.md`: the agents pattern is a *content-registry* pattern, and
`mcp_sync`'s skills-sync is chezmoi-bound (`skills.py` hardcodes `~/.local/share/chezmoi`), so
do **not** try to transplant the private-SSH-external pattern onto a team audience.

- **Problem 1 (blast radius):** the 7 work secrets leave the personal dotfiles for a
  company-org repo with its own work-1Password-vaulted key, capability-gated so personal-mac
  and lab-mac never even clone it.
- **Problem 2 (team asset):** a freestanding company-org `agent-registry` fork (the CLI is
  zero-dependency, pure-stdlib, no personal paths — trivially forkable) that teammates install
  with `uv run python -m agent_registry.cli install`, no chezmoi/1Password/age required.

**Grafts adopted regardless of architecture:**
- Add a permissive **LICENSE (MIT/Apache-2.0) to the personal `agents` repo now**, before any
  company use or public flip — forecloses the "unlicensed personal repo of an employee"
  governance flag and the departure-risk of a live cross-repo dependency.
- **Vendor, never depend:** the company repo forks/copies `agent_registry` at a point in time;
  pulling upstream improvements is a manual reviewed PR, never a submodule/live checkout.
- **Layer, don't fork, company agents:** add a multi-`--skills-dir` flag to `agent_registry`
  so a company agent can list `skills: spark-scala-guidelines, company-spark-platform-guidelines`
  and inline both a public rubric and a private one, instead of forking whole `agent.md` files
  that then drift from upstream fixes.
- **Finish the secrets migration in one pass:** move `encrypted_dot_work.env.age` alongside the
  5 skills, don't leave it as a fast-follow.
- Defer extracting `mcp_sync` into a shared engine until a *second real consumer* exists (a
  teammate asking for MCP-overlay parity). Note the trigger; don't build speculatively.

## 1Password mechanics (verified against current tool behavior)

- **Secret custody — prefer `op://` templating over keeping ciphertext.** Replace
  `encrypted_foo.age` with a `foo.tmpl` calling `{{ onepasswordRead "op://Vault/item/field" }}`
  (chezmoi built-in) so the secret lives in 1Password and the repo holds only a reference —
  this kills the "one age key on every machine" problem for that secret entirely (no age key
  needed at all). For a whole identity/key file, use the hook pattern instead:
  `[hooks.read-source-state.pre]` runs `op read "op://Vault/item/key" > $KEY_PATH; chmod 600`,
  and `[hooks.apply.post]` / `[hooks.diff.post]` / `[hooks.status.post]` shred it after.
- **Headless auth = Service Account token**, not the desktop app. `OP_SERVICE_ACCOUNT_TOKEN`
  (an `ops_…` token, read-only, vault-scoped at creation) works with zero biometric/app
  unlock — required for lab-mac and any unattended `chezmoi apply`. Interactive `op` (desktop
  app + biometric) is fine for personal-mac/work-mac.
- **Vault-scoping fixes blast radius for free:** scope lab-mac's service account to *no* work
  vault, and it structurally cannot read work secrets even if it tried — the fix falls out of
  the mechanism instead of needing separate key management.
- **Reject `age-plugin-op`** — single-maintainer, barely reviewed, unverified headless support;
  don't put it in the trust-critical decrypt path. The `op`-CLI + chezmoi-hook path achieves
  the same end state with only officially-supported tooling.
- **Root-of-trust caveat:** the service-account token is the one secret that can't live inside
  what it unlocks (chicken-and-egg). It goes in macOS Keychain or a tight-perm file. Decide
  per machine once (see W6).

## Second GitHub identity (verified)

- Work-mac already has a **separate SSH key registered to the personal GitHub account** — so it
  authenticates to the personal dotfiles repo today via its own key (no shared key). It is an
  **equal contributor**: changes and branches are pushed from work-mac, not just personal-mac.
- For the company org, add an SSH host-alias (mirroring the existing per-host blocks in
  `~/.ssh/config`): `Host github-work` / `HostName github.com` / `IdentityFile ~/.ssh/work_git.pub`
  / `IdentitiesOnly yes`. Pointing `IdentityFile` at the **public** key is intentional, not a
  typo: with the 1Password SSH agent as the system-wide SSH auth (no local private key file
  exists at all), OpenSSH accepts a `.pub` path here purely to select which identity to *request*
  from the agent — the agent matches it to the private key it holds and never touches disk.
  Clone/set-url work repos as `github-work:org/repo.git`. Personal `github.com` URLs are
  unaffected.
- **Use the SSH alias for git, not global `gh auth switch`.** `gh` supports concurrent
  multi-account login, but the active account is a single *global* per-host setting — easy to
  push/comment as the wrong identity. For the narrow set of `gh` calls that must hit the company
  org, use `GH_TOKEN=$(gh auth token --user <work-handle>) gh …` instead of switching globally.

---

## Already applied this session (uncommitted in this working tree)

These are done in the working tree, not yet committed. Listed so they're not lost and are
committed deliberately (likely as their own scoped commits). **Not mine and unrelated — leave
alone:** `dot_config/hippo/config.toml` (model experiments), `dot_config/jj/` (new jj config).

- [x] `.chezmoiscripts/run_after_sync-agents.sh.tmpl` — install from `~/projects/agents` working
  copy when present (was silently installing the hourly, days-stale external clone); appends a
  routing-context cache-write step after install.
- [x] `dot_claude/hooks/executable_emit-routing-context.sh` — new SessionStart hook that `cat`s
  the cached routing block (~9ms, no per-session generation).
- [x] `dot_claude/modify_settings.json.tmpl` — wires that hook into `SessionStart` gated on the
  `agents` capability (independent of the hippo gate; generalized the stale-hook cleanup to
  strip either hook when its capability flips off).
- [x] `dot_config/mcp/mcp-master.json` + `machine/{personal,work,lab}.json[.tmpl]` — deduped
  grafana into master with a per-machine `enabled:false` in `work.json` (verified the effective
  per-machine server sets are unchanged).
- [x] `dot_config/skills/skills-master.json` + `skills/personal/chezmoi-secret-encrypt-verify/`
  — decrypted the generic `chezmoi-secret-encrypt-verify` skill (no real secrets) out of
  `dot_claude/skills/*.age` and moved it to a plaintext personal skill source.

**Counterpart work in `~/projects/agents`** (3 jj commits on `cursor/spark-and-jj-agents`, not
pushed): skill eval suites + `validate_skill_closure`; `build/` untracked; the
`tools/routing/generate_context.py` generator. The routing hook deliberately spans both repos
(generator in `agents`, hook wiring + cache-write here).

---

## Workstreams (each independently shippable; recommended order)

### W1 — Git author email: forward fix (do first, trivial)

Only one real consumer: `dot_config/git/config.tmpl:6` (`email = {{ .email }}`, which is the
*work* email on work-prefixed machines). Point `user.email` at the GitHub `noreply` address on
all machines so no machine ever stamps a real work or personal email into history again.

- [ ] Change `config.tmpl` to a `noreply` email (decide: constant noreply, or keep `.email` for
  display but override `user.email`). Verify `chezmoi execute-template` renders correctly for
  all three machine types.
- [ ] `chezmoi apply` on work-mac; confirm `git config user.email` is the noreply.

### W2 — Git history scrub (the genuinely hard one; before going public)

- [ ] Rewrite work-email author/committer across history (`git filter-repo --mailmap`), **with
  both machines quiescent** (no in-flight branches) or the old identity merges back in.
- [ ] **Also check for ever-committed plaintext secrets** (before the `encrypted_` treatment
  existed) — the scarier version of the same operation, and the one that actually bites when the
  repo goes public. This is a separate scan from the email scrub; don't let the email distract
  from it.
- [ ] Force-push; re-clone/reset on both machines.

### W3 — Prove the `op://` pattern on one personal secret (de-risk before volume)

- [ ] Migrate `encrypted_dot_personal.env.age` → a `.tmpl` using `onepasswordRead`; create the
  1Password item in the personal vault; drop it from `.chezmoiencrypt.toml` globs.
- [ ] `chezmoi apply`; verify the rendered target is correct and no plaintext is in the source
  tree or git history. Establishes the repeatable per-secret checklist.

### W4 — Migrate remaining personal secrets age → personal 1Password vault

- [ ] Inspect whether `encrypted_dot_env.age` and `private_dot_ssh/encrypted_private_config.age`
  **straddle** work/personal (read-only; do NOT dump values into a transcript/context). Split any
  that do before routing.
- [ ] Apply the W3 pattern to each personal secret.

### W5 — Work decoupling = company repo + work vault (handles the 7 work secrets' 1Password migration)

- [ ] Add LICENSE to personal `agents` repo (graft; do independently, anytime).
- [ ] Create empty company-org repo; provision work 1Password vault + read-only Service Account.
- [ ] Add the `github-work` SSH host-alias; add multi-`--skills-dir` to `agent_registry`.
- [ ] Move the 5 work skills + `encrypted_dot_work.env.age` + `aws-config-gen` overrides into it,
  re-keyed to the work vault; capability-gate a new `.chezmoiexternal` entry + a *new* (not
  repointed) `run_after_sync-work-secrets.sh.tmpl` so personal-mac/lab-mac never fetch it.
- [ ] Verify `chezmoi apply` decrypts on work-mac only; personal-mac/lab-mac don't clone it.
- [ ] Teammate onboarding target: `git clone github-work:org/agent-registry && uv run python -m
  agent_registry.cli install` — no chezmoi, no vault access, no age.

### W6 — Root-of-trust per machine (decide once)

- [ ] personal-mac / work-mac: 1Password desktop app + biometric for interactive `op`.
- [ ] lab-mac / any CI: vault-scoped Service Account token in Keychain (or tight-perm file);
  scope it to exclude the work vault so lab structurally can't read work secrets.

---

## Open decisions (not yet made)

- **Personal `agents` repo visibility** — public (matches its own CLAUDE.md non-sensitive
  mandate + token-auditor precedent; content-audit first since jj auto-snapshots `research/`,
  `mining/`) vs. scoped deploy key. Blocks flipping `agents=true` on work-mac if that's wanted.
- **`encrypted_dot_env.age` / SSH config straddle** — resolved in W4's first step; determines
  whether they split.
- **Teammate distribution channel** — plain `git clone` + `uv run` is enough to start; PyPI /
  `uv tool install` only if external demand shows up (per `tooling-extraction.md`).
- **`mcp_sync` extraction** — deferred; trigger is a teammate asking for MCP-overlay parity.

## Honest hard parts

1. **W2 history scrub** — force-push across two authoring machines with branches possibly in
   flight (plain git, not jj). Highest coordination cost. The plaintext-ever-committed check is
   the dangerous half, not the email.
2. **W6 root secret** — the `op` service-account token can't live inside what it unlocks;
   there's always one irreducible bootstrapping secret outside the system.
3. Everything else is voluminous-but-mechanical: once W3 proves the `op://` pattern on one
   secret, the rest is a checklist.
