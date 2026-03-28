# AGENTS.md

## Cross-Platform Compatibility

This config targets both macOS (Darwin) and Linux. All shell scripts must work on both.

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

## Plugin Management

- Claude plugins: declared in `claude/settings.json` (`enabledPlugins` + `extraKnownMarketplaces`)
- Codex curated skills: listed in `codex/skills.txt` (one name per line)
- Codex external skill repos: declared in `codex/external-skills.json`
- Codex plugins: preserved in `config.toml` (setup.sh does not modify)

## Config Management

- Claude: full symlink (settings.json, CLAUDE.md, hooks, commands)
- Codex: symlink (AGENTS.md, hooks.json, hooks) + config.toml patch (profile block only)
