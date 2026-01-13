# Copilot Development Workflow Instructions

## Terminal Command Execution Policy

### Ground Truth Verification
**ALWAYS verify command outputs using actual terminal results. Never assume success.**

### Command Execution Strategy

#### 1. Long-Running Commands (builds, tests, compilation)
```
✅ DO: Use isBackground=true and verify with get_terminal_output
❌ DON'T: Use pipes that truncate output (tail, head) on error checking
```

**Required pattern:**
```
1. run_in_terminal with isBackground=true
2. get_terminal_output to check progress
3. Repeat get_terminal_output until complete
4. Show user the ACTUAL output
5. Reason about what you see
```

#### 2. Build/Compile Commands
```bash
# Correct approach (examples for various languages)
npm run build 2>&1                  # isBackground=true (JavaScript/TypeScript)
python -m pytest 2>&1               # isBackground=true (Python)
mvn clean verify 2>&1               # isBackground=true (Java/Maven)
go test ./... 2>&1                  # isBackground=true (Go)
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
5. **Re-verify after each fix** - background + get_terminal_output
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
# Background execution
run_in_terminal(isBackground=true)

# Then verify
get_terminal_output(id)

# Show user what you found
# Reason about the output
# Take action based on evidence
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

**Core principle: Show, don't tell**

When you say something works:
1. Show the command you ran
2. Show the output you got
3. Explain what it means
4. Conclude based on evidence

Example:
```
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

**Remember: The terminal output is ground truth. Always verify. Always show your work.**
