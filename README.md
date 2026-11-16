# Dotfiles

Personal macOS dotfiles managed by **dotfiles-manager**. The manager owns the links from `~`
into this checkout and the Claude settings merge; Homebrew owns packages (`Brewfile`); mise
owns runtimes and npm CLIs; a few scripts own macOS defaults, the login shell and one
LaunchAgent. The raw config files live under [`home/`](home/) with their real dotted names and
are symlinked into place through `~/.dotfiles`. Editing a raw config is live immediately: no
apply required.

One bundle drives its hosts (currently just `personal-mac`) from a per-host profile
([`dfm/profiles/personal-mac.toml`](dfm/profiles/personal-mac.toml)) that selects modules, so the
same checkout produces a different environment on each host with no hostname checks anywhere
but `scripts/host-detect.sh`.

Secrets render directly from 1Password references via `op-render`; no host holds an age
identity. Secrets for an externally-owned host are that overlay's custody.
The repo also vendors a small Python tool (`mcp_sync/`) that
regenerates machine-specific AI-tool config after every apply.

## Repo tour

```
dfm-bundle.toml           # module list; an external bundle extends it
dfm-personal.toml         # the bundle personal-mac names: dfm-bundle.toml plus source roots
dfm-module-*.toml         # one manifest per module: core, personal, tiling, mcp, skills,
                          #   agent-journal, agents, dev, gui, atuin, infra
dfm/profiles/<host>.toml  # which modules a host selects (the capability table)
Brewfile                  # shared formulae, casks and fonts; applied by scripts/brew-sync.sh
Brewfile.personal         # entries for the personal identity only (jj, tailscale)
home/                     # raw dotfiles (live, symlinked through ~/.dotfiles)
secrets/                  # documentation only: no ciphertext, no age secrets
mcp_sync/                 # vendored uv tool: MCP + skills fan-out
agent_reap/               # vendored uv tool: idle Claude teammate reaper
bootstrap.sh              # fresh-machine setup (CLT, Homebrew, Brewfile)
scripts/                  # system scripts, side channels, hygiene tests
Justfile                  # plan, apply, update, python and sync recipes
```

- **`dfm-bundle.toml`**: declares the modules. **`dfm-personal.toml`** extends it and declares
  the `[sources]` roots (`home`, `skills`, `dfm`) the manager may link from; an external bundle
  extends `dfm-bundle.toml` instead ([`docs/external-bundles.md`](docs/external-bundles.md)). The bundle and module manifests sit at the checkout root
  because the resolver confines a module's sources to the directory of its manifest.
- **`dfm-module-*.toml`**: each module lists `[[resources]]`: `fs-link/v1` links,
  `text-fragments/v1` assemblies (Codex and Pi `AGENTS.md`), and the `claude-settings/v1`
  merge. Modules contribute handlers to that merge (hippo and routing SessionStart hooks).
- **`dfm/profiles/`**: one file per host. `modules = [...]` is the capability table:
  `scripts/host-capability.sh` reads it for the shell-side gates, and the atlas renders it.
- **`home/`**: the actual dotfiles, mirroring `~` (e.g. `home/.config/nvim`,
  `home/.config/zsh/.zshrc`, `home/.claude/hooks/…`). Symlinked live; safe to edit in place.
- **`secrets/`**: documentation only. No ciphertext is tracked in this repo. Templates live
  under `home/` and contain only `op://` references. See
  [`secrets/README.md`](secrets/README.md).
- **`mcp_sync/`**: isolated `uv` project (Python 3.14+, no runtime deps) that
  fans config out to per-tool formats after each apply (`scripts/hooks-sync.sh`).

## Machines and capability gating

A capability is a module. A host has it when its profile selects that module. The shell
gates (`scripts/host-capability.sh <cap>`) and the identity (`--identity`, the selected
module named `personal`, `work` or `lab`) come from the same file: the profile `dfm binding`
names, or `dfm/profiles/<host>.toml` before the machine is bound.

| Module | personal | Gates |
|--------|:--:|-------|
| `tiling` | yes | AeroSpace + SketchyBar + borders links |
| `atuin` | yes | `config.sync.toml` with the self-hosted `sync_address` |
| `mcp` | yes | MCP master config, pi, mise axi tools links; MCP sync step |
| `skills` | yes | skills manifest link, sync step |
| `gui` | yes | no resources; marks GUI casks and display fonts as wanted |
| `dev` | yes | mise `conf.d/dev.toml` |
| `infra` | no | mise `conf.d/infra.toml`, Kubernetes / cluster-ops tooling |
| `agent_journal` | yes | CLI wrappers |
| `agents` | yes | routing SessionStart hook; the agent-registry checkout and the `agents` updater |
| `personal` (identity) | yes | hippo hook, op-render templates, and the identity files of shared capabilities: Claude `allowWrite` fragment, jj, MCP and skills overlays, pinned skills, aerospace and sketchybar variants, journal config |

**Adding a machine:** add `dfm/profiles/<name>.toml`, and add the name to the shared detect
map in `scripts/host-detect.sh`.
**Adding a capability:** create `dfm-module-<name>.toml`, register it in `dfm-bundle.toml`,
and select it in each profile that wants it.

## Fresh-machine setup

`bootstrap.sh` is idempotent: safe to re-run. It:

1. Installs **Xcode Command Line Tools**.
2. Resolves the host profile and checks `dfm/profiles/<host>.toml` exists.
3. Links `~/.dotfiles → <repo>` (the root every managed link resolves through).
4. Installs **Homebrew** if absent, then applies the `Brewfile` (`scripts/brew-sync.sh`),
   which brings `just`, `mise`, `uv` and the rest.
5. Installs **rustup** if absent. The manager's installer builds from a pinned toolchain
   staged out of `~/.rustup`.
6. Prints the remaining steps: stage the toolchain and install the manager (`dfm`) from its
   own repository ([`docs/m5-cutover.md`](docs/m5-cutover.md) section 1), bind the machine
   to its profile (`dfm bind --profile … --machine-id <id>`), grant the dotfiles origin, run
   `dfm sync`, then the one-time commands that `dfm sync` does not run.

```bash
./bootstrap.sh              # auto-detect host from LocalHostName
./bootstrap.sh personal-mac # or force a host profile
# equivalently: just bootstrap
```

A handful of TCC-protected first-run steps can't be scripted (Reduce Transparency, Caps-Lock
remap, granting AeroSpace/SketchyBar Accessibility): `bootstrap.sh` prints them at the end.

## Daily use

```bash
dfm sync                         # fetch, apply, install, render secrets, services, then the updaters
dfm doctor                       # read-only health report with a fix for each row
dfm status                       # the same rows, status and subject only
dfm sync --preview               # print the plan; change nothing
just brew-audit                  # compare declared and installed Homebrew inventory, read-only
```

`dfm sync` is the daily command, and `dfm doctor` and `dfm status` are the checks. Do not deploy
through `just`. `dfm sync` runs from any directory, because the binding names this checkout. It
fast-forwards the bound checkout (`~/.dotfiles`) and applies it as it is, uncommitted edits
included. An edit in another worktree reaches a sync only after it merges to `main`.

`dotfiles-manager.lock` at the checkout root declares the Git source that `dfm sync`
fetches: one root entry for `ssh://git@github.com/stevencarpenter/dotfiles` tracking
`main`. Each machine grants that origin once, before the first sync:
`dfm sync --root ~/.dotfiles --trust-origin ssh://git@github.com/stevencarpenter/dotfiles`.
That run prints the plan and stops.

A plain `dfm sync` prints the plan and runs it, removals included. A new origin needs
`--trust-origin <origin>`: without the grant, dfm refuses the whole run and prints the command.
An adoption or takeover needs `--allow-adopt <operation-id>`: without it, dfm withholds that
operation, runs the rest and prints the flag to add. A running service restarts only with
`--restart <resource-id>`.

After its scopes, `dfm sync` runs the profile's updaters. They upgrade the package managers
(Homebrew, mise, rustup, uv, npm and others). `brew pin` holds and the declared mise ranges
stay. The last updater, `side-channels`, runs `scripts/sync-side-channels.sh` (see
[Side channels](#side-channels)).

`dfm sync` does not run these commands. Run each one by hand when its comment applies:

```bash
scripts/brew-sync.sh             # install missing Brewfile items; --check reports gaps
scripts/launch-agents.sh load    # after a change to the maxfiles plist; launchd also loads it at login
scripts/tiling-reload.sh         # after a sketchybar or AeroSpace config change; restarts sketchybar
scripts/login-shell.sh --check   # read-only login shell check
scripts/mac-defaults.sh --check  # read-only macOS defaults check
```

`just --list` groups targeted maintenance, validation, and utilities.

### Day-to-day procedures

**Editing raw configs needs no apply.** Everything under `home/` is a symlink into the
checkout, so a change to `~/.config/nvim/…` or `~/.config/zsh/.zshrc` is live the moment you
save. An apply is only needed when you add or remove a *link*, change a module's
*resources*, or change the Claude settings merge.

| Change | Where | Then run |
| --- | --- | --- |
| A file that is already linked (`home/**`) | edit it in place | nothing; it is live |
| A package | `Brewfile`; `home/.config/mise/config.toml` for every machine, or a `home/.config/mise/conf.d/<capability>.toml` fragment | `scripts/brew-sync.sh` for a Brewfile line; `dfm sync` for a mise line (its `mise` updater installs missing tools) |
| A link, a module's `[[resources]]`, a profile's module list | `dfm-module-*.toml`, `dfm/profiles/<host>.toml` | `dfm sync` |
| Claude settings | the `core.claude-settings` resource in `dfm-module-core.toml` (inline `managed`, `seed` and `handlers` tables; `home/.claude/settings-base.json` is the pre-cutover copy and is not deployed) | `dfm sync` |
| MCP servers | `home/.config/mcp/mcp-master.json` and `machine/*.json` | `just mcp-sync`, or `dfm sync` |
| macOS defaults | `scripts/mac-defaults.sh` | `scripts/mac-defaults.sh` ([`docs/m5-system-scripts.md`](docs/m5-system-scripts.md)) |

**Update everything installed.** `dfm sync` rolls every package manager. Exact pins stay.
Homebrew alone: `just brew-upgrade`. To pick up configuration pushed from another machine, run
`dfm sync`: it fetches and fast-forwards the checkout first.

**Add a tool.**

1. Declare the package: a `Brewfile` line for a formula, cask or font, or a mise line in
   `home/.config/mise/config.toml` (every machine) or `home/.config/mise/conf.d/<capability>.toml`
   (gated). Record its origin in [`docs/package-mapping.md`](docs/package-mapping.md).
2. Install it: `scripts/brew-sync.sh` for a Brewfile line, `mise install` for a mise line.
   Neither upgrades anything else. The next `dfm sync` also installs a missing mise tool.
3. Try it. When its configuration is worth keeping, adopt it (next procedure).

**Add a configuration** (promote a config the tool wrote under `~`). Full runbook:
[`docs/adopting-a-config.md`](docs/adopting-a-config.md); Claude Code has the `adopt-config` skill.

1. `bash .claude/skills/adopt-config/scripts/plan_adoption.sh ~/.config/<tool>/<config>`
   prints the repo path, a file-or-directory recommendation and the `[[resources]]` stanza.
2. Copy the config under `home/` and add the stanza to the module that should own it:
   `dfm-module-core.toml` for every machine, `dfm-module-personal.toml` for the personal
   identity, `dfm-module-<capability>.toml` for a gated capability.
3. Verify the copy, then move the original aside: `mv <path> <path>.pre-dfm`. A real file at
   a managed target blocks the plan with `E_CONFLICT`; no flag overrides it.
4. `dfm sync`. It prints the plan and runs it.
5. `realpath <path>` lands in `~/.dotfiles/home/…` and the tool reads it. Delete the backup.

**Remove a configuration.**

1. Delete its `[[resources]]` stanza from the module. To drop a whole capability on one
   machine, remove the module from `dfm/profiles/<host>.toml` instead.
2. `dfm sync --preview`. The plan lists one `remove@<resource>@<path>` per owned output.
3. `dfm sync`. The manager deletes only exact, unchanged outputs it owns and reports anything
   modified or foreign as a conflict instead of deleting it.
4. `git rm` the source under `home/` and commit.

**Remove a tool.** Remove its configuration as above, then delete the `Brewfile` or mise line.
`brew-sync.sh` and the side channels never uninstall, so run `brew uninstall <name>` or
`mise uninstall <tool>` yourself, and clear the tool's own state under `~/.local/share`,
`~/.cache` or `~/Library` by hand if you want it gone.

**Turn a capability on or off for a machine.** Edit `modules = [...]` in
`dfm/profiles/<host>.toml`, then plan and apply. Adding a module creates its links; removing
one goes through the removal flow above. A new axis needs a module: see
[Machines and capability gating](#machines-and-capability-gating).

Long-lived programs still cache state after a raw file changes. For tmux/z4h/Claude behavior,
follow the [tmux runtime lifecycle runbook](docs/ai-tools/tmux-runtime-lifecycle.md): it separates
tracked source, deployed artifacts, live server state, and surviving processes/sockets, and covers
cwd inheritance, detach topology, agent cleanup, plugin residue, and stale side-channel binaries.

## Validate without applying

```bash
dfm plan --root ~/.dotfiles                  # every operation and the plan digest; writes nothing
dfm doctor --root ~/.dotfiles                # live links against the manifests
scripts/brew-sync.sh --check                 # Brewfile gaps
scripts/mac-defaults.sh --check              # macOS defaults drift
just lefthook                                # every pre-commit job, as CI does
```

CI runs the hygiene suite (lefthook jobs, gitleaks, configuration tests under `scripts/`) and
the two Python projects' lint and tests.

## Secrets

No host holds an age identity. `home/.local/bin/op-render` atomically renders
`~/.config/zsh/.personal.env` and `~/.ssh/config.d/10-homelab.conf` from public-safe templates
containing `op://` references. It preserves the last known-good targets on any failure.

`dfm sync` renders the same targets as `op-template/v1` secrets. Without a 1Password session dfm
skips the secrets with a warning; run `op signin`, then `dfm sync` again. Run `op-render` by hand
from an authenticated terminal for a manual render. `op-render --warn-stale-only` reads the
`.last-render` sentinel, touches no network, and warns when the last successful render is older
than `OP_RENDER_STALE_DAYS` (default 7).

For reviewed edits made directly to `~/.config/zsh/.personal.env`, `just op-adopt` produces a
names-only reverse-adoption plan and `just op-adopt --apply` updates only fields already pinned in
`home/.config/op/adopt-policy.json`. It cannot import new variables, modify templates, or adopt SSH
config; Login-item fields remain manual-only to avoid the 1Password CLI's passkey-loss hazard.

The former carry-verbatim age bridge for work secrets has been removed: its ciphertexts, recipient
file, and module are gone, and no host requires an age identity. Secrets for an externally-owned
host are administered by that overlay. See [`secrets/README.md`](secrets/README.md).

## Shared output policy

[`home/.config/agents/output-policy.md`](home/.config/agents/output-policy.md) defines the
ASD-STE100-based communication rules for Claude Code, Codex, Pi, and OpenCode. Dotfiles owns
this default because it deploys global harness configuration on every host. The personal
agents repository owns specialist definitions and rubrics.

The policy uses short sentences, active voice, consistent terms, and explicit evidence.
The 80 to 90% target describes the intended style, not a measured compliance score.
Technical terms, code, commands, identifiers, and quotations retain their exact meaning.
An explicit user request for another language, format, or audience style takes precedence.

| Harness | Load mechanism |
|---|---|
| Claude Code | Global `CLAUDE.md` imports the policy. The `STE` output style reinforces it and retains coding instructions. |
| Codex | The `codex-agents` assembly appends the shared `20-output-policy.md` fragment to global `AGENTS.md`. |
| Pi | The `pi-agents` assembly appends the same policy to global `AGENTS.md` after the Pi runtime notes. |
| OpenCode | MCP sync renders the policy's absolute path into the global config's `instructions` list. |

Run `dfm sync` after adding these paths or editing the policy to refresh the
assembled Codex and Pi instructions. Claude and OpenCode read the linked policy directly in a
new session. Restart sessions after deployment. Project settings and explicit overrides can
change the defaults. The adapters do not add the policy to separately constructed subagent
prompts. Such agents receive it only if their harness loads the global instructions.

This is prompt-level enforcement. The configuration checks verify that each adapter loads
the same policy. They do not assess the model's output against the STE rules or dictionary.
Claude's [output-style documentation](https://code.claude.com/docs/en/output-styles) states
that styles are model instructions. The source standard is
[ASD-STE100](https://www.asd-ste100.org/).

## Side channels

`scripts/sync-side-channels.sh` holds the sync steps that dfm has no resource for yet. The
`side-channels` updater runs it last in every `dfm sync`, through the `sync-side-channels`
recipe, detached and with a cleared environment:

- `scripts/hooks-sync.sh`: the MCP client configs, then the skills fan-out (`mcp_sync`).
- The upstream `gh-axi` skill, on hosts with the `skills` capability. dfm's `skills` updater
  keeps it at its newest version; see [update ownership](docs/adopting-a-config.md#update-ownership).
- The ponytail Codex plugin. A failure here is a warning, not a failed step.

Every step runs even when an earlier one failed. The script then exits 1, so dfm reports the
updater as `failed`, and a summary line names the failed steps. dfm shows none of the output,
so the script also writes it to `~/.local/state/dotfiles/side-channels.log`.

`dfm sync` owns the rest: the `op-template/v1` secrets (`.personal.env` and
`~/.ssh/config.d/10-homelab.conf`), the mise tools (its `mise` updater), the uv tools
`token-auditor` and `agent-reap` (`uv-tool/v1`), and the tpm and agent-registry checkouts
(`git-checkout/v1`, cloned when missing and fast-forwarded by the `checkouts` updater), the
DuckDB extensions for the yazi previews (`duckdb-extension/v1`), the lefthook git hooks (the
`lefthook` updater). The `agents` updater pulls the registry and installs it; a working copy
at `~/projects/agents` takes precedence for the install.

The rule: declarative work is a manager resource or updater. The side channels hold only the
steps that dfm cannot declare yet.

Global npm CLIs are declared in `home/.config/mise/config.toml`. dfm's `mise` updater installs
the missing tools and upgrades each one inside its declared range: `latest` tracks releases,
partial versions track their range, and exact versions stay pinned. mise removes a replaced
version after its grace period (24 h by default). Inspect the inventory with `mise ls`.

## Homebrew policy

`Brewfile` plus `Brewfile.<identity>` is the complete declared inventory: formulae, casks and
fonts. `scripts/brew-sync.sh` applies the identity file after the shared one, installs what is missing and never uninstalls; `--check` reports gaps. `dfm sync` upgrades
every outdated formula and cask except `brew pin` holds, including retained unmanaged packages.
`just brew-upgrade` upgrades Homebrew alone. Use `just brew-audit` to
compare declared and installed inventory using read-only `brew list`, `brew leaves`, and
`brew tap` queries. It never invokes Homebrew cleanup or uninstall.
[`docs/package-mapping.md`](docs/package-mapping.md) records how each package arrived in the
Brewfile.

## dotfiles-manager bundle

`dfm-bundle.toml`, `dfm-personal.toml`, `dfm-module-*.toml` and `dfm/profiles/personal-mac.toml` declare the files
the manager places (DFM-49). Run `plan --root <checkout>` with the checkout at `~/.dotfiles`.
Each link text is `<checkout>/home/<path>` (skills: `<checkout>/skills/personal/<name>`).

| Module | Resources |
| --- | --- |
| `core` (all machines: ssh, mise base, agent-reap, `.duckdbrc`, `20-output-policy.md` fragments, maxfiles plist) | 43 links, 2 `text-fragments/v1` assemblies, 1 `claude-settings/v1` merge |
| `personal` (+ identity files of shared capabilities) | 46 links (30 skill links), 1 `op-template/v1` secret, hippo SessionStart handler |
| `tiling` | 4 links |
| `mcp` (master config, pi, mise axi tools) | 14 links |
| `skills` | 1 config link |
| `agent-journal` | 2 links |
| `dev` | 1 link |
| `atuin` | 1 link (`config.sync.toml`) |
| `agents` | routing SessionStart handler |
| `infra` | 1 link (mise `conf.d/infra.toml`) |
| `gui` | none |

`.config/sketchybar/machine.env` is a link to the static file
`home/.config/sketchybar/machine.personal.env`. The planner creates parent directories.

The settings merge (`core.claude-settings` in `dfm-module-core.toml`) declares its values inline. The
adapter reads no file, so edit the manifest, not `home/.claude/settings-base.json`, which is the
pre-cutover copy that `scripts/test-tmux-lifecycle-contract.sh` still reads. The manifest carries every
value of that file plus the `personal-mac` variant: plugins, `permissions`, `skillOverrides`,
`extraKnownMarketplaces`, `env`, flags, the three `allowWrite` paths (appended), `model` and
`effortLevel` (seeds), and all hooks as handlers. The two `SessionStart` handlers come from the
`personal` (hippo) and `agents` (routing) modules. `.claude/settings.d/*.json` fragments merge over the
declared values. Tables merge into the live file, so plugins and permissions that the application
added stay.

`dfm-personal.toml` declares `[sources]` roots `home`, `skills` and `dfm`, so the live checkout can be the
plan root. It excludes `home/.config/tmux/plugins` (nested `.git`), `home/.pi/agent/extensions/node_modules`
and `**/__pycache__`, `**/.venv`, `**/node_modules`. A directory link still publishes excluded content
(`plan` prints `note: contains N excluded entries, not hashed`).

Not managed on purpose:

- Secrets and op-render outputs: `.config/op/*` (except the two linked files), every `.personal.env`.
- Application state: `~/.claude.json`, `~/.codex/config.toml`, every `~/.codex/hooks.json` entry
  other than the hippo hook (`personal.codex-hooks`, `codex-hooks/v1`), MCP generated outputs, `~/.config/mcp/overrides`, skills synced by
  `sync-skills`.
- `~/.config/jj` as a directory (mutable metadata under `repos/`): only `config.toml` is linked.

The cutover from the previous manager is recorded in [`docs/m5-cutover.md`](docs/m5-cutover.md).

## Vendored Python tools

Isolated `uv` projects (Python 3.14+, no runtime deps). See [CLAUDE.md](CLAUDE.md) for
the full lint/test matrix.

- `mcp_sync/`: MCP + skills fan-out (the `sync-mcp-configs` / `sync-skills` entry points).
- [`agent_reap/`](agent_reap/): reports and reaps idle Claude teammate panes across every tmux
  socket (`agent-reap`); automatic cleanup is the Claude `Stop` and `SessionEnd` hooks, not a daemon.

```bash
just test
uv run --project mcp_sync --group dev pytest mcp_sync/tests
```

`aws_config_gen` (the AWS SSO profile generator) was extracted to
[its own repo](https://github.com/stevencarpenter/aws-config-generator); the external work overlay
now owns AWS profile generation, so this repo no longer ships it.

`token-auditor` (behind the `codax`/`claade`/`opencade` wrappers) was extracted to
[its own repo](https://github.com/stevencarpenter/token-auditor) and installs as a standalone uv
tool. The `core` module declares it as a `uv-tool/v1` resource from its default branch, and `dfm sync` rolls it.
