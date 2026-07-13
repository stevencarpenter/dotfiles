# WS1 — Migrate m5 personal + common secrets: agenix → op inject Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Render personal-mac (m5)'s common + personal secret files from `op://` templates via `op inject`, removing their agenix `age.secrets` entries — proving the `op` pattern in-band before work extraction relies on it.

**Architecture:** m5 has the 1Password **desktop app** (biometric), so it renders via **desktop-app `op inject`** — **no Connect server or token** (that is i9/WS3's path). The existing `home/.local/bin/op-render` (fail-safe render-to-tmp → validate non-empty → atomic `mv` over `0600`) is extended with an "interactive op available" mode. A `home.activation` entry runs it warn-not-fail after `writeBoundary`. Common+personal `age.secrets.*` are deleted; the **work** block and the shared age key stay (removed in WS2/WS4).

> **Vault decision (2026-07-12 — authoritative; supersedes the illustrative `op://Homelab/*` examples further down).** The 14 personal dev secrets reference the **Private** vault (`op://Private/<item>/<field>`) — most already live there (OpenAI, OpenRouter, Context7, Clerk, nugs); the desktop app reads any vault, so no migration. A dedicated "Dev" vault was considered and **abandoned/deleted**. The **exception** is the ssh-config's i9 host fields, which are genuine **homelab infra** and stay in the **Homelab** vault (`op://Homelab/I9/*`). So the split is: **personal dev secrets → Private, homelab infra → Homelab.** Enumeration is already done — the concrete var list is in Linear SNUG-386.

**Tech Stack:** nix-darwin + home-manager, agenix (being partially retired), 1Password CLI (`op`), plain-shell tests (no bats), `op inject` templates.

**Linear:** SNUG-386. Design: `docs/superpowers/specs/2026-07-11-secrets-op-connect-design.md`. Renderer already built/tested (`home/.local/bin/op-render`, `scripts/test-op-render.sh`; test perm() fixed PR #124).

## Global Constraints

- **Deviation from spec (approved in-plan):** m5 uses desktop-app `op`, NOT Connect. Connect (SNUG-384) is only a WS3/i9 dependency; WS1's Linear block on SNUG-384 is dropped.
- **Never render in place.** `op inject -o <target>` directly is forbidden — a failed/empty inject would truncate the file. Always render-to-tmp in the target's dir → validate → atomic `mv`.
- **Fail-safe is sacred.** If `op` cannot authenticate or inject fails/returns empty, the existing target file MUST be left byte-for-byte intact and the switch MUST NOT fail (`|| true`, warn-not-fail — matches `modules/home/sync-hooks.nix`).
- **Zero secret values in the repo, ever.** Templates contain only `op://<vault>/<item>/<field>` refs (Private for personal dev secrets, Homelab for the i9 infra fields — see the Vault decision above). No plaintext secret in any `.tpl`, doc, commit message, or this plan. gitleaks (pre-commit) must pass.
- **Names-only enumeration.** When listing secret env vars, record variable NAMES and `op://` refs only — never values. Do not paste decrypted content into any file, commit, or transcript.
- **Scope = m5 (identity `personal`) common + personal only.** Do NOT touch the `identity == "work"` block in `secrets.nix` (WS2) or delete the age key / `secrets/` blobs (WS4).
- **Sandbox:** `op`, `uv`, `git push` calls run with the sandbox disabled (repo convention; see the sandbox-preflight skill). `op` writes/reads use the desktop-app session.
- **Commits:** Conventional prefix, one line, NO `Co-Authored-By` / AI-attribution trailer (commit-msg hook strips it; do not emit it).

---

## File Structure

| File | Responsibility |
|---|---|
| `home/.local/bin/op-render` | Extend: add interactive-op mode between Connect-mode and skip. |
| `scripts/test-op-render.sh` | Extend: cover interactive-available render + no-auth skip. |
| `home/.config/zsh/.personal.env.tpl` | NEW — `op://Private/*` template for personal API tokens. |
| `home/.config/zsh/.env.tpl` *(conditional)* | NEW **iff** `.env` holds a real secret; else `.env` becomes a plain committed file. |
| `home/.ssh/config.tpl` | NEW — ssh config with sensitive fields as `op://` refs. |
| `home/.config/op/render-manifest` | NEW — `template:target` lines the renderer consumes. |
| `modules/home/secrets.nix` | Remove common+personal `age.secrets`; keep work block + age identity. |
| `modules/home/sync-hooks.nix` | Add `opRender` `home.activation` entry (warn-not-fail). |
| `.gitignore` | Ignore `~/.config/op/connect-token` (future Connect) + rendered targets already ignored. |
| `docs/superpowers/plans/ws1-m5-secret-map.md` | NEW — names + `op://` refs mapping (NO values). |

---

## Task 1: Enumerate m5's secret surface and build the op mapping

**Files:**
- Create: `docs/superpowers/plans/ws1-m5-secret-map.md` (names + `op://` refs only)

**Interfaces:**
- Produces: the authoritative env-var-name → `op://<vault>/<item>/<field>` map every later template consumes. Also classifies each of the 3 files as *secret* (template) or *non-secret* (plain committed file).

- [ ] **Step 1: Decrypt the three files locally, names-only**

Run (sandbox disabled; key already at `~/.config/chezmoi/key.txt`):
```bash
cd ~/.local/share/chezmoi-m5
for f in common/zsh-env personal/zsh-personal-env; do
  echo "== $f =="
  age -d -i ~/.config/chezmoi/key.txt "secrets/$f.age" | grep -oE '^(export )?[A-Z_][A-Z0-9_]*=' | sed 's/=$//; s/^export //'
done
echo "== ssh-config (sensitive fields) =="
age -d -i ~/.config/chezmoi/key.txt secrets/common/ssh-config.age | grep -iE '^\s*(host|hostname|user|identityfile|proxyjump|port)\b'
```
Expected: a list of VARIABLE NAMES (e.g. `OPENAI_API_KEY`, `OPENROUTER_TOKEN`, `CONTEXT7_API_KEY`) and ssh host stanzas. **Do not record any value to the right of `=`.**

- [ ] **Step 2: Classify each variable**

For every name, decide: real secret (→ `op://` ref) or non-secret config (e.g. `ENABLE_LSP_TOOL=1`, `ENABLE_TOOL_SEARCH`). Per the design §5, `common/zsh-env` on m5 may be ONLY a non-secret flag — if so, `.env` becomes a plain committed file (Task 3), NOT a template, and drops out of the secret surface entirely.

- [ ] **Step 3: Ensure each real secret exists in the Private vault (create only the missing ones)**

Most of the 14 already live in **Private** (OpenAI, OpenRouter, Context7, Clerk, nugs) — reference them in place, no move needed. For each secret var, confirm its item/field:
```bash
op item list --vault Private | rg -i '<candidate item>'
op item get '<Item>' --vault Private --format json | jq '[.fields[].label]'   # confirm field label
```
Only ~6 need creating (`CLAUDE_CODE_OAUTH_TOKEN`, `LLM_API_KEY`, `STRIX_LLM`, `AUTH_JWKS_URL`, `E2E_TEST_USER_*`):
```bash
# op item create --vault Private --category 'API Credential' --title '<Item>' 'credential=...'
```
The ssh-config's i9 host fields are **homelab infra** — reference/confirm those in the **Homelab** vault (`op item get I9 --vault Homelab`), not Private.

- [ ] **Step 4: Write the mapping doc (names + refs only)**

Create `docs/superpowers/plans/ws1-m5-secret-map.md`:
```markdown
# WS1 m5 secret map (names + op:// refs only — NO values)

| var / field | file | classification | op:// ref |
|---|---|---|---|
| OPENAI_API_KEY | .personal.env | secret | op://Private/OpenAI/api_key |
| OPENROUTER_TOKEN | .personal.env | secret | op://Private/OpenRouter/token |
| ENABLE_LSP_TOOL | .env | non-secret | (plain committed) |
| Host homelab / HostName | ~/.ssh/config | secret | op://Homelab/I9/tailscale_ip |
| ... | ... | ... | ... |
```
(Fill from Steps 1–3. Every "secret" row must have a resolvable ref.)

- [ ] **Step 5: Verify every ref resolves (desktop-app op)**

Run:
```bash
rg -o 'op://[^ )|]+' docs/superpowers/plans/ws1-m5-secret-map.md | sort -u | while read -r ref; do
  if op read "$ref" >/dev/null 2>&1; then echo "ok   $ref"; else echo "MISS $ref"; fi
done
```
Expected: every ref prints `ok`. Any `MISS` → create/rename the vault item and re-run until zero misses. (`op read` uses the desktop app — no Connect needed.)

- [ ] **Step 6: Commit the map**

```bash
git switch -c feat/ws1-m5-op-inject
git add docs/superpowers/plans/ws1-m5-secret-map.md
git commit -m "docs: map m5 personal/common secrets to op:// Homelab refs (WS1)"
```

---

## Task 2: Extend op-render with an interactive-op mode

**Files:**
- Modify: `home/.local/bin/op-render`
- Test: `scripts/test-op-render.sh`

**Interfaces:**
- Consumes: `OP_BIN` (default `op`), `OP_RENDER_MANIFEST`, optional `OP_CONNECT_HOST`/`OP_CONNECT_TOKEN`.
- Produces: an `op-render` that renders when EITHER Connect creds are set OR an interactive `op` session is available, and still skips (exit 0, files intact) when NEITHER is present. Auth precedence: Connect creds → interactive session → skip.

- [ ] **Step 1: Write the failing tests**

Append to `scripts/test-op-render.sh` (before the `run` block), two cases. The mock already switches on `$OP_MOCK_MODE`; add an auth probe the script will call (`op account list`) that the mock answers via `$OP_MOCK_AUTH`:

Extend `make_mock` to handle an `account` subcommand:
```bash
# inside the mock's `case "$1"` for the first arg — add before the inject handling:
#   account) case "${OP_MOCK_AUTH:-none}" in ok) echo '[{"url":"my.1password.com"}]'; exit 0 ;; *) exit 1 ;; esac ;;
```
Then the tests:
```bash
t_interactive_renders() {
  setup; : > "$target"
  ( unset OP_CONNECT_HOST OP_CONNECT_TOKEN
    OP_MOCK_MODE=ok OP_MOCK_AUTH=ok "$RENDER" >/dev/null 2>&1 )
  [ "$(cat "$target")" = "export FOO=bar" ] && [ "$(perm "$target")" = "600" ]
}

t_no_auth_skips() {
  setup; printf 'PRE\n' > "$target"
  ( unset OP_CONNECT_HOST OP_CONNECT_TOKEN
    OP_MOCK_MODE=ok OP_MOCK_AUTH=none "$RENDER" >/dev/null 2>&1 )
  [ "$(cat "$target")" = "PRE" ]
}
```
Add to the run list:
```bash
run "interactive op renders 0600"      t_interactive_renders
run "no auth (no connect, no session)" t_no_auth_skips
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `bash scripts/test-op-render.sh` (sandbox disabled)
Expected: FAIL on `interactive op renders 0600` (current script skips when Connect creds absent, regardless of session).

- [ ] **Step 3: Extend the auth guard in op-render**

Replace the guard block (`home/.local/bin/op-render` lines ~23-26) with a three-way precedence:
```bash
if [ -n "${OP_CONNECT_HOST:-}" ] && [ -n "${OP_CONNECT_TOKEN:-}" ]; then
  :  # Connect mode (headless, e.g. i9)
elif "$OP_BIN" account list >/dev/null 2>&1; then
  :  # interactive desktop-app session (e.g. m5)
else
  log "no op auth (no Connect creds, no interactive session); skipping (files left intact)."
  exit 0
fi
```
(Everything below — manifest read, render-to-tmp, validate, atomic `mv` — is unchanged.)

- [ ] **Step 4: Run tests to verify they pass**

Run: `bash scripts/test-op-render.sh` (sandbox disabled)
Expected: all 6 tests PASS (`all op-render tests passed`).

- [ ] **Step 5: Commit**

```bash
git add home/.local/bin/op-render scripts/test-op-render.sh
git commit -m "feat: op-render interactive-op mode (desktop app, no Connect)"
```

---

## Task 3: Author templates + render manifest for m5

**Files:**
- Create: `home/.config/zsh/.personal.env.tpl`
- Create: `home/.ssh/config.tpl`
- Create: `home/.config/zsh/.env.tpl` *(only if Task 1 classified `.env` as holding a secret; else create a plain `home/.config/zsh/.env` committed file with the non-secret flags)*
- Create: `home/.config/op/render-manifest`

**Interfaces:**
- Consumes: the map from Task 1.
- Produces: committed `*.tpl` files (public-safe) + a `template:target` manifest the activation entry (Task 4) points `op-render` at.

- [ ] **Step 1: Author `.personal.env.tpl`**

One line per secret from the map, values quoted to survive whitespace:
```bash
# home/.config/zsh/.personal.env.tpl  (fill refs from ws1-m5-secret-map.md)
export OPENAI_API_KEY="{{ op://Private/OpenAI/api_key }}"
export OPENROUTER_TOKEN="{{ op://Private/OpenRouter/token }}"
# ...every secret var from the map...
```

- [ ] **Step 2: Author `.ssh/config.tpl`**

Copy the current ssh config structure (from Task 1 Step 1's stanza list), replacing only sensitive fields with refs:
```bash
# home/.ssh/config.tpl
Host homelab
  HostName {{ op://Homelab/I9/tailscale_ip }}
  User {{ op://Homelab/I9/username }}
# ...non-sensitive lines verbatim...
```

- [ ] **Step 3: Handle `.env` per its classification**

If `.env` is non-secret only (likely): create plain `home/.config/zsh/.env` with the flags, and it will be linked by `dotfiles.nix` as a normal out-of-store symlink (a follow-up wiring line — note it in the task's commit). If it holds a secret, create `home/.config/zsh/.env.tpl` like Step 1 and include it in the manifest.

- [ ] **Step 4: Author the render manifest**

```bash
# home/.config/op/render-manifest  (template:target, ~ expands in op-render)
~/.dotfiles/home/.config/zsh/.personal.env.tpl:~/.config/zsh/.personal.env
~/.dotfiles/home/.ssh/config.tpl:~/.ssh/config
# add the .env.tpl line ONLY if .env holds a secret
```

- [ ] **Step 5: Verify templates render locally (desktop app), fail-safe intact**

Run (sandbox disabled):
```bash
OP_RENDER_MANIFEST=~/.dotfiles/home/.config/op/render-manifest ~/.dotfiles/home/.local/bin/op-render
stat -f '%Lp' ~/.config/zsh/.personal.env   # → 600
rg -c 'op://' ~/.config/zsh/.personal.env    # → 0 (fully rendered, no refs left)
```
Expected: rendered `0600` files with real values, zero `op://` residue. Then the fail-safe check:
```bash
cp ~/.ssh/config /tmp/ssh.good
OP_BIN=/usr/bin/false OP_RENDER_MANIFEST=~/.dotfiles/home/.config/op/render-manifest ~/.dotfiles/home/.local/bin/op-render || true
diff ~/.ssh/config /tmp/ssh.good && echo "FAIL-SAFE OK: config unchanged"
```
Expected: `FAIL-SAFE OK` (a broken `op` left the file intact).

- [ ] **Step 6: Confirm no secret leaked into templates, then commit**

Run: `pre-commit run gitleaks --all-files` (or the repo's gitleaks hook) → PASS.
Run: `rg -n 'op://' home/.config/zsh/*.tpl home/.ssh/config.tpl` → every sensitive field is a ref, no literal values.
```bash
git add home/.config/zsh/.personal.env.tpl home/.ssh/config.tpl home/.config/op/render-manifest
# + home/.config/zsh/.env or .env.tpl per classification
git commit -m "feat: op:// templates + render manifest for m5 secrets (WS1)"
```

---

## Task 4: Wire the nix activation trigger and remove common/personal age.secrets

**Files:**
- Modify: `modules/home/sync-hooks.nix` (add `opRender` activation entry)
- Modify: `modules/home/secrets.nix` (remove common + personal `age.secrets`; keep work block + `age.identityPaths`)
- Modify: `.gitignore` (ignore `~/.config/op/connect-token`)
- Modify: `modules/home/dotfiles.nix` (link the manifest + templates + any plain `.env`) — follow the existing `mkLinks` pattern

**Interfaces:**
- Consumes: `home/.local/bin/op-render`, the manifest, the templates.
- Produces: an `opRender` `home.activation` entry that renders m5's secrets each switch, warn-not-fail; a `secrets.nix` whose common/personal blocks are gone.

- [ ] **Step 1: Add the `opRender` activation entry**

In `modules/home/sync-hooks.nix`, mirroring the `mcpSync` entry (subshell, `entryAfter [ "writeBoundary" ]`, `|| true`):
```nix
opRender = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
  (
    set -u
    MANIFEST="$HOME/.config/op/render-manifest"
    RENDER="$HOME/.dotfiles/home/.local/bin/op-render"
    [ -f "$MANIFEST" ] || { echo "op-render: no manifest; skipping." >&2; exit 0; }
    OP_RENDER_MANIFEST="$MANIFEST" "$RENDER" || echo "op-render: warned (secrets left intact)." >&2
  ) || true
'';
```
(Add it to the `home.activation` attrset alongside the existing hooks. Ungated — m5 is the only current consumer; the manifest-absent guard makes it a no-op elsewhere.)

- [ ] **Step 2: Remove the common + personal age.secrets**

In `modules/home/secrets.nix`, delete the `"zsh-env"` block *(if Task 1 classified it non-secret; if it still holds a secret it stays templated, so still remove the age entry)*, the `identity != "work"` `ssh-config` block, and the `identity == "personal"` `zsh-personal-env` block. **Keep** `age.identityPaths` and the entire `identity == "work"` block untouched.

- [ ] **Step 3: gitignore the future Connect token + link manifest/templates**

Add to `.gitignore`: `.config/op/connect-token`. In `modules/home/dotfiles.nix`, add the manifest + templates (+ plain `.env` if applicable) to the appropriate `mkLinks` list so they land as out-of-store symlinks.

- [ ] **Step 4: Evaluate the flake**

Run: `nix flake check --no-build` (or `just check`) — sandbox disabled if Nix present.
Expected: green. (If Nix is not installed on m5 yet, note it and rely on CI `nix-flake-check.yml` after push — same posture as the lab-removal PR.)

- [ ] **Step 5: Commit**

```bash
git add modules/home/secrets.nix modules/home/sync-hooks.nix modules/home/dotfiles.nix .gitignore
git commit -m "feat: render m5 common/personal secrets via op-render; drop their agenix entries (WS1)"
```

---

## Task 5: End-to-end verification on m5 and doc update

**Files:**
- Modify: `secrets/README.md` (note the op-render path for common/personal on m5)
- Modify: `docs/superpowers/specs/2026-07-11-secrets-op-connect-design.md` (mark WS1/m5 milestone done; note desktop-app deviation)

**Interfaces:**
- Consumes: everything above.
- Produces: a verified m5 whose personal/common secrets come from `op`, not age.

- [ ] **Step 1: Switch and observe the render**

Run: `./rebuild.sh personal-mac` (or, if Nix not yet bootstrapped, run the activation entry's body directly). Watch for the `op-render` line; approve the biometric prompt if shown.
Expected: switch completes; no age decrypt for common/personal (only the work block, if present, still uses age).

- [ ] **Step 2: Assert rendered files are correct**

Run:
```bash
stat -f '%Lp' ~/.config/zsh/.personal.env ~/.ssh/config   # → 600 600
rg -c 'op://' ~/.config/zsh/.personal.env ~/.ssh/config    # → 0 0
exec zsh -ic 'echo ${OPENAI_API_KEY:+set} ${OPENROUTER_TOKEN:+set}'  # → set set (names, not values)
```
Expected: `0600` files, no `op://` residue, a fresh shell sources the vars.

- [ ] **Step 3: Confirm no age involvement for these three**

Run: `rg -n 'zsh-env|ssh-config|zsh-personal-env' modules/home/secrets.nix`
Expected: no matches (all three removed; work block intact).

- [ ] **Step 4: Update docs and open the PR**

Update `secrets/README.md` + the design-spec status line. Then:
```bash
git add secrets/README.md docs/superpowers/specs/2026-07-11-secrets-op-connect-design.md
git commit -m "docs: record WS1 m5 secrets on op-render (agenix retired for personal/common)"
git push -u origin HEAD   # sandbox disabled
gh pr create --base m5 --fill   # sandbox disabled
```
Expected: PR opens against `m5`; CI `nix-flake-check` + hygiene green.

---

## Self-Review

**Spec coverage:** §3 (templates + renderer) → Tasks 2–4. §4.4 fail-safe → Task 2 (preserved) + Task 3 Step 5 + Task 5. §4.5 nix activation trigger → Task 4 Step 1. §5 inventory + "known gap" enumeration → Task 1. §6 phase 3 (m5) → this whole plan (i9 phase 2 deferred to WS3; deviation: m5-first is fine because op-render is deploy-agnostic and m5 is in-hand). §8 testing (fail-safe, happy path, no-plaintext guard, idempotency) → Tasks 2, 3.5, 5.2. **Deferred by design:** §4.6 Connect token, §4.1 Connect server (WS3/SNUG-384); §6 phase 4 age retirement (WS4/SNUG-389); work secrets (WS2/SNUG-387).

**Placeholder scan:** Refs shown as illustrative (`op://Private/OpenAI/api_key`) are filled concretely from Task 1's enumeration — Task 1 is the explicit "author against the real list" step, not a placeholder. No "TBD"/"handle edge cases".

**Type consistency:** `op-render` env contract (`OP_BIN`, `OP_RENDER_MANIFEST`, `OP_CONNECT_*`, new `op account list` probe / `OP_MOCK_AUTH` mock) is consistent across Tasks 2, 3, 4. Manifest format (`template:target`, `~` expansion) matches op-render's existing parser (`sed 's/~/$HOME/'` at lines 35-36).
