# INPUTS

Read these files in order:

1. `CLAUDE.md` - Project-specific patterns, conventions, and commands. This is your operating manual.
2. `__PRD_PATH__` - The product requirements document containing all user stories.
3. `__PROGRESS_FILE__` - Start with the **Codebase Patterns** section at the top. These are consolidated learnings from previous iterations. Read them before doing anything else. Then read the full log to understand recent work.

The last 10 RALPH commits (SHA, date, full message) have been appended to the bottom of this prompt by ralph.sh. Review them to understand what work has been done recently and avoid duplicating effort.

4. `codebase-snapshot.md` — If this file exists, read it. It contains a deterministic snapshot of the codebase generated between iterations: file tree, public exports, import graph, test counts, and alerts. Compare the import graph against `__SPECS_DIR__/architecture.md` dependency rules. Flag any violations in your iteration notes.

5. `__SPECS_DIR__/architecture.md` — If this file contains only HTML comment placeholders (`<!-- Generated from PRD`), populate it before starting story work:
   - Read `__PRD_PATH__` and identify the modules, their responsibilities, and dependency direction
   - Fill in Modules, Dependency Rules, and Hard Constraints with concrete entries
   - Keep it under 20 lines total
   - Commit as `RALPH: chore: populate architecture.md from PRD` before starting the first story
     If architecture.md is already populated, read it and check planned changes against the dependency rules.

6. `.gitignore` — On the first iteration, review `.gitignore` against the PRD's tech stack. The template covers common patterns (node_modules, .next, .env, data/, coverage, etc.). If the PRD specifies additional technology (e.g. Python venv, Rust target/, Go bin/, specific database files), append the relevant patterns. Do this in the same commit as the architecture.md population. Do NOT remove existing entries — only add missing ones.

# TASK SELECTION

Pick the **highest priority** user story in `__PRD_PATH__` where `passes: false`.

Make each task the smallest possible unit of work. We don't want to outrun our headlights. One small, well-tested change per iteration.

If there are **no remaining stories** with `passes: false`, emit `<promise>COMPLETE</promise>` and stop.

If the PRD includes an architectural fitness test story (one that verifies module boundaries, import direction, or code structure constraints by writing tests that analyse source files), schedule it after core modules exist but before the final third of stories. This gives it enough code to check while leaving time for cleanup if violations are found.

ONE task per iteration - this is non-negotiable. Do not batch. Do not "quickly knock out" a second story. One story, done properly, verified, committed.

# EXPLORATION

Explore the repo and fill your context window with relevant information that will allow you to complete the task.

If `codebase-snapshot.md` exists, check its import graph against `__SPECS_DIR__/architecture.md` dependency rules. If you spot violations in modules you're about to touch, fix them as part of this iteration.

Read existing tests to understand testing patterns before writing new ones. Look at naming conventions, assertion styles, test structure, and how mocks (if any) are used.

If this task involves writing code, read the TDD skill at `__SKILLS_DIR__/tdd/SKILL.md` to internalise the methodology before proceeding.

Understand the shape of the code you will be changing. Read the files you will modify. Read their tests. Read their callers. Do not start coding until you understand the local context.

Check which skill reference files are relevant to this story. Scan the filenames in `__SKILLS_DIR__/tdd/` and read any that relate to your planned approach. Examples: if your story involves dependency injection or system boundaries, read `mocking.md`. If it involves module boundaries or public API design, read `deep-modules.md` and `interface-design.md`. If it involves restructuring existing code, read `refactoring.md`. If none are relevant, skip this step - but if you find yourself reaching for a pattern you're unsure about, check the skill files before inventing your own.

If this story requires changing a shared function's signature (adding parameters, changing return types), plan the ripple before writing the first test. List all callers and test files that will need updating. Budget the caller updates into your GREEN step rather than fixing them reactively after tests break.

Before planning your approach, quickly scan the modules you'll be touching. Check: are any functions you'll modify already over ~50 lines? Is the function signature already at 4+ parameters? Is data being threaded through multiple calls unchanged? If so, plan a refactor as part of this iteration's work rather than adding to the debt.

# RED (Write Failing Test)

Write ONE failing test for the current task.

**Rules:**

- The test must describe **behaviour through the public interface**, not implementation details. Test what the code does, not how it does it.
- Write ONE test confirming ONE thing. If the test name contains "and", split it.
- The test name must clearly describe the expected behaviour.
- Use real code. Mock only at **system boundaries** (external APIs, databases, time, file system). Never mock your own code.
- Do NOT write multiple tests upfront. That is horizontal slicing. Write one test, make it pass, then write the next.

**Verify RED - Watch It Fail:**

Run the test. This step is **mandatory. Never skip.**

Confirm:

- The test **fails** (not errors - fails)
- The failure message is what you expect
- It fails because the **feature is missing**, not because of a typo or import error

If the test passes immediately, you are testing existing behaviour. Fix the test.

If the test errors, fix the error and re-run until it fails correctly.

# GREEN (Minimal Implementation)

1. You have ONE red test. Write the smallest change that makes it pass.
2. Run the test. If it passes, STOP. Do not write any more production code.
3. Return to RED. Write the next failing test.
4. Only after the new test fails may you write more production code.

This is not advice — it is the process. There is no step where you write production code without a failing test demanding it.

If your next RED test passes immediately without code changes, that means your previous GREEN was too large. Once per story is acceptable. Twice or more means you are not following the procedure above — go back and write smaller GREEN steps.

**Verify GREEN - Watch It Pass:**

Run the test. Confirm it passes. Then run **ALL** tests. Confirm everything is green.

If the test still fails, fix the **implementation** - not the test.

If other tests broke, fix them now.

# REFACTOR

After all tests are green, look for refactor candidates:

- Duplication
- Long methods
- Shallow modules
- Feature envy
- Primitive obsession
- Unclear names

Check the following triggers against the code you've written or modified this iteration. If any are true, refactor before committing:

- Any function exceeds ~50 lines - extract helpers
- Any function signature has more than 4 parameters - convert trailing params to an options/config object
- The same data (e.g. theme, config, logger) is threaded through 3+ function calls unchanged - introduce a context object
- You have 3+ custom error classes with no shared base - consider a base error class
- You're copy-pasting a pattern for the third time - extract it

If a needed refactor is too large to do safely within this iteration, note it as technical debt in **PROGRESS_FILE** under a "Technical Debt" heading and flag it in RALPH_STATUS RECOMMENDATION field.

**Never refactor while RED.** Get to GREEN first.

Run tests after **each** refactor step. If anything goes red, undo the refactor and try again.

If this task has multiple behaviours to implement, loop back to RED for the next behaviour. If the task is complete, continue to FEEDBACK LOOPS.

# FEEDBACK LOOPS

Before committing, run the full verification suite:

```bash
__TEST_CMD__
__TYPECHECK_CMD__
__LINT_CMD__
```

**From the Iron Law of Verification:**

If you have not run the verification command **in this message**, you cannot claim it passes. NO COMPLETION CLAIMS WITHOUT FRESH VERIFICATION EVIDENCE.

The Gate Function:

1. IDENTIFY: What command proves this claim?
2. RUN: Execute the full command (fresh, complete)
3. READ: Full output, check exit code, count failures
4. VERIFY: Does output confirm the claim?
5. ONLY THEN: Make the claim

If anything fails, fix it before committing. Do NOT commit broken code.

# COMMIT

Update the PRD first: set `passes: true` for the completed story in `__PRD_PATH__`. This must be included in the same commit.

Commit ALL changes with the message format:

```
RALPH: feat: [US-XXX] - [Story Title]

Task completed: <brief description>
Key decisions: <any architectural or design decisions>
Files changed: <list>
Blockers/notes: <anything the next iteration should know>
```

# PROGRESS

Append to `__PROGRESS_FILE__` (never replace existing content):

```
## [Date/Time] - [Story ID]
- What was implemented
- Files changed
- **Learnings for future iterations:**
  - Patterns discovered
  - Gotchas encountered
  - Useful context
---
```

If you discover a **reusable pattern** that future iterations should know about, add it to the `## Codebase Patterns` section at the **top** of `__PROGRESS_FILE__`. Only add patterns that are general and reusable, not story-specific details.

Before appending your progress entry, check the length of **PROGRESS_FILE**. If it's getting long (over ~100 lines), compress it: summarise all completed stories older than the last 5 into a "Completed Work Summary" section at the top (max 20 lines). Keep the Codebase Patterns section, the Technical Debt section (if any), and the last 5 detailed iteration entries. Remove the detailed entries for older iterations. The goal is to keep **PROGRESS_FILE** informative without growing unbounded.

Check if any directories you edited have nearby `CLAUDE.md` files. If you discovered something future iterations should know (API conventions, gotchas, dependencies between files, testing approaches), add it there.

# RALPH_STATUS

At the end of your response, ALWAYS include this status block:

```
---RALPH_STATUS---
STATUS: IN_PROGRESS | COMPLETE | BLOCKED
CURRENT_STORY: US-XXX
TASKS_COMPLETED_THIS_LOOP: <number>
FILES_MODIFIED: <number>
TESTS_STATUS: PASSING | FAILING | NOT_RUN
WORK_TYPE: IMPLEMENTATION | TESTING | DOCUMENTATION | REFACTORING
EXIT_SIGNAL: false | true
RECOMMENDATION: <one line summary of what to do next>
---END_RALPH_STATUS---
```

## When to set EXIT_SIGNAL: true

Set EXIT_SIGNAL to **true** when ALL of these conditions are met:

1. All stories in the PRD have `passes: true`
2. All tests are passing (or no tests exist for valid reasons)
3. No errors or warnings in the last execution
4. All requirements from the PRD are implemented
5. You have nothing meaningful left to implement

## Exit Scenarios (Specification by Example)

Ralph's circuit breaker and response analyser use these scenarios to detect completion. Each scenario shows the exact conditions and expected behaviour.

### Scenario 1: Successful Project Completion

**Given**:

- All stories in **PRD_PATH** have `passes: true`
- Last test run shows all tests passing
- No errors in recent output
- All requirements from the PRD are implemented

**When**: You evaluate project status at end of loop

**Then**: You must output:

```
---RALPH_STATUS---
STATUS: COMPLETE
TASKS_COMPLETED_THIS_LOOP: 1
FILES_MODIFIED: 1
TESTS_STATUS: PASSING
WORK_TYPE: DOCUMENTATION
EXIT_SIGNAL: true
RECOMMENDATION: All requirements met, project ready for review
---END_RALPH_STATUS---
```

**Ralph's Action**: Detects EXIT_SIGNAL=true, gracefully exits loop with success message

### Scenario 2: Test-Only Loop Detected

**Given**:

- Last 3 loops only executed tests (bun run test, etc.)
- No new files were created
- No existing files were modified
- No implementation work was performed

**When**: You start a new loop iteration

**Then**: You must output:

```
---RALPH_STATUS---
STATUS: IN_PROGRESS
TASKS_COMPLETED_THIS_LOOP: 0
FILES_MODIFIED: 0
TESTS_STATUS: PASSING
WORK_TYPE: TESTING
EXIT_SIGNAL: false
RECOMMENDATION: All tests passing, no implementation needed
---END_RALPH_STATUS---
```

**Ralph's Action**: Increments test_only_loops counter, exits after 3 consecutive test-only loops

### Scenario 3: Stuck on Recurring Error

**Given**:

- Same error appears in last 5 consecutive loops
- No progress on fixing the error
- Error message is identical or very similar

**When**: You encounter the same error again

**Then**: You must output:

```
---RALPH_STATUS---
STATUS: BLOCKED
TASKS_COMPLETED_THIS_LOOP: 0
FILES_MODIFIED: 2
TESTS_STATUS: FAILING
WORK_TYPE: DEBUGGING
EXIT_SIGNAL: false
RECOMMENDATION: Stuck on [error description] - human intervention needed
---END_RALPH_STATUS---
```

**Ralph's Action**: Circuit breaker detects repeated errors, opens circuit after 5 loops

### Scenario 4: No Work Remaining

**Given**:

- All tasks in the PRD are complete
- You analyse the PRD and find nothing new to implement
- Code quality is acceptable
- Tests are passing

**When**: You search for work to do and find none

**Then**: You must output:

```
---RALPH_STATUS---
STATUS: COMPLETE
TASKS_COMPLETED_THIS_LOOP: 0
FILES_MODIFIED: 0
TESTS_STATUS: PASSING
WORK_TYPE: DOCUMENTATION
EXIT_SIGNAL: true
RECOMMENDATION: No remaining work, all PRD stories implemented
---END_RALPH_STATUS---
```

**Ralph's Action**: Detects completion signal, exits loop immediately

### Scenario 5: Making Progress

**Given**:

- Tasks remain in the PRD with `passes: false`
- Implementation is underway
- Files are being modified
- Tests are passing or being fixed

**When**: You complete a task successfully

**Then**: You must output:

```
---RALPH_STATUS---
STATUS: IN_PROGRESS
TASKS_COMPLETED_THIS_LOOP: 1
FILES_MODIFIED: 7
TESTS_STATUS: PASSING
WORK_TYPE: IMPLEMENTATION
EXIT_SIGNAL: false
RECOMMENDATION: Continue with next task from PRD
---END_RALPH_STATUS---
```

**Ralph's Action**: Continues loop, circuit breaker stays CLOSED (normal operation)

### Scenario 6: Blocked on External Dependency

**Given**:

- Task requires external API, library, or human decision
- Cannot proceed without missing information
- Have tried reasonable workarounds

**When**: You identify the blocker

**Then**: You must output:

```
---RALPH_STATUS---
STATUS: BLOCKED
TASKS_COMPLETED_THIS_LOOP: 0
FILES_MODIFIED: 0
TESTS_STATUS: NOT_RUN
WORK_TYPE: IMPLEMENTATION
EXIT_SIGNAL: false
RECOMMENDATION: Blocked on [specific dependency] - need [what's needed]
---END_RALPH_STATUS---
```

**Ralph's Action**: Logs blocker, may exit after multiple blocked loops

## What NOT to do

- Do NOT continue with busy work when EXIT_SIGNAL should be true
- Do NOT run tests repeatedly without implementing new features
- Do NOT refactor code that is already working fine
- Do NOT add features not in the PRD
- Do NOT forget to include the status block (Ralph depends on it!)

# Protected Files (DO NOT MODIFY)

The following files and directories are part of Ralph's infrastructure. NEVER delete, move, rename, or overwrite these under any circumstances:

- `__ENGINE_DIR__/` (entire directory - prompt.md, ralph.sh, snapshot.sh)
- `__SPECS_DIR__/` (entire directory - architecture.md, prd.json structure)
- `__SKILLS_DIR__/` (entire directory and all contents)
- `__PROGRESS_FILE__` (append only - never replace, never delete content)
- `CLAUDE.md` (update Codebase Patterns section only - never delete existing content)

When performing cleanup, refactoring, or restructuring tasks: these files are NOT part of your project code. They are Ralph's internal control files that keep the development loop running. Deleting them will break Ralph and halt all autonomous development.

# Final Rules

ONLY WORK ON A SINGLE TASK.

Keep CI green.

If anything blocks your completion of the task, output `<promise>ABORT</promise>`.

Using "should", "probably", "seems to" before running verification is a RED FLAG. Run the command first, then make claims.
