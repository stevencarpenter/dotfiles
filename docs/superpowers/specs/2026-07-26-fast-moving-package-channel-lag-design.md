# Fast-moving packages → per-package unstable escape hatch (design)

**Date:** 2026-07-26 · **Status:** approved design, pre-implementation · **Branch:** `main`

Adds a named, per-package escape hatch from the `nixpkgs-26.05-darwin` stable pin for CLI tools
whose upstream release cadence outruns the stable channel's backport window. Seeded with the six
measured laggards. Migrating the Homebrew fast-movers (`railway`, `crush`, `worktrunk`) into the
same mechanism is explicitly **out of scope** here and recorded as a follow-up in §7.

## 1. Context & problem

`flake.nix:8` pins `nixpkgs` to `github:NixOS/nixpkgs/nixpkgs-26.05-darwin`, and
`modules/home/packages.nix` draws every CLI tool from it. The stable line backports fixes but not
new upstream releases, so a tool that ships every few days drifts arbitrarily far behind while a
tool that ships a few times a year stays current.

The trigger was `mise` printing an upgrade warning on every invocation. Measured 2026-07-26,
installed store paths vs. upstream latest release:

| Tool | nixpkgs 26.05 | Upstream | Gap |
|---|---|---|---|
| **mise** | 2026.5.12 | 2026.7.13 | ~2 months, ~15 releases |
| **uv** | 0.11.21 | 0.11.32 | 11 patch releases |
| **fzf** | 0.72.0 | 0.74.1 | 2 minor |
| **lazygit** | 0.61.1 | 0.63.1 | 2 minor |
| **zoxide** | 0.9.9 | 0.10.0 | 1 minor |
| **ripgrep** | 15.1.0 | 15.2.0 | 1 minor |
| gh, yazi, neovim, delta, bat, fd, btop | — | — | current |

The distribution is the important part: **7 of 14 sampled tools are exactly current.** The lag is
not a general property of nixpkgs-stable — it concentrates in tools whose cadence the channel
structurally cannot track. This is a cadence mismatch, not a channel defect, so the fix should be
per-package rather than channel-wide.

Same measurement against `nixpkgs-unstable` — all six land at or within days of upstream:

| Tool | unstable | Upstream |
|---|---|---|
| mise | 2026.7.10 | 2026.7.13 |
| uv | 0.11.28 | 0.11.32 |
| fzf | 0.74.1 | 0.74.1 |
| lazygit | 0.63.1 | 0.63.1 |
| zoxide | 0.10.0 | 0.10.0 |
| ripgrep | 15.2.0 | 15.2.0 |

## 2. Goals & non-goals

**Goals**

- One named, editable list of packages that track unstable; adding a future fast-mover is a
  one-line edit.
- Everything not in that list keeps the 26.05 pin — literally, including transitive build inputs.
- No change to the LOCKED external-overlay contract (`docs/external-overlays.md` v1.0).
- Reproducibility preserved: the unstable input is locked in `flake.lock` like any other.

**Non-goals**

- Moving the whole package set to unstable. `nix-darwin` and `home-manager` are pinned to their
  `26.05` release branches and expect a matching `nixpkgs`; repointing the shared input would risk
  module/option mismatches for ~60 packages to fix problems in six.
- Migrating Homebrew-held tools into nix (see §7).
- Any change to the `mise` shim/PATH work landed earlier the same day.

## 3. Architecture

A second nixpkgs input, consumed by explicit selection rather than by overlay.

```
flake.nix
  inputs.nixpkgs           -> nixpkgs-26.05-darwin   (everything, as today)
  inputs.nixpkgs-unstable  -> nixpkgs-unstable       (NOT `follows` nixpkgs)
        │
        │ inputs is already in specialArgs / extraSpecialArgs
        ▼
modules/home/packages.nix
  fastMovingPackages = [ … ]                 <- the one editable list
  pkgsFresh          = import inputs.nixpkgs-unstable { inherit (pkgs) system; }
  home.packages      = stablePackages ++ map (n: pkgsFresh.${n}) fastMovingPackages
```

**Why explicit selection and not an overlay.** An overlay rewrites `pkgs.<name>` globally, so any
stable package that merely *depends* on `ripgrep` or `fzf` would also be rebuilt against the
unstable copy — costing binary-cache hits on packages that were never meant to change, and
quietly violating the "everything else stays on stable" guarantee. Explicit selection confines the
blast radius to exactly the six named derivations.

**Why the contract is untouched.** `flake.nix:57-60` threads `inputs` wholesale into both
`specialArgs` and `extraSpecialArgs`. A new flake input is therefore visible to every module
without altering the specialArgs *shape*, so the v1.0 seam does not change and no review round is
required. `modules/home/packages.nix` only needs `inputs` added to its argument list.

## 4. Components

### 4.1 `flake.nix`

```nix
# Escape hatch for tools whose release cadence outruns the stable channel's
# backport window (see modules/home/packages.nix). Deliberately does NOT
# `follows` nixpkgs — tracking a different channel is the entire point.
nixpkgs-unstable.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
```

The input must **also** be added to the `outputs` destructuring pattern. That pattern
(`inputs@{ self, nixpkgs, nix-darwin, home-manager, nix-homebrew, agenix }`) has no `...`, and Nix
attrset patterns are strict: a declared-but-unlisted input fails evaluation with *"called with
unexpected argument 'nixpkgs-unstable'"*. This is the single easiest step to get wrong.

No `.inputs.nixpkgs.follows` line — unlike `nix-darwin`/`home-manager`/`agenix`, this input has no
nixpkgs input of its own; it *is* nixpkgs.

### 4.2 `modules/home/packages.nix`

Takes `inputs`. Introduces a `let` block holding the allowlist, the second package set, and the
stable list (currently an inline literal, lifted to a binding so the assertion in §4.3 can inspect
it). The six names are **removed** from the stable literal — they now enter `home.packages` only
through the map.

The allowlist carries the measurement inline as a comment, with the date, so a future reader can
tell whether an entry is still justified rather than cargo-culting it.

No `nixpkgs.config` exists anywhere in this repo (verified by `rg`), so the second instantiation
needs only `system`; there is no `allowUnfree` or overlay stack to mirror.

### 4.3 Double-declaration assertion

A name in both lists yields two derivations shipping the same `bin/` entry, which surfaces as a
home-manager file collision at activation — loud, but with a message that points at the symptom.
An eval-time assertion filtering `fastMovingPackages` against the `pname` of each stable entry
turns it into a directive message, in the style of the `capsOk` assertion at `flake.nix:40-43`.

The assertion inspects the **fully assembled** stable set — the base literal *plus* every
`lib.optionals` block (`caps.gui`, `caps.dev` ×2, `identity == "work"`) — not just the base list.
All six current entries live in the base literal, but a future fast-mover added to a capability-gated
block must not slip past the guard. Note this means the assertion only sees the blocks active for
the host being evaluated; `nix flake check --all-systems` covers every host, so a collision gated
behind another machine's caps still fails CI.

### 4.4 `README.md`

The bucket table at `README.md:213` explains what stays in Homebrew and why. The row
`| railway, crush | … ship far faster than the stable channel tracks |` describes a constraint this
change removes. The table gets a note that a nix-side escape hatch now exists, and that those tools
remain in Homebrew pending the follow-up in §7 — so the rationale does not silently rot.

## 5. Testing & verification

| Gate | Command | Passing means |
|---|---|---|
| Eval | `nix flake check --no-build --all-systems` | Both host closures evaluate; assertion holds |
| **Cache** | `nix build --dry-run` on both closures | All six under *"will be fetched"*, not *"will be built"* |
| Format | `nix fmt --check` | Matches `nixfmt` |
| Hygiene | `pre-commit run --all-files` | Repo-wide checks |
| Post-switch | `mise --version` &c. on all six | Versions match §1's unstable column |

The cache gate is the load-bearing one, and it is the repo's own existing rule: `packages.nix:112-119`
already documents *"promote one here only after `nix build --dry-run` reports it under 'will be
fetched'"* for the Swift toolchain. nixpkgs-unstable is Hydra-built so substitution is expected,
but a `darwin-rebuild switch` that silently compiles `ripgrep` from source is the failure mode this
catches.

## 6. Risks

| Risk | Mitigation |
|---|---|
| Unstable ships a regression in one of the six | `flake.lock` pins a specific commit; roll back the lock entry. Blast radius is one package. |
| Second nixpkgs evaluation costs eval time/memory | One extra instantiation, no overlay stack. Accepted. |
| Cache miss → long source build | The `--dry-run` gate in §5 blocks the change until verified. |
| Tool declared in both lists | Eval-time assertion (§4.3). |
| Unstable input drifts stale | It is bumped by `nix flake update` like any input; the lock keeps it deterministic until then. |

## 7. Open items / follow-ups

- **Homebrew fast-movers → nix.** Deliberately deferred. On unstable, `crush` is 0.86.0
  (vs 0.70.0 on stable; upstream 0.87.0) and `railway` is 5.27.0 (upstream 5.28.1) — so the
  "ships faster than the channel tracks" rationale for keeping them in brew is obsolete once this
  lands. A brew→nix migration is a different class of change from a channel bump and deserves its
  own cache verification per package.
- **`worktrunk` is packaged in nixpkgs-unstable at 0.66.0.** `README.md` currently claims it has
  "no nixpkgs equivalent". That claim is false on unstable and should be corrected when the item
  above is picked up.
- **`mise` self-update warning.** `mise` warns about a newer release on every invocation. This
  change closes the gap to ~3 days, which should silence it in practice; if it persists, it is a
  mise-side setting, not a packaging problem.
