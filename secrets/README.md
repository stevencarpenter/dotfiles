# Secret management

This directory holds documentation only. **No ciphertext is tracked in this repository**, and no
host declares `age.secrets` or an age identity — the agenix module is not imported at all. Every
secret this repo owns renders from 1Password. Secrets for an externally-owned host are that
wrapper's custody, administered by its own flake.

## 1Password templates

Values are stored in 1Password and rendered by `home/.local/bin/op-render` from public-safe
templates:

```text
home/.config/zsh/.personal.env.tpl -> ~/.config/zsh/.personal.env
home/.ssh/config.d/10-homelab.conf.tpl -> ~/.ssh/config.d/10-homelab.conf
```

`home/.config/op/render-manifest` is the authoritative template-to-target map.
`home/.config/op/adopt-policy.json` separately pins every allowed reference, variable, item,
field, and reverse-adoption permission. Home Manager links both only for
`identity == "personal"`; `just sync` invokes the renderer (via
`scripts/sync-side-channels.sh`, which signs in first when it has a TTY). The personal-only
`opRenderStaleCheck` activation entry only warns when the last render has gone stale — it never
renders, because activation can neither reach `op` nor authenticate.

The renderer:

- accepts an authenticated desktop-app CLI session or 1Password Connect credentials;
- renders to a same-directory temporary file;
- requires successful, nonempty output;
- sets mode `0600`;
- atomically replaces the target; and
- touches `~/.config/op/.last-render` only after every manifest entry succeeds.

On auth, injection, or empty-output failure it preserves the last known-good file. A skip is not
proof of freshness, so `scripts/verify-live-deployment.sh` also checks template/live variable-name
parity, the SSH include seam, and the render sentinel.

On each personal Mac, open and unlock 1Password, then enable **Settings > Developer > Integrate
with 1Password CLI**. Without app integration (or explicit Connect credentials), activation safely
keeps the last-good files but cannot refresh them.

### Add or rotate a personal secret

1. Add or update the field in the personal 1Password account.
2. For a new mapping, add its exact reference and item/field metadata to
   `home/.config/op/adopt-policy.json`.
3. Add only that exact reference to the appropriate `*.tpl` file under `home/`.
4. Add a manifest entry only when introducing a new template/target pair.
5. Run `just sync` (or `home/.local/bin/op-render` directly) from an interactive terminal with an
   authenticated `op` session. It cannot run from a `darwin-rebuild` activation hook — 1Password
   authorizes CLI access by calling-process ancestry, so only a terminal you have approved can
   render. Activation runs `op-render --warn-stale-only`, which nags but never renders.
6. Run the documented secret-policy, renderer, and live-deployment checks.

Never commit the rendered target, copy a literal value into a template, or use agenix for a new
personal secret.

### Adopt a reviewed live personal-env change

`op-adopt` provides a deliberately narrower reverse path for
`~/.config/zsh/.personal.env`. It does not behave like a general dotfile importer:

- the live target must be a current-user-owned regular file with mode `0600`;
- every non-comment line must be one already-approved exported variable;
- new, missing, duplicate, empty, or unresolved values are rejected;
- the tracked template must contain only exact policy-approved injection assignments;
- the tool never edits a template or creates/deletes a 1Password field;
- dry-run and apply output variable, item, and field names only; and
- sensitive update JSON is passed to `op item edit` over stdin, never command arguments.

Start with the names-only plan:

```bash
just op-adopt
```

After reviewing it, explicitly apply and type `personal-env` at the prompt:

```bash
just op-adopt --apply
```

The tool renders to a private temporary file after the edit and requires the updated vault to
reproduce every live value. It never overwrites the live source file. If multiple 1Password items
are involved, those external edits are not transactional; a late failure reports how many items
were already updated and leaves recovery to 1Password item history.

Login items are `manual-only`. The installed 1Password CLI warns that whole-item JSON edits can
overwrite passkeys, so changes to `NUGS_EMAIL` or `NUGS_PASSWORD` must be made in 1Password first;
rerun the dry-run afterward to prove parity. SSH config is render-only because it mixes static
configuration with an injected value and is not safe to reverse-import.

This is an accidental-leak and drift guard, not a hostile-maintainer boundary. A maintainer who
can change the template, policy, checker, and CI together can bypass it. Exact allowlisting,
rendered-target ignore rules, lefthook policy validation, gitleaks, review, and 1Password item
history provide layered protection without claiming that arbitrary strings can be proven
non-secret.

## No age secrets, ever

The former carry-verbatim age bridge for work secrets is **gone**. Removed in full: the 26
ciphertexts under `secrets/work/`, the `secrets/secrets.nix` recipient file,
`modules/home/secrets.nix`, the agenix flake input and module imports, and `bootstrap.sh`'s
age-identity fetch.

Do not add it back. Two tests enforce this:

- `scripts/test-nix-review-regressions.sh` — asserts `age.secrets` does not evaluate on any host.
- `scripts/test-external-overlay-contract.sh` — asserts a wrapper-built external work host
  declares zero `age.secrets` and no `age.identityPaths`.

If a future secret genuinely cannot use 1Password, the requirements are: org-scoped recipients,
teammate-decryptable, and **no reuse of a personal age recipient or any single person's key**.
Deleting a ciphertext from git does not remove it from history — rotate any credential that was
ever committed.

Never `builtins.readFile` a decrypted value. Ciphertext may enter the public Nix store; plaintext
must not.
