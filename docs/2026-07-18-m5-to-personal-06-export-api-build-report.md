<!--
OUTBOUND — new file, append-only (nothing prior edited). Written 2026-07-18 on the m5 session.
From: m5 session.  To: personal-mac session.  Chain position: outbound, m5 seq 06.
Org-agnostic by rule 5; uncommitted-mechanism deviations recorded here so the
org side can build against reality, not against the original draft.
-->

# m5 → personal 06 — export-API build report

The m5 export-API build (checklist items 1–5 in `docs/external-overlays.md`)
is complete and gated green. The sanitized consensus history and final
migration plan are preserved in
[`external-overlays-decision-record.md`](external-overlays-decision-record.md).

## What shipped, per task

1. **`lib.mkHost` + module exports + superset caps assertion** — `0d21b29`.
   Flake now exports `lib.mkHost`, `darwinModules.default`,
   `homeModules.default` (+ `homeManagerModules` alias), and
   `lib.canonicalCapKeys`. The host-row caps assertion relaxed from exact-key
   equality to superset — external rows may add caps their own modules gate
   on; validating those extra caps is the external repo's responsibility.
2. **`homeModules.rawDotfiles`** — `ff3359d`. Generalized the out-of-store
   symlink machinery in `dotfiles.nix` into a reusable, source-root-
   parameterized module, so an external wrapper gets the same
   edit-live-without-rebuild property for its own `files/` tree.
3. **`mkDefault` on identity-selected symlinks** — `031fdaf`. The mcp/skills
   machine overlays and other identity-selected symlinks now declare
   `lib.mkDefault`, so an external module can take ownership without an eval
   conflict. (Minor doc-parity fix in this task: the skills overlay was
   missing the explanatory one-liner the mcp overlay already carried —
   added, no behavior change.)
4. **ssh/git/tmux extension seams** — `c21a722`. Native layering seams:
   ssh `Include ~/.ssh/config.d/*` (top-placed, above all `Host` blocks), git
   isolated `external-overlays/git/{extra,work}.inc` fixed-filename includes,
   and the `external-overlays/tmux/*.conf` `source-file -q` glob.
5. **Claude settings fragment hook** — `f25348c`. Activation-time jq merge
   in `ai-stack.nix`: fragments dropped in `~/.claude/settings.d/*.json`
   deep-merge over the managed base+variant settings.

Step 6 (extraction — moving org files/overlays/secrets out and deleting the
work module here) remains explicitly out of scope for this build; it happens
after an external repo exists to receive them.

## Review-caught deviations and corrections

Both matter to a wrapper author building against this contract — the letter
of the original seam table undersells the actual mechanism:

1. **`home.file`-under-symlinked-directory collision → isolated overlay dirs.**
   An initial workaround placed git/tmux `.keep` files inside their existing
   whole-directory out-of-store symlinks. That made the include paths exist but
   did not let an external Home Manager module own a nested fragment: building
   such a consumer failed with "outside $HOME". The corrected model preserves
   the base directory links and moves externally owned fragments to the real
   `~/.config/external-overlays/{git,tmux}` tree. No live-state migration or
   parent-link mutation is required.
2. **Fragment-merge commit-on-success hardening.** A Task 5 review catch:
   the Claude settings fragment merge now only commits its jq output to the
   real settings file on successful, well-formed output. Without that guard
   a malformed fragment (bad JSON, a `jq` error) could have overwritten the
   managed base with an empty or partial merge result during activation.
3. **Declared overrides must be executable contracts.** The Worktrunk seam is
   now `mkDefault`, and the external-consumer regression build exercises git,
   tmux, Worktrunk, and wrapper revision composition together.

## Hostname collision rule (new — flag for wrapper authors)

`lib.mkHost` selects a host's darwin import by
`builtins.pathExists ./hosts/${hostName}.nix`, falling back to the generic
`modules/darwin` import only when no such file exists in this repo. An
external wrapper whose host row uses a `hostName` that collides with an
in-repo basename (`personal-mac`, `work-mac`) gets **this repo's in-tree
shim silently substituted** for its own host module, with no eval error.
Wrapper authors must pick a `hostName` distinct from every file under
`hosts/`.

## Verification (this session, all green)

- `nix flake check --no-build` — clean (only the expected "unknown flake
  output" info-level warnings for `homeModules`/`homeManagerModules`, which
  are extra, non-standard outputs `nix flake check` doesn't recognize by
  name; not an error).
- `pre-commit run --all-files` — all hooks passed.
- `git ls-files '*.sh' | xargs -n1 bash -n` — all scripts parse.
- `scripts/test-exec-bits.sh` — OK, all exec'd scripts 100755.
- `scripts/test-external-overlay-contract.sh` — wrapper revision, isolated git
  and tmux fragments, and Worktrunk takeover build together.
- `nix build '.#darwinConfigurations.<host>.config.home-manager.users.carpenter.home.activationPackage' --no-link`
  — succeeded for both `personal-mac` and `work-mac`.

### Final baseline-diff proof

Re-evaluated `home.file` for both hosts against the Task-0 baselines. The
intended structural delta is:

- `+ .ssh/config.d/.keep`
- `+ .claude/settings.d/.keep`
- `+ .config/external-overlays/git/.keep`
- `+ .config/external-overlays/tmux/.keep`

The existing git, tmux, and Worktrunk targets remain present; Worktrunk now uses
a lower-priority default definition.

## Pending

- **Live switch (owner-only, needs sudo)** — not run this session. Pending
  owner action: `./rebuild.sh`, then spot-check `readlink
  ~/.ssh/config.d/.keep` resolves, `ssh -G i9` stays clean, and a new shell
  opens under the startup budget.
- Owner go/no-go items still open per round-5 ack: (1) go for this build —
  now delivered; (2) go for the org-side v2 rewrite; (3) aws-tool decision
  (default vendored, no action needed to accept); (4) archive-hardening
  decision; (5) org name/vault/schema when Part B begins.

## For the wrapper

The export API above is real and gated as of this build. A wrapper flake may
be built against a revision containing this report and its review remediation — `lib.mkHost`,
`darwinModules.default`, `homeModules.default` / `homeManagerModules`,
`homeModules.rawDotfiles`, and `lib.canonicalCapKeys` are all present and
building for both host types. Build against the two deviations above, not
the original seam-table letter.
