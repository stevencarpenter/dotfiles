# AeroSpace Work-Machine Rollout — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Populate the empty work-machine block in `aerospace.toml.tmpl` with seven workspace-assignment rules plus three enterprise-app float rules, and gate the personal-only `workspace-5-comms.sh` layout script out of work deploys via `.chezmoiignore`.

**Architecture:** Two independent file edits in a chezmoi-managed dotfiles repo. No code runs at apply time beyond `chezmoi`'s Go-template engine. "Testing" here means (1) template rendering validation on the authoring machine (personal) and (2) behavioral verification on the work Mac at next sit-down. No unit test framework applies.

**Tech Stack:**
- chezmoi (Go-template-based dotfile manager, already configured)
- AeroSpace TOML config (`on-window-detected` rules)
- pre-commit hooks (ruff / yaml / json / toml / trailing-whitespace — the repo standard)

**Parallelism:** Tasks 1 and 2 touch different files with no shared state. They can execute in parallel. Task 3 (render-verification) depends on both.

**Spec:** `docs/superpowers/specs/2026-04-12-aerospace-work-machine-design.md`

---

## Task 1: Populate the work block in `aerospace.toml.tmpl`

**Files:**
- Modify: `dot_config/aerospace/aerospace.toml.tmpl` (lines 196–203)

**What to replace:** The current placeholder-comment block that looks like this:

```toml
{{- if hasPrefix "work" .machine }}
# ── Work Machine ──
# Define workspace assignments for your work apps here.
# Example:
# [[on-window-detected]]
# if.app-id = 'com.tinyspeck.slackmacgap'
# run = 'move-node-to-workspace 8'
{{- end }}
```

- [ ] **Step 1: Open the file and locate the work block**

Use `mcp__idea__get_file_text_by_path` for `/Users/carpenter/.local/share/chezmoi/dot_config/aerospace/aerospace.toml.tmpl`. Find lines 196–203 (the block above between `{{- if hasPrefix "work" .machine }}` and `{{- end }}`, right before the shared "Window Rules" section at line 205).

- [ ] **Step 2: Replace the placeholder work block with the full populated block**

The replacement content (use `mcp__idea__replace_text_in_file` or `Edit`):

**Old (exact match, 8 lines):**

```toml
{{- if hasPrefix "work" .machine }}
# ── Work Machine ──
# Define workspace assignments for your work apps here.
# Example:
# [[on-window-detected]]
# if.app-id = 'com.tinyspeck.slackmacgap'
# run = 'move-node-to-workspace 8'
{{- end }}
```

**New:**

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

- [ ] **Step 3: Local sanity check — grep for expected markers**

Run:

```bash
grep -c 'move-node-to-workspace' /Users/carpenter/.local/share/chezmoi/dot_config/aerospace/aerospace.toml.tmpl
```

Expected: `19` (12 existing personal rules + 7 new work rules).

Run:

```bash
grep -c 'app-name-regex-substring' /Users/carpenter/.local/share/chezmoi/dot_config/aerospace/aerospace.toml.tmpl
```

Expected: `3` (the three new security-app float rules).

Run:

```bash
grep -c '{{- if hasPrefix "work" .machine }}' /Users/carpenter/.local/share/chezmoi/dot_config/aerospace/aerospace.toml.tmpl
```

Expected: `2` (one in `[mode.service.binding]`, one opening the workspace block).

- [ ] **Step 4: Personal-side render check**

Confirm the work block does NOT render on personal. Run from repo root:

```bash
chezmoi diff dot_config/aerospace/aerospace.toml.tmpl
```

Expected: no diff against the currently-deployed `~/.config/aerospace/aerospace.toml` (since `.machine` on this machine has the `personal` prefix, the new `{{ if hasPrefix "work" }}` block is skipped during rendering).

If a diff DOES appear on personal, something in the personal block was unintentionally touched — stop and investigate before committing.

- [ ] **Step 5: Commit**

```bash
cd /Users/carpenter/.local/share/chezmoi
git add dot_config/aerospace/aerospace.toml.tmpl
git commit -m "feat(aerospace): populate work-machine workspace assignments and enterprise-app floats"
```

---

## Task 2: Gate `workspace-5-comms.sh` out of work deploys

**Files:**
- Modify: `.chezmoiignore` (inside the existing `{{ if not (hasPrefix "personal" .machine) }}` block at lines 70–75)

- [ ] **Step 1: Open `.chezmoiignore`**

Use `mcp__idea__get_file_text_by_path` for `/Users/carpenter/.local/share/chezmoi/.chezmoiignore`. Locate the block starting at line 70:

```
# Skip personal files on work machines
{{ if not (hasPrefix "personal" .machine) }}
.config/mcp/machine/personal.json
.config/zsh/.personal.env
.config/zsh/profile.d/personal-secrets.zsh
.config/zsh/profile.d/personal-shell-functions.zsh
{{ end }}
```

- [ ] **Step 2: Append one line before `{{ end }}`**

**Old:**

```
.config/zsh/profile.d/personal-shell-functions.zsh
{{ end }}
```

**New:**

```
.config/zsh/profile.d/personal-shell-functions.zsh
.config/aerospace/layouts/workspace-5-comms.sh
{{ end }}
```

- [ ] **Step 3: Verify the change**

Run:

```bash
grep -c 'workspace-5-comms' /Users/carpenter/.local/share/chezmoi/.chezmoiignore
```

Expected: `1`.

Run:

```bash
grep -c '^{{ if not (hasPrefix "personal" .machine) }}' /Users/carpenter/.local/share/chezmoi/.chezmoiignore
```

Expected: `1` (the block we edited is still the only one of its kind).

- [ ] **Step 4: Personal-side render check**

The ignore block is gated behind `not (hasPrefix "personal" .machine)`, so on personal it should NOT take effect. Confirm `workspace-5-comms.sh` is still deployed on this machine:

```bash
ls -la ~/.config/aerospace/layouts/workspace-5-comms.sh
```

Expected: the file exists and is executable. No `chezmoi apply` or `chezmoi diff` activity should mention it.

- [ ] **Step 5: Commit**

```bash
cd /Users/carpenter/.local/share/chezmoi
git add .chezmoiignore
git commit -m "chore(chezmoi): skip workspace-5-comms.sh on non-personal machines"
```

---

## Task 3: Final repo-level verification

**Depends on:** Tasks 1 and 2 both complete.

- [ ] **Step 1: Run pre-commit on changed files**

```bash
cd /Users/carpenter/.local/share/chezmoi
pre-commit run --files dot_config/aerospace/aerospace.toml.tmpl .chezmoiignore
```

Expected: all hooks pass. YAML / JSON / TOML checks should skip the `.tmpl` file (it's not parsed as raw TOML because of `{{ }}` directives), but trailing-whitespace + end-of-files + private-key + AWS-creds checks should all pass clean.

- [ ] **Step 2: Full repo `chezmoi diff`**

```bash
cd /Users/carpenter/.local/share/chezmoi
chezmoi diff
```

Expected on personal machine: empty diff, or at most whitespace-only. No functional change.

If a non-whitespace diff appears, investigate — it means the personal-rendered output changed, which was not intended.

- [ ] **Step 3: Work-output render check (optional but recommended)**

Use `chezmoi execute-template` with `.machine` overridden to a `work-*` value (the exact flag syntax varies by chezmoi version — `--init --promptString machine=work-m3-max` or `--data` both work depending on version):

```bash
cd /Users/carpenter/.local/share/chezmoi
chezmoi execute-template --init --promptString machine=work-m3-max \
    < dot_config/aerospace/aerospace.toml.tmpl | less
```

Verify visually:
- Seven `[[on-window-detected]]` blocks with `move-node-to-workspace` (work apps).
- Three `[[on-window-detected]]` blocks with `if.app-name-regex-substring` + `layout floating` (security apps).
- The workspace-5 service-mode binding (`5 = ['exec-and-forget ...']`) does NOT appear (personal-only).
- The personal `on-window-detected` block (Mail, Calendar, Messages, Steam, LM Studio, etc.) does NOT appear.

If the flag syntax errors out, skip this step — the on-work-machine diff (Task 4) will catch any template issues.

- [ ] **Step 4: Push branch (optional — defer if user wants to review first)**

```bash
cd /Users/carpenter/.local/share/chezmoi
git push -u origin some-more
```

Hold off on PR creation until the user reviews the work output in person on the work Mac.

---

## Task 4: (Deferred — for next work-machine session)

Not executed now. Documented here so future-you has the sequence:

1. `cd ~/.local/share/chezmoi && chezmoi diff` — should show the populated work block and the `workspace-5-comms.sh` removal.
2. `chezmoi apply`
3. `aerospace reload-config` (or `alt-shift-;` then `r`).
4. Launch each of Ghostty / Firefox / IntelliJ / Claude / Obsidian / Slack / Zed — verify auto-routing.
5. Next time Zscaler re-auths, SentinelOne prompts, Self Service+ opens — verify each floats.
6. If any bundle ID is wrong (Firefox stable vs Dev Ed., Zed stable vs Preview), edit the ID in place and reload.

---

## Self-Review Checklist

Run these against the spec before handing off:

- [x] **Spec coverage:**
  - Goals 1–4 (routing, floats, pruning, zero-drift elsewhere) all map to Tasks 1–3.
  - Decisions D1–D5 all reflected in plan (mirror layout in Task 1, name-substring in Task 1, work-gated floats in Task 1, `.chezmoiignore` in Task 2, macOS defaults untouched).
  - Known-assumption bundle IDs flagged in Task 4 for post-deploy validation.

- [x] **Placeholder scan:** No TBD / TODO / "implement later" / "similar to above" / bare "add validation". Every step has exact paths, exact commands, exact content.

- [x] **Type consistency:** Chezmoi template directives consistent (`{{- if hasPrefix "work" .machine }}` / `{{- end }}`). Regex syntax consistent (`(?i)<term>`). File paths consistent (no `~/` vs absolute mismatches).

- [x] **No `.tmpl` suffix mistakes:** `workspace-5-comms.sh` is NOT being renamed to `.tmpl`. It stays a plain executable file; `.chezmoiignore` does the gating.
