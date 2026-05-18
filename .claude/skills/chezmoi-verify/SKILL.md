---
name: chezmoi-verify
description: Verify chezmoi state before applying. USE THIS SKILL whenever the user says "preview chezmoi changes", "test the templates", "verify apply", "what would chezmoi apply do", "chezmoi diff", "dry-run chezmoi", "render the templates", "check the .tmpl files", "did I break any templates", "is my chezmoi config valid", "before I run chezmoi apply", "apply safely", or any phrasing where the user wants to inspect what `chezmoi apply` will change without committing the change. Bias toward triggering: a broken `*.tmpl` file renders as empty output and shows up in `chezmoi diff` as a silent file deletion that is easy to miss — running every template through `execute-template` first is the only reliable surface for syntax errors. The cost of an unnecessary trigger is one extra CI-style report; the cost of missing a template error is a corrupted dotfile on apply.
---

# Chezmoi verify

Run a structured verification of pending chezmoi changes before `chezmoi apply` so template syntax errors and unintended diffs surface as report rows, not as silently-empty files in the destination tree.

## Why this skill exists

`chezmoi diff` does not flag a `*.tmpl` parse error. A template that fails to render emits an empty string, and the diff displays that as a deletion of the destination file (or a silent no-op if the destination is also missing). The fix is to call `chezmoi execute-template --file <path>` per template first, capture stderr, and only then run the diff.

## Workflow

### 1. Confirm the active machine

```bash
chezmoi data | jq -r '.chezmoi.config.data.machine // .machine'
```

The same source tree renders differently for `personal-mac`, `work-mac`, and `lab-mac` (see `.chezmoidata/machines.toml` for the capability matrix). All template checks below use the active machine's data.

### 2. Render every `*.tmpl` and surface errors

```bash
cd "$(chezmoi source-path)"
errlog="${TMPDIR:-/tmp}/chezmoi-verify.err"
fail=0
while IFS= read -r tmpl; do
  if ! chezmoi execute-template --file "$tmpl" >/dev/null 2> "$errlog"; then
    printf 'FAIL %s\n' "$tmpl"
    sed 's/^/    /' "$errlog"
    fail=1
  fi
done < <(find . -name '*.tmpl' -type f -not -path './.git/*' -not -name '.chezmoi.toml.tmpl')
exit "$fail"
```

Fails fast on the first template error rather than letting `chezmoi apply` silently truncate the destination file. Run this *before* anything else.

**Why `.chezmoi.toml.tmpl` is excluded**: it uses `chezmoi init`-only template functions like `promptStringOnce` that aren't available outside the init context. `chezmoi execute-template --init < .chezmoi.toml.tmpl` is the right call to test it specifically; the bulk walk skips it.

A passing run prints nothing; a failing run prints `FAIL <path>` followed by the indented stderr from chezmoi (line/column of the parse error, undefined variable name, etc.).

### 3. Preview the diff

```bash
chezmoi diff
```

Read the diff section by section. Look for:

- **Empty replacements** — a file shown as fully removed that you didn't mean to remove usually means a template gate (`{{ if ... }}`) flipped, or a `.chezmoiignore` entry started matching it.
- **Unexpected mode changes** — `executable_` prefix added or dropped.
- **Encrypted file diffs** — `encrypted_` files should NEVER show plaintext in `chezmoi diff`. If you see plaintext secrets in a diff, stop and check `~/.config/chezmoi/key.txt` and the file's `encrypted_` prefix before proceeding.

### 4. Optional: dry-run apply

```bash
chezmoi apply --dry-run --verbose
```

Use this when the diff is clean but you still want to walk through the post-apply hooks (`.chezmoiscripts/run_after_*`) without executing them. `--dry-run` skips the script bodies but still prints which scripts *would* run.

### 5. Apply

```bash
chezmoi apply -v
```

Only after steps 2–4 are clean. The post-apply hooks (MCP sync, AWS config gen) are not idempotent in the strict sense — they overwrite their generated outputs — so re-running after a verified-clean state is safe.

## When NOT to use this skill

- One-off `chezmoi add` calls that don't touch templates — `chezmoi diff` alone is sufficient.
- Reading a single tmpl by hand to understand the rendered output — a single `chezmoi execute-template --file <path>` is faster than the whole walk.
- After-the-fact debugging of an apply that already happened — use `chezmoi managed -v` and inspect destination files directly.

## Common failure modes the walk catches

- **Undefined `.machines.<name>` row** — a new machine type was added to `.chezmoi.toml.tmpl`'s prompt but missing from `.chezmoidata/machines.toml`. `(index .machines .machine).<cap>` returns `<no value>`, which most call sites silently treat as falsy. The execute-template walk surfaces it as an explicit error only when the template uses strict accessors; most uses pass through silently. Mitigation: when adding a machine, grep for `(index .machines` and audit each callsite.
- **Renamed capability key** — adding a new capability column to `machines.toml` but forgetting one of the existing rows. Templates that gate on the missing key silently render the gated branch as off. The walk does not catch this; it has to be caught at gate-site review time.
- **Stray `{{` in a non-template file** — a file without `.tmpl` suffix containing `{{` is fine; chezmoi only treats `.tmpl`-suffixed sources as templates. If you see a syntax error on a non-`.tmpl` file, you've miscategorised it — rename it to add `.tmpl`.
- **Encrypted file accidentally committed unencrypted** — `head -3 dot_config/zsh/encrypted_dot_env` should print `-----BEGIN AGE ENCRYPTED FILE-----`. If it prints plaintext, run `chezmoi add --encrypt ~/.config/zsh/.env` to re-encrypt before committing.

## Reference

- `chezmoi execute-template --help` — full flag list, including `--init` for testing `.chezmoi.toml.tmpl` itself.
- `chezmoi diff --help` — `--include` / `--exclude` filters for narrowing the diff to a single subtree (e.g. `--include=files`).
- `.chezmoidata/machines.toml` — capability matrix; gate sites read `(index .machines .machine).<cap>`.
- `CLAUDE.md` § *Machine-Type Gating* — explains the capability vs. prefix gate styles.
