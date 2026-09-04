# AGENTS.md

# Project-Level Instructions

This repo is `chanmuzi-agent-harness` — a unified harness for Claude Code and Codex CLI configuration.

This file is the single canonical project doc (SSoT) for this repository.
Codex reads it directly; Claude Code enters through root `CLAUDE.md`, which imports this file via `@AGENTS.md`.
Both agents receive the same repository rules here.

## Structure

- `shared/` contains cross-platform helpers, shell functions, common hooks, and
  operational tools (`shared/bin/orca-nudge` — Orca stuck-spinner recovery; see
  `claude/skills/orca-relay/SKILL.md` for the diagnosis playbook)
- `shared/skills.json` declares cross-agent external skills (currently `gpt-image`);
  `setup.sh` clones each repo under `${XDG_DATA_HOME:-~/.local/share}` and symlinks it into
  `~/.agents/skills`, both Claude accounts, and the Codex skills dir
  (see `docs/decisions/2026-08-gpt-image-shared-skill.md`)
- `claude/` contains Claude Code config sources for `~/.claude/`
- `claude/hooks/clawd-relay.sh` — Clawd on Desk relay; harness owns these hook entries and
  Clawd's own auto-management must stay off (see `docs/decisions/2026-08-clawd-on-desk-hooks.md`)
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
- Two Claude accounts share this config: `cc` (personal, `~/.claude`) and `ccu` (work, `~/.claude-upstage`); `setup.sh` symlinks the same sources into both
- Never hardcode `~/.claude` in `claude/settings.json` — use `${CLAUDE_CONFIG_DIR:-$HOME/.claude}` so each account resolves its own directory
- Codex config is split between symlink-managed files in `codex/` and patch-only updates to `~/.codex/config.toml`
- This harness fully manages Codex `mcp_servers.*` state based on `codex/mcp-servers.json` and may prune undeclared entries during setup
- Do not overwrite unrelated Codex machine state such as `projects.*` or unrelated `plugins.*`
- Keep this repo portable: never hardcode usernames or machine-specific absolute paths when a variable such as `$HOME` or `$REPO_DIR` can be used
- Never commit per-user/per-machine runtime preferences (model selection, `theme`, and the like)
  into managed configs — the runtime owns those values, and a committed pin permanently fights
  the runtime's writes (see Runtime Drift below)

## Runtime Drift

Live configs are symlinked back into this repo, so runtimes write machine-local state
directly into the working tree. This is expected, recurring, and NOT work-in-progress:

- `claude/settings.json` — Claude Code CLI rewrites `model` (e.g. via `/model` or `/config`)
  and `theme`; Orca(ADE) injects and reorders its own agent-hook entries
- `codex/hooks.json` — Orca may inject `~/.orca/agent-hooks/codex-hook.sh` entries

Handling rules:

- Before `git pull` / `git checkout`, clear this drift with `git stash push` (or discard it
  if it only touches the fields above) — do not treat it as a blocker or try to merge it
- After `git pull && ./setup.sh && ./check.sh` all pass, pre-pull drift stashes are obsolete
  and safe to drop; the runtime regenerates its state on next use
- Never commit runtime drift as-is; a hook-related change becomes a commit only when it is an
  intentional harness decision, normalized per the portability rules above
- Managed configs intentionally do NOT pin `model` or `theme` (see Repository Rules); if the
  runtime writes them into `claude/settings.json`, that diff is always discardable drift

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
- `claude/CLAUDE.md` and `codex/AGENTS.md` are kept in sync as a pair: a behavioral rule added, changed, or removed in one must land in the other **in the same PR** (wording adapted to each file's style). Skip the mirror only when the rule depends on a runtime feature the other agent lacks, and say so in the PR
- When a mirrored rule is important enough to guard, add a `check_contains` pair for it in `check.sh` so drift between the two docs is caught by `./check.sh`

## Verification

When modifying `setup.sh`, `check.sh`, hooks, project docs, or config files:

1. If project rules changed, edit root `AGENTS.md` only — `CLAUDE.md` stays a single `@AGENTS.md` adapter line
2. If a global behavioral rule changed in `claude/CLAUDE.md` or `codex/AGENTS.md`, mirror it in the other file (Agent Parity Policy)
3. Run `./setup.sh` or the relevant agent-specific setup command
4. Run `./check.sh`
5. Only report completion after the checks reflect the final state
