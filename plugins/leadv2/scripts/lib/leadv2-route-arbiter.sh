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
  free_reason=""
  if [[ -x "$free_gate" || -f "$free_gate" ]]; then
    # FREEPOOL-DEAD-ARM-LOOKS-LIKE-A-BUSY-ARM-01: the gate's refusal marker
    # (LEADV2_DISPATCH_REFUSED: arm_down|gate_broken|pin_drift) previously
    # died in ">/dev/null 2>&1", so "proxy dead" and "quota burnt" both
    # arrived as the same bare non-zero rc and rendered identically below as
    # util_freepool=100 — a dead arm read as a busy one for a full day
    # (2026-09-04). Capture the stderr, parse the named reason out of it,
    # and re-emit the arm_down case loudly: the arbiter's own stderr is what
    # lands in the dispatch journal a lead actually reads.
    free_err="$(bash "$free_gate" check 2>&1 >/dev/null)"; free_rc=$?
    free_reason="$(printf '%s\n' "${free_err}" | sed -n 's/.*LEADV2_DISPATCH_REFUSED:[[:space:]]*\([A-Za-z0-9._-]\{1,\}\).*/\1/p' | head -1)"
  fi
  if [[ "${free_reason}" == "arm_down" ]]; then
    # LOUD journal line — the one fact the lead must not have to reconstruct.
    # Not auto-restarting the proxy (founder scope 2026-09-04): name the fix,
    # do not perform it.
    printf '[route-arbiter] FREEPOOL ARM DOWN: gate refused arm_down (proxy unreachable) — NOT quota exhaustion; util_freepool=down on this line. Restart with: plugins/leadv2/scripts/freepool-proxy.sh start\n' >&2
  fi
  # FP-08 CAPABILITY-FLOOR: freepool's operator surface (config/freepool-arm.yaml)
  # carries `capability_floor: bulk_only|full`. bulk_only (the default, also when
  # the file/key is unreadable) holds freepool below codex/sonnet for Standard+
  # build work; `full` is the flip FP-04's quality gate will make. Env seam for
  # tests/hermeticity: LEADV2_ROUTE_ARBITER_FREEPOOL_CONFIG.
  freepool_config="${LEADV2_ROUTE_ARBITER_FREEPOOL_CONFIG:-${here}/../config/freepool-arm.yaml}"
  ROUTE_ARBITER_ROLE="$role" ROUTE_ARBITER_DESCRIPTOR="$descriptor" \
  ROUTE_ARBITER_QUOTA="$quota_json" ROUTE_ARBITER_FREEPOOL_RC="$free_rc" \
  ROUTE_ARBITER_FREEPOOL_REASON="${free_reason}" \
  ROUTE_ARBITER_STATE_FILE="${LEADV2_ROUTE_ARBITER_STATE_FILE:-${TMPDIR:-/tmp}/leadv2-route-arbiter-last-arm}" \
  ROUTE_ARBITER_FAILURE_LEDGER="${LEADV2_ROUTE_ARBITER_FAILURE_LEDGER:-${HOME}/.claude/leadv2-state/leadv2/dispatch-ledger.jsonl}" \
  ROUTE_ARBITER_EVENTS_JOURNAL="${LEADV2_ROUTE_ARBITER_EVENTS_JOURNAL:-${HOME}/.claude/cache/leadv2-events/leadv2.jsonl}" \
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
# FREEPOOL-DEAD-ARM-LOOKS-LIKE-A-BUSY-ARM-01: the gate's named refusal reason
# (arm_down|gate_broken|pin_drift), parsed upstream from the gate's stderr
# marker. This is the difference between "dead" and "busy": pct below stays a
# NUMBER (sort/capped semantics unchanged — a dead freepool must still lose
# selection), but the RENDERING below turns arm_down into the word `down` so
# the decision line can never present a dead arm as a 100%-busy one.
free_reason=str(os.environ.get('ROUTE_ARBITER_FREEPOOL_REASON') or '').strip()
# T17 fix-round (C1): normalize kind to the matrix vocabulary. Real callers
# pass fanout-class-funnel / backlog-pump (now first-class matrix entries,
# see config/leadv2-routing.yaml) plus the abstract code|docs|review|plan|
# audit|safety set. Any OTHER value (a future caller, a typo) falls open to
# `code` rather than refusing -- this is a second, defensive layer under the
# matrix rows, never the caller's only path to a capable cell.
KNOWN_KINDS={'code','docs','review','plan','audit','safety','fanout-class-funnel','backlog-pump','build','recon'}
# ROUTING-EVERY-SPAWN-THROUGH-THE-ARBITER-01 (founder 2026-09-04): the lead-facing
# spelling is `work_kind` -- task-judge.sh already emits build|review|diagnose|docs
# under that key. `kind` stays accepted for the existing dispatch-code callers.
# `build` folds onto the existing `code` cells, so build routing is unchanged by
# construction. `recon` (read-only exploration) is a first-class kind with its own
# cheap matrix rows (config/leadv2-routing.yaml), not a code branch.
kind=str(d.get('work_kind') or d.get('kind') or 'code').lower()
if kind not in KNOWN_KINDS: kind='code'
MATRIX_KIND={'build':'code'}  # recon keeps its own name -- it has its own rows
mkind=MATRIX_KIND.get(kind,kind)
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
# recon is read-only exploration: it never writes production code, so the
# protected-lane rule must not ban a cheap untrusted arm from it.
writes_prod = kind not in ('review','audit','plan','recon')
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
        return dict(empty, pct=(0.0 if free_ok else 100.0),
                    status=('ok' if free_ok else ('down' if free_reason=='arm_down' else (free_reason or 'unknown'))))
    x=q.get('anthropic' if provider=='claude' else provider,{})
    if x.get('status')!='ok': return dict(empty, pct=100.0, unknown=True)
    if provider=='glm':
        windows={k:(x.get(k) or {}) for k in ('five_hour','weekly')}; pct_key='pct'
    elif provider=='codex':
        if x.get('limit_reached'): return dict(empty, pct=100.0)
        ws=x.get('windows') or []
        windows={(w.get('kind') or 'w%d'%i):w for i,w in enumerate(ws)}; pct_key='used_percent'
    else:
        # ARBITER-DECISION-LOGIC-CENSUS-01: the `active` flag names which
        # account CREDENTIAL the session resolved to -- it is not proof that
        # account's probe succeeded. Measured 2026-09-04: the active-flagged
        # max_20x entry read http 401 (status=unknown, every pct null) while
        # a DIFFERENT, non-active max_20x entry for the same account_label
        # carried the real, freshly-probed pct. The old code took `a` from
        # the active flag unconditionally, so a broken active credential fed
        # nulls into every window below and this function returned the
        # optimistic `empty` (pct=0.0) at line ~181 -- "claude is free" -- while
        # a probed 72%/48% sat one field over, unread. Prefer the active
        # account only when it actually reports ok; otherwise fall back to a
        # DIFFERENT account with status=='ok' -- same account_label first (the
        # true measurement for the account we believe we're using), then any
        # ok account, before ever falling to the pessimistic unknown branch
        # C3 already established for a fully-broken provider.
        accounts=x.get('accounts') or [{}]
        active=next((z for z in accounts if z.get('active')), None)
        ok_accounts=[z for z in accounts if z.get('status')=='ok']
        if active is not None and active.get('status')=='ok':
            a=active
        elif ok_accounts:
            label=(active or {}).get('account_label')
            a=next((z for z in ok_accounts if z.get('account_label')==label), ok_accounts[0])
        else:
            return dict(empty, pct=100.0, unknown=True)
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
floor_applies = (size_raw in ('standard','heavy','strategic') and mkind == 'code' and not test_only) if floor_mode=='bulk_only' else False
def ufmt():
    # FREEPOOL-DEAD-ARM-LOOKS-LIKE-A-BUSY-ARM-01: a DOWN freepool renders as
    # the word `down`, never as the number 100 — one number must not carry
    # two facts. Other gate refusals (gate_broken/pin_drift) keep their
    # numeric pct and are named by the freepool_gate= token on the line.
    util_part=' '.join('util_%s=%s' % (p, 'unknown_capped' if unk[p] else ('down' if (p=='freepool' and _uraw['freepool'].get('status')=='down') else '%d'%u[p])) for p in ('glm','codex','claude','freepool'))
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
    # ARBITER-REMEMBERS-FAILURES-01 edit B (founder 2026-09-05): `unknown` is a
    # THIRD state, never a synonym for "busy". util() already returns pct=100.0
    # WITH unknown=True when a provider's probe did not answer (the status!='ok'
    # line and the claude branch's no-ok-account fall-through), and `unk` has
    # carried that flag ever since -- but it entered the SELECTION nowhere, so a
    # broken measurer rendered identically to an exhausted quota. Measured
    # 2026-09-04/05: util_codex=unknown_capped in 122 of 143 decisions, codex out
    # for a day, and six lanes killed by `reason=all_arms_capped` when what
    # actually failed was the instrument. An unknown arm is therefore NOT capped
    # -- it stays in the candidate set and is instead DEMOTED on effective cost
    # (UNKNOWN_PROBE_PENALTY below), so it ranks strictly after every arm whose
    # headroom we actually measured and is picked only when the alternative is
    # refusing the work outright. Rejected alternatives: "skip it" is today's bug
    # verbatim; "take it as free" would spend a genuinely burnt provider on the
    # strength of a failed reading.
    if unk.get(provider): return False
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
capable=[c for c in cells if mkind in c.get('kinds',[]) and size in c.get('sizes',[]) and (not require_trusted or c.get('protected',False)) and (allowed is None or c.get('arm') in allowed)]
# ARBITER-REMEMBERS-FAILURES-01 edit A (founder 2026-09-05) -- the arbiter must
# remember which arms already failed THIS task.
#
# What was wrong: selection was `reason=cheapest_capable` and nothing else. The
# arbiter kept no record of outcomes, so an arm that had already come up and died
# without writing a line was named again on the next request, at the same cost, by
# construction. Live 2026-09-04/05: GUARDS-SELF-DISABLE-ON-THE-EMPTY-WRITE-SET-01
# went to glm twice with nothing to show and the third resolve said glm again. The
# "glm failed twice -> sonnet" rule existed in prose and in no code path.
#
# What counts as a failure -- the distinction the whole edit turns on. A failure
# is: THE SPAWN HAPPENED AND NO WORK CAME BACK. A refusal BEFORE the spawn is not
# the arm's fault and must never ban it -- writeset_pending/overlap/conflict (the
# registry window), duplicate_task_signature, all_arms_capped, plan_source_absent,
# undiffable_write_set, unscoped_lane_work: each of those is the lane's or the
# gate's shape, and banning a healthy arm for them is how an arm is lost to
# someone else's breakage. Quality rejections (e2e_regression, review_verdict_fail,
# review_dod_fail) are excluded for the opposite reason: work DID come back and was
# judged bad -- a different question from "this arm cannot produce here". The list
# is therefore an ALLOW-list: an unrecognized cause is never counted as a failure.
#
# Where the counter lives: no sixth store. Two journals that already exist carry
# between them exactly what is needed, and neither carries it alone --
#   ~/.claude/leadv2-state/leadv2/dispatch-ledger.jsonl : task_sig + terminal +
#     cause + ts, but NO arm;
#   ~/.claude/cache/leadv2-events/leadv2.jsonl : worker_spawned rows with arm +
#     task + ts (and arm_refused rows, which name the arm directly).
# So a ledger failure at time T for signature S is attributed to the arm of the
# LAST worker_spawned for S at or before T. Measured over the live journals on
# 2026-09-05: 113 ledger failures attribute to an arm, and 12 task signatures show
# one arm failing twice or more (a605eb2a gave codex FOUR turns). 71 older failures
# have no surviving spawn row -- the events file is a rotating cache -- and those
# simply do not count, which is the conservative direction.
#
# Key: `d['task']`, which leadv2-dispatch-code.sh already fills with sig8 (the
# mission-content signature, dispatch-code line ~8038) -- the SAME key the
# duplicate_task_signature guard uses. No new field, no caller change. The three
# fallback descriptors (bench-fallback, exit76, advisory) and the reviewer
# descriptor do not carry it; those journal failure_memory=absent_key and route
# exactly as before rather than pretending the memory answered zero.
#
# An unreadable journal is NOT zero failures. If either journal cannot be read the
# status is `unavailable`: nothing is banned (banning on no evidence is its own
# failure mode) but the decision line SAYS SO, so a lead reading the journal can
# tell "this arm has a clean record here" from "we could not look".
FAILURE_BAN_THRESHOLD_DEFAULT=2
ARM_FAILURE_CAUSES_DEFAULT={
    'no_work:arm_produced_nothing','no_work:empty_diff','dead:crashed_unfinished',
    'dead:timeout','dead:empty_response','dead:worker_died_with_session',
    'dead:no_verdict_marker','dead:review_body_lost'}
_fm_cfg=((data.get('router_v2') or {}).get('failure_memory') or {})
if not isinstance(_fm_cfg, dict): _fm_cfg={}
try: fm_threshold=int(_fm_cfg.get('threshold', FAILURE_BAN_THRESHOLD_DEFAULT))
except (TypeError, ValueError): fm_threshold=FAILURE_BAN_THRESHOLD_DEFAULT
if fm_threshold < 1: fm_threshold=FAILURE_BAN_THRESHOLD_DEFAULT
_cfg_causes=_fm_cfg.get('arm_failure_causes')
arm_failure_causes=({str(x).strip() for x in _cfg_causes if str(x).strip()}
                    if isinstance(_cfg_causes, list) and _cfg_causes
                    else set(ARM_FAILURE_CAUSES_DEFAULT))
task_sig=str(d.get('task') or '').strip()
def read_failure_memory(sig):
    # -> (counts_by_arm, status). status is one of:
    #   absent_key  -- this caller passed no task signature; nothing to look up
    #   unavailable -- a journal could not be read; UNKNOWN, never "zero"
    #   no_history  -- journals read fine, this signature has no failures
    #   ok          -- journals read fine and this signature has failures
    if not sig: return {}, 'absent_key'
    evt=os.environ.get('ROUTE_ARBITER_EVENTS_JOURNAL') or ''
    led=os.environ.get('ROUTE_ARBITER_FAILURE_LEDGER') or ''
    spawns=[]; counts={}; evt_ok=False; led_ok=False
    try:
        with open(evt) as _f:
            for _l in _f:
                try: r=json.loads(_l)
                except Exception: continue
                if str(r.get('task') or '')!=sig: continue
                a=str(r.get('arm') or '')
                if not a: continue
                k=r.get('kind')
                if k=='worker_spawned': spawns.append((str(r.get('ts') or ''), a))
                elif k=='arm_refused': counts[a]=counts.get(a,0)+1
        evt_ok=True
    except Exception:
        evt_ok=False
    spawns.sort()
    try:
        with open(led) as _f:
            for _l in _f:
                try: r=json.loads(_l)
                except Exception: continue
                if str(r.get('task_sig') or '')!=sig: continue
                if ('%s:%s' % (r.get('terminal'), r.get('cause'))) not in arm_failure_causes: continue
                ts=str(r.get('ts') or ''); arm=None
                for _sts,_a in spawns:
                    if _sts<=ts: arm=_a
                if arm: counts[arm]=counts.get(arm,0)+1
        led_ok=True
    except Exception:
        led_ok=False
    if not (evt_ok and led_ok): return {}, 'unavailable'
    return counts, ('ok' if counts else 'no_history')
failure_counts, failure_memory = read_failure_memory(task_sig)
failure_banned={a:n for a,n in failure_counts.items() if n>=fm_threshold}
failure_dropped=[]
if failure_banned:
    _kept=[c for c in capable if c.get('arm') not in failure_banned]
    if _kept:
        failure_dropped=sorted({c.get('arm') for c in capable if c.get('arm') in failure_banned})
        capable=_kept
    else:
        # Every capable cell is a repeat offender. Refusing here would turn a
        # memory into a deadlock, so the ban yields -- and says that it yielded.
        failure_memory='exhausted'
_fm_tok=' failure_memory=%s' % failure_memory
if failure_dropped:
    _fm_tok += ' failure_banned=%s' % ','.join('%s:%d' % (a, failure_banned[a]) for a in failure_dropped)
elif failure_memory=='exhausted':
    _fm_tok += ' failure_banned=none_left:%s' % ','.join('%s:%d' % (a,n) for a,n in sorted(failure_banned.items()))
# Edit B's outage token: a broken INSTRUMENT is named separately from a burnt
# quota, so `all_arms_capped` can never again absorb a probe failure silently.
_probe_outage=[p for p in ('glm','codex','claude','freepool') if unk.get(p)]
_outage=(' probe_outage=%s' % ','.join(_probe_outage)) if _probe_outage else ''
# ROUTING-EVERY-SPAWN-THROUGH-THE-ARBITER-01: the decision journal is the
# enforcement-side record. The spawn gate (PreToolUse Agent) distinguishes
# "consulted, decision=X" from "no decision" by the PRESENCE of a fresh,
# arm!=refuse record for the spawn's subtype -- the predicate is the absence
# of a record, never a name list of subtypes/models/providers.
import time
def _record(arm, model, tier, reason):
    try:
        _jf_path=os.environ.get('LEADV2_ROUTE_ARBITER_DECISIONS_FILE') or os.path.join(os.environ.get('TMPDIR','/tmp'),'leadv2-route-arbiter-decisions.jsonl')
        os.makedirs(os.path.dirname(_jf_path) or '.',exist_ok=True)
        if os.path.exists(_jf_path) and os.path.getsize(_jf_path)>262144:
            try:
                with open(_jf_path) as _old: _lines=_old.readlines()
                with open(_jf_path,'w') as _new: _new.writelines(_lines[len(_lines)//2:])
            except Exception:
                pass
        _rec={'ts':time.strftime('%Y-%m-%dT%H:%M:%SZ',time.gmtime()),'ts_epoch':int(time.time()),
              'role':role,'work_kind':kind,'subtype':str(d.get('subtype','')),
              'model_requested':str(d.get('model_requested','')),'arm':arm,'model':model,
              'tier':tier,'reason':reason,'task':str(d.get('task',''))[:200],
              'failure_memory':failure_memory,
              'failure_banned':{a:failure_banned[a] for a in failure_dropped},
              'probe_outage':list(_probe_outage)}
        with open(_jf_path,'a') as _jf: _jf.write(json.dumps(_rec)+'\n')
    except Exception:
        pass
if not capable:
    _record('refuse','none','none','no_capable_cell')
    print('arm=refuse model=none tier=none reason=no_capable_cell kind=%s chain= %s%s%s' % (kind,ufmt(),_outage,_fm_tok))
    raise SystemExit(68)
ok=[c for c in capable if not capped(c.get('provider'))]
if not ok:
    _record('refuse','none','none','all_arms_capped')
    print('arm=refuse model=none tier=none reason=all_arms_capped kind=%s chain= %s%s%s' % (kind,ufmt(),_outage,_fm_tok))
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
# ARBITER-REMEMBERS-FAILURES-01 edit B: the demotion for an unmeasured arm rides
# on effective cost -- the sort's dominant key -- exactly like the freepool floor
# above, because that is the only dimension the selector actually ranks by. 50
# clears the whole real cost range (max real cost: opus 9), so ANY arm with a live
# reading outranks ANY arm whose probe failed; and it stays below the freepool
# capability floor (+100), so an unmeasured arm loses to nothing except a
# deliberately floored one.
UNKNOWN_PROBE_PENALTY=50.0
def ecost(c):
    return float(c.get('cost',999)) + (100.0 if (floor_applies and c.get('arm')=='freepool') else 0.0) + (UNKNOWN_PROBE_PENALTY if unk.get(c.get('provider')) else 0.0) + complexity_penalty(c)
complexity_penalty_active = any(complexity_penalty(c) > 0 for c in ok)
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
# (config/leadv2-routing.yaml router_v2.effort_matrix), never a name literal.
#
# SMART-ARBITER-01 / EFFORT-FOLLOWS-THE-ARM-NOT-THE-TASK-01 (founder
# 2026-09-04): the old lookup let the WINNING ARM's tags decide effort --
# glm-flash won a standard build on cost and its `cheap`/`mechanical` tags
# then forced effort=low (43 live build decisions at effort=low,
# 2026-09-03/04; the founder named exactly this outcome). Circular: B was
# derived from A's outcome instead of the task's own properties. Rows are
# now TWO PHASES: a row keyed ONLY on task-descriptor properties
# (kinds/sizes/complexity/duration_class/protected/default -- `protected`
# stays the TASK flag, exactly as before) is evaluated FIRST; rows that key
# on the arm too (`tags`) are a FALLBACK consulted only when no task row
# matched. Config order is preserved within each phase, and a task-keyed row
# ANYWHERE in the matrix outranks any arm-keyed row -- so a yaml edit alone
# (no script change) still retunes every outcome, the anti-hardcoding
# property test-effort-routing.sh case (6) grades.
TASK_EFFORT_KEYS={'kinds','sizes','complexity','duration_class','protected','default'}
def _effort_row_is_task_keyed(row):
    return set(row.keys()) <= (TASK_EFFORT_KEYS | {'effort'})
def _effort_row_matches(row):
    if row.get('default'): return True
    if 'tags' in row:
        if not (set(row.get('tags') or []) & set(w.get('tags') or [])): return False
    if 'kinds' in row and mkind not in (row.get('kinds') or []): return False
    if 'sizes' in row and size not in (row.get('sizes') or []): return False
    if 'complexity' in row and complexity not in (row.get('complexity') or []): return False
    if 'duration_class' in row and duration_class not in (row.get('duration_class') or []): return False
    if 'protected' in row and bool(row['protected']) != protected: return False
    return True
_effort_rows=((data.get('router_v2') or {}).get('effort_matrix') or [])
_task_rows=[r for r in _effort_rows if _effort_row_is_task_keyed(r)]
_arm_rows=[r for r in _effort_rows if not _effort_row_is_task_keyed(r)]
effort='medium'
for _row in (_task_rows+_arm_rows):
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
# FREEPOOL-DEAD-ARM-LOOKS-LIKE-A-BUSY-ARM-01: name ANY gate refusal on the
# decision line itself -- this line is what the dispatcher journals verbatim
# (route_resolved ... util_glm=... tail), so the freepool verdict travels
# with every decision, not only the ones a human re-derives by hand.
_gate = (' freepool_gate=%s' % free_reason) if (free_reason and not free_ok) else ''
# A complexity rule only changes the selector through effective cost.  Say so
# when it is active: `cheapest_capable` alone would hide that cheaper tagged
# cells were deliberately demoted for this estimate.
reason = 'complexity_penalty' if complexity_penalty_active else 'cheapest_capable'
_complexity_policy = (' complexity_policy=penalty' if complexity_penalty_active else ' complexity_policy=none')
_record(w['arm'],w['model'],w.get('tier','standard'),reason)
# ROUTING-EVERY-SPAWN-THROUGH-THE-ARBITER-01: the decision line names the kind
# it routed for -- a decision that cannot be read back is not a decision.
# UNION 2026-09-04 (RECOVER-TWELVE-CONFLICTED-BRANCHES-01), third union of this
# print line: HEAD contributed kind=/_quota/_wait/_gate/_record, the branch
# contributed the variable reason (complexity_penalty) and complexity_policy=.
print('arm=%s kind=%s model=%s tier=%s effort=%s reason=%s chain=%s %s%s%s%s%s%s%s%s%s%s%s' % (w['arm'],kind,w['model'],w.get('tier','standard'),effort,reason,','.join(rotated),ufmt(),_extra,_floor,_fmode,_complexity,_complexity_policy,_quota,_wait,_gate,_outage,_fm_tok))
PY
}

# ROUTING-EVERY-SPAWN-THROUGH-THE-ARBITER-01: CLI consult entry. The lib stays
# source-only for its existing callers (dispatch-code, product-close); invoked
# directly it consults the arbiter and prints the decision line, which the
# spawn gate's way-forward text hands to the lead:
#   bash .../lib/leadv2-route-arbiter.sh worker '{"work_kind":"recon","size":"standard","subtype":"Explore","task":"map auth flow"}'
if [[ "${BASH_SOURCE[0]}" == "${0}" && ( "${1:-}" == worker || "${1:-}" == reviewer ) ]]; then
  route_arbiter "$1" "${2:-{\}}"; exit $?
fi
