# AeroSpace + SketchyBar on the Work Machine — Design

**Date:** 2026-04-12
**Branch:** `some-more`
**Context:** PR #38 (`cc51846`) landed AeroSpace + SketchyBar + JankyBorders on
both machines but left the work-machine `on-window-detected` block empty
pending first use. This spec populates it and adds the enterprise-app float
rules the work Mac needs (Jamf Self Service+, Zscaler, SentinelOne).

## Goals

1. Route work apps to workspaces on the work Mac — mirror the personal layout
   where apps are shared (terminal, browser, IDE, AI, Obsidian, Slack, Zed),
   skip the personal-only comms stack (workspace 5).
2. Float Jamf / Zscaler / SentinelOne windows so their non-native modal /
   popup behavior doesn't fight the tiler during re-auth, update, or prompt
   flows.
3. Prune `workspace-5-comms.sh` from the work deploy — it's dead code on work
   (the keybinding that invokes it is already personal-gated).
4. Zero changes to anything already gated correctly.

## Non-Goals

- Redesigning any interface element from PR #38 (SketchyBar, AeroSpace
  keybindings, JankyBorders colors, macOS defaults). Those stay identical
  across machines.
- Splitting the macOS `defaults` script per machine. Shared stays shared;
  split if something turns out wrong.
- Changing how Brewfile / MCP overlays / Claude plugin gating work. Those
  are already correct per PR #38 and PR #32.
- Looking up exact bundle IDs for Jamf / Zscaler / SentinelOne. Name-substring
  regex is the deliberate choice (see Decisions).

## Decisions

### D1 — Layout strategy: mirror personal

Use the same workspace roles as personal where the app exists on work:

| WS | Personal | Work |
|----|----------|------|
| 1  | Ghostty  | Ghostty |
| 2  | Firefox Dev Ed. | Firefox Dev Ed. |
| 3  | IntelliJ | IntelliJ |
| 4  | Claude + LM Studio | Claude |
| 5  | Mail + Calendar + Messages | *(unused)* |
| 6  | Steam | *(unused)* |
| 7  | Obsidian | Obsidian |
| 8  | Slack | Slack |
| 9  | Zed | Zed |

Workspaces 5 and 6 stay deliberately unassigned on work. Aerospace doesn't
care whether a workspace has rules; empty workspaces are still navigable via
`alt-5` / `alt-6`.

### D2 — Float rule matching: name-substring for security apps

Existing float rules use `if.app-id` (exact bundle ID). For the enterprise
security apps, use `if.app-name-regex-substring` instead:

- **Rationale 1 — multi-component apps.** Zscaler ships several daemon / UI
  processes (Zscaler client, Zscaler Tunnel, Zscaler Notification, etc.) each
  with its own bundle ID. SentinelOne has an agent GUI plus separate alert
  windows. One name-substring rule catches all of them.
- **Rationale 2 — version churn.** Jamf renamed their user-facing app when
  Self Service+ replaced legacy Self Service. Bundle IDs drifted. App name
  substring (`'self service'`) survives the rename; bundle ID would not.
- **Rationale 3 — no physical access.** Authoring this on the personal Mac.
  Can't introspect the work Mac's actual bundle IDs live without deferring
  the whole change. Name-substring removes that dependency.

Tradeoff: slightly wider match surface. If a personal app were ever named
"Self Service" or "Zscaler …", it'd get floated too. Risk rejected as
negligible — those terms are enterprise-specific.

Pattern: `(?i)<substring>` for case-insensitivity.

### D3 — Security floats: gated to work block, not global

Put the three new float rules inside the `{{ if hasPrefix "work" }}` block
rather than the shared global "Window Rules" section. Rationale:

- These apps don't exist on personal — rules would never fire there anyway.
  Gating costs nothing at runtime.
- Conceptually they *are* work-specific. Grouping them with other work-only
  config is clearer for future-me reading the template.
- The shared "Window Rules" section stays dedicated to apps on both machines
  (SystemPreferences, 1Password, Raycast, Finder, Calculator, Activity
  Monitor, Alt-Tab).

### D4 — `workspace-5-comms.sh` pruning via `.chezmoiignore`

The comms-layout script is a plain executable file (not a template). Options
considered:

- **`.chezmoiignore` template block** — this repo's `.chezmoiignore` is
  already a Go template with an existing "Skip personal files on work
  machines" gate. One-line addition.
- `.tmpl` rename + whole-body `{{ if }}` wrap — would leave an empty file on
  work, which is weirder than no file.
- Leave as dead code — works but the file is specifically tied to the
  personal comms stack; it has no reason to exist on work.

`.chezmoiignore` wins on simplicity and consistency with existing gating.

### D5 — macOS `defaults` script: stays shared

Every key in `run_onchange_configure-macos-defaults.sh` is a stock Apple
`defaults` namespace (documented inline in that file). Nothing in it can
trip SOC/MDM controls — it's the same namespace System Settings writes.

The *choices* (left-side dock, autohide-delay 1s, hot corners, tap-to-click
off, etc.) are personal preferences that travel with the user, not machine-
specific configuration. Splitting invites drift. If a specific default turns
out wrong on work later, gate that one key at that time.

## File Changes

Exactly two files change.

### F1 — `dot_config/aerospace/aerospace.toml.tmpl`

Replace the placeholder-comment work block (currently lines 196–203) with
the full populated work block: 7 workspace assignments + 3 security float
rules. See "Content" section below.

### F2 — `.chezmoiignore`

Append one line inside the existing `{{ if not (hasPrefix "personal" .machine) }}`
block:

```diff
 # Skip personal files on work machines
 {{ if not (hasPrefix "personal" .machine) }}
 .config/mcp/machine/personal.json
 .config/zsh/.personal.env
 .config/zsh/profile.d/personal-secrets.zsh
 .config/zsh/profile.d/personal-shell-functions.zsh
+.config/aerospace/layouts/workspace-5-comms.sh
 {{ end }}
```

## Content — Work Block Replacement

```toml
{{- if hasPrefix "work" .machine }}
# ── Work Machine ──
# 1: Terminal (Ghostty)
# 2: Browser (Firefox Dev Ed.)
# 3: IDE (IntelliJ)
# 4: AI (Claude)
# 5: (unused — personal comms stack not applicable at work)
# 6: (unused)
# 7: Notes (Obsidian)
# 8: Slack
# 9: Editor (Zed)

[[on-window-detected]]
if.app-id = 'com.mitchellh.ghostty'
run = 'move-node-to-workspace 1'

[[on-window-detected]]
if.app-id = 'org.mozilla.firefoxdeveloperedition'
run = 'move-node-to-workspace 2'

[[on-window-detected]]
if.app-id = 'com.jetbrains.intellij'
run = 'move-node-to-workspace 3'

[[on-window-detected]]
if.app-id = 'com.anthropic.claudefordesktop'
run = 'move-node-to-workspace 4'

[[on-window-detected]]
if.app-id = 'md.obsidian'
run = 'move-node-to-workspace 7'

[[on-window-detected]]
if.app-id = 'com.tinyspeck.slackmacgap'
run = 'move-node-to-workspace 8'

[[on-window-detected]]
if.app-id = 'dev.zed.Zed-Preview'
run = 'move-node-to-workspace 9'

# ── Work Machine: enterprise / security app floats ──
# Name-substring matches handle multi-component apps (Zscaler has several
# daemon/UI processes) and survive version renames (Self Service →
# Self Service+). Floating so re-auth, update, and prompt flows aren't
# fought by the tiler.

[[on-window-detected]]
if.app-name-regex-substring = '(?i)self service'
run = 'layout floating'

[[on-window-detected]]
if.app-name-regex-substring = '(?i)zscaler'
run = 'layout floating'

[[on-window-detected]]
if.app-name-regex-substring = '(?i)sentinel'
run = 'layout floating'
{{- end }}
```

## Known Assumptions (Verify on First Work Apply)

Inherited from personal block — flag at `chezmoi diff` time if wrong on work:

- **Firefox bundle ID:** `org.mozilla.firefoxdeveloperedition` (Dev Edition).
  If work runs stable Firefox, use `org.mozilla.firefox` instead.
- **Zed bundle ID:** `dev.zed.Zed-Preview` (Preview channel). If work runs
  stable Zed, use `dev.zed.Zed`.
- **IntelliJ bundle ID:** `com.jetbrains.intellij` (Community/Ultimate
  shared). Correct for both.
- **Claude Desktop bundle ID:** `com.anthropic.claudefordesktop`. If work
  runs a different Claude client, update.

All of these are harmless if wrong — the rule simply won't match, and the
app lands on whatever workspace you launch it in. Fix post-hoc with a one-
line edit.

## Testing

### Pre-merge (personal machine)

1. `chezmoi diff` → zero functional changes. Whitespace-only at most. The
   new work block is behind `{{ if hasPrefix "work" }}` and does not render
   on personal.
2. Render-check the work output without applying — use `chezmoi
   execute-template` with `.machine` overridden to a `work-*` value
   (exact flag syntax varies by chezmoi version; `--init --promptString`
   or `--data` both work). Verify: populated `[[on-window-detected]]`
   rules appear; workspace-5 comms rules do NOT; three float rules
   render at the bottom of the work block.
3. `pre-commit run --all-files` passes.

### On-work-machine (post-apply, next time user sits at work Mac)

1. `chezmoi diff` shows:
   - New populated `on-window-detected` block in `aerospace.toml`
   - Three security-app float rules
   - `~/.config/aerospace/layouts/workspace-5-comms.sh` removal (via
     `.chezmoiignore`)
2. `chezmoi apply`
3. `aerospace reload-config` (or `alt-shift-;` then `r`)
4. Launch each of Ghostty, Firefox, IntelliJ, Claude, Obsidian, Slack, Zed
   → each lands on its expected workspace. If one fails to route, bundle
   ID is wrong (see "Known Assumptions") — edit and reload.
5. Next time Zscaler prompts for re-auth / SentinelOne throws an alert /
   Self Service+ opens for an update: verify each floats freely, not tiled.

## Rollback

Either file is a single-commit revert:

- `aerospace.toml.tmpl` — revert the work block back to the 8-line
  placeholder comment. Reload config.
- `.chezmoiignore` — remove the appended line. `chezmoi apply` re-deploys
  `workspace-5-comms.sh` to work (as dead code, no side effects).
