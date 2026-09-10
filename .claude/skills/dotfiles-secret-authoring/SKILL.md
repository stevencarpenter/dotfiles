---
name: dotfiles-secret-authoring
description: Apply authoring-time secret judgment in this public Nix dotfiles repo. Use when adding, rotating, or documenting credentials, tokens, private keys, authenticated URLs, or op:// templates. Prefer anonymous access, never commit plaintext, render every secret from 1Password via op-render, and never reintroduce age ciphertext. Then run the repo secret scanners.
---

# Dotfiles secret authoring

This repository is public. A credential committed to history is effectively permanent.
Git-hook scanning is the backstop; this workflow makes the design decision before a
secret reaches the working tree.

## Choose the storage path

- Prefer anonymous access whenever the service permits it.
- Every secret this repo owns uses an `op://` template under `home/` and is rendered by
  `home/.local/bin/op-render` to a mode-0600 target outside the repository. The manifest at
  `home/.config/op/render-manifest` is the authoritative template-to-target map.
- No host declares `age.secrets` or an age identity. Do not reintroduce one:
  `scripts/test-nix-review-regressions.sh` and `scripts/test-external-overlay-contract.sh`
  both assert its absence. Work-host secrets belong to the external host's flake.
- For reviewed edits to a rendered `.personal.env`, `just op-adopt` prints a
  names-only plan. Only the user runs `just op-adopt --apply`; never apply adoption
  on the user's behalf. The policy permits exact mappings only. Login items and
  SSH configuration remain manual or render-only.
- Public configuration and identifiers stay plaintext. Do not add encryption friction to
  values that are not secrets.

## Verification

1. Confirm the repository contains no `.age` files. This fails on any `.age` file,
   regardless of its header or whether Git tracks it:

   ```bash
   bash .claude/skills/dotfiles-secret-authoring/scripts/verify_encrypted.sh
   ```

2. Sweep the entire repository for any literal value that was removed or migrated:

   ```bash
   bash .claude/skills/dotfiles-secret-authoring/scripts/sibling_sweep.sh '<exact value>'
   ```

3. Run `just lefthook` (every pre-commit job against all files) before committing.

Never use `builtins.readFile` on a secret value: that would copy plaintext into the
world-readable Nix store.
