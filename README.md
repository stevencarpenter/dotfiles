# Dotfiles

Personal macOS dotfiles built as a **nix-darwin + home-manager flake**, in the "thin wrapper"
shape modeled on [kunchenguid/dotfiles](https://github.com/kunchenguid/dotfiles): nix owns
*packages*, macOS defaults, capability gating, and orchestration, while the raw config files live
under [`home/`](home/) with their real dotted names and are symlinked into place **out of the nix
store** (through `~/.dotfiles`). Editing a raw config is live immediately — no rebuild required.

One flake drives two machine types — `personal-mac` and `work-mac` — from a single
capability table ([`lib/machines.nix`](lib/machines.nix)), so the same checkout produces a
different environment on each host with no hostname checks inside any module.

Personal secrets render directly from 1Password references via `op-render`; work secrets still use
the temporary [agenix](https://github.com/ryantm/agenix) bridge until the external work wrapper takes
custody. The repo also vendors a small Python tool (`mcp_sync/`) that
regenerates machine-specific AI-tool config after every switch.

> **Migrating from the old chezmoi layout?** See [`docs/nix-migration.md`](docs/nix-migration.md)
> for the full mechanism-by-mechanism mapping (dot\_ prefixes → `home/`, `.chezmoiignore` gates →
> `mkIf`, `run_` hooks → activation vs `just sync`, age → agenix).

## Repo tour

```
flake.nix                 # inputs + one-screen mkHost fold (darwinConfigurations.<host>)
lib/machines.nix          # capability table — the single source of per-host variance
hosts/                    # {personal,work}-mac.nix — thin shims; host-scoped decls only
modules/
  darwin/                 # system scope (specialArgs): core, macos-defaults, homebrew
  home/                   # home scope (extraSpecialArgs): dotfiles, shell, packages,
                          #   tiling, dev-tools, ai-stack, secrets, sync-hooks
home/                     # raw dotfiles (live, symlinked out-of-store through ~/.dotfiles)
secrets/                  # age ciphertext + secrets.nix recipients (see secrets/README.md)
mcp_sync/                 # vendored uv tool — MCP + skills fan-out
bootstrap.sh  rebuild.sh  # fresh-machine setup / routine switch (host auto-detect)
Justfile                  # nix + python + sync task runner
```

- **`flake.nix`** — pins `nixpkgs`/`nix-darwin`/`home-manager` to the **26.05** stable darwin line
  (plus `nix-homebrew` and `agenix`), then folds `lib/machines.nix` into
  `darwinConfigurations.<host>` via a `mkHost` helper. Every host receives the same specialArgs
  payload — `{ inherit inputs hostName; user; caps; identity; }` — for both the darwin modules
  (`specialArgs`) and home-manager (`extraSpecialArgs`). Adding a machine stays a one-row edit.
- **`lib/machines.nix`** — the capability table: each machine maps to `system`, `user`, an
  `identity` string (`personal`/`work`, replacing the old `hasPrefix` gates), and a `caps`
  set of booleans. Modules gate on `caps.<x>` / `identity` — never on hostname.
- **`hosts/*.nix`** — deliberately thin. They import `modules/darwin` and hold only genuinely
  host-scoped declarations. All real variance flows from the caps table.
- **`modules/darwin/`** — system scope. `core.nix` (nix-daemon ownership, unfree policy, login
  shell pin, `maxfiles` launchd agent, `stateVersion`), `macos-defaults.nix` (declarative
  `system.defaults.*`), `homebrew.nix` (nix-homebrew taps/brews/casks, gated per caps).
- **`modules/home/`** — home scope. `dotfiles.nix` is the heart of the thin wrapper (out-of-store
  symlinks); the rest own shell, packages, tiling, dev tooling, the AI stack, agenix secrets, and
  the post-switch sync hooks. Each self-gates on caps/identity.
- **`home/`** — the actual dotfiles, mirroring `~` (e.g. `home/.config/nvim`,
  `home/.config/zsh/.zshrc`, `home/.claude/hooks/…`). Symlinked live; safe to edit in place.
- **`secrets/`** — work-only age ciphertext carried over from chezmoi, plus `secrets.nix`
  (agenix recipients). Personal templates live under `home/` and contain only `op://` references.
  Nothing under `secrets/` is decrypted or edited by hand. See
  [`secrets/README.md`](secrets/README.md).
- **`mcp_sync/`** — isolated `uv` project (Python 3.14+, no runtime deps) that
  fans config out to per-tool formats after each switch. Run standalone or via the activation hooks.

## Machines and capability gating

Every gate keys off a capability boolean in `lib/machines.nix` (threaded in via specialArgs), so
adding a machine is a one-row change and no gate site needs editing.

| Capability | personal | work | Gates |
|------------|:--:|:--:|-------|
| `tiling` | yes | yes | AeroSpace + SketchyBar + borders (WM stack) |
| `sketchybar_workspace_badges` | no | yes | SketchyBar dock-badge queries via `lsappinfo` |
| `atuin` | yes | no | sync shell history to the self-hosted server (selects which config variant deploys; both machines get the config) |
| `mcp` | yes | yes | MCP master config + per-tool sync hook |
| `skills` | yes | yes | Claude skills manifest + sync hook |
| `gui` | yes | yes | GUI apps + display fonts |
| `dev` | yes | no | language-LSP plugins + dev Brewfile/fonts block |
| `infra` | no | yes | Kubernetes / cluster-ops tooling via mise |
| `agent_journal` | yes | no | Obsidian agent-journal config, CLI wrappers, Claude hook |
| `agents` | yes | no | personal agent-registry clone + fan-out installer |

`identity` (`personal`/`work`) additionally splits ownership-flavored gates — personal-only
shell profiles + hippo, work-only shell/AWS profiles, homelab-over-Tailscale (`!= "work"`) SSH +
`tailscale.zsh`. `work` is corporate-curated (`dev`/`atuin` off, its own dev tooling); `personal`
is the daily driver. Both current machines are `aarch64-darwin`.

**Adding a machine:** copy a row in `lib/machines.nix`, rename it, flip the caps you don't want,
and add the name to the `detect_host` map in `bootstrap.sh` / `rebuild.sh`.
**Adding a capability:** add the key to *every* row (`flake.nix` asserts the row shape) and gate
the owning module on `caps.<capability>`.

## Fresh-machine setup

`bootstrap.sh` is idempotent — safe to re-run. It:

1. Installs **Xcode Command Line Tools** (nix-darwin has no option for CLT; native builds need
   them first).
2. Installs **Lix** if `nix` isn't on PATH, via the Lix installer. (`nix.enable = true` with
   `nix.package = pkgs.lix` in `modules/darwin/core.nix` — nix-darwin manages the daemon and
   runs Lix as the interpreter.)
3. Resolves the host config. On `work-mac` only, fetches the temporary work **age identity key from
   1Password** into `~/.config/age/keys.txt`:

   ```bash
   op read "op://Private/dotfiles-age-key/notesPlain" > ~/.config/age/keys.txt
   chmod 600 ~/.config/age/keys.txt
   ```

   Personal machines skip this step because their secret surface is fully 1Password-rendered and
   evaluates to zero `age.secrets`.
4. Links `~/.dotfiles → <repo>` (the out-of-store root the raw symlinks resolve through).
5. Runs the
   **first switch** straight from the flake input (`darwin-rebuild` isn't on PATH yet):

   ```bash
   sudo nix run github:nix-darwin/nix-darwin/nix-darwin-26.05#darwin-rebuild -- \
     switch --flake "$HOME/.dotfiles#<host>"
   ```

6. Installs **rustup** (kept imperative on purpose — see `docs/nix-migration.md`).
7. Runs **`just sync`** for the network/SSH side channels (git externals, agent installation,
   and token-auditor).

Then run it:

```bash
./bootstrap.sh              # auto-detect host from LocalHostName
./bootstrap.sh work-mac     # or force a host config
# equivalently: just bootstrap
```

A handful of TCC-protected first-run steps can't be scripted (Reduce Transparency, Caps-Lock
remap, granting AeroSpace/SketchyBar Accessibility) — `bootstrap.sh` prints them at the end.

## Daily use

```bash
./rebuild.sh                # auto-detect host, sudo darwin-rebuild switch
./rebuild.sh work-mac       # force a host config
just rebuild                # same, via the task runner
```

`rebuild.sh` verifies that `~/.dotfiles` resolves to the physical checkout, maps `LocalHostName` to
a flake config, and `exec`s `sudo darwin-rebuild switch` against that physical path. There's also a
`rebuild`/`ca` shell function in `home/.config/zsh/lib/rebuild.zsh` for use from any directory.

**Editing raw configs needs no rebuild.** Everything under `home/` is an out-of-store symlink, so a
change to `~/.config/nvim/…` or `~/.config/zsh/.zshrc` is live the moment you save. A rebuild is
only needed when you change *packages*, *macOS defaults*, *gating*, or a *secret/hook declaration*
— anything nix actually owns.

## Validate without applying

```bash
nix flake check --no-build --all-systems   # or: just check
git ls-files -z '*.nix' | xargs -0 nix fmt -- --check # or: just nix-fmt-check
nix build --no-link \
  '.#checks.aarch64-darwin.personal-mac' \
  '.#checks.aarch64-darwin.work-mac' \
  '.#checks.aarch64-darwin.statix'
```

The flake exports every host closure through `checks.<system>.<host>`. That makes the fast check
force `config.system.build.toplevel` for both machines instead of only traversing the non-standard
`darwinConfigurations` output. CI also formats all Nix sources and realizes both closures on
`macos-latest`; evaluation catches module/option errors, while realization catches file collisions
and build-time failures.

## Secrets

Personal machines declare zero `age.secrets`. `home/.local/bin/op-render` atomically renders
`~/.config/zsh/.personal.env` and `~/.ssh/config` from public-safe templates containing `op://`
references. It runs during personal Home Manager activation when the 1Password CLI is authenticated
and preserves the last known-good targets on any failure.

For reviewed edits made directly to `~/.config/zsh/.personal.env`, `just op-adopt` produces a
names-only reverse-adoption plan and `just op-adopt --apply` updates only fields already pinned in
`home/.config/op/adopt-policy.json`. It cannot import new variables, modify templates, or adopt SSH
config; Login-item fields remain manual-only to avoid the 1Password CLI's passkey-loss hazard.

Work currently decrypts its environment, AWS overrides, and 25 work-skill files through agenix
using `~/.config/age/keys.txt`. That carry-verbatim bridge remains until the external work wrapper
moves them to externally administered custody. See [`secrets/README.md`](secrets/README.md).

## Side channels (`just sync` / `just bootstrap`)

Some provisioning is deliberately kept **out of `darwin-rebuild switch`** because it needs the
network, SSH auth, or `sudo` — things a `switch` should not silently depend on. Those live in the
Justfile instead:

- **`just sync`** — clone/refresh tpm over HTTPS; install and validate the personal
  `agent-registry` from `~/projects/agents` when that working copy exists, otherwise clone/refresh
  `~/.local/share/agent-registry`, only when the selected host's canonical `agents` capability is
  enabled; and install the immutable `token-auditor` release pinned in the Justfile. Safe to re-run;
  `bootstrap.sh` passes its resolved host explicitly. A failed side channel makes this explicit
  command fail instead of leaving a silently partial install.
- **`just bootstrap`** — the full fresh-machine flow (`bootstrap.sh`): Lix, the work-only age key
  when applicable, first switch, rustup.

The rule ("bucket rule" in `docs/nix-migration.md`): declarative or offline+fast+idempotent work
goes in the switch (as `home.activation` hooks); anything touching network/SSH/sudo goes in
`just sync` / `just bootstrap`. This keeps a switch reproducible and offline-safe.

## Homebrew policy

Rebuilds are idempotent: they neither update Homebrew metadata nor upgrade installed packages.
Activation keeps unmanaged inventory in place because nix-darwin's `"check"` mode would abort
while the migrated prefix still contains reviewed-useful extras. Run `just brew-upgrade` for
deliberate updates and `just brew-audit` to compare declared and installed inventory using read-only
`brew list`, `brew leaves`, and `brew tap` queries. It never invokes Homebrew cleanup or uninstall.
**Never** set activation cleanup to `"zap"`; it deletes application data.

What stays in Homebrew rather than nixpkgs, and why:

| Kept in brew | Reason |
|---|---|
| GUI casks, bespoke fonts | no nixpkgs equivalent, or too heavy to build (e.g. iosevka) |
| `zsh`, `bash` + completions | the zshrc probes the Homebrew prefix for them |
| `tailscale` (`identity != "work"`) | nixpkgs ships binaries only; nix-darwin has no `services.tailscale`, so `brew services` supervises `tailscaled` |
| Swift toolchain (`caps.dev`) | in nixpkgs but not reliably cached for aarch64-darwin — a switch would compile Swift from source |
| `railway`, `crush` | packaged in nixpkgs (or not), but ship far faster than the stable channel tracks |
| `worktrunk`, `herdr`, `mole` | no nixpkgs equivalent |

Everything else that is a plain CLI belongs in `modules/home/packages.nix`. Note that nix only
*wins* a name collision because `home/.config/zsh/.zshrc` explicitly orders the nix profiles ahead
of `/opt/homebrew/bin`; `brew shellenv` prepends itself, so removing that ordering silently makes
every duplicated `home.packages` entry inert.

### Fast-moving tools and the stable pin

Shipping faster than the stable channel tracks is **no longer** a reason to keep a tool in Homebrew.
`modules/home/packages.nix` opens with a `fastMovingPackages` allowlist: any name in it is drawn
from a second `nixpkgs-unstable` flake input, while everything else stays on the `26.05` pin.
Selection is explicit rather than an overlay, so unstable versions never leak into other packages'
dependency graphs and the rest of the closure keeps its cache hits. An eval-time assertion fails the
build if a package is declared in both channels.

Currently allowlisted: `mise`, `uv`, `fzf`, `lazygit`, `zoxide`, `ripgrep` — measured 2026-07-26 at
between one minor version and ~15 releases behind upstream (`mise` was the worst, ~2 months). Most
CLI tools do **not** belong here: `gh`, `yazi`, `neovim`, `delta`, `bat`, `fd`, and `btop` were all
exactly current on stable. Add a tool only after measuring it.

The `railway` and `crush` rows above predate this mechanism, and their stated reason no longer
holds — on unstable they sit one release behind upstream rather than months. They remain brews only
because moving them is a package-manager migration rather than a channel change; see
`docs/superpowers/specs/2026-07-26-fast-moving-package-channel-lag-design.md` §7. That follow-up
should also revisit the `worktrunk` row: it *is* packaged in nixpkgs-unstable, at 0.66.0.

## Vendored Python tools

An isolated `uv` project (Python 3.14+, no runtime deps). See [CLAUDE.md](CLAUDE.md) for
the full lint/test matrix.

- `mcp_sync/` — MCP + skills fan-out (the `sync-mcp-configs` / `sync-skills` entry points).

```bash
just test                                                    # lint+test mcp_sync
uv run --project mcp_sync --group dev pytest mcp_sync/tests
```

`aws_config_gen` (the AWS SSO profile generator) was extracted to
[its own repo](https://github.com/stevencarpenter/aws-config-generator); the external work wrapper
now owns AWS profile generation, so this repo no longer ships it or the `aws_sso` capability.

`token-auditor` (behind the `codax`/`claade`/`opencade` wrappers) was extracted to
[its own repo](https://github.com/stevencarpenter/token-auditor) and installs as a standalone uv
tool via `just sync` (immutable release in `versions/token-auditor`).
