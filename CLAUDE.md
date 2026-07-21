# CLAUDE.md

Guidance for Claude Code (claude.ai/code) and Codex (`AGENTS.md` is a symlink to this file) when
working in this repo. Global personal preferences live in `~/.claude/CLAUDE.md`; do not duplicate
them here.

## What This Is

A personal macOS dotfiles repository built as a **nix-darwin + home-manager flake** in a "thin
wrapper" shape: nix owns packages, macOS defaults, capability gating, and orchestration, while the
raw config files live under `home/` (real dotted names) and are symlinked into place **out of the
nix store** through `~/.dotfiles` — so editing a raw config is live immediately, no rebuild needed.
One flake drives two machine types (`personal-mac`, `work-mac`) from a single
capability table (`lib/machines.nix`); modules gate on caps/identity, never on hostname. Personal
secrets render directly from 1Password via `op-render`; work secrets temporarily remain
age-encrypted through [agenix](https://github.com/ryantm/agenix) until the external work wrapper
takes custody. The repo also vendors one small Python tool
(`mcp_sync/`). Two former tools were extracted to their own public repos and install as standalone
uv tools: `token-auditor` (github.com/stevencarpenter/token-auditor, via `just sync`) and
`aws_config_gen` (github.com/stevencarpenter/aws-config-generator; the external work wrapper now
owns AWS profile generation, so this repo dropped it and the `aws_sso` capability). This repo was
ported from chezmoi; see `docs/nix-migration.md` for the full mechanism map.

## Commands

All Python commands run from the repo root. Each tool is its own `uv` project.

Both vendored Python tools use PEP 735 `[dependency-groups]`; install dev deps with `--group dev`.

### MCP Sync (`mcp_sync/`)

```bash
# Lint
uv run --project mcp_sync --group dev ruff check mcp_sync/src mcp_sync/tests
uv run --project mcp_sync --group dev ruff format --check mcp_sync/src mcp_sync/tests

# Test
uv run --project mcp_sync --group dev pytest mcp_sync/tests --cov=mcp_sync --cov-report=term-missing
uv run --project mcp_sync --group dev pytest mcp_sync/tests/test_sync_mcp_configs.py -v  # single file

# Run sync manually
uv run --project mcp_sync sync-mcp-configs
```

### Token Auditor (external — `token-auditor` uv tool)

`token-auditor` (the auditor behind the `codax`/`claade`/`opencade` wrappers) now lives in its own
repo: <https://github.com/stevencarpenter/token-auditor>. Lint/type/test run there, not here. The
dotfiles pin it in the `TOKEN_AUDITOR_VERSION` variable at the top of the `Justfile` (set to
`"latest"` to track `main`) and install it via `just sync`. The install is **unconditional** on
every machine by design; the former `token_auditor` capability was dropped (2026-07-17) because no
consumer read it. Re-add the cap with real plumbing (see the machine.env pattern in `tiling.nix`)
only if a host ever needs an opt-out.

```bash
uv tool install git+https://github.com/stevencarpenter/token-auditor   # manual install / upgrade
token-auditor --help                                                   # or `codax --help`
```

### Nix (build / switch / validate)

```bash
./rebuild.sh              # Auto-detect host from LocalHostName, sudo darwin-rebuild switch
./rebuild.sh work-mac     # Force a specific host config
just rebuild              # Same, via the task runner
nix flake check --no-build   # Evaluate every output without building (fast structural check)
just check                   # Alias for the above
./bootstrap.sh            # Fresh-machine setup (Lix, work-only age key, first switch, rustup)
just sync                 # Network/SSH side channels: git externals + token-auditor install
```

Raw configs under `home/` are out-of-store symlinks — editing them is live with no rebuild. A
`darwin-rebuild switch` is only needed for changes nix owns: packages, macOS defaults, gating, or a
secret/hook declaration.

### Pre-commit

```bash
pre-commit run --all-files
```

## Architecture

### Layout & module conventions

```
flake.nix                 # inputs + mkHost fold → darwinConfigurations.<host>
lib/machines.nix          # capability table (the single source of per-host variance)
hosts/*.nix               # thin per-host shims; host-scoped declarations only
modules/darwin/*.nix      # system scope (specialArgs): core, macos-defaults, homebrew
modules/home/*.nix        # home scope (extraSpecialArgs): dotfiles, shell, packages,
                          #   tiling, dev-tools, ai-stack, secrets, sync-hooks
home/                     # raw dotfiles, real dotted names, symlinked out-of-store
secrets/                  # work-only age ciphertext + recipients
```

Conventions:
- **No hostname checks in modules.** All per-host variance flows from `lib/machines.nix` through
  `specialArgs` (darwin) / `extraSpecialArgs` (home-manager) as `{ inputs; hostName; user; caps;
  identity; }`. Modules take only what they use and gate on `caps.<x>` / `identity`.
- **Raw dotfiles are out-of-store symlinks.** `modules/home/dotfiles.nix` links each `home/<path>`
  via `config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/.dotfiles/home/<path>"`,
  gated by caps/identity. Editing the target is live — no rebuild.
- **Templates were resolved at port time.** What used to be `.tmpl` is now either a static per-host
  file selected by `identity` (e.g. `aerospace.{personal,work}.toml` in `tiling.nix`) or a small
  nix-generated `home.file.<x>.text` (e.g. `sketchybar/machine.env` from
  `caps.sketchybar_workspace_badges`).
- **Nix owns packages & system state**, not in-shell init: `home.packages` (CLI + fonts),
  `modules/darwin/homebrew.nix` (GUI casks + macOS-native tooling), `system.defaults.*` (macOS
  prefs), `launchd` agents, and the login-shell pin. z4h owns the shell (`programs.zsh.enable =
  false`); all zsh files stay raw symlinks.

**Adding a machine:** copy a row in `lib/machines.nix`, flip caps, add the name to the
`detect_host` map in `bootstrap.sh` / `rebuild.sh`. **Adding a capability:** add the key to *every*
row (`flake.nix` asserts the row shape) and gate the owning module on `caps.<capability>`.

### MCP Sync System (`mcp_sync/`)

The sync tool reads `home/.config/mcp/mcp-master.json` and generates tool-specific configs:

- **Master config**: `home/.config/mcp/mcp-master.json` — shared servers deployed to all machines
- **Machine overlays**: `home/.config/mcp/machine/{personal,work,lab}.json` — machine-type-specific
  servers (e.g., AWS MCP on work only). Static files now (the old `.tmpl` overlays were resolved at
  port time); `modules/home/dotfiles.nix` symlinks the overlay for this host's `identity`.
- **Templates**: `mcp_sync/src/mcp_sync/templates/` — base config templates per tool
- **Transform functions** in `sync.py`: `transform_to_copilot_format()`, `transform_to_identity_format()`,
  `transform_to_mcpservers_format()`, `transform_to_opencode_format()`
- **Merge order**: base template + master + machine overlay + per-tool overrides (later values win).
  The overrides layer is wired in `sync.py` — each target reads `~/.config/mcp/overrides/<key>.json`
  at sync time — but no override files are managed in-repo yet (`dotfiles.nix` links a `.keep`
  marker so `~/.config/mcp/overrides/` exists but is otherwise empty).

The sync runs automatically after every `darwin-rebuild switch` via the `mcpSync`
`home.activation` entry in `modules/home/sync-hooks.nix` (gated on `caps.mcp`). The hook selects
the overlay for this host's `identity` (`~/.config/mcp/machine/<identity>.json`) at nix eval time
and passes it via `--machine-config` — it does not glob whatever overlay sorts first on disk. It
uses the nix-store `uv`/`python314`, runs after `writeBoundary`, and warns-but-never-fails the
switch. Run it by hand with `just mcp-sync`.

#### Machine-Type Gating

All per-host variance flows from the `caps` set + `identity` string in `lib/machines.nix`, threaded
into modules via specialArgs. Gating replaced two chezmoi mechanisms with one: a `.chezmoiignore`
`hasPrefix`/`(index .machines .machine).<cap>` line becomes a `lib.mkIf caps.<x>` /
`lib.optionalAttrs (identity == "…")` in the module that owns the thing. There is exactly one gate
site per concern, and `nix flake check` fails evaluation if a gate references an undefined
capability. The full per-capability rationale lives as comments in `lib/machines.nix`; the table is
in `README.md`. Where each capability is enforced:

- **`tiling`** — `modules/home/tiling.nix` (aerospace/sketchybar/borders symlinks + restart
  activation) and `modules/darwin/homebrew.nix` (WM tap/brew/cask block, `font-sketchybar-app-font`).
- **`sketchybar_workspace_badges`** — `modules/home/tiling.nix` generates
  `~/.config/sketchybar/machine.env` (`SKETCHYBAR_WORKSPACE_BADGES=0/1`).
- **`atuin`** — `modules/home/dotfiles.nix` links `~/.config/atuin/config.toml`.
- **`mcp`** — `modules/home/dotfiles.nix` (master config + overlay + overrides `.keep`) and the
  `mcpSync` hook in `modules/home/sync-hooks.nix`. (No github MCP server ships anywhere: `mcp_sync`
  strips a `github` server via `RETIRED_MCP_SERVER_NAMES`, and the `github@claude-plugins-official`
  plugin — which bundles a remote GitHub MCP server — is pinned `false` in
  `home/.claude/settings-base.json`. `gh-axi` is used for GitHub instead.)
- **`skills`** — `modules/home/dotfiles.nix` (manifest + overlay) and the `skillsSync` hook. Also
  gates the work-only decrypted skill blobs in `modules/home/secrets.nix`.
- **`gui`** — `modules/darwin/homebrew.nix` (GUI casks) and `modules/home/packages.nix` (display
  fonts). CLI casks like `1password-cli` stay outside this gate.
- **`dev`** — `modules/home/dev-tools.nix` (mise `conf.d/dev.toml`), `modules/home/packages.nix`
  (dev fonts), `modules/darwin/homebrew.nix` (railway CLI + dev font casks), and
  `home/.claude/settings-base.json` variant (dev-only LSP plugins, resolved in `ai-stack.nix`).
- **`infra`** — `modules/home/dev-tools.nix` (mise `conf.d/infra.toml`).
- **`agent_journal`** — `modules/home/dotfiles.nix` (config + `~/.local/bin/{agent-journal,agent-note}`).
- **`agents`** — the `agentsInstall` hook (`sync-hooks.nix`) + the capability-aware personal
  registry clone in `just sync`; the `emit-routing-context.sh` SessionStart hook is unioned in
  `ai-stack.nix`. A work-host sync never contacts the personal registry remote.
- token-auditor is **not capability-gated**: `just sync` installs it unconditionally (pin in the
  Justfile's `TOKEN_AUDITOR_VERSION`; public https repo). The former orphan `token_auditor` cap
  was dropped 2026-07-17.

Identity-flavored splits (personal/work/lab shell profiles, hippo, homelab-over-Tailscale for
`!= "work"`) live in `modules/home/dotfiles.nix` and `modules/home/secrets.nix` as
`lib.optionalAttrs (identity == "…")`.

> No `wireguard` capability is defined. The home network uses Tailscale (WireGuard under the hood);
> if a future device needs a raw WG tunnel, add the capability then with a real consumer in tree.
> See `docs/networking.md`.

**Adding a machine:** add a row to `lib/machines.nix` and the `detect_host` map in `bootstrap.sh` /
`rebuild.sh`. **Adding a capability:** add the key to every row (`flake.nix` asserts the row shape)
and gate the owning module on `caps.<capability>`.

### Key Directories

- `flake.nix` — inputs + `mkHost` fold → `darwinConfigurations.<host>`
- `lib/machines.nix` — per-machine capability table (single source of truth for gating)
- `hosts/*.nix` — thin per-host shims; host-scoped declarations only
- `modules/darwin/` — system scope: `core.nix`, `macos-defaults.nix`, `homebrew.nix`
- `modules/home/` — home scope: `dotfiles`, `shell`, `packages`, `tiling`, `dev-tools`, `ai-stack`, `secrets`, `sync-hooks`
- `home/` — raw dotfiles (real dotted names), symlinked out-of-store through `~/.dotfiles`
- `home/.config/mcp/` — master MCP config + per-machine overlays (override layer wired in `sync.py`; no override files managed in-repo yet)
- `home/.config/nvim/` — Neovim config (LazyVim)
- `secrets/` — work-only age ciphertext + `secrets.nix` recipients (decrypted by agenix at work activation)
- `mcp_sync/` — MCP + skills fan-out tool (uv project, Python 3.14+, no runtime deps)
- `bootstrap.sh` / `rebuild.sh` — fresh-machine setup / routine switch (host auto-detect)
- `Justfile` — `TOKEN_AUDITOR_VERSION` pin + nix/python/sync recipes
- `scripts/` — hygiene test scripts (statusline, sketchybar, claude-settings-order, mcp-sync) + `strip-claude-trailer.sh`
- `docs/ai-tools/` — Setup guides for MCP, Copilot, etc.
- `docs/nix-migration.md` — chezmoi → nix mechanism map

### Tmux Status Bar Integration

A monitor script (`home/.config/tmux/scripts/claude-pane-monitor.sh`) runs every status-interval and
sets per-window `@claude_state` options. The everforest color palette is defined inline (no theme
plugin) so the monitor has full control over `window-status-format` and
`window-status-current-format` with stoplight colors:

- **Green** (`#a7c080`) — actively working (braille spinner in pane title)
- **Yellow** (`#dbbc7f`) — waiting for input (pane title contains ✳)

Window names show `#{pane_title}` via `automatic-rename-format`, so tabs display Claude session
names and state spinners instead of version numbers.

### Secrets

Personal and work secret authoring deliberately differ:

- **Personal:** add an `op://` reference to the appropriate template under `home/`, keep the target
  in `home/.config/op/render-manifest`, run `op-render`, and verify mode `0600`, structural parity,
  no unresolved references, and a fresh `.last-render` sentinel. Personal declares zero
  `age.secrets`. For reviewed edits to the rendered `.personal.env`, run `just op-adopt` for a
  names-only plan and let the user run `just op-adopt --apply` after review. Never run the apply
  path on the user's behalf. Adoption is limited to exact mappings in
  `home/.config/op/adopt-policy.json`; Login items and SSH config remain manual/render-only.
- **Work:** the temporary bridge remains age ciphertext under `secrets/`, decrypted by agenix using
  the work-only identity at `~/.config/age/keys.txt`. Use `agenix -e`, update
  `modules/home/secrets.nix`, and rebuild until the external work wrapper replaces this custody.

Do NOT `builtins.readFile` a decrypted value anywhere; that would bake plaintext into the public
Nix store. Full workflows are in `secrets/README.md` and the project secret-authoring skill.

## CI

GitHub Actions in `.github/workflows/`:
- `mcp-sync-ci.yml` — lint + test for the vendored `mcp_sync` tool (token-auditor and aws_config_gen CI live in their own repos now)
- `nix-flake-check.yml` — `nix flake check --no-build` on `macos-latest` (DeterminateSystems/nix-installer-action); evaluates every flake output so a broken module or bad option is a hard error
- `dotfiles-hygiene-ci.yml` — repo-wide hygiene: pre-commit, MCP master-config structure, shell `bash -n` syntax, and the statusline / sketchybar / claude-settings-order test scripts

## Style

- Shell scripts: `set -euo pipefail`, bash
- Python: ruff for linting and formatting, no runtime dependencies, Python 3.14+
  - 4-space indentation, `snake_case` for modules/functions, `PascalCase` for classes
  - Verbose Google-style docstrings on classes/functions with typed `Args:` / `Returns:` sections;
    include `Raises:` when relevant
- Package manager: uv (not pip/poetry)
- Tests: `test_*.py` filenames and `test_*` function names (enforced by pre-commit)
- Nix: 2-space indentation; keep modules small and readable, with comments that explain constraints
  (the flake ships no formatter, so match surrounding style by hand)
- Raw dotfiles: live under `home/` with their real dotted names (no `dot_`/`encrypted_` prefixes);
  gating is nix (`mkIf`/`optionalAttrs`), not filename convention
- Prefer small, focused edits; keep scripts idempotent and safe to re-run

## IntelliJ MCP in this repo

The `mcp__idea__*` tools need explicit targeting — called bare they fail with "Unable to
determine the target project for the current MCP tool call" or "No argument is passed for
required parameter 'pathInProject'". When using them in this repo, always pass
`projectPath=~/.dotfiles`, a **repo-relative** `pathInProject`
(e.g. `mcp_sync/src/mcp_sync/sync.py`), and the **exact** current `oldText` for replacements.
The global `~/.claude/CLAUDE.md` covers *preferring* these tools; this note is the
repo-specific targeting that makes them resolve.

## Commits & Pull Requests

History uses Conventional Commit prefixes: `feat:`, `fix:`, `chore:`, `docs:`, `refactor:`.

- Format: `type: short imperative summary` (optionally append `(#NN)` for PR/issue references)
- Keep each commit scoped to one concern
- PRs should include: purpose, key changed paths, test/lint evidence, and any config/security
  impact (especially secrets, MCP, or shell-startup behavior)
- Include screenshots only when UI/docs rendering changes need visual confirmation
- **Do not add a `Co-Authored-By` trailer, or any "generated by" / "created by" attribution
  naming an AI agent, assistant, or harness (Claude, Codex, Copilot, Gemini, etc.), to commits
  in this repo.** This overrides the harness default. Slash commands that template such a
  trailer must strip it before committing here.
