# Project-Level Instructions

This repo is `chanmuzi-agent-harness` — a unified harness for Claude Code and Codex CLI configuration.

Within this repository, the project-level `CLAUDE.md` and `AGENTS.md` must stay aligned.
Claude Code and Codex may enter through different filenames, but they should receive the same repository rules here.

## Structure

- `shared/` contains cross-platform helpers, shell functions, common hooks, and shared project-doc sources
- `claude/` contains Claude Code config sources for `~/.claude/`
- `codex/` contains Codex CLI config sources for `~/.codex/`
- `setup.sh` installs symlinks, patches Codex config, and installs agent extras
- `check.sh` verifies symlinks, config patches, doc sync, and required dependencies

## Repository Rules

- Shell scripts must work on both macOS (Darwin) and Linux (GNU)
- Use helper functions from `shared/lib/os.sh`
- Use `sed_inplace()` instead of raw `sed -i`
- Use `resolve_path()` instead of `readlink -f`
- Use `play_sound()` for notification sounds
- Guard macOS-only commands with `[ "$(uname -s)" = "Darwin" ]`
- Guard Linux-only commands with `[ "$(uname -s)" = "Linux" ]`
- Claude config is fully symlink-managed from `claude/`
- Codex config is split between symlink-managed files in `codex/` and patch-only updates to `~/.codex/config.toml`
- This harness fully manages Codex `mcp_servers.*` state based on `codex/mcp-servers.json` and may prune undeclared entries during setup
- Do not overwrite unrelated Codex machine state such as `projects.*` or unrelated `plugins.*`
- Keep this repo portable: never hardcode usernames or machine-specific absolute paths when a variable such as `$HOME` or `$REPO_DIR` can be used

## Project Doc Policy

- Root `CLAUDE.md` and root `AGENTS.md` are intentionally synchronized project docs for this repository
- The canonical shared content lives in `shared/project-doc.md`
- If project-level rules change, regenerate both root docs instead of editing only one
- Agent-specific global behavior still belongs in `claude/CLAUDE.md` and `codex/AGENTS.md`
- Do not assume a rule is shared unless it is present in the synchronized root project docs

## Agent Parity Policy

- Claude Code and Codex CLI do not need one-to-one feature parity; their ecosystems are different
- The harness must keep minimum policy parity for safety, git workflow, verification, and project-doc behavior
- Differences in plugins, skills, MCP servers, commands, or runtime-specific features are acceptable only when intentional
- When adding or removing a Claude-only or Codex-only capability, either add an equivalent counterpart or update `check.sh`/docs so the difference is visible
- Shared guardrails should live in `shared/hooks/` when both agents can enforce the same rule
- Agent-specific global docs may use different wording, but they must preserve the same minimum working rules: verify before completion, do not hide failures, get approval for risky/git-finalizing actions, and keep git workflow routed through the managed skills/hooks

## Verification

When modifying `setup.sh`, `check.sh`, hooks, project docs, or config files:

1. Regenerate the root project docs if the shared project doc changed
2. Run `./setup.sh` or the relevant agent-specific setup command
3. Run `./check.sh`
4. Only report completion after the checks reflect the final state
