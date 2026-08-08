#!/usr/bin/env bash
# Build a real external mkHost consumer so declared Home Manager seams cannot
# regress into parent/child symlink conflicts that evaluation alone misses.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
flake_ref="git+file://${repo_root}"

# A bare `rg -Fq` under `set -e` aborts with no output, which reports a seam
# regression as an unexplained exit 1. Name the missing string instead.
assert_contains() {
  local pattern="$1" file="$2"
  if ! rg -Fq "${pattern}" "${file}"; then
    echo "missing from ${file#"${repo_root}/"}: ${pattern}" >&2
    exit 1
  fi
}

# These includes must stay $HOME-anchored. git resolves a RELATIVE include
# against the realpath of the file holding it, which for this out-of-store
# symlink lands on a path that does not exist — and git skips a missing include
# silently, so the seam breaks with no error and no loaded keys. The full
# derivation is in the comment above [include] in home/.config/git/config.
assert_contains 'path = ~/.config/external-overlays/git/extra.inc' \
  "${repo_root}/home/.config/git/config"
assert_contains 'path = ~/.config/external-overlays/git/work.inc' \
  "${repo_root}/home/.config/git/config"

# Assert the regression direction too: reverting to a relative path is invisible
# at runtime, so presence-only checks above would still pass alongside it.
if rg -Fq 'path = ../external-overlays/git/' "${repo_root}/home/.config/git/config"; then
  echo "git overlay include regressed to a relative path: it resolves outside the" >&2
  echo "overlay tree and git will skip it silently. Anchor it at ~/ instead." >&2
  exit 1
fi

assert_contains 'source-file -q "$XDG_CONFIG_HOME/external-overlays/tmux/*.conf"' \
  "${repo_root}/home/.config/tmux/tmux.conf"

row_revision_expr="
let
  f = builtins.getFlake \"${flake_ref}\";
  caps = builtins.listToAttrs (map (name: { inherit name; value = false; }) f.lib.canonicalCapKeys);
  host = f.lib.mkHost \"contract-row-revision\" {
    system = \"aarch64-darwin\";
    user = \"contract-test\";
    identity = \"work\";
    inherit caps;
    configurationRevision = \"wrapper-row-revision\";
  };
in host.config.system.configurationRevision
"

row_revision="$(nix eval --impure --raw --expr "${row_revision_expr}")"
if [[ "${row_revision}" != "wrapper-row-revision" ]]; then
  echo "external host row revision was not preserved: ${row_revision}" >&2
  exit 1
fi

consumer_expr="
let
  f = builtins.getFlake \"${flake_ref}\";
  caps = builtins.listToAttrs (map (name: { inherit name; value = false; }) f.lib.canonicalCapKeys);
  host = f.lib.mkHost \"contract-external-host\" {
    system = \"aarch64-darwin\";
    user = \"contract-test\";
    identity = \"work\";
    inherit caps;
    extraDarwinModules = [
      ({ ... }: { system.configurationRevision = \"wrapper-module-revision\"; })
    ];
    extraHomeModules = [
      ({ config, ... }: {
        home.file.\".config/external-overlays/git/work.inc\".text = \"[user]\";
        home.file.\".config/external-overlays/tmux/work.conf\".text = \"set -g @contract-test yes\";
        home.file.\".config/worktrunk\".source =
          config.lib.file.mkOutOfStoreSymlink \"/tmp/external-worktrunk\";
      })
    ];
  };
in host
"

module_revision="$(
  nix eval --impure --raw --expr \
    "(${consumer_expr}).config.system.configurationRevision"
)"
if [[ "${module_revision}" != "wrapper-module-revision" ]]; then
  echo "external Darwin module could not override the default revision: ${module_revision}" >&2
  exit 1
fi

activation_path="$(
  nix build --no-link --print-out-paths --impure --expr \
    "(${consumer_expr}).config.home-manager.users.\"contract-test\".home.activationPackage"
)"

test -x "${activation_path}/activate"

# A wrapper-built work host must declare ZERO age secrets.
#
# This base repo no longer imports agenix, so `age.secrets` is not a defined
# option and evaluating it must FAIL. That is the assertion: a successful eval
# means the agenix module leaked back into the base module set, which would
# re-impose an age identity (and a fatal decrypt step) on every external work
# host. Wrappers that want their own secret custody bring their own module.
if nix eval --impure --json --expr \
  "(${consumer_expr}).config.home-manager.users.\"contract-test\".age.secrets" \
  >/dev/null 2>&1; then
  echo "external work host still declares age.secrets: the base re-imported agenix" >&2
  exit 1
fi

# Belt and braces: no age identity path either.
if nix eval --impure --json --expr \
  "(${consumer_expr}).config.home-manager.users.\"contract-test\".age.identityPaths" \
  >/dev/null 2>&1; then
  echo "external work host still declares age.identityPaths" >&2
  exit 1
fi

echo "external-overlay-contract: revision, isolated fragment build, and zero-age-secrets passed"

# ── Coverage for capability branches no in-repo host exercises ──────────────
#
# personal-mac is now the only host in lib/machines.nix, and it has infra=false,
# sketchybar_workspace_badges=false, and identity=personal. So three things this
# repo still ships for external consumers had ZERO evaluated coverage after the
# work host row was removed: the caps.infra mise fragment, the badges=1 branch of
# sketchybar/machine.env, and the identity-selected aerospace.work.toml. A rename
# or deletion of any of them would have gone undetected by every check.
#
# The consumer above deliberately runs with all caps FALSE (it tests the seams).
# This second one turns the relevant caps on so those branches are evaluated and
# asserted. Not a wrapper being tested — a coverage floor for this repo's own
# files.
caps_on_expr="
let
  f = builtins.getFlake \"${flake_ref}\";
  caps = builtins.listToAttrs (map (name: { inherit name; value = false; }) f.lib.canonicalCapKeys)
    // { tiling = true; sketchybar_workspace_badges = true; infra = true; };
  host = f.lib.mkHost \"contract-caps-on\" {
    system = \"aarch64-darwin\";
    user = \"contract-test\";
    identity = \"work\";
    inherit caps;
  };
in host.config.home-manager.users.\"contract-test\"
"

# mkOutOfStoreSymlink embeds a path STRING and never checks that it resolves —
# so asserting readlink alone verifies the wiring but not that the file exists.
# Renaming the source away leaves the derivation byte-identical and the symlink
# merely dangling (found by mutation testing; the first version of this block
# passed happily with aerospace.work.toml moved out of the tree). The link also
# points into the synthetic consumer's $HOME (/Users/contract-test/.dotfiles/...),
# which does not exist here, so existence has to be checked back in the repo.
# Deriving the repo-relative suffix FROM the link keeps the two coupled: a
# changed selection changes which file must exist.
assert_links_to_existing_repo_file() {
  local label="$1" attr="$2" want_suffix="$3"
  local out target rel
  out="$(
    nix build --no-link --print-out-paths --impure --expr \
      "(${caps_on_expr}).home.file.\"${attr}\".source"
  )"
  target="$(readlink "${out}")"
  if [[ "${target}" != *"${want_suffix}" ]]; then
    echo "${label}: expected a link ending in ${want_suffix}, got ${target}" >&2
    exit 1
  fi
  # Everything after the consumer's ".dotfiles/" is the repo-relative path.
  rel="${target#*/.dotfiles/}"
  if [[ "${rel}" == "${target}" ]]; then
    echo "${label}: link is not routed through .dotfiles: ${target}" >&2
    exit 1
  fi
  if [[ ! -f "${repo_root}/${rel}" ]]; then
    echo "${label}: links to ${rel}, which does not exist in this repo" >&2
    exit 1
  fi
}

assert_links_to_existing_repo_file \
  "work identity aerospace selection" \
  ".config/aerospace/aerospace.toml" \
  "/home/.config/aerospace/aerospace.work.toml"

assert_links_to_existing_repo_file \
  "caps.infra mise fragment" \
  ".config/mise/conf.d/infra.toml" \
  "/home/.config/mise/conf.d/infra.toml"

badges="$(
  nix eval --impure --raw --expr \
    "(${caps_on_expr}).home.file.\".config/sketchybar/machine.env\".text"
)"
if ! rg -Fq 'SKETCHYBAR_WORKSPACE_BADGES=1' <<<"${badges}"; then
  echo "sketchybar_workspace_badges=true did not emit the enabled branch" >&2
  exit 1
fi

echo "external-overlay-contract: caps-on coverage (aerospace.work, infra, badges) passed"
