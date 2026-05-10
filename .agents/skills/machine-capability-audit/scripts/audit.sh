#!/usr/bin/env bash
# Machine-capability audit for the chezmoi dotfiles repo.
#
# Reports:
#   1. All capabilities defined in `.chezmoidata/machines.toml`.
#   2. Per-capability consumer count + locations (file:line) across .tmpl files,
#      .chezmoiignore, and .chezmoiscripts/.
#   3. Orphans — capabilities defined in the table but referenced by nothing.
#   4. Undefined gates — capabilities referenced in templates but missing from
#      every row of the table.
#   5. Prefix-based gates (`hasPrefix "personal"` / `hasPrefix "work"`) that
#      could migrate to the capability table per the repo's stated preference
#      for capability-based gating.
#
# Run from anywhere; the script roots itself on the chezmoi source dir.

set -euo pipefail

# Resolve repo root (the chezmoi source dir). Override with REPO_ROOT env var.
if [[ -n "${REPO_ROOT:-}" ]]; then
  ROOT="$REPO_ROOT"
elif command -v chezmoi >/dev/null 2>&1; then
  ROOT="$(chezmoi source-path 2>/dev/null || true)"
fi
ROOT="${ROOT:-$(cd "$(dirname "$0")/../../../.." && pwd)}"

if [[ ! -f "$ROOT/.chezmoidata/machines.toml" ]]; then
  echo "error: $ROOT/.chezmoidata/machines.toml not found — set REPO_ROOT or run from chezmoi source dir" >&2
  exit 2
fi

cd "$ROOT"

# ---------------------------------------------------------------------------
# 1. Extract defined capabilities — every key under any [machines.*] table,
#    de-duped. Lines look like:  `tiling = true`  /  `aws_sso = false`.
# ---------------------------------------------------------------------------
mapfile -t CAPS < <(
  awk '
    /^\[machines\./        { in_machine = 1; next }
    /^\[/                  { in_machine = 0; next }
    in_machine && /^[a-zA-Z_][a-zA-Z0-9_]*[[:space:]]*=[[:space:]]*(true|false)/ {
      sub(/[[:space:]]*=.*/, "")
      print
    }
  ' .chezmoidata/machines.toml | sort -u
)

if [[ ${#CAPS[@]} -eq 0 ]]; then
  echo "error: no capabilities found in .chezmoidata/machines.toml" >&2
  exit 2
fi

# ---------------------------------------------------------------------------
# 2. Collect every consumer. Search .tmpl files, .chezmoiignore, and any shell
#    scripts. Pattern: `(index .machines .machine).<cap>` — possibly negated.
# ---------------------------------------------------------------------------
SEARCH_TARGETS=(
  $(find . -name "*.tmpl" -not -path "./.git/*" -not -path "./.idea/*" 2>/dev/null)
  .chezmoiignore
)

# Build a map: capability -> list of "file:line" hits.
declare -A HITS
for cap in "${CAPS[@]}"; do
  HITS[$cap]=""
done

# Also discover any references that point at undefined capabilities.
declare -A SEEN_REFS

# grep -nH gives "file:line:content"; the regex matches `.machines .machine).<cap>`.
while IFS= read -r line; do
  file="${line%%:*}"
  rest="${line#*:}"
  lineno="${rest%%:*}"
  # Extract capability name. Pattern: `.machine).<NAME>` — name is [A-Za-z_][A-Za-z0-9_]*.
  cap=$(printf '%s\n' "$rest" | grep -oE '\.machine\)\.[A-Za-z_][A-Za-z0-9_]*' | head -1 | sed 's/^\.machine)\.//')
  [[ -z "$cap" ]] && continue
  SEEN_REFS[$cap]=1
  if [[ -n "${HITS[$cap]+x}" ]]; then
    HITS[$cap]+="${file}:${lineno}"$'\n'
  fi
done < <(grep -nH -E '\(index \.machines \.machine\)\.[A-Za-z_][A-Za-z0-9_]*' "${SEARCH_TARGETS[@]}" 2>/dev/null || true)

# ---------------------------------------------------------------------------
# 3. Find prefix-based gates that are migration candidates.
# ---------------------------------------------------------------------------
mapfile -t PREFIX_HITS < <(
  grep -nH -E 'hasPrefix "(personal|work|lab)"' "${SEARCH_TARGETS[@]}" 2>/dev/null \
    | grep -v '\.chezmoi\.toml\.tmpl' \
    || true
)

# ---------------------------------------------------------------------------
# 4. Render the report.
# ---------------------------------------------------------------------------
printf '# Capabilities defined: %s\n' "$(IFS=', '; echo "${CAPS[*]}")"
printf '# Per capability:\n'

ORPHANS=()
for cap in "${CAPS[@]}"; do
  raw="${HITS[$cap]}"
  count=0
  if [[ -n "$raw" ]]; then
    count=$(printf '%s' "$raw" | grep -c .)
  fi
  if [[ $count -eq 0 ]]; then
    printf '##  %s: 0 consumers — ORPHAN\n' "$cap"
    ORPHANS+=("$cap")
  else
    # Strip "./" prefix and join with ", ".
    locs=$(printf '%s' "$raw" | sed 's|^\./||' | grep -v '^$' | paste -sd ',' - | sed 's/,/, /g')
    printf '##  %s: %d consumers (%s)\n' "$cap" "$count" "$locs"
  fi
done

# Undefined gates: anything we saw in templates that isn't in the table.
UNDEFINED=()
for ref in "${!SEEN_REFS[@]}"; do
  found=0
  for cap in "${CAPS[@]}"; do
    [[ "$ref" == "$cap" ]] && { found=1; break; }
  done
  [[ $found -eq 0 ]] && UNDEFINED+=("$ref")
done

if [[ ${#UNDEFINED[@]} -gt 0 ]]; then
  printf '# Undefined gates (referenced but not in machines.toml):\n'
  for u in "${UNDEFINED[@]}"; do
    printf '##  %s\n' "$u"
  done
fi

printf '# Prefix-based gates that could migrate:\n'
if [[ ${#PREFIX_HITS[@]} -eq 0 ]]; then
  printf '##  (none)\n'
else
  for hit in "${PREFIX_HITS[@]}"; do
    file="${hit%%:*}"
    rest="${hit#*:}"
    lineno="${rest%%:*}"
    flavor=$(printf '%s' "$rest" | grep -oE 'hasPrefix "(personal|work|lab)"' | head -1)
    file="${file#./}"
    printf '##  %s:%s (%s)\n' "$file" "$lineno" "$flavor"
  done
fi

# Exit non-zero if anything actionable was found, so this can be wired into
# CI / pre-commit later without rework.
if [[ ${#ORPHANS[@]} -gt 0 || ${#UNDEFINED[@]} -gt 0 ]]; then
  exit 1
fi
exit 0
