#!/usr/bin/env bash
# Mutation audit of scripts/test-atuin-filter-parity.sh — a test for a test.
#
# Why this exists: the parity guard's first version PASSED while the exact
# defect it was written to catch was reproducible, because its assertions
# matched bare substrings instead of the properties they claimed to check
# (`enabled = true` anywhere in the file rather than inside [tmux]; two
# history_filter blocks being "identical" when both were empty). A guard that
# cannot fail is worse than no guard, because it reads as coverage.
#
# So: apply one regression at a time to throwaway copies and assert the guard
# fails, with the RIGHT message. Cases marked PASS are valid-but-unusual inputs
# that must not trip it — false positives erode trust just as fast.
#
# Mutations go through python3 rather than `sed -i`, whose in-place flag takes
# an argument on BSD and not on GNU; this runs on both.
set -uo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
guard="scripts/test-atuin-filter-parity.sh"
sync_rel="home/.config/atuin/config.sync.toml"
local_rel="home/.config/atuin/config.local.toml"

for f in "${guard}" "${sync_rel}" "${local_rel}"; do
  [[ -f "${repo_root}/${f}" ]] || {
    echo "FAIL: ${f} not found (moved? update this test)" >&2
    exit 1
  }
done

work="$(mktemp -d "${TMPDIR:-/tmp}/parity-mutations.XXXXXX")"
trap 'rm -rf "${work}"' EXIT

cat >"${work}/mutate.py" <<'PYEOF'
import sys, os

op, path = sys.argv[1], sys.argv[2]
rest = sys.argv[3:]
s = open(path).read()

if op == "sub":                       # sub <file> <old> <new>  (must be unique)
    old, new = rest
    assert s.count(old) == 1, f"{path}: expected 1 occurrence of {old!r}, found {s.count(old)}"
    s = s.replace(old, new)
elif op == "delline":                 # delline <file> <substring>
    needle = rest[0]
    s = "\n".join(l for l in s.split("\n") if needle not in l)
elif op == "subline":                 # subline <file> <exact-line> <replacement>
    # Line-exact, for keys whose text also appears in prose above them —
    # `auto_sync = false` is both an assignment and part of its own comment.
    old, new = rest
    lines = s.split("\n")
    hits = [i for i, l in enumerate(lines) if l == old]
    assert len(hits) == 1, f"{path}: expected 1 line == {old!r}, found {len(hits)}"
    lines[hits[0]] = new
    s = "\n".join(lines)
elif op == "delexact":                # delexact <file> <exact-line>
    old = rest[0]
    lines = s.split("\n")
    hits = [i for i, l in enumerate(lines) if l == old]
    assert len(hits) == 1, f"{path}: expected 1 line == {old!r}, found {len(hits)}"
    s = "\n".join(l for i, l in enumerate(lines) if i != hits[0])
elif op == "shrink":                  # shrink <file> <n>  -> n placeholder patterns
    n = int(rest[0])
    lines = s.split("\n")
    b = next(i for i, l in enumerate(lines) if l.startswith("# --- BEGIN history_filter"))
    e = next(i for i, l in enumerate(lines) if l.startswith("# --- END history_filter"))
    body = ["history_filter = ["] + [f'    "PAT{i}",' for i in range(n)] + ["]"]
    s = "\n".join(lines[:b + 1] + body + lines[e:])
elif op == "addpat":                  # addpat <file>  -> one extra pattern
    s = s.replace('    "AKIA', '    "MUTATION_ONLY",\n    "AKIA', 1)
elif op == "swap":                    # swap <file> <substrA> <substrB>
    a, b = rest
    lines = s.split("\n")
    i = next(n for n, l in enumerate(lines) if a in l)
    j = next(n for n, l in enumerate(lines) if b in l)
    lines[i], lines[j] = lines[j], lines[i]
    s = "\n".join(lines)
elif op == "append":                  # append <file> <text>
    s = s + rest[0] + "\n"
elif op == "padto":                   # padto <file> <other-file>  -> equal byte size
    other = os.path.getsize(rest[0])
    cur = len(s.encode())
    if other > cur:
        s = s + "#" + " " * (other - cur - 2) + "\n"
else:
    raise SystemExit(f"unknown op {op}")

open(path, "w").write(s)
PYEOF

ok=0
bad=0

fresh() {
  rm -rf "${work}/w"
  mkdir -p "${work}/w/scripts" "${work}/w/home/.config/atuin"
  cp "${repo_root}/${guard}" "${work}/w/scripts/"
  cp "${repo_root}/${sync_rel}" "${work}/w/${sync_rel}"
  cp "${repo_root}/${local_rel}" "${work}/w/${local_rel}"
}
mut() { python3 "${work}/mutate.py" "$@"; }
SYNC="${work}/w/${sync_rel}"
LOCAL="${work}/w/${local_rel}"

# check <name> <PASS|FAIL> <expected-message-substring or ->
check() {
  local name="$1" want="$2" needle="$3" out rc got verdict
  out="$("${work}/w/${guard}" 2>&1)"
  rc=$?
  if [[ ${rc} -eq 0 ]]; then got=PASS; else got=FAIL; fi

  verdict=OK
  [[ "${got}" == "${want}" ]] || verdict=WRONG-OUTCOME
  if [[ "${verdict}" == OK && "${want}" == FAIL && "${needle}" != "-" ]]; then
    grep -qF -- "${needle}" <<<"${out}" || verdict=WRONG-REASON
  fi

  if [[ "${verdict}" == OK ]]; then
    ok=$((ok + 1))
  else
    bad=$((bad + 1))
    echo "MUTATION-AUDIT FAIL: ${name} (want ${want}, got ${got}, rc=${rc}, ${verdict})" >&2
    # shellcheck disable=SC2001  # multi-line indent; parameter expansion won't do it
    sed 's/^/    /' <<<"${out}" >&2
  fi
}

fresh; check "baseline unmutated" PASS -

# --- the guarded files must exist at all --------------------------------
fresh; rm "${SYNC}";  check "sync variant deleted" FAIL "is missing"
fresh; rm "${LOCAL}"; check "local variant deleted" FAIL "is missing"
fresh; mv "${SYNC}" "${work}/w/home/.config/atuin/config.renamed.toml"
check "sync variant renamed" FAIL "is missing"

# --- history_filter must exist and be non-trivial -----------------------
fresh; mut delline "${SYNC}" 'history_filter = ['; mut delline "${LOCAL}" 'history_filter = ['
check "history_filter assignment removed from both" FAIL "has no top-level history_filter"
fresh; mut shrink "${SYNC}" 4; mut shrink "${LOCAL}" 4
check "both filters shrunk below the 5-pattern floor" FAIL "expected at least 5"
fresh; mut shrink "${SYNC}" 5; mut shrink "${LOCAL}" 5
check "both filters at exactly the 5-pattern floor" PASS -

# --- the two lists must not drift ---------------------------------------
fresh; mut addpat "${SYNC}"
check "pattern added to sync only" FAIL "have drifted"
fresh; mut sub "${LOCAL}" '"ghp_[A-Za-z0-9]+",' '"ghp_[A-Za-z]+",'
check "one pattern subtly weakened in local" FAIL "have drifted"
fresh; mut swap "${LOCAL}" '"DIUN_TOKEN"' '"NTFY_PASSWORD"'
check "two patterns reordered in local" FAIL "have drifted"

# --- the sentinels the comparison depends on ----------------------------
fresh; mut delline "${SYNC}" '# --- BEGIN history_filter'
check "BEGIN sentinel removed from sync" FAIL -
fresh; mut delline "${LOCAL}" '# --- END history_filter'
check "END sentinel removed from local" FAIL -

# --- [tmux].enabled, and specifically its table scope -------------------
fresh; mut sub "${LOCAL}" 'enabled = true' 'enabled = false'
check "local [tmux] enabled = false" FAIL "inside [tmux]"
fresh; mut delline "${LOCAL}" '[tmux]'
check "[tmux] header deleted, enabled floats to top level" FAIL "inside [tmux]"
fresh; mut sub "${LOCAL}" '[tmux]' '[daemon]'
check "[tmux] renamed to [daemon]" FAIL "inside [tmux]"
fresh; mut sub "${LOCAL}" 'enabled = true' 'enabled = "true"'
check "local [tmux] enabled as a string" FAIL "inside [tmux]"
fresh; mut sub "${LOCAL}" 'enabled = true' 'enabled=true'
check "local enabled=true without spaces (valid TOML)" PASS -

# --- the sync stanzas that separate the two variants --------------------
fresh; mut subline "${LOCAL}" 'auto_sync = false' 'auto_sync = true'
check "local auto_sync flipped on" FAIL "auto_sync = false"
fresh; mut delexact "${LOCAL}" 'auto_sync = false'
check "local auto_sync removed" FAIL "auto_sync = false"
fresh; mut append "${LOCAL}" 'sync_address = "https://logbook.snugmarina.org"'
check "sync_address appended into local's [tmux] table (atuin ignores it there)" PASS -
fresh; mut subline "${LOCAL}" 'auto_sync = false' \
  'auto_sync = false
sync_address = "https://logbook.snugmarina.org"'
check "local gains a top-level sync_address" FAIL "assigns a top-level sync_address"
fresh; mut sub "${SYNC}" 'sync_address = "https://logbook.snugmarina.org"' \
  'sync_address = "https://evil.example.com"'
check "sync_address repointed in the sync variant" FAIL "lost its top-level self-hosted"
fresh; mut delline "${SYNC}" 'sync_address ='
check "sync_address removed from the sync variant" FAIL "lost its top-level self-hosted"

# --- comment stripping must respect quotes ------------------------------
# Both the config value AND the guard's expected literal are mutated together,
# so this isolates the parser: the value is legitimate and matches, and the
# only way to fail is to truncate at the '#' inside the string.
GUARD="${work}/w/${guard}"
fresh
mut sub "${SYNC}" 'sync_address = "https://logbook.snugmarina.org"' \
  'sync_address = "https://logbook.snugmarina.org/#frag"'
mut sub "${GUARD}" '"https://logbook.snugmarina.org"'"'" '"https://logbook.snugmarina.org/#frag"'"'"
check "a '#' inside a quoted value is not treated as a comment" PASS -

fresh
mut sub "${SYNC}" 'sync_address = "https://logbook.snugmarina.org"' \
  'sync_address = "https://logbook.snugmarina.org" # real trailing comment'
check "a genuine trailing comment after a value is stripped" PASS -

# --- byte-size divergence (zcached stamp insurance, see the guard) ------
fresh; mut padto "${LOCAL}" "${SYNC}"
check "variants padded to identical byte size" FAIL "identical size"

# --- the guard must be deterministic ------------------------------------
fresh
for i in 1 2 3; do
  "${work}/w/${guard}" >/dev/null 2>&1 ||
    { echo "MUTATION-AUDIT FAIL: unmutated guard failed on run ${i}" >&2; bad=$((bad + 1)); }
done

if ((bad > 0)); then
  echo "parity-guard mutation audit: ${bad} case(s) wrong, ${ok} correct" >&2
  exit 1
fi

echo "parity-guard mutation audit OK (${ok} cases: every regression caught, valid inputs not tripped)"
