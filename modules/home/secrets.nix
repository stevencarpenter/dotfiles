# Secrets: agenix wired to the EXISTING chezmoi age identity.
#
# Design (see phase1-results.json smes[1] for the full rationale): agenix is the carry-verbatim
# bridge for the nix port. It decrypts each ciphertext blob under secrets/ at home-manager
# activation time using the identity at ~/.config/chezmoi/key.txt — the exact key chezmoi's
# `[age]` config already points at (itself sourced into place from 1Password by bootstrap.sh
# before the first `darwin-rebuild switch`). No blob was re-encrypted to get here: every
# secrets/**/*.age file is byte-identical ciphertext moved from its old dot_ chezmoi path, so
# this module MUST NOT run `age -e` or otherwise touch plaintext.
#
# Store-safety: age.secrets.<name>.file is a ciphertext path — it enters the (world-readable)
# nix store safely because it stays encrypted there. agenix's activation script decrypts each
# secret to config.age.secretsDir (a user-owned, activation-managed path outside the store,
# mode 0400 by default) and symlinks/copies it to the declared `.path`. Do not reach for
# `builtins.readFile` on a decrypted value anywhere in this repo — that would bake plaintext
# into a derivation and thus into the public store/binary cache.
#
# Interaction with skillsSync — there is NO activation ordering guarantee, and we do not rely on
# one. An earlier draft of this comment claimed agenix registers its installer as
# `lib.hm.dag.entryBefore [ "writeBoundary" ]` so decrypted work skills would land before
# skillsSync (entryAfter "writeBoundary") runs. That is FALSE for the pinned agenix rev
# (flake.lock: ryantm/agenix b027ee29…): its home-manager module (modules/age-home.nix) contains
# no `home.activation` / `writeBoundary` / `entryBefore` at all. On darwin it decrypts via an
# ASYNCHRONOUS `launchd.agents.activate-agenix` job (RunAtLoad = true); on linux via a
# `systemd.user.services.agenix` oneshot. Neither is ordered relative to home-manager's
# writeBoundary DAG, so a decrypted work-skill dir may not exist on disk when skillsSync
# (sync-hooks.nix, entryAfter "writeBoundary") runs — especially on a first switch.
#
# Why this is still safe: skillsSync (mcp_sync `sync-skills`) GCs ONLY the entries it recorded in
# its own manifest, and the agenix-decrypted work-skill dirs are never in that manifest — so it
# will not delete them even if they are absent when it runs. The failure mode is therefore
# transient first-switch absence (skills appear once the launchd agent finishes), not deletion.
# The safety property is the record-scoped GC, NOT ordering. Do not reintroduce an ordering claim
# without re-verifying it against the pinned agenix rev.
{
  config,
  lib,
  inputs,
  identity,
  caps,
  ...
}:
let
  home = config.home.homeDirectory;

  # Repo root, two levels up from modules/home/.
  secretsDir = ../../secrets;

  # The 25 work-only Claude skill blobs (secrets/work/claude-skills/<skill>/<relpath>.age).
  # Contract allows an explicit list in place of a fold over builtins.readDir when readDir
  # over the secrets tree is awkward (it is: subdirectories, mixed extensions, and the
  # 0700-for-scripts rule are all easier to eyeball as a flat list than to infer from readDir
  # entry types). Keep this list in sync with `find secrets/work/claude-skills -type f`.
  claudeSkillFiles = [
    { skill = "databricks-tf-v1-v2-parity-mirror"; relpath = "SKILL.md"; }
    { skill = "databricks-tf-v1-v2-parity-mirror"; relpath = "evals/evals.json"; }
    { skill = "databricks-tf-v1-v2-parity-mirror"; relpath = "evals/trigger-evals.json"; }
    { skill = "databricks-tf-v1-v2-parity-mirror"; relpath = "references/parity-map.md"; }
    { skill = "databricks-tf-v1-v2-parity-mirror"; relpath = "scripts/parity_diff.sh"; }

    { skill = "kafka-connect-sink-log-triage"; relpath = "SKILL.md"; }
    { skill = "kafka-connect-sink-log-triage"; relpath = "evals/evals.json"; }
    { skill = "kafka-connect-sink-log-triage"; relpath = "evals/trigger-evals.json"; }
    { skill = "kafka-connect-sink-log-triage"; relpath = "references/rebalance-rca.md"; }
    { skill = "kafka-connect-sink-log-triage"; relpath = "scripts/connector_triage.sh"; }

    { skill = "schema-drift-config-reconciler"; relpath = "SKILL.md"; }
    { skill = "schema-drift-config-reconciler"; relpath = "evals/evals.json"; }
    { skill = "schema-drift-config-reconciler"; relpath = "evals/trigger-evals.json"; }
    { skill = "schema-drift-config-reconciler"; relpath = "references/sources-of-truth.md"; }
    { skill = "schema-drift-config-reconciler"; relpath = "scripts/reconcile.py"; }

    { skill = "spark-job-failure-forensics"; relpath = "SKILL.md"; }
    { skill = "spark-job-failure-forensics"; relpath = "evals/evals.json"; }
    { skill = "spark-job-failure-forensics"; relpath = "evals/trigger-evals.json"; }
    { skill = "spark-job-failure-forensics"; relpath = "references/failure-patterns.md"; }
    { skill = "spark-job-failure-forensics"; relpath = "scripts/eventlog_triage.py"; }

    { skill = "terraform-precommit-gauntlet"; relpath = "SKILL.md"; }
    { skill = "terraform-precommit-gauntlet"; relpath = "evals/evals.json"; }
    { skill = "terraform-precommit-gauntlet"; relpath = "evals/trigger-evals.json"; }
    { skill = "terraform-precommit-gauntlet"; relpath = "references/hook-map.md"; }
    { skill = "terraform-precommit-gauntlet"; relpath = "scripts/gauntlet.sh"; }
  ];

  # agenix secret name must be a unique attr — flatten "<skill>/<relpath>" into one string.
  claudeSkillName = f: "claude-skill-${f.skill}-${lib.replaceStrings [ "/" ] [ "-" ] f.relpath}";

  # Everything under scripts/ is an executable (.sh / .py) per the contract; everything else
  # (SKILL.md, evals/*.json, references/*.md) is a plain read-only doc.
  claudeSkillMode = f: if lib.hasPrefix "scripts/" f.relpath then "0700" else "0600";

  claudeSkillSecrets = builtins.listToAttrs (
    map (f: {
      name = claudeSkillName f;
      value = {
        file = secretsDir + "/work/claude-skills/${f.skill}/${f.relpath}.age";
        path = "${home}/.claude/skills/${f.skill}/${f.relpath}";
        mode = claudeSkillMode f;
      };
    }) claudeSkillFiles
  );
in
{
  imports = [ inputs.agenix.homeManagerModules.default ];

  # Existing chezmoi age identity — sourced into place by bootstrap.sh (`op read ... >
  # ~/.config/chezmoi/key.txt`) before the first `darwin-rebuild switch`. Must exist before
  # activation or every age.secrets decrypt below fails.
  age.identityPaths = [ "${home}/.config/chezmoi/key.txt" ];

  age.secrets =
    # WS1 (SNUG-386) migrated the common + personal secrets off agenix:
    #   - zsh-env (~/.config/zsh/.env): its only content was the non-secret flag
    #     ENABLE_TOOL_SEARCH, now a plain profile.d fragment (common-env.zsh).
    #   - zsh-personal-env (~/.config/zsh/.personal.env): now rendered from op://
    #     templates by the opRender activation (see sync-hooks.nix).
    # ssh-config stays on agenix for now — it holds only low-sensitivity homelab
    # topology (no real secrets), and its public-vs-op disposition is a pending
    # decision, so it was deliberately deferred from WS1.
    lib.optionalAttrs (identity != "work") {
      "ssh-config" = {
        file = secretsDir + "/common/ssh-config.age";
        path = "${home}/.ssh/config";
        mode = "0600";
      };
    }
    # Work-only env + AWS overrides + the 25 gated Claude skill blobs.
    // lib.optionalAttrs (identity == "work") (
      {
        "zsh-work-env" = {
          file = secretsDir + "/work/zsh-work-env.age";
          path = "${home}/.config/zsh/.work.env";
          mode = "0600";
        };
        "aws-config-gen-overrides" = {
          file = secretsDir + "/work/aws-config-gen-overrides.json.age";
          path = "${home}/.config/aws-config-gen/overrides.json";
          mode = "0600";
        };
      }
      // lib.optionalAttrs caps.skills claudeSkillSecrets
    );
}
