# M5 cutover runbook (DFM-52)

This runbook moves the personal MacBook from nix-darwin and Home Manager to dotfiles-manager.
Each step has a mode. `LIVE` writes to the machine. `CHECK` only reads. Run the steps in order.
Stop at the first unexpected output and use the rollback section.

Related files: `docs/m5-system-scripts.md`, `docs/package-mapping.md`, the "dotfiles-manager bundle"
section of `README.md`, and `docs/first-run.md` in the dotfiles-manager repository.

## 1. Prerequisites

1. LIVE. Place the pinned Rust toolchain before `bootstrap.sh install`. The install needs it under the
   manager data directory, and refuses to build without it. The copy costs 1.6 GB. `~/.rustup` does not
   depend on nix: rustup comes through mise, which `scripts/brew-sync.sh` installs from Homebrew.

   ```sh
   mkdir -p -m 700 ~/.local/share/dotfiles-manager/toolchains
   cp -Rp ~/.rustup/toolchains/1.98.1-aarch64-apple-darwin ~/.local/share/dotfiles-manager/toolchains/1.98.1
   ```

   The directories must be real directories that you own.
   CHECK. The digest is path-relative, so the copy matches the original:

   ```sh
   sh scripts/bootstrap.sh toolchain-digest --dir ~/.local/share/dotfiles-manager/toolchains/1.98.1
   ```

   It must print `afc5eb67d9c2b331a5a64f779e8243e544235c19ca7f4131a1e14eeb126c3c5e`. That value must equal
   `[manager].toolchain_tree_sha256` in `dotfiles-manager.lock` of the commit you install. Run the script
   from a checkout of that commit.
2. CHECK. The manager is installed with `bootstrap.sh install` at a named commit of the
   `going-to-sleep` branch: `c253cb9e1fdc02688fc33ee115e12ae3ab19c450` (DFM-58 Codex comment fixes, PRs #42
   to #44, on top of the DFM-57 review fix wave) or later. It carries `dotfiles-manager.lock` (since 266fef4, DFM-56) and is the commit to install;
   the file fingerprint domain and the publish mechanism changed in DFM-57, so an older commit must not be
   used. A later commit is acceptable only after its own fresh-clone gate passed and it is named in
   approval 1.
   Run `dotfiles-manager --version`. The output must show the semver and that commit. It must not contain `isolated:`.
3. CHECK. DFM-48 (hook identity, object merge, append, `settings.d`) and DFM-53 (bundle-declared source
   roots and excludes) are merged into the installed manager commit. Until DFM-53 is merged,
   `plan --root ~/.dotfiles` fails on ignored runtime files (`.codegraph`, `*/.venv`, a nested `.git`
   under `home/.config/tmux/plugins`). Do not start before that. Commit 55d2d4e also holds the
   `directory = true` key that this branch sets on its 47 directory links (a directory source without it
   is `E_MANIFEST_INVALID`), the `E_PLATFORM_MISMATCH` check and the canonical HOME check.
   Commit e35aa3a also records every source directory in the tree digest, rechecks each link source just
   before it publishes (`E_PLAN_STALE` if the checkout changed after the plan), refuses sibling names that
   differ only by case, and validates `~/.config` and `~/.config/dotfiles-manager` in `bootstrap.sh`.
   Rehearsal 5 (2026-10-11, a test-isolation build of e35aa3a, an isolated HOME with the Home Manager
   links removed, the assembled files moved aside and `settings.json` at mode 600): `plan` showed 0
   blocked and 159 operations (117 links, 39 `mkdir`, 1 take, 2 writes). The 120 non-`mkdir` paths match
   rehearsals 3 and 4. `apply` with the one `--allow-adopt` flag gave `result: ok`, and the second apply
   gave `current=120`. `doctor` and `state check` exited 0. Plan digest of the first plan:
   `6ad717fc95645ebfc283d8f50e23e7ae384504ff5df03af7807de24479364ef2`. The digest depends on the HOME
   path and the machine state, so the live digest differs. `bootstrap.sh install` was not rehearsed: only
   the `DFM_BOOTSTRAP_TEST=1` hooks redirect HOME, and install needs a placed toolchain and a lock.
   Rehearsal 6 (2026-10-12, manager ba745e7, same setup): `bootstrap.sh install` was rehearsed this time,
   in the isolated HOME with the toolchain clone from step 1 and the `DFM_BOOTSTRAP_TEST=1` redirect: the
   digest matched the lock, the install exited 0, and `--version` printed the commit with no isolation
   marker. Cargo warns `stripping debug info with rust-objcopy failed: Library not loaded:
   @rpath/libLLVM.dylib`; the original rustup toolchain gives the same warning (rust-objcopy's rpath does
   not reach `lib/libLLVM.dylib`), the binary is installed unstripped and works, so expect the warning live.
   `plan` showed 0 blocked and 157 operations (117 links, 37 `mkdir`, 1 take, 2 writes); the two missing
   `mkdir` operations are `.local/bin` and `.local/share`, which the install had created. The 120 other
   paths equal rehearsal 5. `apply` with the one `--allow-adopt` flag gave `updated=157` and `result: ok`,
   the second apply gave `current=120`, `doctor` (`ok=136`), `status` and `state check` exited 0, and the
   assembled files were byte-identical. Plan digest of the first plan:
   `c3a80dd32d37fe452453bcfa8e0b1f11a06789c1ef08746ff3e2a82f37a759ce`.
   Rehearsal 7 (2026-10-12, manager dfa6001, an empty isolated HOME with only the toolchain clone placed):
   `bootstrap.sh install --commit dfa6001...` exited 0 in 57 s (the digest matched the lock, `--version`
   printed the commit with no isolation marker, binary sha256 `7fb50a23...`); this time the strip warning
   read `rust-objcopy failed: signal: 6 (SIGABRT)`, with the same unstripped result. `plan` showed 0
   blocked and 169 operations (117 links, 50 `mkdir`, 2 writes); the 117 link paths are identical to
   rehearsal 6, and the extra `mkdir` and the missing take come from the empty HOME (no existing
   `settings.json` to adopt, no assembled files to move aside). `apply` with the `--allow-adopt` flag from
   rehearsal 6 was refused (`E_USAGE ... names no adoption in this plan`, nothing written), and `apply`
   without the flag gave `result: ok` with `updated=169`. `doctor` and `status` reported ok=136, `state
   check` exited 0 (journal 338 entries). Since DFM-58 `bootstrap.sh install` refuses a checkout with a
   non-empty `.git/info/attributes`, a `core.attributesFile` or any `filter.*` git config
   (`E_SOURCE_UNTRUSTED`); the manager checkout used here had none.
   Rehearsal 8 (2026-10-12, manager c253cb9, same empty isolated HOME setup): `bootstrap.sh toolchain-digest`
   printed the lock value, `install --commit c253cb9...` exited 0 (binary sha256 `12029553...`), `plan`
   showed 0 blocked and 169 operations with the same 117 link paths, `apply` gave `result: ok` with
   `updated=169`, the second `apply` gave `current=120`, `doctor` and `status` ok=136, `state check` exit 0.
   c253cb9 adds one refusal to `bootstrap.sh`: a password-database home that contains Unicode whitespace
   or a C1 control is `E_HOME_MISMATCH`, the same rule the installed command applies.
   Rehearsal 9 (2026-10-12, a test-isolation build of c253cb9, this branch at eab63cb): the 119 target
   paths that exist in the live HOME (116 Home Manager links, `settings.json` and the two assembled files)
   were copied with `rsync -a --relative` into an isolated HOME. Sections 2 to 4 ran in the copy: an
   archive of the 119 paths, Path B (the 116 links removed), `chmod 600` and the files moved aside.
   `plan` showed 0 blocked and 122 operations (117 links, 2 creates, 1 update, 2 `mkdir`); the preview
   asked for the one `--allow-adopt` flag; `apply` gave `result: ok`, the second apply `current=120`,
   `doctor` and `status` ok=136, `state check` exit 0, and the assembled files were byte-identical. Plan
   digest of the first plan: `c3d8f5404b000a8ad7b903cfe73fb7100257c98cc011c9967d5ff258a529c8f4`.
   The merged `settings.json` held the hippo and routing SessionStart hooks twice. The live file spells
   them as `/Users/carpenter/...`, and the manager counts the absolute HOME path as `${HOME}/` only when
   HOME is that path; a second copy with the path rewritten to its own HOME had no duplicate. On the live
   apply, check in section 10 that each SessionStart hook appears once. The `--check` scripts against this
   machine: `mac-defaults` 33 ok, `login-shell` and `tiling-reload` ok, `launch-agents` exit 1 (the two old
   agents, section 5), `brew-sync` exit 1 with the 14 missing items of section 8, `hooks-sync` wrote
   nothing. Deselect test: with `tiling` removed from the profile, the preview listed 7
   `--allow-disruptive` flags, `apply` removed exactly those 7 links and nothing else, and restoring the
   7 paths from the archive brought back the Home Manager links; `doctor` then had 0 errors.
4. CHECK. This branch (`dfm-cutover`) is checked out at `~/.dotfiles`. Run
   `git -C ~/.dotfiles rev-parse --abbrev-ref HEAD` and `git -C ~/.dotfiles status --short`.
   The branch must be `dfm-cutover` and the tree must have no tracked changes.
5. CHECK. Homebrew and 1Password work: `brew --version`, `op whoami`.
6. CHECK. Close Claude Code, Codex and pi sessions other than the one you use for this runbook.
   The manager writes `~/.claude/settings.json`, and an open session can write it at the same time.
7. LIVE. Make a private work directory. Every temporary file in this runbook lives in it. If you open a new
   terminal, set `w` again to the printed path:

   ```sh
   w=$(mktemp -d "${TMPDIR:-/tmp}/dfm-cutover.XXXXXX"); echo "$w"
   ```

8. Approval 1, in writing, before section 2: "Approved to begin the M5 handoff. Backup archive:
   `<path>`. Handoff path: `<A or B>`." The agent runs no LIVE step in sections 2 to 5 without this
   sentence. Approval 2 (the plan digest) comes in section 6.

## 2. Back up

1. LIVE. Bind first, because `plan` needs a binding to list targets. Binding writes only the
   binding file and an empty state store:

   ```sh
   dotfiles-manager bind --profile ~/.dotfiles/dfm/profiles/personal-mac.toml --machine-id <id>
   ```

2. CHECK. List every plan target. The plan can show blockers at this point (the files in section 4).
   The target list is still complete:

   ```sh
   dotfiles-manager plan --root ~/.dotfiles --json > "$w/plan.json"
   python3 -I -c 'import json,sys;[print(o["path"]) for o in json.load(open(sys.argv[1]))["plan"]["operations"] if o.get("path")]' "$w/plan.json" > "$w/targets.txt"
   wc -l "$w/targets.txt"
   ```

3. CHECK. List every Home Manager link. This lists them and removes nothing. The archive in step 5 holds
   this list and the links themselves, and Path B removes exactly this list:

   ```sh
   for r in .config .claude .codex .pi .local .ssh .cursor .copilot .junie .agents; do
     find "$HOME/$r" -type l -not -path '*/node_modules/*' 2>/dev/null
   done > "$w/links.txt"
   find "$HOME" -maxdepth 1 -type l >> "$w/links.txt"
   while read -r l; do
     case "$(readlink "$l")" in /nix/store/*-home-manager-files/*) echo "$l";; esac
   done < "$w/links.txt" | sort > "$w/hm-links.txt"
   sed "s#^$HOME/##" "$w/hm-links.txt" > "$w/hm-links-rel.txt"
   wc -l "$w/hm-links.txt"
   ```

   On 2026-10-11 this printed 124 lines on this machine: 116 links the bundle manages, 2 `.config/op`
   links the bundle also manages, 7 `.keep` seams that the bundle drops, and `.local/state/.keep`.
   The last one is an empty file that Home Manager itself creates. No file in this repository declares it.
   The bundle does not manage it. Read the list. A link that the bundle does not manage is not an
   error, but you must know why it exists.
4. CHECK. Record the current macOS defaults, for the rollback table: `scripts/mac-defaults.sh --check > "$w/defaults-before.txt"`.
5. LIVE. Write the archive. `tar` skips absent paths and prints a notice for each. It stores a symlink as
   a link, not as the file it points to, so the archive holds the Home Manager links as they are today:

   ```sh
   arch="$HOME/dfm-cutover-backup-$(date +%Y%m%d).tgz"
   { cat "$w/targets.txt" "$w/hm-links-rel.txt"
     printf '%s\n' .claude/settings.json .codex/AGENTS.md .pi/agent/AGENTS.md \
       Library/LaunchAgents/com.user.maxfiles.plist Library/LaunchAgents/org.nixos.maxfiles.plist \
       .local/state/dotfiles-manager .config/dotfiles-manager
   } | sort -u > "$w/backup-paths.txt"
   tar -czf "$arch" -C "$HOME" -T "$w/backup-paths.txt" \
     -C / "${w#/}/hm-links.txt" "${w#/}/defaults-before.txt" 2>&1 | tee "$w/backup.log"
   ```

   Use one `-T` file: `bsdtar` ignores all but the last `-T` option.
6. CHECK. The archive holds the link list and a Home Manager link:
   `tar -tzf "$arch" | wc -l` is not zero, `tar -tzf "$arch" | rg -c 'hm-links.txt'` prints 1, and
   `tar -tzf "$arch" | rg -c '^\.local/state/\.keep$'` prints 1. Copy the archive to a place outside the home directory.
7. CHECK. Record the current nix generation for rollback: `darwin-rebuild --list-generations | tail -3`
   and `readlink /run/current-system`. Write both here: `<generation>`, `<store path>`.

## 3. Hand off from Home Manager

Pick one path. Path A is the declarative path. Path B is manual.

### Path A: final switch with `home.file` emptied

Path A is for `personal-mac` only. It edits shared modules, so the branch must never merge. The
switch also recreates `org.nixos.maxfiles`, because `modules/darwin/core.nix` (line 104) still
declares `launchd.user.agents.maxfiles`. Run section 5 after the switch.

1. LIVE. In a Worktrunk worktree of `~/.dotfiles` on a branch other than `dfm-cutover`, make this
   change. It has not been evaluated or built, because the author of this runbook ran no nix command:
   - In `modules/home/default.nix`, remove the imports `./dotfiles.nix`, `./raw-dotfiles.nix`,
     `./tiling.nix`, `./dev-tools.nix` and `./ai-stack.nix`. Keep `shell.nix`, `packages.nix` and `sync-hooks.nix`.
   - In `hosts/personal-mac.nix`, remove the `home-manager.users.${user}.rawDotfiles.trees` block.
2. CHECK. Run `nix flake check --no-update-lock-file --no-build --all-systems` in that worktree. Do not go on if it fails.
3. LIVE. Run `./rebuild.sh personal-mac`. Home Manager removes the links it created in the old
   generation. It does not remove the regular files that activation scripts wrote:
   `~/.codex/AGENTS.md`, `~/.pi/agent/AGENTS.md` and `~/.claude/settings.json`.
4. CHECK. Run step 3 of section 2 again, with `$w/links2.txt` and `$w/hm-links2.txt` as the output names. The final file must have 0 lines.

### Path B: remove the links by hand

1. CHECK. The list in `$w/hm-links.txt` is in the archive:
   `tar -xzOf "$arch" "${w#/}/hm-links.txt" | cmp - "$w/hm-links.txt"` prints nothing.
2. LIVE. Remove the links, reading the list from the archive. A directory link (for example
   `~/.config/nvim`) is removed as a link, not recursively:

   ```sh
   tar -xzOf "$arch" "${w#/}/hm-links.txt" | while read -r l; do rm "$l"; done
   ```

   `rm` without `-r` cannot delete a real directory. A failure here means a path is not a link.
3. CHECK. Repeat step 3 of section 2 with `$w/links2.txt` and `$w/hm-links2.txt` as the output names.
   The final file must have 0 lines.

Neither path removes `/run/current-system` or the nix daemon. Those stay until section 12.

## 4. Fix what blocks the first apply

1. LIVE. `chmod 600 ~/.claude/settings.json`. The manager refuses a settings file open to group or others (`E_CONFLICT`).
2. LIVE. Move the assembled files aside with a dated suffix. They are regular files that the manager does not own yet:

   ```sh
   d=$(date +%Y%m%d); echo "$d" > "$w/date"
   mv ~/.codex/AGENTS.md ~/.codex/AGENTS.md.pre-dfm-$d
   mv ~/.pi/agent/AGENTS.md ~/.pi/agent/AGENTS.md.pre-dfm-$d
   ```

   In the rehearsal, the new assembled files were byte-identical to these. Section 7 reads `d` again.
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

### Abort before approval 2

Use this if you stop after section 3, 4 or 5 and do not approve a plan digest.

1. LIVE. Restore the files: `tar -xzf "$arch" -C "$HOME"`. For Path B this recreates every removed
   Home Manager link, both maxfiles plists and the original settings and assembled files.
2. LIVE. For Path A, return to the previous generation with the branch you used before the Path A edit:
   `DFM_ALLOW_NIX=1 ./rebuild.sh personal-mac`. Home Manager then relinks the files. Run it only after
   `$HOME/.codex/AGENTS.md.pre-dfm-*` and the other moved files are back in place (step 1).
3. LIVE. Reload the old agents:
   `launchctl bootstrap "gui/$(id -u)" ~/Library/LaunchAgents/com.user.maxfiles.plist` and, if the
   file exists, the same for `org.nixos.maxfiles.plist`.
4. CHECK. `scripts/launch-agents.sh --check` lists the old agents as loaded. `readlink ~/.zshenv`
   prints a `/nix/store` path. The manager binding stays. `just sync` and `just rebuild` refuse to run
   while it exists, so set `DFM_ALLOW_NIX=1` for any nix command until you decide again.

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
3. Approval 2, in writing, names the digest: "Approved for apply on the M5: plan digest `<64 hex>`."
   The agent runs no apply without this sentence.

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
3. CHECK. Compare the assembled files. Set `d` to the date from section 4 (`d=$(cat "$w/date")`):

   ```sh
   d=$(cat "$w/date")
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

1. LIVE. `scripts/hooks-sync.sh`. It runs the MCP sync, the skills sync and the Codex hippo hook merge.
   These were Home Manager activation hooks. Run `scripts/hooks-sync.sh --check` first: it prints the
   commands and writes nothing. Each step warns and continues on failure.
2. LIVE. `scripts/sync-side-channels.sh`. It renders secrets with op-render, updates git sources and
   agents, installs token-auditor, the gh-axi skill and the fantasy-sports agents. It does not run the MCP
   or skills sync (step 1 does). It needs an interactive terminal and `op signin`.
3. LIVE. `scripts/launch-agents.sh load`. The plist is a symlink into the checkout. Whether launchd
   accepts a symlinked plist is unverified, and this step shows it. If `bootstrap` fails, replace
   the link with a copy: `rm ~/Library/LaunchAgents/org.carpenter.maxfiles.plist`, then
   `cp ~/.dotfiles/home/Library/LaunchAgents/org.carpenter.maxfiles.plist ~/Library/LaunchAgents/`,
   load it again, and remove the `library-launchagents-org-carpenter-maxfiles-plist` resource from
   `dfm-module-core.toml` so the next plan does not link it.
4. CHECK. `scripts/launch-agents.sh --check`. Expect `ok: org.carpenter.maxfiles loaded`.
5. CHECK. `scripts/login-shell.sh --check`. Expect `ok: UserShell = /bin/zsh`.
6. LIVE. `scripts/tiling-reload.sh`. It restarts the sketchybar service and reloads AeroSpace. The bar flickers once.
7. CHECK. `scripts/mac-defaults.sh --check`. Expect 33 lines, all `ok`. If a line is not `ok`, read it,
   then run `scripts/mac-defaults.sh` (LIVE, it restarts the Dock).
8. CHECK. `dotfiles-manager doctor --root ~/.dotfiles`. Expect exit 0. `D_PROBING_NOT_BUILT` is allowed.
9. CHECK. `dotfiles-manager state check`.

`just sync-dfm` and `just sync-dfm-apply <digest>` run sections 6 and 7 and steps 1 to 9 of this section as one
sequence. `just sync-dfm` writes the approval flags to `~/.local/state/dfm-cutover/allow.txt` (directory mode 0700, or `$DFM_ALLOW_DIR`). The apply recipe refuses a file that is a link or not yours.
`just sync-dfm-apply` rejects a digest that is not 64 hex characters, and it continues after a
`tiling-reload.sh` or `mac-defaults.sh --check` failure. Use the manual steps for the first run.

After the cutover, `just sync` and `just rebuild` refuse to run while the manager binding exists
(`~/.config/dotfiles-manager/machine.toml`). They would recreate `org.nixos.maxfiles` and the Home Manager
links. Set `DFM_ALLOW_NIX=1` only for a rollback.

### Home Manager activation hooks: coverage

`scripts/hooks-sync.sh` ports the hooks that no manager resource covers. The table classifies every
`home.activation` entry under `modules/home` (verified 2026-10-11).

| Hook (source) | Coverage on this branch |
| --- | --- |
| `mcpSync` (`sync-hooks.nix`) | Ported: `scripts/hooks-sync.sh` |
| `skillsSync` (`sync-hooks.nix`) | Ported: `scripts/hooks-sync.sh` |
| `codexHooksMerge` (`dotfiles.nix`) | Ported: `scripts/hooks-sync.sh` |
| `claudeSettingsMerge` (`ai-stack.nix`) | Manager resource: the Claude settings merge in `dfm-module-core.toml` |
| `codexAgentsAssemble`, `piAgentsAssemble` (`dotfiles.nix`) | Manager resources: `codex-agents` and the pi assembly in `dfm-module-core.toml` |
| `fantasySportsSync` (`sync-hooks.nix`) | Existing script: `sync-side-channels.sh` runs `install-fantasy-sports.sh` |
| `opRenderStaleCheck` (`sync-hooks.nix`) | Existing script: `sync-side-channels.sh` runs op-render itself, which refreshes the secrets |
| `startTilingStack` (`tiling.nix`) | Existing script: `scripts/tiling-reload.sh` (section 9) |
| `checkLinkParents` (`raw-dotfiles.nix`) | Dropped: it guards Home Manager link writes only. The manager does not use Home Manager links |
| `onFilesChange`, `copyApps`, `setupLaunchAgents` | Not declared under `modules/home`; they are nix-darwin and Home Manager built-ins. Dropped with nix |

## 10. Manual checks

Run each in a new terminal window unless the step says otherwise.

1. New shell: `exec zsh`. The prompt loads and `echo $EDITOR` prints `nvim`. `zsh -c 'echo $EDITOR'` also prints `nvim`.
   GUI apps that launchd starts do not read `~/.zshenv`, so they have no `EDITOR`. nix-darwin set it system-wide.
2. `readlink ~/.zshenv` prints `/Users/carpenter/.dotfiles/home/.zshenv`.
3. AeroSpace: the hotkeys work and `aerospace list-workspaces --all` runs.
4. SketchyBar: the bar shows workspaces. Hover the top edge: the native menu appears, then the bar returns.
5. Claude Code: start `claude`. `/status` shows the settings. Hooks run once: create a worktree and
   check that one directory appears. `/mcp` lists the servers.
   Each SessionStart hook is present once. The check reads the matcher and the command with the home
   spelling made one form, so `/Users/carpenter/x` and `"${HOME}/x"` count as the same hook. It prints nothing:

   ```sh
   jq -r '.hooks.SessionStart[] | (.matcher // "") as $m | .hooks[].command | gsub("\""; "")
     | sub("^(\\$HOME|\\$\\{HOME\\}|/Users/carpenter)"; "~") | "\($m) \(.)"' ~/.claude/settings.json | sort | uniq -d
   ```

   Before the apply it printed nothing on this machine. In rehearsal 9 it printed the two duplicated hooks.
6. Codex: start `codex`. It reads `~/.codex/AGENTS.md`.
7. pi: start `pi` and check that `AGENTS.md` loads.
8. tmux: start a session. The status bar and the Claude pane colors show.
9. git and jj: `git config --get user.email` and `jj config list --user | head`.
10. nvim: open `nvim`. LazyVim starts with no error. `git -C ~/.dotfiles status --short` shows no
    `lazy-lock.json` change that you did not make.

## 11. Rollback

Use the first level that fixes the problem. Level 3 works only after level 1 has removed the manager's
links, because Home Manager aborts when a file exists where it wants to place a link.

1. Undo the links only. LIVE. Set `modules = []` in the profile, then run `plan`, `apply --preview`,
   and apply with the `--allow-disruptive` flags that the preview lists. This removes only the links
   the manager owns. The source files stay.
2. Restore the backup. LIVE. `tar -xzf "$arch" -C "$HOME"`. This restores the Home Manager links and the
   pre-cutover settings and assembled files. Links that the manager created and the archive does not hold
   stay, so run level 1 first if you want a clean state.
3. Return to the previous nix generation. LIVE. After level 1, run `DFM_ALLOW_NIX=1 sudo darwin-rebuild switch --rollback`,
   or `sudo /nix/var/nix/profiles/system-<N>-link/activate` with the generation recorded in section 2.
   Home Manager then relinks the files. If you used Path A, this brings back the old modules.
4. Reload the old agent. LIVE. `scripts/launch-agents.sh unload`, then
   `launchctl bootstrap "gui/$(id -u)" ~/Library/LaunchAgents/com.user.maxfiles.plist` (restore the file from the archive first).
5. CHECK. `readlink /run/current-system` equals the store path recorded in section 2.

No level undoes the following. Each has an undo command or is accepted:

| Change | Undo or decision |
| --- | --- |
| `brew bundle` installs (14 items on 2026-10-11) | Accepted. They do not conflict with nix. To remove one: `brew uninstall <name>`. |
| `brew pin` on `sketchybar` and `borders` | `brew unpin sketchybar borders`. |
| macOS defaults written by `scripts/mac-defaults.sh` | Compare with `defaults-before.txt` from the archive and run `defaults write` for each changed key. Nix-darwin writes the same values on the next switch. |
| Side-channel and hook outputs (op-render files, git sources, agents, token-auditor, MCP and skills sync, `~/.codex/hooks.json` merge) | Accepted. The old `just sync` regenerates them. |
| Toolchain copy in `~/.local/share/dotfiles-manager/toolchains/1.98.1` (1.6 GB) | `bootstrap.sh uninstall` removes the PATH link, `versions/`, `current` and the build directories, but its documentation says it leaves toolchains, state and the binding. Remove the copy yourself with `rm -rf ~/.local/share/dotfiles-manager/toolchains/1.98.1`, or the whole data directory with `rm -rf ~/.local/share/dotfiles-manager` when you also drop the state. |
| `org.carpenter.maxfiles` loaded | `scripts/launch-agents.sh unload`. |
| Login shell | `scripts/login-shell.sh --set` writes `/bin/zsh`. Nix set the same value, so nothing changes. |

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
