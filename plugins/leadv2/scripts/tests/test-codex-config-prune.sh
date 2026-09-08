#!/usr/bin/env bash
# run-all-triggers: leadv2-lane-worktree leadv2-codex-config-prune
# Every subprocess uses a temporary CODEX_HOME and an explicit fixture config.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
python3 - "$SCRIPT_DIR" <<'PY'
import concurrent.futures
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import tomllib

scripts = Path(sys.argv[1])
passed = failed = 0


def check(label, condition, detail=''):
    global passed, failed
    if condition:
        passed += 1
        print('PASS: ' + label)
    else:
        failed += 1
        print('FAIL: ' + label + ' ' + detail)


with tempfile.TemporaryDirectory(prefix='codex-config-fixture-') as tmp:
    root = Path(tmp)
    home = root / 'home'
    home.mkdir()
    cfg = home / 'config.toml'
    env = dict(os.environ, HOME=str(home), CODEX_HOME=str(home), LEADV2_CODEX_WORKTREE_TRUST='on')
    live = root / 'live'
    live.mkdir()
    alias = root / 'alias'
    alias.symlink_to(live, target_is_directory=True)
    dead = root / 'known-dead'

    def stanza(path, policy='trusted'):
        return '[projects.' + json.dumps(str(path)) + ']\ntrust_level = "' + policy + '"\n'

    def run(*args):
        return subprocess.run(['bash', str(scripts / 'leadv2-codex-config-prune.sh'),
                               '--config', str(cfg), *args], env=env,
                              capture_output=True, text=True, timeout=20)

    def register(path):
        return subprocess.run(['bash', '-c', 'source "$1"; codex_trust_worktree "$2"',
                               'fixture', str(scripts / 'leadv2-lane-worktree.sh'), str(path)],
                              env=env, capture_output=True, text=True, timeout=20)

    def count():
        return len(tomllib.loads(cfg.read_text()).get('projects', {}))

    original = '# root comment\nmodel = "fixture"\n' + stanza(live) + '# retained live comment\n'
    original += stanza(dead).replace('trust_level = "trusted"',
                                     'trust_level = "trusted" # dead inline comment')
    original += '# dead full comment\n[unrelated]\nvalue = "kept"\n'
    cfg.write_text(original)
    cfg.chmod(0o600)
    result = run('--dry-run')
    check('dry-run does not write', result.returncode == 0
          and cfg.read_text() == original
          and not list(home.glob('config.toml.bak-*')) and not (home / 'config.toml.leadv2.lock').exists())
    result = run()
    check('dead-path surviving table count', result.returncode == 0 and count() == 1,
          f'expected=1 actual={count()} rc={result.returncode} {result.stderr}')
    report = json.loads(result.stdout)
    check('reported count matches observed drop', report['before'] - report['removed'] == count()
          and report['remaining'] == count())
    check('backup preserves original bytes and permissions', bool(report['backup'])
          and Path(report['backup']).read_bytes() == original.encode()
          and Path(report['backup']).stat().st_mode & 0o777 == 0o600
          and cfg.stat().st_mode & 0o777 == 0o600)
    check('live bytes and all comments retained', stanza(live) + '# retained live comment\n' in cfg.read_text()
          and '# dead inline comment\n' in cfg.read_text() and '# dead full comment\n' in cfg.read_text()
          and '[unrelated]\nvalue = "kept"\n' in cfg.read_text())
    before = cfg.read_bytes()
    backups = list(home.glob('config.toml.bak-*'))
    result = run()
    check('second prune is a byte-identical no-op', result.returncode == 0
          and cfg.read_bytes() == before and list(home.glob('config.toml.bak-*')) == backups)

    cfg.write_text(stanza(alias) + stanza(live))
    result = run()
    check('identical live aliases collapse to physical entry', result.returncode == 0 and count() == 1
          and str(live.resolve()) in tomllib.loads(cfg.read_text())['projects'])
    cfg.write_text(stanza(alias, 'untrusted') + stanza(live))
    before = cfg.read_bytes()
    result = run()
    check('conflicting live policies untouched', result.returncode == 0 and cfg.read_bytes() == before
          and json.loads(result.stdout)['retained_conflicts'] == 1)

    cfg.write_text('# writer fixture\n')
    first = register(alias)
    check('first write registers one canonical path', first.returncode == 0 and count() == 1
          and str(live.resolve()) in tomllib.loads(cfg.read_text())['projects'])
    second = register(live)
    # Count raw headers: a broken always-append writer may create invalid TOML.
    raw_count = sum(line.startswith('[projects.') for line in cfg.read_text().splitlines())
    check('second-write table count', raw_count == 1,
          f'expected=1 actual={raw_count} rc={second.returncode}')
    cfg.write_text(stanza(alias, 'untrusted'))
    before = cfg.read_bytes()
    register(live)
    check('writer leaves existing alias policy untouched', cfg.read_bytes() == before)

    cfg.write_text('# concurrent writers\n')
    with concurrent.futures.ThreadPoolExecutor(max_workers=8) as pool:
        results = list(pool.map(register, [alias, live] * 8))
    check('concurrent writers produce one table', sum(line.startswith('[projects.') for line in cfg.read_text().splitlines()) == 1 and all(r.returncode == 0 for r in results))

    odd = root / 'quotes" and \\ slash'
    odd.mkdir()
    cfg.write_text('')
    register(odd)
    check('writer escapes TOML path keys', str(odd.resolve()) in tomllib.loads(cfg.read_text())['projects'])

    # A fake header inside a multiline string must never become a section.
    text = 'description = """\n[projects.\"/fake-header\"]\n# string content\n"""\n'
    text += 'matrix = [\n[1, 2],\n[3, 4]\n]\n'
    text += stanza(live) + 'note = \'\'\'\n[projects."/fake-literal"]\n\'\'\'\n'
    text += stanza(dead) + '[projects.' + json.dumps(str(dead)) + '.nested]\nvalue=1 # nested comment\n'
    cfg.write_text(text)
    result = run()
    check('multiline strings and nested tables', result.returncode == 0 and count() == 1
          and '[projects."/fake-header"]' in cfg.read_text()
          and '[projects."/fake-literal"]' in cfg.read_text() and '# nested comment' in cfg.read_text())

    cfg.write_text('[projects."broken"\n')
    before = cfg.read_bytes()
    result = run()
    check('invalid input fails without changing config', result.returncode != 0 and cfg.read_bytes() == before)
    cfg.write_text('[projects]\n' + json.dumps(str(dead)) + ' = {trust_level="trusted"}\n')
    before = cfg.read_bytes()
    result = run()
    check('unsupported inline layout fails without changing config', result.returncode != 0 and cfg.read_bytes() == before)

print(f'test-codex-config-prune: {passed} passed, {failed} failed')
sys.exit(1 if failed else 0)
PY
