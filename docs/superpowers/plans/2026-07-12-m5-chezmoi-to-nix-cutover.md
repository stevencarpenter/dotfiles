# m5: chezmoi → nix trial cutover (runbook)

> A **reversible, m5-only** cutover from the live chezmoi setup to the nix prototype on branch
> `m5`, with an explicit yes/no decision gate. work (m3) and lab (i9) are untouched — they keep
> running chezmoi from `main`. Nothing here merges to `main`.

**Date:** 2026-07-12 · **Branch:** `m5` · **Host config:** `personal-mac`

## 0. Invariants (do not violate)

- **Only m5.** Deploy this branch on m5 alone. Do **not** merge `m5` → `main`, and do **not** push
  to `main`. work/lab resolve their config from `main` (chezmoi) and must stay that way.
- **work m3 + lab i9 are frozen on chezmoi-`main`.** This cutover changes nothing on them. The
  tradeoff (accepted): while m5 is on nix, config edits you make on m5 land in this branch's
  `home/` and do **not** reach m3/i9 until they migrate or you backport. Don't camp here long.
- **Secrets at first switch still use agenix.** The age key is sourced from
  `op://Private/chezmoi-age-key` into `~/.config/chezmoi/key.txt` by `bootstrap.sh`. The `op://`
  Connect migration (SNUG-384 + the secrets plan) is a **later** step, not part of this cutover.
- **`main` is your backup.** The chezmoi source of truth is untouched on `main`; nothing is
  destroyed by this trial. Rollback re-asserts it.

## 1. Pre-flight (before any switch)

- [ ] **Confirm isolation.** `git branch --show-current` → `m5`. m3/i9 not touched.
- [ ] **Add the collision guard (REQUIRED — verified not set).** Without it the first switch
  aborts the instant home-manager wants to symlink a path chezmoi already owns
  (e.g. `~/.config/zsh/.zshrc`). Add to `flake.nix` in the home-manager block (currently lines
  54–59, beside `useGlobalPkgs`):

  ```nix
  home-manager.backupFileExtension = "chezmoi-bak";
  ```

  With this, home-manager renames each colliding file to `<name>.chezmoi-bak` instead of erroring —
  and those `.chezmoi-bak` files become part of your rollback material. Commit on branch `m5`.
- [ ] **Age key present.** `test -s ~/.config/chezmoi/key.txt` (bootstrap sources it from
  `op://Private/chezmoi-age-key`). Required for agenix decrypt at switch.
- [ ] **Determinate Nix installed** (or let `bootstrap.sh` install it).
- [ ] **Record current state for diffing/rollback.** From the chezmoi checkout
  (`~/.local/share/chezmoi`): `chezmoi managed > ~/chezmoi-managed-2026-07-12.txt`. Optionally
  confirm a Time Machine / backup ran. (Belt-and-suspenders; `main` already is the source backup.)

## 2. Cutover (on m5)

- [ ] **Stop running chezmoi on m5.** From here, nix owns the target symlinks; don't run `ca` /
  `chezmoi apply` on this box again during the trial.
- [ ] **First switch.** From *this* worktree:
  - Fresh Nix: `./bootstrap.sh personal-mac`
  - Nix already present: `./rebuild.sh personal-mac`

  This links `~/.dotfiles` → this repo, ensures the age key, and runs
  `darwin-rebuild switch --flake ~/.dotfiles#personal-mac`.
- [ ] **Expect during activation:** chezmoi-owned files backed up to `*.chezmoi-bak`; out-of-store
  symlinks created; agenix decrypts secrets; activation runs the sync hooks (mcp/skills) + tiling
  restart. Homebrew runs with `cleanup = "none"` → it uninstalls nothing.
- [ ] **`just sync`** (git externals + token-auditor — the network/SSH side channels).

## 3. On-hardware verification (SNUG-362 checklist + live-use gate)

Run immediately, then actually live on it for a few days before deciding.

- [ ] **Shell:** a fresh login loads z4h, the p10k prompt, and aliases; secret env vars resolve
  (`test -s ~/.config/zsh/.env`; spot-check an expected var is set).
- [ ] **Secrets files:** `test -s ~/.ssh/config` and it's `0600`; personal env present.
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
- [ ] Re-assert chezmoi from `main`: in `~/.local/share/chezmoi`, run `chezmoi apply`. This
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
- [ ] **Full nix removal (optional, clean slate):** `/nix/nix-installer uninstall` (Determinate
  uninstaller). Heavy — only if you want zero nix footprint.

**Why rollback is low-risk:** `main` is untouched, `cleanup=none` prevents brew destruction, and
home-manager backed up every file it replaced. The only genuinely one-way changes are cosmetic
macOS defaults and any nix-added brew casks — both harmless to leave.

## 6. Housekeeping (optional, when ready)

- **Remote rename** (publishes the 6 session commits, deletes the old remote branch):
  `git push origin -u m5 && git push origin --delete full-nix-darwin-dotfile-shape`
- **Worktree directory rename** (do when NOT working inside it — it changes the path):
  `git worktree move "$PWD" ~/.local/share/chezmoi-m5`
