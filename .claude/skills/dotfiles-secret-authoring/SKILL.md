---
name: dotfiles-secret-authoring
description: Apply authoring-time secret judgment in this public Nix dotfiles repo. Use when adding, rotating, or documenting credentials, tokens, private keys, authenticated URLs, op:// templates, or agenix ciphertext. Prefer anonymous access, never commit plaintext, use op-render for personal interactive secrets and agenix for work-only encrypted blobs, then run the repo secret scanners.
---

# Dotfiles secret authoring

This repository is public. A credential committed to history is effectively permanent.
Pre-commit scanning is the backstop; this workflow makes the design decision before a
secret reaches the working tree.

## Choose the storage path

- Prefer anonymous access whenever the service permits it.
- Personal interactive secrets use an `op://` template under `home/` and are rendered by
  `home/.local/bin/op-render` to a mode-0600 target outside the repository.
- Work-only secrets that must exist at activation use age ciphertext under `secrets/`,
  declared in `modules/home/secrets.nix`. Edit them with `agenix -e`; never decrypt them
  into the repository.
- Public configuration and identifiers stay plaintext. Do not add encryption friction to
  values that are not secrets.

## Verification

1. Confirm every `secrets/**/*.age` file starts with the AGE encrypted-file header:

   ```bash
   bash .claude/skills/dotfiles-secret-authoring/scripts/verify_encrypted.sh
   ```

2. Sweep the entire repository for any literal value that was removed or migrated:

   ```bash
   bash .claude/skills/dotfiles-secret-authoring/scripts/sibling_sweep.sh '<exact value>'
   ```

3. Run `pre-commit run --all-files` before committing.

Never use `builtins.readFile` on decrypted content: that would copy plaintext into the
world-readable Nix store.
