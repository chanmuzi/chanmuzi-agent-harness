# AGENTS.md
<!-- Copy this file to your project root and customize per project -->

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
