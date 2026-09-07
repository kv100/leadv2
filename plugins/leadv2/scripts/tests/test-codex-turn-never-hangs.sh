#!/usr/bin/env bash
# run-all-triggers: codex-task
# Exercise the actual adapter preamble + _run_node with a protocol-boundary
# companion fixture. The child really exits mid-turn; the turn never settles.
# Without the race Node exits 13 (unsettled top-level await); assertions inspect
# the persisted cause, not that exit code or a timeout. No live credentials.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
T="$(mktemp -d /tmp/codex-turn-test.XXXXXX)"
trap 'rm -rf "$T"' EXIT
python3 - "$ROOT/codex-task.sh" "$T" <<'PY'
import pathlib,sys
s=pathlib.Path(sys.argv[1]).read_text(); t=pathlib.Path(sys.argv[2])
a=s.index('_codex_worker_owned_app_server() {'); b=s.index('\n# C1 ',a)
(t/'adapter.sh').write_text(s[a:b])
PY
mkdir -p "$T/lib"
cat > "$T/lib/app-server.mjs" <<'JS'
import { spawn } from 'node:child_process';
let connections = 0;
export class CodexAppServerClient {
  static async connect(cwd, options) {
    connections++;
    if (process.env.FIXTURE === 'connect-error') throw new Error('ordinary_connect_error');
    const client = { options, number: connections };
    client.proc = spawn(process.execPath, ['-e', 'setInterval(()=>{},1000)'], {stdio:'ignore'});
    client.exitPromise = new Promise(resolve => client.proc.once('exit', resolve));
    client.close = async () => { client.proc.kill('SIGTERM'); await client.exitPromise; };
    if (process.env.FIXTURE === 'missing-exit') delete client.exitPromise;
    return client;
  }
}
if (process.env.FIXTURE === 'missing-connect') CodexAppServerClient.connect = undefined;
JS
cat > "$T/lib/state.mjs" <<'JS'
import fs from 'node:fs';
export const resolveJobFile = (cwd,id) => cwd + '/' + id + '.json';
export const readJobFile = file => JSON.parse(fs.readFileSync(file));
export const writeJobFile = (cwd,id,data) => fs.writeFileSync(resolveJobFile(cwd,id),JSON.stringify(data));
export const upsertJob = (cwd,data) => fs.writeFileSync(cwd+'/index.json',JSON.stringify(data));
JS
cat > "$T/lib/tracked-jobs.mjs" <<'JS'
import * as state from './state.mjs';
export async function runTrackedJob(job,runner) {
  const write = data => state.writeJobFile(job.workspaceRoot,job.id,{...job,...data});
  write({status:'running'});
  try {
    const result=await runner();
    // Upstream success writes its original runningRecord, discarding extras.
    write({status:'completed',result});
    return result;
  } catch(e) { write({status:'failed',errorMessage:e.message}); throw e; }
}
JS
cat > "$T/lib/codex.mjs" <<'JS'
import { CodexAppServerClient } from './app-server.mjs';
export async function runAppServerTurn(cwd,options) {
  const c=await CodexAppServerClient.connect(cwd);
  try {
    if (!c.options.disableBroker) throw new Error('shared_broker_used');
    if (process.env.FIXTURE === 'ordinary-error') throw new Error('ordinary_turn_error');
    if (process.env.FIXTURE === 'killed' || (process.env.FIXTURE === 'recover' && c.number === 1)) {
      c.proc.kill('SIGKILL');
      return await new Promise(()=>{});
    }
    return {status:'completed', text:'fixture result'};
  } finally { await c.close(); }
}
export const runAppServerReview = runAppServerTurn;
JS
cat > "$T/codex-companion.mjs" <<'JS'
import { runAppServerTurn, runAppServerReview } from './lib/codex.mjs';
import { runTrackedJob } from './lib/tracked-jobs.mjs';
const job={id:process.env.FIXTURE_ID,workspaceRoot:process.env.FIXTURE_DIR};
try {
  await runTrackedJob(job,()=> (process.argv[2] === 'review' ? runAppServerReview : runAppServerTurn)(job.workspaceRoot,{
    onProgress: event => console.error(event.message)
  }));
} catch(e) { console.error(e.message); process.exitCode=1; }
JS
cat > "$T/run.sh" <<'SH'
set -euo pipefail
source "$FIXTURE_DIR/adapter.sh"
COMPANION="$FIXTURE_DIR/codex-companion.mjs"
_CODEX_SCRIPT_DIR="$ADAPTER_SCRIPT_DIR"
_TIMEOUT_CMD=""; _CODEX_TIMEOUT=10; _TIER=""
# Bound by Python below. Use the timeout binary when available so a fixture
# cannot leave a sleep watcher behind; fail if this test prerequisite is absent.
if command -v timeout >/dev/null; then _TIMEOUT_CMD=timeout; else _TIMEOUT_CMD=gtimeout; fi
_run_node "$@"
SH
python3 - "$T" "$ROOT" <<'PY'
import json,os,pathlib,subprocess,sys
p=pathlib.Path(sys.argv[1]); root=sys.argv[2]; failed=0
CAUSE='codex_worker_exited_before_turn_completed'
def check(ok,label,actual=None):
    global failed
    print(('PASS: ' if ok else 'FAIL: ')+label+((' actual='+json.dumps(actual)) if not ok else ''))
    failed+=not ok
for name,mode in [('missing-connect','task'),('killed','task-worker'),('recover','task-worker'),('normal','task-worker'),
                  ('normal','task'),('normal','review'),('ordinary-error','task'),
                  ('connect-error','task'),('missing-exit','task')]:
    jid=name+'-'+mode
    env={**os.environ,'FIXTURE':name,'FIXTURE_ID':jid,'FIXTURE_DIR':str(p),
         'ADAPTER_SCRIPT_DIR':root,'LEADV2_EVENT_LOG_DIR':str(p/'journal')}
    # Production _run_node injects the preload on both command paths.
    args=['bash',str(p/'run.sh'),mode]
    if mode=='task-worker': args+=['--background']
    r=subprocess.run(args,env=env,text=True,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,timeout=15)
    f=p/(jid+'.json'); job=json.loads(f.read_text()) if f.exists() else {}
    entries=job.get('codexAttempts',[]); starts=[e for e in entries if e['status']=='started']
    errors=[e for e in entries if e['status']=='failed']
    if name=='killed':
        check(job.get('errorMessage')==CAUSE,'killed app-server CAUSE LABEL',job.get('errorMessage'))
        check(len(starts)==2 and [e['attempt'] for e in starts]==[1,2], 'exactly one retry in same record',entries)
        check(len(errors)==2 and all(e['cause']==CAUSE for e in errors),'both failed attempts carry typed cause',errors)
        check(len({e['appServerPid'] for e in starts})==2,'retry owns a fresh process',starts)
        journal=''.join(f.read_text() for f in (p/'journal').glob('*.jsonl'))
        check(journal.count(CAUSE)==2 and journal.count(jid)==2,'journal attributes both exits to job',journal)
    elif name=='recover':
        check(r.returncode==0 and job.get('status')=='completed' and len(starts)==2 and len(errors)==1,
              'first exit then successful retry retains both attempts',job)
    elif name=='normal':
        check(r.returncode==0 and job.get('status')=='completed' and len(starts)==1 and not errors,
              mode+' completion and normal close do not retry',job)
        check(job.get('codexTransport')=='worker-owned' and 'transport=worker-owned app-server' in r.stdout,
              mode+' owned transport is in record and log',job)
    elif name=='missing-connect':
        check(r.returncode!=0 and 'codex_companion_api_incompatible:connect_missing' in r.stdout and not job,
              'missing connect refuses launch',{'rc':r.returncode,'job':job,'output':r.stdout[-700:]})
    elif name=='missing-exit':
        check('codex_companion_api_incompatible:exitPromise_or_close_missing'==job.get('errorMessage') and len(errors)==1,
              'missing exitPromise refuses turn without retry',job)
    else:
        check(job.get('status')=='failed' and len(errors)==1 and len(starts)<=1,
              name+' never retries',job)
print(f'[CODEX-TURN-NEVER-HANGS] fail={failed}')
sys.exit(bool(failed))
PY
