#!/usr/bin/env python3
"""Exercise actual agent wrappers, file input and installation normalization."""
import importlib.util
import json
import os
from pathlib import Path
import shlex
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]


class IssueBodyTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix='git-claw-test-')
        self.addCleanup(self.tmp.cleanup)
        self.directory = Path(self.tmp.name)

    def hook(self, command, agent='codex', expected=0, bypass=False, cwd=None):
        result = subprocess.run(
            ['bash', str(ROOT / agent / 'hooks/enforce-git-claw.sh')],
            input=json.dumps({'tool_name': 'Bash', 'cwd': str(cwd or self.directory),
                              'tool_input': {'command': command}}),
            text=True, capture_output=True, timeout=5,
            env={**os.environ, 'ENFORCE_GIT_CLAW': '0' if bypass else '1'},
        )
        self.assertEqual(result.returncode, expected, result.stderr)
        return result

    def body(self, agent):
        name = 'Codex' if agent == 'codex' else 'Claude Code'
        return f'## 설명\n\n한글 "quote"; | & text\n\n🤖 Generated with [{name}](https://example.com)\n'

    def test_agent_attribution(self):
        for agent in ('codex', 'claude'):
            for author in ('codex', 'claude'):
                with self.subTest(agent=agent, author=author):
                    self.hook('gh issue create --title test --body ' + shlex.quote(self.body(author)),
                              agent, 0 if author == agent else 2)

    def test_file_flags_and_paths(self):
        for agent in ('codex', 'claude'):
            path = self.directory / 'body with spaces.md'
            path.write_text(self.body(agent))
            for option in ('--body-file ', '--body-file=', '-F ', '-F'):
                for name in (str(path), path.name):
                    with self.subTest(agent=agent, option=option, name=name):
                        self.hook('gh issue create --title test ' + option + shlex.quote(name), agent)

    def test_literal_forms(self):
        for flag in ('--body ', '--body=', '-b ', '-b'):
            self.hook('gh issue create --title test ' + flag + shlex.quote(self.body('codex')))
        self.hook('gh issue create --title test --body "$(cat <<\'EOF\'\n' +
                  self.body('codex') + 'EOF\n)"')
        self.hook('gh issue create --title test --body "$(cat <<-\'EOF\'\n\t' +
                  self.body('codex').replace('\n', '\n\t') + 'EOF\n)"')

    def test_missing_invalid_or_unreadable_body(self):
        for args in ('', '--body nope', '--body-file missing.md', '--body-file -',
                     '--body-file "$BODY_FILE"', '--body-file "$(printf file)"',
                     '--body-file .'):
            with self.subTest(args=args):
                self.hook('gh issue create --title test ' + args, expected=2)
        path = self.directory / 'wrong.md'
        path.write_text(self.body('claude'))
        self.hook('gh issue create --title test -F ' + shlex.quote(str(path)), expected=2)
        path.write_bytes(b'\xff')
        self.hook('gh issue create --title test -F ' + shlex.quote(str(path)), expected=2)
        path.unlink()
        os.mkfifo(path)
        self.hook('gh issue create --title test -F ' + shlex.quote(str(path)), expected=2)

    def test_attribution_must_be_in_each_body(self):
        valid = shlex.quote(self.body('codex'))
        for command in (
            f'gh issue create --title {valid} --body nope',
            f'gh issue create --body nope # {valid}',
            f'gh issue create --body nope; echo {valid}',
            f'gh issue create --body {valid}; gh issue create --body nope',
            f'gh issue create --body {valid} --body nope',
            f'gh issue create --title --body {valid}',
        ):
            with self.subTest(command=command):
                self.hook(command, expected=2)
        self.hook(f'gh issue create --body {valid}; gh issue create --body {valid}')
        self.hook('echo "gh issue create --body nope"')

    def test_cwd_and_no_execution(self):
        nested = self.directory / 'nested'
        nested.mkdir()
        (nested / 'body.md').write_text(self.body('codex'))
        self.hook('cd nested && gh issue create --body-file body.md')
        self.hook('cd nested; gh issue create --body-file body.md', expected=2)
        sentinel = self.directory / 'executed'
        self.hook(f'gh issue create --body "$(touch {sentinel})"', expected=2)
        self.assertFalse(sentinel.exists())

    def test_override_environment_not_command_prefix(self):
        for agent in ('codex', 'claude'):
            result = self.hook('ENFORCE_GIT_CLAW=0 gh issue create --body nope', agent, 2)
            self.assertIn('Prefixing the pending command does not affect PreToolUse', result.stderr)
            self.hook('gh issue create --body nope', agent, bypass=True)
            self.hook('gh issue create --body nope', agent, 2)

    def test_common_guards_remain(self):
        for agent in ('codex', 'claude'):
            for command in ('git add .', 'git commit -m nope',
                            'gh pr create --title nope --body test',
                            'gh pr create --title "Fix: test" --draft --body test'):
                self.hook(command, agent, 2)
            self.hook('git commit -m "fix: test"', agent)
            self.hook('gh pr create --title "Fix: test" --body test', agent)

    def test_install_normalization_is_narrow_and_idempotent(self):
        spec = importlib.util.spec_from_file_location('normalize', ROOT / 'codex/scripts/normalize-git-claw.py')
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        skill = self.directory / 'issue'
        skill.mkdir()
        path = skill / 'SKILL.md'
        original = '---\nname: issue\n---\nClaude Code integration docs\n\n' + module.CLAUDE
        path.write_text(original)
        with self.assertRaises(ValueError):
            module.normalize(skill, check=True)
        module.normalize(skill)
        first = path.read_bytes()
        module.normalize(skill)
        module.normalize(skill, check=True)
        self.assertEqual(first, path.read_bytes())
        self.assertIn('Claude Code integration docs', path.read_text())
        self.assertIn(module.CODEX, path.read_text())
        path.write_text(original)
        module.normalize(skill)
        self.assertEqual(first, path.read_bytes())


if __name__ == '__main__':
    unittest.main()
