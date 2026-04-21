# AWS Profile Session Switcher Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship two work-only zsh commands — `awsp` (set `AWS_PROFILE` in current shell via fzf picker) and `awsx` (spawn a tmux window or subshell with `AWS_PROFILE` pre-set) — without touching shell-startup defaults.

**Architecture:** A single new zsh file `dot_config/zsh/profile.d/work-aws-shell-functions.zsh` contains two shared private helpers (`_awsp_pick`, `_awsp_check_token`) plus the public `awsp` and `awsx` functions. The file is gated to work machines via `.chezmoiignore`. The profile picker uses `aws configure list-profiles` + `fzf` with a preview pane that reads `~/.aws/config`. The token health check is a fast local-only read of `~/.aws/sso/cache/<sha1(session)>.json` via `jq`. `awsx` auto-detects `$TMUX` and opens either a new `tmux new-window -e AWS_PROFILE=<p> -n aws:<p>` or a `zsh -i` subshell with the profile exported.

**Tech Stack:** zsh, fzf (brew), jq (brew), shasum (macOS builtin), AWS CLI (`aws configure list-profiles`), tmux (for windowed Pattern C), chezmoi for deployment.

**Spec:** `docs/superpowers/specs/2026-04-20-aws-profile-session-switcher-design.md`

---

## File Structure

| Path | Action | Responsibility |
|---|---|---|
| `dot_config/zsh/profile.d/work-aws-shell-functions.zsh` | Create | All four functions (`_awsp_pick`, `_awsp_check_token`, `awsp`, `awsx`) |
| `.chezmoiignore` | Modify | Gate new file to work machines |
| `dot_config/zsh/dot_p10k.zsh` (line 1759) | Modify | Add `awsp\|awsx` to `POWERLEVEL9K_AWS_SHOW_ON_COMMAND` |
| `aws_config_gen/README.md` | Modify | Add "Using generated profiles" section |

**Pre-existing context the engineer needs:**

- The zshrc loader at `dot_config/zsh/dot_zshrc:334-339` auto-sources every `profile.d/*.zsh` — no wiring needed for the new file.
- `work-shell-functions.zsh` is a sibling file already gated via `.chezmoiignore` under `{{ if not (hasPrefix "work" .machine) }}`. We use the same block.
- Chezmoi target paths: source-dir `dot_config/zsh/profile.d/foo.zsh` deploys to `~/.config/zsh/profile.d/foo.zsh`. In `.chezmoiignore` you reference the **target path**: `.config/zsh/profile.d/foo.zsh` (no `dot_` prefix).
- `fzf` (0.71.0+) and `jq` are already in `dot_config/homebrew/Brewfile.tmpl` — no Brewfile changes.
- **Testing machine reality:** This plan is most useful on a work machine (AWS profiles exist). On a personal machine you can still verify file creation, lint, and chezmoi diff, but end-to-end smoke tests require real profiles.
- **No TDD.** There is no automated-test harness for these shell functions; verification is manual smoke tests documented per task. See spec §"Testing Strategy".

---

## Task 1: Scaffold the new shell file and gate it

**Files:**
- Create: `dot_config/zsh/profile.d/work-aws-shell-functions.zsh`
- Modify: `.chezmoiignore`

- [ ] **Step 1: Create the empty shell file with a header**

Create `dot_config/zsh/profile.d/work-aws-shell-functions.zsh` with exactly this content:

```zsh
#!/usr/bin/env zsh
# AWS profile session switcher — work-only.
# Provides `awsp` (set AWS_PROFILE in current shell) and `awsx` (dedicated
# subshell/tmux window with AWS_PROFILE pre-exported). Shell-startup default
# remains: no AWS_PROFILE set.
```

- [ ] **Step 2: Add the file to the work-gating block in `.chezmoiignore`**

Open `.chezmoiignore` and add one line inside the existing
`{{ if not (hasPrefix "work" .machine) }}` block (starts at line 61), so it reads:

```
{{ if not (hasPrefix "work" .machine) }}
.config/aws-config-gen/overrides.json
.config/mcp/machine/work.json
.config/zsh/.work.env
.config/zsh/profile.d/work-secrets.zsh
.config/zsh/profile.d/work-shell-functions.zsh
.config/zsh/profile.d/work-aws-shell-functions.zsh
{{ end }}
```

- [ ] **Step 3: Verify chezmoi sees it correctly per machine type**

Run:

```bash
chezmoi diff dot_config/zsh/profile.d/work-aws-shell-functions.zsh
```

Expected on a work machine: a diff showing the new file will be created at
`~/.config/zsh/profile.d/work-aws-shell-functions.zsh`.
Expected on a personal machine: no diff (file is ignored).

Also run:

```bash
chezmoi execute-template '{{ .machine }}'
```

Note the machine type in the output and confirm the result above matches.

- [ ] **Step 4: Commit**

```bash
git add dot_config/zsh/profile.d/work-aws-shell-functions.zsh .chezmoiignore
git commit -m "feat(zsh): scaffold work-aws-shell-functions and gate to work"
```

---

## Task 2: Implement the shared fzf picker helper

**Files:**
- Modify: `dot_config/zsh/profile.d/work-aws-shell-functions.zsh`

- [ ] **Step 1: Append the `_awsp_pick` helper**

Append this function to the file:

```zsh
# _awsp_pick — internal helper. Prints the selected profile name to stdout,
# returns non-zero on cancel/empty list. Uses fzf with a preview pane that
# greps the profile block out of ~/.aws/config.
_awsp_pick() {
    local profiles
    profiles="$(aws configure list-profiles 2>/dev/null)"
    if [[ -z "$profiles" ]]; then
        print -u2 "No AWS profiles found. Have you run aws-config-gen?"
        return 1
    fi

    local preview='awk -v p="[profile {r}]" '\''
        $0 == p { inblock=1; print; next }
        /^\[/   { inblock=0 }
        inblock { print }
    '\'' "$HOME/.aws/config"'

    print -r -- "$profiles" | fzf \
        --prompt='aws profile> ' \
        --height=40% \
        --reverse \
        --preview "$preview" \
        --preview-window=right:50%:wrap
}
```

- [ ] **Step 2: Source the file and manually verify the picker opens**

In a new zsh:

```bash
source ~/.local/share/chezmoi/dot_config/zsh/profile.d/work-aws-shell-functions.zsh
_awsp_pick
```

Expected (work machine): fzf opens with a list of profiles; preview shows the
`[profile <name>]` block from `~/.aws/config` for the highlighted entry.
Selecting a profile prints its name to stdout.
Cancelling (Esc) returns non-zero with no output.

Expected (personal machine with no profiles): prints the
`No AWS profiles found...` message and returns non-zero.

- [ ] **Step 3: Commit**

```bash
git add dot_config/zsh/profile.d/work-aws-shell-functions.zsh
git commit -m "feat(zsh): add _awsp_pick fzf picker helper"
```

---

## Task 3: Implement `awsp` with argument handling and unset

**Files:**
- Modify: `dot_config/zsh/profile.d/work-aws-shell-functions.zsh`

- [ ] **Step 1: Append the `awsp` function**

Append this function:

```zsh
# awsp — set AWS_PROFILE in the current shell.
#   awsp              → fzf picker
#   awsp <profile>    → direct set
#   awsp -            → unset AWS_PROFILE only (leaves AWS_ACCESS_KEY_ID etc.)
awsp() {
    if [[ "$1" == "-" ]]; then
        unset AWS_PROFILE
        print -r -- "AWS_PROFILE unset."
        return 0
    fi

    local profile="$1"
    if [[ -z "$profile" ]]; then
        profile="$(_awsp_pick)" || return $?
    fi

    export AWS_PROFILE="$profile"
    print -r -- "AWS_PROFILE=$AWS_PROFILE"
}
```

- [ ] **Step 2: Smoke test each invocation form**

In a fresh zsh:

```bash
source ~/.local/share/chezmoi/dot_config/zsh/profile.d/work-aws-shell-functions.zsh

# Direct set
awsp default
echo "AWS_PROFILE=$AWS_PROFILE"
# Expected: AWS_PROFILE=default

# Unset
awsp -
echo "AWS_PROFILE=${AWS_PROFILE:-<unset>}"
# Expected: AWS_PROFILE=<unset>

# Regression guard: unset must not clobber session credential env vars
export AWS_ACCESS_KEY_ID=dummy AWS_SECRET_ACCESS_KEY=dummy AWS_SESSION_TOKEN=dummy
awsp -
echo "KEY=${AWS_ACCESS_KEY_ID:-<unset>}"
# Expected: KEY=dummy
unset AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN
```

- [ ] **Step 3: Smoke test fzf flow (work machine only)**

```bash
awsp
# Expected: picker opens; selecting a profile sets AWS_PROFILE and prints it.
echo "AWS_PROFILE=$AWS_PROFILE"
```

- [ ] **Step 4: Commit**

```bash
git add dot_config/zsh/profile.d/work-aws-shell-functions.zsh
git commit -m "feat(zsh): add awsp profile switcher with unset"
```

---

## Task 4: Add SSO token health check

**Files:**
- Modify: `dot_config/zsh/profile.d/work-aws-shell-functions.zsh`

- [ ] **Step 1: Append the `_awsp_check_token` helper**

Append this function **before** `awsp` (move it above `awsp` in the file):

```zsh
# _awsp_check_token <profile> — emit a warning to stderr if the SSO token for
# this profile's sso_session is missing or expired. Never blocks. Local-only
# (no network call). Returns 0 on valid token, 1 otherwise.
_awsp_check_token() {
    local profile="$1"
    local session
    session="$(aws configure get sso_session --profile "$profile" 2>/dev/null)"
    if [[ -z "$session" ]]; then
        # Profile has no sso_session (e.g. a static-credentials profile). Skip.
        return 0
    fi

    local hash cache expires now
    hash="$(printf '%s' "$session" | shasum -a 1 | awk '{print $1}')"
    cache="$HOME/.aws/sso/cache/${hash}.json"
    if [[ ! -f "$cache" ]]; then
        print -u2 -r -- "⚠ SSO token missing — run: aws sso login --sso-session $session"
        return 1
    fi

    expires="$(jq -r '.expiresAt // empty' "$cache" 2>/dev/null)"
    if [[ -z "$expires" ]]; then
        print -u2 -r -- "⚠ SSO token cache unreadable at $cache"
        return 1
    fi

    # date -j -f "%Y-%m-%dT%H:%M:%SZ" is macOS-specific; aws writes UTC ISO8601.
    # Strip fractional seconds if present.
    expires="${expires%%.*}"
    expires="${expires%Z}"
    local exp_epoch
    exp_epoch="$(date -j -u -f '%Y-%m-%dT%H:%M:%S' "$expires" +%s 2>/dev/null)"
    now="$(date -u +%s)"
    if [[ -z "$exp_epoch" || "$exp_epoch" -le "$now" ]]; then
        print -u2 -r -- "⚠ SSO token expired — run: aws sso login --sso-session $session"
        return 1
    fi

    return 0
}
```

- [ ] **Step 2: Wire the check into `awsp`**

Replace the body of the `awsp` function with:

```zsh
awsp() {
    if [[ "$1" == "-" ]]; then
        unset AWS_PROFILE
        print -r -- "AWS_PROFILE unset."
        return 0
    fi

    local profile="$1"
    if [[ -z "$profile" ]]; then
        profile="$(_awsp_pick)" || return $?
    fi

    export AWS_PROFILE="$profile"
    _awsp_check_token "$profile"  # warn on expired/missing token; do not block
    print -r -- "AWS_PROFILE=$AWS_PROFILE"
}
```

- [ ] **Step 3: Smoke test — token valid**

```bash
# Assuming an already-logged-in SSO session
aws sso login --sso-session <your-session>   # if needed
source ~/.local/share/chezmoi/dot_config/zsh/profile.d/work-aws-shell-functions.zsh
awsp <a-profile-using-that-session>
# Expected: no warning, only "AWS_PROFILE=<name>"
```

- [ ] **Step 4: Smoke test — token expired**

```bash
# Simulate expiry by moving the cache aside
hash="$(printf '%s' "<your-session>" | shasum -a 1 | awk '{print $1}')"
mv "$HOME/.aws/sso/cache/${hash}.json" /tmp/sso-cache-backup.json
awsp <a-profile-using-that-session>
# Expected: "⚠ SSO token missing — run: aws sso login --sso-session <name>" on stderr,
# AND AWS_PROFILE is still set (non-blocking).
echo "AWS_PROFILE=$AWS_PROFILE"
mv /tmp/sso-cache-backup.json "$HOME/.aws/sso/cache/${hash}.json"
```

- [ ] **Step 5: Smoke test — static-credentials profile (no sso_session)**

```bash
awsp default    # or any profile without sso_session
# Expected: no warning; AWS_PROFILE set silently.
```

- [ ] **Step 6: Commit**

```bash
git add dot_config/zsh/profile.d/work-aws-shell-functions.zsh
git commit -m "feat(zsh): add non-blocking SSO token health check to awsp"
```

---

## Task 5: Implement `awsx` with tmux/subshell auto-detection

**Files:**
- Modify: `dot_config/zsh/profile.d/work-aws-shell-functions.zsh`

- [ ] **Step 1: Append the `awsx` function**

Append:

```zsh
# awsx — spawn a dedicated context with AWS_PROFILE pre-exported.
#   Inside tmux → opens a new window named aws:<profile>
#   Outside tmux → spawns an interactive zsh subshell
awsx() {
    local profile="$1"
    if [[ -z "$profile" ]]; then
        profile="$(_awsp_pick)" || return $?
    fi

    _awsp_check_token "$profile"  # warn on expired/missing token; do not block

    if [[ -n "$TMUX" ]]; then
        tmux new-window -n "aws:${profile}" -e "AWS_PROFILE=${profile}"
    else
        AWS_PROFILE="$profile" zsh -i
    fi
}
```

- [ ] **Step 2: Smoke test — inside tmux**

```bash
# Inside a tmux session
source ~/.local/share/chezmoi/dot_config/zsh/profile.d/work-aws-shell-functions.zsh
awsx <a-profile>
# Expected: new tmux window opens, named "aws:<profile>".
# In the new window, run:
echo "AWS_PROFILE=$AWS_PROFILE"
# Expected: AWS_PROFILE=<a-profile>
# Close the window (exit). Back in the parent shell:
echo "AWS_PROFILE=${AWS_PROFILE:-<unset>}"
# Expected: <unset> (parent shell untouched)
```

- [ ] **Step 3: Smoke test — outside tmux**

```bash
# Open a plain terminal (no tmux). Detach first if you are in one:
#   tmux detach  (or Ctrl-b d)
source ~/.local/share/chezmoi/dot_config/zsh/profile.d/work-aws-shell-functions.zsh
awsx <a-profile>
# Expected: a subshell starts. Inside it:
echo "AWS_PROFILE=$AWS_PROFILE"
# Expected: AWS_PROFILE=<a-profile>
exit
# Back in the parent shell:
echo "AWS_PROFILE=${AWS_PROFILE:-<unset>}"
# Expected: <unset>
```

- [ ] **Step 4: Commit**

```bash
git add dot_config/zsh/profile.d/work-aws-shell-functions.zsh
git commit -m "feat(zsh): add awsx dedicated-context spawner"
```

---

## Task 6: Update p10k `AWS_SHOW_ON_COMMAND`

**Files:**
- Modify: `dot_config/zsh/dot_p10k.zsh` (line 1759)

- [ ] **Step 1: Edit the line**

At line 1759, change:

```zsh
typeset -g POWERLEVEL9K_AWS_SHOW_ON_COMMAND='aws|aws-config-gen'
```

to:

```zsh
typeset -g POWERLEVEL9K_AWS_SHOW_ON_COMMAND='aws|aws-config-gen|awsp|awsx'
```

- [ ] **Step 2: Verify the change**

```bash
grep -n "POWERLEVEL9K_AWS_SHOW_ON_COMMAND" dot_config/zsh/dot_p10k.zsh
# Expected: exactly one hit, line 1759, with the updated value
```

- [ ] **Step 3: Apply and confirm prompt behavior (work machine)**

```bash
chezmoi apply
exec zsh
# Type `awsp ` (with trailing space, don't run) — p10k aws segment should light up.
# Type `awsx ` — same.
# Type `ls ` — segment stays hidden.
```

- [ ] **Step 4: Commit**

```bash
git add dot_config/zsh/dot_p10k.zsh
git commit -m "feat(p10k): show AWS segment on awsp/awsx commands"
```

---

## Task 7: Document the new commands in `aws_config_gen/README.md`

**Files:**
- Modify: `aws_config_gen/README.md`

- [ ] **Step 1: Add a "Using generated profiles" subsection**

Insert this subsection between the existing "Usage" section and the "Configuration" section (i.e., just before the `## Configuration` heading near line 80):

````markdown
### Using generated profiles in a shell session

Two zsh helpers ship alongside this tool (work machines only, see
`dot_config/zsh/profile.d/work-aws-shell-functions.zsh`):

- **`awsp [profile|-]`** — set `AWS_PROFILE` in the **current** shell.
  - `awsp` → fzf picker over all generated profiles (preview shows account id,
    role, region).
  - `awsp prod-admin` → direct set.
  - `awsp -` → unset `AWS_PROFILE` (returns to the default "no profile" state;
    leaves `AWS_ACCESS_KEY_ID`/`AWS_SECRET_ACCESS_KEY`/`AWS_SESSION_TOKEN` alone
    so `get_assumed_role_credentials` state is preserved).

- **`awsx [profile]`** — spawn a **dedicated context** with `AWS_PROFILE`
  pre-exported.
  - Inside tmux → new window named `aws:<profile>`.
  - Outside tmux → new interactive zsh subshell.
  - Exiting the window/subshell drops the profile.

Both commands emit a non-blocking warning to stderr if the underlying SSO
token for the profile's `sso_session` is missing or expired:

```
⚠ SSO token expired — run: aws sso login --sso-session my-sso
```

The default "no profile set" behavior on new shells is preserved, so scripts
that iterate across accounts with per-call `--profile` flags are unaffected.
````

- [ ] **Step 2: Spot-check rendering**

```bash
grep -n "Using generated profiles" aws_config_gen/README.md
# Expected: one hit before the "## Configuration" heading
```

- [ ] **Step 3: Commit**

```bash
git add aws_config_gen/README.md
git commit -m "docs(aws_config_gen): document awsp/awsx helpers"
```

---

## Task 8: End-to-end verification on a work machine

**Files:** none (verification only)

- [ ] **Step 1: Apply all changes**

```bash
chezmoi apply -v
exec zsh
```

Expected: no errors from the profile.d loader; `type awsp awsx` returns function bodies.

- [ ] **Step 2: Regression guard — default shell has no AWS_PROFILE**

```bash
exec zsh
echo "AWS_PROFILE=${AWS_PROFILE:-<unset>}"
# Expected: <unset>
```

- [ ] **Step 3: Run the script that motivated the no-default constraint**

Run whatever cross-account script you use that relies on per-call `--profile`.
Confirm it still completes successfully.

- [ ] **Step 4: Pattern A end-to-end**

```bash
awsp             # pick via fzf
aws sts get-caller-identity
# Expected: identity matches the picked profile
awsp -
echo "AWS_PROFILE=${AWS_PROFILE:-<unset>}"   # Expected: <unset>
```

- [ ] **Step 5: Pattern C end-to-end (inside tmux)**

```bash
awsx <profile-1>    # new window
# In the new window:
aws sts get-caller-identity        # Expected: profile-1 identity
exit

# Back in original window:
awsx <profile-2>                    # another new window
aws sts get-caller-identity        # Expected: profile-2 identity
exit

# Original window untouched:
echo "AWS_PROFILE=${AWS_PROFILE:-<unset>}"   # Expected: <unset>
```

- [ ] **Step 6: No commit**

Verification task; nothing to commit.

---

## Task 9: Push and open the PR

**Files:** none

- [ ] **Step 1: Push the branch**

```bash
git push -u origin codex/finish-aws-sso-cli-cutover
```

- [ ] **Step 2: Open a PR**

```bash
gh pr create --title "Finish aws-sso-cli cutover + add awsp/awsx profile switcher" --body "$(cat <<'EOF'
## Summary
- Completes the aws-sso-cli → aws_config_gen cutover (prior commits: `AWS_SSO_PROFILE` → `AWS_PROFILE` in MCP work overlay, p10k `SHOW_ON_COMMAND` refresh, stale reference cleanup)
- Adds `awsp` and `awsx` — zsh helpers for in-session AWS profile selection without per-command `--profile`, while keeping the default "no profile set" behavior that cross-account scripts depend on
- Work-machine-gated via `.chezmoiignore`; personal machines unaffected

## Test plan
- [ ] `chezmoi apply` succeeds on a work machine and new shells have `AWS_PROFILE` unset
- [ ] `awsp` fzf picker opens, preview shows account/role/region, selection exports `AWS_PROFILE`
- [ ] `awsp -` unsets only `AWS_PROFILE` (STS helper env vars preserved)
- [ ] `awsx <profile>` inside tmux opens a new `aws:<profile>` window with the profile set
- [ ] `awsx <profile>` outside tmux spawns a subshell with the profile set; exit drops it
- [ ] Expired/missing SSO token emits a non-blocking warning
- [ ] Existing cross-account script using per-call `--profile` still works unchanged
- [ ] Personal-machine deploy does not ship `work-aws-shell-functions.zsh`

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
)"
```

- [ ] **Step 3: Confirm**

Report the PR URL.

---

## Self-Review Notes

- **Spec coverage:**
  - Two commands `awsp`/`awsx` → Tasks 3, 4, 5.
  - Shared fzf picker with preview → Task 2.
  - Non-blocking SSO token health check → Task 4.
  - `awsp -` unset semantics, preserves credential env vars → Task 3 (verified), Task 4 (retained).
  - tmux auto-detect via `$TMUX`, window naming `aws:<profile>` → Task 5.
  - Subshell fallback outside tmux → Task 5.
  - p10k `SHOW_ON_COMMAND` extension → Task 6.
  - Docs addition in `aws_config_gen/README.md` → Task 7.
  - Work-only gating via `.chezmoiignore` → Task 1.
  - New file `work-aws-shell-functions.zsh` (not appended to `work-shell-functions.zsh`) → Task 1.
  - Shell-startup unaffected / no-default preserved → Task 8 step 2, PR body test plan.
- **Placeholder scan:** No TBDs, TODOs, vague "add error handling" instructions, or undefined references.
- **Type consistency:** Function names `_awsp_pick`, `_awsp_check_token`, `awsp`, `awsx` used consistently across tasks. tmux flag `-e KEY=VAL` used consistently. `AWS_PROFILE` used as the sole exported var in all paths.
