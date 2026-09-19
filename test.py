#!/usr/bin/env python3
"""Isolated integration spec: python3 test.py [installed-fall]."""
import os
import json
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile

SOURCE = Path(__file__).resolve().parent
COMMAND = [str(Path(sys.argv[1]).resolve())] if len(sys.argv) > 1 else [shutil.which('nu'), str(SOURCE / 'fall.nu')]
GIT = shutil.which('git')


def encode(path):
    return str(path).replace(' ', '\\ ')


with tempfile.TemporaryDirectory(prefix='fall-test-') as temporary:
    root = Path(temporary)
    home = root / 'home'
    home.mkdir()
    env = {**os.environ, 'HOME': str(home), 'GIT_CONFIG_NOSYSTEM': '1', 'GIT_CONFIG_GLOBAL': '/dev/null'}
    for key in list(env):
        if key.startswith('GIT_') and key not in ('GIT_CONFIG_NOSYSTEM', 'GIT_CONFIG_GLOBAL'):
            del env[key]
    conf = home / '.config/fall/repos.conf'
    prev = home / '.local/state/fall/prev.txt'
    calls = root / 'git-calls'
    # Trace2 retains argv (including -C) even when packaged Git overrides PATH.
    env['GIT_TRACE2_EVENT'] = str(calls)

    def call_log():
        events = (json.loads(line) for line in calls.read_text().splitlines())
        return '\n'.join(' '.join(event['argv']) for event in events if event['event'] == 'start')

    def git(*args):
        subprocess.run([GIT, *map(str, args)], env=env, check=True, capture_output=True)

    def run(*args, cwd=root, code=0, streams=False):
        result = subprocess.run([*COMMAND, *args], cwd=cwd, env=env, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        output = re.sub(r'\x1b\[[0-9;]*m', '', result.stdout + result.stderr)
        assert result.returncode == code, (args, result.returncode, output)
        return result if streams else output

    def write(content):
        conf.parent.mkdir(parents=True, exist_ok=True)
        conf.write_text(content)

    # Every help route is read-only, even with absent or malformed configs.
    help_cases = {
        (): ('Fetch ALL git repositories', 'fall <command> --help', '--version'),
        ('show',): ('Display the contents', '$HOME/.config/fall/repos.conf'),
        ('add',): ('current directory', 'Creates the config', 'Duplicates are skipped'),
        ('edit',): ('$EDITOR', 'default: vi', '[prefix]path [remote [remote-branch]]', '? ~/my\\ repo upstream', "README's Config"),
        ('prev',): ('age or datetime', '$HOME/.local/state/fall/prev.txt'),
        ('.',): ('nearest .repos.conf', 'upwards', 'relative', 'Does not save'),
        ('status',): ('without fetching', 'fall status .', 'saves results', 'possibly stale'),
        ('status', '.'): ('without fetching', 'nearest .repos.conf', 'relative', 'Does not save', 'possibly stale'),
        ('test',): ('Git repository roots', 'fall test .', 'Exit 0', 'Exit 1', '100 lines', 'config or state files'),
        ('test', '.'): ('absolute path first', 'relative', 'Exit 0', 'Exit 1', '100 lines', 'config or state files'),
    }
    with tempfile.TemporaryDirectory(prefix='fall-help-') as help_temporary:
        help_root = Path(help_temporary)
        help_home = help_root / 'home'
        help_home.mkdir()
        help_cwd = help_root / 'project/nested'
        help_cwd.mkdir(parents=True)
        editor = help_root / 'editor'
        editor.write_text('#!/bin/sh\necho invoked > "' + str(help_root / 'editor-called') + '"\n')
        editor.chmod(0o755)
        saved_env = env.copy()
        env.update(HOME=str(help_home), EDITOR=str(editor), GIT_TRACE2_EVENT=str(help_root / 'git-calls'))

        def snapshot():
            return {str(p.relative_to(help_root)): (p.stat().st_mtime_ns, p.read_bytes() if p.is_file() else None)
                    for p in help_root.rglob('*')}

        for malformed in (False, True):
            if malformed:
                bad_conf = help_home / '.config/fall/repos.conf'
                bad_conf.parent.mkdir(parents=True)
                bad_conf.write_text('bad\\q\n')
                (help_cwd.parent / '.repos.conf').write_text('bad\\q\n')
                state = help_home / '.local/state/fall/prev.txt'
                state.parent.mkdir(parents=True)
                state.write_text('saved result')
            before = snapshot()
            for topic, expected in help_cases.items():
                for leading in ((), ('--',)):
                    result = run(*leading, *topic, '--help', cwd=help_cwd, streams=True)
                    assert result.stderr == '', (topic, result.stderr)
                    plain = re.sub(r'\x1b\[[0-9;]*m', '', result.stdout)
                    assert all(part in plain for part in expected), (topic, plain)
                    assert len(plain.splitlines()) <= (25 if not topic or topic == ('edit',) else 15), plain
                    assert max(map(len, plain.splitlines())) <= 120, plain
                    assert '\x1b[1m' in result.stdout and '\x1b[4m' in result.stdout
                    assert '\x1b[90m' in result.stdout
                    assert '\x1b[34m' in result.stdout or '\x1b[35m' in result.stdout
                    if topic:
                        assert '\x1b[32m' in result.stdout
                    else:
                        assert '\x1b[36m' in result.stdout
                    if len(topic) == 2:
                        assert 'global' not in plain.lower() and '$HOME' not in plain
            invalid = [('--help', 'status'), ('unknown', '--help'), ('--version', '--help'),
                       ('status', '--help', '.'), ('status', '.', '--help', 'extra'),
                       ('test', '.', '.', '--help'), ('--', '--', '--help'), ('-h',)]
            invalid += [(command, 'extra', '--help') for command in ('show', 'add', 'edit', 'prev', '.', 'status', 'test')]
            invalid += [(command, '.', '--help') for command in ('show', 'add', 'edit', 'prev', '.')]
            for args in invalid:
                result = run(*args, cwd=help_cwd, code=1, streams=True)
                assert result.stdout == '' and result.stderr
                hint = 'fall ' + args[0] if (args[0],) in help_cases else 'fall'
                assert hint + ' --help' in result.stderr, (args, result.stderr)
            for leading in ((), ('--',)):
                result = run(*leading, '--version', cwd=help_cwd, streams=True)
                assert result.stderr == '' and re.fullmatch(r'\d+\.\d+\.\d+\n', result.stdout)
            assert snapshot() == before
        env = saved_env

    assert 'repos.conf' in run('test', code=1)
    assert not conf.parent.exists() and not prev.parent.exists()
    repo = home / '한글 repo  '
    git('init', repo)
    git('-C', repo, '-c', 'user.name=Test', '-c', 'user.email=test@example.invalid', 'commit', '--allow-empty', '-m', 'init')
    worktree = root / 'work tree'
    git('-C', repo, 'worktree', 'add', '-b', 'other', worktree)
    sub = repo / 'sub'
    sub.mkdir()
    bare = root / 'bare'
    git('init', '--bare', bare)
    nongit = root / 'nongit'
    nongit.mkdir()
    write(encode(repo)+'   \n'+encode(worktree)+'\n')
    before = conf.read_bytes()
    assert 'succeeded: 2, failed: 0' in run('test')
    assert conf.read_bytes() == before and not prev.parent.exists()
    prev.parent.mkdir(parents=True)
    prev.write_text('sentinel')
    stamp = prev.stat().st_mtime_ns
    for count in (100, 101):
        write((encode(repo)+'\n')*count)
        output = run('test', code=int(count > 100))
        assert f'Checked: {count}, succeeded: {count}, failed: 0' in output
        if count == 101:
            assert f'{conf}:101:' in output and 'line limit exceeded' in output
    write('# comment\n\n  \t# indented\n'+encode(repo)+'\n'+'bad\\q\nrelative\n/\n'+encode(repo)+'/\n'+encode(root/'absent')+'\n'+encode(sub)+'\n'+encode(bare)+'\n'+encode(nongit)+'\n')
    output = run('test', code=1)
    assert 'Checked: 9, succeeded: 1, failed: 8' in output
    for line in range(5, 13):
        assert f'{conf}:{line}:' in output
    assert 'backslash is only allowed' in output and '경로에 공백이 포함되어 있다면' in output
    assert '[bad\\q]' in output
    write(('# comment\n'*101)+'bad\\q\n')
    output = run('test', code=1)
    assert f'{conf}:102:' in output and 'line limit exceeded' in output
    write('\n'*100)
    assert 'file lines: 100' in run('test')
    write('\n'*101)
    run('test', code=1)
    write('')
    assert 'Checked: 0' in run('test')
    write(encode(repo)+'\r\n')
    assert 'CR/LF' in run('test', code=1)
    # An existing full path with an unescaped space must never be reinterpreted.
    ambiguous = root/'missing suffix'
    git('init', ambiguous)
    write(str(ambiguous)+'\n')
    assert 'directory not found' in run('test', code=1)
    # If the prefix exists, the suffix is validated as a remote name.
    git('init', root/'missing')
    assert 'unregistered remote: suffix' in run('test', code=1)
    project = root / 'project'
    nested = project / 'nested/deep'
    nested.mkdir(parents=True)
    local = project / '.repos.conf'
    local.write_text(encode(os.path.relpath(repo, project))+'\n')
    write('invalid global\n')
    output = run('test', '.', cwd=nested)
    assert output.splitlines()[0] == f'.repos.conf at: {local}'
    run('test', cwd=nested, code=1)
    nearer = nested.parent / '.repos.conf'
    nearer.write_text('/absolute\n~/home\nrepo/\n')
    output = run('test', '.', cwd=nested, code=1)
    assert output.splitlines()[0] == f'.repos.conf at: {nearer}'
    assert 'failed: 3' in output
    nearer.unlink()
    local.unlink()
    assert '.repos.conf not found' in run('test', '.', cwd=nested, code=1)
    assert prev.read_text() == 'sentinel' and prev.stat().st_mtime_ns == stamp
    if calls.exists():
        assert all(' fetch' not in line and ' status' not in line for line in call_log().splitlines())
    # add encodes, checks decoded home-expanded paths, and preserves invalid files.
    write('# comment without final newline')
    assert 'added' in run('add', cwd=repo)
    assert conf.read_text() == '# comment without final newline\n'+encode(repo)+'\n'
    assert 'duplicate' in run('add', cwd=repo)
    write('~/'+encode(repo.name)+' upstream\n')
    assert 'duplicate' in run('add', cwd=repo)
    write('bad\\x\nbad\\\n')
    before = conf.read_bytes()
    output = run('add', cwd=repo, code=1)
    assert f'{conf}:1:' in output and f'{conf}:2:' in output
    assert conf.read_bytes() == before
    conf.unlink()
    run('add', cwd=repo)
    assert '#? /path/to/' in conf.read_text()
    assert '#/path/to/repo origin main # description' in conf.read_text()
    assert 'a token starting with #' in run('edit', '--help')
    assert '? to fetch' in run('edit', '--help')
    run('test')
    if os.geteuid() != 0:
        conf.chmod(0)
        try:
            assert str(conf) in run('test', code=1)
        finally:
            conf.chmod(0o600)
    conf.unlink()
    conf.mkdir()
    run('test', code=1)
    conf.rmdir()
    # Normal execution uses the same codec and 100/101 boundary.
    write(encode(repo)+'\n'+'# comment\n'*99)
    assert 'clean' in run()
    write(encode(repo)+'\n'+'# comment\n'*100)
    assert 'maximum is 100' in run(code=1)
    local.write_text(encode(os.path.relpath(worktree, project))+'\n')
    before = prev.read_bytes()
    assert 'clean' in run('.', cwd=nested)
    assert prev.read_bytes() == before
    local.write_text(encode(os.path.relpath(worktree, project))+'\n'+'# comment\n'*99)
    run('test', '.', cwd=nested)
    assert 'clean' in run('.', cwd=nested)
    local.write_text('# comment\n'*101)
    run('test', '.', cwd=nested, code=1)
    run('.', cwd=nested, code=1)

    # Both status commands check every entry without contacting remotes.
    # Seed tracking refs so offline ahead/behind reporting is exercised too.
    git('-C', repo, 'remote', 'add', 'origin', root/'unreachable-remote')
    git('-C', repo, 'update-ref', 'refs/remotes/origin/tracked', 'HEAD')
    branch = subprocess.check_output([GIT, '-C', str(repo), 'branch', '--show-current'], env=env, text=True).strip()
    git('-C', repo, 'config', f'branch.{branch}.remote', 'origin')
    git('-C', repo, 'config', f'branch.{branch}.merge', 'refs/heads/tracked')
    git('-C', repo, '-c', 'user.name=Test', '-c', 'user.email=test@example.invalid', 'commit', '--allow-empty', '-m', 'ahead')
    write(encode(repo)+'\n!   '+encode(worktree)+'\n')
    calls.write_text('')
    output = run('status')
    log = call_log()
    assert ' fetch' not in log
    for path in (repo, worktree):
        assert any(str(path) in line and ' status --porcelain=v2 --branch' in line for line in log.splitlines()), log
        assert str(path) in output and str(path) in prev.read_text()
    assert '+1 -0' in output and 'error occurred' not in output
    assert '\x1b' not in prev.read_text()
    assert prev.read_text() in run('prev')
    before, stamp = prev.read_bytes(), prev.stat().st_mtime_ns
    local.write_text(encode(os.path.relpath(repo, project))+'\n! '+encode(os.path.relpath(worktree, project))+'\n')
    write('invalid global\n')
    calls.write_text('')
    output = run('status', '.', cwd=nested)
    log = call_log()
    assert ' fetch' not in log
    for path in (repo, worktree):
        assert any(str(path) in line and ' status --porcelain=v2 --branch' in line for line in log.splitlines()), log
    assert '+1 -0' in output
    assert prev.read_bytes() == before and prev.stat().st_mtime_ns == stamp
    nearer.write_text('! '+encode(os.path.relpath(repo, nearer.parent))+'\n')
    output = run('status', '.', cwd=nested)
    assert str(repo) in output and str(worktree) not in output
    nearer.unlink()
    local.unlink()
    run('status', '.', cwd=nested, code=1)

    # A skip entry with an unreachable remote still reports status normally.
    # Use an independent repository for required fetch (worktrees share remotes).
    required = root/'required'
    git('init', required)
    write('! '+encode(repo)+'\n'+encode(required)+'\n')
    calls.write_text('')
    output = run()
    log = call_log()
    assert any(str(required) in line and ' fetch' in line for line in log.splitlines()), log
    assert not any(str(repo) in line and ' fetch' in line for line in log.splitlines()), log
    for path in (repo, required):
        assert any(str(path) in line and ' status --porcelain=v2 --branch' in line for line in log.splitlines()), log
    assert '+1 -0' in output and 'error occurred' not in output
    write(encode(repo)+'\n')
    assert 'error occurred' in run()  # Required fetch failure keeps existing policy.
    write('! ~/'+encode(repo.name)+' origin\n')
    assert 'succeeded: 1, failed: 0' in run('test')
    before = conf.read_bytes()
    assert 'duplicate' in run('add', cwd=repo)
    assert conf.read_bytes() == before
    write('!repo\n!\tbad\n! \n! '+encode(sub)+'\n')
    assert 'failed: 4' in run('test', code=1)
    before = conf.read_bytes()
    run('add', cwd=repo, code=1)
    assert conf.read_bytes() == before

    # Optional failures suppress Git diagnostics, warn on stderr, and retain status.
    warning = f'{repo} fetch failed; showing local status'
    write('?   '+encode(repo)+' origin\n')
    calls.write_text('')
    result = run(streams=True)
    stderr = re.sub(r'\x1b\[[0-9;]*m', '', result.stderr)
    assert stderr == warning+'\n', result
    assert '\x1b[33mfetch failed;' in result.stderr
    assert '+1 -0' in result.stdout and 'error occurred' not in result.stdout
    log = call_log()
    assert any(str(repo) in line and ' fetch' in line for line in log.splitlines()), log
    assert any(str(repo) in line and ' status --porcelain=v2 --branch' in line for line in log.splitlines()), log
    assert warning in prev.read_text() and '+1 -0' in prev.read_text()
    assert '\x1b' not in prev.read_text() and 'fatal:' not in prev.read_text()
    before, stamp = prev.read_bytes(), prev.stat().st_mtime_ns
    local.write_text('? '+encode(os.path.relpath(repo, project))+'\n')
    assert warning in run('.', cwd=nested)
    assert prev.read_bytes() == before and prev.stat().st_mtime_ns == stamp

    # All three modes coexist; optional success actually updates tracking refs.
    remote = root/'reachable-remote'
    git('clone', '--bare', repo, remote)
    reachable = root/'reachable'
    git('clone', remote, reachable)
    git('-C', repo, 'push', remote, f'HEAD:refs/heads/{branch}')
    git('-C', repo, '-c', 'user.name=Test', '-c', 'user.email=test@example.invalid', 'commit', '--allow-empty', '-m', 'remote advance')
    git('-C', repo, 'push', remote, f'HEAD:refs/heads/{branch}')
    write('? '+encode(reachable)+'\n! '+encode(repo)+'\n'+encode(required)+'\n')
    calls.write_text('')
    output = run()
    log = call_log()
    assert '+0 -1' in output and 'fetch failed' not in output and 'error occurred' not in output
    assert ' -> origin/' in output  # Successful fetch output remains visible.
    for path in (reachable, required):
        assert any(str(path) in line and ' fetch' in line for line in log.splitlines()), log
    assert not any(str(repo) in line and ' fetch' in line for line in log.splitlines()), log
    for path in (reachable, repo, required):
        assert any(str(path) in line and ' status --porcelain=v2 --branch' in line for line in log.splitlines()), log

    # Explicit selection fetches exactly one remote while status follows upstream.
    second_remote = root/'second-remote'
    git('clone', '--bare', remote, second_remote)
    git('-C', reachable, 'remote', 'add', 'upstream', second_remote)
    git('-C', reachable, 'fetch', 'upstream')
    git('-C', reachable, 'branch', '--set-upstream-to', f'upstream/{branch}')

    def revision(path, ref):
        return subprocess.check_output([GIT, '-C', str(path), 'rev-parse', ref], env=env, text=True).strip()

    def fetch_argv():
        return [event['argv'] for event in map(json.loads, calls.read_text().splitlines())
                if event['event'] == 'start' and 'fetch' in event['argv']]

    # Inline comments share decoding across validation, execution, and add.
    for prefix in ('', '! ', '? '):
        for suffix in ('', ' origin', f' origin {branch}'):
            comment = '   #설명 bad\\field\t extra ignored tokens'
            raw = prefix+encode(reachable)+suffix+comment
            local_raw = prefix+encode(os.path.relpath(reachable, project))+suffix+comment
            write('# heading\n'+raw+'\n')
            local.write_text('# heading\n'+local_raw+'\n')
            global_before, local_before = conf.read_bytes(), local.read_bytes()
            for args in (('test',), ('test', '.')):
                assert 'succeeded: 1, failed: 0' in run(*args, cwd=nested)
            for args in ((), ('.',)):
                calls.write_text('')
                output = run(*args, cwd=nested)
                assert str(reachable) in output and 'error occurred' not in output
                argv = fetch_argv()
                if prefix == '! ':
                    assert not argv, argv
                else:
                    expected = ['fetch', '--', 'origin'] if suffix else ['fetch']
                    assert len(argv) == 1 and argv[0][-len(expected):] == expected, argv
            assert 'duplicate' in run('add', cwd=reachable)
            assert conf.read_bytes() == global_before and local.read_bytes() == local_before

    # Errors retain their original line and comment in both config diagnostics.
    for suffix in ('origin main extra', 'origin\\bad', 'origin\tbad'):
        raw = encode(reachable)+' '+suffix+' # retained comment'
        local_raw = encode(os.path.relpath(reachable, project))+' '+suffix+' # retained comment'
        write('# heading\n'+raw+'\n')
        local.write_text('# heading\n'+local_raw+'\n')
        for args, selected, original in ((('test',), conf, raw), (('test', '.'), local, local_raw)):
            output = run(*args, cwd=nested, code=1)
            assert f'{selected}:2: [{original}]' in output, output
        before = conf.read_bytes()
        run('add', cwd=reachable, code=1)
        assert conf.read_bytes() == before

    stale = revision(reachable, f'upstream/{branch}')
    git('-C', repo, '-c', 'user.name=Test', '-c', 'user.email=test@example.invalid',
        'commit', '--allow-empty', '-m', 'both remotes advance')
    for destination in (remote, second_remote):
        git('-C', repo, 'push', destination, f'HEAD:refs/heads/{branch}')
    latest = revision(repo, 'HEAD')
    git('-C', reachable, 'config', 'fetch.all', 'true')
    write(encode(reachable)+'   origin   \n')
    calls.write_text('')
    output = run()
    argv = fetch_argv()
    assert len(argv) == 1 and argv[0][-3:] == ['fetch', '--', 'origin'], argv
    assert revision(reachable, f'origin/{branch}') == latest
    assert revision(reachable, f'upstream/{branch}') == stale
    assert f'upstream/{branch}' in output and '+0 -1' in output

    git('-C', reachable, 'config', '--unset', 'fetch.all')

    # Omission keeps argument-free fetch and selects the configured upstream.
    write(encode(reachable)+'\n')
    calls.write_text('')
    output = run()
    argv = fetch_argv()
    assert len(argv) == 1 and argv[0][-1] == 'fetch', argv
    assert revision(reachable, f'upstream/{branch}') == latest
    assert '+0 -2' in output

    # Without a configured upstream Git defaults to origin.
    git('-C', reachable, 'branch', '--unset-upstream')
    git('-C', repo, '-c', 'user.name=Test', '-c', 'user.email=test@example.invalid',
        'commit', '--allow-empty', '-m', 'origin advance')
    git('-C', repo, 'push', remote, f'HEAD:refs/heads/{branch}')
    calls.write_text('')
    run()
    argv = fetch_argv()
    assert len(argv) == 1 and argv[0][-1] == 'fetch', argv
    assert revision(reachable, f'origin/{branch}') == revision(repo, 'HEAD')
    assert revision(reachable, f'upstream/{branch}') == latest

    # Omission also preserves fetch.all from user Git configuration.
    git('-C', repo, 'push', second_remote, f'HEAD:refs/heads/{branch}')
    git('-C', reachable, 'config', 'fetch.all', 'true')
    calls.write_text('')
    run()
    assert fetch_argv()[0][-1] == 'fetch'
    assert revision(reachable, f'upstream/{branch}') == revision(repo, 'HEAD')
    git('-C', reachable, 'config', '--unset', 'fetch.all')

    # A registered option-looking name is passed literally as one argument.
    git('-C', reachable, 'config', 'remote.--literal.url', str(remote))
    git('-C', reachable, 'config', 'remote.--literal.fetch', f'+refs/heads/*:refs/remotes/literal/*')
    write(encode(reachable)+' --literal\n')
    calls.write_text('')
    assert 'error occurred' not in run()
    assert fetch_argv()[0][-3:] == ['fetch', '--', '--literal']
    assert revision(reachable, f'literal/{branch}') == revision(repo, 'HEAD')

    # Explicit branch comparisons are independent of upstream and fetch selection.
    comparison = root/'comparison'
    git('init', '-b', 'feature', comparison)
    git('-C', comparison, 'remote', 'add', 'origin', remote)

    def commit_comparison(message):
        git('-C', comparison, '-c', 'user.name=Test', '-c', 'user.email=test@example.invalid',
            'commit', '--allow-empty', '-m', message)

    def comparison_config(prefix='! ', target='main'):
        write(prefix+encode(comparison)+' origin '+target+'\n! '+encode(required)+'\n')

    comparison_config()
    (comparison/'dirty').write_text('untracked')
    assert 'succeeded: 2, failed: 0' in run('test')
    output = run('status')
    assert 'comparison unavailable: HEAD has no commit ±' in output, output
    assert str(required) in output
    commit_comparison('base')
    base = revision(comparison, 'HEAD')
    git('-C', comparison, 'update-ref', 'refs/remotes/origin/main', base)
    output = run('status')
    assert '(feature → origin/main) up-to-date ±' in output, output
    (comparison/'dirty').unlink()
    assert '(feature → origin/main) up-to-date' in run('status')
    commit_comparison('ahead one')
    commit_comparison('ahead two')
    assert 'ahead 2, behind 0' in run('status')
    git('-C', comparison, 'checkout', '-b', 'target', base)
    commit_comparison('behind one')
    git('-C', comparison, 'update-ref', 'refs/remotes/origin/main', 'HEAD')
    git('-C', comparison, 'checkout', 'feature')
    # Deliberately configure a different upstream with zero divergence.
    git('-C', comparison, 'update-ref', 'refs/remotes/origin/other', 'HEAD')
    git('-C', comparison, 'branch', '--set-upstream-to', 'origin/other')
    output = run('status')
    assert '(feature → origin/main) ahead 2, behind 1' in output, output
    assert 'origin/other' not in output
    assert f'{comparison} (feature → origin/main) ahead 2, behind 1\n' in prev.read_text()
    assert str(required) in prev.read_text() and '\x1b' not in prev.read_text()
    calls.write_text('')
    run()
    assert not fetch_argv()
    # Local execution has identical comparison behavior and preserves saved output.
    local.write_text('! '+encode(os.path.relpath(comparison, project))+' origin main\n')
    before, stamp = prev.read_bytes(), prev.stat().st_mtime_ns
    assert 'ahead 2, behind 1' in run('.', cwd=nested)
    assert 'ahead 2, behind 1' in run('status', '.', cwd=nested)
    assert prev.read_bytes() == before and prev.stat().st_mtime_ns == stamp
    git('-C', comparison, 'checkout', '--detach')
    short = subprocess.check_output([GIT, '-C', str(comparison), 'rev-parse', '--short', 'HEAD'], env=env, text=True).strip()
    assert f'(HEAD@{short} → origin/main) ahead 2, behind 1' in run('status')
    comparison_config(target='missing/topic')
    calls.write_text('')
    assert 'succeeded: 2, failed: 0' in run('test')
    assert 'rev-parse --verify' not in call_log() and ' status' not in call_log()
    (comparison/'dirty').write_text('untracked')
    output = run('status')
    assert 'comparison unavailable: target ref missing or not a commit: refs/remotes/origin/missing/topic ±' in output
    assert str(required) in output and 'ahead' not in output
    for invalid in ('bad..name', 'bad@{name', '/main', 'main/', 'main.lock', 'a//b', 'a~b', '.'):
        comparison_config(target=invalid)
        assert 'invalid remote-branch:' in run('test', code=1)
    # A local branch name in field two must still be validated as a remote.
    write(encode(comparison)+' feature\n')
    assert 'unregistered remote: feature' in run('test', code=1)
    comparison_config()
    before = conf.read_bytes()
    assert 'duplicate' in run('add', cwd=comparison)
    assert conf.read_bytes() == before
    # Fetch receives only the remote, never the comparison branch.
    comparison_config(prefix='')
    calls.write_text('')
    run()
    assert fetch_argv()[0][-3:] == ['fetch', '--', 'origin']
    git('-C', comparison, 'remote', 'set-url', 'origin', root/'absent-remote')
    comparison_config(prefix='? ')
    output = run()
    assert 'fetch failed; showing local status' in output and 'ahead 2, behind 1' in output
    assert 'fetch failed; showing local status' in prev.read_text()
    comparison_config(prefix='')
    output = run()
    assert 'error occurred' in output and '→' not in output
    assert str(required) in output

    # Missing remote names are config errors in every mode, including offline/local.
    git('-C', reachable, 'config', 'remotes.group', 'origin upstream')
    for invalid in ('orig', 'Origin', 'group', str(remote)):
        for prefix in ('', '? ', '! '):
            raw = prefix+encode(reachable)+' '+invalid
            write('# comment\n'+raw+'\n')
            local_raw = prefix+encode(os.path.relpath(reachable, project))+' '+invalid
            local.write_text('# comment\n'+local_raw+'\n')
            for args in ((), ('status',), ('test',), ('.',), ('status', '.'), ('test', '.')):
                calls.write_text('')
                output = run(*args, cwd=nested, code=int(args[:1] == ('test',)))
                selected, original = (local, local_raw) if '.' in args else (conf, raw)
                assert f'{selected}:2: [{original}]: unregistered remote: {invalid}' in output, output
                assert not fetch_argv() and ' status' not in call_log()
                assert 'fetch failed' not in output

    # Old ignored suffixes now fail syntax validation and never execute the row.
    for suffix in ('origin main extra', 'origin\\bad', 'origin\tbad'):
        write(encode(reachable)+' '+suffix+'\n')
        calls.write_text('')
        assert 'failed: 1' in run('test', code=1)
        run()
        assert not fetch_argv() and ' status' not in call_log()

    for args in [('status',), ('status', '.')]:
        write('? '+encode(repo)+'\n! '+encode(reachable)+'\n'+encode(required)+'\n')
        local.write_text('? '+encode(os.path.relpath(repo, project))+'\n! '+encode(os.path.relpath(reachable, project))+'\n'+encode(os.path.relpath(required, project))+'\n')
        before, stamp = prev.read_bytes(), prev.stat().st_mtime_ns
        calls.write_text('')
        output = run(*args, cwd=nested)
        assert ' fetch' not in call_log() and 'fetch failed' not in output
        assert all(str(path) in output for path in (repo, reachable, required))
        if len(args) == 2:
            assert prev.read_bytes() == before and prev.stat().st_mtime_ns == stamp
        else:
            assert all(str(path) in prev.read_text() for path in (repo, reachable, required))

    write('? ~/'+encode(repo.name)+' origin\n')
    calls.write_text('')
    assert 'succeeded: 1, failed: 0' in run('test')
    before = conf.read_bytes()
    assert 'duplicate' in run('add', cwd=repo)
    assert conf.read_bytes() == before
    assert ' fetch' not in call_log() and ' status' not in call_log()
    write('?repo\n?\tbad\n? \n? ! repo\n! ? repo\n? '+encode(sub)+'\n? '+encode(bare)+'\n? '+encode(nongit)+'\n? '+encode(root/'absent')+'\n? relative\n')
    calls.write_text('')
    assert 'failed: 10' in run('test', code=1)
    output = run()
    assert 'fetch failed' not in output and 'directory not found' in output
    assert ' fetch' not in call_log() and ' status' not in call_log()
    before = conf.read_bytes()
    run('add', cwd=repo, code=1)
    assert conf.read_bytes() == before
    local.write_text('? /absolute\n? ~/home\n? repo/\n')
    assert 'failed: 3' in run('test', '.', cwd=nested, code=1)
    write('# comment\n'*101)
    run('status', code=1)
    for args in [('status', 'repo'), ('status', '.', 'extra'), ('.', 'status'), ('unknown',)]:
        run(*args, code=1)
print('CLI integration tests passed')
