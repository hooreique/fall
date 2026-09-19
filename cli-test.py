#!/usr/bin/env python3
"""Isolated integration spec: python3 cli-test.py [installed-fall]."""
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
    assert '? to fetch' in run('--help')
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
    for suffix in ('origin extra', 'origin\\bad', 'origin\tbad'):
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
    for args in [('status', 'repo'), ('status', '.', 'extra'), ('.', 'status'), ('status', '--help'), ('unknown',)]:
        run(*args, code=1)
print('CLI integration tests passed')
