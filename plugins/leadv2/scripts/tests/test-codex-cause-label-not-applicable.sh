#!/usr/bin/env bash
# run-all-triggers: codex-task
set -euo pipefail
src="${CODEX_TASK_TEST_SOURCE:-$(cd "$(dirname "$0")/.." && pwd)/codex-task.sh}"
python3 - "$src" <<'PY'
import ast, datetime, json, os, pathlib, re, subprocess, sys, tempfile
from unittest.mock import patch
source=pathlib.Path(sys.argv[1]).read_text()
match=re.search(r"python3 - [^\n]*CODEX_REAP_STATE_ROOT[^\n]*<<'PY'\n(.*?)\nPY\n",source,re.S)
assert match, 'production reaper missing'
# Execute definitions/imports only, never the top-level sweep against real jobs.
tree=ast.parse(match.group(1))
tree.body=[n for n in tree.body if isinstance(n,(ast.Import,ast.ImportFrom,ast.FunctionDef))]
g={};exec(compile(tree,'production-reaper','exec'),g)
g.update(queued_kill_min=45,running_kill_min=5,_APP_SERVER_PROBE={})
with tempfile.TemporaryDirectory(prefix='codex-label-test-') as temp:
    root=pathlib.Path(temp); standalone=root/'packages/standalone/current/codex'
    def check(name, installed, rc, stdout, expected):
        if installed:
            standalone.parent.mkdir(parents=True,exist_ok=True)
            standalone.write_text('fixture');standalone.chmod(0o700)
        elif standalone.exists(): standalone.unlink()
        g['_APP_SERVER_PROBE'].clear()
        job=root/(name+'.json')
        old=(datetime.datetime.now(datetime.timezone.utc)-datetime.timedelta(hours=2)).isoformat()
        job.write_text(json.dumps(dict(id=name,status='running',phase='running',pid=99999999,startedAt=old,createdAt=old)))
        result=subprocess.CompletedProcess([],rc,stdout,'')
        with patch.dict(os.environ,{'CODEX_HOME':temp}), patch.object(g['subprocess'],'run',return_value=result):
            reaped=g['reap_one'](str(job))
        assert reaped, 'fixture did not reach reap'
        data=json.loads(job.read_text())
        assert data['errorMessage']=='reaped: '+expected, f'{name}: {data["errorMessage"]}'
        assert data['status']=='failed'
        print(f'PASS {name}: {data["errorMessage"]}')
    unknown='worker_died_stale_cause_unknown'
    check('npm_not_applicable',False,1,'',unknown)
    check('standalone_absent',True,1,'','transport_gone_app_server_absent')
    check('standalone_alive',True,0,'123\n',unknown)
    check('probe_error',True,2,'',unknown)
    check('empty_probe',True,0,'',unknown)
PY
