# CLAUDE.md
<!-- Copy this file to your project root and customize per project -->

This file defines Claude-specific behavior for the project.
Shared project facts should stay aligned with `AGENTS.md`.

## Shared Project Context
- Read `AGENTS.md` first for repository structure, environment constraints, required commands, and non-negotiable project rules.
- Do not silently diverge from `AGENTS.md` on shared project facts.
- If a shared project rule changes here, update `AGENTS.md` in the same commit.

## Workflow
- Before significant actions, explain the plan briefly and clearly.
- Keep progress updates short and useful.
- When a task spans multiple steps, mention the natural next step without over-planning.

## Project Overrides
- Record Claude-only workflow preferences here.
- Keep shared path, environment, and test constraints in `AGENTS.md`.
- If the project uses MCP servers, document Claude-only usage notes here and keep machine-specific setup out of the repo unless it is portable.
