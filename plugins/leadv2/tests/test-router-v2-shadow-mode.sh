#!/usr/bin/env bash
# ARBITER-SCORING-DESIGN-01 step 3. Proves LEADV2_ARBITER_CAPABILITY_FIT=shadow (design.md
# §8 row 3): the fit_pick=/fit_differs=/fit_bucket= tokens react exactly as they do under
# 'on', but the ACTUAL arm= pick never moves off the pure-cost order -- shadow is allowed to
# talk, never to choose. Step 1 (b64ce433) already computes _fit_order/_cost_order/fit_pick/
# fit_differs unconditionally in every FIT_MODE (leadv2-route-arbiter.sh ~:770-780, ~:890-909);
# this suite is proof, not new plumbing -- see docs/handoff/F1-ARBITER-SCORING-20260907/
# seam-diagnosis.md for why no dispatcher change was needed to reach this mode.
# run-all-triggers: leadv2-route-arbiter leadv2-routing.yaml leadv2-dispatch-code
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
ARBITER="${ROOT}/scripts/lib/leadv2-route-arbiter.sh"
ROUTING="${ROOT}/config/leadv2-routing.yaml"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
PASS=0; FAIL=0; SKIP=0
LAST_ASSERT="(none yet -- died before the first assertion)"
SUMMARY_PRINTED=0
_suite_abort_report() {
  local rc=$?
  [[ ${SUMMARY_PRINTED} -eq 1 ]] && return 0
  printf 'ABORT: suite exited rc=%s WITHOUT a summary after %s assertion(s); last completed: %s\n' \
    "${rc}" "$((PASS+FAIL))" "${LAST_ASSERT}" >&2
}
trap _suite_abort_report EXIT
pass(){ LAST_ASSERT="$1"; printf 'PASS: %s\n' "$1"; PASS=$((PASS+1)); }
fail(){ LAST_ASSERT="$1"; printf 'FAIL: %s\n' "$1"; FAIL=$((FAIL+1)); }
skip(){ LAST_ASSERT="$1"; printf 'SKIP: %s\n' "$1"; SKIP=$((SKIP+1)); }

cat >"$TMP/live.sh" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$ROUTE_TEST_QUOTA"
EOF
cat >"$TMP/free.sh" <<'EOF'
#!/usr/bin/env bash
exit "${ROUTE_TEST_FREE_RC:-0}"
EOF
chmod +x "$TMP/live.sh" "$TMP/free.sh"

quota(){ python3 - "$1" "$2" "$3" <<'PY'
import json,sys
g,c,a=map(int,sys.argv[1:])
print(json.dumps({'glm':{'status':'ok','five_hour':{'pct':g},'weekly':{'pct':g}},'codex':{'status':'ok','binding_window':'primary','windows':[{'kind':'primary','used_percent':c}]},'anthropic':{'status':'ok','accounts':[{'active':True,'status':'ok','five_hour_pct':a,'seven_day_pct':a}]}}))
PY
}
HEALTHY="$(quota 10 20 20)"

# run <routing-yaml> <descriptor-json> <FIT_MODE>
run(){
  local routing="$1" descriptor="$2" mode="$3"
  rm -f "$TMP/state"
  LEADV2_ARBITER_CAPABILITY_FIT="$mode" \
  LEADV2_ROUTE_ARBITER_ROUTING_YAML="$routing" LEADV2_ROUTE_ARBITER_QUOTA_LIVE="$TMP/live.sh" \
  LEADV2_ROUTE_ARBITER_FREEPOOL_GATE="$TMP/free.sh" LEADV2_ROUTE_ARBITER_STATE_FILE="$TMP/state" \
  ROUTE_TEST_QUOTA="$HEALTHY" ROUTE_TEST_FREE_RC=0 \
  bash -c 'source "$0"; route_arbiter worker "$1"' "$ARBITER" "$descriptor"
}
tok(){ printf '%s\n' "$1" | grep -oE "(^| )$2=[^ ]+" | head -1 | sed 's/.*=//'; }

# ── §9.2 rows under FIT_MODE=shadow: same fit_pick/fit_differs as 'on' would report,
# but the ACTUAL arm= must equal what 'off' produces on the identical descriptor --
# shadow's whole point is "print the fit comparison, never act on it".
declare -a ROWS=(
  'r1|{"kind":"code","size":"standard","complexity":"simple","complexity_source":"heuristic","task":"r1"}|glm|1|glm-flash'
  'r2|{"kind":"code","size":"standard","complexity":"standard","complexity_source":"judge","task":"r2"}|glm|1|glm-flash'
  'r3|{"kind":"code","size":"standard","complexity":"trivial","complexity_source":"unknown","task":"r3"}|glm|1|glm-flash'
  'r6|{"kind":"code","size":"heavy","complexity":"complex","complexity_source":"heuristic","task":"r6"}|glm|0|glm'
  'r7|{"kind":"code","size":"standard","complexity":"simple","complexity_source":"heuristic","allowed_arms":["sonnet"],"task":"r7"}|sonnet|0|sonnet'
  'r8|{"kind":"code","task_class":"Heavy","complexity":"complex","complexity_source":"flag","task":"r8"}|glm|0|glm'
  'r9|{"kind":"code","size":"standard","complexity":"trivial","complexity_source":"judge","task":"r9"}|glm-flash|0|glm-flash'
)
for row in "${ROWS[@]}"; do
  IFS='|' read -r label desc exp_fit_pick exp_fit_differs exp_actual_arm <<<"$row"
  out_shadow="$(run "$ROUTING" "$desc" shadow)"
  out_off="$(run "$ROUTING" "$desc" off)"
  actual_arm="$(printf '%s\n' "$out_shadow" | sed -n 's/^arm=\([^ ]*\).*/\1/p')"
  off_arm="$(printf '%s\n' "$out_off" | sed -n 's/^arm=\([^ ]*\).*/\1/p')"
  if [[ "$(tok "$out_shadow" fit_mode)" == "shadow" && "$(tok "$out_shadow" fit_pick)" == "$exp_fit_pick" \
     && "$(tok "$out_shadow" fit_differs)" == "$exp_fit_differs" && "$actual_arm" == "$exp_actual_arm" \
     && "$actual_arm" == "$off_arm" ]]; then
    pass "9.2 $label (shadow): fit_pick=$exp_fit_pick fit_differs=$exp_fit_differs, actual arm=$actual_arm unchanged vs off"
  else
    fail "9.2 $label out_shadow=$out_shadow out_off=$out_off"
  fi
done

# ── negative control: mutating glm-flash's capability tier must flip the shadow-mode
# fit_bucket token (proves shadow reads live config, not a frozen default) while the
# ACTUAL pick stays glm-flash either way (proves shadow never sorts on it) ──────────
python3 - "$ROUTING" "$TMP/mutated-cap.yaml" <<'PY'
import sys, yaml
src, dst = sys.argv[1], sys.argv[2]
data = yaml.safe_load(open(src))
cells = data['router_v2']['capability_matrix']
flash = [c for c in cells if c.get('arm') == 'glm-flash']
if len(flash) != 1 or flash[0].get('capability') != 2:
    sys.exit('FIXTURE PRECONDITION GONE: glm-flash capability is not 2 in leadv2-routing.yaml -- re-anchor this control, do not silence it')
flash[0]['capability'] = 4
yaml.safe_dump(data, open(dst, 'w'))
PY
base="$(run "$ROUTING" '{"kind":"code","size":"standard","complexity":"standard","complexity_source":"judge","task":"nc-a-base"}' shadow)"
mut="$(run "$TMP/mutated-cap.yaml" '{"kind":"code","size":"standard","complexity":"standard","complexity_source":"judge","task":"nc-a-mut"}' shadow)"
base_arm="$(printf '%s\n' "$base" | sed -n 's/^arm=\([^ ]*\).*/\1/p')"
mut_arm="$(printf '%s\n' "$mut" | sed -n 's/^arm=\([^ ]*\).*/\1/p')"
if [[ "$base" == *'fit_bucket='*'glm-flash:1'* && "$mut" == *'fit_bucket='*'glm-flash:0'* \
   && "$base_arm" == "glm-flash" && "$mut_arm" == "glm-flash" ]]; then
  pass 'NC(shadow-a): mutating glm-flash capability 2->4 flips shadow fit_bucket :1->:0, actual pick stays glm-flash both times'
else
  fail "NC(shadow-a) base=$base mut=$mut"
fi

# ── negative control: a mutation that made shadow ACT on fit (accidentally sorting
# on _fit_key even when FIT_MODE!='on') must be caught -- flip the sort's ternary and
# confirm this suite goes red, proving the assertions above actually exercise the sort.
MUT_B="$TMP/arbiter-nc-shadow-acts.sh"; cp "$ARBITER" "$MUT_B"
python3 - "$MUT_B" <<'PY'
import sys
p = sys.argv[1]; s = open(p).read()
anchor = "ok.sort(key=_fit_key if FIT_MODE == 'on' else _cost_key)"
n = s.count(anchor)
if n != 1:
    sys.exit('mutation anchor found %d times (expected 1) -- sort ternary moved or was reworded; re-anchor this control, do not silence it' % n)
open(p, 'w').write(s.replace(anchor, "ok.sort(key=_fit_key if FIT_MODE != 'off' else _cost_key)"))
PY
ARBITER_SAVE="$ARBITER"; ARBITER="$MUT_B"
mut_out="$(run "$ROUTING" '{"kind":"code","size":"standard","complexity":"standard","complexity_source":"judge","task":"nc-shadow-acts"}' shadow)"
ARBITER="$ARBITER_SAVE"
mut_arm="$(printf '%s\n' "$mut_out" | sed -n 's/^arm=\([^ ]*\).*/\1/p')"
if [[ "$mut_arm" == "glm" ]]; then
  pass 'NC(shadow-b): mutating the sort ternary to act on shadow flips the actual pick glm-flash->glm -- this suite would have caught it'
else
  fail "NC(shadow-b) expected mutant to flip the pick to glm, got mut_out=$mut_out"
fi

# ── live acceptance (design.md §8 step 3 / §9.2): reconstruct real descriptors from
# live lane journals (path-excluded for ephemeral|deadbeef per corpus-split.md case 6,
# same discipline as design.md §9.1), replay each once under 'off' and once under
# 'shadow', and assert (a) the two ACTUAL picks are byte-identical on every row --
# shadow must never move the live decision -- and (b) >=29 usable rows exist. A thin
# corpus is a SKIP (external environment state), never a silvered PASS.
STATE_ROOT="${LEADV2_STATE_ROOT:-$HOME/.claude/leadv2-state}"
if [[ -d "$STATE_ROOT" ]]; then
  DESC_FILE="$TMP/live-descriptors.jsonl"
  python3 - "$STATE_ROOT" > "$DESC_FILE" <<'PY'
import re, os, sys, json
state_root = sys.argv[1]
live_files = []
for root, dirs, files in os.walk(state_root):
    if 'ephemeral' in root or 'deadbeef' in root:
        continue
    for f in files:
        if f == 'journal.md' and (os.sep + 'tasks' + os.sep) in os.path.join(root, f):
            live_files.append(os.path.join(root, f))
rows = []
for fpath in live_files:
    try:
        text = open(fpath, errors='replace').read()
    except OSError:
        continue
    lines = text.splitlines()
    kind_by_task, class_by_task = {}, {}
    for ln in lines:
        m = re.search(r'\btask=([a-f0-9-]+)\b', ln)
        if not m:
            continue
        tid = m.group(1)
        km = re.search(r'\bkind=([a-z_-]+)\b', ln)
        if km and tid not in kind_by_task:
            kind_by_task[tid] = km.group(1)
        cm = re.search(r'\btask_class=([A-Za-z]+)\b', ln)
        if cm and tid not in class_by_task:
            class_by_task[tid] = cm.group(1).lower()
    for ln in lines:
        if 'route_resolved by=arbiter' not in ln or 'arm=refuse' in ln:
            continue
        m = re.search(r'\btask=([a-f0-9-]+)\b', ln)
        if not m:
            continue
        tid = m.group(1)
        cxm = re.search(r'\bcomplexity=([a-z]+)\b', ln)
        if not cxm:
            continue
        durm = re.search(r'\bduration_class=([a-z]+)\b', ln)
        srcm = re.search(r'\bcomplexity_source=([a-z]+)\b', ln)
        rows.append({
            'task': tid,
            'kind': kind_by_task.get(tid, 'code'),
            'size': class_by_task.get(tid, 'standard'),
            'complexity': cxm.group(1),
            'complexity_source': srcm.group(1) if srcm else 'unknown',
            'duration_class': durm.group(1) if durm else 'unknown',
        })
for r in rows:
    print(json.dumps(r))
PY
  N_LIVE="$(wc -l < "$DESC_FILE" | tr -d ' ')"
  if [[ "${N_LIVE:-0}" -lt 29 ]]; then
    skip "live acceptance: only ${N_LIVE:-0} usable live route_resolved descriptors under $STATE_ROOT (need >=29) -- external corpus is thin in this environment, not a suite defect"
  else
    MISMATCH=0
    DIFFER=0
    MATCH=0
    while IFS= read -r row; do
      desc="$(python3 -c "import json,sys; r=json.loads(sys.argv[1]); print(json.dumps({'kind':r['kind'],'size':r['size'],'complexity':r['complexity'],'complexity_source':r['complexity_source'],'duration_class':r['duration_class'],'task':r['task']}))" "$row")"
      out_shadow="$(run "$ROUTING" "$desc" shadow)"
      out_off="$(run "$ROUTING" "$desc" off)"
      arm_shadow="$(printf '%s\n' "$out_shadow" | sed -n 's/^arm=\([^ ]*\).*/\1/p')"
      arm_off="$(printf '%s\n' "$out_off" | sed -n 's/^arm=\([^ ]*\).*/\1/p')"
      [[ "$arm_shadow" == "$arm_off" ]] || MISMATCH=$((MISMATCH+1))
      if [[ "$(tok "$out_shadow" fit_differs)" == "1" ]]; then DIFFER=$((DIFFER+1)); else MATCH=$((MATCH+1)); fi
    done < "$DESC_FILE"
    printf 'LIVE_REPLAY: rows=%s differ=%s match=%s pick_mismatch(shadow_vs_off)=%s\n' "$N_LIVE" "$DIFFER" "$MATCH" "$MISMATCH"
    if [[ "$MISMATCH" -eq 0 ]]; then
      pass "live acceptance: ${N_LIVE} real reconstructed descriptors replayed, shadow's actual pick == off's actual pick on every row (0 mismatch), differ=${DIFFER} match=${MATCH}"
    else
      fail "live acceptance: shadow changed the actual pick vs off on ${MISMATCH}/${N_LIVE} real descriptors -- shadow must be inert"
    fi
  fi
else
  skip "live acceptance: $STATE_ROOT not present in this environment"
fi

SUMMARY_PRINTED=1
printf 'SUMMARY: pass=%s fail=%s skip=%s\n' "$PASS" "$FAIL" "$SKIP"
(( FAIL == 0 ))
