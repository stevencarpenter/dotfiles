# CLAUDE.md

Guidance for Claude Code (claude.ai/code) and Codex (`AGENTS.md` is a symlink to this file) when
working in this repo. Global personal preferences are in `~/.claude/CLAUDE.md`; do not duplicate
them here.

## Repository

This is a personal macOS dotfiles repository managed by dotfiles-manager. The manager owns the
links from `~` into the checkout and the Claude settings merge. Homebrew owns packages
(`Brewfile`), mise owns runtimes and npm CLIs, and scripts under `scripts/` own macOS defaults,
the login shell and one LaunchAgent. Raw configuration files retain their dotted names under
`home/` and are symlinked through `~/.dotfiles`. Edits to raw configuration files take effect
without an apply.

`dfm/profiles/personal-mac.toml` selects the modules for the only host in this repository; an
external bundle extends `dfm-bundle.toml` for another identity (`docs/external-bundles.md`).
Modules select behavior
by capability and identity, not hostname. `op-render` renders secrets from 1Password. No host
holds an age identity. Externally managed hosts keep their secrets in their own overlays.

The repository includes the Python tools `mcp_sync/` and `agent_reap/`. Two other Python tools are
installed from separate public repositories: `token-auditor`
(github.com/stevencarpenter/token-auditor, installed by the side channels) and `aws_config_gen`
(github.com/stevencarpenter/aws-config-generator). The external work overlay manages AWS profile
generation, so this repository does not define an `aws_sso` capability.

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
just reap-kill       # reap idle teammate panes

uv run --project agent_reap --group dev ruff check agent_reap/src agent_reap/tests
uv run --project agent_reap --group dev ruff format --check agent_reap/src agent_reap/tests
uv run --project agent_reap --group dev mypy agent_reap/src agent_reap/tests
uv run --project agent_reap --group dev pytest agent_reap/tests --cov=agent_reap
```

The side channels install the local uv tool through `scripts/sync-side-channels.sh` on every
machine. Without a tmux server or team directory, the tool exits without action. No capability
gate is required. The side channels manage `~/.local/bin/agent-reap`; only
`~/.config/agent-reap/config.toml` is linked by the `core` module.
It is not a daemon: automatic cleanup is the Claude `Stop` and `SessionEnd` hooks, and solo sessions do not
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
dotfiles pin it in `versions/token-auditor` (read by the Justfile and the side-channel script) and
install it from the side channels. The install is **unconditional** on every machine by design;
the former `token_auditor` capability was dropped (2026-07-17) because no consumer read it.

```bash
uv tool install git+https://github.com/stevencarpenter/token-auditor   # manual install / upgrade
token-auditor --help                                                   # or `codax --help`
```

### Plan, apply, update

```bash
just sync-dfm                 # dfm plan; prints the digest, writes the approval flags
just sync-dfm-apply <digest>  # apply, then Brewfile, hooks-sync, side channels, agents, checks
just update                   # preview Homebrew and mise upgrades; approve; upgrade + side channels
just update -y                # same, assume approval (sudo/op may still prompt)
just sync-side-channels       # side channels only: mise, op-render, skills, Git sources, tools
./bootstrap.sh                # fresh-machine setup (CLT, Homebrew, Brewfile), then prints the steps
scripts/brew-sync.sh --check  # Brewfile gaps, installs nothing
scripts/mac-defaults.sh --check
dfm doctor --root ~/.dotfiles
dfm sync --root ~/.dotfiles --preview   # needs the one-time origin grant below
```

`dotfiles-manager.lock` at the checkout root declares the Git source `sync` fetches (root entry,
`ssh://git@github.com/stevencarpenter/dotfiles`, `refs/heads/main`). Grant that origin once per
machine: `dfm sync --root ~/.dotfiles --trust-origin ssh://git@github.com/stevencarpenter/dotfiles`.

See [Daily use](README.md#daily-use) for the command hierarchy.

Raw configs under `home/` are symlinks into the checkout. Edits take effect without an apply. An
apply is only needed for changes the manager owns: a new or removed link, a module's resources,
or the Claude settings merge. `docs/m5-cutover.md` records the cutover and is a historical
document; the nix sources it names were removed after section 12 ran.

### Git hooks (lefthook)

`lefthook.yml` defines the `pre-commit` and `commit-msg` jobs; it replaced
`.pre-commit-config.yaml` on 2026-08-29. The language-agnostic file checks are the same
`pre-commit-hooks` 6.0.0 entry points, run through `uvx` instead of pre-commit's own env
management, so nothing needs a global install beyond `lefthook`, `gitleaks`, and `uv`.

```bash
just lefthook            # run every pre-commit job against all files, as CI does
just lefthook-install    # wire .git/hooks (also done by the side channels)
lefthook run pre-commit  # staged files only, exactly what a commit triggers
lefthook validate        # config sanity
```

`lefthook install` runs from `scripts/sync-side-channels.sh`, so a machine that has run the
side channels has its hooks wired. lefthook has no equivalent of pre-commit's
`types: [text]` filter, so a job that rewrites files pipes its list through
`scripts/hook-text-files.py` first (handing a PNG to the whitespace fixer corrupts it).
The `gitleaks` job scans staged changes only; the whole-tree scan runs in CI.

## Architecture

### Layout & module conventions

```
dfm-bundle.toml           # module list + [sources] roots (home, skills, dfm)
dfm-module-*.toml         # one manifest per module; [[resources]] and [[contributions]]
dfm/profiles/<host>.toml  # modules a host selects: the capability table
Brewfile                  # every formula, cask and font
home/                     # raw dotfiles, real dotted names, symlinked into ~
skills/personal/          # locally authored skills, linked by the skills module
scripts/                  # system scripts, side channels, hygiene tests
secrets/                  # documentation only; no ciphertext, no age secrets
```

Conventions:
- **No hostname checks outside `scripts/host-detect.sh`.** The profile defines all per-host
  variance. A module is on for a host when the profile selects it.
- **Raw dotfiles are checkout symlinks.** Each `fs-link/v1` resource links `~/<target>` to
  `<checkout>/home/<path>`. Target edits take effect without an apply. A directory link
  carries `directory = true`.
- **Adopting a new tool's config** (promote a test-driven config into the repo): follow
  `docs/adopting-a-config.md`. Copy it under `home/`, choose file or directory linking, add the
  `[[resources]]` stanza, move the original aside, plan, apply. Claude Code has the
  `adopt-config` skill for this.
- **No templates.** Per-host variance is a static file selected by a module (e.g.
  `aerospace.personal.toml`, `sketchybar/machine.personal.env`).
- **Homebrew manages packages**, mise manages runtimes, and the scripts in
  `docs/m5-system-scripts.md` manage macOS defaults, the login shell and the maxfiles
  LaunchAgent. z4h manages the shell; all zsh files are raw symlinks.

**Adding a machine:** add `dfm/profiles/<name>.toml` and the name to the shared detect map in
`scripts/host-detect.sh`. **Adding a capability:** create `dfm-module-<name>.toml`, register it
under `[modules]` in `dfm-bundle.toml`, and select it in each profile that wants it.

### MCP Sync System (`mcp_sync/`)

The sync tool reads `home/.config/mcp/mcp-master.json` and generates tool-specific configs:

- **Master config**: `home/.config/mcp/mcp-master.json`, with shared servers deployed to all machines
- **Machine overlays**: `home/.config/mcp/machine/{personal,work,lab}.json`, with machine-type-specific
  servers (e.g., AWS MCP on work only). The `mcp` module links the overlay for this host's identity.
- **Templates**: `mcp_sync/src/mcp_sync/templates/`, with base config templates per tool
- **Transform functions** in `sync.py`: `transform_to_copilot_format()`, `transform_to_identity_format()`,
  `transform_to_mcpservers_format()`, `transform_to_opencode_format()`
- **Merge order**: base template + master + machine overlay + per-tool overrides. Later values
  override earlier values.
  `sync.py` implements the overrides layer. Each target reads `~/.config/mcp/overrides/<key>.json`
  at sync time. No override files are managed in the repository.

The sync runs during `just sync-dfm-apply` through `scripts/hooks-sync.sh`, which selects the
overlay for this host's identity (`~/.config/mcp/machine/<identity>.json`) and passes it via
`--machine-config`. It runs through `uv run --frozen --project mcp_sync` and reports failures
without failing the apply. Run it manually with `just mcp-sync`.

#### Capability gating

The profile's module list defines all per-host variance. Each module is enforced at these
locations:

- **`tiling`**: `dfm-module-tiling.toml` (shared sketchybar/borders links; the identity module
  links `aerospace.toml`, `machine.env` and `layouts`) and
  `scripts/tiling-reload.sh`. The WM tap, formulae and `font-sketchybar-app-font` are in the
  `Brewfile`.
- **`atuin`**: `dfm-module-atuin.toml` links `~/.config/atuin/config.toml` to `config.sync.toml`
  (self-hosted `sync_address`). A host without the module gets no managed atuin config;
  `config.local.toml` (`auto_sync = false`) is the variant for such a host; an external bundle's
  identity module links it. Both include `history_filter` and `[tmux] enabled`.
  `scripts/check-atuin-parity.py` keeps the two filter lists identical.
- **`mcp`**: `dfm-module-mcp.toml` (master config + pi + firstmate links; the identity module
  links the `machine/<identity>.json` overlay) and the
  `mcpSync` step of `scripts/hooks-sync.sh`. (No github MCP server ships anywhere: `mcp_sync`
  strips a `github` server via `RETIRED_MCP_SERVER_NAMES`, and the `github@claude-plugins-official`
  plugin, which bundles a remote GitHub MCP server, is pinned `false` in the
  `core.claude-settings` resource of `dfm-module-core.toml`. `gh-axi` is used for GitHub instead.)
- **`skills`**: `dfm-module-skills.toml` (manifest; the identity module links the overlay and the
  pinned skill links) and the
  `skillsSync` step of `scripts/hooks-sync.sh`.
  **Git-source provenance is enforced in code**, not just by review: a git skill source is a
  tracking clone (`fetch` + `reset --hard FETCH_HEAD`) whose contents an agent then executes, so
  `resolve_skills` rejects any source whose `<host>/<owner>` is not in an allowlist
  (`DEFAULT_ALLOWED_GIT_OWNERS` in `mcp_sync/src/mcp_sync/skills.py`). An empty or
  malformed `allowedGitOwners` is an error, never allow-all. This repo's default names only the
  maintainer's own forge account; a machine overlay extends the list via `allowedGitOwners` (it
  deep-merges into the manifest). A private overlay can permit its own organization without adding
  that organization's name to this public repository.
- **`gui`**: no resources. GUI casks and display fonts live in the `Brewfile`.
- **`dev`**: `dfm-module-dev.toml` (mise `conf.d/dev.toml`). The dev-only LSP plugins are the
  personal-mac variant of the Claude settings merge in `dfm-module-core.toml`.
- **`infra`**: `dfm-module-infra.toml` (mise `conf.d/infra.toml`).
- **`agent_journal`**: `dfm-module-agent-journal.toml` links the CLI wrappers; the identity
  module links `config.toml` and `workstreams.toml`.
- **`agents`**: contributes the `emit-routing-context.sh` SessionStart handler to the Claude
  settings merge. The personal registry clone, install and validation run in
  `scripts/sync-side-channels.sh`, gated by `scripts/host-capability.sh agents`. The registry
  (`stevencarpenter/agents`) is public, and a work host that selects `agents` installs it too.
- **`personal`** (identity): `dfm-module-personal.toml` links the personal shell profiles,
  hippo, homelab-over-Tailscale SSH fragment template, and contributes the
  hippo SessionStart handler. It also links the identity files of shared capabilities: the
  Claude `settings.d` `allowWrite` fragment, jj, the MCP and skills overlays, the pinned skills,
  the aerospace and sketchybar variants and the journal config. `Brewfile.personal` holds jj and
  tailscale.
- token-auditor is **not capability-gated**: the side channels install it unconditionally.

`scripts/host-capability.sh <cap>` prints 1 or 0 from the profile (the one `dfm binding` names,
or `dfm/profiles/<host>.toml` before bind) and `--identity` prints the identity module. The shell-side gates in `scripts/sync-side-channels.sh` read it; the hygiene
test `scripts/test-host-capability.sh` pins the personal-mac answers.

> No `wireguard` module is defined. The home network uses Tailscale, which uses WireGuard;
> if a future device needs a raw WG tunnel, add the module with a consumer that reads it.
> See `docs/networking.md`.

### Key Directories

- `dfm-bundle.toml`, `dfm-personal.toml`, `dfm-module-*.toml`, `dfm/profiles/`: the manager's
  declarations; `docs/external-bundles.md` is the contract for an external bundle
- `Brewfile`, `Brewfile.<identity>`: declared Homebrew inventory, applied by `scripts/brew-sync.sh`
- `home/`: raw dotfiles with their real names, symlinked through `~/.dotfiles`
- `home/.config/mcp/`: master MCP config and per-machine overlays; `sync.py` implements overrides
- `home/.config/nvim/`: Neovim config (LazyVim)
- `secrets/`: documentation only; no ciphertext or age secrets
- `mcp_sync/`: MCP and skills config generator (uv project, Python 3.14+, no runtime dependencies)
- `agent_reap/`: idle Claude teammate reaper (uv project, Python 3.14+, no runtime dependencies)
- `bootstrap.sh`: new-machine setup with host auto-detection
- `Justfile`: plan, apply, update, Python, and sync recipes; `versions/token-auditor` specifies the tool release
- `scripts/`: system scripts (`mac-defaults.sh`, `launch-agents.sh`, `login-shell.sh`,
  `tiling-reload.sh`, `brew-sync.sh`, `hooks-sync.sh`), side channels, hygiene tests
- `docs/ai-tools/`: setup guides for MCP, Copilot, and related tools, plus
  `hippo-usage-measurement.md` (hippo recall baseline, re-measure dates, and query constraints)
- `docs/m5-cutover.md`, `docs/m5-system-scripts.md`, `docs/package-mapping.md`: the cutover
  record, the system-script table, and how each package reached the Brewfile

### SketchyBar and native menu hover

The user accepted the current menu interaction on macOS 27.2: top-edge hover exposes a
clickable native menu, and leaving it promptly restores clickable SketchyBar workspace tabs.
Preserve both interactions and the smooth return when changing the tiling stack. The rationale
is beside the helper launch in `home/.config/sketchybar/sketchybarrc` and the window-ordering
command in `plugins/menu_bar_hover.swift`. Read those comments before simplifying this workaround.
`bash scripts/test-sketchybar-menu-hover-launch.sh` checks launcher lifecycle in isolation;
its header specifies the live acceptance checks that automated tests do not cover.

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
test uses an isolated tmux server to check pane classification and cleanup; key bindings and cwd
choices remain preferences. Runtime debugging and cleanup procedures are in
`docs/ai-tools/tmux-runtime-lifecycle.md`.

### Secrets

Personal and work secrets use different workflows:

- **Personal:** add an `op://` reference to the appropriate template under `home/`, keep the target
  in `home/.config/op/render-manifest`, run the side channels (or `op-render` directly), and verify
  mode `0600`, structural parity, no unresolved references, and an updated `.last-render` sentinel.
  op-render must run from an interactive terminal: the side channels run `eval "$(op signin)"`
  right before it (TTY-guarded, since `op signin` blocks on input) because op sessions expire
  after ~30 minutes.
  For reviewed edits to the rendered `.personal.env`, run `just op-adopt` for a
  names-only plan and let the user run `just op-adopt --apply` after review. Never run the apply
  path on the user's behalf. Adoption is limited to exact mappings in
  `home/.config/op/adopt-policy.json`; Login items and SSH config remain manual/render-only.
- **Work:** work-host secrets are managed outside this repository. The age bridge was removed;
  no host holds an age identity. The external overlay manages its secrets.

Do not add an age secret to this repository or render a plaintext value into a tracked file.
Procedures are in `secrets/README.md` and the project secret-authoring skill.

## CI

GitHub Actions in `.github/workflows/`:
- `mcp-sync-ci.yml`: lint and test for `mcp_sync`; token-auditor and aws_config_gen run CI in their
  repositories
- `agent-reap-ci.yml`: lint and test for `agent_reap`
- `dotfiles-hygiene-ci.yml`: lefthook pre-commit jobs, whole-tree gitleaks scan, MCP
  master-config structure, shell `bash -n` syntax, `ruff check .` over the Python that
  lives outside the two uv projects (root `ruff.toml`), and the configuration test scripts

## Style

- Shell scripts: `set -euo pipefail`, bash
- Python: ruff for linting and formatting, no runtime dependencies, Python 3.14+
  - The uv projects use their own `pyproject.toml`; everything else (scripts, hook libs,
    skill scripts) is covered by the root `ruff.toml`, which excludes vendored plugin
    skill scripts that are carried verbatim from upstream
  - 4-space indentation, `snake_case` for modules/functions, `PascalCase` for classes
  - Verbose Google-style docstrings on classes/functions with typed `Args:` / `Returns:` sections;
    include `Raises:` when relevant
  - **No inline Python.** A heredoc or `python -c` body belongs in its own file, next to the
    caller, which then execs it by path. Shell scripts, hooks, and CI steps call the file.
  - Every standalone script (anything outside the vendored `mcp_sync/` and `agent_reap/`
    projects) starts with `#!/usr/bin/env -S uv run --script`
    followed by a PEP 723 `# /// script` block enumerating `requires-python` and `dependencies`,
    even when the list is empty. A script importing a repo project names it in `dependencies`
    with a `[tool.uv.sources]` path relative to the script's own directory.
  - Exception: `home/.claude/hooks/lib/*.py` is exec'd as `/usr/bin/python3 <path>` by the reap
    hooks and must stay 3.9-compatible. Session teardown runs under a 20s Claude cap and cannot
    depend on uv resolving an environment. Those files use `#!/usr/bin/python3` so a manual
    run hits the same interpreter the hooks do.
- Package manager: uv (not pip/poetry)
- Tests: `test_*.py` filenames and `test_*` function names (enforced by the lefthook
  `name-tests-test` job)
- TOML manifests: 2-space indentation; comments explain constraints, not provenance
- Raw dotfiles: store them under `home/` with their real dotted names (no `dot_`/`encrypted_` prefixes);
  gating is module selection, not filename convention
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
