#!/bin/bash
# Each agent owns one atomically replaced registry file; no shared RMW exists.
set -u
EVENT="${1:-}"; case "$EVENT" in start|stop) ;; *) exit 0;; esac
ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"; REGISTRY="${LEADV2_NATIVE_AGENT_REGISTRY:-$ROOT/.native-agent-registry}"; INPUT="$(cat 2>/dev/null || true)"
REGISTRY="$REGISTRY" EVENT="$EVENT" INPUT="$INPUT" python3 - <<'PY'
import hashlib,json,os,tempfile,time
try:
 directory,event,raw=os.environ['REGISTRY'],os.environ['EVENT'],os.environ['INPUT']
 try: payload=json.loads(raw) if raw else {}
 except Exception: payload={}
 if not isinstance(payload,dict): payload={}
 source=payload.get('tool_input') if isinstance(payload.get('tool_input'),dict) else payload
 def field(name):
  value=source.get(name,payload.get(name,'')); return str(value)[:256] if value is not None else ''
 agent=field('agent_id') or field('task_id') or field('subagent_id') or 'unknown'
 name=hashlib.sha256(agent.encode()).hexdigest()+'.json'; path=os.path.join(directory,name)
 if event=='stop':
  try: os.unlink(path)
  except FileNotFoundError: pass
  raise SystemExit
 os.makedirs(directory,exist_ok=True); now=time.strftime('%Y-%m-%dT%H:%M:%SZ',time.gmtime())
 record={'version':1,'agent_id':agent,'started_at':now,'last_pulse':now,'session_id':field('session_id'),'task_name':field('task_name')}
 fd,tmp=tempfile.mkstemp(prefix='.native-agent.',dir=directory)
 try:
  with os.fdopen(fd,'w',encoding='utf-8') as f: json.dump(record,f,sort_keys=True,separators=(',',':')); f.write('\n'); f.flush(); os.fsync(f.fileno())
  os.replace(tmp,path)
 finally:
  try: os.unlink(tmp)
  except FileNotFoundError: pass
except SystemExit:
 pass
except Exception:
 pass
PY
exit 0
