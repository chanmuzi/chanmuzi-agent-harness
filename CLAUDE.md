# CLAUDE.md (project-level)

This repo is `chanmuzi-agent-harness` — a unified harness for Claude Code and Codex CLI configuration.

## Structure

- `shared/` — Cross-platform helpers, shell functions, common hooks
- `claude/` — Claude Code config (symlinked to ~/.claude/)
- `codex/` — Codex CLI config (symlinked to ~/.codex/)
- `setup.sh` — Installs symlinks, patches config, installs plugins/skills
- `check.sh` — Verifies installation health

## Rules

- Shell scripts must work on both macOS (BSD) and Linux (GNU)
- Use `sed_inplace()` and `resolve_path()` from `shared/lib/os.sh`
- Guard macOS-only commands with `[ "$(uname -s)" = "Darwin" ]`
- Guard Linux-only commands with `[ "$(uname -s)" = "Linux" ]`
- Codex `config.toml` is patch-only — never overwrite `projects.*`, `mcp_servers.*`, `plugins.*`
- Claude `settings.json` is fully managed — safe to overwrite via symlink
