# Chezmoi → nix-darwin migration

A digest of the port from a chezmoi-managed dotfiles repo to a **nix-darwin + home-manager flake**,
in the "thin wrapper" shape (raw configs symlinked out-of-store; nix owns packages, defaults,
gating, orchestration). This document is the map: what each chezmoi mechanism became, what improved,
what got riskier, what was deliberately deferred, and how the port was verified.

The shape is modeled on [kunchenguid/dotfiles](https://github.com/kunchenguid/dotfiles).

## (a) Mechanism mapping

| Chezmoi mechanism | Nix home |
|---|---|
| `dot_config/…` source prefix | `home/.config/…` — real dotted name, symlinked out-of-store via `mkOutOfStoreSymlink` in `modules/home/dotfiles.nix` |
| `dot_claude/`, `private_dot_ssh/`, etc. | `home/.claude/`, `~/.ssh/config` (the SSH config is an agenix secret, not a raw symlink) |
| `executable_` prefix | file mode set where it matters (agenix `mode = "0700"` for skill scripts); raw symlinks inherit the tracked file's mode |
| `.tmpl` (Go template) — **structural** per-host diff | static per-host file selected by `identity`. e.g. `aerospace.toml.tmpl` → `home/.config/aerospace/aerospace.{personal,work}.toml`, chosen in `modules/home/tiling.nix` |
| `.tmpl` — **scalar** per-host value | nix-generated `home.file.<x>.text`. e.g. `sketchybar/machine.env.tmpl` → generated from `caps.sketchybar_workspace_badges` in `tiling.nix` |
| `.tmpl` — **assembled** (base + gated blocks) | split raw files merged by the tool. e.g. `mise/config.toml.tmpl` → `config.toml` + `conf.d/{dev,infra}.toml`, each linked only when its cap is on (`dev-tools.nix`); mise merges `conf.d/*.toml` |
| `.tmpl` — zero directives (rename only) | plain file. e.g. `git/config.tmpl` → `home/.config/git/config` |
| `modify_settings.json.tmpl` (chezmoi `modify_` script) | `home/.claude/settings-base.json` (invariant block) + a Nix-computed variant + a jq-merge `home.activation` entry in `modules/home/ai-stack.nix` (preserves Claude's in-tool edits + SessionStart-hook union) |
| `.chezmoiignore` gate (`hasPrefix` / `(index .machines .machine).<cap>`) | `lib.mkIf caps.<x>` / `lib.optionalAttrs (identity == "…")` in the module that owns the thing — one gate site per concern |
| `.chezmoidata/machines.toml` (capability table) | `lib/machines.nix`, threaded into modules via `specialArgs` / `extraSpecialArgs` as `{ inputs; hostName; user; caps; identity; }` |
| `.chezmoi.toml.tmpl` machine prompt | `bootstrap.sh` / `rebuild.sh` `detect_host` (LocalHostName → flake config), arg override, prompt fallback |
| `run_after_` hook (MCP/skills/aws/agents sync) | `home.activation` entry after `writeBoundary` in `modules/home/sync-hooks.nix` (bucket **B** below) |
| `run_onchange_configure-macos-defaults.sh` | declarative `system.defaults.*` (+ `CustomUserPreferences` fallback) in `modules/darwin/macos-defaults.nix` (bucket **A**) |
| `run_onchange_set-login-shell.sh` (chsh dance) | `users.users.<user>.shell = "/bin/zsh"` + `environment.shells` in `modules/darwin/core.nix` (bucket **A**) |
| `run_onchange_after_start-tiling-stack.sh` | `home.activation.startTilingStack` in `modules/home/tiling.nix` (bucket **B**) |
| `run_once_setup-macos.sh` (xcode CLT, first-run) | `bootstrap.sh` (bucket **C**) |
| `run_onchange_install-token-auditor.sh` | `just sync` (bucket **C**; pin in Justfile `TOKEN_AUDITOR_VERSION`) |
| `run_onchange` hash guards | **dropped** — nix re-runs are content-addressed; idempotent re-runs accepted |
| `.chezmoiexternal.toml.tmpl` (agent-registry SSH clone, tpm) | `just sync` (bucket **C**; needs network/SSH) |
| `~/Library/LaunchAgents/com.user.maxfiles.plist` | `launchd.user.agents.maxfiles` in `modules/darwin/core.nix` |
| `dot_config/homebrew/Brewfile.tmpl` | `modules/darwin/homebrew.nix` (nix-homebrew + nix-darwin `homebrew` module), caps-gated; pure CLI tools moved to `home.packages` |
| age encryption (chezmoi `encrypted_` + `[age]` key) | **agenix, carry-verbatim** — same identity at `~/.config/chezmoi/key.txt`, same ciphertext blobs, `modules/home/secrets.nix` |

### The hook bucket rule

Every `run_` hook was sorted into one of three buckets:

- **A — declarative.** State nix can express directly: macOS defaults, login shell, launchd agents.
  Becomes a `system.defaults.*` / `launchd.*` / `users.users.*` option. No script survives.
- **B — offline + fast + idempotent.** Working-tree fan-out that must run every switch but needs no
  network/sudo: MCP sync, skills sync, AWS config gen, agent installer, tiling-stack restart.
  Becomes a `home.activation` entry after `writeBoundary`, using the nix-store `uv`/`python314`,
  wrapped `|| true` so it warns-but-never-fails the switch.
- **C — network / SSH / sudo / one-time.** Anything a reproducible switch must not silently depend
  on: git externals (SSH), token-auditor install, xcode CLT, rustup, the first switch itself.
  Becomes `just sync` / `just bootstrap`.

| Hook (chezmoi) | Bucket | Nix home |
|---|---|---|
| `run_after_sync-mcp` | B | `sync-hooks.nix` `mcpSync` (`caps.mcp`) |
| `run_after_sync-skills` | B | `sync-hooks.nix` `skillsSync` (`caps.skills`, `--repo-root $HOME/.dotfiles`) |
| `run_after_sync-aws-config` | B | `sync-hooks.nix` `awsConfigGen` (`caps.aws_sso`) |
| `run_after_sync-agents` | B | `sync-hooks.nix` `agentsInstall` (`caps.agents`; warns if clone missing → `just sync`) |
| `configure-macos-defaults` | A | `macos-defaults.nix` |
| `set-login-shell` | A | `core.nix` (`users.users.<user>.shell`) |
| `after_start-tiling-stack` | B | `tiling.nix` `startTilingStack` (`caps.tiling`) |
| `install-token-auditor` | C | `Justfile` `sync` |
| `.chezmoiexternal` (agent-registry, tpm) | C | `Justfile` `sync` |
| `setup-macos`, first switch, rustup | C | `bootstrap.sh` |

## (b) What got better

- **Sticky-negation is gone.** Chezmoi's `.chezmoiignore` couldn't reliably *un*-ignore a file once
  a machine-type flag changed, and it can't gate scripts at all (a script had to be a `.tmpl` whose
  body no-ops). In nix, a gate is a pure boolean at eval time: flip a cap in `lib/machines.nix` and
  the next switch adds or removes the thing with no stale-state class.
- **`run_onchange` hash guards are free.** Nix derivations and `home.activation` are
  content-addressed by construction — no `.chezmoiscripts` hash-comment bookkeeping to keep a script
  from re-running. The port simply dropped those guards; idempotent re-runs are accepted.
- **macOS defaults, login shell, and launchd are declarative.** `defaults write` loops became typed
  `system.defaults.*` options (with `CustomUserPreferences` for the untyped keys); the chsh dance
  became `users.users.<user>.shell`; the maxfiles plist became `launchd.user.agents`. These are now
  reviewable in one place and can't drift from an imperative script.
- **One gate site per concern.** A capability is enforced in exactly the module that owns the thing,
  and `nix flake check` fails evaluation if a gate references an undefined cap — a whole class of
  "defined-but-unwired capability" silent bugs is now a build error.
- **The thin-wrapper edit loop is preserved.** Raw configs stay live-editable (out-of-store
  symlinks), so the port kept chezmoi's best property — "edit a config, it's immediately live" —
  while moving packages/state under nix.

## (c) What got worse or riskier

- **Rebuild needs `sudo`.** `chezmoi apply` ran as the user; `darwin-rebuild switch` needs root to
  write system state. Routine config edits still need no rebuild, but any package/defaults change is
  now a privileged operation.
- **Activation ordering is subtle.** home-manager activation is a DAG around `writeBoundary`. The
  port relies on agenix's secret installation (`entryBefore "writeBoundary"`) landing decrypted work
  skills *before* `skillsSync` (`entryAfter "writeBoundary"`) GCs the skills dir. This ordering is
  documented in `secrets.nix` / `sync-hooks.nix` but is a real invariant a future edit could break.
- **Nix learning curve.** The repo is now Nix expressions, specialArgs threading, and the
  home-manager/nix-darwin option surface — a steeper on-ramp than chezmoi's prefix conventions for
  anyone (including future-owner) making changes.
- **x86_64-darwin sunset.** `lab-mac` is Intel. nixpkgs ends Intel-darwin support with the **26.05**
  channel this flake pins. When the flake rolls past 26.05, lab-mac's `system` must move to Apple
  Silicon or the host be retired.
- **Secrets are plaintext-on-disk after decrypt.** agenix decrypts to a user-owned path outside the
  store and symlinks to the target — the *store* stays safe (only ciphertext enters it), but the
  decrypted secret sits on disk mode 0400/0600, same as chezmoi's decrypted output. A single
  long-lived age identity is shared by all three machines including the weaker-posture lab-mac; this
  is an accepted limitation of the agenix bridge, not something the port solved (see
  `secrets/README.md`).

## (d) Deferred work

Explicitly scoped OUT of the port; none blocks a switch today.

1. **One-time re-encryption to agenix-native recipients (hygiene only).** Blobs were produced by
   plain `age -e -r` via chezmoi, not the `agenix` CLI. They decrypt identically; re-encrypting via
   `agenix -e` just buys a clean edit loop. See `secrets/README.md`.
2. **opnix / `op://` end-state (the actual blast-radius fix).** Replace `age.secrets.<name>` entries
   with `op read op://…` (or opnix) item-by-item, per the 2026-07-02 work-decoupling plan, starting
   with one low-risk personal secret. agenix and `op://` secrets can coexist during migration.
3. **Homebrew cleanup graduation.** `modules/darwin/homebrew.nix` runs `cleanup = "none"` so the
   first switch won't uninstall un-listed brew packages while the inventory is audited. Graduate to
   `"uninstall"` once the brew lists are confirmed complete. Never `"zap"`.
4. **First real switch is untested on hardware.** Only Linux-container *evaluation* was run (see
   below) — no darwin closure has actually been built or activated on a Mac yet. The macos-defaults
   and homebrew modules carry reviewer NOTEs for keys that need on-hardware verification against the
   pinned nix-darwin release (e.g. `menuExtraClock.ShowDate` int-vs-string, trackpad four-finger
   gesture keys, unmanaged-user `shell` pin).
5. **Repo-level Claude skills are still chezmoi-flavored.** `.claude/skills/` in this repo (e.g.
   `chezmoi-verify`, `machine-capability-audit`, `dotfiles-secret-authoring`) still describe chezmoi
   mechanics and target `.chezmoi*` paths. They need a nix-flavored rewrite (or retirement). The
   chezmoi-native `machine-capability-audit` pre-commit hook was already dropped;
   `.pre-commit-config.yaml` notes the deferred nix-flavored successor.

## (e) Verification evidence

- **All three `darwinConfigurations` evaluate.** `darwinConfigurations.{personal-mac,work-mac,
  lab-mac}.system.drvPath` were forced on a `nixos/nix` container. Nix evaluation is
  platform-independent (only *building* a darwin closure needs a Mac), so an all-hosts eval on Linux
  is a valid structural gate — it exercises every module, option, and gate, including lab-mac's
  x86_64-darwin row.
- **`flake.lock` is committed.** Inputs are pinned; `nix flake check --no-build` in CI
  (`.github/workflows/nix-flake-check.yml`, `macos-latest`) re-evaluates every output on each change.
- **One fix applied during the port.** The Dock hot-corner `wvous-*-modifier` keys are not typed
  nix-darwin options; they were moved from the `dock` submodule (which rejected them) into
  `system.defaults.CustomUserPreferences."com.apple.dock"` in `macos-defaults.nix`, matching the
  original script's `modifier = 0` (none).

## (f) Path to first switch

Tracked in Linear as [SNUG-362](https://linear.app/snugmarina/issue/SNUG-362) (label: `dotfiles`).

The port is complete *as a shape*: all 293 tracked files are accounted for (140 raw dotfiles →
`home/`, 30 age blobs → `secrets/`, 12 `.tmpl` templates resolved, 10 hooks ported, machinery
deleted), and every host evaluates. The honest gap is that **evaluates cleanly ≠ switches
cleanly** — evaluation type-checks the whole module tree but cannot exercise Homebrew activation,
launchd, macOS `defaults` acceptance, or agenix's runtime decrypt. Rollout order:

1. **personal-mac first** — it is the machine that can be babysat. `./bootstrap.sh`, then walk the
   on-hardware checklist in SNUG-362 (defaults edge-case keys, unmanaged-user shell pin, homebrew
   activation with `cleanup = "none"`, agenix decrypt, the four sync-hook activations, tiling
   restart), then `just sync`.
2. **work-mac** once personal-mac proves out.
3. **lab-mac last, pending a decision**: nixpkgs 26.05 is the last release supporting
   x86_64-darwin, so the Intel lab machine's runway under this paradigm is finite — stay pinned,
   move it to Linux/NixOS, or keep it on chezmoi.

Until step 1 has run, treat every reviewer `NOTE:` comment in `modules/darwin/` as an open
question, and do not merge this branch to main.
