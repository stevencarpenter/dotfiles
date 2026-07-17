# m5: live Nix cutover and promotion runbook

> `personal-mac` runs the Nix shape from branch `m5`. The canonical checkout is `~/.dotfiles`;
> the old local chezmoi checkout and deployed backups are retired after the live verification gate.
> `main` remains the remote archive candidate until the Nix shape has soaked long enough to make a
> deliberate promotion decision.

**Date:** 2026-07-12 · **Branch:** `m5` · **Host config:** `personal-mac`

## 0. Invariants (do not violate)

- **Only m5.** Deploy this branch on m5 alone. Do **not** merge `m5` → `main`, and do **not** push
  to `main`. The work Mac still resolves its config from chezmoi `main`.
- **work m3 + i9 are outside this cutover.** This cutover changes nothing on them. The
  tradeoff (accepted): while m5 is on nix, config edits you make on m5 land in this branch's
  `home/` and do **not** reach m3/i9 until they migrate or you backport. Don't camp here long.
- **Secrets at first switch now use `op-render`, not agenix (updated post-WS1).** WS1 (SNUG-386,
  PR #127) + PR #128 migrated m5's entire personal secret surface to `op inject`: `.personal.env`
  and `~/.ssh/config` render from `op://` templates via the `opRender` activation, and
  `ENABLE_TOOL_SEARCH` is now a plain `profile.d/common-env.zsh`. **The personal identity declares
  zero `age.secrets`, so the age key is vestigial on m5.** What the first switch DOES need is the
  **1Password CLI authenticated** — `opRender` checks `op whoami` and skips without blocking when
  signed out. Existing rendered files remain intact.
- **`main` is your backup.** The chezmoi source of truth is untouched on `main`; nothing is
  destroyed by this trial. Rollback re-asserts it.

## 1. Pre-flight (before any switch)

- [ ] **Confirm isolation.** `git branch --show-current` → `m5`. m3/i9 not touched.
- [x] **Collision guard installed.** The first switch used this Home Manager setting to back up
  pre-existing chezmoi targets instead of aborting:

  ```nix
  home-manager.backupFileExtension = "chezmoi-bak";
  ```

  The backups are removed only after the live verification gate passes.
- [ ] **1Password CLI authenticated when refreshing secrets.** `opRender` renders
  `.personal.env` + `~/.ssh/config` via `op inject`; when signed out it skips without blocking and
  preserves the last known-good files.
  (The age key at `~/.config/age/keys.txt`, sourced from `op://Private/chezmoi-age-key` by
  `bootstrap.sh`, is now only needed if any `age.secrets` remain — personal declares none, so it is
  vestigial on m5.)
- [ ] **Lix installed** (or let `bootstrap.sh` install it — it runs the Lix installer).
- [x] **Rollback source retained remotely.** Current chezmoi `main` remains on GitHub until the
  promotion decision; the active local checkout is no longer required after verification.

## 2. Cutover (on m5)

- [ ] **Stop running chezmoi on m5.** From here, nix owns the target symlinks; don't run `ca` /
  `chezmoi apply` on this box again during the trial.
- [ ] **First switch.** From *this* worktree:
  - Fresh Nix: `./bootstrap.sh personal-mac`
  - Nix already present: `./rebuild.sh personal-mac`

  This links `~/.dotfiles` → this repo, ensures the age key, and runs
  `darwin-rebuild switch --flake ~/.dotfiles#personal-mac`.
- [ ] **Expect during activation:** chezmoi-owned files backed up to `*.chezmoi-bak`; out-of-store
  symlinks created; **`opRender` renders `~/.config/zsh/.personal.env` + `~/.ssh/config` from
  `op://` when the CLI is authenticated**; activation runs the sync hooks
  (mcp/skills) + tiling restart. Homebrew runs with `cleanup = "none"` → it uninstalls nothing.
  (If 1Password is locked, `opRender` skips and leaves any existing secret files intact — the
  switch does not fail — but `.personal.env`/`~/.ssh/config` won't be (re)rendered until you rerun
  the switch with it unlocked.)
- [ ] **`just sync`** (git externals + token-auditor — the network/SSH side channels).

## 3. On-hardware verification (SNUG-362 checklist + live-use gate)

Run immediately, then actually live on it for a few days before deciding.

- [ ] **Shell:** a fresh login loads z4h, the p10k prompt, and aliases; `echo $ENABLE_TOOL_SEARCH`
  → `true` (from `profile.d/common-env.zsh`, not the retired `.env`); a personal secret resolves in
  a new shell (e.g. `echo ${OPENAI_API_KEY:+set}` → `set`).
- [ ] **op-rendered secret files:** `test -s ~/.config/zsh/.personal.env` and `test -s ~/.ssh/config`,
  both `0600`, and **no unresolved refs** (`! rg -q 'op://' ~/.config/zsh/.personal.env ~/.ssh/config`).
  Confirm `ssh i9` still resolves the host (rendered from `op://Homelab/I9/tailnet_hostname`).
- [ ] **Editors / mux:** nvim (LazyVim), tmux, ghostty all launch normally.
- [ ] **Tiling:** aerospace + sketchybar + borders running (personal identity).
- [ ] **macOS defaults — check the reviewer-NOTE keys on hardware:** menu-bar `ShowDate`
  (int-vs-string), four-finger trackpad gestures, dock hot corners. A wrong `ShowDate` is *silent* —
  verify the written plist, not just that the switch succeeded.
- [ ] **Login-shell pin:** `dscl . -read /Users/$USER UserShell` → `/bin/zsh` (confirms the
  unmanaged-user NOTE didn't silently no-op; if it did, add `users.knownUsers`).
- [ ] **Homebrew intact:** `brew list` shows your casks/brews (cleanup=none preserved them).
- [ ] **Tooling:** MCP sync ran (`~/.codex`/`~/.config/opencode` regenerated), atuin history works,
  `claade` runs.
- [ ] **Live-edit loop:** edit `~/.config/zsh/.zshrc` (a symlink into `~/.dotfiles`), open a new
  shell — change is immediate, no rebuild. This is the property the whole shape exists for.

## 4. Decision gate

- **YES — keep nix on m5.** Proceed to the **m3 migration** (its own sub-project) so work stops
  drifting on chezmoi-`main`. Do **not** merge `m5` → `main` until m3 is on nix *and* i9 has moved
  to the homelab/stow repo. Only then does nix become `main` and chezmoi retire.
- **NO — roll back.** Go to §5.

## 5. Rollback (honest asymmetry)

**Userland — fully reversible:**
- [ ] Fresh-clone the archived chezmoi `main`, then run `chezmoi apply`. This
  overwrites nix's out-of-store symlinks with chezmoi's files. (The `*.chezmoi-bak` backups are
  also on disk if you prefer a manual restore of any specific file.)
- [ ] Stop using nix on m5: don't run `rebuild` / `darwin-rebuild` again.

**System state — stickier; decide per item (most need no action):**
- [ ] **macOS defaults** nix wrote persist. Cosmetic, and chezmoi's `run_onchange` reasserts its own
  values on next `apply` anyway. Usually leave as-is.
- [ ] **launchd `maxfiles` agent:** if you want it gone,
  `launchctl bootout gui/$(id -u)/<label>` and remove the plist (chezmoi installs its own).
- [ ] **Homebrew:** `cleanup = "none"` meant nix uninstalled nothing; any casks/brews nix *added*
  remain. Leave them, or `brew uninstall` individually.
- [ ] **Full nix removal (optional, clean slate):** `/nix/nix-installer uninstall` (the Lix
  installer's uninstaller). Heavy — only if you want zero nix footprint.

**Why rollback is low-risk:** `main` is untouched, `cleanup=none` prevents brew destruction, and
home-manager backed up every file it replaced. The only genuinely one-way changes are cosmetic
macOS defaults and any nix-added brew casks — both harmless to leave.

## 6. Housekeeping (optional, when ready)

- ✅ **Remote rename — DONE.** `origin` now has only `refs/heads/m5`; the old
  `full-nix-darwin-dotfile-shape` branch is deleted.
- ✅ **Canonical checkout — DONE.** The live standalone checkout is `~/.dotfiles`.
- **Promotion, only after the soak decision:** preserve current remote `main` as a dated
  `archive/chezmoi-main-*` ref, then promote `m5` to `main`. Do not resolve the architectural
  conflict set by merging old chezmoi paths into the Nix tree.
