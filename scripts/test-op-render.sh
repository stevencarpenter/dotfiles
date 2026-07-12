#!/usr/bin/env bash
# Tests for home/.local/bin/op-render — the fail-safe 1Password Connect renderer.
# Follows the repo's plain-shell test convention (no bats). Uses a mock `op`
# switched by $OP_MOCK_MODE so the dangerous branches (inject failure, empty
# output, absent creds) are exercised deterministically without a real Connect.
set -uo pipefail

here="$(cd "$(dirname "$0")/.." && pwd)"
RENDER="$here/home/.local/bin/op-render"

fails=0
run() { local name="$1"; shift; if "$@"; then echo "ok   - $name"; else echo "FAIL - $name"; fails=$((fails + 1)); fi; }

# Portable permission read: GNU stat (Linux CI) then BSD stat (macOS).
# Order matters — GNU `stat -f` means --file-system and exits 0 with garbage
# (never triggering the fallback), whereas BSD `stat -c` fails cleanly, so the
# GNU-first / BSD-fallback direction is the only one that works on both.
perm() { stat -c '%a' "$1" 2>/dev/null || stat -f '%Lp' "$1"; }

make_mock() {
  cat > "$work/op" <<'EOF'
#!/usr/bin/env bash
# mock op: supports only `op inject -i <tpl> -o <out>`; behavior via $OP_MOCK_MODE.
out=""
while [ $# -gt 0 ]; do case "$1" in -o) out="$2"; shift 2 ;; *) shift ;; esac; done
case "${OP_MOCK_MODE:-ok}" in
  ok)    printf 'export FOO=bar\n' > "$out"; exit 0 ;;
  fail)  exit 3 ;;
  empty) : > "$out"; exit 0 ;;
esac
EOF
  chmod +x "$work/op"
}

setup() {
  work="$(mktemp -d)"
  export OP_BIN="$work/op"
  export OP_RENDER_MANIFEST="$work/manifest"
  tpl="$work/in.tpl"; target="$work/out"
  printf 'export FOO={{ op://Homelab/x/y }}\n' > "$tpl"
  printf '%s:%s\n' "$tpl" "$target" > "$OP_RENDER_MANIFEST"
  make_mock
}

t_happy() {
  setup
  OP_MOCK_MODE=ok OP_CONNECT_HOST=h OP_CONNECT_TOKEN=t "$RENDER" >/dev/null 2>&1
  [ "$(cat "$target")" = "export FOO=bar" ] && [ "$(perm "$target")" = "600" ]
}

t_creds_absent_skips() {
  setup; printf 'PRE\n' > "$target"
  ( unset OP_CONNECT_HOST OP_CONNECT_TOKEN; OP_MOCK_MODE=ok "$RENDER" >/dev/null 2>&1 )
  [ "$(cat "$target")" = "PRE" ]
}

t_inject_fail_preserves() {
  setup; printf 'GOOD\n' > "$target"
  OP_MOCK_MODE=fail OP_CONNECT_HOST=h OP_CONNECT_TOKEN=t "$RENDER" >/dev/null 2>&1; local rc=$?
  [ "$(cat "$target")" = "GOOD" ] && [ "$rc" -ne 0 ]
}

t_empty_output_preserves() {
  setup; printf 'GOOD\n' > "$target"
  OP_MOCK_MODE=empty OP_CONNECT_HOST=h OP_CONNECT_TOKEN=t "$RENDER" >/dev/null 2>&1
  [ "$(cat "$target")" = "GOOD" ]
}

run "happy path renders 0600"          t_happy
run "absent creds skip, keep file"     t_creds_absent_skips
run "inject failure preserves target"  t_inject_fail_preserves
run "empty output preserves target"    t_empty_output_preserves

[ "$fails" -eq 0 ] || { echo "$fails test(s) failed"; exit 1; }
echo "all op-render tests passed"
