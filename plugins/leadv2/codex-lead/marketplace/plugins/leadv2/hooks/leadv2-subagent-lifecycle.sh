#!/bin/bash
# Local bounded lifecycle pulse recorder; it never invokes an LLM.
set -u
EVENT="${1:-}"; case "$EVENT" in start|stop) ;; *) exit 0;; esac
ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"; REGISTRY="${LEADV2_NATIVE_AGENT_REGISTRY:-$ROOT/.native-agent-registry.json}"; INPUT="$(cat 2>/dev/null || true)"
REGISTRY="$REGISTRY" EVENT="$EVENT" INPUT="$INPUT" python3 - <<'PY'
import json,os,tempfile,time
path,event,raw=os.environ['REGISTRY'],os.environ['EVENT'],os.environ['INPUT']
try: payload=json.loads(raw) if raw else {}
except Exception: payload={}
if not isinstance(payload,dict): payload={}
source=payload.get('tool_input') if isinstance(payload.get('tool_input'),dict) else payload
def field(name):
 v=source.get(name,payload.get(name,'')); return str(v)[:256] if v is not None else ''
agent=field('agent_id') or field('task_id') or field('subagent_id') or 'unknown'; now=time.strftime('%Y-%m-%dT%H:%M:%SZ',time.gmtime())
try:
 with open(path,encoding='utf-8') as f: state=json.load(f)
except Exception: state={}
if not isinstance(state,dict): state={}
agents=state.get('agents') if isinstance(state.get('agents'),dict) else {}
if event=='start': agents[agent]={'started_at':now,'last_pulse':now,'session_id':field('session_id'),'task_name':field('task_name')}
else: agents.pop(agent,None)
state.update({'version':1,'updated_at':now,'last_event':{'event':event,'agent_id':agent,'at':now},'agents':agents})
directory=os.path.dirname(path) or '.'; os.makedirs(directory,exist_ok=True); fd,tmp=tempfile.mkstemp(prefix='.native-agent-registry.',dir=directory)
try:
 with os.fdopen(fd,'w',encoding='utf-8') as f: json.dump(state,f,sort_keys=True,separators=(',',':')); f.write('\n'); f.flush(); os.fsync(f.fileno())
 os.replace(tmp,path)
finally:
 try: os.unlink(tmp)
 except FileNotFoundError: pass
PY
