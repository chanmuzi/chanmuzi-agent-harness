# AGENTS.md

## Scope

This file defines repository-level rules for maintaining `chanmuzi-agent-harness`.
Agent-specific behavior should live in each agent's own source docs:

- Claude: `claude/CLAUDE.md`
- Codex: `codex/AGENTS.md`

Keep shared project facts in this file and reflect corresponding project-level changes in `CLAUDE.md` within the same commit.

## Cross-Platform Compatibility

This harness targets both macOS (Darwin) and Linux. All shell scripts must work on both.

### Platform-Specific Commands

| Command | macOS (BSD) | Linux (GNU) | Solution |
|---------|-------------|-------------|----------|
| `sed -i` | Requires `sed -i ''` | `sed -i` works | Use `sed_inplace()` in `shared/lib/os.sh` |
| `readlink -f` | Not available natively | Works | Use `resolve_path()` in `shared/lib/os.sh` |
| `afplay` | Available | Not available | Guard with `uname` check or use `play_sound()` |

### Rules

- Use helper functions from `shared/lib/os.sh`
- Guard macOS-only commands with `[ "$(uname -s)" = "Darwin" ]`
- Guard Linux-only commands with `[ "$(uname -s)" = "Linux" ]`

## Repository Ownership

- `shared/` contains cross-platform helpers and shared shell utilities
- `claude/` contains Claude-specific config sources
- `codex/` contains Codex-specific config sources
- `setup.sh` installs symlinks, patches Codex config, and installs agent extras
- `check.sh` verifies symlinks, config patches, and required dependencies

## Agent Config Management

- Claude plugins are declared in `claude/settings.json` via `enabledPlugins` and `extraKnownMarketplaces`
- Codex curated skills are listed in `codex/skills.txt`
- Codex external skill repos are declared in `codex/external-skills.json`
- Claude config is fully symlink-managed from `claude/`
- Codex config is split between symlink-managed files in `codex/` and patch-only updates to `~/.codex/config.toml`
- Do not treat agent-specific source docs as shared project rules unless they are restated here
