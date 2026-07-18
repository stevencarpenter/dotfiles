# secrets/

Age ciphertext for this repo, decrypted at `darwin-rebuild switch` / home-manager activation
time by [agenix](https://github.com/ryantm/agenix) (see `modules/home/secrets.nix`). Every
`.age` file here is byte-identical ciphertext carried over from the old chezmoi layout
(`dot_config/.../encrypted_*.age`, `dot_claude/skills/*/*.age`) — nothing was re-encrypted to
land here, and nothing in this directory should ever be decrypted or edited by hand.

## Layout

```
secrets/
  secrets.nix                          # agenix-CLI recipients file (agenix -e only, see below)
  common/
    zsh-env.age                        -> ~/.config/zsh/.env                (all hosts)
    ssh-config.age                     -> ~/.ssh/config                     (personal + lab, NOT work)
  personal/
    zsh-personal-env.age               -> ~/.config/zsh/.personal.env       (identity == personal)
  work/
    zsh-work-env.age                   -> ~/.config/zsh/.work.env           (identity == work)
    aws-config-gen-overrides.json.age  -> ~/.config/aws-config-gen/overrides.json  (identity == work)
    claude-skills/<skill>/**           -> ~/.claude/skills/<skill>/**        (identity == work AND caps.skills)
```

The `claude-skills/` subtree holds 25 blobs across 5 work-only Claude skills
(`databricks-tf-v1-v2-parity-mirror`, `kafka-connect-sink-log-triage`,
`schema-drift-config-reconciler`, `spark-job-failure-forensics`, `terraform-precommit-gauntlet`),
each with a `SKILL.md`, two `evals/*.json`, one `references/*.md`, and one executable
`scripts/*.{sh,py}`. The gating and per-file mode (`0700` for `scripts/`, `0600` everywhere
else) are declared explicitly in `modules/home/secrets.nix` — see that file's header comment
for why an explicit list was used instead of folding over `builtins.readDir`, and for the
agenix-vs-writeBoundary activation-ordering note that guarantees these land on disk before the
`skillsSync` activation script runs.

Which `age.secrets` entries actually get declared (and thus decrypted) on a given host is
driven entirely by `identity` and `caps.skills`, both threaded in via `specialArgs` from
`lib/machines.nix` — there is no per-host secrets file to edit; `hosts/*.nix` doesn't reference
`secrets/` directly.

## Bootstrap: getting the age identity in place

Every secret above decrypts against a single existing age identity — the same key used before
the Nix migration, now kept at `~/.config/age/keys.txt`. `age.identityPaths` in
`modules/home/secrets.nix` points straight at it. This is a chicken-and-egg root of trust: the
key itself is **not** stored in this repo (public repo — see `docs/superpowers/plans/
2026-07-02-work-decoupling-and-1password-secret-migration.md` for why), so it must be placed on
disk once, by hand, before the very first `darwin-rebuild switch` on a new machine:

```bash
mkdir -p ~/.config/age
op read "op://Private/dotfiles-age-key/notesPlain" > ~/.config/age/keys.txt
chmod 600 ~/.config/age/keys.txt

# only now is it safe to run the first activation:
darwin-rebuild switch --flake ~/.dotfiles#<host>
```

`bootstrap.sh` runs this step (see that script for the exact 1Password item reference). If the
key is missing or unreadable, every `age.secrets.*` decrypt fails during activation — check for
that first if a fresh machine's `darwin-rebuild switch` errors out on agenix.

## Adding or rotating a secret

1. Encrypt (or re-encrypt) the plaintext with the `agenix` CLI, which reads `secrets/secrets.nix`
   to know which recipient(s) to encrypt for:

   ```bash
   cd secrets
   agenix -e work/some-new-secret.age
   # opens $EDITOR on the decrypted plaintext; writes ciphertext back out on save
   ```

   For a brand-new secret, add its path to `secrets/secrets.nix` (`otherPaths` or
   `claudeSkillFiles`, as appropriate) **before** running `agenix -e`, so the CLI knows the
   recipient set to encrypt for.

2. Declare (or update) the corresponding `age.secrets.<name>` entry in
   `modules/home/secrets.nix` — `file` (ciphertext path, relative to `secrets/`), `path`
   (decrypted destination), `mode`, and whatever `identity`/`caps` gate it belongs under.

3. `chezmoi`-style diffing doesn't apply anymore — just `darwin-rebuild switch --flake
   ~/.dotfiles#<host>` (or `just rebuild`) and confirm the new/rotated file lands at its
   `path` with the right `mode`.

Rotating recipients (e.g. adding a second key, or dropping one) means re-running `agenix -e`
for every affected file after updating `secrets/secrets.nix`'s `publicKeys` list — agenix has no
bulk "rekey everything" command; `agenix -e` opens each file, decrypts with the currently-valid
identity, and re-encrypts for the recipients recorded in `secrets.nix` at that moment.

## What's deferred (not part of this port)

Two independent follow-ups were explicitly scoped OUT of the nix-darwin port and are left for
later, on-demand work. Neither blocks `darwin-rebuild switch` today.

1. **Optional: re-encrypt onto agenix-native recipients.** The blobs in this directory were
   produced by plain `age -e -r <recipient>` (via chezmoi), not by the `agenix` CLI. They
   decrypt identically either way — agenix doesn't care how ciphertext was produced, only that
   the identity in `age.identityPaths` can open it — so this step is pure hygiene, not a
   correctness requirement. It buys a working `agenix -e` edit loop without an external
   decrypt/re-encrypt round-trip:

   ```bash
   # conceptual — decrypt with the existing identity, then let agenix re-encrypt via -e
   for f in $(find secrets -name '*.age'); do
     age -d -i ~/.config/age/keys.txt "$f" > /tmp/plain
     agenix -e "$f" <<< "$(cat /tmp/plain)"   # or open $EDITOR and paste
     shred -u /tmp/plain
   done
   ```

   Until this runs, editing a secret still works fine via the `agenix -e` flow in the previous
   section — there is no gap in capability, only in workflow polish.

2. **Optional: migrate individual secrets to 1Password (`opnix` / `op://`), per the
   2026-07-02 plan.** See `docs/superpowers/plans/
   2026-07-02-work-decoupling-and-1password-secret-migration.md` (workstreams W3–W6) for the
   full design: replacing an `age.secrets.<name>` entry with an `op read op://Vault/item/field`
   activation step (or `opnix`), item-by-item, starting with a single low-risk personal secret
   to prove the pattern before touching the 5 work skills. This is the plan's actual
   blast-radius fix — a single long-lived age identity shared by all three machines (including
   the weaker-posture `lab-mac`) is a known, accepted limitation of the agenix bridge, not
   something this port attempts to solve. `agenix` and `op://`-sourced secrets can coexist
   during the migration; delete each `age.secrets` entry (and its `.age` blob) only once its
   `op://` replacement is proven working on the host(s) that need it.

Recipient key reference (documented here for `agenix -e`, see `secrets/secrets.nix`):

```
age1462h0ed4ufkjrq0wu326l30c8hay9uewlsaudk89mgqjc5540vrqacejsz
```
