# Secrets → 1Password Connect Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace agenix (age ciphertext + shared age key) with 1Password Connect + `op inject` templates, so the same fail-safe renderer produces the `0600` secret files on both nix (m5, work m3) and stow (headless i9), and the repo ships zero ciphertext.

**Architecture:** A single portable shell renderer (`op-render`) reads a manifest of `template:target` pairs and, for each, `op inject`s an `op://Homelab/...` template to a same-directory tmpfile, then atomically `mv`s it over a `0600` target only if `op inject` succeeded and the output is non-empty. Triggered by launchd on i9 and by a home-manager activation entry on the nix machines. Migration is phased i9-first and coexists with agenix until every machine renders from `op://`, at which point agenix and all `*.age` blobs are deleted.

**Tech Stack:** bash (macOS `/bin/bash` 3.2-compatible), 1Password CLI `op` (Connect mode via `OP_CONNECT_HOST`/`OP_CONNECT_TOKEN`), self-hosted 1Password Connect, launchd (i9), nix-darwin/home-manager activation (m5/m3), agenix (retired at end).

Design spec: `docs/superpowers/specs/2026-07-11-secrets-op-connect-design.md`.

## Global Constraints

- **Zero secret ciphertext or values in the repo** — only `*.tpl` with `op://Homelab/<item>/<field>` refs. gitleaks + the hardcoded-secret pre-commit hook must stay green.
- **Never render in place** — always render-to-tmp (same dir) → validate non-empty + `op inject` exit 0 → `chmod 0600` → `mv -f`. A Connect/Tailscale outage must leave the previous good target untouched.
- **Connect tokens are read-only and scoped to the single Homelab vault**, one per machine, in `~/.config/op/connect-token` (`0600`, gitignored). `OP_CONNECT_HOST` is a Tailscale address, non-secret, committed.
- **Coexistence:** agenix and `op-render` write different files; migrate secret-by-secret, reversible. Delete each `age.secrets.<name>` only after its `op://` twin is verified.
- **Renderer must be bash 3.2-safe** (macOS default) — no associative arrays, no `mapfile`.
- **Follow repo test convention:** plain `scripts/test-*.sh`, wired into `.github/workflows/dotfiles-hygiene-ci.yml`. No bats.
- **Sub-project 3 boundary:** rendered secret files (`~/.config/zsh/.env`, `~/.ssh/config`) are NEVER included in any cross-machine config sync; only `*.tpl` templates are shareable.

## Progress

- ✅ **Task 3 — `op-render` renderer + tests** — DONE (commit `fb5b745`). Renderer at
  `home/.local/bin/op-render`, tests at `scripts/test-op-render.sh` (4 passing: happy/0600,
  creds-absent skip, inject-fail preserve, empty-output preserve), wired into
  `dotfiles-hygiene-ci.yml`. This is the fully in-repo, unblocked core.
- ⏳ **Blocked on homelab Connect standup (Task 2) + on-i9 access (Tasks 1, 5):** Tasks 1, 2, 4, 5,
  6, 7, 8. Do Task 1 (enumerate i9 secrets on-box) and Task 2 (stand up Connect) first; they gate
  the rest.

## File Structure

| Path | Responsibility | Task |
|---|---|---|
| `home/.local/bin/op-render` | The portable fail-safe renderer (on PATH via symlinked bin dir) | 3 |
| `scripts/test-op-render.sh` | Shell tests for the renderer, mock `op` | 3 |
| `home/.config/op/render-manifest` | `template:target` pairs (non-secret; committed) | 4 |
| `home/.config/zsh/env.tpl` | `op://` template for `~/.config/zsh/.env` (authored from the i9 inventory) | 4 |
| `home/.ssh/config.tpl` | `op://` template for `~/.ssh/config` | 4 |
| `modules/home/secrets.nix` | Shrinks as `age.secrets.*` are removed; imports drop at end | 6,7,8 |
| `modules/home/sync-hooks.nix` (or new `op-render.nix`) | home-manager activation entry calling `op-render` on nix machines | 6 |
| `secrets/`, `secrets/secrets.nix` | Deleted at retirement | 8 |
| `.gitignore` | Add `~/.config/op/connect-token` path guard note; ensure no rendered files tracked | 3 |
| `.github/workflows/dotfiles-hygiene-ci.yml` | Add `test-op-render.sh` | 3 |

---

### Task 1: Enumerate i9's real secret surface (operational — run ON i9)

**Files:** none in repo. Produces a redacted inventory (names + intended `op://Homelab/<item>/<field>` mapping) recorded in the PR description / a scratch note, never committed with values.

**Interfaces:**
- Produces: the authoritative list of env-var names i9's interactive shell needs, each mapped to a Homelab vault item/field. Task 4 authors `env.tpl` from this.

- [ ] **Step 1: On i9, list env-var names only (values redacted).** SSH to i9, then run against each secret-bearing file it currently loads:

```bash
for f in ~/.config/zsh/.env ~/.config/zsh/.personal.env ~/.config/zsh/.lab.env; do
  [ -f "$f" ] && { echo "== $f =="; \
    rg --hidden -o '^\s*(export\s+)?[A-Za-z_][A-Za-z0-9_]*=' "$f" | sed -E 's/^\s*(export\s+)?//; s/=.*$//' | sort; }
done
```

Expected: the true dozen-plus var names (e.g. `CLAUDE_CODE_OAUTH_TOKEN`, `OPENAI_API_KEY`, …). Record names only.

- [ ] **Step 2: Capture the ssh-config secret shape (names only).**

```bash
rg --hidden -o '^\s*[A-Za-z]+' ~/.ssh/config | tr -d ' ' | sort -u
```

Expected: directive names (`Host`, `HostName`, `User`, `IdentityAgent`, …) — identifies which fields become `op://` refs.

- [ ] **Step 3: Write the mapping.** For each var, note the target `op://Homelab/<item>/<field>`. Flag any not yet in the Homelab vault (they get created in Task 2). No commit — this is input to Tasks 2 and 4.

---

### Task 2: Homelab Connect + vault prep (operational — homelab repo / 1Password)

**Files:** none in this repo (Connect container config lives in the homelab repo).

**Interfaces:**
- Produces: a reachable Connect endpoint (`OP_CONNECT_HOST`) scoped to the Homelab vault, and the ability to mint per-machine read-only tokens (Task 5/6/7 consume these).

- [ ] **Step 1: Stand up 1Password Connect in the homelab.** Follow the current official Connect deployment (Secrets Automation → `1password-credentials.json` + a Connect server), exposed on the Tailscale network. This is homelab-repo work; verify against 1Password's current docs at implementation time (do not hardcode a possibly-stale flag set here).

- [ ] **Step 2: Confirm the canonical Homelab vault and consolidate.** Ensure every item/field from the Task 1 mapping exists in the **Homelab** vault. Sweep any stragglers out of the **Private** vault into Homelab so Connect can be scoped to exactly one vault.

- [ ] **Step 3: Verify Connect answers.** From a machine on Tailscale with a temporary token:

```bash
OP_CONNECT_HOST=http://<tailscale-host>:8080 OP_CONNECT_TOKEN=<tmp> op vault list
```

Expected: the Homelab vault is listed. Revoke the temporary token afterward.

---

### Task 3: The `op-render` fail-safe renderer (TDD — in this repo)

**Files:**
- Create: `home/.local/bin/op-render`
- Create: `scripts/test-op-render.sh`
- Modify: `.github/workflows/dotfiles-hygiene-ci.yml` (add the test)

**Interfaces:**
- Consumes: env `OP_CONNECT_HOST`, `OP_CONNECT_TOKEN`; env `OP_BIN` (override for tests, default `op`); env `OP_RENDER_MANIFEST` (default `~/.config/op/render-manifest`).
- Produces: executable `op-render` that renders each `template:target` line; exits 0 when creds absent (skip) or all render; nonzero if any render failed. Never leaves a partial/empty target.

- [ ] **Step 1: Write the failing test** (`scripts/test-op-render.sh`):

```bash
#!/usr/bin/env bash
set -uo pipefail
here="$(cd "$(dirname "$0")/.." && pwd)"
RENDER="$here/home/.local/bin/op-render"
fails=0
run() { local name="$1"; shift; if "$@"; then echo "ok - $name"; else echo "FAIL - $name"; fails=$((fails+1)); fi; }

setup() { work="$(mktemp -d)"; export OP_RENDER_MANIFEST="$work/manifest"; tpl="$work/in.tpl"; out="$work/out";
  printf 'export FOO={{ op://Homelab/x/y }}\n' >"$tpl"; printf '%s:%s\n' "$tpl" "$out" >"$OP_RENDER_MANIFEST"; }
mock_op() { export OP_BIN="$work/op"; { echo '#!/usr/bin/env bash'; echo "$1"; } >"$work/op"; chmod +x "$work/op"; }

t_happy() { setup; mock_op 'shift; while [ $# -gt 1 ]; do [ "$1" = "-o" ] && { out="$2"; }; shift; done; printf "export FOO=bar\n" >"$out"; exit 0'
  OP_CONNECT_HOST=h OP_CONNECT_TOKEN=t "$RENDER" >/dev/null 2>&1; [ "$(cat "$out")" = "export FOO=bar" ] && [ "$(stat -f '%Lp' "$out")" = "600" ]; }

t_creds_absent_skips() { setup; printf 'PRE\n' >"$out"; mock_op 'exit 0'
  ( unset OP_CONNECT_HOST OP_CONNECT_TOKEN; "$RENDER" >/dev/null 2>&1 ); [ "$(cat "$out")" = "PRE" ]; }

t_inject_fail_preserves() { setup; printf 'GOOD\n' >"$out"; mock_op 'exit 3'
  OP_CONNECT_HOST=h OP_CONNECT_TOKEN=t "$RENDER" >/dev/null 2>&1; local rc=$?; [ "$(cat "$out")" = "GOOD" ] && [ "$rc" -ne 0 ]; }

t_empty_output_preserves() { setup; printf 'GOOD\n' >"$out"; mock_op 'shift; while [ $# -gt 1 ]; do [ "$1" = "-o" ] && out="$2"; shift; done; : >"$out"; exit 0'
  OP_CONNECT_HOST=h OP_CONNECT_TOKEN=t "$RENDER" >/dev/null 2>&1; [ "$(cat "$out")" = "GOOD" ]; }

run "happy path renders 0600" t_happy
run "absent creds skip, keep file" t_creds_absent_skips
run "inject failure preserves target" t_inject_fail_preserves
run "empty output preserves target" t_empty_output_preserves
[ "$fails" -eq 0 ] || { echo "$fails test(s) failed"; exit 1; }
echo "all op-render tests passed"
```

- [ ] **Step 2: Run to verify it fails.**

Run: `bash scripts/test-op-render.sh`
Expected: FAIL — `op-render` does not exist yet.

- [ ] **Step 3: Write the renderer** (`home/.local/bin/op-render`):

```bash
#!/usr/bin/env bash
# op-render — render op:// templates to 0600 files via 1Password Connect. Fail-safe: never
# truncates a target if op inject fails or Connect is unreachable. bash 3.2 safe.
set -uo pipefail
OP_BIN="${OP_BIN:-op}"
MANIFEST="${OP_RENDER_MANIFEST:-$HOME/.config/op/render-manifest}"
log() { printf 'op-render: %s\n' "$*" >&2; }

if [ -z "${OP_CONNECT_HOST:-}" ] || [ -z "${OP_CONNECT_TOKEN:-}" ]; then
  log "Connect creds not set; skipping (existing secret files left intact)."; exit 0
fi
[ -f "$MANIFEST" ] || { log "no manifest at $MANIFEST; nothing to render."; exit 0; }

rc=0
while IFS=: read -r tpl target; do
  [ -z "${tpl:-}" ] && continue
  case "$tpl" in \#*) continue ;; esac
  tpl="${tpl/#\~/$HOME}"; target="${target/#\~/$HOME}"
  dir="$(dirname "$target")"; mkdir -p "$dir"
  tmp="$(mktemp "$dir/.op-render.XXXXXX")" || { log "mktemp failed: $target"; rc=1; continue; }
  if ! "$OP_BIN" inject -i "$tpl" -o "$tmp" 2>/dev/null; then
    log "op inject failed: $tpl (keeping $target)"; rm -f "$tmp"; rc=1; continue
  fi
  if [ ! -s "$tmp" ]; then
    log "empty render: $tpl (keeping $target)"; rm -f "$tmp"; rc=1; continue
  fi
  chmod 0600 "$tmp"; mv -f "$tmp" "$target"; log "rendered $target"
done < "$MANIFEST"
exit "$rc"
```

- [ ] **Step 4: Make it executable and set the git mode.**

```bash
chmod +x home/.local/bin/op-render
git update-index --add --chmod=+x home/.local/bin/op-render 2>/dev/null || true
```

- [ ] **Step 5: Run tests to verify they pass.**

Run: `bash scripts/test-op-render.sh`
Expected: `all op-render tests passed`.

- [ ] **Step 6: Wire into CI.** Add to `.github/workflows/dotfiles-hygiene-ci.yml` alongside the other `scripts/test-*.sh` invocations:

```yaml
      - name: op-render renderer tests
        run: bash scripts/test-op-render.sh
```

- [ ] **Step 7: Commit.**

```bash
git add home/.local/bin/op-render scripts/test-op-render.sh .github/workflows/dotfiles-hygiene-ci.yml
git commit -m "feat: add fail-safe op-render renderer + tests"
```

---

### Task 4: Author templates + manifest from the i9 inventory

**Files:**
- Create: `home/.config/op/render-manifest`
- Create: `home/.config/zsh/env.tpl`
- Create: `home/.ssh/config.tpl`
- Modify: `modules/home/dotfiles.nix` (symlink the new `.tpl` + manifest; NOT the rendered targets)

**Interfaces:**
- Consumes: the Task 1 var→`op://` mapping.
- Produces: templates the renderer consumes; the manifest listing `template:target` pairs.

- [ ] **Step 1: Write the manifest** (`home/.config/op/render-manifest`) — non-secret, committed:

```
~/.config/zsh/env.tpl:~/.config/zsh/.env
~/.ssh/config.tpl:~/.ssh/config
```

- [ ] **Step 2: Author `env.tpl` from the Task 1 mapping.** One line per enumerated var, value quoted. Worked example (replace with the real enumerated set — never invent refs for vars not confirmed in Task 1):

```
export CLAUDE_CODE_OAUTH_TOKEN="{{ op://Homelab/Claude Code/oauth_token }}"
export OPENAI_API_KEY="{{ op://Homelab/OpenAI/api_key }}"
export OPENROUTER_TOKEN="{{ op://Homelab/OpenRouter/token }}"
export CONTEXT7_API_KEY="{{ op://Homelab/Context7/api_key }}"
```

- [ ] **Step 3: Author `config.tpl`** — the ssh config with only the sensitive fields as `op://` refs, structural directives (from Task 1 Step 2) as plaintext.

- [ ] **Step 4: Validate templates contain only `op://` refs (no literal secrets).**

Run: `rg --hidden -n 'op://' home/.config/zsh/env.tpl home/.ssh/config.tpl && ! rg --hidden -nP '=(?!"?\{\{)' home/.config/zsh/env.tpl`
Expected: every value is an `op://` ref; no literal RHS values.

- [ ] **Step 5: Symlink templates + manifest via nix** (`modules/home/dotfiles.nix`) — add `.config/op/render-manifest`, `.config/zsh/env.tpl`, `.ssh/config.tpl` to the appropriate identity blocks. Do NOT symlink `.env`/`.ssh/config` (those are rendered, not tracked).

- [ ] **Step 6: Commit.**

```bash
git add home/.config/op/render-manifest home/.config/zsh/env.tpl home/.ssh/config.tpl modules/home/dotfiles.nix
git commit -m "feat: add op:// secret templates + render manifest"
```

---

### Task 5: i9 pilot deploy (operational — run ON i9)

**Files:** i9's stow/homelab repo gets a launchd plist + a vendored copy of `op-render` + templates (sub-project 3 will later automate the copy; for now, vendor manually).

**Interfaces:**
- Consumes: `op-render`, templates, manifest (Task 3/4); a per-machine Connect token (Task 2).
- Produces: i9 rendering both secret files at boot from `op://`.

- [ ] **Step 1: Provision the Connect token on i9.** Mint a read-only, Homelab-scoped token; write it `0600`:

```bash
install -m 700 -d ~/.config/op
umask 177; printf '%s' '<token>' > ~/.config/op/connect-token
```

Set `OP_CONNECT_HOST` (Tailscale addr) in i9's non-secret shell env.

- [ ] **Step 2: Vendor `op-render` + templates + manifest onto i9** (from the committed repo copies) and install a launchd agent that exports `OP_CONNECT_HOST` + `OP_CONNECT_TOKEN` (read from the `0600` file) and runs `op-render`, `RunAtLoad = true`.

- [ ] **Step 3: Verify happy-path render.**

```bash
launchctl kickstart -k gui/$(id -u)/<agent-label>
diff <(rg --hidden -o '^\s*(export )?[A-Za-z_]+' ~/.config/zsh/.env | sed -E 's/^\s*(export )?//') <i9-inventory-names>
```

Expected: `.env` var names match the Task 1 inventory; `~/.ssh/config` present; both `0600`.

- [ ] **Step 4: Verify the fail-safe on i9** (the critical headless test). Point `OP_CONNECT_HOST` at an unreachable address, re-run `op-render`, and assert the existing files are UNCHANGED (not truncated):

```bash
OP_CONNECT_HOST=http://127.0.0.1:1 OP_CONNECT_TOKEN=x op-render; echo "exit=$?"; test -s ~/.ssh/config && echo "ssh config intact"
```

Expected: `exit` nonzero, "ssh config intact", `.env` unchanged.

- [ ] **Step 5: Cut i9 over.** Confirm a fresh login shell sources the rendered `.env` and `ssh` reads its config. Remove i9's old chezmoi/age secret delivery path.

---

### Task 6: m5 migration (nix activation), secret-by-secret

**Files:**
- Create: `modules/home/op-render.nix` (activation entry) OR extend `modules/home/sync-hooks.nix`
- Modify: `modules/home/secrets.nix` (remove migrated `age.secrets.<name>`)
- Modify: `modules/home/default.nix` (import op-render module if new)

**Interfaces:**
- Consumes: `op-render`, templates, manifest, an m5 Connect token.
- Produces: m5 rendering from `op://` via activation; migrated `age.secrets` removed.

- [ ] **Step 1: Provision m5's Connect token** (read-only, Homelab-scoped) into `~/.config/op/connect-token` (`0600`); set `OP_CONNECT_HOST`.

- [ ] **Step 2: Add the activation entry** (`entryAfter [ "writeBoundary" ]`, warn-not-fail, matching the sync-hooks pattern) that exports the Connect env and runs `${home}/.local/bin/op-render`:

```nix
# modules/home/op-render.nix
{ config, lib, ... }:
let home = config.home.homeDirectory; in {
  home.activation.opRender = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    ( set -u
      TOKEN_FILE="${home}/.config/op/connect-token"
      [ -r "$TOKEN_FILE" ] || { echo "op-render: no Connect token; skipping." >&2; exit 0; }
      export OP_CONNECT_TOKEN="$(cat "$TOKEN_FILE")"
      export OP_CONNECT_HOST="''${OP_CONNECT_HOST:-}"
      "${home}/.local/bin/op-render" || echo "op-render: warned (non-fatal)." >&2
    ) || true
  '';
}
```

- [ ] **Step 3: Rebuild and verify m5 renders.**

Run: `./rebuild.sh personal-mac` then check `~/.config/zsh/.env` matches m5's expected vars and is `0600`.
Expected: rendered file present; shell sources it.

- [ ] **Step 4: Remove the migrated `age.secrets` from `secrets.nix`** (the ones now rendered on m5: `zsh-env`, `ssh-config`, `zsh-personal-env`). Keep work-only entries until Task 7.

- [ ] **Step 5: Rebuild, verify no regression, commit.**

```bash
./rebuild.sh personal-mac
git add modules/home/op-render.nix modules/home/default.nix modules/home/secrets.nix
git commit -m "feat: render m5 secrets via op-render; drop migrated agenix entries"
```

---

### Task 7: work m3 migration

**Files:** Modify `modules/home/secrets.nix` (remove work `age.secrets`: `zsh-work-env`, `aws-config-gen-overrides`, 25× `claude-skill-*`).

**Interfaces:**
- Consumes: op-render, templates (work vars added to `env.tpl`/manifest as in Task 4), m3 Connect token.
- Produces: m3 rendering from `op://`; agenix work entries removed.

- [ ] **Step 1: Enumerate m3's work secret var names** (repeat Task 1 on m3), map to Homelab items, extend `env.tpl`/manifest with work targets (`~/.config/zsh/.work.env`, `~/.config/aws-config-gen/overrides.json`, and the 25 claude-skill paths).

- [ ] **Step 2: Provision m3's Connect token; rebuild `./rebuild.sh work-mac`; verify** all work secret files render and are `0600`.

- [ ] **Step 3: Remove the work `age.secrets` entries; rebuild; verify; commit.**

```bash
git add modules/home/secrets.nix home/.config/op/render-manifest home/.config/zsh/env.tpl
git commit -m "feat: render work-mac secrets via op-render; drop work agenix entries"
```

---

### Task 8: Retire agenix

**Files:**
- Delete: `secrets/` (all `*.age` blobs + `secrets/secrets.nix` + `secrets/README.md` or rewrite)
- Modify: `modules/home/secrets.nix` (delete file or reduce to empty), `modules/home/default.nix` (drop agenix import), `flake.nix` (drop the agenix input if unused elsewhere), `bootstrap.sh` (drop the age-key `op read > key.txt` step)

**Interfaces:**
- Consumes: nothing (terminal).
- Produces: repo with zero ciphertext, no age key, no agenix.

- [ ] **Step 1: Confirm all three machines render from `op://`** (m5, m3, i9 all have working `op-render` output; no machine still depends on any `age.secrets`).

- [ ] **Step 2: Delete the agenix surface.**

```bash
git rm -r secrets/
git rm modules/home/secrets.nix   # or reduce to a stub if other config remains
```

Remove the agenix import from `modules/home/default.nix`, the `inputs.agenix` from `flake.nix` (if unreferenced), and the age-key step from `bootstrap.sh`.

- [ ] **Step 3: Evaluate and verify zero ciphertext.**

Run: `nix flake check --no-build` (in CI/on a mac) and `rg --hidden -l -- '-----BEGIN AGE' . ; echo "blobs: $?"`
Expected: flake evaluates; no age blobs remain.

- [ ] **Step 4: Update docs.** Note in `docs/nix-migration.md` §d that deferred items 1–2 (re-encryption / opnix end-state) are superseded by the Connect migration.

- [ ] **Step 5: Commit.**

```bash
git add -A
git commit -m "refactor: retire agenix — secrets fully on 1Password Connect"
```

---

## Self-Review

**Spec coverage:** §3 architecture → Tasks 3–4; §4.1 Connect → Task 2; §4.2 vault → Task 2; §4.3 templates → Task 4; §4.4 render script → Task 3; §4.5 triggers → Task 5 (launchd) + Task 6 (activation); §4.6 bootstrap token → Tasks 5–7; §5 inventory + i9 gap → Task 1; §6 phasing → Tasks 5→6→7→8; §7 posture → achieved by Task 8; §8 testing → Task 3 (unit) + Task 5 Step 4 (on-hardware fail-safe). No uncovered spec sections.

**Placeholder scan:** The only non-literal content is `env.tpl`/`config.tpl` bodies and the i9 var list — deliberately, because they are secret-inventory-dependent and only knowable on the box (Task 1). Task 4 gives the exact format + a worked example and forbids inventing refs, so this is a procedure, not a placeholder.

**Type consistency:** Renderer env contract (`OP_BIN`, `OP_RENDER_MANIFEST`, `OP_CONNECT_HOST`, `OP_CONNECT_TOKEN`) is identical across Task 3 (definition), Task 5 (launchd), Task 6 (activation). Manifest format (`template:target`, `~` expansion, `#` comments) is consistent between Task 3 parser and Task 4 authoring.

**Known operational dependencies (not gaps):** Task 2 (Connect standup) is homelab-repo work and gates Tasks 5–7; Task 1 (on-i9 enumeration) gates Task 4. Both are explicit, ordered tasks.
