#!/usr/bin/env bash
# Contract tests for the repo atlas builder.
#
# Three properties matter and none are visible from a successful build:
#   1. The payload is a pure function of the tree, so two builds must match.
#   2. A cached summary whose source moved must never reach the rendered page.
#   3. Only tracked files may appear, so the site cannot leak untracked work.
#
# Runs against a scratch copy of site/ and restores whatever was there before.
set -euo pipefail

repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
builder="$repo/scripts/build-site.py"
site="$repo/site"
cache="$site/enrichment.json"
work="$(mktemp -d "${TMPDIR:-/tmp}/atlas-test.XXXXXX")"
fail=0

cleanup() {
  if [ -f "$work/enrichment.json.bak" ]; then
    mv "$work/enrichment.json.bak" "$cache"
  elif [ -f "$work/no-cache" ] && [ -f "$cache" ]; then
    rm -f "$cache"
  fi
  rm -rf "$work"
}
trap cleanup EXIT

check() {
  if [ "$1" = "0" ]; then
    printf '  ok    %s\n' "$2"
  else
    printf '  FAIL  %s\n' "$2"
    fail=1
  fi
}

if [ -f "$cache" ]; then
  cp "$cache" "$work/enrichment.json.bak"
else
  touch "$work/no-cache"
fi

echo "build-site contract tests"

# ── 1. determinism ───────────────────────────────────────────────────────────
python3 "$builder" >/dev/null
cp "$site/data.json" "$work/first.json"
python3 "$builder" >/dev/null
if cmp -s "$work/first.json" "$site/data.json"; then
  check 0 "two builds of an unchanged tree produce identical payloads"
else
  check 1 "two builds of an unchanged tree produce identical payloads"
fi

# ── 2. the staleness contract ────────────────────────────────────────────────
# Pick a node the scorer actually queued, then cache a summary against a hash
# that cannot match. The paragraph must not survive into the payload.
target="$(python3 "$builder" --queue | awk '$1=="file"{print $2; exit}')"
if [ -z "$target" ]; then
  check 1 "found a queued file to test suppression against"
else
  marker="STALE_SENTINEL_DO_NOT_RENDER_7f3a"
  python3 - "$cache" "$target" "$marker" <<'PY'
import json, pathlib, sys
path, target, marker = sys.argv[1], sys.argv[2], sys.argv[3]
p = pathlib.Path(path)
data = json.loads(p.read_text()) if p.exists() else {}
data[target] = {
    "text": marker,
    "source_hash": "0000000000000000",  # deliberately cannot match
    "commit": "test",
}
p.write_text(json.dumps(data, indent=2))
PY
  python3 "$builder" >/dev/null
  if grep -q "$marker" "$site/data.json"; then
    check 1 "a summary whose source hash moved is absent from the payload"
  else
    check 0 "a summary whose source hash moved is absent from the payload"
  fi

  if python3 "$builder" --check >/dev/null 2>&1; then
    check 1 "--check exits non-zero while a stale summary is present"
  else
    check 0 "--check exits non-zero while a stale summary is present"
  fi

  # A matching hash must render, so suppression is proven specific rather than
  # a summary that never renders at all.
  real_hash="$(python3 - "$site/data.json" "$target" <<'PY'
import json, sys
print(json.load(open(sys.argv[1]))["nodes"][sys.argv[2]]["hash"])
PY
)"
  python3 - "$cache" "$target" "$marker" "$real_hash" <<'PY'
import json, pathlib, sys
path, target, marker, digest = sys.argv[1:5]
p = pathlib.Path(path)
data = json.loads(p.read_text())
data[target] = {"text": marker, "source_hash": digest, "commit": "test"}
p.write_text(json.dumps(data, indent=2))
PY
  python3 "$builder" >/dev/null
  if grep -q "$marker" "$site/data.json"; then
    check 0 "a summary whose source hash matches does render"
  else
    check 1 "a summary whose source hash matches does render"
  fi
fi

# ── 3. tracked files only ────────────────────────────────────────────────────
if python3 - "$site/data.json" "$repo" <<'PY'
import json, subprocess, sys
payload, repo = sys.argv[1], sys.argv[2]
tracked = set(
    subprocess.run(
        ["git", "-C", repo, "ls-files"], capture_output=True, text=True, check=True
    ).stdout.split()
)
nodes = json.load(open(payload))["nodes"]
leaked = [
    p for p, n in nodes.items() if p and n["kind"] == "file" and p not in tracked
]
if leaked:
    print("untracked paths in payload:", leaked[:5], file=sys.stderr)
    sys.exit(1)
PY
then check 0 "no untracked file reaches the payload"
else check 1 "no untracked file reaches the payload"
fi

# ── 4. gates resolve against the real capability table ───────────────────────
if python3 - "$site/data.json" <<'PY'
import json, sys
data = json.load(open(sys.argv[1]))
hosts = set(data["machines"])
if not hosts:
    print("capability table did not parse", file=sys.stderr)
    sys.exit(1)
seen = 0
for node in data["nodes"].values():
    for gate in (node.get("structure") or {}).get("gates", []):
        seen += 1
        if gate["unknown"]:
            print("gate names an undeclared capability:", gate["expr"], file=sys.stderr)
            sys.exit(1)
        if set(gate["hosts"]) - hosts:
            print("gate resolved to an unknown host:", gate, file=sys.stderr)
            sys.exit(1)
if seen == 0:
    print("no nix gates were extracted at all", file=sys.stderr)
    sys.exit(1)
PY
then check 0 "every extracted nix gate resolves to a declared host"
else check 1 "every extracted nix gate resolves to a declared host"
fi

echo
if [ "$fail" -eq 0 ]; then
  echo "build-site: all contract tests passed"
else
  echo "build-site: contract tests FAILED" >&2
fi
exit "$fail"
