---
name: dotfiles-secret-authoring
description: Apply authoring-time secret JUDGMENT for this PUBLIC repo before committing — the judgment gitleaks (already in pre-commit) cannot make. USE THIS SKILL whenever you are about to write or commit a skill, doc, or config that references a credential, token, API key, basic-auth, or a URL with `-u user:pass` / an Authorization header; whenever you are deciding between the `private_` and `encrypted_` chezmoi prefix; whenever the user says "is this a secret", "should this be encrypted", "private_ vs encrypted_", "make this config encrypted", "no secrets even if trivial", "we have principals here", "can we do this without auth / anonymously", or "chezmoi detected a secrets leak"; or whenever you add a curl/http call that authenticates to even a trivial local service. Bias toward triggering on a PUBLIC repo where a leaked secret in git history is effectively permanent: prefer ANONYMOUS access over embedding any credential, route real secrets through chezmoi age encryption (verify `head -3` shows the AGE header), default sensitive files to `encrypted_` not `private_` (which commits PLAINTEXT source), and sweep EVERY sibling — code AND docs — for the same value so you never leave a second copy behind.
---

# Dotfiles secret authoring

Make the *authoring* call about secrets before they reach a commit on this **public** repo.
Detection is already handled by pre-commit; this skill owns the decisions detection can't:
prefer anonymous access, choose `encrypted_` over `private_`, and sweep every sibling copy.

## Why this skill exists

This repo is public, so a secret committed to history is effectively permanent. The
existing pre-commit stack (`gitleaks` v8.30.1 + `detect-private-key` + `detect-aws-credentials`)
catches many patterns, but it has structural blind spots and makes no design decisions. In
the session history, a hardcoded `admin:<redacted>` basic-auth credential was about to ship
inside a vendored skill; the agent removed it from the code but **left it in a doc line**,
and the human had to drive the sibling-sweep. Separately, an SSH config was tracked as
`private_` (plaintext source) when it should have been `encrypted_`. The standard the user
set is explicit: *"No secrets allowed, even if they are trivial. We have principals here!"*

> This skill does **not** re-implement secret scanning. Re-scanning would duplicate gitleaks
> and give false confidence. Detection is the backstop; this skill is the judgment in front
> of it.

## Decision 1 — prefer anonymous

Before embedding any credential, ask whether the operation works **unauthenticated**. The
Grafana `curl -s -u admin:<redacted> http://localhost:3030/...` became an anonymous call once it
was clear the local service allowed it. Embedding a credential is the last resort, not the
first.

## Decision 2 — `encrypted_` not `private_`

| Prefix | What it does | Use for |
|---|---|---|
| `private_` | sets `0600` on the **deployed target** only — the **source stays PLAINTEXT in git** | non-secret files that merely need tight perms on disk |
| `encrypted_` | age-encrypts the source at rest via `chezmoi add --encrypt` | anything sensitive on this public repo |

On a public repo, sensitive files use `encrypted_`. Encrypt and verify:

```bash
chezmoi add --encrypt ~/.config/zsh/.env        # or the relevant target
head -3 dot_config/zsh/encrypted_dot_env        # MUST show: -----BEGIN AGE ENCRYPTED FILE-----
bash .claude/skills/dotfiles-secret-authoring/scripts/verify_encrypted.sh   # assert ALL encrypted_* sources
```

## The sibling sweep (the step that was missed)

Removing a credential from the file you're editing is not enough — the same value often
lives in a doc, a README, or a second config. Sweep the **whole repo**, code and docs:

```bash
bash .claude/skills/dotfiles-secret-authoring/scripts/sibling_sweep.sh 'admin:<redacted>'
# rg -F over the entire tree (--hidden --no-ignore) — lists every file:line still holding it
```

Remove every occurrence before committing.

## When NOT to use this skill

- Non-secret config — a public URL, a port number, the existing non-sensitive
  `private_`-tracked files that contain no secret. Do not reflexively encrypt
  non-sensitive files; `encrypted_` adds friction (age round-trip on every edit).
- Verifying that an already-`encrypted_` file renders as ciphertext in the diff — that's
  [chezmoi-verify](../chezmoi-verify/SKILL.md)'s diff check.
- Bulk secret scanning of arbitrary content — that's the pre-commit gitleaks hook's job.

## Common failure modes

| Symptom | Cause | Action |
|---|---|---|
| credential removed from code but still in a doc | no sibling sweep | run `sibling_sweep.sh` over the whole repo |
| sensitive file tracked as `private_` | wrong prefix — source is plaintext in git | re-track with `chezmoi add --encrypt`; delete the plaintext source |
| `head -3` of an `encrypted_*` source shows plaintext | file was added without `--encrypt` | `chezmoi add --encrypt` the target; verify the AGE header |
| a work-only secret (e.g. `NODE_EXTRA_CA_CERTS` Zscaler cert) leaks onto personal | unscoped env file | gate it by machine — see [machine-capability-audit](../machine-capability-audit/SKILL.md) |

## Reference

- `scripts/sibling_sweep.sh` — whole-repo fixed-string sweep (code + docs + hidden).
- `scripts/verify_encrypted.sh` — assert every `encrypted_*` source begins with the AGE header.
- `.pre-commit-config.yaml` — the gitleaks/detect-private-key/detect-aws-credentials backstop this skill defers to.
- CLAUDE.md § *Encrypted Secrets* — the encrypt-and-verify procedure.
