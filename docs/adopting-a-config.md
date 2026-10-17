# Adopting a tool's config into the dotfiles

You install a tool, test-drive it for a while, and decide to keep it. This is the
procedure for promoting its ad-hoc config (and the tool itself) into managed dotfiles so
it reproduces on every machine.

This repo uses **checkout symlinks**: the deployed file points to the
repo file (`~/.config/foo` → `~/.dotfiles/home/.config/foo`). Edits need no apply.
An existing real file at the target path blocks the plan (`E_CONFLICT`); you move it aside
before planning.

## When an apply is required

- **Raw config content:** editing an *already-linked* file under `home/` needs no apply.
- **Adding a new file/path:** the manager must create the symlink. Needs `just sync-dfm`
  and `just sync-dfm-apply <digest>`.
- **Packages:** a `Brewfile` edit takes effect at the next `scripts/brew-sync.sh` run, which
  `sync-dfm-apply` includes. A mise edit takes effect at the next `mise install`.

**Adoption requires an apply** because it adds a new `[[resources]]` link.
Subsequent edits to the linked file need no apply.

## Collision handling

The planner refuses a real file or directory at a managed target: the plan shows the path as
`blocked … E_CONFLICT`, `just sync-dfm` stops there, and no flag overrides it. Before you plan,
verify the repository copy, then move the original aside
(`mv ~/.config/foo/config ~/.config/foo/config.pre-dfm`). Keep that backup until the apply and
the tool both check out, then delete it.

`--allow-adopt '<id>'` covers one case only: the live path already is the exact symlink the
plan would create (made by stow or by hand) and the manager does not own it yet. The plan
shows it as `adopt`, and `just sync-dfm` writes the flag for `just sync-dfm-apply`.

## Procedure

1. **Declare installation and update ownership.** A fresh machine must be able to install
   the tool through the owning package manager or an idempotent setup command.
   - Formula, cask or font → `Brewfile`.
   - Version-managed CLI → the appropriate `home/.config/mise/conf.d/` fragment.
   - Application-owned updates → the [provisioning contract](#update-ownership) below.

2. **Move the tuned config into the repo.** Copy `~/.config/foo/config` →
   `~/.dotfiles/home/.config/foo/config`, preserving exactly what you tuned. The `home/`
   tree mirrors `~`, so the relative path is identical.

3. **Choose file-level vs directory-level linking.**
   See [Decision: file vs directory](#decision-file-vs-directory-linking) below.

4. **Declare the link in a module manifest.** Add a `[[resources]]` stanza to:
   - all machines → `dfm-module-core.toml`
   - personal-only → `dfm-module-personal.toml`
   - capability-gated → the matching `dfm-module-<cap>.toml`
   - needs a new capability → **[add a module](#adding-a-module)**.

   ```toml
   [[resources]]
   id = "config-foo-config"
   kind = "link"
   adapter = "fs-link/v1"
   target = ".config/foo/config"
   [resources.value]
   source = "home/.config/foo/config"
   ```

   A directory link adds `directory = true` under `[resources.value]`.

5. **Move the original aside.** Verify the repository copy, then
   `mv ~/.config/foo/config ~/.config/foo/config.pre-dfm`. A real file at the target blocks
   the plan with `E_CONFLICT`; see [Collision handling](#collision-handling).

6. **Plan.** `just sync-dfm`. The plan shows the new link as `planned`.

7. **Apply.** `just sync-dfm-apply <digest>`. The manager creates the symlink.

8. **Verify.** `realpath ~/.config/foo/config` lands in `~/.dotfiles/…` and the tool still
   reads it. Then delete the `.pre-dfm` backup.

A helper plans the file copy, link, and collision handling:

```bash
bash .claude/skills/adopt-config/scripts/plan_adoption.sh ~/.config/foo/config
```

It prints the repo target path, a file-vs-directory recommendation (by scanning for tool
state), a collision check, and the exact stanza to add. It does **not** decide the
module or the package source: those are judgment calls it surfaces for you.

## Update ownership

Each component has one update owner. Choose it from the application's supported lifecycle, not
its release frequency alone. A version manager can handle frequent CLI releases; an application
coordinating persistent workers may need its own update and restart protocol. Application-owned
installations are provisioned from `scripts/sync-side-channels.sh`, gated by the same capability
as their configuration, and link only individual declarative settings; the application keeps
its own versions, runtime state, and update receipts. See
[Firstmate](ai-tools/firstmate.md#native-updates) for the reference implementation.

For rapidly changing upstream skills, prefer the maintainer's supported installer and a
shared `~/.agents/skills` installation. Keep locally authored skills and deliberately patched
forks in `sync-skills` or the skills module, with no overlapping ownership of a skill path.
Refresh explicitly declared sources only; a bulk `skills update` could overwrite unrelated
local work.

`gh-axi` follows its [upstream installation instructions](https://github.com/kunchenguid/gh-axi):
the side channels run `DISABLE_TELEMETRY=1 npx --yes skills@1.7.0 add
https://github.com/kunchenguid/gh-axi/tree/d221ffabfe106e2c7a5998bde30bf58528678d22/skills/gh-axi
--skill gh-axi --global --yes --agent claude-code codex pi junie`. The installer owns the shared content,
consumer links, and local skill lock record. This replaces the vendored `0.1.23` instructions
with upstream's small discovery skill, which obtains current guidance from CLI help. Mise manages
the global CLI installation; upstream's skill can also invoke unpinned `npx`, which does not
inherit mise's release-age constraint. The sync command pins the installer version and skill source
commit; changing either requires a reviewed repository edit.
Running agents may retain previously loaded skill instructions until they reload or restart.

Dependency ownership is separate: an application owns its code and lifecycle, while mise owns its
companion CLI installations. Installing a dependency does not prove a running process uses it;
retain old mise installations with `upgrade --no-prune`.

## Decision: file vs directory linking

The question: **does the tool write runtime state into the same directory as its config?**

- **File-level** (link `.config/foo/config`): the safe default. Use whenever the tool also
  writes caches, history, logs, sockets, lockfiles, or `.git` state alongside its config.
  You manage only the config; runtime state stays out of the repo checkout.
- **Directory-level** (link `.config/foo`, `directory = true`): only when the *entire*
  directory is config you author and the tool does not write state there. Sibling config
  files are linked automatically. If the tool writes state into a directory-linked path, it
  flows through the symlink into the **repo working tree** and dirties git.

This repo's own precedents (all in `dfm-module-core.toml`):

| Config | Linked as | Why |
|---|---|---|
| `jj/config.toml` | file | jj writes repo metadata under `~/.config/jj/repos` |
| `nushell/config.nu` | file | nushell writes `history`/`env.nu` in the dir |
| `github-copilot/intellij/…instructions.md` | file | copilot writes runtime state in the dir |
| `git` | directory | pure config dir (+ `.gitignore_global`); no state written |
| `nvim` | directory | LazyVim rewrites `lazy-lock.json` in place: expected & wanted in-repo |

When unsure, link the file. You can always widen to a directory later.

## Cross-agent note

The auto-triggering skill (`.claude/skills/adopt-config/`) is **Claude Code only**: the
skills mechanism here targets `~/.claude/skills/`, which Codex and opencode do not consume.
Codex and opencode read `AGENTS.md` (a symlink to `CLAUDE.md`), which points at *this doc*.
So all three agents share the same procedure; only Claude Code gets first-class triggering.

## Related

- `CLAUDE.md` § *Layout & module conventions*: the checkout-symlink model.
- `dfm-module-core.toml`: the link stanzas you extend in step 4.

<a id="adding-a-module"></a>
### Adding a module

If the config needs an on/off axis no existing module covers: create
`dfm-module-<name>.toml`, register it under `[modules]` in `dfm-bundle.toml`, and select it
in `dfm/profiles/<host>.toml` for each host that wants it. `scripts/host-capability.sh`
reads the same two files, so shell gates follow automatically. See `CLAUDE.md` § *Capability gating*.
