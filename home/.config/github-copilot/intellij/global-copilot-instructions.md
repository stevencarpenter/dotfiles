# Copilot Development Workflow Instructions

## Terminal Command Execution Policy

### Ground Truth Verification

**ALWAYS verify command outputs using actual terminal results. Never assume success.**

### Command Execution Strategy

#### Background terminal definition

"Background terminal" means a dedicated IDE terminal tab or pane whose output
remains available for later inspection. It does not mean a shell job backgrounded
with `&`; `2>&1` only redirects stderr into stdout.

#### 1. Long-Running Commands (builds, tests, compilation)

```text
✅ DO: Run long tasks in a background terminal and poll its output until done
❌ DON'T: Use pipes that truncate output (tail, head) on error checking
```

**Required pattern:**

```text
1. Start the command in a background terminal
2. Read the terminal output to check progress
3. Re-read the output until the command completes
4. Show user the ACTUAL output
5. Reason about what you see
```

#### 2. Build/Compile Commands

```bash
# Correct approach (examples for various languages)
npm run build 2>&1                  # capture stderr + stdout (JavaScript/TypeScript)
python -m pytest 2>&1               # capture stderr + stdout (Python)
mvn clean verify 2>&1               # capture stderr + stdout (Java/Maven)
go test ./... 2>&1                  # capture stderr + stdout (Go)
```

**Never claim:**

- "Build passed" without showing output
- "Tests green" without showing test summary
- "No errors" without showing full error list

#### 3. Verification Requirements

After ANY code change:

1. ✅ Run build/compile command (background) → verify output
2. ✅ Run linter/formatter checks (if applicable) → verify output
3. ✅ Run test suite (background) → verify output
4. ✅ Show user what you found
5. ✅ If errors exist, show ALL errors, not summaries

### Error Handling

When you see compilation/test errors:

1. **Capture full error output** - don't truncate
2. **Count the errors** - "5 errors" means fix all 5
3. **Read the actual error messages** - don't guess
4. **Fix systematically** - one file at a time
5. **Re-verify after each fix** - re-run in a background terminal and read the output
6. **Show your reasoning** - explain what you saw and how you fixed it

### Anti-Patterns to Avoid

❌ **Never do this:**

```bash
npm test 2>&1 | tail -5             # Can't see all errors
go test ./... 2>&1 | grep -E "PASS" # Might miss failures
python -m pytest 2>&1 | head -20    # Truncates output
```

❌ **Never claim:**

- "Linter is passing" before running it
- "Tests are passing" without showing test count
- "Build succeeded" based on exit code alone

✅ **Always do this:**

```bash
# Run the command in a background terminal, then read its output to verify.
# Show user what you found, reason about the output, and act on the evidence.
```

## Language-Agnostic Pre-commit Checklist

Before claiming "done":

- [ ] Build/compile command completes without errors
- [ ] Linter/formatter checks pass (if applicable)
- [ ] Test suite runs and passes completely
- [ ] Showed user the actual command outputs
- [ ] Explained what was fixed with evidence

### Common Pitfalls (All Languages)

1. **Syntax/Type errors**: Show the actual error, don't guess the fix
2. **Import/dependency errors**: Check existing imports before adding
3. **Test failures**: Run tests, see actual failure, fix the cause
4. **Linter warnings**: Address all warnings, don't ignore them

## Git Operations

Always disable pagers:

```bash
git --no-pager diff
git --no-pager log
git --no-pager show
```

## Evidence-Based Development

### Core Principle

Show, don't tell.

When you say something works:

1. Show the command you ran
2. Show the output you got
3. Explain what it means
4. Conclude based on evidence

Example:

```text
❌ "Tests are passing"
✅ "Tests are passing - here's the output:
    test result: ok. 206 passed; 0 failed
    This shows all 206 tests in the workspace passed."
```

## User Communication

When reporting status:

- ✅ "I ran X and got Y output (showed above)"
- ✅ "I see 5 errors in the build output"
- ✅ "Here's the full error list..."
- ❌ "Everything looks good" (without evidence)
- ❌ "Build succeeded" (without showing output)

## Session Startup

At the start of any development task:

1. Understand what's being asked
2. Identify verification strategy
3. Plan to use background execution
4. Commit to showing all outputs
5. Work systematically with evidence

---

Remember: The terminal output is ground truth. Always verify. Always show your
work.

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
