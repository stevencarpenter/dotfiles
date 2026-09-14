---
name: branch-first-pr
description: Commit and publish this repository's requested changes on a feature branch, or diagnose commits made on the default branch. Use for commit, push, PR, or protected-branch recovery requests.
---

# Branch-first PR

Inspect `git status`, the staged and unstaged diff, the current branch, and
`refs/remotes/origin/HEAD`. Confirm the actual base before creating a branch.
In a Jujutsu-managed checkout, use its configured workflow instead of moving Git
HEAD directly. Preserve unrelated work.

For this Git checkout:

1. Create a feature branch before committing if the current branch is the default
   branch. Reuse an appropriate existing feature branch.
2. Stage only the intended changes. Run the relevant checks and configured hooks.
3. Use a concise Conventional Commit message without attribution trailers. Existing
   commit-message hooks own normalization; do not add another stripping mechanism.
4. When publication is requested, push the feature branch and use the configured
   `gh-axi` skill to create or update its PR. Use a body file for multiline text.
   Include the behavior change, relevant paths, and actual validation evidence.

Keep independently reviewable concerns separate when combining them would obscure
the change. Do not split a cohesive fix into artificial PRs or publish a local-only
request. If the branch has no difference from the base, report that fact instead of
creating an empty commit or unrelated PR.

If commits already exist on the default branch, preserve them by creating a feature
branch at the current commit. Inspect ancestry before changing any other reference.
Do not force-move the default branch, reset, or delete work without explicit scope
and a verified recovery path. A guardrail rejection is not permission to perform the
same operation through another command.

Use current harness permissions for network operations. For a demonstrated sandbox
failure, consult [sandbox-preflight](../sandbox-preflight/SKILL.md); do not disable
the sandbox solely because the command uses GitHub.
