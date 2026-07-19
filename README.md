# Dotfiles

Personal macOS dotfiles built as a **nix-darwin + home-manager flake**, in the "thin wrapper"
shape modeled on [kunchenguid/dotfiles](https://github.com/kunchenguid/dotfiles): nix owns
*packages*, macOS defaults, capability gating, and orchestration, while the raw config files live
under [`home/`](home/) with their real dotted names and are symlinked into place **out of the nix
store** (through `~/.dotfiles`). Editing a raw config is live immediately — no rebuild required.

One flake drives two machine types — `personal-mac` and `work-mac` — from a single
capability table ([`lib/machines.nix`](lib/machines.nix)), so the same checkout produces a
different environment on each host with no hostname checks inside any module.

Secrets are age-encrypted (via [agenix](https://github.com/ryantm/agenix)) against the existing
age identity, whose key is sourced from 1Password at bootstrap. The repo also vendors two small
Python tools (`mcp_sync/`, `aws_config_gen/`) that regenerate machine-specific AI-tool config after
every switch.

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
aws_config_gen/           # vendored uv tool — AWS SSO profile generator
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
- **`secrets/`** — byte-identical age ciphertext carried over from chezmoi, plus `secrets.nix`
  (agenix recipients). Nothing here is decrypted or edited by hand. See
  [`secrets/README.md`](secrets/README.md).
- **`mcp_sync/`, `aws_config_gen/`** — isolated `uv` projects (Python 3.14+, no runtime deps) that
  fan config out to per-tool formats after each switch. Run standalone or via the activation hooks.

## Machines and capability gating

Every gate keys off a capability boolean in `lib/machines.nix` (threaded in via specialArgs), so
adding a machine is a one-row change and no gate site needs editing.

| Capability | personal | work | Gates |
|------------|:--:|:--:|-------|
| `tiling` | yes | yes | AeroSpace + SketchyBar + borders (WM stack) |
| `sketchybar_workspace_badges` | no | yes | SketchyBar dock-badge queries via `lsappinfo` |
| `atuin` | yes | no | atuin client → self-hosted sync server |
| `mcp` | yes | yes | MCP master config + per-tool sync hook |
| `skills` | yes | yes | Claude skills manifest + sync hook |
| `gui` | yes | yes | GUI apps + display fonts |
| `dev` | yes | no | language-LSP plugins + dev Brewfile/fonts block |
| `aws_sso` | no | yes | AWS SSO profile generator |
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
3. Fetches the existing **age identity key from 1Password** into
   `~/.config/age/keys.txt`:

   ```bash
   op read "op://Private/chezmoi-age-key/key.txt" > ~/.config/age/keys.txt
   chmod 600 ~/.config/age/keys.txt
   ```

   This must exist before the first switch or every agenix decrypt fails during activation.
4. Links `~/.dotfiles → <repo>` (the out-of-store root the raw symlinks resolve through).
5. Resolves the host config (arg → `scutil --get LocalHostName` map → prompt) and runs the
   **first switch** straight from the flake input (`darwin-rebuild` isn't on PATH yet):

   ```bash
   sudo nix run github:nix-darwin/nix-darwin/nix-darwin-26.05#darwin-rebuild -- \
     switch --flake "$HOME/.dotfiles#<host>"
   ```

6. Installs **rustup** (kept imperative on purpose — see `docs/nix-migration.md`).
7. Runs **`just sync`** for the network/SSH side channels (git externals + token-auditor).

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

`rebuild.sh` re-links `~/.dotfiles` (harmless if correct), maps `LocalHostName` to a flake config,
and `exec`s `sudo darwin-rebuild switch --flake ~/.dotfiles#<host>`. There's also a `rebuild`/`ca`
shell function in `home/.config/zsh/lib/rebuild.zsh` for use from any directory.

**Editing raw configs needs no rebuild.** Everything under `home/` is an out-of-store symlink, so a
change to `~/.config/nvim/…` or `~/.config/zsh/.zshrc` is live the moment you save. A rebuild is
only needed when you change *packages*, *macOS defaults*, *gating*, or a *secret/hook declaration*
— anything nix actually owns.

## Validate without applying

```bash
nix flake check --no-build   # or: just check
```

`--no-build` evaluates every flake output — so a broken module, a bad option, or a gate referencing
an undefined capability surfaces as a hard evaluation error — **without** realizing the full darwin
system closures. (The flake ships no formatter, so there's no `nix fmt --check` step.)

> Full evaluation of both `darwinConfigurations.<host>.system` derivations was verified in a
> Linux `nixos/nix` container. Nix *evaluation* is platform-independent — only *building* a darwin
> closure requires a Mac — so an all-hosts eval on Linux is a valid structural gate. This runs in
> CI on `macos-latest` (`.github/workflows/nix-flake-check.yml`).

## Secrets

agenix decrypts every `secrets/**/*.age` blob at activation time using the identity at
`~/.config/age/keys.txt` — the same age identity, moved out of the retired chezmoi root. **No blob
was re-encrypted for the port**: each is byte-identical ciphertext moved from its old chezmoi path,
and agenix decrypts it regardless of how it was produced.

Which secrets a host decrypts is driven entirely by `identity` / `caps.skills` in
`modules/home/secrets.nix` (common env everywhere; SSH config on personal (`!= "work"`); personal/work env
splits; work-only AWS overrides + the 25 gated Claude-skill blobs). There is no per-host secrets
file to edit. To add or rotate a secret, or to rekey recipients, see
[`secrets/README.md`](secrets/README.md).

## Side channels (`just sync` / `just bootstrap`)

Some provisioning is deliberately kept **out of `darwin-rebuild switch`** because it needs the
network, SSH auth, or `sudo` — things a `switch` should not silently depend on. Those live in the
Justfile instead:

- **`just sync`** — clone/refresh tpm over HTTPS, clone the personal `agent-registry` over SSH
  only when the selected host's canonical `agents` capability is enabled, and install the pinned
  `token-auditor` uv tool. Safe to re-run; `bootstrap.sh` passes its resolved host explicitly.
- **`just bootstrap`** — the full fresh-machine flow (`bootstrap.sh`): Lix, the age
  key, first switch, rustup.

The rule ("bucket rule" in `docs/nix-migration.md`): declarative or offline+fast+idempotent work
goes in the switch (as `home.activation` hooks); anything touching network/SSH/sudo goes in
`just sync` / `just bootstrap`. This keeps a switch reproducible and offline-safe.

## First-switch caution: `homebrew.onActivation.cleanup = "none"`

`modules/darwin/homebrew.nix` sets `cleanup = "none"` — nix-darwin will **not** uninstall brew
packages that aren't listed in the module. This is intentional during the cutover, while the brew
inventory is still being audited: the first switch on an existing machine won't rip out anything the
Brewfile port might have missed. Graduate to `"uninstall"` once the lists are confirmed complete.
**Never** use `"zap"` (it deletes app data/config, not just the app).

## Vendored Python tools

Each is an isolated `uv` project (Python 3.14+, no runtime deps). See [CLAUDE.md](CLAUDE.md) for
the full lint/test matrix.

- `mcp_sync/` — MCP + skills fan-out (the `sync-mcp-configs` / `sync-skills` entry points).
- `aws_config_gen/` — AWS SSO profile generator.

```bash
just test                                                    # lint+test both tools
uv run --project mcp_sync --group dev pytest mcp_sync/tests
uv run --project aws_config_gen --group dev pytest aws_config_gen/tests
```

`token-auditor` (behind the `codax`/`claade`/`opencade` wrappers) was extracted to
[its own repo](https://github.com/stevencarpenter/token-auditor) and installs as a standalone uv
tool via `just sync` (pin in the Justfile's `TOKEN_AUDITOR_VERSION`).
