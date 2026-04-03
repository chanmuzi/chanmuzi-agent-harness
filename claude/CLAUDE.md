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

## Workflow

### Git
Use `/commit`, `/pr`, `/pr release`, `/review` skills for all git operations.
These skills handle conventions and approval steps internally — invoke them directly.
When starting work in a git project, check if the current branch is up to date with the remote.
If behind, inform the user and suggest an appropriate action (pull, rebase, or proceed as-is).
Never squash merge — preserve commit history. Only exception is when the user explicitly requests it.

### Task Continuity
When a task involves multiple logical steps, don't stop after one step.
Briefly mention what's left or suggest the natural next step.
Keep it light — a short sentence is enough, not a full plan.

### Significant Actions
Before performing significant actions:
1. Explain what you plan to do and why
2. Describe the expected outcome

## Project-Level Instructions
For project-specific coding style, testing rules, and agent orchestration:
- Use project-level `CLAUDE.md` at the project root for project-specific rules
- Project-level CLAUDE.md overrides global settings where they conflict

