---
name: chezmoi-secret-encrypt-verify
description: Add or rotate a secret in the chezmoi dotfiles repo as an age-encrypted entry and PROVE the plaintext never reaches the working tree or git history. USE THIS SKILL whenever the user wants to encrypt a secret/token/password/API-key/env file with chezmoi, says "chezmoi add --encrypt", "encrypt this .env / .work.env", "rotate a secret in chezmoi", "is this actually encrypted", "did my real values leak", "the .tmpl still has my actual values", or wants a chezmoi secret confirmed plaintext-free before commit — including with neither "chezmoi" nor "age" named, e.g. "I put my API key in dot_config/zsh and want to commit it". A secret added without --encrypt, or baked into a .tmpl, is plaintext one push from public and chezmoi diff will NOT warn you, so bias toward triggering. Do NOT use for — dry-run/template preview with no secret (chezmoi-verify); decrypt-to-read a value (chezmoi cat); rotating cloud/IAM/SSO creds in iac terraform; or AI-spend, Spark/Databricks, or Jira tasks merely mentioning secrets.
---

# Chezmoi secret encrypt + verify

Walk the correct flow to add or rotate a secret in the chezmoi repo as an age-encrypted entry, then run a verifier that **proves** the plaintext never reaches the working tree or git history. The verifier refuses to pass — exit 1, loudly — on any leak.

This is complementary to the `chezmoi-verify` skill (which previews template renders and `apply` diffs). Use **this** skill when the operation is specifically about a secret: encrypting, rotating, or confirming no plaintext leak.

## Quick start

Prove an already-managed secret is encrypted end-to-end and leak-free:

```bash
"${CLAUDE_SKILL_DIR}/scripts/verify_encrypted.sh" ~/.config/zsh/.work.env
```

Accept either a deployed **target** path (`~/.config/zsh/.work.env`) or a **source** entry (`dot_config/zsh/encrypted_dot_work.env.age`); the script resolves one to the other. With no `--expect-value`, it auto-derives candidate secret literals from the decrypted plaintext — the RHS of shell `KEY=VALUE`/`export` lines — and hunts for those. Structured/opaque secrets (JSON, YAML, TOML, SSH-config) are **not** auto-derived: there's no reliable way to tell which quoted token is the secret, and harvesting every string cries wolf on dictionary words. When nothing is auto-derived, the leak scans have nothing to hunt for and the run reports **PARTIAL** (exit `3`), not a clean pass — pass `--expect-value`/`--expect-file` to prove leak-freedom. To assert a specific value or an exact plaintext file:

```bash
"${CLAUDE_SKILL_DIR}/scripts/verify_encrypted.sh" ~/.ssh/config --expect-value 'ghp_realtokenhere'
"${CLAUDE_SKILL_DIR}/scripts/verify_encrypted.sh" ~/.config/zsh/.env --expect-file /tmp/intended-plaintext.env
```

Exit `0` = encrypted **and** leak-scanned clean, safe to commit. Exit `1` = a leak or misconfiguration printed above — do NOT commit. Exit `2` = usage/environment error. Exit `3` = PARTIAL: encryption verified but no leak-scan ran (no secret values to search for) — re-run with `--expect-value`/`--expect-file` to prove leak-freedom.

## What it does

`scripts/verify_encrypted.sh` runs six read-only checks and fails the whole run if any fail:

1. **Source name** carries the `encrypted_` attribute prefix AND the `.age` suffix (both required for cipher=age — see why in the cheatsheet).
2. **Source bytes** actually begin with an age header (`-----BEGIN AGE ENCRYPTED FILE-----` or the binary `age-` magic) — not plaintext someone named `encrypted_` by hand.
3. **Round-trip**: `chezmoi cat <target>` decrypts + renders to non-empty output; against `--expect-file` it must match byte-for-byte.
4. **Working-tree leak scan**: no secret literal appears anywhere in the source repo. The scan uses `rg --no-ignore --hidden` on purpose — a secret dropped into a `.gitignore`'d path is still plaintext on disk and one `git add -f` from a leak.
5. **History leak scan**: `git log --all -S<secret>` (the pickaxe) finds any commit that ever added the literal — catching the "committed plaintext, then re-added with --encrypt" trap where HEAD looks clean but the blob is still recoverable.
6. **Template scan**: no `*.tmpl` in the repo contains a literal secret value — the single most common trap (a templated file is rendered, never decrypted, so an inline secret sits in plaintext in git).

The script never writes to the repo, never stages, never commits. Decrypted plaintext lives only in a `0600` tempfile that is shredded on exit, and all reporting masks secret values to a prefix + length.

## The add / rotate procedure

Do this **before** running the verifier. The verifier proves the result; it does not perform the encryption.

### Adding a new secret

1. Write the real plaintext at its **destination**, never in the repo: `$EDITOR ~/.config/zsh/.newsecret.env`.
2. Pull it in and encrypt in one step — this is the only safe add: `chezmoi add --encrypt ~/.config/zsh/.newsecret.env`. chezmoi creates the source as `encrypted_…name….age` using the recipient from `.chezmoi.toml.tmpl`.
3. Verify, then commit:
   ```bash
   "${CLAUDE_SKILL_DIR}/scripts/verify_encrypted.sh" ~/.config/zsh/.newsecret.env
   ```

### Rotating / editing an existing secret

Never hand-edit the `.age` file. Either:

- `chezmoi edit ~/.config/zsh/.work.env` — opens the **decrypted** content in `$EDITOR`, re-encrypts on save; or
- re-stage a fresh plaintext copy at the target: `chezmoi add --encrypt ~/.config/zsh/.work.env`.

Then re-run the verifier. If you rotated because the **old** value leaked, that old value is compromised — issue a new credential; do not assume scrubbing history is enough.

## Why this skill exists

`chezmoi diff` does not warn when a secret is plaintext. Three failure modes recur in this repo's history of secret work:

- `chezmoi add` **without** `--encrypt` → plaintext source committed.
- a real secret **baked into a `.tmpl`** → plaintext in git, because templates are rendered, not decrypted.
- re-encrypting at HEAD after a plaintext commit → HEAD is clean but `git log -p` still reveals the secret.

Each one looks fine to the eye and to `chezmoi diff`. The verifier mechanically rules all three out, and on a leak it tells you the file/commit and that the secret must be rotated.

## Reference

Read `references/age-chezmoi-cheatsheet.md` for: the `encrypted_` + `.age` naming rules with the real source→target table for this repo, the `add --encrypt` vs `edit` vs `.chezmoiencrypt.toml` glob distinctions, the five recurring traps with exact recovery commands, and the read-only inspection commands (`chezmoi source-path` / `target-path` / `cat` / `decrypt` / `managed -i encrypted`).

This repo's encryption facts (from `.chezmoi.toml.tmpl` and `.chezmoiencrypt.toml`):

- cipher = `age`; identity = `~/.config/chezmoi/key.txt`; recipient `age1462h0…acejsz`.
- auto-encrypt globs already registered: `**/secret*`, `**/password*`, `**/*token*`, plus the explicit zsh env files and `.envrc`. A `chezmoi add` of a path matching one of these encrypts automatically — but **still run the verifier**; a matching glob does not prove the on-disk bytes are ciphertext.
