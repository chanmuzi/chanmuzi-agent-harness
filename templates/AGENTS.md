# AGENTS.md
<!-- Copy this file to your project root and customize per project -->

## Shared Project Context
- This file is the project-level source of truth for shared constraints used by both Codex and Claude.
- Keep cross-agent facts here: repository layout, environment caveats, required commands, and non-negotiable rules.
- Put Claude-specific behavior in `CLAUDE.md`, but keep shared project facts aligned between the two files.
- If one file changes shared project assumptions, update the other file in the same commit.

## Project Info
- **Language**: <!-- e.g., Python 3.12, TypeScript 5.x -->
- **Framework**: <!-- e.g., Next.js 15, FastAPI, Django -->
- **Package Manager**: <!-- e.g., npm, pnpm, bun, uv, pip -->
- **Test Runner**: <!-- e.g., pytest, vitest, jest -->

## Coding Style

### Python
- Formatter/Linter: Ruff (`ruff check --fix && ruff format`)
- Type hints required for function signatures
- Use `pathlib.Path` over `os.path`
- Prefer dataclasses or Pydantic models over raw dicts
- Docstrings: Google style for public APIs only

### TypeScript / Next.js
- Formatter: Prettier, Linter: ESLint (or Biome if configured)
- Prefer `interface` over `type` for object shapes
- Use `const` by default, `let` only when reassignment is needed
- Prefer named exports over default exports
- Server Components by default; add `"use client"` only when needed

## Testing

### Requirements
- Write tests for new features and bug fixes
- Test file location: colocated (`*.test.ts`) or `tests/` directory — follow existing project convention
- Prefer integration tests over unit tests when testing API routes or data flows

### Python
```bash
pytest tests/ -v
```

### TypeScript
```bash
npm run test
# or: npx vitest run
```

## Agent Orchestration

### Claude Alignment
- `CLAUDE.md` should reference this file for shared project facts rather than redefining them differently.
- Keep project-specific workflow notes consistent across `AGENTS.md` and `CLAUDE.md`.

### When to use agents
- **code-reviewer**: After completing a feature or significant refactor
- **security-reviewer**: Before committing changes that touch auth, API keys, or user input handling
- **architect**: When planning a feature that spans 3+ files or introduces new patterns

### Agent restrictions
- Analysis agents (code-reviewer, architect) should be read-only — do not let them modify code directly
- Implementation agents should make minimal, focused changes

## Git Conventions
- Commit format: conventional commits (`feat:`, `fix:`, `refactor:`, `docs:`, `test:`, `chore:`)
- Branch naming: `feat/description`, `fix/description`, `chore/description`
- PR: summary + test plan required

## Security Checklist
Before committing, verify:
- [ ] No hardcoded secrets, API keys, or credentials
- [ ] User input is validated at system boundaries
- [ ] No `eval()`, `dangerouslySetInnerHTML`, or raw SQL without parameterization
- [ ] Sensitive files (.env, *.pem, *.key) are in .gitignore

## Environment Notes
- Document path-sensitive commands explicitly when local and server paths differ.
- Prefer environment variables or wrapper scripts over hardcoded absolute paths.
- If the project depends on MCP servers, record which parts are repo-managed and which parts each machine must configure manually.
