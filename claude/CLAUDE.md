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
- Define concrete success criteria (e.g., "test passes", "command exits with code 0", "output contains X")
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

### Async Work Tracking
These rules apply only when work runs in the background (background shell, background sub-agent, separate session); they change nothing for ordinary foreground work. For background sub-agents, check state via `TaskList`/`TaskGet` (plus a `ScheduleWakeup` fallback) instead of a file watch.

Completion notifications are not guaranteed to arrive — a known Claude Code limitation, worst when several tasks finish around the same time. A dropped notification with no other wake mechanism leaves the session idle until the user speaks. Treat notifications as a bonus signal, never the sole mechanism.

- Prefer foreground execution when the result informs your next step.
- **Never end a turn with unwatched background work**: before ending, arm at least one wake mechanism sized to outlive the job — `Monitor` with `persistent: true` (or a timeout beyond the expected duration), a `ScheduleWakeup` fallback, or the `/loop` skill — and state how you will know it finished. "I'll wait for the notification" alone is not acceptable.
- Send background shell output to a log file with an exit marker (`cmd > "$LOG" 2>&1; status=$?; echo "exit=$status" >> "$LOG"; exit "$status"`, with `$LOG` under the session scratchpad or a temp dir, never the repo working tree) rather than pipes, so output and exit status stay visible and failures keep their exit code.
- Keep watch events coarse (milestones, errors, completion) — not per-line.
- When work completes, verify the actual result (exit marker, output) before acting on or reporting it.

### Wrap-Up Cleanup
Arming a watcher is half the job; tearing it down is the other half. A task is not done while background work this session started is still running.

- Before reporting completion, inventory what this session started or created: background sub-agents (`TaskList`), `Monitor`s, background shells and other launched processes (dev servers, watchers), cron jobs (`CronList`) and pending `ScheduleWakeup`s, worktrees, local and remote branches, and temporary files (scratch notes, logs, drafts).
- Stop a self-started item without asking only when its purpose is verifiably fulfilled — the investigation returned its final result, the watched job hit its exit marker, the awaited condition resolved. Name what you stopped in one line of the report.
- Branches and worktrees count as fulfilled only once their work is merged (confirm the PR state or `git branch --merged`). Keep any branch with unmerged commits, an open PR, or that the user still needs.
- Temporary files count as fulfilled only when they are outside the deliverable and nothing still reads them; never delete files the user or another process created.
- If completion is not verified, treat the item as in progress: never stop it on your own, since stopping mid-run can leave work in an unexpected half-done state.
- For anything in progress, ambiguous, or not started by this session (other sessions, user-launched processes), list it and propose cleanup; stop it only after the user approves. Never stop another session's work on your own.
- When the user asks to wrap up or clean up the session, run the full inventory, stop what they approve, re-check that nothing remains, and report what was stopped and what was left (with the reason).
- Clean up before declaring done: never say the work is finished while self-started background work is still running.

### Mixed Messages — Answer Before Acting
When one message mixes directives with questions or doubts, address every question first;
open questions are never dropped because a directive was also present.
Start a directive only if its outcome does not depend on any unanswered item — a question is not a go-ahead.
If a question is a decision the user must make (approach, scope, trade-off), your own answer does not unblock it; wait for the user.

### Significant Actions
Before performing significant actions:
1. Explain what you plan to do and why
2. Describe the expected outcome

## Project-Level Instructions
For project-specific coding style, testing rules, and agent orchestration:
- Use project-level `CLAUDE.md` at the project root for project-specific rules
- Project-level CLAUDE.md overrides global settings where they conflict
