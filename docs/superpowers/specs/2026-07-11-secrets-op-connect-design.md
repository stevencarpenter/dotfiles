# Secrets → 1Password Connect (design)

**Date:** 2026-07-11 · **Status:** approved design, pre-implementation · **Branch:** `full-nix-darwin-dotfile-shape`

Sub-project 1 of 3 in the dotfiles restructure. Migrates the secret surface from agenix (age
ciphertext + a shared age key) to **1Password Connect** with `op inject` templates. Sub-projects 2
(i9 teardown → GNU stow) and 3 (bi-directional overlap sync) are **out of scope** here and get their
own specs; this design only assumes their existence where it must (the render trigger differs by
deploy mechanism, §4).

## 1. Context & problem

Today (`modules/home/secrets.nix`): agenix decrypts 30 `*.age` blobs at activation using a single
age identity at `~/.config/chezmoi/key.txt`, shared byte-for-byte across every machine. This works
but carries three costs the port itself flagged (`docs/nix-migration.md` §c/§d):

- **Ciphertext ships in the public repo** — 30 blobs under `secrets/`.
- **One shared age key** decrypts everything on every box, including the weakest-posture headless
  Intel homelab machine (i9). A single key compromise is total.
- **agenix is nix-only.** i9 is leaving the nix flake for GNU stow (Intel-darwin support ends at
  nixpkgs 26.05), so it needs a secret mechanism that is not tied to nix activation.

## 2. Goals & non-goals

**Goals**
- One secret mechanism that runs identically on nix (aarch64 dev laptops m5, work m3) and stow
  (x86 headless i9): `op inject` against Connect.
- Zero secret ciphertext in the repo — only templates with `op://` references.
- Per-machine, read-only, independently-revocable credentials scoped to one vault.
- Fail-safe on a headless box: a Connect/Tailscale outage at boot must never truncate a secret file.
- Retire agenix and the shared age key entirely once all machines are migrated.

**Non-goals**
- i9's stow teardown and the bi-directional config sync (separate sub-projects).
- Managing homelab *service* secrets (container env, etc.) — those belong to the homelab repo. This
  covers the interactive **shell/ssh** secret surface only.
- Runtime-only (no-plaintext-at-rest) secrets. i9's secrets are files tools read (sourced `.env`,
  `~/.ssh/config`), so `0600` plaintext-at-rest is retained — same posture as agenix today. The
  exposure win is removing repo ciphertext + the shared key, not eliminating on-disk plaintext.

## 3. Architecture

The repo stops shipping secrets. It ships **templates** (`op://Homelab/<item>/<field>` refs, safe to
commit publicly) plus a renderer. At boot, the renderer calls `op inject` against Connect and writes
the real `0600` files locally.

```
1Password Homelab vault ──(Connect REST API, over Tailscale)──> machine
   op://Homelab/<item>/<field>                                    │
                                                                  ▼
repo:  home/.config/zsh/env.tpl   ──op inject──> ~/.config/zsh/.env   (0600)
       home/.ssh/config.tpl       ──op inject──> ~/.ssh/config        (0600)
```

| Today (agenix) | After (Connect + op inject) |
|---|---|
| 30 `*.age` blobs in the public repo | `*.tpl` templates with `op://` refs — no secrets in repo |
| shared age identity on every box | one read-only, Homelab-scoped **Connect token** per box |
| `age.secrets.*` in `secrets.nix` | render script + launchd (stow) / activation (nix) trigger |

## 4. Components

### 4.1 Connect server (homelab)
A 1Password Connect container in the homelab, exposed on Tailscale, scoped to the **Homelab** vault.
Owned by the homelab repo. Provides the REST API `op` uses when `OP_CONNECT_HOST` + `OP_CONNECT_TOKEN`
are set. `OP_CONNECT_HOST` is a Tailscale address — not a secret, committed in plain config.

### 4.2 Vault: Homelab (canonical)
Single canonical vault. Existing secrets already largely live here; a one-time consolidation sweeps
stragglers out of the Private vault into Homelab so Connect can be scoped to exactly one vault.

### 4.3 Templates
Plain files committed to the repo, one per rendered secret file:
- `home/.config/zsh/env.tpl` → lines like `export OPENAI_API_KEY={{ op://Homelab/OpenAI/api_key }}`.
- `home/.ssh/config.tpl` → the ssh config with sensitive fields (hostnames/IPs) as `op://` refs.

Values are quoted in the template (`="{{ … }}"`) to survive whitespace; secrets containing a literal
double-quote are handled by preferring `op read` for that single field if it ever arises (none in the
current inventory).

### 4.4 Render script (fail-safe, shared by nix and stow)
One script, identical everywhere — the "central without gymnastics" lever:

1. Guard: `OP_CONNECT_HOST` and `OP_CONNECT_TOKEN` present, else warn-and-skip (never fail boot/switch).
2. For each template: `op inject -i <tpl> -o <tmpfile>`, where `<tmpfile>` is created in the **same
   directory** as the target (so the final step is a rename on one filesystem, not a cross-device copy).
3. **Atomic, fail-safe write:** validate `<tmpfile>` is non-empty and `op inject` exited 0, then
   `chmod 0600 <tmpfile> && mv -f <tmpfile> <target>` — a same-filesystem `rename(2)`, which is
   atomic: the target is either the old content or the fully-rendered new content, never a partial or
   empty file. On any failure (`op inject` nonzero, empty output) the tmpfile is discarded and the
   previous good target is left untouched.
4. Never renders in place — a naive `op inject -o ~/.ssh/config` would truncate the file to empty if
   Connect is unreachable at boot and lock out the headless box.

### 4.5 Trigger (differs by deploy mechanism only)
- **stow (i9):** a launchd user agent, `RunAtLoad = true`, plus a manual `op-render` / `just secrets`
  verb. Optionally re-triggered on network-up so a pre-Tailscale boot self-heals.
- **nix (m5, m3):** the same script wrapped in a `home.activation` entry (after `writeBoundary`),
  warn-not-fail, matching the existing sync-hook pattern.

### 4.6 Bootstrap token (the one root secret)
`OP_CONNECT_TOKEN` cannot come from `op://`. Provisioned once per machine, read-only and
Homelab-scoped, into `~/.config/op/connect-token` (`0600`, gitignored, never committed).
`OP_CONNECT_HOST` set in committed non-secret config. Rotating a machine means reissuing its token;
no other machine is affected.

## 5. Secret inventory

Current agenix surface (`modules/home/secrets.nix`):

| secret | hosts | rendered file |
|---|---|---|
| `zsh-env` | all | `~/.config/zsh/.env` |
| `ssh-config` | personal, lab (not work) | `~/.ssh/config` |
| `zsh-personal-env` | personal | `~/.config/zsh/.personal.env` |
| `zsh-work-env` | work | `~/.config/zsh/.work.env` |
| `aws-config-gen-overrides` | work | `~/.config/aws-config-gen/overrides.json` |
| 25× `claude-skill-*` | work (+ caps.skills) | `~/.claude/skills/<skill>/<relpath>` |

**Known gap (must resolve as plan step 1):** the nix port under-models i9's real secret surface. It
models only `zsh-env` (which on m5 contains a single non-secret flag, `ENABLE_TOOL_SEARCH`) +
`ssh-config` for the lab identity, yet the i9 command corpus proves it uses a dozen-plus shell secrets
(personal dev/API-token class: `CLAUDE_CODE_OAUTH_TOKEN`, `OPENAI_API_KEY`, `OPENROUTER_TOKEN`,
`CONTEXT7_API_KEY`, etc. — the same class as m5's personal-gated `.personal.env`, which lab gating
never deployed). The exact i9 list can only be enumerated **on i9** (names-only, values redacted).
That enumeration is the first implementation step; the vault mapping and `env.tpl` are authored
against it, not against the port's thin model.

## 6. Migration phasing (i9-first, no big-bang)

`op inject` and agenix coexist (different files), so this is secret-by-secret and reversible.

1. **Prep (homelab):** Connect up; Homelab vault confirmed; Private→Homelab consolidation; every
   needed item/field present.
2. **i9 pilot:** (a) enumerate i9's real secret env names on-box; (b) confirm matching Homelab
   items; (c) author `env.tpl` + `ssh-config.tpl`; (d) drop the Connect token + `OP_CONNECT_HOST`;
   (e) install the render launchd agent, verify boot render + fail-safe (including a
   Connect-unreachable boot); (f) cut i9's shell/ssh over to rendered files, remove its old
   age/chezmoi secret path.
3. **m5, then m3:** same templates (shared Homelab items), rendered via nix activation. Delete each
   `age.secrets.<name>` as its `op://` twin proves out.
4. **Retire agenix:** once all three render from `op://`, delete the agenix usage in `secrets.nix`,
   the 30 `*.age` blobs, `secrets/secrets.nix`, and the age-key bootstrap in `bootstrap.sh`. Repo
   ships zero ciphertext.

## 7. Security posture: before → after

- **Repo:** 30 committed ciphertext blobs → zero (templates only).
- **Key material on a box:** one shared age identity decrypting everything → one read-only,
  single-vault, per-machine Connect token. i9's token grants read on Homelab only and revokes
  independently.
- **At-rest:** unchanged — `0600` plaintext files after render (tools need files). Acceptable and
  explicitly a non-goal to change.
- **New dependency:** availability of the Connect container over Tailscale at render time. Mitigated
  by last-good-file persistence + warn-not-fail; a machine already provisioned keeps working through
  a Connect outage.

## 8. Testing & verification

- **Fail-safe:** with `OP_CONNECT_HOST` pointed at an unreachable address, run the render script and
  assert the existing `~/.ssh/config` and `~/.config/zsh/.env` are **unchanged** (not truncated).
- **Happy path:** render on i9, `diff` the produced `.env` var names against the enumerated inventory
  (names only); confirm a fresh shell sources them and `ssh` reads its config.
- **No-plaintext-in-repo guard:** gitleaks (already in pre-commit) + assert templates contain only
  `op://` refs, never literal secret values; `~/.config/op/connect-token` is gitignored.
- **Idempotency:** two consecutive renders produce identical files and exit 0.

## 9. Dependencies & open items

- Homelab must run Connect (homelab-repo work) before the i9 pilot.
- Exact i9 secret inventory (plan step 1) gates template authoring.
- Interaction with sub-project 3: the overlap sync must **exclude** rendered secret files
  (`.env`, `~/.ssh/config`); only `*.tpl` templates are ever shareable across machines.
