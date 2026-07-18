#!/usr/bin/env bash
# Build a real external mkHost consumer so declared Home Manager seams cannot
# regress into parent/child symlink conflicts that evaluation alone misses.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
flake_ref="git+file://${repo_root}"

rg -Fq 'path = ../external-overlays/git/extra.inc' \
  "${repo_root}/home/.config/git/config"
rg -Fq 'path = ../external-overlays/git/work.inc' \
  "${repo_root}/home/.config/git/config"
rg -Fq 'source-file -q "$XDG_CONFIG_HOME/external-overlays/tmux/*.conf"' \
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
echo "external-overlay-contract: revision and isolated fragment build passed"
