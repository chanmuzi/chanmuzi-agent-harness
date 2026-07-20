# AGENTS.md

# Project-Level Instructions

This repo is `chanmuzi-agent-harness` — a unified harness for Claude Code and Codex CLI configuration.

This file is the single canonical project doc (SSoT) for this repository.
Codex reads it directly; Claude Code enters through root `CLAUDE.md`, which imports this file via `@AGENTS.md`.
Both agents receive the same repository rules here.

## Structure

- `shared/` contains cross-platform helpers, shell functions, and common hooks
- `claude/` contains Claude Code config sources for `~/.claude/`
- `codex/` contains Codex CLI config sources for `~/.codex/`
- `setup.sh` installs symlinks, patches Codex config, and installs agent extras
- `check.sh` verifies symlinks, config patches, the project-doc adapter, and required dependencies

## Repository Rules

- Shell scripts must work on both macOS (Darwin) and Linux (GNU)
- Use helper functions from `shared/lib/os.sh`
- Use `sed_inplace()` instead of raw `sed -i`
- Use `resolve_path()` instead of `readlink -f`
- Use `play_sound()` for notification sounds
- Guard macOS-only commands with `[ "$(uname -s)" = "Darwin" ]`
- Guard Linux-only commands with `[ "$(uname -s)" = "Linux" ]`
- Claude config is fully symlink-managed from `claude/`
- Two Claude accounts share this config: `cc` (personal, `~/.claude`) and `cc-up` (work, `~/.claude-upstage`); `setup.sh` symlinks the same sources into both
- Never hardcode `~/.claude` in `claude/settings.json` — use `${CLAUDE_CONFIG_DIR:-$HOME/.claude}` so each account resolves its own directory
- Codex config is split between symlink-managed files in `codex/` and patch-only updates to `~/.codex/config.toml`
- This harness fully manages Codex `mcp_servers.*` state based on `codex/mcp-servers.json` and may prune undeclared entries during setup
- Do not overwrite unrelated Codex machine state such as `projects.*` or unrelated `plugins.*`
- Keep this repo portable: never hardcode usernames or machine-specific absolute paths when a variable such as `$HOME` or `$REPO_DIR` can be used

## Project Doc Policy

- Root `AGENTS.md` (this file) is the single canonical project doc for this repository
- Root `CLAUDE.md` is a one-line adapter (`@AGENTS.md`) so Claude Code imports the same rules — never duplicate shared content there
- If a Claude-only project rule is ever needed, add it below the import line in `CLAUDE.md`; everything shared belongs here
- Agent sessions should start at the repository root; per-directory child docs and `AGENTS.override.md` files are not used in this repository
- Agent-specific global behavior still belongs in `claude/CLAUDE.md` and `codex/AGENTS.md`
- Rationale and loading-model details: `docs/decisions/2026-07-agent-instruction-loading.md`

## Decision Records

- Durable decisions about this harness live in `docs/decisions/`, named `YYYY-MM-<topic>.md`
- Before adding, replacing, or removing a tool or capability, read the relevant record there first — it may already document why an option was rejected
- Write a new record when a decision changes what this harness ships, especially when a capability is **intentionally absent**; a missing capability is invisible in the code and will otherwise be re-investigated from scratch
- Records capture the reasoning (context, alternatives considered, consequences), not the diff; the diff belongs in the PR

## Agent Parity Policy

- Claude Code and Codex CLI do not need one-to-one feature parity; their ecosystems are different
- The harness must keep minimum policy parity for safety, git workflow, verification, and project-doc behavior
- Differences in plugins, skills, MCP servers, commands, or runtime-specific features are acceptable only when intentional
- When adding or removing a Claude-only or Codex-only capability, either add an equivalent counterpart or update `check.sh`/docs so the difference is visible
- Shared guardrails should live in `shared/hooks/` when both agents can enforce the same rule
- Agent-specific global docs may use different wording, but they must preserve the same minimum working rules: verify before completion, do not hide failures, get approval for risky/git-finalizing actions, and keep git workflow routed through the managed skills/hooks

## Verification

When modifying `setup.sh`, `check.sh`, hooks, project docs, or config files:

1. If project rules changed, edit root `AGENTS.md` only — `CLAUDE.md` stays a single `@AGENTS.md` adapter line
2. Run `./setup.sh` or the relevant agent-specific setup command
3. Run `./check.sh`
4. Only report completion after the checks reflect the final state
