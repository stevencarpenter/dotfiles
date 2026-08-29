# CLAUDE.md

Guidance for Claude Code (claude.ai/code) and Codex (`AGENTS.md` is a symlink to this file) when
working in this repo. Global personal preferences are in `~/.claude/CLAUDE.md`; do not duplicate
them here.

## Repository

This is a personal macOS dotfiles repository implemented as a nix-darwin and home-manager flake.
Nix manages packages, macOS defaults, capability gating, and orchestration. Raw configuration files
retain their dotted names under `home/` and are symlinked through `~/.dotfiles` without entering the
Nix store. Edits to raw configuration files take effect without a rebuild.

`lib/machines.nix` defines the capability table for all hosts, currently only `personal-mac`.
Modules select behavior by capability and identity, not hostname. `op-render` renders secrets from
1Password. No identity declares `age.secrets`, and the repository does not depend on agenix.
Externally managed hosts keep their secrets in their own flakes.

The repository includes the Python tools `mcp_sync/` and `agent_reap/`. Two other Python tools are
installed from separate public repositories: `token-auditor`
(github.com/stevencarpenter/token-auditor, installed by `just sync`) and `aws_config_gen`
(github.com/stevencarpenter/aws-config-generator). The external work flake manages AWS profile
generation, so this repository does not define the `aws_sso` capability.

## Commands

All Python commands run from the repo root. Each tool is its own `uv` project.

Both vendored Python tools use PEP 735 `[dependency-groups]`; install dev deps with `--group dev`.

### Agent Reap (`agent_reap/`)

Finds and reaps idle Claude Code teammate panes across *every* tmux socket. Teams in tmux mode
leave one pane per teammate alive after the work is done; nothing closes them, so they
accumulate until they exhaust the subagent budget. Report-only unless `--kill` is passed;
team leads and idle interactive sessions are never killed without a further explicit flag.

```bash
just reap            # report (kills nothing)
just reap-sockets    # every tmux server; shows why `tmux kill-server` missed one
just reap-strays     # ssh control masters + disowned descendants (report-only)
just reap-kill       # actually reap idle teammate panes

uv run --project agent_reap --group dev ruff check agent_reap/src agent_reap/tests
uv run --project agent_reap --group dev ruff format --check agent_reap/src agent_reap/tests
uv run --project agent_reap --group dev mypy agent_reap/src agent_reap/tests
uv run --project agent_reap --group dev pytest agent_reap/tests --cov=agent_reap
```

`just sync` installs the local uv tool through `scripts/sync-side-channels.sh` on every machine.
Without a tmux server or team directory, the tool exits without action. No capability gate is
required. `just sync` manages `~/.local/bin/agent-reap`; only
`~/.config/agent-reap/config.toml` is symlinked by `modules/home/dotfiles.nix`.
It is not a daemon: automatic cleanup is the Claude `SessionEnd` hook, and solo sessions do not
create a hook log. See `docs/ai-tools/tmux-runtime-lifecycle.md` before diagnosing tmux cwd,
detach, socket, pane/process, stateful-plugin, generated-config, or stale-binary behavior.

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

### Token Auditor (external `token-auditor` uv tool)

`token-auditor` (the auditor behind the `codax`/`claade`/`opencade` wrappers) is maintained in its own
repo: <https://github.com/stevencarpenter/token-auditor>. Lint/type/test run there, not here. The
dotfiles pin it in `versions/token-auditor` (read by both the Justfile and direct sync script) and
install it via `just sync`. The install is **unconditional** on
every machine by design; the former `token_auditor` capability was dropped (2026-07-17) because no
consumer read it. Re-add the capability only with a module that reads it. The `machine.env` pattern
in `tiling.nix` provides an example.

```bash
uv tool install git+https://github.com/stevencarpenter/token-auditor   # manual install / upgrade
token-auditor --help                                                   # or `codax --help`
```

### Nix (build / switch / validate)

```bash
./rebuild.sh              # Auto-detect host from LocalHostName, sudo darwin-rebuild switch
./rebuild.sh personal-mac # Force a specific host config
just rebuild              # Same, via the task runner
nix flake check --no-update-lock-file --no-build --all-systems   # Evaluate all-host checks
just check                   # Alias for the above
just update                  # Default pin bump: 26.05 inputs + unstable soak + brew.
                             #   Never switches. Review, then `just sync`.
just update 14               # Same, with a 14-day unstable soak window
just update-unstable         # Record today's nixpkgs-unstable tip; after 7 elapsed
                             #   days promote/build it and print the closure diff.
just update-unstable 14      # Wider soak window
./bootstrap.sh            # Fresh-machine setup (Lix, Homebrew, first switch, rustup)
just sync                 # Full deploy: switch, then op-render secrets + git externals + agents
                          #   + token-auditor. The sequence is required.
just sync-side-channels   # Side channels only, skipping the rebuild
```

Raw configs under `home/` are out-of-store symlinks. Edits take effect without a rebuild. A
`darwin-rebuild switch` is only needed for changes Nix manages: packages, macOS defaults, gating, or a
secret/hook declaration.

`nixpkgs-unstable` is pinned to a **rev**, not to the branch, so `nix flake update` cannot move it
and every bump is a reviewable `git diff`. `just update-unstable` first records the current channel
tip and a local first-seen time, then promotes that exact rev only after the requested elapsed soak;
it never infers channel age from a commit timestamp. A lockfile's narHash proves the tree was not
tampered with, not that it was benign when locked. Do not bump this input by hand. Branch pins and
pin/lock disagreement fail `scripts/test-nix-review-regressions.sh`.
`scripts/update-unstable.sh` documents the rationale. The package allowlist is
`fastMovingPackages` in `modules/home/packages.nix`.

### Pre-commit

```bash
pre-commit run --all-files
```

## Architecture

### Layout & module conventions

```
flake.nix                 # inputs + mkHost fold → darwinConfigurations.<host>
lib/machines.nix          # complete capability table for per-host variance
hosts/*.nix               # host-scoped declarations only
modules/darwin/*.nix      # system scope (specialArgs): core, macos-defaults, homebrew
modules/home/*.nix        # home scope (extraSpecialArgs): dotfiles, shell, packages,
                          #   tiling, dev-tools, ai-stack, sync-hooks
home/                     # raw dotfiles, real dotted names, symlinked out-of-store
secrets/                  # documentation only; no ciphertext, no age secrets
```

Conventions:
- **No hostname checks in modules.** `lib/machines.nix` defines all per-host variance.
  `specialArgs` (darwin) and `extraSpecialArgs` (home-manager) pass `{ inputs; hostName; user; caps;
  identity; }` to modules. Modules take only what they use and gate on `caps.<x>` or `identity`.
- **Raw dotfiles are out-of-store symlinks.** `modules/home/dotfiles.nix` links each `home/<path>`
  via `config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/.dotfiles/home/<path>"`,
  gated by caps/identity. Target edits take effect without a rebuild.
- **Adopting a new tool's config** (promote a test-driven config into the repo): follow
  `docs/adopting-a-config.md`. Copy it under `home/`, choose file or directory linking, add the
  `mkLinks` entry, clear the collision, rebuild. Claude Code has the `adopt-config` skill for this.
- **Templates were resolved at port time.** What used to be `.tmpl` is now either a static per-host
  file selected by `identity` (e.g. `aerospace.{personal,work}.toml` in `tiling.nix`) or a small
  nix-generated `home.file.<x>.text` (e.g. `sketchybar/machine.env` from
  `caps.sketchybar_workspace_badges`).
- **Nix manages packages and system state**, not in-shell initialization: `home.packages` (CLI + fonts),
  `modules/darwin/homebrew.nix` (GUI casks + macOS-native tooling), `system.defaults.*` (macOS
  preferences), `launchd` agents, and the login-shell pin. z4h manages the shell (`programs.zsh.enable =
  false`); all zsh files stay raw symlinks.

**Adding a machine:** copy a row in `lib/machines.nix`, set its capabilities, add the name to the
shared detect map in `scripts/host-detect.sh`. **Adding a capability:** add the key to *every*
row (`flake.nix` asserts the row shape) and gate the owning module on `caps.<capability>`.

### MCP Sync System (`mcp_sync/`)

The sync tool reads `home/.config/mcp/mcp-master.json` and generates tool-specific configs:

- **Master config**: `home/.config/mcp/mcp-master.json`, with shared servers deployed to all machines
- **Machine overlays**: `home/.config/mcp/machine/{personal,work,lab}.json`, with machine-type-specific
  servers (e.g., AWS MCP on work only). Static files now (the old `.tmpl` overlays were resolved at
  port time); `modules/home/dotfiles.nix` symlinks the overlay for this host's `identity`.
- **Templates**: `mcp_sync/src/mcp_sync/templates/`, with base config templates per tool
- **Transform functions** in `sync.py`: `transform_to_copilot_format()`, `transform_to_identity_format()`,
  `transform_to_mcpservers_format()`, `transform_to_opencode_format()`
- **Merge order**: base template + master + machine overlay + per-tool overrides. Later values
  override earlier values.
  `sync.py` implements the overrides layer. Each target reads `~/.config/mcp/overrides/<key>.json`
  at sync time. No override files are managed in the repository (`dotfiles.nix` links a `.keep`
  marker so `~/.config/mcp/overrides/` exists but is otherwise empty).

The sync runs automatically after every `darwin-rebuild switch` via the `mcpSync`
`home.activation` entry in `modules/home/sync-hooks.nix` (gated on `caps.mcp`). The hook selects
the overlay for this host's `identity` (`~/.config/mcp/machine/<identity>.json`) at nix eval time
and passes it via `--machine-config`. It does not select an overlay by filename sort order. It uses
the Nix store `uv` and `python314`, runs after `writeBoundary`, and reports failures without failing
the switch. Run it manually with `just mcp-sync`.

#### Machine-Type Gating

The `caps` set and `identity` string in `lib/machines.nix` define all per-host variance.
`specialArgs` passes both values to modules. Gating replaced two chezmoi mechanisms with one: a
`.chezmoiignore`
`hasPrefix`/`(index .machines .machine).<cap>` line becomes a `lib.mkIf caps.<x>` /
`lib.optionalAttrs (identity == "…")` in the module that manages the configuration. There is
exactly one gate site per concern. `nix flake check` fails evaluation if a gate references an
undefined capability. Comments in `lib/machines.nix` document each capability. `README.md`
contains the capability table. Each capability is enforced at these locations:

- **`tiling`**: `modules/home/tiling.nix` (aerospace/sketchybar/borders symlinks + restart
  activation) and `modules/darwin/homebrew.nix` (WM tap/brew/cask block, `font-sketchybar-app-font`).
- **`sketchybar_workspace_badges`**: `modules/home/tiling.nix` generates
  `~/.config/sketchybar/machine.env` (`SKETCHYBAR_WORKSPACE_BADGES=0/1`).
- **`atuin`**: `modules/home/dotfiles.nix` links `~/.config/atuin/config.toml` on *every* machine;
  the capability selects which variant (`config.sync.toml` with the self-hosted `sync_address`, vs
  `config.local.toml` with `auto_sync = false`). Both include `history_filter` and `[tmux] enabled`.
  `scripts/test-atuin-filter-parity.sh` keeps the two filter lists identical.
- **`mcp`**: `modules/home/dotfiles.nix` (master config + overlay + overrides `.keep`) and the
  `mcpSync` hook in `modules/home/sync-hooks.nix`. (No github MCP server ships anywhere: `mcp_sync`
  strips a `github` server via `RETIRED_MCP_SERVER_NAMES`, and the `github@claude-plugins-official`
  plugin, which bundles a remote GitHub MCP server, is pinned `false` in
  `home/.claude/settings-base.json`. `gh-axi` is used for GitHub instead.)
- **`skills`**: `modules/home/dotfiles.nix` (manifest + overlay) and the `skillsSync` hook.
  **Git-source provenance is enforced in code**, not just by review: a git skill source is a
  tracking clone (`fetch` + `reset --hard FETCH_HEAD`) whose contents an agent then executes, so
  `resolve_skills` rejects any source whose `<host>/<owner>` is not in an allowlist
  (`DEFAULT_ALLOWED_GIT_OWNERS` in `mcp_sync/src/mcp_sync/skills.py`). An empty or
  malformed `allowedGitOwners` is an error, never allow-all. This repo's default names only the
  maintainer's own forge account; a machine overlay extends the list via `allowedGitOwners` (it
  deep-merges into the manifest). A private overlay can permit its own organization without adding
  that organization's name to this public repository.
- **`gui`**: `modules/darwin/homebrew.nix` (GUI casks) and `modules/home/packages.nix` (display
  fonts). CLI casks like `1password-cli` stay outside this gate.
- **`dev`**: `modules/home/dev-tools.nix` (mise `conf.d/dev.toml`), `modules/home/packages.nix`
  (dev fonts), `modules/darwin/homebrew.nix` (railway CLI + dev font casks), and
  `home/.claude/settings-base.json` variant (dev-only LSP plugins, resolved in `ai-stack.nix`).
- **`infra`**: `modules/home/dev-tools.nix` (mise `conf.d/infra.toml`).
- **`agent_journal`**: `modules/home/dotfiles.nix` (config + `~/.local/bin/{agent-journal,agent-note}`).
- **`agents`**: capability-aware personal registry clone, install, routing-cache refresh, and
  validation in `just sync`; the `emit-routing-context.sh` SessionStart hook is unioned in
  `ai-stack.nix`. A work-host sync never contacts the personal registry remote.
- token-auditor is **not capability-gated**: `just sync` installs it unconditionally (release in
  `versions/token-auditor`; public https repo). The unused `token_auditor` capability
  was dropped 2026-07-17.

Identity-specific configurations (personal/work/lab shell profiles, hippo, and
homelab-over-Tailscale for `!= "work"`) are defined as
`lib.optionalAttrs (identity == "…")` blocks across the home modules — chiefly
`modules/home/dotfiles.nix`, with identity-based file selection in
`tiling.nix` (aerospace variants) and identity/capability gating in
`ai-stack.nix`. There is no secrets module: the age bridge was removed.

> No `wireguard` capability is defined. The home network uses Tailscale, which uses WireGuard;
> if a future device needs a raw WG tunnel, add the capability with a module that reads it.
> See `docs/networking.md`.

**Adding a machine:** add a row to `lib/machines.nix` and the shared detect map in
`scripts/host-detect.sh`. **Adding a capability:** add the key to every row (`flake.nix` asserts the row shape)
and gate the owning module on `caps.<capability>`.

### Key Directories

- `flake.nix`: inputs and `mkHost` fold to `darwinConfigurations.<host>`
- `lib/machines.nix`: complete per-machine capability table
- `hosts/*.nix`: host-scoped declarations
- `modules/darwin/`: system scope (`core.nix`, `macos-defaults.nix`, `homebrew.nix`)
- `modules/home/`: home scope (`dotfiles`, `shell`, `packages`, `tiling`, `dev-tools`, `ai-stack`,
  `sync-hooks`)
- `home/`: raw dotfiles with their real names, symlinked out of store through `~/.dotfiles`
- `home/.config/mcp/`: master MCP config and per-machine overlays; `sync.py` implements overrides
- `home/.config/nvim/`: Neovim config (LazyVim)
- `secrets/`: documentation only; no ciphertext or age secrets
- `mcp_sync/`: MCP and skills config generator (uv project, Python 3.14+, no runtime dependencies)
- `agent_reap/`: idle Claude teammate reaper (uv project, Python 3.14+, no runtime dependencies)
- `bootstrap.sh` / `rebuild.sh`: new-machine setup and routine switch with host auto-detection
- `Justfile`: Nix, Python, and sync recipes; `versions/token-auditor` specifies the tool release
- `scripts/`: hygiene tests and `strip-claude-trailer.sh`
- `docs/ai-tools/`: setup guides for MCP, Copilot, and related tools, plus
  `hippo-usage-measurement.md` (hippo recall baseline, re-measure dates, and query constraints)

### Tmux Status Bar Integration

A monitor script (`home/.config/tmux/scripts/claude-pane-monitor.sh`) runs every status-interval and
sets per-window `@claude_state` options. The everforest color palette is defined inline without a
theme plugin. The monitor sets `window-status-format` and `window-status-current-format` using
state colors:

- **Green** (`#a7c080`): actively working (pane title begins with a braille spinner)
- **Yellow** (`#dbbc7f`): waiting for input (pane title begins with ✳)

Titles without one of those state markers, such as an editor-set `nvim` title, are not classified
as Claude panes.

Window names show `#{pane_title}` via `automatic-rename-format`, so tabs display Claude session
names and state spinners instead of version numbers.

The cwd contract is separate from window identity. `prefix c`, `prefix |`, and `prefix -` pass
`-c "$HOME"` so a new shell does not inherit a foreground agent's launch directory. The hygiene
test loads the configuration into an isolated tmux server and checks the effective final bindings,
including later overrides. Runtime debugging and cleanup procedures are in
`docs/ai-tools/tmux-runtime-lifecycle.md`.

### Secrets

Personal and work secrets use different workflows:

- **Personal:** add an `op://` reference to the appropriate template under `home/`, keep the target
  in `home/.config/op/render-manifest`, run `just sync` (or `op-render` directly), and verify mode
  `0600`, structural parity, no unresolved references, and an updated `.last-render` sentinel.
  op-render must run from an interactive terminal: `just sync` runs `eval "$(op signin)"` right
  before it (TTY-guarded, since `op signin` blocks on input) because op sessions expire after ~30
  minutes. Activation only runs `op-render --warn-stale-only`.
  For reviewed edits to the rendered `.personal.env`, run `just op-adopt` for a
  names-only plan and let the user run `just op-adopt --apply` after review. Never run the apply
  path on the user's behalf. Adoption is limited to exact mappings in
  `home/.config/op/adopt-policy.json`; Login items and SSH config remain manual/render-only.
- **Work:** work-host secrets are managed outside this repository. The age bridge (ciphertexts,
  recipient file, and `modules/home/secrets.nix`) was removed; no host declares `age.secrets` or an
  age identity. The external host's flake manages its secrets.

Do not add an age secret to this repository or pass a decrypted value to `builtins.readFile`.
Either action would include plaintext in the public Nix store. Procedures are in `secrets/README.md`
and the project secret-authoring skill.

## CI

GitHub Actions in `.github/workflows/`:
- `mcp-sync-ci.yml`: lint and test for `mcp_sync`; token-auditor and aws_config_gen run CI in their
  repositories
- `agent-reap-ci.yml`: lint and test for `agent_reap`
- `nix-flake-check.yml`: Nix formatting, explicit `checks.<system>.<host>` evaluation, and both
  Darwin builds on `macos-latest`
- `dotfiles-hygiene-ci.yml`: pre-commit, MCP master-config structure, shell `bash -n` syntax, and
  configuration test scripts

## Style

- Shell scripts: `set -euo pipefail`, bash
- Python: ruff for linting and formatting, no runtime dependencies, Python 3.14+
  - 4-space indentation, `snake_case` for modules/functions, `PascalCase` for classes
  - Verbose Google-style docstrings on classes/functions with typed `Args:` / `Returns:` sections;
    include `Raises:` when relevant
  - **No inline Python.** A heredoc or `python -c` body belongs in its own file, next to the
    caller, which then execs it by path. Shell scripts, hooks, and CI steps call the file.
  - Every standalone script (anything outside `mcp_sync/`, `agent_reap/`, and the
    `firefox-dashboard-tabs/` package body) starts with `#!/usr/bin/env -S uv run --script`
    followed by a PEP 723 `# /// script` block enumerating `requires-python` and `dependencies`,
    even when the list is empty. A script importing a repo project names it in `dependencies`
    with a `[tool.uv.sources]` path relative to the script's own directory.
  - Exception: `home/.claude/hooks/lib/*.py` is exec'd as `/usr/bin/python3 <path>` by the reap
    hooks and must stay 3.9-compatible. Session teardown runs under a 20s Claude cap and cannot
    depend on uv resolving an environment; the shebang there is for manual runs only.
- Package manager: uv (not pip/poetry)
- Tests: `test_*.py` filenames and `test_*` function names (enforced by pre-commit)
- Nix: `nixfmt` via `nix fmt`; 2-space indentation; keep modules small and readable, with comments
  that explain constraints
- Raw dotfiles: store them under `home/` with their real dotted names (no `dot_`/`encrypted_` prefixes);
  gating is nix (`mkIf`/`optionalAttrs`), not filename convention
- Prefer small, focused edits; keep scripts idempotent and safe to re-run

## IntelliJ MCP in this repo

The `mcp__idea__*` tools require explicit targeting. Without target arguments they fail with "Unable to
determine the target project for the current MCP tool call" or "No argument is passed for
required parameter 'pathInProject'". When using them in this repo, always pass
`projectPath=~/.dotfiles`, a **repo-relative** `pathInProject`
(e.g. `mcp_sync/src/mcp_sync/sync.py`), and the **exact** current `oldText` for replacements.
The global `~/.claude/CLAUDE.md` defines tool priority. These repository-specific arguments are
required for project resolution.

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
