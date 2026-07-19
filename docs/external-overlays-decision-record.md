# External overlays: consensus, decisions, and migration record

## Status and privacy boundary

This is the single public-safe record of the external-overlay design. It
captures the full problem, the review process, the decisions that survived
review, the implemented base-repository API, and the remaining migration.

Names, account identifiers, repository URLs, machine names, vault names,
organization names, and other personally or workplace-identifying details are
intentionally omitted. Historical working documents may contain more detail;
they are not part of this repository's contract and are not required to apply
the design.

The normative interface remains [`external-overlays.md`](external-overlays.md).
If this record and that contract disagree, stop and reconcile them through an
explicit review rather than silently choosing one.

## Scope

The base repository currently defines a reusable macOS configuration and also
contains configuration selected for a second administrative context. The goal
is to move context-specific configuration into a separately controlled
external repository without:

- making the public base depend on a private input;
- exposing names, URLs, credentials, or other identifying metadata;
- breaking the base repository's complete CI evaluation;
- forcing teammates to adopt Nix or this repository's dotfile layout;
- creating two writers for the same file;
- losing generic tools merely because their configuration is context-specific;
- deleting the existing configuration before the replacement is proven; or
- entangling personal credentials with externally administered secrets.

The work is therefore split into two milestones:

1. expose and verify stable extension seams in the base repository; then
2. build and validate the external consumer before removing any migrated
   material from the base.

## How consensus was reached

The design was not accepted from the initial proposal. It went through an
adversarial review and several response rounds:

1. **Initial proposal.** The base flake would conditionally consume a private
   repository and select its modules only for one identity.
2. **Blocking review.** Conditional module composition was shown not to prevent
   eager flake-input fetching. The design would require private credentials for
   unrelated base builds, weaken CI, expose the external identity in public
   metadata, and require a public-repository edit during future transitions.
3. **Architectural inversion.** The external repository became the wrapper and
   the public repository became its input. This removed private fetching and
   identifying references from the base while preserving complete base CI.
4. **Refinement round.** The non-Nix path was changed from seam-only deployment
   to a dual-mode installer; the secrets boundary was clarified; tools were
   separated from configuration fragments; the capability-superset tradeoff
   received an explicit owner; and operational handoff was added to the
   migration.
5. **Ownership review.** Whole-file tools without native includes were assigned
   exactly one owner. The identity-specific window-manager file moves whole,
   rather than being split by line range. Skills deployment was checked for
   double management and assigned to one mechanism.
6. **Independent verification and lock.** Both sides independently converged on
   the inverted architecture and verified the privacy boundary. Remaining
   clarifications were resolved, and the contract was locked for implementation.
7. **Implementation review.** A consumer fixture exposed that git and tmux
   include directories still sat below whole-directory symlinks, preventing an
   external Home Manager module from writing fragments. The external fragments
   moved to an isolated real directory, Worktrunk's documented override was
   implemented, wrapper revision attribution was corrected, and consumer-level
   regression coverage was added.

Consensus means the design survived those objections; it does not mean every
early proposal was incorporated.

## Final architecture

The dependency points from the external repository to the base:

```text
external repository
  flake wrapper
  context-specific files and fragments
  external modules and secrets
           |
           | flake input
           v
base repository
  lib.mkHost
  darwinModules.default
  homeModules.default
  homeModules.rawDotfiles
  declared file and structured-merge seams
```

The external host switches from the wrapper flake. Base-only hosts continue to
switch from the base repository. Updating the base for the external host is an
explicit wrapper lock-file update, which is accepted in exchange for privacy,
CI isolation, and clean lifecycle ownership.

## Locked decisions

### Dependency and privacy

- The base repository never names, fetches, or conditionally imports the
  external repository.
- Identifying names and URLs do not appear in tracked files, comments, examples,
  ignore patterns, or history.
- The external repository consumes a pinned revision of the base.
- A later change of external context replaces the wrapper; the base contract
  does not change.

### One writer per target

- The base owns base files and the extension points they expose.
- The external repository owns fragments placed in those extension points and
  any whole file explicitly declared overridable.
- A missing seam is fixed in the base contract; it is not worked around by
  patching or mutating a base-owned file.
- Runtime-managed directories remain runtime-owned.

### Composition API

`lib.mkHost` accepts the canonical host fields plus:

- `configurationRevision` for wrapper revision attribution;
- `extraDarwinModules` for system-level composition; and
- `extraHomeModules` for user-level composition.

The base exports its Darwin and Home Manager module sets, the
`rawDotfiles.trees` helper, and the canonical capability keys. External host
rows must include every canonical capability as a boolean and may add their own
boolean capabilities. The external wrapper is responsible for validating any
extra keys it introduces.

An external wrapper should pass its own revision explicitly:

```nix
configurationRevision = self.rev or self.dirtyRev or null;
```

The base definition is a module default, so an extra Darwin module may also
supply the revision without `mkForce`.

### Configuration seams

- SSH: `~/.ssh/config.d/*`, included before every base `Host` block because SSH
  uses first-match-wins semantics.
- Git: fixed `~/.config/external-overlays/git/extra.inc` and `work.inc`
  includes. The isolated parent is real and externally writable without
  nesting beneath the base git directory link.
- tmux: `~/.config/external-overlays/tmux/*.conf`, loaded after the base config
  from the same isolated ownership tree.
- Shell: `~/.config/zsh/profile.d/*.zsh`.
- MCP and skills: identity overlay files whose base sources are `mkDefault` and
  may be replaced by an external module.
- Claude settings: lexical `~/.claude/settings.d/*.json` deep merge over the
  managed block, with malformed fragments skipped without committing partial
  output.
- Whole-file tools: explicit `mkDefault` ownership for formats without native
  layering, currently including the identity-selected window-manager config and
  Worktrunk.

### Nix and non-Nix consumers

- On the managed external host, the wrapper composes modules and deploys files
  through Home Manager.
- On teammate machines, the default installer copies content into standard tool
  locations and does not assume this base repository or Nix.
- The non-Nix path must have an idempotent uninstall operation and must not edit
  a teammate's base dotfiles.
- The two modes deploy the same logical content and must not assign different
  ownership for the same target.

### Tools

- Generic tools remain public and context-neutral; context-specific repositories
  provide only configuration or overrides.
- Tools and activation hooks compose through modules on the Nix path and through
  ordinary tool installation plus generation steps on the non-Nix path.
- Tools are not represented as configuration fragments.
- Public tool installation uses an authentication-neutral transport.
- If a helper is copied for standalone use, the public copy remains upstream;
  the external copy is refreshed deliberately and is not allowed to diverge as
  an independent fork.

### Secrets

- Personal secret recipients are never reused for externally administered data.
- No single person's key is the team decryption path.
- Credential-class values are never committed in plaintext, including to a
  private repository.
- Non-credential configuration may use repository access as its boundary.
- Credential templates contain references only and render against an
  externally administered vault or equivalent shared secret system.
- Migration is secret-by-secret and reversible until cutover is verified.

### Skills

- Each skill has exactly one deployment owner: either the structured skills
  overlay/synchronizer or direct file ownership, never both.
- A subtractive machine overlay may disable base skills without redeploying
  externally owned skills.
- The Nix module and non-Nix installer must implement the same ownership choice.

## Implemented base preparation

The base repository now provides:

- exported host and module APIs;
- a superset capability contract;
- reusable out-of-store raw-file linking;
- external Darwin and Home Manager module composition;
- wrapper revision attribution;
- isolated real directories for git and tmux extension fragments, without
  changing ownership of their base directories;
- native SSH, git, tmux, and shell seams;
- structured MCP, skills, and Claude settings seams;
- `mkDefault` takeover points for the current whole-file overrides; and
- an external-consumer build test covering nested fragments, Worktrunk takeover,
  and revision behavior.

This preparation is intentionally behavior-preserving for existing base hosts.
It does not remove the material that will eventually move.

## Final migration plan

### Phase 0: freeze and inventory

1. Capture the current base and external-host activation packages.
2. Inventory every context-specific file, secret, package, hook, capability,
   generated artifact, and operational command.
3. Assign each item to a declared seam, a whole-file takeover, an external
   module, a generic public tool, or explicit retirement.
4. Reject any item with two proposed writers or no rollback path.

### Phase 1: scaffold the external repository

1. Create a private wrapper flake that pins the base repository.
2. Define an external host row containing every canonical capability, any
   validated external capabilities, the wrapper revision, and the extra modules.
3. Add a source-root-aware raw-file tree for external files.
4. Add CI that evaluates the wrapper and builds its Home Manager activation
   package without requiring personal credentials.
5. Add a dual-mode installer and uninstall path for non-Nix consumers.

### Phase 2: move configuration without deleting the source

1. Add SSH, git, tmux, shell, MCP, skills, and Claude fragments to their declared
   seams.
2. Move each no-include identity file whole and take over its `mkDefault` target.
3. Move context-specific package and activation behavior into extra modules.
4. Keep generic tools in public ownership and point external configuration at
   them.
5. Resolve skills through the single agreed deployment owner.

The base copies remain during this phase as rollback material, but only one side
may be active for a given target in the generated configuration.

### Phase 3: migrate secrets

1. Provision externally administered recipient or vault access for every
   authorized operator.
2. Recreate templates with references rather than credential values.
3. Render to temporary targets and compare permissions, structure, and consumer
   behavior with the current outputs.
4. Switch one secret consumer at a time and retain the prior encrypted source
   until validation passes.
5. Verify that personal recipients and account identifiers are absent from the
   external secret path.

### Phase 4: validate both delivery modes

For the wrapper host:

1. evaluate all outputs;
2. build the Darwin and Home Manager activation packages;
3. verify emitted file ownership and symlink destinations;
4. test native include ordering and structured merges;
5. test secret rendering without exposing values; and
6. perform a controlled switch with the previous generation available.

For a clean non-Nix fixture:

1. run the installer twice to prove idempotence;
2. verify standard locations and expected tool behavior;
3. confirm unrelated dotfiles are unchanged; and
4. run uninstall and confirm only externally installed material is removed.

### Phase 5: operational cutover

1. Change the external host's daily rebuild command to the wrapper flake.
2. Transfer bootstrap, flake-root selection, lock-file updates, and recovery
   documentation to the external repository.
3. Verify the generated system reports the wrapper revision.
4. Exercise rollback to the last base-managed generation.
5. Observe at least one normal update cycle before deleting the old sources.

### Phase 6: remove migrated material from the base

Only after the external host and non-Nix path are green:

1. delete migrated context-specific files, overlays, hooks, and secrets from the
   base repository;
2. remove the external host row and host detection from base bootstrap/rebuild
   scripts;
3. remove gates and secret plumbing that have no remaining base consumer;
4. retire the old secret mechanism if no base secret uses it;
5. run an orphaned-file, orphaned-capability, and stale-documentation sweep;
6. re-run every base and external gate; and
7. record the cutover revision and rollback generation without identifying the
   external context in this repository.

## Acceptance gates

Migration is complete only when:

- the base repository evaluates and builds without external credentials;
- the wrapper reports its own revision and builds with all external modules;
- nested git and tmux fragments build without an outside-home error;
- every managed target has one writer;
- native include order and structured merge precedence are tested;
- malformed structured fragments fail safely;
- no credential-class value appears in either repository or build output;
- the non-Nix install/uninstall cycle is idempotent and reversible;
- the external host can roll back to a known generation; and
- the base contains no remaining external identity, source, secret, or
  operational dependency.

## Change control

The architecture is locked, but implementation corrections are allowed when a
test proves the contract cannot be consumed as written. Any change to dependency
direction, privacy boundaries, secret ownership, deployment modes, or the
one-writer rule requires a new explicit review with the objection, evidence,
decision, and migration impact recorded here or in a successor decision record.
