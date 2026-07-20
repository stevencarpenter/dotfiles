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
# mock op: supports `op whoami` (auth probe via $OP_MOCK_AUTH) and deliberately
# lets `op account list` succeed even while signed out, matching the real CLI.
# `op inject -i <tpl> -o <out> [--force]` (behavior via $OP_MOCK_MODE).
# Mirrors real `op inject`: it ABORTS on an existing -o file without --force,
# so op-render (which mktemps its tmpfile first) must pass --force.
case "$1" in
  account) echo '[{"url":"my.1password.com"}]'; exit 0 ;;
  whoami) case "${OP_MOCK_AUTH:-none}" in ok) echo '{"url":"my.1password.com"}'; exit 0 ;; *) exit 1 ;; esac ;;
esac
out=""; force=0
for a in "$@"; do case "$a" in -f|--force) force=1 ;; esac; done
while [ $# -gt 0 ]; do case "$1" in -o) out="$2"; shift 2 ;; *) shift ;; esac; done
if [ -e "$out" ] && [ "$force" -eq 0 ]; then
  echo "mock op: output '$out' exists; use --force" >&2; exit 1
fi
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
  [ "$(cat "$target")" = "export FOO=bar" ] \
    && [ "$(perm "$target")" = "600" ] \
    && [ -f "$work/.last-render" ]
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

t_interactive_renders() {
  setup; : > "$target"
  ( unset OP_CONNECT_HOST OP_CONNECT_TOKEN
    OP_MOCK_MODE=ok OP_MOCK_AUTH=ok "$RENDER" >/dev/null 2>&1 )
  [ "$(cat "$target")" = "export FOO=bar" ] && [ "$(perm "$target")" = "600" ]
}

t_no_auth_skips() {
  setup; printf 'PRE\n' > "$target"
  ( unset OP_CONNECT_HOST OP_CONNECT_TOKEN
    OP_MOCK_MODE=ok OP_MOCK_AUTH=none "$RENDER" >/dev/null 2>&1 )
  [ "$(cat "$target")" = "PRE" ]
}

run "happy path renders 0600 + sentinel" t_happy
run "absent creds skip, keep file"     t_creds_absent_skips
run "inject failure preserves target"  t_inject_fail_preserves
run "empty output preserves target"    t_empty_output_preserves
run "interactive op renders 0600"      t_interactive_renders
run "no auth (no connect, no session)" t_no_auth_skips

[ "$fails" -eq 0 ] || { echo "$fails test(s) failed"; exit 1; }
echo "all op-render tests passed"
