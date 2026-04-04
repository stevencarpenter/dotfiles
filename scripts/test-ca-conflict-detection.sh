#!/usr/bin/env zsh

set -euo pipefail

repo_root="${0:A:h:h}"
helper_path="${repo_root}/dot_config/zsh/lib/chezmoi-apply.zsh"

source "${helper_path}"

tmpdir="$(mktemp -d /tmp/chezmoi-ca-test.XXXXXX)"
trap 'rm -rf "${tmpdir}"' EXIT

source_dir="${tmpdir}/source"
home_dir="${tmpdir}/home"

mkdir -p "${source_dir}" "${home_dir}"
print -r -- 'source-v1' > "${source_dir}/dot_testfile"

HOME="${home_dir}" chezmoi init --source="${source_dir}" >/dev/null 2>&1
HOME="${home_dir}" chezmoi --source="${source_dir}" apply >/dev/null 2>&1

print -r -- 'source-v2' > "${source_dir}/dot_testfile"
if HOME="${home_dir}" chezmoi --source="${source_dir}" status | _ca_has_target_drift; then
  echo "expected source-only change to avoid the conflict prompt" >&2
  exit 1
fi

print -r -- 'manual-edit' > "${home_dir}/.testfile"
if ! HOME="${home_dir}" chezmoi --source="${source_dir}" status | _ca_has_target_drift; then
  echo "expected target drift to trigger the conflict prompt" >&2
  exit 1
fi

echo "ca conflict detection behaves as expected"
