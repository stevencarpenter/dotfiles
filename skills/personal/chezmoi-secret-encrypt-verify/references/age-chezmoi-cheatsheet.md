# age + chezmoi secret cheatsheet

Grounded in this repo's actual config:

- `~/.config/chezmoi/key.txt` — age **identity** (private key, mode 0600). Decrypts.
- recipient `age1462h0ed4ufkjrq0wu326l30c8hay9uewlsaudk89mgqjc5540vrqacejsz` — **public**. Encrypts. Set in both `.chezmoi.toml.tmpl` `[age]` and `.chezmoiencrypt.toml` `[encryption]`.
- cipher `age` → encrypted sources get a **`.age` suffix** in addition to the `encrypted_` attribute prefix.

## The two markers chezmoi needs, and why both matter

An encrypted source file is identified by **both**:

1. **`encrypted_` attribute prefix** on the source filename. This tells chezmoi to run the configured cipher when reading the file. Without it, chezmoi treats the bytes as literal file content and writes them to the target verbatim — i.e. it ships your ciphertext as-is, or worse, ships plaintext you named `encrypted_` by hand without ever encrypting.
2. **`.age` suffix** (because cipher = age). chezmoi appends this automatically when it encrypts. It is part of the source name, not the target name.

Real examples from this repo:

| Source (in repo, committed)                                  | Target (deployed)              |
|--------------------------------------------------------------|--------------------------------|
| `dot_config/zsh/encrypted_dot_env.age`                       | `~/.config/zsh/.env`           |
| `dot_config/zsh/encrypted_dot_work.env.age`                  | `~/.config/zsh/.work.env`      |
| `dot_config/zsh/encrypted_dot_personal.env.age`              | `~/.config/zsh/.personal.env`  |
| `private_dot_ssh/encrypted_private_config.age`               | `~/.ssh/config`                |
| `dot_config/aws-config-gen/encrypted_overrides.json.age`     | `~/.config/aws-config-gen/overrides.json` |

Note how attribute prefixes stack and strip: `encrypted_dot_work.env.age` → `encrypted_` (cipher) + `dot_` (leading dot) → `.work.env`, and the `.age` is consumed by decryption. `encrypted_private_config.age` adds `private_` (0600 mode) too.

## The canonical add / rotate flow

**Add a brand-new secret file:**

```bash
# 1. Put the real plaintext at its destination (NOT in the repo).
$EDITOR ~/.config/zsh/.newsecret.env

# 2. Let chezmoi pull it in AND encrypt in one step. This is the only safe add.
chezmoi add --encrypt ~/.config/zsh/.newsecret.env

# 3. Confirm the source is ciphertext, then commit.
head -1 "$(chezmoi source-path ~/.config/zsh/.newsecret.env)"   # → -----BEGIN AGE ENCRYPTED FILE-----
```

**Edit / rotate an existing encrypted secret** — never hand-edit the `.age` file:

```bash
chezmoi edit ~/.config/zsh/.work.env          # opens DECRYPTED in $EDITOR, re-encrypts on save
# or, if rotating from a fresh plaintext copy at the target:
chezmoi add --encrypt ~/.config/zsh/.work.env # re-encrypts the new plaintext over the old source
```

**Register a new glob for auto-encrypt** (so future `chezmoi add` of matching paths encrypts automatically) — edit `.chezmoiencrypt.toml`. This repo already auto-encrypts `**/secret*`, `**/password*`, `**/*token*`, plus the explicit env globs. List the glob **without** the `.age` suffix; chezmoi adds it.

## Traps that recur (and the recovery)

### Trap 1 — `chezmoi add` without `--encrypt`
`chezmoi add ~/.config/zsh/.env` stores **plaintext** as `dot_config/zsh/dot_env` (no `encrypted_`, no `.age`). The secret is now plaintext in the working tree.
**Recover:** `chezmoi forget ~/.config/zsh/.env` (removes from source), then `chezmoi add --encrypt ~/.config/zsh/.env`. If you already committed, the plaintext is in history — see Trap 4.

### Trap 2 — "I encrypted the template but the .tmpl still has my actual values"
A `.tmpl` is rendered, **never decrypted**. Putting a literal secret inside a template means it sits in plaintext in the source tree and in git. The recipient/identity does nothing for it.
**Fix:** secrets do not belong inline in templates. Either (a) make the whole file an encrypted non-template (`encrypted_…age`) and stop templating it, or (b) keep the template but pull the secret at render time from an encrypted store, e.g. `{{ (joinPath .chezmoi.homeDir ".config/zsh/.env") | include }}` referencing a separately-encrypted file, or chezmoi's `{{ output ... }}` / a password-manager template function. The value itself must never be a literal in the `.tmpl`.

### Trap 3 — "cat shows dot_env is not encrypted at all"
If `head -1 <source>` prints your real values instead of `-----BEGIN AGE ENCRYPTED FILE-----`, the source was added without `--encrypt` (Trap 1) or the `encrypted_` prefix was stripped by a rename. The `.age` suffix without real ciphertext underneath is just as bad.
**Fix:** same as Trap 1 — `forget` then `add --encrypt`.

### Trap 4 — re-encrypting does NOT scrub history
Fixing a leaked plaintext at HEAD leaves the old plaintext blob recoverable via `git log -p` / `git show <oldsha>`. The verifier's pickaxe scan (`git log --all -S<secret>`) flags this.
**Recover:** the secret is **compromised — rotate it first** (issue a new token, change the password). Only then scrub history with `git filter-repo --replace-text` or BFG, and force-push. Rotation matters more than scrubbing; assume anything ever pushed is public.

### Trap 5 — wrong identity, silent empty render
If `~/.config/chezmoi/key.txt` is missing or is the wrong key, `chezmoi cat <target>` fails or renders empty. On `chezmoi apply` that can truncate the destination file. The verifier treats empty `chezmoi cat` output as a FAIL.

## Inspection commands (read-only)

```bash
chezmoi source-path ~/.config/zsh/.env          # target → source
chezmoi target-path dot_config/zsh/encrypted_dot_env.age   # source → target
chezmoi cat ~/.config/zsh/.env                  # the exact decrypted+rendered bytes chezmoi would deploy
chezmoi decrypt dot_config/zsh/encrypted_dot_env.age       # raw .age → plaintext (no templating)
chezmoi managed -i encrypted                    # list managed encrypted entries
```

Prefer `chezmoi cat <target>` as the ground truth for "what plaintext does this become" — it decrypts and runs templates, exactly like `apply` would.
