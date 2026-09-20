#!/usr/bin/env python3
"""Adapt installed git-claw attribution only; retain upstream skill content."""
from pathlib import Path
import sys

CLAUDE = 'Generated with [Claude Code](https://claude.com/claude-code)'
CODEX = 'Generated with [Codex](https://openai.com/codex/)'
ISSUE_NOTE = """
<!-- harness: git-claw body input -->
## Harness body input

Keep the template style and use the actual authoring tool's attribution above.
For `--body-file` / `-F`, write the complete body in a separate tool call first,
then pass its absolute path. The pre-execution hook reads that existing file;
it cannot inspect a file that the pending command has yet to create, shell
variable expansion, or `--body-file -` stdin. Do not relabel Codex work as Claude
Code or disable hooks to resolve a body verification error.
"""


def normalize(directory, check=False):
    failures = []
    for path in sorted(Path(directory).rglob('*.md')):
        original = path.read_text(encoding='utf-8')
        updated = original.replace(CLAUDE, CODEX)
        if path.name == 'SKILL.md' and path.parent.name == 'issue' and '<!-- harness: git-claw body input -->' not in updated:
            updated = updated.rstrip() + '\n' + ISSUE_NOTE
        if original != updated:
            if check:
                failures.append(str(path))
            else:
                path.write_text(updated, encoding='utf-8')
    if failures:
        raise ValueError('Codex git-claw template normalization needed: ' + ', '.join(failures))


if __name__ == '__main__':
    try:
        normalize(sys.argv[1], '--check' in sys.argv[2:])
    except (OSError, ValueError) as error:
        print(error, file=sys.stderr)
        sys.exit(1)
