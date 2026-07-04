#!/usr/bin/env bash
# verify_encrypted.sh — prove a chezmoi secret is age-encrypted end-to-end and
# that its plaintext never reaches the working tree or git history.
#
# Usage:
#   verify_encrypted.sh <target-or-source> [--expect-file PLAINTEXT_FILE]
#                                          [--expect-value 'literal value']
#
#   <target-or-source>  Either a deployed target path (e.g. ~/.config/zsh/.env)
#                       OR a source entry under the chezmoi repo
#                       (e.g. dot_config/zsh/encrypted_dot_env.age or its
#                       absolute path). The script resolves one to the other
#                       via `chezmoi source-path` / `chezmoi target-path`.
#
#   --expect-file F     File containing the exact plaintext the entry should
#                       decrypt to. The script asserts the round-trip matches.
#   --expect-value V    One or more secret literals that MUST NOT appear in the
#                       working tree or git history. Repeatable. If omitted, the
#                       script derives candidate secret values from the decrypted
#                       plaintext (RHS of KEY=VALUE lines) and scans for those.
#
# Exit codes:
#   0  every check passed — safe to commit
#   1  a check FAILED — a leak or a misconfiguration; DO NOT commit
#   2  usage / environment error (missing chezmoi, age key, etc.)
#   3  encryption verified, but NO leak-scan ran (no secret values to search
#      for) — pass --expect-value/--expect-file to prove the entry is leak-free
#
# This script is read-only. It never writes to the repo, never stages, never
# commits. Decrypted plaintext is held in a 0600 tempfile under $TMPDIR and
# shredded on exit.

set -euo pipefail

# ---- config / dependencies ------------------------------------------------

die()  { printf 'ERROR: %s\n' "$*" >&2; exit 2; }
fail() { printf 'FAIL  %s\n' "$*" >&2; FAILED=1; }
ok()   { printf 'ok    %s\n' "$*"; }
info() { printf '      %s\n' "$*"; }

usage() {
  cat <<'USAGE'
verify_encrypted.sh — prove a chezmoi secret is age-encrypted end-to-end and
that its plaintext never reaches the working tree or git history.

Usage:
  verify_encrypted.sh <target-or-source> [--expect-file PLAINTEXT_FILE]
                                         [--expect-value 'literal value']

  <target-or-source>  Either a deployed target path (e.g. ~/.config/zsh/.env)
                      OR a source entry under the chezmoi repo
                      (e.g. dot_config/zsh/encrypted_dot_env.age or its
                      absolute path). The script resolves one to the other
                      via `chezmoi source-path` / `chezmoi target-path`.

  --expect-file F     File containing the exact plaintext the entry should
                      decrypt to. The script asserts the round-trip matches.
  --expect-value V    One or more secret literals that MUST NOT appear in the
                      working tree or git history. Repeatable. If omitted, the
                      script derives candidate secret values from the decrypted
                      plaintext (RHS of KEY=VALUE lines) and scans for those.

Exit codes:
  0  every check passed — safe to commit
  1  a check FAILED — a leak or a misconfiguration; DO NOT commit
  2  usage / environment error (missing chezmoi, age key, etc.)
  3  encryption verified, but NO leak-scan ran — pass --expect-value or
     --expect-file to prove the entry is leak-free

This script is read-only. It never writes to the repo, never stages, never
commits. Decrypted plaintext is held in a 0600 tempfile under $TMPDIR and
shredded on exit.
USAGE
}

command -v chezmoi >/dev/null 2>&1 || die "chezmoi not on PATH"
command -v git     >/dev/null 2>&1 || die "git not on PATH"

FAILED=0
EXPECT_FILE=""
declare -a EXPECT_VALUES=()
ENTRY=""

while [ $# -gt 0 ]; do
  case "$1" in
    --expect-file)  [ $# -ge 2 ] || die "--expect-file needs a path"; EXPECT_FILE="$2"; shift 2 ;;
    --expect-value) [ $# -ge 2 ] || die "--expect-value needs a value"; EXPECT_VALUES+=("$2"); shift 2 ;;
    -h|--help)
      usage; exit 0 ;;
    -*) die "unknown flag: $1" ;;
    *)  [ -z "$ENTRY" ] || die "only one target/source may be given"; ENTRY="$1"; shift ;;
  esac
done

[ -n "$ENTRY" ] || die "no target/source given (see --help)"

REPO="$(chezmoi source-path 2>/dev/null)" || die "cannot resolve chezmoi source dir"
[ -d "$REPO/.git" ] || info "note: $REPO is not a git repo root; history scan will be skipped"

# ---- tempfile for decrypted plaintext (0600, shredded on exit) ------------

PLAIN="$(mktemp "${TMPDIR:-/tmp}/cz-verify.XXXXXX")" || die "mktemp failed"
chmod 600 "$PLAIN"
# shellcheck disable=SC2329  # invoked indirectly via the EXIT/INT/TERM trap below
cleanup() {
  if [ -f "$PLAIN" ]; then
    # overwrite then remove; `shred` is GNU-only, fall back to dd+rm sized to
    # the actual file (a fixed small block count would leave the tail of a
    # large plaintext secret un-wiped)
    if command -v shred >/dev/null 2>&1; then shred -u "$PLAIN" 2>/dev/null || rm -f "$PLAIN"
    else
      plain_size="$(wc -c < "$PLAIN" 2>/dev/null || echo 0)"
      dd if=/dev/zero of="$PLAIN" bs=1 count="$plain_size" conv=notrunc 2>/dev/null || true
      rm -f "$PLAIN"
    fi
  fi
}
trap cleanup EXIT INT TERM

# ---- resolve target <-> source -------------------------------------------
# Normalise to: TARGET (absolute deployed path) and SRC (absolute source path).

abs() { case "$1" in /*) printf '%s\n' "$1";; ~*) printf '%s\n' "${1/#\~/$HOME}";; *) printf '%s\n' "$PWD/$1";; esac; }

TARGET="" ; SRC=""
ENTRY_ABS="$(abs "$ENTRY")"

# Literal prefix test (no regex): is ENTRY_ABS under the chezmoi source repo?
case "$ENTRY_ABS" in "$REPO"/*) ENTRY_UNDER_REPO=1 ;; *) ENTRY_UNDER_REPO=0 ;; esac

if [ "$ENTRY_UNDER_REPO" -eq 1 ]; then
  # Looks like a source path.
  SRC="$ENTRY_ABS"
  TARGET="$(chezmoi target-path "$SRC" 2>/dev/null)" || die "chezmoi target-path failed for $SRC"
elif [ -e "$REPO/$ENTRY" ]; then
  # Repo-relative source entry.
  SRC="$REPO/$ENTRY"
  TARGET="$(chezmoi target-path "$SRC" 2>/dev/null)" || die "chezmoi target-path failed for $SRC"
else
  # Treat as a deployed target path.
  TARGET="$ENTRY_ABS"
  SRC="$(chezmoi source-path "$TARGET" 2>/dev/null)" || die \
    "chezmoi source-path failed for $TARGET — is it managed by chezmoi?"
fi

info "target: $TARGET"
info "source: $SRC"
printf '\n'

SRC_BASE="$(basename "$SRC")"

# ===========================================================================
# CHECK 1 — source entry is declared encrypted
#   chezmoi marks an encrypted source two ways, and BOTH must hold:
#     (a) the source filename carries the `encrypted_` attribute prefix
#     (b) with cipher=age the source filename ends in `.age`
#   (See references/age-chezmoi-cheatsheet.md.)
# ===========================================================================

if printf '%s' "$SRC_BASE" | grep -q '^encrypted_' ; then
  ok "source name has 'encrypted_' attribute prefix"
else
  fail "source name '$SRC_BASE' is MISSING the 'encrypted_' prefix — chezmoi will store it in PLAINTEXT"
fi

case "$SRC_BASE" in
  *.age) ok "source name has '.age' suffix (cipher=age)";;
  *)     fail "source name '$SRC_BASE' is MISSING the '.age' suffix expected for cipher=age";;
esac

# ===========================================================================
# CHECK 2 — the on-disk source bytes are actually an age ciphertext, not
#   plaintext that someone named encrypted_ by hand.
# ===========================================================================

if [ -f "$SRC" ]; then
  if head -c 64 "$SRC" | grep -q 'BEGIN AGE ENCRYPTED FILE'; then
    ok "source bytes begin with an age armored header"
  elif head -c 4 "$SRC" | grep -q 'age-'; then
    ok "source bytes begin with an age binary header"
  else
    # Do NOT echo the raw plaintext — this is exactly the secret we are trying
    # to protect. Report only the byte count and a redacted first-line preview.
    fail "source bytes do NOT look like age ciphertext (likely plaintext); $(wc -c < "$SRC" | tr -d ' ') bytes total"
    info "redacted first-line preview: $(head -1 "$SRC" | sed 's/./*/g')"
  fi
else
  fail "source file does not exist on disk: $SRC"
fi

# ===========================================================================
# CHECK 3 — decrypt round-trips. `chezmoi cat <target>` renders the exact
#   bytes chezmoi WOULD deploy (decrypting + running any template). That is the
#   ground truth for "what plaintext does this become".
# ===========================================================================

if chezmoi cat "$TARGET" > "$PLAIN" 2>/dev/null; then
  if [ -s "$PLAIN" ]; then
    ok "chezmoi cat decrypted/rendered the entry ($(wc -c < "$PLAIN" | tr -d ' ') bytes)"
  else
    fail "chezmoi cat produced EMPTY output — decryption or template render failed silently"
  fi
else
  fail "chezmoi cat failed — wrong age identity (~/.config/chezmoi/key.txt) or corrupt ciphertext"
fi

# Round-trip against an expected plaintext file, if given.
if [ -n "$EXPECT_FILE" ]; then
  EXPECT_FILE_ABS="$(abs "$EXPECT_FILE")"
  [ -f "$EXPECT_FILE_ABS" ] || die "--expect-file not found: $EXPECT_FILE_ABS"
  if cmp -s "$PLAIN" "$EXPECT_FILE_ABS"; then
    ok "decrypted plaintext matches --expect-file exactly"
  else
    fail "decrypted plaintext does NOT match --expect-file ($EXPECT_FILE_ABS)"
    info "diff (expected vs decrypted), secrets masked to length only:"
    diff <(sed 's/./*/g' "$EXPECT_FILE_ABS") <(sed 's/./*/g' "$PLAIN") | sed 's/^/        /' >&2 || true
  fi
fi

# ===========================================================================
# Derive the secret literals to hunt for.
#   Prefer explicit --expect-value/--expect-file. Otherwise extract candidate
#   values from the decrypted plaintext: the RHS of shell KEY=VALUE / export
#   lines (env files, .envrc), keeping only values >= 6 chars so we don't flag
#   trivially-common substrings.
#
#   We deliberately do NOT auto-derive needles from structured secrets
#   (JSON / YAML / TOML / SSH-config). There is no reliable way to tell which
#   quoted token is "the secret", and harvesting every quoted string pulls in
#   dictionary words (e.g. "service", "security") that false-match unrelated
#   files and cry wolf on a correctly-encrypted entry. For those secrets
#   EXPECT_VALUES stays empty, the leak scans are skipped, and the verdict is
#   PARTIAL (exit 3) — re-run with --expect-value/--expect-file to scan a
#   specific literal.
# ===========================================================================

if [ "${#EXPECT_VALUES[@]}" -eq 0 ] && [ -s "$PLAIN" ]; then
  # RHS of shell KEY=VALUE / export lines.
  while IFS= read -r v; do
    [ "${#v}" -ge 6 ] && EXPECT_VALUES+=("$v")
  done < <(
    grep -aE '^[[:space:]]*(export[[:space:]]+)?[A-Za-z_][A-Za-z0-9_]*=' "$PLAIN" \
      | sed -E 's/^[[:space:]]*(export[[:space:]]+)?[A-Za-z_][A-Za-z0-9_]*=//' \
      | sed -E "s/^[\"']//; s/[\"'][[:space:]]*$//" \
      | sort -u
  )

  if [ "${#EXPECT_VALUES[@]}" -gt 0 ]; then
    info "derived ${#EXPECT_VALUES[@]} candidate secret value(s) from KEY=VALUE lines to leak-scan"
  else
    info "no KEY=VALUE secrets auto-derived (structured/opaque secret?); pass --expect-value or --expect-file to leak-scan a specific literal"
  fi
fi

# Track whether the leak scans (checks 4/5/6) actually have something to hunt
# for. With zero secret literals, those checks short-circuit and prove NOTHING
# about leaks — so the final verdict must NOT claim "no plaintext leak".
LEAK_SCAN_RAN=0
[ "${#EXPECT_VALUES[@]}" -gt 0 ] && LEAK_SCAN_RAN=1

# ===========================================================================
# CHECK 4 — no plaintext secret appears anywhere in the WORKING TREE except the
#   decrypted runtime target itself. We scan the chezmoi source repo, since that
#   is what gets committed. The .age source is ciphertext, so a match there is a
#   real leak (a stray plaintext copy).
# ===========================================================================

scan_tree() {
  local needle="$1" hits
  # CRITICAL: must scan ignored AND hidden files. A secret carelessly dropped
  # into a .gitignore'd path is still plaintext on disk and one `git add -f`
  # away from a leak — so DO NOT let the scanner honour .gitignore.
  if command -v rg >/dev/null 2>&1; then
    hits="$(rg -n --no-heading --no-ignore --hidden --fixed-strings -- "$needle" "$REPO" 2>/dev/null \
            | grep -v "/\.git/" || true)"
  else
    hits="$(grep -rnaF -- "$needle" "$REPO" 2>/dev/null \
            | grep -v "/\.git/" || true)"
  fi
  printf '%s' "$hits"
}

if [ "${#EXPECT_VALUES[@]}" -gt 0 ]; then
  for secret in "${EXPECT_VALUES[@]+"${EXPECT_VALUES[@]}"}"; do
    masked="${secret:0:2}…(${#secret} chars)"
    hits="$(scan_tree "$secret")"
    if [ -z "$hits" ]; then
      ok "working tree clean of secret [$masked]"
    else
      fail "secret [$masked] found in PLAINTEXT in the working tree:"
      # Redact the literal secret value out of each matched line before
      # printing — otherwise a FAIL echoes the very value this tool exists
      # to keep out of terminal scrollback / CI logs.
      printf '%s\n' "${hits//$secret/[REDACTED]}" | sed 's/^/        /' >&2
    fi
  done
else
  info "skipping working-tree leak scan (no secret values to search for)"
fi

# ===========================================================================
# CHECK 5 — no plaintext secret in git history. `git log -p -S<secret>` (the
#   pickaxe) finds any commit that added or removed the literal. This catches
#   the classic "committed plaintext, then re-added with --encrypt" mistake —
#   the secret is gone from HEAD but still recoverable from history.
# ===========================================================================

if [ -d "$REPO/.git" ] && [ "${#EXPECT_VALUES[@]}" -gt 0 ]; then
  for secret in "${EXPECT_VALUES[@]+"${EXPECT_VALUES[@]}"}"; do
    masked="${secret:0:2}…(${#secret} chars)"
    # -S<string> = pickaxe on literal; --all = every ref, not just HEAD's branch.
    histhits="$(git -C "$REPO" log --all --oneline -S"$secret" 2>/dev/null || true)"
    if [ -z "$histhits" ]; then
      ok "git history clean of secret [$masked]"
    else
      fail "secret [$masked] appears in git HISTORY (recoverable via git log):"
      printf '%s\n' "$histhits" | sed 's/^/        /' >&2
      info "remediate: the secret is compromised. ROTATE it, then scrub history"
      info "(git filter-repo / BFG) — re-encrypting HEAD does NOT remove old blobs."
    fi
  done
elif [ ! -d "$REPO/.git" ]; then
  info "no .git in $REPO — skipping history scan"
fi

# ===========================================================================
# CHECK 6 — templates carry no literal secret values. A `.tmpl` that bakes a
#   real secret into the source is the single most common trap (the file is
#   tracked unencrypted; the secret is in plaintext on disk and in git). For
#   each template in the repo, scan it for any of the secret literals.
# ===========================================================================

if [ "${#EXPECT_VALUES[@]}" -gt 0 ]; then
  tmpl_leak=0
  while IFS= read -r tmpl; do
    for secret in "${EXPECT_VALUES[@]+"${EXPECT_VALUES[@]}"}"; do
      if grep -qaF -- "$secret" "$tmpl" 2>/dev/null; then
        masked="${secret:0:2}…(${#secret} chars)"
        fail "template '$tmpl' contains a LITERAL secret value [$masked] — templates must reference, never embed, secrets"
        tmpl_leak=1
      fi
    done
  done < <(find "$REPO" -name '*.tmpl' -type f -not -path '*/.git/*' 2>/dev/null)
  [ "$tmpl_leak" -eq 0 ] && ok "no '*.tmpl' file contains a literal secret value"
else
  info "skipping template scan (no secret values to search for)"
fi

# ---- verdict --------------------------------------------------------------

printf '\n'
if [ "$FAILED" -ne 0 ]; then
  printf 'FAILED — leak or misconfiguration above. DO NOT commit. Fix, then re-run.\n' >&2
  exit 1
elif [ "$LEAK_SCAN_RAN" -eq 0 ]; then
  # Encryption (checks 1-3) verified, but checks 4-6 had no secret literal to
  # hunt for, so we have NOT proven the plaintext is absent from the working
  # tree / git history / templates. Do not claim "no plaintext leak".
  printf 'PARTIAL — %s is encrypted end-to-end, but NO leak-scan was performed\n' "$SRC_BASE"
  printf '          (no secret values to search for). Encryption is verified;\n'
  printf '          leak-freedom is NOT. Re-run with --expect-value '"'"'literal'"'"' or\n'
  printf '          --expect-file PLAINTEXT to prove the working tree, git history,\n'
  printf '          and templates carry no plaintext copy before you commit.\n'
  exit 3
else
  printf 'PASS — %s is encrypted end-to-end; no plaintext leak detected. Safe to commit.\n' "$SRC_BASE"
  exit 0
fi
