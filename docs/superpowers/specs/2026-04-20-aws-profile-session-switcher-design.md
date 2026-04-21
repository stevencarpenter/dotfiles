# AWS Profile Session Switcher — Design

**Status:** Approved via brainstorming on 2026-04-20
**Branch:** `codex/finish-aws-sso-cli-cutover`
**Scope:** Work machines only

## Problem

After the cutover from `aws-sso-cli` to `aws_config_gen`, there is no ergonomic way to adopt an AWS profile for a shell
session. Current options are `aws --profile <name> …` per command or manual `export AWS_PROFILE=<name>`. Neither matches
the two real workflows:

1. **On-demand single-account work** — open a shell, pick an account, do work, maybe switch later.
2. **Ad-hoc multi-account work** — have several windows open, each pinned to a different account.

A hard constraint: the default must stay "no profile set" so that multi-account scripts that pass `--profile` per call
(e.g., artifact-upload loops) keep working unchanged.

## Goals

- Fast profile switching in the current shell, with an fzf picker.
- Dedicated shell/tmux-window per profile for parallel account work.
- Zero impact on shell startup: `AWS_PROFILE` remains unset on new shells.
- Visibility: existing p10k `aws` segment already reflects `AWS_PROFILE`; extend its `SHOW_ON_COMMAND` list.
- Work-only deployment; no impact on personal machines.

## Non-Goals

- Auto-running `aws sso login` (requires browser; noisy).
- Region override flags on the switcher (profiles in `~/.aws/config` carry their own region).
- Shell completion beyond the fzf picker.
- Caching the profile list (native `aws configure list-profiles` is fast).
- Replacing or modifying the existing `get_assumed_role_credentials` STS helper.

## Design

### Two Commands

**`awsp [profile|-]`** — set `AWS_PROFILE` in the current shell.

- No arg → fzf picker over `aws configure list-profiles`; selection exports `AWS_PROFILE`.
- Positional arg → direct set: `awsp prod-admin`.
- `awsp -` → unset `AWS_PROFILE` (returns to no-profile state). Does NOT touch
  `AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY` / `AWS_SESSION_TOKEN` so `get_assumed_role_credentials` state is not
  clobbered.

**`awsx [profile]`** — spawn a dedicated context with `AWS_PROFILE` pre-exported.

- Auto-detects environment via `$TMUX`:
  - **Inside tmux** → `tmux new-window -n "aws:<profile>"` running an interactive zsh with `AWS_PROFILE` exported.
  - **Outside tmux** → spawns a subshell (`AWS_PROFILE=<profile> zsh -i`). Exiting the subshell drops the profile.
- No arg → fzf picker (same picker implementation as `awsp`).
- Exiting the window/subshell releases the profile; no cleanup needed in the parent shell.

### Shared fzf Picker

A private helper `_awsp_pick` (leading underscore, not exported as a command) encapsulates:

1. Capture profiles from `aws configure list-profiles`.
2. Pipe to fzf with a preview pane that greps the `[profile <name>]` block out of `~/.aws/config` and renders
   `sso_account_id`, `sso_role_name`, and `region` lines.
3. Return the selected profile name on stdout, non-zero on cancel.

Both `awsp` and `awsx` reuse this.

### SSO Token Health Check

Before exporting the profile, a *fast local-only* check: for the profile's `sso_session`, read the matching token cache
JSON in `~/.aws/sso/cache/` and compare `expiresAt` to now.

- Valid → silent pass-through.
- Missing or expired → emit a single warning line: `⚠ SSO token expired/missing — run: aws sso login --sso-session <name>`
  and **continue** (don't block). The user may intentionally want the profile set before they log in.

No network call. No auto-login.

### p10k Integration

Update `dot_config/zsh/dot_p10k.zsh`:

```
POWERLEVEL9K_AWS_SHOW_ON_COMMAND='aws|aws-config-gen|awsp|awsx'
```

Safe to ship on all machines; on personal machines these commands don't exist, so the segment simply never activates.

### File Layout

**New:** `dot_config/zsh/profile.d/work-aws-shell-functions.zsh`

Contents (in order):
- `_awsp_pick` — internal fzf picker helper.
- `_awsp_check_token` — internal SSO token freshness check.
- `awsp` — Pattern A.
- `awsx` — Pattern C.

Loaded by the existing `profile.d/*.zsh` glob in `zshrc` (already in place for the other work/personal function files).

### Chezmoi Gating

Append one line to the work gating block in `.chezmoiignore`:

```
{{ if not (hasPrefix "work" .machine) }}
.config/aws-config-gen/overrides.json
.config/mcp/machine/work.json
.config/zsh/.work.env
.config/zsh/profile.d/work-secrets.zsh
.config/zsh/profile.d/work-shell-functions.zsh
.config/zsh/profile.d/work-aws-shell-functions.zsh   # NEW
{{ end }}
```

### Documentation

Add a "Using generated profiles" subsection to `aws_config_gen/README.md` describing `awsp` and `awsx`. One short
section; no separate doc file.

## Dependencies

- `fzf` — verify present in Brewfile; add if missing. (Expected to already be there.)
- `aws` CLI — already present.
- No new Python, no new Homebrew taps.

## Testing Strategy

Shell functions with external dependencies (aws CLI, fzf, tmux) are painful to unit-test. Strategy:

- **Manual smoke tests** (documented in the implementation plan):
  1. `awsp <profile>` with arg → `echo $AWS_PROFILE` matches.
  2. `awsp` (no arg) → fzf picker opens, selecting sets `AWS_PROFILE`.
  3. `awsp -` → `AWS_PROFILE` unset; credentials env vars untouched.
  4. `awsx <profile>` inside tmux → new window named `aws:<profile>`, profile set inside, parent shell unchanged.
  5. `awsx <profile>` outside tmux → subshell with profile set; exit returns to parent unchanged.
  6. Expired token → warning printed, profile still set.
  7. New shell → `AWS_PROFILE` unset (regression guard for the multi-account script use case).

- **No automated tests** for the shell functions. Chezmoi dotfiles repo has no shell test harness and adding one for
  four small functions is out of proportion.

## Alternatives Considered

- **Single `aws-switch --new-window` flag command.** Rejected: two short commands build muscle memory better than a
  flag, and the "where does the profile live" choice is a first-class UX concern, not a modifier.
- **Exec-replace for Pattern C (`exec env AWS_PROFILE=… zsh`).** Rejected: would make "exit = profile gone" impossible
  because exiting the replaced shell closes the terminal.
- **direnv / chpwd hook tying profile to repo directory.** Explicitly rejected by the user — doesn't match actual
  workflows.
- **Forking aws-config-gen to emit a profile manifest.** Rejected: `aws configure list-profiles` is native and
  authoritative; no duplicate state.
- **Auto-running `aws sso login` on expired token.** Rejected: requires browser, is noisy, and sometimes the user
  wants the profile set *before* logging in.
- **Adding functions to existing `work-shell-functions.zsh`.** Rejected: that file's current contents (`burp`,
  `get_assumed_role_credentials`) are unrelated concerns; a separate file keeps boundaries clean.

## Open Questions

None. Design is ready for implementation planning.

## Success Criteria

- `awsp` and `awsx` land as documented, gated to work machines.
- No shell-startup regression: `AWS_PROFILE` remains unset on new shells.
- Existing `get_assumed_role_credentials` and multi-account scripts that pass `--profile` work unchanged.
- P10k segment lights up when using the switchers.
- Manual smoke tests above all pass on a work machine.
