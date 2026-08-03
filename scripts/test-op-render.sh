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
  whoami) case "${OP_MOCK_AUTH:-none}" in
            ok) echo '{"url":"my.1password.com"}'; exit 0 ;;
            # Real `op` explains itself on stderr; op-render must relay that
            # verbatim instead of collapsing every cause into "failed".
            *) echo '[ERROR] 2026/01/01 00:00:00 account is not signed in' >&2; exit 1 ;;
          esac ;;
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

# "op binary absent" and "op signed out" are different faults with different
# fixes (PATH vs auth). op-render collapsed both into one message, which is how
# a missing-op activation went unnoticed for weeks. Keep them distinguishable.
t_missing_op_distinct_from_signed_out() {
  setup; printf 'PRE\n' > "$target"
  local absent signed_out
  absent="$( ( unset OP_CONNECT_HOST OP_CONNECT_TOKEN
               OP_BIN="$work/definitely-not-here" "$RENDER" 2>&1 >/dev/null ) )"
  signed_out="$( ( unset OP_CONNECT_HOST OP_CONNECT_TOKEN
                   OP_MOCK_AUTH=none "$RENDER" 2>&1 >/dev/null ) )"
  printf '%s\n' "$absent"        | rg -q 'not found' \
    && printf '%s\n' "$signed_out" | rg -q "whoami' failed" \
    && printf '%s\n' "$signed_out" | rg -q 'account is not signed in' \
    && [ "$(cat "$target")" = "PRE" ]
}

# --warn-stale-only is what home.activation runs: sentinel check only, no op
# call and no network, so it stays inside the activation contract (offline +
# fast + idempotent). It must never render, even when auth would succeed.
t_warn_stale_only_never_renders() {
  setup; printf 'PRE\n' > "$target"
  touch -t 202001010000 "$work/.last-render"
  local err rc
  err="$( ( OP_MOCK_MODE=ok OP_CONNECT_HOST=h OP_CONNECT_TOKEN=t \
            "$RENDER" --warn-stale-only 2>&1 >/dev/null ) )"; rc=$?
  [ "$(cat "$target")" = "PRE" ] \
    && [ "$rc" -eq 0 ] \
    && printf '%s\n' "$err" | rg -q 'going stale'
}

# The activation PATH is a closed nix-store list (bash, coreutils, findutils,
# gnused, jq, lix) with NO /opt/homebrew and NO /usr/bin — which is why a bare
# `op` was unresolvable there. --warn-stale-only must need none of that. Pinned
# to a minimal PATH rather than sniffing the live generation: a test that skips
# itself when it can't find machine state silently stops covering anything.
t_warn_stale_only_needs_no_homebrew() {
  setup
  touch -t 202001010000 "$work/.last-render"
  local err
  err="$(env -i HOME="$HOME" PATH="/usr/bin:/bin" \
    OP_RENDER_MANIFEST="$OP_RENDER_MANIFEST" \
    "$RENDER" --warn-stale-only 2>&1 >/dev/null)"
  printf '%s\n' "$err" | rg -q 'going stale' \
    && ! printf '%s\n' "$err" | rg -q 'cannot read file system|not found'
}

# A truncating pipe (`| head -1`) closes stdout mid-run. Without SIGPIPE
# ignored, the second "rendered ..." log kills the script after the targets are
# in place but before the sentinel is touched — a successful render recorded
# forever as stale. Needs >1 manifest entry to reach the fatal second write.
t_sigpipe_does_not_skip_sentinel() {
  setup
  local tpl2="$work/in2.tpl" target2="$work/out2"
  printf 'export BAZ={{ op://Homelab/x/y }}\n' > "$tpl2"
  printf '%s:%s\n' "$tpl2" "$target2" >> "$OP_RENDER_MANIFEST"
  rm -f "$work/.last-render"
  OP_MOCK_MODE=ok OP_CONNECT_HOST=h OP_CONNECT_TOKEN=t \
    "$RENDER" 2>&1 | head -1 >/dev/null
  [ -f "$target2" ] && [ -f "$work/.last-render" ]
}

t_stale_warning_is_clean() {
  setup; printf 'PRE\n' > "$target"
  touch -t 202001010000 "$work/.last-render"
  local err
  err="$( ( unset OP_CONNECT_HOST OP_CONNECT_TOKEN
            OP_MOCK_MODE=ok OP_MOCK_AUTH=none "$RENDER" 2>&1 >/dev/null ) )"
  # The warning must name a timestamp and stay one line. A BSD-only `stat -f`
  # under GNU coreutils (home-manager activation PATH) splices a filesystem
  # dump into the middle of the sentence instead.
  printf '%s\n' "$err" | rg -q 'last successful render was .+ \(>7 days ago\)' \
    && ! printf '%s\n' "$err" | rg -q 'cannot read file system information' \
    && [ "$(printf '%s\n' "$err" | rg -c 'op-render:')" = "$(printf '%s\n' "$err" | wc -l | tr -d ' ')" ]
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
run "missing op vs signed-out differ"   t_missing_op_distinct_from_signed_out
run "truncating pipe keeps sentinel"   t_sigpipe_does_not_skip_sentinel
run "stale warning is one clean line"  t_stale_warning_is_clean
run "--warn-stale-only never renders"  t_warn_stale_only_never_renders
run "--warn-stale-only needs no homebrew" t_warn_stale_only_needs_no_homebrew

[ "$fails" -eq 0 ] || { echo "$fails test(s) failed"; exit 1; }
echo "all op-render tests passed"
