"""Reproduce the identified writer before/after in isolated fresh repositories."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

lane = Path.cwd()
source = lane / 'plugins/leadv2/scripts'
with tempfile.TemporaryDirectory(prefix='shadow-writer-') as temp:
    temp = Path(temp).resolve()
    for variant in ('before', 'after'):
        root = temp / variant
        scripts = root / 'plugins/leadv2/scripts'
        shutil.copytree(source, scripts, symlinks=True, ignore=shutil.ignore_patterns('docs', 'tests', '__pycache__'))
        subprocess.run(['git', '-C', str(root), 'init', '-q'], check=True)
        subprocess.run(['git', '-C', str(root), '-c', 'user.name=test', '-c', 'user.email=test@local', 'commit', '--allow-empty', '-qm', 'seed'], check=True)
        if variant == 'before':
            for name in ('leadv2-state-path.sh', 'leadv2-status-collector.sh'):
                (scripts / name).write_bytes(subprocess.check_output(['git', 'show', '9194ff89^:plugins/leadv2/scripts/' + name]))
        state = temp / 'state' / variant
        state.mkdir(parents=True)
        (state / 'active.yaml').write_text('sessions: []\n')
        env = {k: v for k, v in os.environ.items() if k not in (
            'PROJECT_ROOT', 'LEADV2_PROJECT_ROOT', 'CLAUDE_PROJECT_DIR', 'CLAUDE_PROJECT_ROOT',
            'LEADV2_STATE_ROOT', 'LEADV2_STATE_PATH_BIN')}
        env.update(LEADV2_TEST_CONTEXT='1', LEADV2_STATE_BASE=str(temp / 'state'),
                   LEADV2_SUPERVISE_OBSERVE_ONLY='1', LEADV2_STATUS_LEDGER_DIR=str(temp / 'ledger'),
                   LEADV2_EVENT_LOG_DIR=str(temp / 'events'), LEADV2_SUPERVISE_TMUX_SOCKET='shadow-isolated')
        command = ['timeout', '-k', '5', '120', 'bash', str(scripts / 'leadv2-status-collector.sh')]
        result = subprocess.run(command, cwd=scripts, env=env, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
        nested = scripts / 'docs'
        exists = os.path.lexists(nested)
        census = [p for p, ds, fs in os.walk(scripts) if p == str(nested)]
        output = (scripts if variant == 'before' else root) / 'docs/leadv2/status-snapshot.json'
        snapshot = json.loads(output.read_text())
        assert result.returncode == 0, result.stdout
        assert exists == (variant == 'before'), (variant, exists)
        assert bool(census) == exists, census
        assert snapshot['sections']['lanes']['ok'], snapshot['sections']['lanes']
        print(f'{variant}: timeout -k 5 120 bash <fresh>/plugins/leadv2/scripts/leadv2-status-collector.sh (cwd=<fresh>/plugins/leadv2/scripts)')
        print(f'{variant}: nested_docs_lexists={exists} walk_count={len(census)} snapshot_exists={output.is_file()} lanes_ok={snapshot["sections"]["lanes"]["ok"]}')
        print(result.stdout.strip())
print('before-after: PASS=2 FAIL=0; two independent directory measurements agree')
