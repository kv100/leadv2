#!/usr/bin/env bash
# One live-window, config-driven arbiter shared by dispatch and review.
# Output is a single machine-readable line; non-zero means caller must fail open.

route_arbiter() { # <worker|reviewer> <task-descriptor-json>
  local role="${1:-}" descriptor="${2:-}" here routing live free_gate free_rc quota_json
  [[ "$role" == worker || "$role" == reviewer ]] || return 64
  here="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
  routing="${LEADV2_ROUTE_ARBITER_ROUTING_YAML:-${here}/../config/leadv2-routing.yaml}"
  [[ -r "$routing" ]] || return 65
  live="${LEADV2_ROUTE_ARBITER_QUOTA_LIVE:-${here}/leadv2-quota-live.sh}"
  [[ -x "$live" || -f "$live" ]] || return 66
  # A single quota-live json invocation obtains GLM, Codex and Claude windows.
  quota_json="$(bash "$live" json 2>/dev/null)" || return 67
  free_gate="${LEADV2_ROUTE_ARBITER_FREEPOOL_GATE:-${here}/lib/leadv2-freepool-gate.sh}"
  free_rc=1
  if [[ -x "$free_gate" || -f "$free_gate" ]]; then
    bash "$free_gate" check >/dev/null 2>&1; free_rc=$?
  fi
  ROUTE_ARBITER_ROLE="$role" ROUTE_ARBITER_DESCRIPTOR="$descriptor" \
  ROUTE_ARBITER_QUOTA="$quota_json" ROUTE_ARBITER_FREEPOOL_RC="$free_rc" \
  ROUTE_ARBITER_STATE_FILE="${LEADV2_ROUTE_ARBITER_STATE_FILE:-${TMPDIR:-/tmp}/leadv2-route-arbiter-last-arm}" \
  python3 - "$routing" <<'PY'
import json, os, sys
try:
    import yaml
    data=yaml.safe_load(open(sys.argv[1])) or {}
    d=json.loads(os.environ['ROUTE_ARBITER_DESCRIPTOR'])
    q=json.loads(os.environ['ROUTE_ARBITER_QUOTA'])
except Exception:
    raise SystemExit(2)
role=os.environ['ROUTE_ARBITER_ROLE']; free_ok=os.environ.get('ROUTE_ARBITER_FREEPOOL_RC')=='0'
kind=str(d.get('kind','code')).lower(); size=str(d.get('size',d.get('task_class','standard'))).lower()
if size not in ('standard','heavy','bulk'): size='standard'
protected=any(bool(d.get(k)) for k in ('protected','safety','publish','ui_judgment'))
def num(x):
    try:return float(x)
    except:return None
def util(provider):
    if provider=='freepool': return 0.0 if free_ok else 100.0
    x=q.get('anthropic' if provider=='claude' else provider,{})
    if x.get('status')!='ok': return 0.0
    if provider=='glm': vals=[num((x.get(k) or {}).get('pct')) for k in ('five_hour','weekly')]
    elif provider=='codex':
        if x.get('limit_reached'): return 100.0
        ws=x.get('windows') or []; bind=x.get('binding_window'); w=next((z for z in ws if z.get('kind')==bind),None)
        vals=[num((w or {}).get('used_percent'))] if w else [num(z.get('used_percent')) for z in ws]
    else:
        a=next((z for z in x.get('accounts',[]) if z.get('active')), (x.get('accounts') or [{}])[0])
        vals=[num(a.get(k)) for k in ('five_hour_pct','seven_day_pct')]
    vals=[z for z in vals if z is not None]; return max(vals) if vals else 0.0
u={p:util(p) for p in ('glm','codex','claude','freepool')}
ceil=((data.get('router_v2') or {}).get('quota_ceilings') or {})
def capped(provider):
    if provider=='freepool': return not free_ok
    key='claude' if provider=='claude' else provider
    c=(ceil.get(key) or {}).get('review_pct' if role=='reviewer' else 'work_pct',100)
    return u[provider] >= float(c)
cells=((data.get('router_v2') or {}).get('capability_matrix') or [])
ok=[]
for c in cells:
    p=c.get('provider')
    if role=='reviewer' and not c.get('review'): continue
    if kind not in c.get('kinds',[]) or size not in c.get('sizes',[]): continue
    if protected and not c.get('protected',False): continue
    if capped(p): continue
    ok.append(c)
if not ok:
    print('arm=refuse model=none tier=none reason=all_arms_capped chain= util_glm=%d util_codex=%d util_claude=%d util_freepool=%d' % (u['glm'],u['codex'],u['claude'],u['freepool']))
    raise SystemExit(3)
ok.sort(key=lambda c:(float(c.get('cost',999)),u[c['provider']],c['arm'],c.get('tier','')))
seen=set(); chain=[]
for c in ok:
    if c['arm'] not in seen: chain.append(c['arm']); seen.add(c['arm'])
state=os.environ['ROUTE_ARBITER_STATE_FILE']
try: last=open(state).read().strip()
except Exception: last=''
# Anti-stickiness is stronger than a static lowest-utilization preference:
# when an equally-priced alternative exists, do not spend the same arm twice.
price=float(ok[0].get('cost',999)); alternatives=[c for c in ok if float(c.get('cost',999))==price and c['arm']!=last]
w=alternatives[0] if alternatives else ok[0]
try:
    os.makedirs(os.path.dirname(state) or '.',exist_ok=True)
    open(state,'w').write(w['arm']+'\n')
except Exception: pass
print('arm=%s model=%s tier=%s reason=cheapest_capable chain=%s util_glm=%d util_codex=%d util_claude=%d util_freepool=%d' % (w['arm'],w['model'],w.get('tier','standard'),','.join(chain),u['glm'],u['codex'],u['claude'],u['freepool']))
PY
}
