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

`home/.config/op/render-manifest` is the authoritative template-to-target map. Home Manager links
that manifest only for `identity == "personal"`; the personal-only `opRender` activation invokes
the renderer after `writeBoundary`.

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
2. Add only its `op://` reference to the appropriate `*.tpl` file under `home/`.
3. Add a manifest entry only when introducing a new template/target pair.
4. Run `home/.local/bin/op-render` with an authenticated `op` session.
5. Run `scripts/verify-live-deployment.sh` and `scripts/test-op-render.sh`.

Never commit the rendered target, copy a literal value into a template, or use agenix for a new
personal secret.

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
