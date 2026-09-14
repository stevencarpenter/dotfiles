# Copilot Development Workflow Instructions

## Verification

- Run the repository checks relevant to the change and any required completion
  gates. Add a focused regression check when changed nontrivial behavior lacks one.
- Inspect actual command output and exit status before reporting success. A running
  background job is incomplete; keep its output accessible and wait for completion.
- Capture complete diagnostics. Read the relevant failures before fixing them;
  filtering for success lines or truncating a pipeline can hide errors.
- Report the command, result, and material failures. Summarize routine successful
  output; attach or link long diagnostics instead of requiring the user to read them
  all. Distinguish checks that passed from checks that were not run.
- Re-run affected checks after a fix. Do not rebuild or run every language tool after
  a prose edit, and do not repeat successful checks without a new reason.
- Disable pagers for Git output with `git --no-pager`.

## Ponytail Mode (Lazy Senior Dev)

<!-- Wired from github.com/DietrichGebert/ponytail (v4.9.0 ruleset). If the
     upstream ladder changes, mirror it here by hand. -->

Before writing any code, stop at the first rung that holds:

1. Does this need to exist at all? Speculative need = skip it, say so (YAGNI)
2. Does it already exist in this codebase? Reuse the helper, util, or pattern
3. Does the standard library do it? Use it
4. Does a native platform feature cover it? Use it
5. Does an already-installed dependency solve it? Use it, never add a new one
6. Can it be one line? Make it one line
7. Only then: write the minimum code that works

The ladder runs AFTER understanding the problem: read the touched code and
trace the real flow first, then climb. Bug fix = root cause in the shared
function, not a guard per caller.

- No unrequested abstractions, no boilerplate, no new dependencies. Deletion
over addition. Fewest files, shortest working diff
- Never simplify away: trust-boundary validation, data-loss error handling,
security, accessibility, anything explicitly requested
- Mark a deliberate simplification with a known ceiling (global lock, O(n^2)
scan) with a `ponytail:` comment naming the ceiling and upgrade path
- Non-trivial logic (branch, loop, parser, money/security path) leaves ONE
runnable check behind: an assert-based demo/self-check or one small test
file. Trivial one-liners need no test
