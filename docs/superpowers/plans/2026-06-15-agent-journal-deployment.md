# Agent Journal Deployment Plan (dotfiles / chezmoi repo)

> **For agentic workers:** REQUIRED SUB-SKILL: superpowers:subagent-driven-development or superpowers:executing-plans. Steps use checkbox (`- [ ]`) syntax. This plan runs **in the chezmoi dotfiles repo** (`~/.local/share/chezmoi`).
>
> **Model cap (user directive):** dispatch implementer/reviewer subagents at **sonnet (high effort)** or lower.
>
> **Sequencing:** Run this AFTER the standalone tool is built (`~/projects/agent-journal`, plan
> `docs/superpowers/plans/2026-06-15-agent-journal.md` in that repo). The bin wrappers and
> post-apply hook invoke the tool's CLI, so smoke-testing requires the tool to exist.

**Goal:** Deploy the standalone `agent-journal` tool onto machines via chezmoi — config templates,
launchd LaunchAgent, bin wrappers, post-apply hook, and the `agent_journal` machine capability — all
pointing at `~/projects/agent-journal` (a cross-device project clone, like `dotfiles`/`stevectl`/`nuv`).

**Architecture:** The tool's code lives in its own repo; chezmoi owns only deployment glue. The tool is
invoked via `uv run --project ~/projects/agent-journal …`. All glue **gracefully no-ops when that repo
is not cloned** on a machine. Gated behind a new `agent_journal` capability (personal + work; off on lab).

## Repo-Specific Gotchas

1. **`machine-capability-audit`** pre-commit hook fails if a capability is defined-but-ungated or
   gated-but-undefined. Land the `machines.toml` rows and the `.chezmoiignore` gate together (Task D1).
2. **Scripts still run even when `.chezmoiignore` skips the dotfiles** — the post-apply hook MUST
   self-gate at the top (Task D3).
3. **No in-repo tool dir / pyright entry** — unlike `mcp_sync`/`token_auditor`, the tool is NOT in this
   repo, so do NOT add `agent_journal` to the `.chezmoiignore` tool-dir list or to `pyrightconfig.json`.
4. **`.toml.tmpl` files are not linted by `check-toml`** (extension `.tmpl`), so `{{ }}` is fine there.
5. **Plist label** uses the repo convention `com.user.agent-journal` (matching `com.user.xcode-mcp-proxy`),
   not the spec's illustrative `org.stevec.*`.
6. **Cross-device clone may be absent** — wrappers/hook must handle `~/projects/agent-journal` missing.

---

## Task D1: `agent_journal` capability + `.chezmoiignore` gates

**Files:** Modify `.chezmoidata/machines.toml`, `.chezmoiignore`.

- [ ] **Step 1: Capability doc comment in `machines.toml`** (after the `infra` paragraph)

```text
#   agent_journal — deploy the agent-journal tool config (~/.config/agent-journal/),
#            the agent-note / agent-journal-run bin wrappers, the post-apply sync
#            hook, and the launchd LaunchAgent that records agent work into the
#            Obsidian vault. The tool itself is a cross-device project clone at
#            ~/projects/agent-journal (not vendored here). On for personal + work;
#            off on lab. Gated in .chezmoiignore and self-gated in
#            .chezmoiscripts/run_after_sync-agent-journal.sh.tmpl.
```

- [ ] **Step 2: Add `agent_journal` to every machine row**
  - `[machines.personal-mac]` → `agent_journal = true`
  - `[machines.work-mac]` → `agent_journal = true`
  - `[machines.lab-mac]` → `agent_journal = false`

- [ ] **Step 3: Append capability + darwin gates to `.chezmoiignore`** (end of file)

```text
# Skip the agent-journal config + bin wrappers + LaunchAgent on machines that
# don't run the agent journal. The tool lives at ~/projects/agent-journal; the
# post-apply hook self-gates on the same capability.
{{ if not (index .machines .machine).agent_journal }}
.config/agent-journal
.local/bin/agent-note
.local/bin/agent-journal-run
Library/LaunchAgents/com.user.agent-journal.plist
{{ end }}

# The agent-journal LaunchAgent is macOS-only (launchd). Skip its plist on any
# non-darwin host even where the capability is on.
{{ if ne .chezmoi.os "darwin" }}
Library/LaunchAgents/com.user.agent-journal.plist
{{ end }}
```

- [ ] **Step 4: Verify + commit**

```bash
pre-commit run machine-capability-audit --files .chezmoidata/machines.toml .chezmoiignore
chezmoi execute-template < .chezmoiignore >/dev/null && echo "renders OK"
git add .chezmoidata/machines.toml .chezmoiignore
git commit -m "feat(agent-journal): add agent_journal capability and ignore gates"
```

---

## Task D2: Config templates

**Files:** Create `dot_config/agent-journal/config.toml.tmpl`, `dot_config/agent-journal/workstreams.toml.tmpl`.

- [ ] **Step 1: `dot_config/agent-journal/config.toml.tmpl`**

```text
# agent-journal configuration. Rendered by chezmoi; gated on the `agent_journal`
# machine capability. The tool is a cross-device clone at ~/projects/agent-journal.
machine = {{ .machine | quote }}
context = "{{ if hasPrefix "work" .machine }}work{{ else }}personal{{ end }}"
standup_hour = 8

[vault]
path = "{{ .chezmoi.homeDir }}/projects/obsidian"
daily_dir = "Daily"
# Python strftime — equivalent to Obsidian's moment format YYYY/MM/DD-ddd.
daily_note_path_format = "%Y/%m/%d-%a"
workstreams_dir = "Workstreams"
sessions_dir = "Agent Sessions"

[state]
dir = "{{ .chezmoi.homeDir }}/.local/state/agent-journal"

[adapters]
# OpenCode/Copilot are intentionally out of v1 (insufficient/weak local state).
enabled = ["codex", "claude_code"]

[adapters.codex]
sessions_glob = "{{ .chezmoi.homeDir }}/.codex/archived_sessions/*.jsonl"

[adapters.claude_code]
projects_dir = "{{ .chezmoi.homeDir }}/.claude/projects"

[redaction]
extra_patterns = []
```

- [ ] **Step 2: `dot_config/agent-journal/workstreams.toml.tmpl`** (personal machines pre-seed cross-device projects incl. agent-journal itself)

```text
# Known workstreams for resolution. Add a [[workstream]] block per ticket or
# project. `agent-journal status` lists unclassified sessions to add here.
{{- if hasPrefix "work" .machine }}
# Work tickets are dynamic — add them as you classify work. Example:
# [[workstream]]
# name = "LA-3141 databricks compute plane"
# jira = "LA-3141"
# context = "work"
# aliases = ["databricks compute", "compute plane"]
# repos = ["terraform", "k8s-config", "service-repo"]
{{- else }}
[[workstream]]
name = "dotfiles"
context = "personal"
aliases = ["chezmoi", "dotfiles"]
repos = ["dotfiles", "chezmoi"]

[[workstream]]
name = "agent-journal"
context = "personal"
aliases = ["agent journal", "agent-journal"]
repos = ["agent-journal"]

[[workstream]]
name = "stevectl"
context = "personal"
aliases = ["stevectl"]
repos = ["stevectl"]

[[workstream]]
name = "nuv"
context = "personal"
aliases = ["nuv"]
repos = ["nuv"]

[[workstream]]
name = "python_playa"
context = "personal"
aliases = ["python playa", "playa"]
repos = ["python_playa"]
{{- end }}
```

- [ ] **Step 3: Verify rendering + commit**

```bash
chezmoi execute-template --init --promptString machine=work-mac < dot_config/agent-journal/config.toml.tmpl
chezmoi execute-template --init --promptString machine=personal-mac < dot_config/agent-journal/workstreams.toml.tmpl
git add dot_config/agent-journal/
git commit -m "feat(agent-journal): add config and workstreams templates"
```

---

## Task D3: Post-apply hook (self-gating, cross-device-aware)

**Files:** Create `.chezmoiscripts/run_after_sync-agent-journal.sh.tmpl`.

- [ ] **Step 1: Create the hook**

```bash
#!/usr/bin/env bash
set -euo pipefail

# Post-apply hook for the agent journal. Self-gates on the `agent_journal`
# machine capability (chezmoi scripts run even when .chezmoiignore skips the
# dotfiles, so this runtime gate is required). The tool is a cross-device clone
# at ~/projects/agent-journal; if it is not present this hook warns and skips.

{{ if not (index .machines .machine).agent_journal -}}
echo "agent-journal sync skipped (machine capability agent_journal=false)."
exit 0
{{- else -}}

PROJECT="${HOME}/projects/agent-journal"
STRICT_MODE="${AGENT_JOURNAL_STRICT:-0}"
LABEL="com.user.agent-journal"
PLIST_PATH="${HOME}/Library/LaunchAgents/${LABEL}.plist"

fail_or_warn() {
  local message="$1"
  if [[ "${STRICT_MODE}" == "1" ]]; then
    echo "Error: ${message}" >&2
    exit 1
  fi
  echo "Warning: ${message}" >&2
}

if ! command -v uv >/dev/null 2>&1; then
  fail_or_warn "uv is not installed; skipping agent-journal sync."
  exit 0
fi

if [[ ! -f "${PROJECT}/pyproject.toml" ]]; then
  echo "agent-journal: tool not cloned at ${PROJECT}; clone it to enable. Skipping." >&2
  exit 0
fi

# Warm the venv so launchd runs are fast and apply-time surfaces errors.
if ! uv sync --project "${PROJECT}" >/dev/null 2>&1; then
  fail_or_warn "agent-journal uv sync failed."
fi

mkdir -p "${HOME}/.local/state/agent-journal"
mkdir -p "${HOME}/Library/Logs"

{{ if eq .chezmoi.os "darwin" -}}
if [[ -f "${PLIST_PATH}" ]]; then
  DOMAIN="gui/$(id -u)"
  launchctl bootout "${DOMAIN}/${LABEL}" 2>/dev/null || true
  launchctl bootstrap "${DOMAIN}" "${PLIST_PATH}" || fail_or_warn "launchctl bootstrap failed for ${LABEL}."
  echo "agent-journal: LaunchAgent loaded (${DOMAIN}/${LABEL})."
else
  echo "agent-journal: plist not yet deployed at ${PLIST_PATH}; skipping load." >&2
fi
{{- end }}

{{- end }}
```

- [ ] **Step 2: Verify both renderings + commit**

```bash
chezmoi execute-template --init --promptString machine=lab-mac  < .chezmoiscripts/run_after_sync-agent-journal.sh.tmpl
chezmoi execute-template --init --promptString machine=work-mac < .chezmoiscripts/run_after_sync-agent-journal.sh.tmpl
git add .chezmoiscripts/run_after_sync-agent-journal.sh.tmpl
git commit -m "feat(agent-journal): add self-gating post-apply hook"
```

---

## Task D4: LaunchAgent plist + bin wrappers

**Files:** Create `Library/LaunchAgents/com.user.agent-journal.plist.tmpl`,
`dot_local/bin/executable_agent-note`, `dot_local/bin/executable_agent-journal-run`.

- [ ] **Step 1: `Library/LaunchAgents/com.user.agent-journal.plist.tmpl`**

```text
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.user.agent-journal</string>

    <key>ProgramArguments</key>
    <array>
        <string>/bin/zsh</string>
        <string>-lc</string>
        <string>exec "{{ .chezmoi.homeDir }}/.local/bin/agent-journal-run"</string>
    </array>

    <!-- Hourly during waking hours. All three subcommands are idempotent, so the
         automation-owned Standup Draft is simply kept fresh each run. Edit this
         array to change cadence (intervals are configuration). -->
    <key>StartCalendarInterval</key>
    <array>
        {{- range $h := (list 8 9 10 11 12 13 14 15 16 17 18 19 20) }}
        <dict><key>Hour</key><integer>{{ $h }}</integer><key>Minute</key><integer>0</integer></dict>
        {{- end }}
    </array>

    <key>RunAtLoad</key>
    <false/>

    <key>ProcessType</key>
    <string>Background</string>

    <key>StandardOutPath</key>
    <string>{{ .chezmoi.homeDir }}/Library/Logs/agent-journal.out.log</string>

    <key>StandardErrorPath</key>
    <string>{{ .chezmoi.homeDir }}/Library/Logs/agent-journal.err.log</string>
</dict>
</plist>
```

- [ ] **Step 2: `dot_local/bin/executable_agent-note`**

```bash
#!/usr/bin/env bash
# Thin wrapper so agents can call `agent-note` from any shell/cwd. The tool is a
# cross-device clone at ~/projects/agent-journal; no-op cleanly if it's absent.
set -euo pipefail
PROJECT="${HOME}/projects/agent-journal"
if [[ ! -f "${PROJECT}/pyproject.toml" ]]; then
  echo "agent-note: tool not cloned at ${PROJECT}" >&2
  exit 0
fi
exec uv run --project "${PROJECT}" agent-note "$@"
```

- [ ] **Step 3: `dot_local/bin/executable_agent-journal-run`**

```bash
#!/usr/bin/env bash
# LaunchAgent entry point: ingest + digest + standup. Each subcommand is
# idempotent, so hourly runs are safe. No-ops if uv or the tool repo is absent.
set -uo pipefail
PROJECT="${HOME}/projects/agent-journal"

if ! command -v uv >/dev/null 2>&1; then
  echo "agent-journal-run: uv not found on PATH" >&2
  exit 0
fi
if [[ ! -f "${PROJECT}/pyproject.toml" ]]; then
  echo "agent-journal-run: tool not cloned at ${PROJECT}" >&2
  exit 0
fi

uv run --project "${PROJECT}" agent-journal ingest || true
uv run --project "${PROJECT}" agent-journal digest || true
uv run --project "${PROJECT}" agent-journal standup || true
```

- [ ] **Step 4: Verify plist rendering + commit**

```bash
chezmoi execute-template --init --promptString machine=work-mac < Library/LaunchAgents/com.user.agent-journal.plist.tmpl | head -30
git add Library/LaunchAgents/com.user.agent-journal.plist.tmpl \
        dot_local/bin/executable_agent-note dot_local/bin/executable_agent-journal-run
git commit -m "feat(agent-journal): add LaunchAgent plist and bin wrappers"
```

---

## Task D5: Documentation

**Files:** Modify `CLAUDE.md`.

- [ ] **Step 1: Add the capability bullet** to the "Current capabilities" list (after `infra`)

```markdown
- **`agent_journal`** — deploy the agent-journal tool config
  (`~/.config/agent-journal/`), the `agent-note` / `agent-journal-run` bin
  wrappers, the post-apply sync hook, and the launchd LaunchAgent that records
  agent work into the Obsidian vault. The tool itself is a cross-device project
  clone at `~/projects/agent-journal` (not vendored here). On for personal +
  work; off on lab. Gated in `.chezmoiignore` and self-gated in
  `.chezmoiscripts/run_after_sync-agent-journal.sh.tmpl`.
```

- [ ] **Step 2: Note the external tool** in the "Key Directories" section

```markdown
- `~/projects/agent-journal` (external repo) — the agent-journal tool. This repo only
  deploys its config/launchd/bin wrappers via the `agent_journal` capability.
```

- [ ] **Step 3: Commit**

```bash
git add CLAUDE.md
git commit -m "docs(agent-journal): document agent_journal capability and external tool"
```

---

## Self-Review

**Coverage:** capability + gates (D1) · config templates (D2) · self-gating cross-device-aware hook
(D3) · plist + wrappers pointing at ~/projects/agent-journal (D4) · docs (D5). **Intentionally NOT
here:** the tool code/tests/CI (live in `~/projects/agent-journal`); no `.chezmoiignore` tool-dir entry;
no `pyrightconfig.json` change.

**Final gate:**
```bash
pre-commit run --all-files
chezmoi execute-template < .chezmoiignore >/dev/null
chezmoi diff   # review the deployment delta before apply
```
Then `chezmoi apply` on a personal/work machine and confirm `launchctl list | grep agent-journal`.
