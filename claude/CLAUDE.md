# CLAUDE.md

## Core Principles

### Verify Before Acting or Reporting
Before writing code, changing configuration, or reporting on external tools/platforms:
1. Search the current codebase for similar patterns or utilities
2. Check official docs or primary sources for built-in solutions
3. Only write new code when existing solutions don't fit
4. When relying on community posts, training data, or memory — verify through primary sources before presenting as fact

### Immutability
Prefer creating new objects over mutating existing ones. Use spread operators, `Object.freeze`, `map`/`filter`/`reduce` instead of in-place mutation. This applies to all languages — use the idiomatic immutable pattern for each.

### Small, Focused Files
Each file should have a single clear purpose. If a file handles multiple distinct responsibilities, split by responsibility.

### Goal-Driven Execution
When a task is ambiguous or multi-step, convert it into verifiable goals before starting:
- Define concrete success criteria (e.g., "test passes", "command exits 0", "output contains X")
- State a brief step-by-step plan with a verification check per step
- Loop: execute a step, verify, then proceed — don't batch steps and verify only at the end
- If success criteria can't be defined upfront, ask for clarification rather than guessing

### Error Handling Integrity
When encountering errors or failures, never bypass or hide them. Fixing the root cause is always the top priority.

**Never:**
- Suppress or ignore an error without fixing its cause
- Bypass failing tests by marking them as skipped, pending, or "known issue"
- Downplay failures or report them as successes
- Substitute a workaround without the user's explicit approval

**Always:**
1. Identify and fix the root cause of the error
2. If the issue persists after reasonable attempts, stop immediately and report to the user — what failed, what was tried, and why it remains unresolved
3. Verify actual behavior before reporting completion — static code-level checks alone do not count as "done"
4. Before any destructive or irreversible operation (hard reset, force push, recursive delete, data drop, etc.), preserve the current state (stash or backup), enumerate what will be lost, and get explicit user confirmation
5. Report verification results as-is — state both successes and failures explicitly

## Workflow

### Git
Use `/commit`, `/pr`, `/pr release`, `/review` skills for all git operations.
These skills handle conventions and approval steps internally — invoke them directly.
For compound requests (e.g., "commit and create PR"), invoke each corresponding skill separately and sequentially — never skip a skill by handling the operation directly.
When starting work in a git project, check if the current branch is up to date with the remote.
If behind, inform the user and suggest an appropriate action (pull, rebase, or proceed as-is).
Never squash merge — preserve commit history. Only exception is when the user explicitly requests it.

### Task Continuity
When a task involves multiple logical steps, don't stop after one step.
Briefly mention what's left or suggest the natural next step.
Keep it light — a short sentence is enough, not a full plan.

### Subagent Delegation
When writing prompts for Agent tool calls that involve shell execution or multi-step work:
- Instruct the agent to report back with: commands run, exit codes, and key output summaries
- Specify the expected deliverable format so results are actionable, not just "done"
- Prefer foreground agents when intermediate results inform your next steps

### Significant Actions
Before performing significant actions:
1. Explain what you plan to do and why
2. Describe the expected outcome

## Project-Level Instructions
For project-specific coding style, testing rules, and agent orchestration:
- Use project-level `CLAUDE.md` at the project root for project-specific rules
- Project-level CLAUDE.md overrides global settings where they conflict
