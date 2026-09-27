#!/usr/bin/env bash
# Offline provisioning and native-update regression using a local remote.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
launcher="$repo_root/home/.local/bin/firstmate"
fixture="$(mktemp -d)"
trap 'rm -rf "$fixture"' EXIT
export HOME="$fixture/home"
export GIT_CONFIG_GLOBAL="$fixture/gitconfig" GIT_CONFIG_NOSYSTEM=1
mkdir -p "$fixture/bin" "$fixture/origin/bin"
git config --global user.name 'Test Fixture'
git config --global user.email 'fixture@example.invalid'
git config --global commit.gpgsign false
git config --global core.hooksPath /dev/null
git config --global "url.$fixture/origin.insteadOf" https://github.com/kunchenguid/firstmate.git
git -C "$fixture/origin" init -q -b main
printf 'fixture\n' >"$fixture/origin/README.md"
cat >"$fixture/origin/bin/fm-inbox.sh" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$FM_HOME" "$@" >"$HOME/inbox-request"
exit "${TEST_INBOX_STATUS:-0}"
SH
chmod +x "$fixture/origin/bin/fm-inbox.sh"
git -C "$fixture/origin" add README.md bin/fm-inbox.sh
git -C "$fixture/origin" commit -qm 'test: seed fixture'
original="$(git -C "$fixture/origin" rev-parse HEAD)"
cat >"$fixture/bin/pi" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$PWD" "$FM_HOME" "$FM_PI_HARNESS" "$@" >"$HOME/pi-launch"
SH
chmod +x "$fixture/bin/pi"
export PATH="$fixture/bin:$PATH"

# Fresh setup follows upstream main without launching an agent.
"$launcher" --setup
checkout="$HOME/.local/share/firstmate/repo"
[[ "$(git -C "$checkout" symbolic-ref --short HEAD)" == main ]]
[[ "$(git -C "$checkout" rev-parse --abbrev-ref '@{upstream}')" == origin/main ]]
[[ ! -e "$HOME/pi-launch" ]]

# Existing installs require no network and retain state and local edits.
mkdir -p "$HOME/.local/share/firstmate/state"
printf 'retain\n' >"$HOME/.local/share/firstmate/state/sentinel"
printf 'local change\n' >>"$checkout/README.md"
mv "$fixture/origin" "$fixture/offline"
"$launcher" --setup
"$launcher" --model 'provider/model' 'one prompt with spaces'
printf '%s\n' "$checkout" "$HOME/.local/share/firstmate" \
  pi --tui-mode regular --model provider/model 'one prompt with spaces' >"$fixture/expected"
cmp "$fixture/expected" "$HOME/pi-launch"
rg -q 'local change' "$checkout/README.md"
[[ "$(<"$HOME/.local/share/firstmate/state/sentinel")" == retain ]]
[[ "$(git -C "$checkout" rev-parse HEAD)" == "$original" ]]
mv "$fixture/offline" "$fixture/origin"
git -C "$checkout" restore README.md

# Only the application advances the checkout; setup does not pull newer commits.
printf 'upstream change\n' >>"$fixture/origin/README.md"
git -C "$fixture/origin" commit -qam 'test: native update'
"$launcher" --setup
[[ "$(git -C "$checkout" rev-parse HEAD)" == "$original" ]]
git -C "$checkout" pull --ff-only
updated="$(git -C "$checkout" rev-parse HEAD)"
[[ "$updated" != "$original" ]]
"$launcher" --setup
"$launcher" --continue
[[ "$(git -C "$checkout" rev-parse HEAD)" == "$updated" ]]

# Native update requests address this home without starting another Pi session.
cp "$HOME/pi-launch" "$fixture/previous-launch"
"$launcher" --request-update test-update >"$fixture/request-output"
update_request='Run the complete updatefirstmate skill, including its persistence and secondmate restart steps. Preserve active crew work and report skipped or unconfirmed updates. Companion CLI packages are managed by dotfiles through mise; do not install competing copies. Record the update outcome with fm-inbox.sh reply against this note.'
printf '%s\n' "$HOME/.local/share/firstmate" note --request-id test-update -- \
  "$update_request" >"$fixture/expected-request"
cmp "$fixture/expected-request" "$HOME/inbox-request"
rg -Fq "$update_request" "$HOME/inbox-request"
rg -Fq 'update requested; completion is reported by Firstmate' "$fixture/request-output"
cmp "$fixture/previous-launch" "$HOME/pi-launch"
[[ "$(git -C "$checkout" rev-parse HEAD)" == "$updated" ]]
for status in 1 3; do
  actual_status=0
  TEST_INBOX_STATUS="$status" "$launcher" --request-update test-update >"$fixture/request-output" 2>&1 || actual_status=$?
  [[ "$actual_status" == "$status" ]]
  if rg -Fq 'update requested; completion' "$fixture/request-output"; then
    echo 'update request hid an inbox failure' >&2; exit 1
  fi
done
rg -Fq 'request saved but wake failed; retry: firstmate --request-update test-update' "$fixture/request-output"

# Reproduce the old pin updater: main is behind the detached installed commit.
git -C "$checkout" switch --detach "$updated"
git -C "$checkout" branch -f main "$original"
# Migration must not steal main from another worktree or move its branch tip.
git -C "$checkout" worktree add -q "$fixture/other-worktree" main
if "$launcher" --setup; then
  echo 'setup moved main while another worktree held it' >&2; exit 1
fi
[[ "$(git -C "$checkout" rev-parse main)" == "$original" ]]
[[ "$(git -C "$checkout" rev-parse HEAD)" == "$updated" ]]
git -C "$checkout" worktree remove "$fixture/other-worktree"
"$launcher" --setup
[[ "$(git -C "$checkout" symbolic-ref --short HEAD)" == main ]]
[[ "$(git -C "$checkout" rev-parse HEAD)" == "$updated" ]]
[[ "$(git -C "$checkout" rev-parse --abbrev-ref '@{upstream}')" == origin/main ]]
[[ -z "$(git -C "$checkout" status --porcelain)" ]]
[[ "$(<"$HOME/.local/share/firstmate/state/sentinel")" == retain ]]
"$launcher" --setup

# A detached install with no local main must gain a tracking branch, not just a name.
git -C "$checkout" switch --detach "$updated"
git -C "$checkout" branch -D main
"$launcher" --setup
[[ "$(git -C "$checkout" symbolic-ref --short HEAD)" == main ]]
[[ "$(git -C "$checkout" rev-parse HEAD)" == "$updated" ]]
[[ "$(git -C "$checkout" rev-parse --abbrev-ref '@{upstream}')" == origin/main ]]

# No migration may roll main back, discard edits, or bless detached local history.
git -C "$checkout" switch --detach "$original"
if "$launcher" --setup; then
  echo 'setup rolled main back to an older detached commit' >&2; exit 1
fi
[[ "$(git -C "$checkout" rev-parse main)" == "$updated" ]]
[[ "$(git -C "$checkout" rev-parse HEAD)" == "$original" ]]
git -C "$checkout" switch --detach "$updated"
printf 'local change\n' >>"$checkout/README.md"
if "$launcher" --setup; then
  echo 'setup migrated a dirty detached checkout' >&2; exit 1
fi
rg -q 'local change' "$checkout/README.md"
git -C "$checkout" restore README.md
git -C "$checkout" commit --allow-empty -qm 'test: detached local work'
local_head="$(git -C "$checkout" rev-parse HEAD)"
if "$launcher" --setup; then
  echo 'setup adopted detached local history' >&2; exit 1
fi
[[ "$(git -C "$checkout" rev-parse HEAD)" == "$local_head" ]]
[[ "$(git -C "$checkout" rev-parse main)" == "$updated" ]]

# A named feature branch and a different origin require explicit inspection.
git -C "$checkout" switch -c local-work
if "$launcher" --setup; then
  echo 'setup switched away from local work' >&2; exit 1
fi
[[ "$(git -C "$checkout" symbolic-ref --short HEAD)" == local-work ]]
git -C "$checkout" switch main
git -C "$checkout" remote set-url origin https://example.invalid/different.git
if "$launcher" --setup; then
  echo 'setup accepted a different origin' >&2; exit 1
fi
if "$launcher"; then
  echo 'launcher accepted a different origin' >&2; exit 1
fi

# The retired pin updater left HEAD ahead of a stale cached origin/main. That state is
# legitimate and must migrate once the ref is refreshed, not be rejected as history.
git -C "$checkout" remote set-url origin https://github.com/kunchenguid/firstmate.git
git -C "$checkout" switch --detach "$updated"
git -C "$checkout" branch -f main "$original"
git -C "$checkout" update-ref refs/remotes/origin/main "$original"
"$launcher" --setup
[[ "$(git -C "$checkout" symbolic-ref --short HEAD)" == main ]]
[[ "$(git -C "$checkout" rev-parse HEAD)" == "$updated" ]]
[[ "$(git -C "$checkout" rev-parse --abbrev-ref '@{upstream}')" == origin/main ]]
[[ -z "$(git -C "$checkout" status --porcelain)" ]]

# A cached proof must not fetch. Detach at a commit cached origin/main already contains and take
# the remote away: this state never needs origin, so a fetch attempt surfaces as git's own
# repository error in the captured output.
git -C "$checkout" switch --detach "$updated"
mv "$fixture/origin" "$fixture/offline"
setup_status=0
"$launcher" --setup >"$fixture/offline-proof.out" 2>&1 || setup_status=$?
mv "$fixture/offline" "$fixture/origin"
if [[ "$setup_status" != 0 ]]; then
  echo "setup failed while the cached origin/main proof already held (rc=$setup_status)" >&2
  cat "$fixture/offline-proof.out" >&2
  exit 1
fi
if rg -q 'does not appear to be a git repository|fatal:' "$fixture/offline-proof.out"; then
  echo 'setup fetched origin although cached origin/main already contained HEAD' >&2
  exit 1
fi
if [[ "$(git -C "$checkout" symbolic-ref --short HEAD)" != main ]]; then
  echo 'setup did not attach main for a detached checkout on the cached origin/main' >&2
  exit 1
fi
if [[ "$(git -C "$checkout" rev-parse HEAD)" != "$updated" ]]; then
  echo 'setup moved HEAD while relying on the cached origin/main proof' >&2
  exit 1
fi
if [[ "$(git -C "$checkout" rev-parse --abbrev-ref '@{upstream}')" != origin/main ]]; then
  echo 'setup did not set the main upstream for a detached checkout' >&2
  exit 1
fi
if [[ -n "$(git -C "$checkout" status --porcelain)" ]]; then
  echo 'setup left the worktree dirty after attaching main' >&2
  exit 1
fi

echo 'test-firstmate-config: OK (provision once, native updates, offline reuse, safe legacy migration)'
