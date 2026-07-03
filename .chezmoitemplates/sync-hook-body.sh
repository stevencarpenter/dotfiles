{{- /*
Shared body for the post-apply sync hooks (MCP + skills), which are identical
except for a handful of strings. Invoked from .chezmoiscripts via:

  {{ template "sync-hook-body.sh" dict ... }}

Expected context keys:
  machine    — chezmoi's .machine
  machines   — chezmoi's .machines capability table
  capability — capability key gating the hook (e.g. "mcp")
  label      — sentence-case label for messages (e.g. "MCP sync")
  labelLower — mid-sentence label (e.g. "skill sync"; acronyms stay as-is)
  entrypoint — mcp_sync console script to run (e.g. "sync-mcp-configs")
  configdir  — subdir of ~/.config holding the machine overlays (e.g. "mcp")
*/ -}}
{{ if not (index (index .machines .machine) .capability) -}}
echo "{{ .label }} skipped (machine capability {{ .capability }}=false)."
exit 0
{{- else -}}

SYNC_PROJECT="${HOME}/.local/share/chezmoi/mcp_sync"
STRICT_MODE="${MCP_SYNC_STRICT:-0}"

fail_or_warn() {
  local message="$1"
  if [[ "${STRICT_MODE}" == "1" ]]; then
    echo "Error: ${message}" >&2
    exit 1
  fi
  echo "Warning: ${message}" >&2
}

if ! command -v uv >/dev/null 2>&1; then
  fail_or_warn "uv is not installed; skipping {{ .labelLower }}."
  exit 0
fi

if [[ -f "${SYNC_PROJECT}/pyproject.toml" ]]; then
  sync_cmd=({{ .entrypoint }})

  # Select the overlay for THIS machine type, rendered from chezmoi's .machine
  # data — never whatever stale overlay happens to sort first on disk after a
  # machine-type change.
  MACHINE_DIR="${HOME}/.config/{{ .configdir }}/machine"
  MACHINE_OVERLAY=""
  {{- if hasPrefix "personal" .machine }}
  MACHINE_OVERLAY="${MACHINE_DIR}/personal.json"
  {{- else if hasPrefix "work" .machine }}
  MACHINE_OVERLAY="${MACHINE_DIR}/work.json"
  {{- else if eq .machine "lab-mac" }}
  MACHINE_OVERLAY="${MACHINE_DIR}/lab.json"
  {{- end }}

  if [[ -n "${MACHINE_OVERLAY}" && -f "${MACHINE_OVERLAY}" ]]; then
    sync_cmd+=(--machine-config "${MACHINE_OVERLAY}")
  fi

  if ! uv run --project "${SYNC_PROJECT}" "${sync_cmd[@]}"; then
    fail_or_warn "{{ .label }} failed."
    exit 0
  fi
else
  echo "Warning: {{ .labelLower }} project not found at ${SYNC_PROJECT}." >&2
  exit 0
fi

{{- end -}}
