# Dotfiles task runner
# Usage: just <recipe>       List: just --list

# Immutable token-auditor release used by the explicit network sync workflow.
# Update deliberately after reviewing the corresponding upstream release.
TOKEN_AUDITOR_VERSION := `tr -d '\n' < versions/token-auditor`

# Default recipe: show available commands
[private]
default:
    @just --list

# ── Setup and maintenance ────────────────────────────────

# Show a names-only plan for adopting reviewed personal env changes into 1Password.
[group('Targeted maintenance')]
op-adopt *FLAGS:
    home/.local/bin/op-adopt {{ FLAGS }}

# Preview Homebrew and mise upgrades, approve, then run the side channels. Pass -y to approve automatically.
[group('Daily')]
update *ARGS:
    scripts/update-inputs.sh {{ ARGS }}

# Homebrew only: refresh metadata and upgrade installed unpinned packages; accepts --dry-run.
[group('Targeted maintenance')]
brew-upgrade *ARGS:
    HOMEBREW_NO_ANALYTICS=1 HOMEBREW_NO_ENV_HINTS=1 brew update
    HOMEBREW_NO_ANALYTICS=1 HOMEBREW_NO_ENV_HINTS=1 HOMEBREW_NO_AUTO_UPDATE=1 brew upgrade {{ ARGS }}

# Compare declared and installed Homebrew inventory without changing anything.
[group('Validation')]
brew-audit:
    scripts/audit-homebrew.sh

# First-time provisioning on a fresh Mac (Command Line Tools, Homebrew, Brewfile).
[group('Setup')]
bootstrap *HOST:
    ./bootstrap.sh {{ HOST }}

# ── Sync (full deploy) ───────────────────────────────────

# Step 1: print the plan and its digest. Applies nothing.
# Also writes the approval flags that `apply --preview` lists to $DFM_ALLOW_DIR/allow.txt
# (default ~/.local/state/dfm-cutover/allow.txt, a 0700 directory), one `--allow-* '<id>'` per line. Review that file.
[group('Daily')]
sync-dfm:
    #!/usr/bin/env bash
    set -euo pipefail
    root="{{ justfile_directory() }}"
    dir="${DFM_ALLOW_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/dfm-cutover}"
    mkdir -p -m 700 "$dir"
    [[ -d $dir && ! -L $dir && -O $dir && ! -g $dir ]] || { echo "error: $dir must be a real directory you own" >&2; exit 2; }
    chmod 700 "$dir"
    allow="$dir/allow.txt"
    dotfiles-manager plan --root "$root"
    # --preview exits non-zero while an approval is missing; the flags are what we want.
    preview="$(dotfiles-manager apply --root "$root" --preview 2>&1 || true)"
    rm -f "$allow"
    ( umask 077; printf '%s\n' "$preview" | grep -oE "\-\-allow-(adopt|disruptive) '[^']*'" | awk '!seen[$0]++' > "$allow" || true )
    echo "flags written to $allow:"; cat "$allow"
    echo "Review the plan and the flags, then approve its digest with: just sync-dfm-apply <digest>"

# Step 2: apply the approved digest, then packages, side channels, agents and checks.
# Reads the flags from $DFM_ALLOW_DIR/allow.txt (see sync-dfm). Needs an interactive terminal (op signin).
[group('Daily')]
sync-dfm-apply $digest:
    #!/usr/bin/env bash
    set -euo pipefail
    root="{{ justfile_directory() }}"
    [[ $digest =~ ^[0-9a-f]{64}$ ]] || { echo "error: digest must be 64 lowercase hex characters" >&2; exit 2; }
    dir="${DFM_ALLOW_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/dfm-cutover}"
    mkdir -p -m 700 "$dir"
    [[ -d $dir && ! -L $dir && -O $dir && ! -g $dir ]] || { echo "error: $dir must be a real directory you own" >&2; exit 2; }
    chmod 700 "$dir"
    allow="$dir/allow.txt"
    flags=()
    if [[ -e $allow || -L $allow ]]; then
      [[ -f $allow && ! -L $allow && -O $allow ]] || { echo "error: $allow must be a regular file you own" >&2; exit 2; }
      while IFS= read -r line; do
        [[ -n $line ]] || continue
        if [[ $line =~ ^(--allow-adopt|--allow-disruptive)\ \'([^\']+)\'$ ]]; then
          flags+=("${BASH_REMATCH[1]}" "${BASH_REMATCH[2]}")
        else
          echo "error: unexpected line in $allow: $line" >&2; exit 2
        fi
      done < "$allow"
    fi
    dotfiles-manager apply --root "$root" --yes-plan "$digest" ${flags[@]+"${flags[@]}"}
    scripts/brew-sync.sh
    scripts/hooks-sync.sh
    scripts/sync-side-channels.sh
    scripts/launch-agents.sh load
    scripts/login-shell.sh --check
    scripts/tiling-reload.sh || echo "tiling-reload failed; continuing" >&2
    scripts/mac-defaults.sh --check || echo "mac-defaults differs; read the lines above, then continue" >&2
    dotfiles-manager state check
    dotfiles-manager doctor --root "$root"

# Mise upgrades, secrets, Git sources, agents, and tools only; included in sync.
[group('Targeted maintenance')]
sync-side-channels:
    TOKEN_AUDITOR_VERSION="{{ TOKEN_AUDITOR_VERSION }}" scripts/sync-side-channels.sh

# Firstmate only: provision its native-update checkout; included in sync-side-channels.
[group('Targeted maintenance')]
firstmate-setup:
    firstmate --setup

# ── Python checks ────────────────────────────────────────

# Lint and verify formatting in both Python projects; included in py-check.
[group('Validation')]
lint:
    for p in mcp_sync agent_reap; do uv run --project $p --group dev ruff check $p/src $p/tests || exit $?; done
    for p in mcp_sync agent_reap; do uv run --project $p --group dev ruff format --check $p/src $p/tests || exit $?; done

# Test both Python projects; included in py-check.
[group('Validation')]
test *FLAGS:
    for p in mcp_sync agent_reap; do uv run --project $p --group dev pytest $p/tests --cov=$p --cov-report=term-missing {{ FLAGS }} || exit $?; done

# Format both Python projects (writes files).
[group('Validation')]
fmt:
    for p in mcp_sync agent_reap; do uv run --project $p --group dev ruff format $p/src $p/tests || exit $?; done

# MCP configs only; hooks-sync.sh also regenerates them during sync-dfm-apply.
[group('Targeted maintenance')]
mcp-sync:
    #!/usr/bin/env bash
    set -euo pipefail
    shopt -s nullglob
    overlays=("$HOME"/.config/mcp/machine/*.json)
    case "${#overlays[@]}" in
      0) printf 'error: machine overlay is missing\n' >&2; exit 1 ;;
      1) uv run --project mcp_sync sync-mcp-configs --machine-config "${overlays[0]}" ;;
      *) printf 'error: multiple machine overlays deployed: %s\n' "${overlays[*]}" >&2; exit 1 ;;
    esac

# Report idle Claude teammate panes across every tmux socket (kills nothing)
[group('Utilities')]
reap:
    uv run --project agent_reap agent-reap report

# Every tmux server and its sessions: shows why `tmux kill-server` missed one
[group('Utilities')]
reap-sockets:
    uv run --project agent_reap agent-reap sockets

# ssh control masters + disowned descendants (report-only)
[group('Utilities')]
reap-strays:
    uv run --project agent_reap agent-reap strays

# Actually reap idle teammate panes. Leads and interactive sessions are spared.
[group('Utilities')]
reap-kill:
    uv run --project agent_reap agent-reap reap --kill

# ── All Python projects ──────────────────────────────────

# Run all Python checks (lint + test).
[group('Validation')]
py-check: lint test

# ── Git hooks (lefthook) ─────────────────────────────────

# Run every lefthook pre-commit job against all files, as CI does
[group('Validation')]
lefthook:
    lefthook run pre-commit --all-files

# Install hooks only (does not run checks); included in sync-side-channels.
[group('Targeted maintenance')]
lefthook-install:
    lefthook install

# ── Repo atlas (derived static site) ─────────────────────

# Build the atlas into site/. Deterministic and free: no model calls.
[group('Utilities')]
site:
    ./scripts/build-site.py

# Serve the built atlas locally.
[group('Utilities')]
site-serve: site
    @echo "atlas: http://127.0.0.1:8931"
    python3 -m http.server 8931 -d site

# Fail when a cached summary is stale or a qualifying node has none. Free.
[group('Validation')]
site-check:
    ./scripts/build-site.py --check
    ./scripts/test-build-site.sh

# Print the nodes that qualify for synthesis, and why.
[group('Utilities')]
site-queue:
    ./scripts/build-site.py --queue --explain
