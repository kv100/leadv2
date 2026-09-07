#!/usr/bin/env bash
# run-all-triggers: codex-task
# Exercise the production preload AND _run_node with real subprocesses. The
# offline companion fixture injects the observed broker SIGKILL after exit 1;
# assert the terminal job JSON and a written file, never a progress/marker line.
set -euo pipefail
src="${CODEX_TASK_TEST_SOURCE:-$(cd "$(dirname "$0")/.." && pwd)/codex-task.sh}"
# Optional live integration: real companion, real Codex, real job store. Inject
# SIGKILL only into this isolated fixture's broker after the deliberate exit 1.
# The sender of the historical SIGKILL is unknown; this reproduces its effect.
if [[ "${1:-}" == "--live" ]]; then
  python3 - "$src" "$(cd "$(dirname "$0")/.." && pwd)" <<'PYLIVE'
import json, os, pathlib, re, signal, subprocess, sys, tempfile, time
source, scripts = map(pathlib.Path, sys.argv[1:])
root=pathlib.Path(tempfile.mkdtemp(prefix='codex-nonzero-live-'))
print('LIVE_ARTIFACTS='+str(root),flush=True)
(root/'plugin/scripts').mkdir(parents=True)
for path in scripts.parent.iterdir():
    if path.name!='scripts': (root/'plugin'/path.name).symlink_to(path.resolve(),target_is_directory=path.is_dir())
for path in scripts.iterdir():
    if path.name!='codex-task.sh': (root/'plugin/scripts'/path.name).symlink_to(path.resolve(),target_is_directory=path.is_dir())
launcher=root/'plugin/scripts/codex-task.sh';launcher.write_bytes(source.read_bytes());launcher.chmod(0o700)
work=root/'work';work.mkdir()
(work/'answer.py').write_text('def answer():\n    raise NotImplementedError\n')
(work/'test_answer.py').write_text('import unittest\nfrom answer import answer\nclass Test(unittest.TestCase):\n    def test_answer(self): self.assertEqual(answer(), 42)\n')
for args in [['init'],['add','--','answer.py','test_answer.py'],['-c','user.name=Probe','-c','user.email=probe@example.invalid','commit','-m','fixture baseline']]:
    subprocess.run(['git',*args],cwd=work,check=True,capture_output=True,text=True)
env=os.environ.copy();env.pop('NODE_OPTIONS',None)
env['CODEX_GUARD_STATE_ROOT']=str(root/'plugin-data/state')
env['LEADV2_ARM_COOLDOWN_DIR']=str(root/'cooldown')
prompt="In this isolated fixture only: first run exactly `grep CODEX_EXPECTED_ABSENCE /dev/null` as a separate shell command; exit 1 is expected. Then run `python3 -m unittest -v` to show the failing test. Implement answer.py to return 42, without changing the test. Run tests again, then git diff --stat. Do not commit or start other jobs. Keep the nonempty diff."
r=subprocess.run(['bash',str(launcher),'task',prompt,'--background','--cwd',str(work),'--tier','standard'],cwd=scripts.parent.parent.parent,env=env,capture_output=True,text=True,timeout=60)
(root/'launch.stdout').write_text(r.stdout);(root/'launch.stderr').write_text(r.stderr)
print(r.stdout+r.stderr,flush=True);assert r.returncode==0, f'launcher rc={r.returncode}'
j=re.search(r'task-[a-z0-9]+-[a-z0-9]+',r.stdout).group()
killed=False;job=None
try:
    for i in range(210):
        paths=list((root/'plugin-data/state').glob('*/jobs/'+j+'.json'))
        if paths:
            path=paths[0];job=json.loads(path.read_text());log=path.with_suffix('.log').read_text()
            if not killed and 'Command failed:' in log and '(exit 1)' in log:
                broker=path.parent.parent/'broker.json'
                if broker.is_file():
                    pid=int(json.loads(broker.read_text())['pid'])
                    cmd=subprocess.run(['ps','-p',str(pid),'-o','command='],capture_output=True,text=True).stdout
                    assert 'app-server-broker.mjs' in cmd and str(work.resolve()) in cmd, 'refuse to signal unrelated process'
                    os.kill(pid,signal.SIGKILL);killed=True
                    (root/'injected-signal.txt').write_text(f'broker_pid={pid} signal=SIGKILL after_exit=1\n')
                    print(f'FAULT broker_pid={pid} SIGKILL after exit 1',flush=True)
            if job['status'] not in ('queued','running'):break
        time.sleep(1)
    else: raise AssertionError('job did not reach terminal state within 210s')
finally:
    if job and job['status'] in ('queued','running'):
        cancel=subprocess.run(['bash',str(launcher),'cancel',j,'--cwd',str(work)],env=env,capture_output=True,text=True,timeout=30)
        print(cancel.stdout+cancel.stderr,flush=True)
assert 'Command failed:' in log and '(exit 1)' in log, 'no deliberate command failure observed'
assert job['status']=='completed',f'terminal job record after exit 1: {job["status"]} {job.get("errorMessage")}; artifacts={root}'
diff=subprocess.check_output(['git','diff','--','answer.py'],cwd=work,text=True)
(root/'result.diff').write_text(diff)
assert diff.strip(),'empty diff'
print(f'PASS LIVE job={j} deliberate_exit=1 terminal_status=completed nonempty_diff=1 artifacts={root}')
PYLIVE
  exit $?
fi
python3 - "$src" <<'PY'
import json, os, pathlib, re, subprocess, sys, tempfile
source=pathlib.Path(sys.argv[1]).read_text()
def function(name):
    if name == '_codex_worker_owned_app_server':
        start=source.index(name+'() {')
        return source[start:source.index('\n_run_node() {',start)]
    m=re.search(r'^'+re.escape(name)+r'\(\) \{\n.*?^\}',source,re.M|re.S)
    assert m, 'missing production function '+name
    return m.group()
with tempfile.TemporaryDirectory(prefix='codex-nonzero-test-') as temp:
    root=pathlib.Path(temp);(root/'lib').mkdir()
    # Public companion transport API fixture. A worker-owned runtime is not
    # subject to an independently killed broker. Both modes spawn a real child.
    (root/'lib/app-server.mjs').write_text('''import {spawn} from 'node:child_process';
import {once} from 'node:events';
export class CodexAppServerClient {
 static async connect(cwd, options={}) {
  const child=spawn(process.execPath,['-e',"setInterval(()=>{},1000);process.stdout.write('ready\\\\n')"],{stdio:['ignore','pipe','inherit']});
  const ended=once(child,'exit');
  await once(child.stdout,'data');
  return {child,ended,transport:options.disableBroker?'direct':'broker'};
 }
}
''')
    (root/'codex-companion.mjs').write_text('''import {spawn,spawnSync} from 'node:child_process';
import {once} from 'node:events';
import fs from 'node:fs';
import {CodexAppServerClient} from './lib/app-server.mjs';
const jobFile=process.env.PROBE_JOB;
if(process.argv[2]==='task') {
 // Like the companion, the worker is a second Node process. The preload must
 // survive this boundary; patching only the launcher's in-memory module fails.
 const worker=spawn(process.execPath,[process.argv[1],'task-worker'],{stdio:'inherit'});
 const [code]=await once(worker,'exit');process.exitCode=code;
} else {
 let job={status:'running',phase:'running'};
 fs.writeFileSync(jobFile,JSON.stringify(job));
 const client=await CodexAppServerClient.connect(process.cwd(),{testOption:42});
 try {
  const bad=spawnSync('grep',['CODEX_EXPECTED_ABSENCE','/dev/null']);
  if(bad.status!==1)throw new Error('fixture did not execute deliberate exit 1');
  job.nonzeroExit=bad.status;
  // Fault injection: reproduce the observed external broker death, not a
  // made-up rule that interprets every failed command as a failed turn.
  if(client.transport==='broker') {
   client.child.kill('SIGKILL');
   const [code,signal]=await client.ended;
   job={...job,status:'failed',phase:'failed',signal};
  } else {
   const good=spawnSync('sh',['-c','printf "implemented after exit 1\\\\n" > result.txt']);
   if(good.status!==0)throw new Error('write after exit 1 failed');
   job={...job,status:'completed',phase:'done',successExit:good.status};
  }
 } finally {
  if(client.child.exitCode===null && client.child.signalCode===null)client.child.kill('SIGTERM');
  await client.ended;
  fs.writeFileSync(jobFile,JSON.stringify(job));
 }
}
''')
    script='\n'.join([function('_codex_worker_owned_app_server'),function('setsid_wrapper'),function('_run_node')])
    driver=root/'drive.sh'
    driver.write_text('set -euo pipefail\n'+script+'''
COMPANION="$1"
_TIMEOUT_CMD="$(command -v timeout || command -v gtimeout || true)"
_CODEX_TIMEOUT=20
_run_node task --background
''')
    env=os.environ.copy();env['PROBE_JOB']=str(root/'job.json')
    # Preserve a genuine pre-existing Node option; do not overwrite user options.
    env['NODE_OPTIONS']='--no-warnings'
    r=subprocess.run(['bash',str(driver),str(root/'codex-companion.mjs')],cwd=root,env=env,capture_output=True,text=True,timeout=30)
    assert r.returncode==0, f'fixture launch failed rc={r.returncode}: {r.stdout} {r.stderr}'
    job=json.loads((root/'job.json').read_text())
    assert job.get('nonzeroExit')==1,job
    assert job['status']=='completed', f'terminal job record after exit 1: {job}'
    assert (root/'result.txt').stat().st_size>0,'no file written after exit 1'
    print('PASS: deliberate_exit=1 terminal_status=completed nonempty_file=1')
    # Preload must not change ordinary Node execution or foreground companion.
    check=subprocess.run(['bash','-euc',function('_codex_worker_owned_app_server')+'\n_codex_worker_owned_app_server\nnode -e "process.exit(0)"'],cwd=root,env=env,capture_output=True,text=True,timeout=10)
    assert check.returncode==0,check.stderr
    print('PASS: unrelated Node invocation unaffected')
PY
