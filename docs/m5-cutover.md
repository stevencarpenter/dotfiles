# M5 cutover runbook (DFM-52)

This runbook moves the personal MacBook from nix-darwin and Home Manager to dotfiles-manager.
Each step has a mode. `LIVE` writes to the machine. `CHECK` only reads. Run the steps in order.
Stop at the first unexpected output and use the rollback section.

Related files: `docs/m5-system-scripts.md`, `docs/package-mapping.md`, the "dotfiles-manager bundle"
section of `README.md`, and `docs/first-run.md` in the dotfiles-manager repository.

## 1. Prerequisites

1. CHECK. The manager is installed with `bootstrap.sh install` at a named commit of the
   `going-to-sleep` branch. Write the commit here before you start: `<full sha>`.
   Run `dotfiles-manager --version`. The output must show the semver and that commit. It must not contain `isolated:`.
2. CHECK. DFM-48 (hook identity, object merge, append, `settings.d`) and DFM-53 (bundle-declared source
   roots and excludes) are merged into the installed manager commit. Until DFM-53 is merged,
   `plan --root ~/.dotfiles` fails on ignored runtime files (`.codegraph`, `*/.venv`, a nested `.git`
   under `home/.config/tmux/plugins`). Do not start before that.
3. CHECK. This branch (`dfm-cutover`) is checked out at `~/.dotfiles`. Run
   `git -C ~/.dotfiles rev-parse --abbrev-ref HEAD` and `git -C ~/.dotfiles status --short`.
   The branch must be `dfm-cutover` and the tree must have no tracked changes.
4. CHECK. Homebrew and 1Password work: `brew --version`, `op whoami`.
5. CHECK. Close Claude Code, Codex and pi sessions other than the one you use for this runbook.
   The manager writes `~/.claude/settings.json`, and an open session can write it at the same time.

## 2. Back up

1. LIVE. Bind first, because `plan` needs a binding to list targets. Binding writes only the
   binding file and an empty state store:

   ```sh
   dotfiles-manager bind --profile ~/.dotfiles/dfm/profiles/personal-mac.toml --machine-id <id>
   ```

2. CHECK. List every plan target:

   ```sh
   dotfiles-manager plan --root ~/.dotfiles --json > /tmp/dfm-plan.json
   python3 -I -c 'import json;[print(o["path"]) for o in json.load(open("/tmp/dfm-plan.json"))["plan"]["operations"] if o.get("path")]' > /tmp/dfm-targets.txt
   wc -l /tmp/dfm-targets.txt
   ```

   The plan can show blockers at this point (the files in section 4). The target list is still complete.
3. LIVE. Write the archive. `tar` skips absent paths and prints a notice for each:

   ```sh
   tar -czf ~/dfm-cutover-backup-$(date +%Y%m%d).tgz -C "$HOME" \
     $(cat /tmp/dfm-targets.txt) \
     .claude/settings.json .codex/AGENTS.md .pi/agent/AGENTS.md \
     Library/LaunchAgents/com.user.maxfiles.plist Library/LaunchAgents/org.nixos.maxfiles.plist \
     .local/state/dotfiles-manager .config/dotfiles-manager 2>&1 | tee /tmp/dfm-backup.log
   ```

   `tar` stores a symlink as a link, not as the file it points to. The archive holds the Home
   Manager links as they are today.
4. CHECK. `tar -tzf ~/dfm-cutover-backup-*.tgz | wc -l` is not zero. Keep a second copy outside the home directory.
5. CHECK. Record the current nix generation for rollback: `darwin-rebuild --list-generations | tail -3`
   and `readlink /run/current-system`. Write both here: `<generation>`, `<store path>`.

## 3. Hand off from Home Manager

Pick one path. Path A is the declarative path. Path B is manual.

### Path A: final switch with `home.file` emptied

1. LIVE. In a Worktrunk worktree of `~/.dotfiles` on a branch other than `dfm-cutover`, make this
   change. It has not been evaluated or built, because the author of this runbook ran no nix command:
   - In `modules/home/default.nix`, remove the imports `./dotfiles.nix`, `./raw-dotfiles.nix`,
     `./tiling.nix`, `./dev-tools.nix` and `./ai-stack.nix`. Keep `shell.nix`, `packages.nix` and `sync-hooks.nix`.
   - In `hosts/personal-mac.nix`, remove the `home-manager.users.${user}.rawDotfiles.trees` block.
2. CHECK. Run `nix flake check --no-update-lock-file --no-build --all-systems` in that worktree. Do not go on if it fails.
3. LIVE. Run `./rebuild.sh personal-mac`. Home Manager removes the links it created in the old
   generation. It does not remove the regular files that activation scripts wrote:
   `~/.codex/AGENTS.md`, `~/.pi/agent/AGENTS.md` and `~/.claude/settings.json`.
4. CHECK. Run the dry run from Path B step 1. It must list 0 links.

### Path B: remove the links by hand

1. CHECK. Dry run. This lists every Home Manager link and removes nothing:

   ```sh
   for r in .config .claude .codex .pi .local .ssh .cursor .copilot .junie .agents; do
     find "$HOME/$r" -type l -not -path '*/node_modules/*' 2>/dev/null
   done > /tmp/dfm-links.txt
   find "$HOME" -maxdepth 1 -type l >> /tmp/dfm-links.txt
   while read -r l; do
     case "$(readlink "$l")" in /nix/store/*-home-manager-files/*) echo "$l";; esac
   done < /tmp/dfm-links.txt | sort > /tmp/dfm-hm-links.txt
   wc -l /tmp/dfm-hm-links.txt
   ```

   On 2026-10-11 this printed 124 lines on this machine: 116 links the bundle manages, 2 `.config/op`
   links the bundle also manages, 7 `.keep` seams that the bundle drops, and `.local/state/.keep`.
   The last one is an empty file that Home Manager itself creates. No file in this repository declares it.
   The bundle does not manage it. Read the list. A link that the bundle does not manage is not an
   error, but you must know why it exists.
2. LIVE. Remove the links. A directory link (for example `~/.config/nvim`) is removed as a link, not recursively:

   ```sh
   while read -r l; do rm "$l"; done < /tmp/dfm-hm-links.txt
   ```

   `rm` without `-r` cannot delete a real directory. A failure here means a path is not a link.
3. CHECK. Run the dry run again. It must list 0 links.

Neither path removes `/run/current-system` or the nix daemon. Those stay until section 12.

## 4. Fix what blocks the first apply

1. LIVE. `chmod 600 ~/.claude/settings.json`. The manager refuses a settings file open to group or others (`E_CONFLICT`).
2. LIVE. Move the assembled files aside with a dated suffix. They are regular files that the manager does not own yet:

   ```sh
   d=$(date +%Y%m%d)
   mv ~/.codex/AGENTS.md ~/.codex/AGENTS.md.pre-dfm-$d
   mv ~/.pi/agent/AGENTS.md ~/.pi/agent/AGENTS.md.pre-dfm-$d
   ```

   In the rehearsal, the new assembled files were byte-identical to these.
3. CHECK. `ls -l ~/.claude/settings.json` shows `-rw-------`.

## 5. Unload the old maxfiles agents

1. CHECK. `scripts/launch-agents.sh --check`. Expect `not loaded: org.carpenter.maxfiles`. On this
   machine it also reports `org.nixos.maxfiles` and `com.user.maxfiles` as loaded.
2. LIVE. Unload both old agents:

   ```sh
   launchctl bootout "gui/$(id -u)/org.nixos.maxfiles"
   launchctl bootout "gui/$(id -u)/com.user.maxfiles"
   ```

   If `bootout` prints "No such process", the agent was already unloaded. Go on.
3. LIVE. Remove the user-made plist: `rm ~/Library/LaunchAgents/com.user.maxfiles.plist`. The section 2 archive holds a copy.
4. LIVE. Remove `~/Library/LaunchAgents/org.nixos.maxfiles.plist` if it exists. It is a read-only
   file from nix-darwin: `rm -f` it.
5. The new agent is loaded in section 9, after apply links its plist.

## 6. Read the plan

1. CHECK. Plan and preview:

   ```sh
   dotfiles-manager plan --root ~/.dotfiles
   dotfiles-manager apply --root ~/.dotfiles --preview
   ```

   The plan must have 0 `blocked` lines. Expect about 120 operations: 117 links (the 116 from the
   rehearsal plus the maxfiles plist), 2 assemblies and the settings merge. The last line of `plan`
   is `plan digest: <64 hex>`.
2. CHECK. The preview prints the flags the real run needs. Expect one:
   `--allow-adopt 'core.claude-settings@.claude/settings.json'`. Any `--allow-disruptive` flag means
   the manager would delete an owned output. Stop and read it.
3. The owner approves in writing and names the digest: "Approved for apply on the M5: plan digest
   `<64 hex>`." The agent runs no LIVE step without this sentence.

## 7. Apply

1. LIVE. Apply the approved digest with the flags from the preview:

   ```sh
   dotfiles-manager apply --root ~/.dotfiles --yes-plan <digest> \
     --allow-adopt 'core.claude-settings@.claude/settings.json'
   ```

   The last line must be `result: ok`. `E_PLAN_STALE` means the machine changed after you read the plan.
   Run section 6 again.
2. CHECK. Run `plan` again and apply the new digest. The state changed, so the digest changes.
   The apply must print `updated=0` and `result: ok`.
3. CHECK. Compare the assembled files:

   ```sh
   cmp ~/.codex/AGENTS.md ~/.codex/AGENTS.md.pre-dfm-$d
   cmp ~/.pi/agent/AGENTS.md ~/.pi/agent/AGENTS.md.pre-dfm-$d
   ```

   A difference is not always an error. A fragment or body that changed since the last nix switch
   explains it. Read the `diff`.

## 8. Install packages

1. CHECK. `scripts/brew-sync.sh --check`. It reports the missing items. On 2026-10-11 the gap was 14
   items: 1 cask (`font-dejavu`) and 13 formulae (`mise`, `sevenzip`, `lefthook`, `trufflehog`, `checkov`,
   `hadolint`, `ffuf`, `testssl`, `gosec`, `cargo-audit`, `cargo-deny`, `bandit`, `pip-audit`).
2. LIVE. `scripts/brew-sync.sh`. It runs `brew bundle --no-upgrade` and pins sketchybar and borders.
3. The `Brewfile` marks only `crush`, `sketchybar` and `borders` with `trusted: true`. The AeroSpace
   cask trust is already granted on this machine (`~/.config/homebrew/trust.json` lists
   `nikitabobko/tap/aerospace` under `trustedcasks`). A fresh machine needs that entry or `trusted: true` in the `Brewfile`.
4. CHECK. `scripts/brew-sync.sh --check` exits 0.

## 9. Side channels, agents and system settings

1. LIVE. `scripts/sync-side-channels.sh`. It renders secrets with op-render, updates git sources and
   agents, installs token-auditor, and runs the MCP and skills sync. It needs an interactive terminal and `op signin`.
2. LIVE. `scripts/launch-agents.sh load`.
3. CHECK. `scripts/launch-agents.sh --check`. Expect `ok: org.carpenter.maxfiles loaded`.
4. CHECK. `scripts/login-shell.sh --check`. Expect `ok: UserShell = /bin/zsh`.
5. LIVE. `scripts/tiling-reload.sh`. It restarts the sketchybar service and reloads AeroSpace. The bar flickers once.
6. CHECK. `scripts/mac-defaults.sh --check`. Expect 33 lines, all `ok`. If a line is not `ok`, read it,
   then run `scripts/mac-defaults.sh` (LIVE, it restarts the Dock).
7. CHECK. `dotfiles-manager doctor --root ~/.dotfiles`. Expect exit 0. `D_PROBING_NOT_BUILT` is allowed.
8. CHECK. `dotfiles-manager state check`.

`just sync-dfm` and `just sync-dfm-apply <digest>` run sections 6 to 9 as one sequence. Use the manual steps for the first run.

## 10. Manual checks

Run each in a new terminal window unless the step says otherwise.

1. New shell: `exec zsh`. The prompt loads and `echo $EDITOR` prints `nvim`.
2. `readlink ~/.zshenv` prints `/Users/carpenter/.dotfiles/home/.zshenv`.
3. AeroSpace: the hotkeys work and `aerospace list-workspaces --all` runs.
4. SketchyBar: the bar shows workspaces. Hover the top edge: the native menu appears, then the bar returns.
5. Claude Code: start `claude`. `/status` shows the settings. Hooks run once: create a worktree and
   check that one directory appears. `/mcp` lists the servers.
6. Codex: start `codex`. It reads `~/.codex/AGENTS.md`.
7. pi: start `pi` and check that `AGENTS.md` loads.
8. tmux: start a session. The status bar and the Claude pane colors show.
9. git and jj: `git config --get user.email` and `jj config list --user | head`.
10. nvim: open `nvim`. LazyVim starts with no error. `git -C ~/.dotfiles status --short` shows no
    `lazy-lock.json` change that you did not make.

## 11. Rollback

Use the first level that fixes the problem.

1. Undo the links only. LIVE. Set `modules = []` in the profile, then run `plan`, `apply --preview`,
   and apply with the `--allow-disruptive` flags that the preview lists. This removes only the links
   the manager owns. The source files stay.
2. Restore the backup. LIVE. `tar -xzf ~/dfm-cutover-backup-<date>.tgz -C "$HOME"`. This restores the
   Home Manager links and the pre-cutover settings and assembled files.
3. Return to the previous nix generation. LIVE. Run `sudo darwin-rebuild switch --rollback`, or run
   `sudo /nix/var/nix/profiles/system-<N>-link/activate` with the generation recorded in section 2.
   Home Manager then relinks the files. If you used Path A, this brings back the old modules.
4. Reload the old agent. LIVE. `scripts/launch-agents.sh unload`, then
   `launchctl bootstrap "gui/$(id -u)" ~/Library/LaunchAgents/com.user.maxfiles.plist` (restore the file from the archive first).
5. CHECK. `readlink /run/current-system` equals the store path recorded in section 2.

## 12. Remove nix-darwin and Lix (after a soak week)

Do this only after at least seven days of daily use with no rollback. These steps remove the rollback
path in section 11, step 3. The commands come from the tools installed on this machine on 2026-10-11.
They were not run. Read each tool's `--help` before you run it.

1. CHECK. Confirm the soak: `dotfiles-manager doctor --root ~/.dotfiles` exits 0 and
   `scripts/brew-sync.sh --check` exits 0. Confirm that no tool you use resolves into `/nix/store`:
   `for t in git nvim tmux jq rg fd; do command -v $t; done`.
2. LIVE. Back up `/etc`:
   `sudo tar -czf ~/etc-before-nix-removal.tgz /etc/bashrc /etc/zshrc /etc/zshenv /etc/zprofile /etc/shells /etc/*.before-nix-darwin`.
3. LIVE. `sudo darwin-uninstaller`. It restores the `/etc` files that nix-darwin replaced.
4. CHECK. For each of `bashrc`, `shells`, `zprofile`, `zshenv` and `zshrc`: if
   `/etc/<name>.before-nix-darwin` still exists, run `sudo mv /etc/<name>.before-nix-darwin /etc/<name>`.
5. LIVE. Unload and remove the nix daemons:

   ```sh
   for p in org.nixos.nix-gc org.nixos.nix-optimise org.nixos.activate-system org.nixos.darwin-store org.nixos.nix-daemon systems.lix.nix-installer.nix-hook; do
     sudo launchctl bootout system /Library/LaunchDaemons/$p.plist 2>/dev/null
     sudo rm -f /Library/LaunchDaemons/$p.plist
   done
   ```

6. LIVE. Remove the Lix installation with its own uninstaller: `sudo /nix/nix-installer uninstall`.
   It reads `/nix/receipt.json`. Read its plan and answer the prompt yourself.
7. LIVE. Remove what the installer leaves: `sudo rm -f /run/current-system` and `sudo rm -rf /etc/profiles`
   (it holds `per-user`). Remove the `nix` line from `/etc/synthetic.conf` if it remains. Then reboot.
8. CHECK after the reboot:
   - `ls /nix` fails, and `command -v nix darwin-rebuild` prints nothing.
   - `launchctl list | rg -i nix` prints nothing, and `ls /Library/LaunchDaemons | rg -i nix` prints nothing.
   - `readlink /run/current-system` fails.
   - `dscl . -list /Users | rg -i nixbld` prints nothing.
   - `echo $PATH` has no `/nix` or `/run/current-system` entry.
   - `exec zsh`, then repeat section 10.
9. Delete `~/etc-before-nix-removal.tgz` and the section 2 archive when you no longer need them. The
   archive holds copies of dotfiles that can name secrets.
