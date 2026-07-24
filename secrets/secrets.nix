# agenix recipients file.
#
# This file is consumed ONLY by the `agenix` CLI (`agenix -e <path>`) when creating or
# rotating a secret — it tells the CLI which public keys to re-encrypt a secret's plaintext
# for. It is NOT read at `darwin-rebuild switch` / home-manager activation time: decryption
# there is driven entirely by modules/home/secrets.nix's `age.identityPaths`, matched against
# whichever recipient(s) a given blob was actually encrypted for. In other words: every
# ciphertext under secrets/ today was produced by plain `age -e -r <recipient>` (via chezmoi),
# not by agenix, and decrypts fine with no involvement from this file. This file only starts
# mattering the day someone runs `agenix -e` for the first time in this repo.
#
# Today there is exactly one work recipient in play — see docs/superpowers/plans/
# 2026-07-02-work-decoupling-and-1password-secret-migration.md for the plan to eventually
# move work secrets onto a distinct, vault-scoped recipient. Personal and common ciphertexts
# were removed after their 1Password-rendered replacements were proven byte-for-byte against
# the old values; every remaining blob is work-only and uses this recipient set.
let
  # The existing age recipient's public key. Corresponds to the identity kept at
  # ~/.config/age/keys.txt (sourced from 1Password by bootstrap.sh). Do not change this
  # value without also re-encrypting every blob under secrets/ to the new key(s) — see
  # secrets/README.md "Rotating a secret's recipients".
  carpenter = "age1462h0ed4ufkjrq0wu326l30c8hay9uewlsaudk89mgqjc5540vrqacejsz";

  recipients = [ carpenter ];

  # Keep this list in sync with modules/home/secrets.nix's claudeSkillFiles — both enumerate
  # the same 25 blobs under secrets/work/claude-skills/, for two different purposes (this one
  # for agenix-CLI recipients, that one for home-manager decrypt targets).
  claudeSkillFiles = [
    {
      skill = "databricks-tf-v1-v2-parity-mirror";
      relpath = "SKILL.md";
    }
    {
      skill = "databricks-tf-v1-v2-parity-mirror";
      relpath = "evals/evals.json";
    }
    {
      skill = "databricks-tf-v1-v2-parity-mirror";
      relpath = "evals/trigger-evals.json";
    }
    {
      skill = "databricks-tf-v1-v2-parity-mirror";
      relpath = "references/parity-map.md";
    }
    {
      skill = "databricks-tf-v1-v2-parity-mirror";
      relpath = "scripts/parity_diff.sh";
    }

    {
      skill = "kafka-connect-sink-log-triage";
      relpath = "SKILL.md";
    }
    {
      skill = "kafka-connect-sink-log-triage";
      relpath = "evals/evals.json";
    }
    {
      skill = "kafka-connect-sink-log-triage";
      relpath = "evals/trigger-evals.json";
    }
    {
      skill = "kafka-connect-sink-log-triage";
      relpath = "references/rebalance-rca.md";
    }
    {
      skill = "kafka-connect-sink-log-triage";
      relpath = "scripts/connector_triage.sh";
    }

    {
      skill = "schema-drift-config-reconciler";
      relpath = "SKILL.md";
    }
    {
      skill = "schema-drift-config-reconciler";
      relpath = "evals/evals.json";
    }
    {
      skill = "schema-drift-config-reconciler";
      relpath = "evals/trigger-evals.json";
    }
    {
      skill = "schema-drift-config-reconciler";
      relpath = "references/sources-of-truth.md";
    }
    {
      skill = "schema-drift-config-reconciler";
      relpath = "scripts/reconcile.py";
    }

    {
      skill = "spark-job-failure-forensics";
      relpath = "SKILL.md";
    }
    {
      skill = "spark-job-failure-forensics";
      relpath = "evals/evals.json";
    }
    {
      skill = "spark-job-failure-forensics";
      relpath = "evals/trigger-evals.json";
    }
    {
      skill = "spark-job-failure-forensics";
      relpath = "references/failure-patterns.md";
    }
    {
      skill = "spark-job-failure-forensics";
      relpath = "scripts/eventlog_triage.py";
    }

    {
      skill = "terraform-precommit-gauntlet";
      relpath = "SKILL.md";
    }
    {
      skill = "terraform-precommit-gauntlet";
      relpath = "evals/evals.json";
    }
    {
      skill = "terraform-precommit-gauntlet";
      relpath = "evals/trigger-evals.json";
    }
    {
      skill = "terraform-precommit-gauntlet";
      relpath = "references/hook-map.md";
    }
    {
      skill = "terraform-precommit-gauntlet";
      relpath = "scripts/gauntlet.sh";
    }
  ];

  otherPaths = [
    "work/zsh-work-env.age"
  ];

  skillPaths = map (f: "work/claude-skills/${f.skill}/${f.relpath}.age") claudeSkillFiles;
in
builtins.listToAttrs (
  map (p: {
    name = p;
    value = {
      publicKeys = recipients;
    };
  }) (otherPaths ++ skillPaths)
)
