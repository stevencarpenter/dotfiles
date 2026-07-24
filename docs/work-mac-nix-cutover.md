# Work laptop Nix cutover and external-wrapper runbook

This runbook moves the work laptop from chezmoi to the Nix dotfiles and makes the external work
flake the long-term system owner. It is intentionally public-safe: substitute the private wrapper
repository path, input name, host name, and secret mechanism locally.

## Decision: switch once, to the wrapper

Do **not** make the base repository's `work-mac` output the live owner and then perform a second
live cutover to the external wrapper. Use `work-mac` as a build-only canary. The first live Nix
switch should use the completed wrapper output.

The two-stage live sequence would change flake roots, rebuild commands, secret ownership, and
generated-file ownership twice. It would also briefly make the work laptop depend on the personal
age recipient. The locked architecture already says the external host switches from the wrapper,
while the base remains its pinned input.

## Current readiness and outstanding work (2026-07-20)

The base side is structurally ready. The external-overlay API and consumer test are on `main` at
`e4c869d`, including `lib.mkHost`, module exports, canonical capabilities, raw-file trees, extension
seams, whole-file takeover points, and wrapper revision attribution.

The work cutover is **not operationally ready** until all of these are complete:

- [ ] Choose and pin a reviewed base revision. PR #145 is green but not merged as of this date; it
  includes work-relevant Homebrew and tiling fixes. Merge it first or deliberately pin another
  reviewed SHA. Do not pin a floating branch.
- [ ] Obtain the actual external work flake on the work laptop and audit it. It is not present in
  this checkout, so none of its outputs, secrets, or ownership claims have been verified.
- [ ] Confirm the work laptop does not depend on the stale `origin/fromwork` ref before retiring
  it. That ref predates both the Nix migration and the external-wrapper API; it is not an
  integration base.
- [ ] Make the wrapper call the base's `lib.mkHost`; do not construct a second competing
  `darwinSystem` around it.
- [ ] Give the wrapper a host name that does not collide with `personal-mac` or `work-mac`. A name
  such as `work-wrapper` is safe; `work-mac` silently selects the base host shim.
- [ ] Add every canonical boolean capability to the wrapper row and validate any external-only
  capability names in the wrapper.
- [ ] Implement the two-checkout rule: the base checkout stays physically at `~/.dotfiles`, while
  the wrapper lives at a different physical path and becomes the rebuild root.
- [ ] Add a wrapper preflight that refuses a dirty base checkout and proves its `HEAD` is exactly
  the base revision pinned in the wrapper lock file. Nix evaluation uses the pin, but base raw
  links and activation hooks read `~/.dotfiles`; allowing those revisions to differ is
  nondeterministic.
- [ ] Inventory every work-owned target and assign exactly one writer before moving it.
- [ ] Move work secrets to externally administered custody. The current bridge still decrypts 27
  work ciphertexts with the personal age identity: the work environment, AWS overrides, and 25
  work-skill files. That is acceptable only as rollback material, not as the wrapper end state.
- [ ] Give the wrapper its own bootstrap, rebuild/update command, rollback procedure, and live
  verifier. The base `rebuild()` only accepts `personal-mac|work-mac`, switches `~/.dotfiles`, and
  the existing verification script is personal-only.
- [ ] Build and verify the wrapper, exercise rollback, and complete one normal wrapper update
  cycle before extracting work ownership from the base or cleaning chezmoi.

The current base work payload to classify includes:

- `home/.config/aerospace/aerospace.work.toml`;
- the work MCP and skills overlays;
- three work zsh fragments;
- the infra mise fragment and work-only `conftest` package;
- work-only Claude plugin behavior;
- AWS config generation and its overrides;
- the work environment plus 25 encrypted work-skill files;
- the `work-mac` host row/shim and host detection in bootstrap/rebuild scripts.

Generic tools should remain in the public base. Move configuration or external modules, not a
private fork of a generic tool.

## Required wrapper shape

The wrapper owns the host and consumes this repository as an input:

```nix
{
  inputs.base.url = "github:stevencarpenter/dotfiles/<reviewed-revision>";

  outputs = { self, base, ... }:
    let
      hostName = "work-wrapper";
      canonicalCaps = builtins.listToAttrs (
        map (name: { inherit name; value = false; }) base.lib.canonicalCapKeys
      );
    in {
      darwinConfigurations.${hostName} = base.lib.mkHost hostName {
        system = "aarch64-darwin";
        user = "carpenter";
        identity = "work";
        caps = canonicalCaps // {
          tiling = true;
          sketchybar_workspace_badges = true;
          mcp = true;
          skills = true;
          gui = true;
          aws_sso = true;
          infra = true;
        };
        configurationRevision = self.rev or self.dirtyRev or null;
        extraDarwinModules = [ ./modules/darwin.nix ];
        extraHomeModules = [ ./modules/home.nix ];
      };
    };
}
```

The real wrapper may structure this differently, but these contracts are mandatory:

- the dependency points from wrapper to base;
- the host name is unique;
- the wrapper revision is reported by the running system;
- wrapper files use `rawDotfiles.trees` with the wrapper's own physical `files/` root;
- work fragments land only in declared seams;
- MCP, skills, AeroSpace, and Worktrunk use their explicit takeover points when whole-file
  ownership is required;
- wrapper secrets do not use the personal recipient or a single employee's key;
- the wrapper supplies a later-loaded shell fragment that replaces the base `rebuild()` and
  transitional `ca()` functions with wrapper-root behavior.

## Phase 0: freeze and capture the work laptop

Do this before cloning over paths or switching generations. Do not record secret contents.

```bash
cutover_stamp="$(date +%Y%m%d-%H%M%S)"
cutover_state="$HOME/.local/state/dotfiles-cutover/$cutover_stamp"
mkdir -p "$cutover_state"

scutil --get LocalHostName > "$cutover_state/local-host-name.txt"
uname -a > "$cutover_state/uname.txt"
command -v chezmoi > "$cutover_state/chezmoi-command.txt"
chezmoi source-path > "$cutover_state/chezmoi-source-path.txt"
chezmoi managed > "$cutover_state/chezmoi-managed.txt"
chezmoi status > "$cutover_state/chezmoi-status.txt"
git -C "$(chezmoi source-path)" status --short --branch > "$cutover_state/chezmoi-git-status.txt"
git -C "$(chezmoi source-path)" rev-parse HEAD > "$cutover_state/chezmoi-source-revision.txt"
brew list --formula > "$cutover_state/brew-formulae.txt"
brew list --cask > "$cutover_state/brew-casks.txt"
darwin-rebuild --list-generations > "$cutover_state/darwin-generations.txt" 2>&1 || true
readlink /run/current-system > "$cutover_state/current-system.txt" 2>/dev/null || true
```

Also record, without displaying values:

```bash
for target in \
  "$HOME/.config/zsh/.work.env" \
  "$HOME/.config/aws-config-gen/overrides.json"; do
  if [ -e "$target" ]; then
    stat -f '%N %Lp %Su:%Sg %z bytes' "$target"
  else
    printf 'missing: %s\n' "$target"
  fi
done > "$cutover_state/work-secret-metadata.txt"
```

Before proceeding:

- [ ] Commit and push wanted changes from the chezmoi source, or archive the exact dirty diff in a
  secure location. Do not use `chezmoi diff` in a general log; it can expose rendered secret
  material.
- [ ] Confirm no teammate or second machine is expected to push a conflicting source rewrite
  during the cutover window.
- [ ] Confirm the old source revision and the current system generation are recoverable.
- [ ] Stop running `chezmoi apply`, automatic external refreshes, and the old `ca` workflow from
  this point onward.

## Phase 1: prepare both checkouts

Use two physical repositories:

```text
~/.dotfiles                  public base checkout; must match the wrapper's locked base revision
<private-wrapper-path>       external wrapper checkout; daily flake root after cutover
```

Do not point `~/.dotfiles` at the wrapper. The base's out-of-store links and activation tools
currently use that exact base path.

The wrapper must provide an idempotent `sync-base-input` command that:

1. reads the exact locked revision of its base input;
2. refuses to continue if `~/.dotfiles` has local changes;
3. fetches and checks out that exact commit in detached state; and
4. proves `git -C ~/.dotfiles rev-parse HEAD` equals the lock revision.

Run that command before every wrapper build or switch. A wrapper lock update without the matching
base-checkout update is a failed preflight.

## Phase 2: inventory and compose the wrapper

Create a one-writer table in the private wrapper before moving files. At minimum, classify:

| Concern | Expected mechanism |
|---|---|
| SSH | `~/.ssh/config.d/*`, included before base `Host` blocks |
| Git | `~/.config/external-overlays/git/{extra,work}.inc` |
| tmux | `~/.config/external-overlays/tmux/*.conf` |
| zsh | uniquely named `~/.config/zsh/profile.d/*.zsh` fragments |
| Claude settings | lexical `~/.claude/settings.d/*.json` fragment |
| MCP | wrapper-owned `~/.config/mcp/machine/work.json` |
| Skills | one owner: structured skills overlay or direct files, never both |
| AeroSpace / Worktrunk | whole-file takeover of the base `mkDefault` target |
| Packages and hooks | `extraDarwinModules` / `extraHomeModules` |
| Secrets | externally administered vault/recipient and temporary render verification |

For each target, record the old writer, new writer, activation dependency, validation command, and
rollback source. Reject any row with two active writers.

The base work copies may remain tracked as rollback material during composition, but the generated
wrapper configuration must have only one active writer per target. Where the base currently has an
unconditional work-identity definition, land the narrow base change needed to yield or remove that
definition before activating the wrapper replacement.

## Phase 3: migrate secrets before the live switch

Migrate one consumer at a time:

1. provision the externally administered vault or recipient for every authorized operator;
2. store references/templates, never credential values, in the wrapper;
3. render to a temporary target outside the live path;
4. compare file presence, mode, ownership, structure, and consumer behavior without printing the
   value;
5. activate the new writer for that consumer and disable the base writer; and
6. retain the old ciphertext until the wrapper has passed the rollback and soak gates.

The wrapper bootstrap must acquire only wrapper-approved credentials. Do not reuse the base
`bootstrap.sh` secret step: it reads the personal `op://Private/dotfiles-age-key` item.

Before switching, evaluate the wrapper's Home Manager configuration and verify that no active work
secret points at `~/.config/age/keys.txt` unless an explicitly approved transitional exception is
documented. The final wrapper state has no such exception.

## Phase 4: build without switching

First validate the selected base revision as a canary:

```bash
cd "$HOME/.dotfiles"
nix flake check --no-build --all-systems
scripts/test-external-overlay-contract.sh
nix eval --raw '.#darwinConfigurations.work-mac.config.system.build.toplevel.drvPath'
nix build --no-link \
  '.#darwinConfigurations.work-mac.config.home-manager.users.carpenter.home.activationPackage'
```

Then, from the physical wrapper checkout:

```bash
just sync-base-input
nix flake check --no-build --all-systems
nix eval --raw '.#darwinConfigurations.work-wrapper.config.system.build.toplevel.drvPath'
nix build --no-link \
  '.#darwinConfigurations.work-wrapper.config.home-manager.users.carpenter.home.activationPackage'
nix build --no-link '.#darwinConfigurations.work-wrapper.config.system.build.toplevel'
```

Replace `just sync-base-input` and `work-wrapper` with the wrapper's actual command and unique host
name. The wrapper CI must run the same evaluation and activation-package build without personal
credentials.

Inspect the emitted Home Manager ownership before switching:

- [ ] base raw links resolve through the clean, lock-matched `~/.dotfiles` checkout;
- [ ] external raw links resolve through the wrapper's `files/` root;
- [ ] git and tmux fragments are under the isolated external-overlay tree;
- [ ] SSH include order is before all base `Host` blocks;
- [ ] MCP/skills overlays and whole-file takeovers have one writer;
- [ ] malformed structured fragments fail safely;
- [ ] secret derivations and logs contain no plaintext values;
- [ ] Homebrew's first-switch behavior is accepted: updates/upgrades are disabled and
  `cleanup = "none"` preserves unmanaged inventory pending an explicit, read-only
  `just brew-audit` review.

## Phase 5: perform the single live cutover

Run the wrapper-owned bootstrap from the physical wrapper checkout. It must verify CLT/Lix,
wrapper secret access, lock/base parity, and the unique host name before invoking the switch.

The essential switch is:

```bash
sudo darwin-rebuild switch --flake '<private-wrapper-path>#work-wrapper'
```

Then run the wrapper's network/SSH side-channel sync. Do not run the base `bootstrap.sh work-mac`,
base `rebuild.sh work-mac`, or `chezmoi apply` after the wrapper takes ownership.

Keep the terminal and existing applications open until verification finishes. Home Manager now
fails on pre-existing targets instead of moving them aside; resolve each ownership collision
explicitly before retrying.

## Phase 6: verify on hardware

The wrapper needs a `verify-live` command. It must fail unless all required checks pass:

- running `/run/current-system` equals the wrapper output;
- `system.configurationRevision` equals the wrapper revision, not merely the base revision;
- the base checkout is clean and exactly matches the wrapper lock;
- base and wrapper symlinks resolve into their assigned physical roots;
- a fresh shell loads, `rebuild` targets the physical wrapper root, and `ca` no longer invokes the
  base host;
- work environment and AWS override files exist with the expected owner/mode and contain no
  unresolved secret references;
- all externally owned work skills are present with correct file/script modes;
- AWS config generation succeeds and its outputs are structurally current;
- MCP and skills fan-out show no drift against the wrapper-owned overlays;
- SSH, Git, tmux, Claude settings, AeroSpace, Worktrunk, and work shell fragments behave as
  assigned in the one-writer table;
- AeroSpace, SketchyBar, and Borders run in the GUI launchd domain;
- the pre-cutover Homebrew formula/cask inventory has no unexplained removal;
- login shell and review-sensitive macOS defaults match the declaration; and
- no live symlink or generated state resolves into the old chezmoi source root.

Use the laptop normally, then perform one ordinary wrapper lock/config update and rerun the full
verifier. Do not extract base work ownership or clean chezmoi before that update cycle passes.

## Phase 7: exercise rollback

Exercise the Nix rollback while the old generation is still known:

```bash
sudo darwin-rebuild switch --rollback
```

Verify that the previous generation starts and the shell remains usable, then switch forward again
from the wrapper and rerun `verify-live`.

If no prior Nix generation exists or the Nix rollback is insufficient, the emergency userland
rollback is the archived chezmoi source revision plus the captured managed-path inventory. This is
the only point where running `chezmoi apply` again is valid, and only after deliberately abandoning
the wrapper generation. Do not mix live Nix/Home Manager ownership with an opportunistic chezmoi
apply.

## Phase 8: extract work ownership from the public base

After the wrapper switch, rollback exercise, and one update cycle are green:

1. remove migrated work files, overlays, secret declarations/ciphertexts, hooks, and package gates
   from the public base;
2. remove `work-mac` from `lib/machines.nix`, `hosts/`, and base bootstrap/rebuild detection;
3. remove capabilities and activation ordering that have no remaining base consumer;
4. update the wrapper's base pin and synchronize `~/.dotfiles` to it;
5. run every base and wrapper gate again; and
6. record the last base-managed generation and first fully wrapper-owned revision in the private
   runbook.

Do not delete the old ciphertext from all recoverable history until the external secret consumers
and rollback path have been accepted.

## Phase 9: chezmoi cleanup

Cleanup comes last. Never run `chezmoi purge`: it can remove targets now owned by Home Manager.

### 9.1 Prove chezmoi is inert

- [ ] `command -v chezmoi` is not used by any shell startup, launchd job, cron entry, or wrapper
  command.
- [ ] `rg` finds no active reference to the old source root in live shell/agent configuration.
- [ ] Every live symlink and generated-state path passes the wrapper ownership verifier.
- [ ] The exact old source revision is pushed or archived.

### 9.2 Archive the source and config recoverably

Use the captured source path, and move rather than delete:

```bash
cutover_state="<captured-state-directory-from-phase-0>"
cutover_stamp="$(date +%Y%m%d-%H%M%S)"
retired_root="$HOME/.Trash/chezmoi-retired-$cutover_stamp"
mkdir -p "$retired_root"

chezmoi_source="$(cat "$cutover_state/chezmoi-source-path.txt")"
case "$chezmoi_source" in
  "$HOME"/*) mv "$chezmoi_source" "$retired_root/source" ;;
  *) printf 'refusing unexpected chezmoi source: %s\n' "$chezmoi_source" >&2; exit 1 ;;
esac
```

Run the move from outside the chezmoi source directory. Before moving its config directory, handle
any legacy private age key explicitly. If `~/.config/chezmoi/key.txt` still exists, verify the
wrapper no longer needs it. If the approved replacement is another age identity, compare only
through a silent `cmp -s` and verify mode `0600`. Remove the exact legacy key path instead of
preserving another plaintext private-key copy in the retired archive. APFS copy-on-write means this
is reference removal, not a guaranteed forensic secure erase.

After handling that key, archive the remaining config:

```bash
if [ -d "$HOME/.config/chezmoi" ]; then
  mv "$HOME/.config/chezmoi" "$retired_root/config"
fi
```

If the final wrapper has no `age.secrets` using the personal identity, remove
`~/.config/age/keys.txt` from the work laptop as a separate, explicit secret-custody cleanup step.

### 9.3 Archive `*.chezmoi-bak` files

Use the pre-cutover managed inventory instead of scanning or deleting the entire home directory:

```bash
backup_archive="$cutover_state/chezmoi-backups"
mkdir -p "$backup_archive"

while IFS= read -r managed; do
  case "$managed" in
    /*) target="$managed" ;;
    *) target="$HOME/$managed" ;;
  esac
  candidate="${target}.chezmoi-bak"
  case "$candidate" in
    "$HOME"/*.chezmoi-bak)
      if [ -e "$candidate" ] || [ -L "$candidate" ]; then
        relative="${candidate#"$HOME"/}"
        mkdir -p "$backup_archive/$(dirname "$relative")"
        mv "$candidate" "$backup_archive/$relative"
      fi
      ;;
    *) printf 'skipping unsafe backup candidate: %s\n' "$candidate" >&2 ;;
  esac
done < "$cutover_state/chezmoi-managed.txt"
```

Rerun the wrapper verifier after moving the backups. Keep this archive through the rollback window;
delete it only after explicit acceptance.

### 9.4 Remove the chezmoi executable and stale state

Uninstall chezmoi with the package manager that installed it. For Homebrew:

```bash
if brew list --formula chezmoi >/dev/null 2>&1; then
  brew uninstall chezmoi
fi
```

Move any remaining chezmoi cache/state directories into the same retired archive rather than
blindly removing broad parents. Open a fresh shell and confirm `chezmoi` is absent, `rebuild`
targets the wrapper, and `verify-live` remains green.

## Completion gate

The migration is complete only when:

- the wrapper and base checks are green at pinned, matching revisions;
- the running system reports the wrapper revision;
- every managed target has one writer;
- externally administered secrets use no personal recipient;
- rollback was exercised successfully;
- one ordinary wrapper update cycle passed;
- the public base no longer owns the extracted work host/material;
- no live path depends on the retired chezmoi source; and
- chezmoi source, backups, executable, and stale state were cleaned in that order.
