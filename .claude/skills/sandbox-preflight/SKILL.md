---
name: sandbox-preflight
description: Diagnose an observed sandbox or filesystem permission failure in this repository. Use when a command is blocked or the user asks about sandbox configuration, not before every Git or Python command.
---

# Sandbox preflight

Use the current harness permission policy and effective configuration. A command
name does not establish whether it needs additional access. Past failures on another
machine are evidence to investigate, not a blanket instruction to disable protection.

1. Read the actual error and identify the denied path, network destination, or
   permission. Distinguish sandbox denial from authentication, certificate, missing
   executable, and ordinary filesystem errors.
2. Check the effective settings. `modules/home/ai-stack.nix` seeds Claude's cache and
   working-directory permissions, but local settings and other harnesses may differ.
3. Use an already permitted location such as the task's temporary directory when
   that preserves behavior. Otherwise use the harness's supported approval mechanism
   for the specific required access. If escalation is unavailable, report the exact
   blocked operation; do not supply flags from another harness or bypass a denial.
4. Retry only after changing the condition that caused failure. Check whether a
   mutating command partially completed before repeating it.

Do not change global permissions, reinstall tooling, or rebuild the system merely
because a command failed. Those actions require a demonstrated cause and appropriate
task scope. Keep successful independent reads when a parallel operation fails.
