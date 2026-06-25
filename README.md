# Dotfiles

Personal macOS dotfiles managed with [chezmoi](https://www.chezmoi.io/). Secrets are age-encrypted,
with the key sourced from 1Password. The repo also vendors three small Python tools that regenerate
machine-specific configuration after every apply.

One source tree drives three machine types — `personal-mac`, `work-mac`, and `lab-mac` — gated by a
capability table, so the same checkout produces a different environment on each.

## What's configured

| Area | Tools |
|------|-------|
| Shell | zsh, nushell, atuin (shell history), mise (runtime/tool versions) |
| Editor | Neovim (LazyVim), IdeaVim |
| Terminal | Ghostty, tmux |
| Window management | AeroSpace, SketchyBar, borders (tiling stack) |
| Files & git | yazi, git, worktrunk (git worktrees) |
| Packages | Homebrew (Brewfile) |
| AI tooling | Claude Code, GitHub Copilot, MCP, Claude skills |
| Other | DuckDB, SSH config, dev-container profiles, hippo (local knowledge-base client) |

Most areas deploy only where the relevant capability is enabled (see
[Machine types and capabilities](#machine-types-and-capabilities)).

## Installation

Requirements: Homebrew, plus Python 3.14+ and `uv` (used by the post-apply hooks and vendored tools).

### 1. Prerequisites (fresh machine)

```shell
ssh-keygen -t ed25519 -C "$USER macbook @ $EPOCHSECONDS"
mkdir -p ~/projects ~/programs

/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
brew install chezmoi age
```

### 2. Age encryption key

Restore the key from the `dotfiles-age-key` 1Password note before initializing:

```shell
mkdir -p ~/.config/chezmoi
cat > ~/.config/chezmoi/key.txt << 'EOF'
# public key: age1462h0ed4ufkjrq0wu326l30c8hay9uewlsaudk89mgqjc5540vrqacejsz
AGE-SECRET-KEY-<your-secret-key>
EOF
chmod 600 ~/.config/chezmoi/key.txt
```

### 3. Initialize and apply

```shell
chezmoi init git@github.com:stevencarpenter/dotfiles.git
chezmoi diff      # preview
chezmoi apply     # apply, then run the sync hooks
exec zsh
```

`chezmoi init` prompts once for the machine type (`personal-mac`, `work-mac`, `lab-mac`) and an
email, caching both in `~/.config/chezmoi/chezmoi.toml`. On a work machine, point git at the right
SSH key:

```shell
git -C ~/.local/share/chezmoi config --local \
  core.sshCommand 'ssh -i ~/.ssh/id_ed25519_personal -o IdentitiesOnly=yes'
```

## Machine types and capabilities

Every gate keys off a capability boolean in
[`.chezmoidata/machines.toml`](.chezmoidata/machines.toml) rather than a hostname, so adding a
machine is a one-row change. Templates and `.chezmoiignore` read
`(index .machines .machine).<capability>`.

| Capability | personal | work | lab | Gates |
|------------|:--:|:--:|:--:|-------|
| `tiling`  | yes | yes | no  | AeroSpace + SketchyBar + borders |
| `atuin`   | yes | no  | yes | atuin client pointed at the self-hosted sync server |
| `mcp`     | yes | yes | yes | MCP master config + per-tool sync hook |
| `skills`  | yes | yes | yes | Claude skills manifest + sync hook |
| `gui`     | yes | yes | yes | GUI apps + display fonts |
| `dev`     | yes | no  | no  | language LSP plugins + dev Brewfile block |
| `aws_sso` | no  | yes | no  | AWS SSO profile generator |
| `infra`   | no  | yes | no  | Kubernetes / cluster-ops tooling via mise |

`work` is corporate-curated (`dev` and `atuin` off); `lab` is a 2019 i9 home server reached over
macOS Screen Share.

## Dynamic configuration for AI agents

Four post-apply hooks regenerate machine-specific config so a single source tree fans out to
whatever tools a given machine runs. Each hook is a no-op where its capability is off, warns rather
than fails on missing `uv` so first boot can continue, and fails fast when `MCP_SYNC_STRICT=1`.

- **MCP sync** (`mcp_sync/`, `mcp` capability) — merges a master config, a per-machine overlay, and
  per-tool overrides, then writes native configs for Copilot, Cursor, VS Code, Junie, LM Studio,
  Codex, Claude Code, and OpenCode. See [docs/ai-tools/mcp-setup.md](docs/ai-tools/mcp-setup.md).
  GitHub is a Claude Code plugin (`github@claude-plugins-official`), not an MCP server.
- **Skills sync** (`sync-skills`, `skills` capability) — populates `~/.claude/skills/` from vendored
  upstream skills and personal skills, with per-machine overlays.
- **Agent registry sync** (`agents` capability) — clones `stevencarpenter/agents` into
  `~/.local/share/agent-registry`, then installs its generated Claude, Codex, OpenCode, and Copilot
  agents. After landing registry changes, refresh the external clone with
  `MCP_SYNC_STRICT=1 chezmoi apply --refresh-externals` so live `~/.claude/agents` is updated.
- **AWS SSO config** (`aws_config_gen/`, `aws_sso` capability) — generates `~/.aws/config` from SSO
  profiles (work only).

Run any of them by hand:

```shell
uv run --project ~/.local/share/chezmoi/mcp_sync sync-mcp-configs
uv run --project ~/.local/share/chezmoi/mcp_sync sync-skills
uv run --directory ~/.local/share/agent-registry python -m agent_registry.cli install
uv run --project ~/.local/share/chezmoi/aws_config_gen aws-config-gen
```

## Secrets

Secrets are age-encrypted in the source tree and decrypted on apply. The `encrypted_` filename
prefix marks a file for decryption; `private_` forces 0600 on the target.

Environment variables live in `dot_config/zsh/encrypted_dot_env.age` and decrypt to `~/.config/zsh/.env`.
To update them:

```shell
nvim ~/.config/zsh/.env
chezmoi add --encrypt ~/.config/zsh/.env
head -3 ~/.local/share/chezmoi/dot_config/zsh/encrypted_dot_env.age   # expect: -----BEGIN AGE ENCRYPTED FILE-----
```

GitHub access uses the `gh` keychain token from `gh auth login`, not an encrypted variable.

## Common commands

```shell
chezmoi diff                       # preview pending changes
chezmoi apply -v                   # apply (runs the sync hooks)
chezmoi edit ~/.config/zsh/.zshrc  # edit source, apply on save
chezmoi add ~/.config/tool/config  # track a new file
chezmoi add --encrypt <file>       # track an encrypted file
chezmoi update                     # pull + apply
chezmoi managed                    # list managed targets
```

## Vendored Python tools

Each is an isolated `uv` project (Python 3.14+, no runtime dependencies). See
[CLAUDE.md](CLAUDE.md) for the full lint/type-check/test matrix.

- `mcp_sync/` — MCP and skills fan-out
- `aws_config_gen/` — AWS SSO profile generator

`token-auditor` (the `codax`/`claade`/`opencade` auditor) was extracted to
[its own repo](https://github.com/stevencarpenter/token-auditor) and installs as a standalone uv
tool; it is no longer vendored here.

```shell
uv run --project mcp_sync --group dev pytest mcp_sync/tests
uv run --project aws_config_gen --group dev pytest aws_config_gen/tests
```
