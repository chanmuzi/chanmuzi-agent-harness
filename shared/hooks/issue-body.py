#!/usr/bin/env python3
"""Inspect literal gh issue bodies without evaluating shell code.

This is a deliberately bounded shell reader, not a shell interpreter. Dynamic
bodies must be materialized in a separate tool call and passed by file path.
"""
import json
import os
from pathlib import Path
import re
import shlex
import stat
import sys


class Unverifiable(ValueError):
    pass


def words(command):
    """Yield (value, dynamic, operator), retaining quoted separator identity."""
    # The skills use this exact cat/heredoc idiom. Extract data, never run cat.
    heredoc = re.compile(
        r'"\$\(cat\s+<<(?P<tabs>-?)\s*(?P<quote>[\'\"]?)(?P<tag>[\w.-]+)'
        r'(?P=quote)[ \t]*\n(?P<body>.*?)\n(?P<indent>\t*)(?P=tag)\n[ \t]*\)"', re.S
    )

    def replace(match):
        if match['indent'] and not match['tabs']:
            raise Unverifiable('invalid heredoc terminator')
        body = match['body']
        if not match['quote'] and re.search(r'[$`\\]', body):
            raise Unverifiable('expanding heredoc: use a separately written body file')
        if match['tabs']:
            body = '\n'.join(line.lstrip('\t') for line in body.split('\n'))
        return shlex.quote(body.rstrip('\n'))

    command = heredoc.sub(replace, command)
    i = 0
    while i < len(command):
        if command[i] in ' \t\r':
            i += 1
            continue
        if command[i] == '#':
            end = command.find('\n', i)
            i = len(command) if end < 0 else end
            continue
        if command[i] in ';|&\n()<>':
            char = command[i]
            i += 1
            if i < len(command) and command[i] == char and char in '&|<>':
                char += command[i]
                i += 1
            yield char, False, True
            continue
        value, dynamic = '', False
        while i < len(command) and command[i] not in ' \t\r\n;|&()<>':
            char = command[i]
            if char in "'\"":
                quote = char
                i += 1
                while i < len(command) and command[i] != quote:
                    char = command[i]
                    if quote == '"' and char == '\\' and i + 1 < len(command) and command[i + 1] in '$`"\\\n':
                        i += 1
                        if command[i] != '\n':
                            value += command[i]
                    else:
                        dynamic |= quote == '"' and char in '$`'
                        value += char
                    i += 1
                if i == len(command):
                    raise Unverifiable('unclosed shell quote')
                i += 1
            elif char == '\\':
                i += 1
                if i == len(command):
                    raise Unverifiable('unfinished shell escape')
                if command[i] != '\n':
                    value += command[i]
                i += 1
            else:
                dynamic |= char in '$`*?[' or (not value and char == '~')
                value += char
                i += 1
        yield value, dynamic, False


def read_body(argv, cwd):
    bodies = []
    i = 0
    while i < len(argv):
        value, dynamic, _ = argv[i]
        kind, body = None, None
        # Values of other gh flags are data, even when they look like body flags.
        if value in ('--title', '-t', '--assignee', '-a', '--label', '-l',
                     '--milestone', '-m', '--project', '-p', '--template', '-T',
                     '--repo', '-R'):
            i += 2
            continue
        if value in ('--body', '-b', '--body-file', '-F'):
            kind = 'file' if value in ('--body-file', '-F') else 'text'
            i += 1
            if i == len(argv):
                raise Unverifiable('body option has no value')
            body, dynamic, _ = argv[i]
        elif value.startswith(('--body=', '--body-file=')):
            flag, body = value.split('=', 1)
            kind = 'file' if flag == '--body-file' else 'text'
        elif value.startswith(('-b', '-F')) and len(value) > 2:
            kind = 'file' if value[:2] == '-F' else 'text'
            body = value[2:]
        if kind:
            if dynamic:
                raise Unverifiable('dynamic body or path: write a file in a separate tool call')
            if kind == 'file':
                if body == '-':
                    raise Unverifiable('stdin body cannot be read before execution; use a saved file')
                path = Path(body)
                if not path.is_absolute():
                    if cwd is None:
                        raise Unverifiable('working directory is uncertain; use an absolute body-file path')
                    path = cwd / path
                # Nonblocking open prevents FIFOs from hanging the pre-tool hook.
                fd = os.open(path, os.O_RDONLY | os.O_NONBLOCK)
                with os.fdopen(fd, 'r', encoding='utf-8') as stream:
                    if not stat.S_ISREG(os.fstat(stream.fileno()).st_mode):
                        raise Unverifiable('body-file must be a regular file')
                    body = stream.read(1024 * 1024 + 1)
                    if len(body) > 1024 * 1024:
                        raise Unverifiable('body-file exceeds 1 MiB inspection limit')
            bodies.append(body)
        i += 1
    if len(bodies) != 1:
        raise Unverifiable('provide exactly one --body/-b or --body-file/-F')
    return bodies[0]


def unwrap(argv, cwd):
    """Remove known shell command prefixes; never interpret their code."""
    while argv:
        value = argv[0][0]
        if re.match(r'^[A-Za-z_][A-Za-z_0-9]*=', value):
            argv = argv[1:]
        elif value in ('if', 'elif', 'while', 'until', 'then', 'do', 'else', '!', '{'):
            argv = argv[1:]
        elif value in ('command', 'time'):
            argv = argv[1:]
            while argv and argv[0][0] in ('-p', '--'):
                argv = argv[1:]
        elif value == 'env':
            argv = argv[1:]
            while argv and argv[0][0].startswith('-'):
                option, dynamic, _ = argv[0]
                argv = argv[1:]
                if option == '--':
                    break
                if option in ('-i', '--ignore-environment'):
                    continue
                if option in ('-u', '--unset', '-C', '--chdir'):
                    if not argv:
                        raise Unverifiable('env option has no value')
                    argument = argv[0]
                    argv = argv[1:]
                elif option.startswith(('--unset=', '--chdir=')):
                    argument = (option.split('=', 1)[1], dynamic, False)
                else:
                    raise Unverifiable('unsupported env option; invoke gh directly')
                if option in ('-C', '--chdir') or option.startswith('--chdir='):
                    path = Path(argument[0])
                    cwd = (path if path.is_absolute() else cwd / path) if cwd is not None and not argument[1] else None
        else:
            break
    return argv, cwd


def inspect(payload, agent):
    names = {'codex': 'Codex', 'claude': 'Claude Code'}
    if agent not in names:
        raise Unverifiable('unknown agent; invoke the Claude or Codex hook wrapper')
    expected = names[agent]
    command = payload['tool_input']['command']
    cwd = Path(payload['tool_input'].get('cwd') or payload['tool_input'].get('workdir')
               or payload.get('cwd') or os.getcwd())
    segments, segment = [], []
    for token in words(command):
        if token[2]:
            segments.append((segment, token[0]))
            segment = []
        else:
            segment.append(token)
    segments.append((segment, ''))
    for argv, separator in segments:
        # env -C affects this invocation only, unlike the shell's cd builtin.
        argv, invocation_cwd = unwrap(argv, cwd)
        values = [item[0] for item in argv]
        if values[:1] == ['cd']:
            if len(argv) == 2 and not argv[1][1] and cwd is not None and separator == '&&':
                path = Path(values[1])
                cwd = path if path.is_absolute() else cwd / path
            else:
                cwd = None
        if separator in ('|', '||', '&', '(', ')'):
            cwd = None
        if values[:3] != ['gh', 'issue', 'create']:
            if values[:1] not in (['echo'], ['printf']):
                if any(values[i:i + 3] == ['gh', 'issue', 'create'] for i in range(len(values))):
                    raise Unverifiable('unsupported command prefix; invoke gh directly')
            continue
        body = read_body(argv[3:], invocation_cwd)
        markers = re.findall(r'(?m)^\s*(?:🤖\s*)?Generated with \[([^\]\n]+)\](?:\([^\n)]*\))?\s*$', body)
        if markers != [expected]:
            raise Unverifiable(f'issue body must contain one Generated with [{expected}] attribution line')


if __name__ == '__main__':
    try:
        inspect(json.load(sys.stdin), sys.argv[1])
    except (Unverifiable, OSError, UnicodeError, ValueError, KeyError) as error:
        print(f'Cannot verify issue body: {error}', file=sys.stderr)
        sys.exit(2)
