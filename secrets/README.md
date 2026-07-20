# Secret management

Personal and work secrets intentionally use different custody paths.

## Personal: 1Password templates

`personal-mac` declares zero `age.secrets` and an empty `age.identityPaths` list. Personal values
are stored in the personal 1Password account and rendered by `home/.local/bin/op-render` from
public-safe templates:

```text
home/.config/zsh/.personal.env.tpl -> ~/.config/zsh/.personal.env
home/.ssh/config.tpl               -> ~/.ssh/config
```

`home/.config/op/render-manifest` is the authoritative template-to-target map.
`home/.config/op/adopt-policy.json` separately pins every allowed reference, variable, item,
field, and reverse-adoption permission. Home Manager links both only for
`identity == "personal"`; the personal-only `opRender` activation invokes the renderer after
`writeBoundary`.

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
5. Run `home/.local/bin/op-render` with an authenticated `op` session.
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
rendered-target ignore rules, pre-commit policy validation, gitleaks, review, and 1Password item
history provide layered protection without claiming that arbitrary strings can be proven
non-secret.

## Work: temporary agenix bridge

The remaining age ciphertext is work-only and is decrypted at Home Manager activation by agenix:

```text
secrets/work/zsh-work-env.age
  -> ~/.config/zsh/.work.env
secrets/work/aws-config-gen-overrides.json.age
  -> ~/.config/aws-config-gen/overrides.json
secrets/work/claude-skills/<skill>/**
  -> ~/.claude/skills/<skill>/**
```

The skills subtree contains 25 blobs across five work-only skills. Script targets are mode `0700`;
other work secret targets are mode `0600`. `modules/home/secrets.nix` declares them only for
`identity == "work"`, and work activation decrypts synchronously before dependent AWS/skills hooks.

`bootstrap.sh work-mac` obtains the temporary work age identity from
`op://Private/dotfiles-age-key/notesPlain` at `~/.config/age/keys.txt`. Personal bootstrap does not
fetch or require this key.

### Add or rotate a work-bridge secret

1. Add its path and recipient to `secrets/secrets.nix`.
2. Run `agenix -e <work/path.age>` from `secrets/`.
3. Declare or update its `age.secrets.<name>` entry in `modules/home/secrets.nix`.
4. Run the work configuration build/verification before switching.

Do not use `builtins.readFile` on decrypted data. Ciphertext may enter the public Nix store;
plaintext must not.

## Required end state

The age bridge is rollback material, not the final work-secret design. The external work wrapper
must move each work consumer to externally administered custody without using the personal age
recipient or a single employee's key. Retain the old ciphertext until the replacement consumer,
rollback, and one normal update cycle are verified; then delete the retired declarations, blobs,
recipient entries, and local work key.

Current bridge recipient (for `agenix -e` only):

```text
age1462h0ed4ufkjrq0wu326l30c8hay9uewlsaudk89mgqjc5540vrqacejsz
```
