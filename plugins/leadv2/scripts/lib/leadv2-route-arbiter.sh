#!/usr/bin/env bash
# One live-window, config-driven arbiter shared by dispatch and review.
# Output is a single machine-readable line; non-zero means caller must fail open.

leadv2_route_arbiter_script_dir() {
  # Per-file installs symlink this library, while BASH_SOURCE preserves the
  # symlink spelling. Follow the chain portably before locating sibling files.
  local source="${BASH_SOURCE[0]}" link dir
  while [[ -h "$source" ]]; do
    dir="$(cd -P "$(dirname "$source")" && pwd)"
    link="$(readlink "$source")"
    [[ "$link" == /* ]] || link="$dir/$link"
    source="$link"
  done
  cd -P "$(dirname "$source")" && pwd
}

route_arbiter() { # <worker|reviewer> <task-descriptor-json>
  local role="${1:-}" descriptor="${2:-}" here routing live free_gate free_rc quota_json
  [[ "$role" == worker || "$role" == reviewer ]] || return 64
  here="$(cd "$(leadv2_route_arbiter_script_dir)/.." && pwd)"
  routing="${LEADV2_ROUTE_ARBITER_ROUTING_YAML:-${here}/../config/leadv2-routing.yaml}"
  [[ -r "$routing" ]] || return 65
  # T17 fix-round (H4): honour the repo's established quota-live seam name
  # (LEADV2_QUOTA_LIVE -- leadv2-burn-governor.sh, leadv2-glm-quota-gate.sh,
  # leadv2-main-model-check.sh) before falling to the arbiter-only spelling,
  # so a caller/test that stubs the common seam also stubs the arbiter.
  live="${LEADV2_ROUTE_ARBITER_QUOTA_LIVE:-${LEADV2_QUOTA_LIVE:-${here}/leadv2-quota-live.sh}}"
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
import json, os, sys, tempfile
try:
    import yaml
    data=yaml.safe_load(open(sys.argv[1])) or {}
    d=json.loads(os.environ['ROUTE_ARBITER_DESCRIPTOR'])
    q=json.loads(os.environ['ROUTE_ARBITER_QUOTA'])
except Exception:
    raise SystemExit(2)
role=os.environ['ROUTE_ARBITER_ROLE']; free_ok=os.environ.get('ROUTE_ARBITER_FREEPOOL_RC')=='0'
# T17 fix-round (C1): normalize kind to the matrix vocabulary. Real callers
# pass fanout-class-funnel / backlog-pump (now first-class matrix entries,
# see config/leadv2-routing.yaml) plus the abstract code|docs|review|plan|
# audit|safety set. Any OTHER value (a future caller, a typo) falls open to
# `code` rather than refusing -- this is a second, defensive layer under the
# matrix rows, never the caller's only path to a capable cell.
KNOWN_KINDS={'code','docs','review','plan','audit','safety','fanout-class-funnel','backlog-pump'}
kind=str(d.get('kind','code')).lower()
if kind not in KNOWN_KINDS: kind='code'
# T17 fix-round (M1): the full --task-class vocabulary is six values
# (trivial|light|standard|heavy|strategic|bulk, dispatch-code.sh usage line
# 5350); the matrix only expresses three buckets. Map every real value
# instead of silently coercing an unrecognized one to 'standard' -- a
# 'strategic' task was landing on the freepool bucket (the cheapest 'bulk'
# cell) before this fix, the opposite of intent.
SIZE_MAP={'standard':'standard','heavy':'heavy','bulk':'bulk','trivial':'standard','light':'standard','strategic':'heavy'}
size_raw=str(d.get('size',d.get('task_class','standard'))).lower()
size_unmapped = None if size_raw in SIZE_MAP else size_raw
size=SIZE_MAP.get(size_raw,'standard')
# ARMS-ADMISSION-01: `protected` alone (the lane-protected/--protected signal)
# means "this LANE writes production code under a protected path" -- it must
# NOT ban an untrusted arm from work that writes nothing dangerous (review,
# audit, plan/discovery). safety/publish/ui_judgment stay a HARD requirement
# regardless of kind -- those are about the CONTENT being touched, not the
# lane. `require_trusted` folds both into the cell filter below; `protected`
# itself is kept (unchanged name/shape) for the existing output/journal callers.
_prot_flag=bool(d.get('protected'))
_hard_flag=any(bool(d.get(k)) for k in ('safety','publish','ui_judgment'))
protected=_prot_flag or _hard_flag
writes_prod = kind not in ('review','audit','plan')
require_trusted = _hard_flag or (_prot_flag and writes_prod)
allowed_raw=d.get('allowed_arms')
allowed={str(a) for a in allowed_raw} if isinstance(allowed_raw, list) else None
def num(x):
    try:return float(x)
    except:return None
# CLASSIFIER-MUST-SEE-QUOTA-AND-RESET-DATE-01 (founder, 2026-09-03): the arbiter
# previously scored ONLY the raw used-pct of a provider's binding window --
# capped()/util() below never looked at WHEN that window resets, so "85%
# burned, resets in 20 minutes" and "85% burned, resets in 4 days" produced the
# identical verdict (switch away). leadv2-quota-read.py already computes
# hours_to_reset per window (normalize_window/with_window_truth, T1,
# leadv2-quota-read.py:113-142) and ships it inside the same JSON this arbiter
# already fetches from quota-live -- glm/codex/anthropic each publish their own
# reset_iso already (kimi is not a live build arm -- config/leadv2-routing.yaml
# marks it `dispatch: false` -- so it carries no reset to read). No new fetcher
# needed; window_period_hours/window_reset below only READ that existing field.
#
# Wait-vs-switch threshold: 10% of the WINDOW'S OWN period. Argued from the
# two live period shapes (5h burst window, 7d/168h weekly window), not picked
# free-hand -- it reproduces both founder examples exactly:
#   20 min left on a 5h window  (0.1*5h=30min)  -> 20<=30  -> WAIT
#   4 days left on a 7d window  (0.1*168h=16.8h) -> 96>16.8 -> SWITCH
# A window whose own reset cannot be read (absent/malformed reset_iso) degrades
# to that window's FULL period as hours_to_reset -- a named, defensible default
# that is always > the 10% threshold, so an unknown reset always reads as "far"
# and can never fabricate an imminent wait. Never a silent zero.
#
# CLASSIFIER-MUST-SEE-QUOTA-AND-RESET-DATE-01 fix-round item 1: an unknown
# window NAME must NOT degrade the same way as an unknown RESET. The two are
# opposite-direction failures. An unreadable reset defaults to the window's
# own (known) full period -- always "far", so it can only ever push us to
# switch, never fabricate a wait. But an unknown NAME has no known period at
# all: silently assuming DEFAULT_PERIOD_HOURS=168h (the old behaviour, now
# removed) made every genuinely SHORT unknown window look like a 168h window,
# so its threshold became 16.8h and a real 20-minute-to-reset window read as
# "near" and WAITED on an over-ceiling provider instead of switching away --
# the harmful direction, because it holds a burnt provider in the chain.
# Fix: window_period_hours() returns None for an unknown name (no
# limit_window_seconds either), and window_reset() reports period_hours=None
# with reset_basis='unknown_window' (never 'default_full_period', which means
# a DIFFERENT case: a known period, unreadable reset). near_reset_wait()
# already treats period_hours is None as False, so an unknown window name
# switches away -- exactly the pre-change behaviour -- and reset_basis
# surfaces which of the two unknowns produced the verdict.
WAIT_FRACTION_OF_PERIOD=0.10
WINDOW_PERIOD_HOURS={'five_hour':5.0,'weekly':168.0,'seven_day':168.0}
def window_period_hours(name, window):
    lws=num((window or {}).get('limit_window_seconds'))
    if lws is not None: return lws/3600.0
    return WINDOW_PERIOD_HOURS.get(name)
def window_reset(name, window):
    period=window_period_hours(name, window)
    h=num((window or {}).get('hours_to_reset'))
    if period is None: return h, None, 'unknown_window'
    if h is not None: return h, period, 'live'
    return period, period, 'default_full_period'
def util(provider):
    # T17 fix-round (C3): a provider whose probe is broken/unknown must be
    # PESSIMISTIC (maximally capped), never the cheapest-looking arm. The old
    # `return 0.0` on status!='ok' made a dead probe sort to the front of
    # every cost/util comparison and win selection forever -- reproduced 3/3
    # in the round-1 review with every real arm healthy. freepool is
    # unaffected: its own gate (free_ok) already encodes this correctly.
    # FP-08 fix-round (H1): the capability floor does NOT live here. util() is
    # a quota number; the selector ranks by EFFECTIVE COST first (the sort's
    # dominant key below). The previous attempt raised util_freepool by +50
    # here, which only tie-breaks against glm (same cost tier) and does
    # nothing against codex (cost 3..7) or sonnet (cost 5) -- falsified by the
    # round-1 live probe (freepool still selected with util_freepool=50).
    # The demotion now happens on the effective cost, right before the sort.
    empty={'pct':0.0,'unknown':False,'hours_to_reset':None,'period_hours':None,'reset_basis':'n/a'}
    if provider=='freepool':
        return dict(empty, pct=(0.0 if free_ok else 100.0))
    x=q.get('anthropic' if provider=='claude' else provider,{})
    if x.get('status')!='ok': return dict(empty, pct=100.0, unknown=True)
    if provider=='glm':
        windows={k:(x.get(k) or {}) for k in ('five_hour','weekly')}; pct_key='pct'
    elif provider=='codex':
        if x.get('limit_reached'): return dict(empty, pct=100.0)
        ws=x.get('windows') or []
        windows={(w.get('kind') or 'w%d'%i):w for i,w in enumerate(ws)}; pct_key='used_percent'
    else:
        a=next((z for z in x.get('accounts',[]) if z.get('active')), (x.get('accounts') or [{}])[0])
        windows={'five_hour':(a.get('five_hour') or {'pct':a.get('five_hour_pct'),'reset_iso':a.get('five_hour_reset_iso')}),
                 'seven_day':(a.get('seven_day') or {'pct':a.get('seven_day_pct'),'reset_iso':a.get('seven_day_reset_iso')})}
        pct_key='pct'
    # The BINDING (worst-case, highest-used) window decides both the pct AND
    # -- new -- travels its own reset/period with it, so a provider with two
    # windows never borrows one window's pct with a DIFFERENT window's clock.
    best_name,best_pct,best_window=None,None,None
    for name,w in windows.items():
        p=num((w or {}).get(pct_key))
        if p is None: continue
        if best_pct is None or p>best_pct: best_name,best_pct,best_window=name,p,w
    if best_pct is None: return empty
    h,period,basis=window_reset(best_name,best_window)
    return {'pct':best_pct,'unknown':False,'hours_to_reset':h,'period_hours':period,'reset_basis':basis}
_uraw={p:util(p) for p in ('glm','codex','claude','freepool')}
u={p:_uraw[p]['pct'] for p in _uraw}; unk={p:_uraw[p]['unknown'] for p in _uraw}
def near_reset_wait(provider):
    info=_uraw[provider]; h=info.get('hours_to_reset'); period=info.get('period_hours')
    if h is None or period is None: return False
    return h <= (period * WAIT_FRACTION_OF_PERIOD)
# FP-08 fix-round (M1): the floor keys on the RAW --task-class, not the
# SIZE_MAP-folded bucket. trivial|light ("simple") fold into the 'standard'
# matrix cell for CAPABILITY lookups but must stay freepool-eligible, and
# bulk is exempt by design; strategic folds into 'heavy' and IS floored.
# FP-06 (founder ask 2026-08-28): capability_floor knob -- bulk_only (the
# default) preserves the FP-08 rule verbatim; full removes the floor so
# freepool is rank-eligible for Standard/Heavy build work. Precedence:
# env FREEPOOL_CAPABILITY_FLOOR > freepool-arm.yaml capability_floor >
# default. An unrecognized value at either layer falls through to the next
# layer -- fail toward today's floored behavior, never silently unfloored.
floor_mode='bulk_only'; floor_mode_src='default'
_env_mode=str(os.environ.get('FREEPOOL_CAPABILITY_FLOOR','') or '').strip().lower()
if _env_mode in ('bulk_only','full'):
    floor_mode=_env_mode; floor_mode_src='env'
else:
    try:
        _arm_cfg_path=os.environ.get('FREEPOOL_ARM_CONFIG') or os.path.join(os.path.dirname(os.path.abspath(sys.argv[1])),'freepool-arm.yaml')
        _arm_cfg=yaml.safe_load(open(_arm_cfg_path)) or {}
        _yaml_mode=str((_arm_cfg.get('capability_floor') if isinstance(_arm_cfg,dict) else None) or '').strip().lower()
        if _yaml_mode in ('bulk_only','full'):
            floor_mode=_yaml_mode; floor_mode_src='yaml'
    except Exception:
        pass
# FREEPOOL-MUST-ACTUALLY-GET-WORK-01: the FP-08 floor still protects
# strategic production work, but a dispatcher-proven tests/docs-only lane is
# mechanical verification work and must compete at its real cost. Missing the
# descriptor flag is conservative: test_only defaults false and the floor
# remains exactly as before.
test_only=bool(d.get('test_only'))
floor_applies = (size_raw in ('standard','heavy','strategic') and kind == 'code' and not test_only) if floor_mode=='bulk_only' else False
def ufmt():
    util_part=' '.join('util_%s=%s' % (p, 'unknown_capped' if unk[p] else '%d'%u[p]) for p in ('glm','codex','claude','freepool'))
    reset_part=' '.join('reset_%s=%s' % (p, ('%.2fh_%s' % (_uraw[p]['hours_to_reset'], _uraw[p]['reset_basis'])) if _uraw[p].get('hours_to_reset') is not None else 'n/a') for p in ('glm','codex','claude','freepool'))
    return util_part + ' ' + reset_part
ceil=((data.get('router_v2') or {}).get('quota_ceilings') or {})
def over_ceiling(provider):
    if provider=='freepool': return not free_ok
    key='claude' if provider=='claude' else provider
    c=(ceil.get(key) or {}).get('review_pct' if role=='reviewer' else 'work_pct',100)
    return u[provider] >= float(c)
# CLASSIFIER-MUST-SEE-QUOTA-AND-RESET-DATE-01: an over-ceiling provider whose
# binding window resets within the wait threshold is NOT excluded -- the task
# waits on it (it stays in `ok` and competes on cost as before, so it is only
# picked again if it is still cheapest) instead of being forced to switch to a
# pricier arm minutes before its own quota would have refreshed anyway. A
# provider that is over ceiling with a FAR reset is unaffected: still capped,
# still switches, exactly today's behaviour.
_waited=[p for p in ('glm','codex','claude') if over_ceiling(p) and near_reset_wait(p)]
def capped(provider):
    if over_ceiling(provider) and near_reset_wait(provider):
        return False
    return over_ceiling(provider)
cells=((data.get('router_v2') or {}).get('capability_matrix') or [])
# T17 fix-round (C1): split the config-vocabulary gap ("no cell matches kind/
# size/protected" -- a routing.yaml drift, never a real refusal) from the
# capacity gap ("every matching cell is over its quota ceiling" -- a true
# refusal). The old code raised the same SystemExit(3)/all_arms_capped for
# both, so a config typo like the fanout-class-funnel/backlog-pump miss
# above produced an honest-looking `reason=all_arms_capped util_glm=10` line
# while glm sat at 10% -- a false statement about the world. The caller
# (leadv2-dispatch-code.sh) only special-cases rc=3 all_arms_capped as a
# hard refusal (exit 4); any other non-zero rc already falls open to the
# ladder, so no caller-side change is needed for the split itself.
complexity=str(d.get('complexity','unknown')).lower()
duration_class=str(d.get('duration_class','unknown')).lower()
capable=[c for c in cells if kind in c.get('kinds',[]) and size in c.get('sizes',[]) and (not require_trusted or c.get('protected',False)) and (allowed is None or c.get('arm') in allowed)]
if not capable:
    print('arm=refuse model=none tier=none reason=no_capable_cell chain= %s' % ufmt())
    raise SystemExit(68)
ok=[c for c in capable if not capped(c.get('provider'))]
if not ok:
    print('arm=refuse model=none tier=none reason=all_arms_capped chain= %s' % ufmt())
    raise SystemExit(3)
# FP-08 fix-round (H1): demote freepool in the dimension the selector ACTUALLY
# ranks by -- effective cost, the sort's dominant key. +100 clears the whole
# real cost range (max real cost: opus 9), so a floored freepool sorts after
# codex (3..7) and sonnet (5) yet stays in the chain as the last-resort
# fallback if every capable arm later benches. Demoted rank is only APPLIED
# when freepool is actually in the candidate set; otherwise the task never
# contended for it and no floor token is emitted.
floor_reason = '%s/%s' % (size_raw, kind) if (floor_applies and any(c.get('arm')=='freepool' for c in ok)) else ''
# COMPLEXITY-ESTIMATOR-IS-OFF-01 (Critical #3, "who does it"): data-driven
# cost penalty, same mechanism the freepool floor above already uses (a cost
# bump on the sort's dominant key), so a complex/long task naturally sorts
# past a cell whose config marks it too cheap for that shape of work. Config-
# only -- router_v2.complexity_penalty absent or empty is a no-op (today's
# behavior, byte-identical). Never a hardcoded arm name: rules match cell
# `tags` (e.g. cheap/mechanical/bulk/background), which config already uses
# to describe glm-flash/freepool/glm above.
complexity_penalty_rules=((data.get('router_v2') or {}).get('complexity_penalty') or [])
def complexity_penalty(c):
    total=0.0
    tags=set(c.get('tags') or [])
    for rule in complexity_penalty_rules:
        if not isinstance(rule, dict):
            continue
        want_complexity=set(rule.get('complexities') or [])
        want_duration=set(rule.get('duration_classes') or [])
        penalize_tags=set(rule.get('penalize_tags') or [])
        if want_complexity and complexity not in want_complexity:
            continue
        if want_duration and duration_class not in want_duration:
            continue
        if penalize_tags and not (tags & penalize_tags):
            continue
        try:
            total += float(rule.get('penalty', 0))
        except (TypeError, ValueError):
            continue
    return total
def ecost(c):
    return float(c.get('cost',999)) + (100.0 if (floor_applies and c.get('arm')=='freepool') else 0.0) + complexity_penalty(c)
ok.sort(key=lambda c:(ecost(c),u[c['provider']],c['arm'],c.get('tier','')))
seen=set(); chain=[]
for c in ok:
    if c['arm'] not in seen: chain.append(c['arm']); seen.add(c['arm'])
state=os.environ['ROUTE_ARBITER_STATE_FILE']
# FP-08 fix-round (H2): the state file is a JSON object (arm + task stamp +
# floor bookkeeping) since 3ffef47, but this anti-sticky reader still did a
# bare .strip() and compared it against arm names -- `last` never matched any
# arm, alternatives[0]==ok[0] always, and T17 arm rotation was silently off
# (caught red by test-route-arbiter.sh case (d) on the merged tree). Parse the
# object; any unparseable/legacy-bare file rotates (last='').
last=''
try: last=(json.load(open(state)) or {}).get('arm','') or ''
except Exception: last=''
# Anti-stickiness is stronger than a static lowest-utilization preference:
# when an equally-priced alternative exists, do not spend the same arm twice.
# Price comparison is on EFFECTIVE cost so a floored freepool never counts as
# the same price tier as an unfloored cost-1 arm.
price=ecost(ok[0]); alternatives=[c for c in ok if ecost(c)==price and c['arm']!=last]
w=alternatives[0] if alternatives else ok[0]
# EFFORT-IS-NOT-WIRED-01: resolve effort from the SAME winning cell `w`, in
# the SAME call that picked the arm -- never a second decision. Data-driven
# (config/leadv2-routing.yaml router_v2.effort_matrix), never a name literal:
# rows match on the winning cell's tags/kind/protected, first match wins, a
# missing/empty matrix (or no match) falls open to 'medium' (never crashes).
def _effort_row_matches(row):
    if row.get('default'): return True
    if 'tags' in row:
        if not (set(row.get('tags') or []) & set(w.get('tags') or [])): return False
    if 'kinds' in row and kind not in (row.get('kinds') or []): return False
    if 'protected' in row and bool(row['protected']) != protected: return False
    return True
effort='medium'
for _row in ((data.get('router_v2') or {}).get('effort_matrix') or []):
    if _effort_row_matches(_row):
        effort = _row.get('effort', 'medium'); break
# FP-08 fix-round (M3/L1/L2): atomic write (same-dir tempfile + os.replace),
# task-stamped, fd closed -- the old `json.dump(..., open(state,'w'))` inside
# `try/except: pass` leaked the fd and, on a failed write, silently left the
# PREVIOUS run's state on disk to be attributed to this task by any reader.
# `task` lets a reader validate provenance; json is already imported at the
# top of this heredoc (the inner `import json` is gone).
try:
    _sdir=os.path.dirname(state) or '.'
    os.makedirs(_sdir,exist_ok=True)
    _fd,_tmp=tempfile.mkstemp(dir=_sdir,prefix='.route-arbiter-',suffix='.tmp')
    try:
        with os.fdopen(_fd,'w') as _sf:
            json.dump({'arm':w['arm'],'task':str(d.get('task','')),'floor_applied':bool(floor_reason),'floor_reason':floor_reason}, _sf)
        os.replace(_tmp,state)
    except BaseException:
        try: os.unlink(_tmp)
        except OSError: pass
        raise
except Exception: pass
# T17 fix-round (H1): emit the chain with the anti-sticky PICK first, then
# the remaining cost-ordered arms. The spawn loop (leadv2-dispatch-code.sh)
# iterates candidate_arms in order starting at index 0 -- before this fix
# `chain=` was a pure cost sort that never varied, so `arm=` (the rotation
# pick) was a value no spawn ever corresponded to and anti-stickiness never
# affected which arm actually ran.
rotated=[w['arm']]+[a for a in chain if a != w['arm']]
_extra = (' size_unmapped=%s' % size_unmapped) if size_unmapped else ''
# FP-08 fix-round (H1/H3): the floor journal rides on the arbiter's OWN output
# line for THIS invocation (never a cross-run state file a stale read could
# misattribute), as explicit tokens -- not a Python bool printed raw, which
# rendered `True` and never matched dispatch-code's `== "true"` comparison
# (round-1 H3, the journal line was unreachable dead code).
_floor = (' floor_applied=1 floor_reason=%s' % floor_reason) if floor_reason else ''
_fmode = ' floor_mode=%s floor_mode_source=%s test_only=%d' % (floor_mode, floor_mode_src, 1 if test_only else 0)
# COMPLEXITY-ESTIMATOR-IS-OFF-01 (Critical #3): name the estimate that fed
# this decision -- absent from the descriptor (an older/unpatched caller)
# renders as "unknown", never a blank/missing token.
_complexity = ' complexity=%s duration_class=%s' % (complexity, duration_class)
# CLASSIFIER-MUST-SEE-QUOTA-AND-RESET-DATE-01: name the winning arm's own
# remaining budget and reset distance on the SAME line the arm was picked on
# -- a decision that cannot be read back from the journal did not happen.
_w_info=_uraw.get(w.get('provider'), {})
if _w_info.get('unknown'):
    _w_remaining='unknown'
elif _w_info.get('pct') is None:
    _w_remaining='n/a'
else:
    _w_remaining='%.1f' % (100.0 - _w_info['pct'])
_w_reset=('%.2fh' % _w_info['hours_to_reset']) if _w_info.get('hours_to_reset') is not None else 'n/a'
_quota = ' remaining=%s reset_in=%s reset_basis=%s' % (_w_remaining, _w_reset, _w_info.get('reset_basis','n/a'))
_wait = (' wait_applied=%s' % ','.join(_waited)) if _waited else ''
print('arm=%s model=%s tier=%s effort=%s reason=cheapest_capable chain=%s %s%s%s%s%s%s%s' % (w['arm'],w['model'],w.get('tier','standard'),effort,','.join(rotated),ufmt(),_extra,_floor,_fmode,_complexity,_quota,_wait))
PY
}
