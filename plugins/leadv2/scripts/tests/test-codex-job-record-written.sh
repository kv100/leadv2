#!/usr/bin/env bash
# run-all-triggers: codex-task
# Offline boundary test: actual wrapper environment and status fallback, Node
# fixture implementing companion state.mjs's CLAUDE_PLUGIN_DATA/TMPDIR contract.
set -euo pipefail
src="${CODEX_TASK_TEST_SOURCE:-$(cd "$(dirname "$0")/.." && pwd)/codex-task.sh}"
python3 - "$src" <<'PY'
import os, pathlib, re, subprocess, sys, tempfile
source = pathlib.Path(sys.argv[1]).read_text()
fn = re.search(r'^_codex_state_environment\(\) \{\n.*?^\}', source, re.M | re.S)
assert fn, 'missing production state environment function'
start = source.index('if [[ "$SUB" == "status" ]]; then')
end = source.index('\n# Default tier', start)
with tempfile.TemporaryDirectory(prefix='codex-record-test-') as temp:
    root = pathlib.Path(temp)
    companion = root/'companion.mjs'
    # The fixture writes real job JSON before returning a handle. No fabricated
    # success line can satisfy either the file assertion or production reader.
    companion.write_text('''import fs from 'node:fs'; import os from 'node:os'; import path from 'node:path';
const root = process.env.CLAUDE_PLUGIN_DATA ? path.join(process.env.CLAUDE_PLUGIN_DATA, 'state') : path.join(os.tmpdir(), 'codex-companion');
const [verb,id] = process.argv.slice(2);
const dir = path.join(root, verb === 'write' ? 'lane-hash' : 'main-hash', 'jobs');
const file = path.join(dir,id+'.json');
if (verb === 'write') {
 fs.mkdirSync(dir,{recursive:true});
 fs.writeFileSync(file,JSON.stringify({id,status:'completed',phase:'done',workspaceRoot:'/lane',logFile:'/lane/log'}));
 console.log(id);
} else if (fs.existsSync(file)) console.log(fs.readFileSync(file,'utf8'));
else { console.error('No job found for '+id); process.exitCode=1; }
''')
    env = os.environ.copy()
    env.update(HOME=str(root/'home'), TMPDIR=temp, CLAUDE_PLUGIN_DATA=str(root/'foreign-plugin'))
    env.pop('CODEX_GUARD_STATE_ROOT',None)
    setup = fn.group()+'\n_codex_state_environment\n'
    for name, override in [('default',None), ('override',str(root/'custom'/'state'))]:
        e = env.copy()
        if override: e['CODEX_GUARD_STATE_ROOT'] = override
        expected = pathlib.Path(override or str(root/'home/.claude/plugins/data/codex-openai-codex/state'))
        job = 'task-record-'+name
        writer = subprocess.run(['bash','-euc',setup+'node "$1" write "$2"','test',str(companion),job],env=e,text=True,capture_output=True)
        assert writer.returncode == 0, writer.stderr
        record = expected/'lane-hash/jobs'/f'{job}.json'
        assert record.is_file(), f'ABSENT job record at reader root: {record}; writer stdout={writer.stdout}'
        reader_script = setup+'COMPANION="$1"\nshift\nSUB=status\n'+source[start:end]
        reader = subprocess.run(['bash','-euc',reader_script,'test',str(companion),'status',job,'--json'],env=e,text=True,capture_output=True)
        import json
        assert reader.returncode == 0, f'record unreadable: {reader.stdout} {reader.stderr}'
        assert json.loads(reader.stdout)['job']['status'] == 'completed', reader.stdout
        print(f'PASS {name}: job_record_written=1 cross_workspace_readable=1 status=completed')
    e = env.copy(); e['CODEX_GUARD_STATE_ROOT']=str(root/'incompatible')
    r=subprocess.run(['bash','-euc',setup],env=e,text=True,capture_output=True)
    assert r.returncode != 0, 'incompatible state override silently accepted'
    print('PASS incompatible root refused before launch')
PY
