#!/usr/bin/env bash
# FP-08 fix-round 1 (2026-08-28) — capability-floor suite for the freepool arm.
#
# Contract: for raw --task-class standard|heavy|strategic (`code` kind) the
# route arbiter DEMOTES freepool in the dimension selection actually ranks by
# — EFFECTIVE COST, the sort's dominant key — so freepool is never the pick
# for Standard+ build work, while trivial/light ("simple") and bulk classes
# and every non-build kind stay freepool-eligible. The applied demotion is
# journaled as `floor_applied=1 floor_reason=<raw-class>/<kind>` tokens on the
# arbiter's own output line for THAT invocation, which leadv2-dispatch-code.sh
# turns into the `arm_floor_applied arm=freepool` decision line.
#
# Test (a) — wait half (review-CONFIRMED, pinned here so it cannot regress):
# a stub freepool worker that finishes at t+2x-window with a REAL diff must
# not be declared no_work by the post-spawn verdict waiter — the waiter exits
# its window with state=running (rc0, proceed) and the run later completes.
#
# NEGATIVE CONTROL (mission test d, declared in header, RUN RED):
# the last case mutates a throwaway copy of the arbiter so the floor can
# never apply, re-runs the EXACT (b) invocation, and proves (b)'s assertion
# goes RED — freepool then WINS the standard build. If the mutation does not
# flip the winner, every assertion above is tautological and this suite is
# lying.
#
# Hermetic: no network, no live proxy, no real dispatch. The arbiter's own
# test seams (LEADV2_ROUTE_ARBITER_QUOTA_LIVE / _FREEPOOL_GATE / _STATE_FILE)
# plus dispatch's launcher seams (LEADV2_DISPATCH_*_BIN) carry every external
# input. The only real OS process spawned is the stub worker's sleeper.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
ARBITER="${SCRIPTS_ROOT}/lib/leadv2-route-arbiter.sh"
DISPATCH_BIN="${SCRIPTS_ROOT}/leadv2-dispatch-code.sh"
ROUTING="${SCRIPTS_ROOT}/../config/leadv2-routing.yaml"

PASS=0; FAIL=0
pass() { printf 'PASS: %s\n' "$1"; PASS=$((PASS + 1)); }
fail() { printf 'FAIL: %s -- %s\n' "$1" "${2:-}"; FAIL=$((FAIL + 1)); }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/fp08-floor.XXXXXX")"
trap '[[ "${FP08_KEEP_LOGS:-0}" == "1" ]] || rm -rf "$TMP"' EXIT

bash -n "$ARBITER" || { fail "bash syntax: arbiter"; exit 1; }
bash -n "$DISPATCH_BIN" || { fail "bash syntax: dispatch"; exit 1; }
pass "bash syntax: arbiter + dispatch"

# Fixture quota source: glm at $1%, codex at $2, claude at $3.
cat > "$TMP/live.sh" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$ROUTE_TEST_QUOTA"
EOF
# Fixture freepool gate: healthy unless the case says otherwise.
cat > "$TMP/free.sh" <<'EOF'
#!/usr/bin/env bash
exit "${ROUTE_TEST_FREE_RC:-0}"
EOF
chmod +x "$TMP/live.sh" "$TMP/free.sh"

quota_json() { # <glm_pct> <codex_pct> <claude_pct>
  python3 - "$1" "$2" "$3" <<'PY'
import json, sys
g, c, a = (int(x) for x in sys.argv[1:])
print(json.dumps({
    'glm': {'status': 'ok', 'five_hour': {'pct': g}, 'weekly': {'pct': g}},
    'codex': {'status': 'ok', 'binding_window': 'primary',
              'windows': [{'kind': 'primary', 'used_percent': c}]},
    'anthropic': {'status': 'ok', 'accounts': [
        {'active': True, 'five_hour_pct': a, 'seven_day_pct': a}]},
}))
PY
}

run_arbiter() { # <quota_json> <descriptor_json> [arbiter_bin]
  local q="$1" desc="$2" arb="${3:-$ARBITER}"
  LEADV2_ROUTE_ARBITER_ROUTING_YAML="$ROUTING" \
  LEADV2_ROUTE_ARBITER_QUOTA_LIVE="$TMP/live.sh" \
  LEADV2_ROUTE_ARBITER_FREEPOOL_GATE="$TMP/free.sh" \
  LEADV2_ROUTE_ARBITER_STATE_FILE="$TMP/state" \
  ROUTE_TEST_QUOTA="$q" \
  bash -c 'source "$0"; route_arbiter worker "$1"' "$arb" "$desc"
}

# glm capped (99%) so glm/glm-flash leave the picture; codex+claude healthy.
# Without the floor this is exactly the live FP-08 shape: freepool (cost 1)
# sorts ahead of codex (3) and sonnet (5) and wins as cheapest_capable.
STD_BUILD_QUOTA="$(quota_json 99 20 20)"

# ── (b) Standard build: freepool NEVER effectively selected ──────────────────
out="$(run_arbiter "$STD_BUILD_QUOTA" '{"kind":"code","size":"standard","task":"deadbeef"}')"
if [[ "$out" == *'arm=freepool '* ]]; then
  fail "(b) standard build: freepool selected despite capability floor ($out)"
else
  pass "(b) standard build: freepool not selected (SELECTION outcome asserted, not just the journal line)"
fi
if [[ "$out" == *'floor_applied=1 floor_reason=standard/code'* ]]; then
  pass "(b) standard build: floor journaled as floor_applied=1 floor_reason=standard/code"
else
  fail "(b) standard build: floor line missing ($out)"
fi
chain="$(printf '%s\n' "$out" | sed -n 's/.*chain=\([^ ]*\).*/\1/p')"
if [[ "${chain##*,}" == "freepool" ]]; then
  pass "(b) standard build: freepool demoted to LAST chain position ($chain)"
else
  fail "(b) standard build: freepool not last in chain ($chain)"
fi
codex_pos="$(printf '%s' "$chain" | awk -F, '{for(i=1;i<=NF;i++) if($i=="codex"){print i; exit}}')"
sonnet_pos="$(printf '%s' "$chain" | awk -F, '{for(i=1;i<=NF;i++) if($i=="sonnet"){print i; exit}}')"
freepool_pos="$(printf '%s' "$chain" | awk -F, '{for(i=1;i<=NF;i++) if($i=="freepool"){print i; exit}}')"
if [[ -n "$codex_pos" && -n "$sonnet_pos" && -n "$freepool_pos" && "$codex_pos" -lt "$freepool_pos" && "$sonnet_pos" -lt "$freepool_pos" ]]; then
  pass "(b) standard build: codex and sonnet both rank ahead of freepool"
else
  fail "(b) standard build: codex/sonnet do not both rank ahead ($chain)"
fi
# ...and the state file carries the task stamp + floor bookkeeping atomically.
if python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); sys.exit(0 if d.get("task")=="deadbeef" and d.get("floor_applied") is True and d.get("floor_reason")=="standard/code" and isinstance(d.get("arm"),str) else 1)' "$TMP/state" 2>/dev/null; then
  pass "(b) state file: JSON with arm + task=deadbeef stamp + floor bookkeeping"
else
  fail "(b) state file: missing task stamp or floor fields ($(cat "$TMP/state" 2>/dev/null))"
fi

# (b2) heavy + strategic build: same floor (freepool not even capable there —
# assert the outcome, never freepool).
for cls in heavy strategic; do
  out="$(run_arbiter "$STD_BUILD_QUOTA" "{\"kind\":\"code\",\"size\":\"${cls}\"}")"
  if [[ "$out" == *'arm=freepool '* ]]; then
    fail "(b2) ${cls} build: freepool selected despite floor"
  else
    pass "(b2) ${cls} build: freepool not selected"
  fi
done

# ── (c) bulk / simple / non-build: freepool still selectable ─────────────────
out="$(run_arbiter "$STD_BUILD_QUOTA" '{"kind":"code","size":"bulk"}')"
if [[ "$out" == *'arm=freepool '* ]]; then
  pass "(c) bulk build: freepool still selectable"
else
  fail "(c) bulk build: freepool unexpectedly demoted ($out)"
fi
if [[ "$out" == *'floor_applied=1'* ]]; then
  fail "(c) bulk build: floor must NOT apply to bulk"
else
  pass "(c) bulk build: no floor token for bulk"
fi
# (c2) trivial/light ("simple") build: the floor must key on the RAW class —
# the SIZE_MAP folds them into the standard cell for capability, but they stay
# freepool-eligible. All providers capped so freepool is the only arm left.
ALL_CAPPED="$(quota_json 99 99 99)"
for cls in trivial light; do
  out="$(run_arbiter "$ALL_CAPPED" "{\"kind\":\"code\",\"size\":\"${cls}\"}")"
  if [[ "$out" == *'arm=freepool '* ]]; then
    pass "(c2) ${cls} build: freepool still selectable (floor keys on raw class)"
  else
    fail "(c2) ${cls} build: freepool demoted for a simple task ($out)"
  fi
done
# (c3) non-build kind (docs) at standard size: not build work, no floor.
out="$(run_arbiter "$STD_BUILD_QUOTA" '{"kind":"docs","size":"standard"}')"
if [[ "$out" == *'arm=freepool '* ]]; then
  pass "(c3) standard docs: freepool still selectable (floor is build-only)"
else
  fail "(c3) standard docs: freepool unexpectedly demoted ($out)"
fi

# ── (dispatch) the dispatcher turns the arbiter's floor tokens into the ──────
# `arm_floor_applied arm=freepool` decision line, and route_resolved does NOT
# pick freepool. Full cmd_resolve, real arbiter lib, --no-spawn. The class
# the descriptor carries is the ADMISSION class (task_class="${ADMISSION_CLASS}",
# capitalized), so the judge stub is forced to fail: admission's conservative
# failure class IS Standard (source=classifier_error) — hermetic, no model.
REPO="$TMP/repo"
mkdir -p "$REPO/.claude/ref" "$REPO/docs/leadv2" "$REPO/docs/leadv2/tasks"
git -C "$REPO" init -q -b main
git -C "$REPO" config user.email t@e.com; git -C "$REPO" config user.name t
: > "$REPO/seed"; git -C "$REPO" add seed; git -C "$REPO" commit -qm seed
cp "$ROUTING" "$REPO/.claude/ref/leadv2-routing.yaml"
WORKER="$TMP/worker.sh"
printf '#!/usr/bin/env bash\nprintf "PID=%%s LABEL=t SESSION_ID=t\\n" "$$"\n' > "$WORKER"
chmod +x "$WORKER"
# Run with CWD inside the fake repo: the foreign-project-root guard
# (FOREIGN-PROJECT-ROOT-GUARD-01) overrides a mismatched CLAUDE_PROJECT_ROOT
# with the CWD-derived root, which would leak admission receipts and the lane
# cap into the REAL tree and make the suite non-hermetic and flaky.
arb_out="$(cd "$REPO" && LEADV2_STATE_ROOT="$TMP/state-root" \
  LEADV2_ROUTE_ARBITER_QUOTA_LIVE="$TMP/live.sh" \
  LEADV2_ROUTE_ARBITER_FREEPOOL_GATE="$TMP/free.sh" \
  LEADV2_ROUTE_ARBITER_STATE_FILE="$TMP/state-dispatch" \
  ROUTE_TEST_QUOTA="$STD_BUILD_QUOTA" \
  CLAUDE_PROJECT_ROOT="$REPO" LEADV2_PROJECT_ROOT="$REPO" \
  LEADV2_DISPATCH_CACHE_DIR="$TMP/cache" \
  LEADV2_DISPATCH_E2E_GATE=0 LEADV2_DISPATCH_REVIEW_GATE=0 LEADV2_DISPATCH_ARCHITECT_GATE=0 \
  LEADV2_REQUIRE_PHASES=0 \
  LEADV2_ROUTER_V2=0 LEADV2_EXCLUDED_ARMS=__none__ LEADV2_LANE_SHAPE=off \
  LEADV2_BURN_GOVERNOR=0 LEADV2_ARM_EARLY_VERDICT_S=0 \
  LEADV2_TASK_JUDGE_BIN=/bin/false \
  LEADV2_DISPATCH_SUBSESSION_BIN="$WORKER" \
  bash "$DISPATCH_BIN" "FP-08 floor journal probe ${TMP}" \
    --kind code --task-class standard --no-spawn --writes src/x.py 2>&1 || true)"
printf '%s\n' "$arb_out" > "$TMP/dispatch-out.log"
if printf '%s\n' "$arb_out" | grep -q 'arm_floor_applied arm=freepool task=[0-9a-f]\{8\} reason=standard/code'; then
  pass "(dispatch) arm_floor_applied journal line emitted from the arbiter's own output"
else
  fail "(dispatch) arm_floor_applied journal line missing (log: $TMP/dispatch-out.log)"
fi
if printf '%s\n' "$arb_out" | grep -q 'route_resolved by=arbiter role=worker arm=freepool'; then
  fail "(dispatch) route_resolved picked freepool for a standard build (selection outcome)"
else
  pass "(dispatch) route_resolved did not pick freepool (selection outcome)"
fi

# ── (a) stub freepool worker finishing at t+2x-window with a real diff: ──────
# the post-spawn verdict waiter must NOT declare no_work early — it exits its
# (short) window with the run still `running` and never spills; the run then
# completes and leaves the diff on disk.
REPO2="$TMP/repo2"
mkdir -p "$REPO2/.claude/ref" "$REPO2/docs/leadv2" "$REPO2/docs/leadv2/tasks"
git -C "$REPO2" init -q -b main
git -C "$REPO2" config user.email t@e.com; git -C "$REPO2" config user.name t
: > "$REPO2/seed"; git -C "$REPO2" add seed; git -C "$REPO2" commit -qm seed
cp "$ROUTING" "$REPO2/.claude/ref/leadv2-routing.yaml"
FP_RUNS="$TMP/freepool-runs"; mkdir -p "$FP_RUNS"
cat > "$TMP/freepool-stub.sh" <<STUB
#!/usr/bin/env bash
# FP-08 (a): fake freepool-coder.sh. bg: create run dir, report running, then
# finalize COMPLETE at t+\${FP_STUB_FINISH_S} with a real diff on disk.
RUNS="\${FP_STUB_RUNS:-$FP_RUNS}"
FINISH="\${FP_STUB_FINISH_S:-8}"
case "\${1:-}" in
  bg)
    shift
    id="run-$\$-$RANDOM"
    mkdir -p "\$RUNS/\$id"
    printf 'status: running\npid: %s\n' "\$\$" > "\$RUNS/\$id/meta.yaml"
    (
      sleep "\$FINISH"
      {
        printf 'diff --git a/src/x.py b/src/x.py\n'
        printf '--- a/src/x.py\n+++ b/src/x.py\n'
        printf '@@ -0,0 +1 @@\n+worker wrote a real diff at t+%ss\n' "\$FINISH"
      } > "\$RUNS/\$id/diff.patch"
      printf 'status: complete\npid: %s\nexit_code: 0\n' "\$\$" > "\$RUNS/\$id/meta.yaml"
    ) >/dev/null 2>&1 &
    disown
    printf '%s\n' "\$id"
    ;;
  status)
    cat "\$RUNS/\${2:-}/meta.yaml" 2>/dev/null
    ;;
  *) exit 2 ;;
esac
STUB
chmod +x "$TMP/freepool-stub.sh"
# Hermetic admission: a trivial estimate stub (the real judge may probe a
# model) maps to Light -> no floor -> freepool selectable for this bulk probe.
cat > "$TMP/judge-light.sh" <<'JEOF'
#!/usr/bin/env bash
printf '%s\n' '{"complexity":"trivial","work_kind":"build","estimate_source":"fallback"}'
JEOF
chmod +x "$TMP/judge-light.sh"
# Poison every non-freepool launcher so a spill would be loud, not silent.
for _arm in glm kimi codex; do
  printf '#!/usr/bin/env bash\nprintf "POISON: real provider spawn attempted\\n" >&2\nexit 99\n' > "$TMP/poison-${_arm}.sh"
  chmod +x "$TMP/poison-${_arm}.sh"
done
# PHASE-GATE-IS-INVERTED-01: this bulk probe maps to Standard, which now
# requires plan+gate1 records before the dispatcher will spawn; seed the
# lead-authored evidence for this mission (both root names must agree).
FP08_SIG="$(printf '%s' "FP-08 wait no-work probe with a real diff ${TMP}" | tr -d '\r' | tr -s '[:space:]' ' ' | sed -e 's/^ //' -e 's/ $//' | shasum -a 256 | awk '{print substr($1, 1, 8)}')"
mkdir -p "$REPO2/docs/handoff/FP08-$FP08_SIG"
printf '# FP-08 wait no-work probe\n\nfixture lead-authored plan\n' > "$REPO2/docs/handoff/FP08-$FP08_SIG/brief.md"
( cd "$REPO2" && PROJECT_ROOT="$REPO2" LEADV2_PROJECT_ROOT="$REPO2" bash "${SCRIPTS_ROOT}/leadv2-phase-record.sh" record "$FP08_SIG" plan \
    --status done --artifact "docs/handoff/FP08-$FP08_SIG/brief.md" --owner lead:fixture ) >/dev/null 2>&1 || true
( cd "$REPO2" && PROJECT_ROOT="$REPO2" LEADV2_PROJECT_ROOT="$REPO2" bash "${SCRIPTS_ROOT}/leadv2-phase-record.sh" record "$FP08_SIG" gate1 \
    --status done --reason 'fixture Gate 1 decision' --owner lead:fixture ) >/dev/null 2>&1 || true
( cd "$REPO2" && PROJECT_ROOT="$REPO2" LEADV2_PROJECT_ROOT="$REPO2" bash "${SCRIPTS_ROOT}/leadv2-phase-record.sh" record "$FP08_SIG" diverge \
    --status n/a --reason 'fixture: no diverge round' --owner lead:fixture ) >/dev/null 2>&1 || true
a_out="$(cd "$REPO2" && LEADV2_STATE_ROOT="$TMP/state-root2" \

  LEADV2_ROUTE_ARBITER_QUOTA_LIVE="$TMP/live.sh" \
  LEADV2_ROUTE_ARBITER_FREEPOOL_GATE="$TMP/free.sh" \
  LEADV2_ROUTE_ARBITER_STATE_FILE="$TMP/state-wait" \
  ROUTE_TEST_QUOTA="$(quota_json 99 99 99)" \
  CLAUDE_PROJECT_ROOT="$REPO2" PROJECT_ROOT="$REPO2" LEADV2_PROJECT_ROOT="$REPO2" \
  LEADV2_DISPATCH_CACHE_DIR="$TMP/cache2" \
  LEADV2_DISPATCH_E2E_GATE=0 LEADV2_DISPATCH_REVIEW_GATE=0 LEADV2_DISPATCH_ARCHITECT_GATE=0 \
  LEADV2_REQUIRE_PHASES=0 \
  LEADV2_ROUTER_V2=0 LEADV2_EXCLUDED_ARMS=__none__ LEADV2_LANE_SHAPE=off \
  LEADV2_BURN_GOVERNOR=0 \
  LEADV2_TASK_JUDGE_BIN="$TMP/judge-light.sh" \
  LEADV2_ARM_EARLY_VERDICT_S=3 LEADV2_ARM_EARLY_VERDICT_POLL_S=0.5 \
  LEADV2_DISPATCH_FREEPOOL_BIN="$TMP/freepool-stub.sh" FP_STUB_RUNS="$FP_RUNS" FP_STUB_FINISH_S=8 \
  LEADV2_DISPATCH_GLM_BIN="$TMP/poison-glm.sh" \
  LEADV2_DISPATCH_KIMI_BIN="$TMP/poison-kimi.sh" \
  LEADV2_DISPATCH_CODEX_BIN="$TMP/poison-codex.sh" \
  LEADV2_DISPATCH_SUBSESSION_BIN="$WORKER" \
  bash "$DISPATCH_BIN" "FP-08 wait no-work probe with a real diff ${TMP}" \
    --kind code --task-class bulk --writes src/x.py 2>&1 || true)"
printf '%s\n' "$a_out" > "$TMP/a-out.log"
if printf '%s\n' "$a_out" | grep -q 'route_resolved by=arbiter role=worker arm=freepool'; then
  pass "(a) bulk build resolved to freepool"
else
  fail "(a) bulk build did not resolve to freepool: $(printf '%s\n' "$a_out" | grep -m1 'route_resolved\|refused\|arbiter_broken' || echo "no-resolution-lines (log: $TMP/a-out.log)")"
fi
if printf '%s\n' "$a_out" | grep -qE 'channel_no_work|arm_refused by=router model=freepool'; then
  fail "(a) waiter declared freepool no_work/refused while the worker was still running"
else
  pass "(a) waiter did not declare no_work early (worker finishes at t+8s, window is 3s)"
fi
# The run must actually COMPLETE with the real diff on disk (bounded poll).
a_done=0; a_diff=0
for _ in $(seq 1 40); do
  if grep -q '^status: complete' "$FP_RUNS"/*/meta.yaml 2>/dev/null; then a_done=1; fi
  if ls "$FP_RUNS"/*/diff.patch >/dev/null 2>&1; then a_diff=1; fi
  [[ "$a_done" == 1 && "$a_diff" == 1 ]] && break
  sleep 0.5
done
if [[ "$a_done" == 1 ]]; then pass "(a) freepool run finalized complete after the window"; else fail "(a) freepool run never completed"; fi
if [[ "$a_diff" == 1 ]]; then pass "(a) run left a REAL diff on disk (diff.patch with hunks)"; else fail "(a) no diff artifact on disk"; fi

# ── (d) NEGATIVE CONTROL — RUN RED (mission test d) ─────────────────────────
# Mutate a throwaway copy of the arbiter so the floor can never apply, re-run
# the EXACT (b) invocation, and require (b)'s central assertion to FAIL:
# freepool must WIN and the floor token must vanish. If it does not flip, the
# mutation did not neutralize the floor AND/OR (b) is not load-bearing.
sed 's/^floor_applies = .*/floor_applies = False/' "$ARBITER" > "$TMP/arb-mutated.sh"
if grep -q '^floor_applies = False' "$TMP/arb-mutated.sh"; then
  pass "(negative-control) floor mutation applied to a throwaway arbiter copy"
else
  fail "(negative-control) floor mutation did not land — control is void"
fi
mut_out="$(run_arbiter "$STD_BUILD_QUOTA" '{"kind":"code","size":"standard"}' "$TMP/arb-mutated.sh")"
b_would_fail=0
[[ "$mut_out" == *'arm=freepool '* ]] && b_would_fail=$((b_would_fail + 1))   # (b) outcome assertion goes red
[[ "$mut_out" != *'floor_applied=1'* ]] && b_would_fail=$((b_would_fail + 1)) # (b) journal assertion goes red
if [[ "$b_would_fail" -eq 2 ]]; then
  pass "(negative-control) with the floor removed, (b) runs RED: freepool WINS the standard build and the floor token vanishes"
else
  fail "(negative-control) mutated arbiter did not flip the winner — (b) is not load-bearing ($mut_out)"
fi


# ── FP-06 (e) capability_floor knob: full -> freepool WINS a Standard build ──
# (inverse of (b)); bulk_only keeps (b)'s behavior. Precedence env > yaml >
# default, resolved inside the arbiter and surfaced as floor_mode/floor_mode_
# source tokens on its output line. A throwaway arm.yaml copy carries the
# yaml source (never the canonical file); a key-less copy proves default.
ARM_YAML_FULL="$TMP/freepool-arm-full.yaml"; ARM_YAML_NONE="$TMP/freepool-arm-none.yaml"; ARM_YAML_BULK="$TMP/freepool-arm-bulk.yaml"
printf 'capability_floor: full\n' > "$ARM_YAML_FULL"
printf 'capability_floor: bulk_only\n' > "$ARM_YAML_BULK"
printf '# no capability_floor key here\nmodel_rank: []\n' > "$ARM_YAML_NONE"

# (e1) env full: freepool wins the standard build, no floor token, mode tokens
out="$(FREEPOOL_CAPABILITY_FLOOR=full run_arbiter "$STD_BUILD_QUOTA" '{"kind":"code","size":"standard"}')"
if [[ "$out" == *'arm=freepool '* ]]; then
  pass "(e1) env full: freepool WINS the standard build (inverse of (b))"
else
  fail "(e1) env full: freepool still demoted ($out)"
fi
if [[ "$out" == *'floor_applied=1'* ]]; then
  fail "(e1) env full: floor token must vanish in full mode ($out)"
else
  pass "(e1) env full: no floor token in full mode"
fi
if [[ "$out" == *'floor_mode=full floor_mode_source=env'* ]]; then
  pass "(e1) env full: floor_mode=full floor_mode_source=env tokens present"
else
  fail "(e1) env full: floor_mode tokens missing ($out)"
fi

# (e2) yaml full (env unset): same win, source=yaml
out="$(FREEPOOL_ARM_CONFIG="$ARM_YAML_FULL" run_arbiter "$STD_BUILD_QUOTA" '{"kind":"code","size":"standard"}')"
if [[ "$out" == *'arm=freepool '* ]]; then
  pass "(e2) yaml full: freepool WINS the standard build"
else
  fail "(e2) yaml full: freepool still demoted ($out)"
fi
if [[ "$out" == *'floor_mode=full floor_mode_source=yaml'* ]]; then
  pass "(e2) yaml full: floor_mode=full floor_mode_source=yaml tokens present"
else
  fail "(e2) yaml full: floor_mode tokens missing ($out)"
fi

# (e3) garbage env falls through to the yaml key (bulk_only wins, source=yaml);
# garbage env + key-less yaml falls all the way to default.
out="$(FREEPOOL_CAPABILITY_FLOOR=nonsense FREEPOOL_ARM_CONFIG="$ARM_YAML_BULK" run_arbiter "$STD_BUILD_QUOTA" '{"kind":"code","size":"standard"}')"
if [[ "$out" != *'arm=freepool '* && "$out" == *'floor_mode=bulk_only floor_mode_source=yaml'* ]]; then
  pass "(e3) garbage env falls through to the yaml key (bulk_only, source=yaml)"
else
  fail "(e3) garbage env did not fall through to yaml ($out)"
fi
out="$(FREEPOOL_CAPABILITY_FLOOR=also-wrong FREEPOOL_ARM_CONFIG="$ARM_YAML_NONE" run_arbiter "$STD_BUILD_QUOTA" '{"kind":"code","size":"standard"}')"
if [[ "$out" != *'arm=freepool '* && "$out" == *'floor_mode=bulk_only floor_mode_source=default'* ]]; then
  pass "(e3) no env + no yaml key: default bulk_only, source=default"
else
  fail "(e3) default resolution wrong ($out)"
fi

# (e4) dispatcher level: env full on the (dispatch) probe shape -> the
# freepool_floor_mode journal line fires AND route_resolved picks freepool for
# a STANDARD build (the inverse of the dispatch assertion above).
REPO3="$TMP/repo3"
mkdir -p "$REPO3/.claude/ref" "$REPO3/docs/leadv2" "$REPO3/docs/leadv2/tasks"
git -C "$REPO3" init -q -b main
git -C "$REPO3" config user.email t@e.com; git -C "$REPO3" config user.name t
: > "$REPO3/seed"; git -C "$REPO3" add seed; git -C "$REPO3" commit -qm seed
cp "$ROUTING" "$REPO3/.claude/ref/leadv2-routing.yaml"
e4_out="$(cd "$REPO3" && LEADV2_STATE_ROOT="$TMP/state-root3" \
  LEADV2_ROUTE_ARBITER_QUOTA_LIVE="$TMP/live.sh" \
  LEADV2_ROUTE_ARBITER_FREEPOOL_GATE="$TMP/free.sh" \
  LEADV2_ROUTE_ARBITER_STATE_FILE="$TMP/state-dispatch3" \
  ROUTE_TEST_QUOTA="$STD_BUILD_QUOTA" \
  FREEPOOL_CAPABILITY_FLOOR=full \
  CLAUDE_PROJECT_ROOT="$REPO3" LEADV2_PROJECT_ROOT="$REPO3" \
  LEADV2_DISPATCH_CACHE_DIR="$TMP/cache3" \
  LEADV2_DISPATCH_E2E_GATE=0 LEADV2_DISPATCH_REVIEW_GATE=0 LEADV2_DISPATCH_ARCHITECT_GATE=0 \
  LEADV2_REQUIRE_PHASES=0 \
  LEADV2_ROUTER_V2=0 LEADV2_EXCLUDED_ARMS=__none__ LEADV2_LANE_SHAPE=off \
  LEADV2_BURN_GOVERNOR=0 LEADV2_ARM_EARLY_VERDICT_S=0 \
  LEADV2_TASK_JUDGE_BIN=/bin/false \
  LEADV2_DISPATCH_SUBSESSION_BIN="$WORKER" \
  bash "$DISPATCH_BIN" "FP-06 floor-mode-full dispatch probe ${TMP}" \
    --kind code --task-class standard --no-spawn --writes src/x.py 2>&1 || true)"
printf '%s\n' "$e4_out" > "$TMP/e4-out.log"
if printf '%s\n' "$e4_out" | grep -q 'freepool_floor_mode mode=full source=env test_only=0 task=[0-9a-f]\{8\}'; then
  pass "(e4) freepool_floor_mode mode=full source=env journaled by the dispatcher"
else
  fail "(e4) freepool_floor_mode journal line missing (log: $TMP/e4-out.log)"
fi
if printf '%s\n' "$e4_out" | grep -q 'route_resolved by=arbiter role=worker arm=freepool'; then
  pass "(e4) floor mode full: route_resolved PICKS freepool for a standard build"
else
  fail "(e4) floor mode full: freepool still not picked (log: $TMP/e4-out.log)"
fi
# ...and with no override the canonical config (capability_floor: bulk_only)
# resolves via yaml and the dispatcher journals it.
e4b_out="$(cd "$REPO3" && LEADV2_STATE_ROOT="$TMP/state-root3" \
  LEADV2_ROUTE_ARBITER_QUOTA_LIVE="$TMP/live.sh" \
  LEADV2_ROUTE_ARBITER_FREEPOOL_GATE="$TMP/free.sh" \
  LEADV2_ROUTE_ARBITER_STATE_FILE="$TMP/state-dispatch3b" \
  ROUTE_TEST_QUOTA="$STD_BUILD_QUOTA" \
  CLAUDE_PROJECT_ROOT="$REPO3" LEADV2_PROJECT_ROOT="$REPO3" \
  LEADV2_DISPATCH_CACHE_DIR="$TMP/cache3" \
  LEADV2_DISPATCH_E2E_GATE=0 LEADV2_DISPATCH_REVIEW_GATE=0 LEADV2_DISPATCH_ARCHITECT_GATE=0 \
  LEADV2_REQUIRE_PHASES=0 \
  LEADV2_ROUTER_V2=0 LEADV2_EXCLUDED_ARMS=__none__ LEADV2_LANE_SHAPE=off \
  LEADV2_BURN_GOVERNOR=0 LEADV2_ARM_EARLY_VERDICT_S=0 \
  LEADV2_TASK_JUDGE_BIN=/bin/false \
  LEADV2_DISPATCH_SUBSESSION_BIN="$WORKER" \
  bash "$DISPATCH_BIN" "FP-06 floor-mode-default dispatch probe ${TMP}" \
    --kind code --task-class standard --no-spawn --writes src/x.py 2>&1 || true)"
if printf '%s\n' "$e4b_out" | grep -q 'freepool_floor_mode mode=bulk_only source=yaml test_only=0 task=[0-9a-f]\{8\}'; then
  pass "(e4b) no override: mode=bulk_only source=yaml journaled (canonical arm.yaml key)"
else
  fail "(e4b) default-mode journal line missing ($(printf '%s\n' "$e4b_out" | grep -m1 freepool_floor_mode || echo none))"
fi

printf '\n=== %d passed, %d failed ===\n' "${PASS}" "${FAIL}"
[[ "${FAIL}" == 0 ]]
