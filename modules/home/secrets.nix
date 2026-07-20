# Work secrets: agenix wired to the carry-verbatim age identity.
#
# Design (see phase1-results.json smes[1] for the full rationale): agenix is the carry-verbatim
# bridge for the Nix port. Only the work identity declares age secrets and an
# identity path; personal secrets render directly from 1Password via op-render.
# No work blob was re-encrypted during the port, so this module MUST NOT run
# `age -e` or otherwise touch plaintext.
#
# Store-safety: age.secrets.<name>.file is a ciphertext path — it enters the (world-readable)
# nix store safely because it stays encrypted there. agenix's activation script decrypts each
# secret to config.age.secretsDir (a user-owned, activation-managed path outside the store,
# mode 0400 by default) and symlinks/copies it to the declared `.path`. Do not reach for
# `builtins.readFile` on a decrypted value anywhere in this repo — that would bake plaintext
# into a derivation and thus into the public store/binary cache.
#
# Darwin ordering: the pinned agenix Home Manager module normally decrypts via
# an asynchronous RunAtLoad launchd agent. That cannot safely feed activation
# consumers: on a first switch or ciphertext rotation they can observe missing
# or stale files. For the work identity below, the async agent is disabled and
# its exact generated mounting script runs synchronously as the `agenixDecrypt`
# Home Manager activation node. Consumers depend on that node in sync-hooks.nix.
{
  config,
  lib,
  inputs,
  pkgs,
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

  synchronousAgenix = identity == "work" && pkgs.stdenv.hostPlatform.isDarwin;
  agenixMountingScript = builtins.head config.launchd.agents.activate-agenix.config.ProgramArguments;
in
{
  imports = [ inputs.agenix.homeManagerModules.default ];

  # Existing work age identity — sourced into place by bootstrap.sh before a
  # work-mac switch. Personal evaluates to an empty identity-path list.
  age.identityPaths =
    if identity == "work" then [ "${home}/.config/age/keys.txt" ] else lib.mkForce [ ];

  # Replace agenix's asynchronous Darwin job with the same generated script in
  # the Home Manager activation DAG. Decryption failure is fatal: continuing
  # would let dependent generators consume missing or stale secrets.
  launchd.agents.activate-agenix.enable = lib.mkIf synchronousAgenix (lib.mkForce false);
  home.activation.agenixDecrypt = lib.mkIf synchronousAgenix (
    lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      echo "Decrypting agenix work secrets synchronously"
      if ! ${agenixMountingScript}; then
        echo "agenix work-secret decryption failed; refusing dependent activation hooks" >&2
        exit 1
      fi
    ''
  );

  age.secrets =
    # WS1 (SNUG-386) migrated ALL common + personal secrets off agenix to
    # op-render (op:// templates, see modules/home/sync-hooks.nix opRender):
    #   - zsh-env (~/.config/zsh/.env): only content was the non-secret flag
    #     ENABLE_TOOL_SEARCH, now a plain profile.d fragment (common-env.zsh).
    #   - zsh-personal-env (~/.config/zsh/.personal.env): op:// template.
    #   - ssh-config (~/.ssh/config): op:// template — the i9 tailnet host comes
    #     from op://Homelab/I9/tailnet_hostname so it never lands in this public
    #     repo.
    # The three superseded common/personal ciphertexts were deleted only after
    # every value was verified against a successful 1Password render.
    # The personal identity now declares ZERO age.secrets; work is unchanged.
    lib.optionalAttrs (identity == "work") (
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
