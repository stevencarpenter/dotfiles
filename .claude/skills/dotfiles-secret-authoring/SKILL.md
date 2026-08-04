---
name: dotfiles-secret-authoring
description: Apply authoring-time secret judgment in this public Nix dotfiles repo. Use when adding, rotating, or documenting credentials, tokens, private keys, authenticated URLs, or op:// templates. Prefer anonymous access, never commit plaintext, render every secret from 1Password via op-render, and never reintroduce age ciphertext. Then run the repo secret scanners.
---

# Dotfiles secret authoring

This repository is public. A credential committed to history is effectively permanent.
Pre-commit scanning is the backstop; this workflow makes the design decision before a
secret reaches the working tree.

## Choose the storage path

- Prefer anonymous access whenever the service permits it.
- Every secret this repo owns uses an `op://` template under `home/` and is rendered by
  `home/.local/bin/op-render` to a mode-0600 target outside the repository. The manifest at
  `home/.config/op/render-manifest` is the authoritative template-to-target map.
- **There is no age path any more.** The former work bridge — the ciphertexts under
  `secrets/work/`, `secrets/secrets.nix`, and `modules/home/secrets.nix` — was removed, and
  no host declares `age.secrets` or an age identity. Do not reintroduce one:
  `scripts/test-nix-review-regressions.sh` and `scripts/test-external-overlay-contract.sh`
  both assert its absence. Secrets for an externally-owned host are that wrapper's custody.
- If some future secret genuinely cannot use 1Password, the hard requirements are:
  org-scoped recipients, teammate-decryptable, and never a personal recipient or any single
  person's key.
- Public configuration and identifiers stay plaintext. Do not add encryption friction to
  values that are not secrets.

## Verification

1. Confirm no age ciphertext has reappeared. The repo should track none, so this reports
   "No .age sources found" — anything else means a blob was added and must be justified
   against the rules above:

   ```bash
   bash .claude/skills/dotfiles-secret-authoring/scripts/verify_encrypted.sh
   ```

2. Sweep the entire repository for any literal value that was removed or migrated:

   ```bash
   bash .claude/skills/dotfiles-secret-authoring/scripts/sibling_sweep.sh '<exact value>'
   ```

3. Run `pre-commit run --all-files` before committing.

Never use `builtins.readFile` on a secret value: that would copy plaintext into the
world-readable Nix store.
