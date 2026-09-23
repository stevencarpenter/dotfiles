#!/usr/bin/env bash
# Offline launcher regression: use a local Git remote and a recording Pi stub.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
launcher="$repo_root/home/.local/bin/firstmate"
rg -qx '[0-9a-f]{40}' "$repo_root/home/.config/firstmate/revision"

fixture="$(mktemp -d)"
trap 'rm -rf "$fixture"' EXIT
export HOME="$fixture/home"
export GIT_CONFIG_GLOBAL="$fixture/gitconfig" GIT_CONFIG_NOSYSTEM=1
mkdir -p "$HOME/.config/firstmate" "$fixture/bin" "$fixture/origin"
git config --global user.name 'Test Fixture'
git config --global user.email 'fixture@example.invalid'
git config --global commit.gpgsign false
git config --global core.hooksPath /dev/null
git config --global "url.$fixture/origin.insteadOf" https://github.com/kunchenguid/firstmate.git
git -C "$fixture/origin" init -q -b main
printf 'fixture\n' >"$fixture/origin/README.md"
git -C "$fixture/origin" add README.md
git -C "$fixture/origin" commit -qm 'test: seed fixture'
git -C "$fixture/origin" rev-parse HEAD >"$HOME/.config/firstmate/revision"

cat >"$fixture/bin/pi" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$PWD" "$FM_HOME" "$FM_PI_HARNESS" "$@" >"$HOME/pi-launch"
EOF
chmod +x "$fixture/bin/pi"
export PATH="$fixture/bin:$PATH"

"$launcher" --setup
"$launcher" --setup
[[ ! -e "$HOME/pi-launch" ]]
"$launcher" --model 'provider/model' 'one prompt with spaces'
printf '%s\n' "$HOME/.local/share/firstmate/repo" "$HOME/.local/share/firstmate" \
  pi --tui-mode regular --model provider/model 'one prompt with spaces' >"$fixture/expected"
cmp "$fixture/expected" "$HOME/pi-launch"

checkout="$HOME/.local/share/firstmate/repo"
mkdir -p "$HOME/.local/share/firstmate/state"
printf 'retain\n' >"$HOME/.local/share/firstmate/state/sentinel"
printf 'local change\n' >>"$checkout/README.md"
if "$launcher" --setup; then
  echo 'firstmate accepted a dirty checkout' >&2
  exit 1
fi
rg -q 'local change' "$checkout/README.md"
[[ "$(<"$HOME/.local/share/firstmate/state/sentinel")" == retain ]]

# A pin change must not reset an existing installation, even when it is clean.
git -C "$checkout" restore README.md
original="$(git -C "$checkout" rev-parse HEAD)"
printf '%040d\n' 0 >"$HOME/.config/firstmate/revision"
if "$launcher" --setup; then
  echo 'firstmate silently replaced a different revision' >&2
  exit 1
fi
[[ "$(git -C "$checkout" rev-parse HEAD)" == "$original" ]]
printf 'main\n' >"$HOME/.config/firstmate/revision"
if "$launcher" --setup; then
  echo 'firstmate accepted an unpinned revision' >&2
  exit 1
fi

# update-firstmate follows upstream main, even from a checkout that drifted ahead of the pin.
updater="$repo_root/scripts/update-firstmate.sh"
printf '#!/usr/bin/env bash\necho 1\n' >"$fixture/bin/capability"
chmod +x "$fixture/bin/capability"
export HOST_CAPABILITY_BIN="$fixture/bin/capability"
printf '%s\n' "$original" >"$HOME/.config/firstmate/revision"
git -C "$fixture/origin" commit --allow-empty -qm 'test: drift'
git -C "$checkout" fetch -q https://github.com/kunchenguid/firstmate.git main
git -C "$checkout" checkout -q --detach FETCH_HEAD
git -C "$fixture/origin" commit --allow-empty -qm 'test: latest'
latest="$(git -C "$fixture/origin" rev-parse HEAD)"
"$updater" | rg -q 'test: latest'
[[ "$(<"$HOME/.config/firstmate/revision")" == "$original" ]]
"$updater" --apply
[[ "$(<"$HOME/.config/firstmate/revision")" == "$latest" ]]
[[ "$(git -C "$checkout" rev-parse HEAD)" == "$latest" ]]
"$launcher" --setup

git -C "$fixture/origin" commit --allow-empty -qm 'test: newer'
printf 'local change\n' >>"$checkout/README.md"
if "$updater" --apply; then
  echo 'update-firstmate moved a dirty checkout' >&2
  exit 1
fi
[[ "$(<"$HOME/.config/firstmate/revision")" == "$latest" ]]

echo 'test-firstmate-config: OK (pinned, isolated, idempotent; local work preserved; updates follow main)'
