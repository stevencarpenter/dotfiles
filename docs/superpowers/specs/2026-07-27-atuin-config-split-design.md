# Atuin config split → popup + history filters on every machine (design)

**Date:** 2026-07-27 · **Status:** approved design, pre-implementation · **Branch:** `main`

Splits `home/.config/atuin/config.toml` into a syncing and a non-syncing variant so the tmux
search popup and the `history_filter` redaction list deploy on **every** machine, while
`sync_address` stays gated on `caps.atuin`. Also fixes a latent cache-key bug in `zcached` that
would otherwise make the change appear to do nothing. Pinning the atuin binary itself (today an
unmanaged upstream `cargo-dist` install under `~/.atuin/bin`) is explicitly **out of scope** and
recorded as a follow-up in §7.

## 1. Context & problem

Reported symptom: on a machine with `caps.atuin = false`, pressing <kbd>↑</kbd> does not open
atuin's floating search window; where the capability is true, it does. The difference predates the
chezmoi → nix port.

`modules/home/dotfiles.nix:149-153` read the capability as "deploy the config file at all":

```nix
(lib.optionalAttrs caps.atuin (mkLinks [
  ".config/atuin/config.toml"
]))
```

So machines with the capability off had **no `~/.config/atuin/config.toml`**. `atuin init zsh`
reads that file at init time and bakes the tmux decision into the generated script. Diffing the
generated init with the repo config against the same command under an empty `ATUIN_CONFIG_DIR`
gives a one-line delta:

```diff
- export ATUIN_TMUX_POPUP=false          # ← capability off
+ export ATUIN_TMUX_POPUP_WIDTH='80%'    # ← capability on
+ export ATUIN_TMUX_POPUP_HEIGHT='60%'
```

The popup code is present in both. It is gated at keypress time by `__atuin_tmux_popup_check`,
whose first two tests are `[[ -n "${TMUX-}" ]]` and
`[[ "${ATUIN_TMUX_POPUP:-true}" != "false" ]]`. With the capability off the second fails, so
`__atuin_search_cmd` takes the else branch and renders `atuin search -i` inline in the current
pane. Up-arrow is still bound to atuin either way — `bindkey -M emacs '^[[A' atuin-up-search` is
emitted identically. It simply doesn't float.

The same code path serves <kbd>Ctrl</kbd>+<kbd>R</kbd>: `_atuin_up_search` calls
`_atuin_search --shell-up-key-binding`, which calls `__atuin_search_cmd`. The old config comment
claiming the setting is "for interactive Ctrl-R search" understated its reach.

### 1.1 The larger problem the symptom exposed

The capability is about **sync**. Gating the whole file on it also withheld two things that have
nothing to do with sync:

1. **`history_filter`** — the redaction patterns that keep matching commands out of the history
   database. Not a sync concern; it should apply wherever history is recorded at all.
2. **`[tmux] enabled`** — the reported symptom.

The general principle, which is the durable lesson here: **an absent config file is never a
neutral state.** It is a silent opt-in to the tool's own defaults, and those defaults are chosen
for the tool's median user, not for this repo. `atuin default-config` shows what "no file" actually
selects:

```toml
# auto_sync = true
# sync_address = "https://api.atuin.sh"
```

That is the *public* Atuin server, with automatic sync on. Nothing about omitting a file is
conservative.

### 1.2 Prior art in this repo

`modules/home/tiling.nix` already encodes the decision rule for per-machine config variance
(`tiling.nix:24-30`): **structural** diffs become two full static files selected at eval time
(`aerospace.{personal,work}.toml`); **scalar** diffs become a small nix-generated `.text`
(`sketchybar/machine.env`). `dotfiles.nix:158-161` names the general case — *"whole-file override
seam for tools without native include support"*. Atuin belongs to that class: `config.toml` is a
single flat file with **no include or import mechanism**.

## 2. Approaches considered

**A. Two static files selected by capability — chosen.** Raw, live-editable, mirrors the
aerospace precedent. Cost: `history_filter` is duplicated, so drift is possible; mitigated by a
CI parity test (§5), which turns the risk into a build failure.

**B. One shared file + a capability-gated env override.** Atuin honors env-var config overrides —
the `config` crate's env source, prefix `ATUIN`, `__` for nesting. Verified empirically, since this
is undocumented in `atuin default-config`:

```
$ ATUIN_CONFIG_DIR=<empty> atuin config get -r sync_address        → https://api.atuin.sh
$ ATUIN_SYNC_ADDRESS=https://example.test  … config get -r sync_address → https://example.test
$ ATUIN_AUTO_SYNC=false                    … config get -r auto_sync    → false
```

Zero duplication, and the fail direction is benign. Rejected because it splits the description of
a machine's behavior across two files and rests a security-adjacent gate on undocumented behavior.

**Rejected outright: one file carrying `sync_address`, env-disabled where sync is unwanted.** A
guard must be the default state, not an override. Anything that needs `profile.d` to have been
sourced in order to *stay* safe fails open. Only the opposite direction — override to *become*
permissive — is acceptable here.

**C. Nix-generated from a shared base.** `builtins.readFile` a shared base plus a
capability-dependent stanza. Single-sources the filter with no new test, but the deployed file
lands in the nix store, so it stops being live-editable and every filter edit needs a rebuild.
Rejected: this repo's central property is that raw configs are live.

## 3. File layout

Two raw files under `home/.config/atuin/`, named for the capability rather than any identity so a
future machine flips one boolean instead of adding a third file.

`config.sync.toml` (`caps.atuin = true`) carries `sync_address`, the shared `history_filter`
block, and `[tmux] enabled = true`.

`config.local.toml` (`caps.atuin = false`) carries `auto_sync = false`, **no** `sync_address`, the
same `history_filter` block, and the same `[tmux] enabled = true`.

Both `history_filter` arrays are wrapped in sentinel comments:

```toml
# --- BEGIN history_filter (parity-checked against the twin variant) ---
history_filter = [ … ]
# --- END history_filter ---
```

so the parity test is a `sed`-range extraction rather than a TOML parse.

`auto_sync = false` and the absent `sync_address` are deliberate as a pair, per §1.1: omitting the
address alone would leave the public server configured.

## 4. Nix wiring

`modules/home/dotfiles.nix` — the block stops being `lib.optionalAttrs`; the file now deploys
everywhere and the capability selects only *which* variant:

```nix
{
  ".config/atuin/config.toml".source = lib.mkDefault (
    link ".config/atuin/config.${if caps.atuin then "sync" else "local"}.toml"
  );
}
```

`lib.mkDefault` matches the aerospace precedent at `tiling.nix:28` and the override seam at
`dotfiles.nix:158-161`, leaving room for an external overlay to outrank it.
`scripts/test-external-overlay-contract.sh` must still pass.

The capability's comment in `lib/machines.nix` and the row in `README.md:73` are reworded: the
capability means "sync history to the self-hosted server", which is what it always claimed.

## 5. Drift guard

`scripts/test-atuin-filter-parity.sh`, in the style of `test-sketchybar-badge-wiring.sh`
(`bash`, `set -euo pipefail`, `repo_root` from `BASH_SOURCE`), asserting:

- the two `history_filter` sentinel blocks are byte-identical (print both on failure)
- `history_filter` is actually **assigned** in both files, with at least 5 patterns — parity alone
  passes when the array is deleted from both files in lockstep, which is the failure mode that
  matters most
- both files set `enabled = true` **inside the `[tmux]` table** — scoped, not a substring match.
  An `enabled = true` at top level or under `[daemon]`/`[dotfiles]` reproduces the original bug
  verbatim, and atuin accepts unknown top-level keys silently, so the regression would be invisible
  in the tool as well as in CI
- `config.local.toml` assigns top-level `auto_sync = false` and **no** top-level `sync_address`
- `config.sync.toml` assigns top-level `sync_address = "https://logbook.snugmarina.org"`
- the two variants differ in byte size — see §6 on why identical sizes could defeat the cache stamp

Assertions are table-aware and split on `=` rather than pattern-matching `key[[:space:]]*=`: in
glob syntax `*` is a wildcard, not a repetition quantifier, so that pattern demands at least one
space and silently rejects the valid TOML `key=value`.

Wired into `.github/workflows/dotfiles-hygiene-ci.yml` alongside the existing test steps, and
added to the exec'd-by-path list in `scripts/test-exec-bits.sh`.

## 6. Cache invalidation

`zcached` (`home/.config/zsh/lib/eval-cache.zsh:26`) keys its cache on the **binary's** mtime+size
only. A config-only change therefore does not invalidate
`~/.cache/zsh-eval-cache/atuin-init.zsh`, so after a rebuild a machine would keep sourcing an init
script that exports `ATUIN_TMUX_POPUP=false`. The fix would appear to do nothing.

This is a latent bug in the helper, not an atuin quirk: any cached `<tool> init` whose output
derives from a config file has it. Atuin is simply the first such caller — `brew shellenv`,
`zoxide init` and `wt config shell init` genuinely depend only on their binaries.

Fix: `zcached` accepts repeatable `-k <path>` flags naming additional stamp inputs.

```zsh
# Usage: zcached [-k <path>]... <cache-name> <binary-path> <command...>
zcached() {
  local -a extra=()
  while [[ ${1-} == -k ]]; do
    [[ -n ${2-} ]] || { print -u2 "zcached: -k requires a path"; return 2 }
    extra+=("$2")
    shift 2
  done
  local name=${1-} bin=${2-}
  shift 2 2>/dev/null || return 2
  [[ -x $bin ]] || return 0
  …
  local -a inputs=("$bin" "${extra[@]}")
  local -A st
  local stamp="#" p
  zmodload -F zsh/stat b:zstat 2>/dev/null
  for p in "${inputs[@]}"; do
    zstat -H st -- "$p" 2>/dev/null || st=(mtime 0 size 0)
    stamp+=" ${st[mtime]}:${st[size]}"
  done
```

Three properties worth stating explicitly:

- **Single-input callers keep a byte-identical stamp.** The loop yields `# <mtime>:<size>` for one
  input, exactly today's format, so `brew-shellenv` / `zoxide-init` / `wt-shell-init` do not
  needlessly refork. Only `atuin-init` gains a second field, so only it regenerates. **The
  transition is self-healing — no manual `rm -rf ~/.cache/zsh-eval-cache` step.**
- **A missing extra path stamps as `0:0` rather than bailing.** `zstat` failure already falls back
  to `(mtime 0 size 0)`; the `[[ -x $bin ]] || return 0` guard still applies to the binary alone.
  A not-yet-deployed config must not silently disable caching.
- **A valueless trailing `-k` must bail, not loop.** zsh's `shift 2` *fails without shifting* when
  `$# < 2`, so the obvious `while [[ $1 == -k ]]; do …; shift 2; done` spins forever on
  `zcached -k`. Since this runs from `.zshrc`, that is an interactive shell recoverable only via
  `zsh -f`. The loop guards on `[[ -z ${2-} ]]` and returns 2 with a message. `${1-}` also keeps a
  zero-arg call from dying under `setopt nounset` (not set in this repo today — cheap insurance).

Alternatives considered for the interface: a caller-set `zcached_extra` array (rejected — the
one-shot reset never fires when the caller's `command -v` guard short-circuits, leaking the paths
into the *next* `zcached` call), and positional stamp paths terminated by `--` (rejected — a
breaking change to all four call sites whose failure mode, forgetting `--`, silently caches an
empty script). With the arity guard above, the flag form fails loudly at the call site it was
edited in; the other two fail silently elsewhere. Without that guard the flag form was the *worst*
of the three. Worth remembering that an interface's failure mode is a property of its
implementation, not of its shape.

Call site, `home/.config/zsh/.zshrc:594`:

```zsh
command -v atuin >/dev/null 2>&1 &&
  zcached -k "${XDG_CONFIG_HOME:-$HOME/.config}/atuin/config.toml" \
    atuin-init "$(command -v atuin)" atuin init zsh
```

### 6.1 Rollout order hazard (hit during implementation)

Deleting `home/.config/atuin/config.toml` while the live symlink still points at it does **not**
leave the machine configless — it leaves a dangling link, and the next `atuin` invocation of any
kind writes atuin's full 371-line default config **into the repo** at that path, mode 0600.
Observed twice within minutes on 2026-07-27 before the chain was broken.

The link chain is `~/.config/atuin/config.toml` → `/nix/store/…-home-manager-files/…` → the repo
file, so atuin follows it all the way home.

Correct order on any machine: **rebuild first** (repointing the link at the new variant), then
remove the old file — or, if the file is already gone, repoint the link by hand as a stopgap
before touching atuin again:

```bash
ln -sfn ~/.dotfiles/home/.config/atuin/config.sync.toml ~/.config/atuin/config.toml
```

`./rebuild.sh` supersedes the stopgap. This hazard applies to any out-of-store-symlinked config
whose tool writes a default on read — worth remembering beyond atuin.

## 7. Out of scope / follow-ups

- **Pinning the atuin binary.** It is installed by the upstream `cargo-dist` script into
  `~/.atuin/bin` and is managed by neither nix nor Homebrew, so versions drift freely between
  machines. If a machine reports a materially older version, that is a *second*, independent cause
  of the reported symptom and needs its own fix.
- **`ATUIN_BIND_UP_ARROW` / `ATUIN_BIND_CTRL_R`.** Present in the binary's env surface; not used
  by this repo. Noted only so a future investigation of "up-arrow does nothing" has the list.

## 8. Verification

Repo-level, runs anywhere:

```bash
scripts/test-atuin-filter-parity.sh
scripts/test-exec-bits.sh
scripts/test-external-overlay-contract.sh
nix flake check --no-build --all-systems
pre-commit run --all-files
```

After `./rebuild.sh` on a machine with `caps.atuin = true`: `~/.config/atuin/config.toml` resolves
to `config.sync.toml`; `atuin config get -r sync_address` → `https://logbook.snugmarina.org`;
up-arrow opens the popup inside tmux.

After a rebuild on a machine with `caps.atuin = false`, in a **fresh** shell:

```bash
readlink ~/.config/atuin/config.toml                       # → …/config.local.toml
atuin config get -r auto_sync                              # → false
head -1 ~/.cache/zsh-eval-cache/atuin-init.zsh             # → two stamp fields, not one
rg ATUIN_TMUX_POPUP ~/.cache/zsh-eval-cache/atuin-init.zsh # → only *_WIDTH / *_HEIGHT
```

then press <kbd>↑</kbd> inside tmux and confirm the popup.
