#!/usr/bin/env bash
# changed-scope triggers, self-registered (SD-SUITE-MAP-SERIALIZES-EVERY-WAVE-01, migrated from tests/run-all.sh EXTRA_SUITE_MAP; discovered by scan_suite_triggers):
# run-all-triggers: leadv2-backlog-pump
# tests/test-backlog-pump.sh — BACKLOG-PUMP-01 + C-1 (LANE-CONCURRENCY-IN-PLUGIN)
# coverage.
#
# C-1 added cases (2026-08-02). The quota gate (`_quota_ok`) used to read
# usable_now/remaining_pct at the TOP level of each provider bucket; those keys
# live INSIDE each provider's binding window, so the gate fell through every
# loop and refused unconditionally while every provider sat at 33–84 % remaining.
# Coverage now feeds a VERBATIM live capture (scripts/tests/fixtures/
# quota-live-real-20260802.json) — never a hand-written object shaped to the
# buggy assumption — plus cases for the floor/ceiling/live-count/refusal-dedupe
# behaviour the redesign added.
#
# Fully isolated: LEADV2_PROJECT_ROOT / LEADV2_STATE_ROOT point at throwaway tmp
# dirs; LEADV2_BACKLOG_PUMP_DISPATCH_BIN / LIVENESS_BIN / QUOTA_BIN / JOURNAL_BIN
# stub out the real dispatch, liveness, quota reader and journal so this never
# touches a real ledger, scans real lanes, or spawns a real worker. Run:
#   bash scripts/tests/test-backlog-pump.sh
#
# Negative control (C3b): named mutation this suite must kill — in
# leadv2-backlog-pump.sh's ceiling check, `cap=$(( MAX_CONCURRENT - active ))`
# off-by-one'd to `cap=$(( MAX_CONCURRENT - active + 1 ))`. At the ceiling
# (active==MAX_CONCURRENT==6) this silently lets a 7th lane dispatch instead
# of refusing at_ceiling — the exact regression test_ceiling_refuses_7th
# exists to catch. The suite applies this mutation to a temp copy of the pump
# script and asserts the 7th candidate dispatches (red).

set -uo pipefail

# BURN-GOVERNOR-01: the burn gate defaults ON and reads the host's real
# ~/.claude/burn/history.db -- a hot host would red this suite on `exit 6`.
export LEADV2_BURN_GOVERNOR=0
# This suite supplies its own pump setting in _run_pump_x.  Do not inherit the
# host kill switch: that would make ordinary fixture cases no-ops, while the
# dedicated kill_switch_off case still passes LEADV2_BACKLOG_PUMP=0 explicitly.
unset LEADV2_BACKLOG_PUMP

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
PUMP_SH="${PLUGIN_DIR}/scripts/leadv2-backlog-pump.sh"
TASKS_LIB="${PLUGIN_DIR}/scripts/leadv2-tasks-lib.sh"
QUOTA_SHAPE="${PLUGIN_DIR}/scripts/lib/leadv2-quota-shape.py"
REAL_QUOTA_FIXTURE="${SCRIPT_DIR}/fixtures/quota-live-real-20260802.json"

PASS=0; FAIL=0; ERRORS=()
log()  { printf -- '[TEST] %s\n' "$*"; }
pass() { PASS=$((PASS + 1)); log "PASS: $1"; }
fail() { FAIL=$((FAIL + 1)); ERRORS+=("FAIL: $1"); log "FAIL: $1"; }

CLEANUP_DIRS=()
cleanup() {
  for d in "${CLEANUP_DIRS[@]:-}"; do
    [[ -n "$d" && -d "$d" ]] && rm -rf "$d"
  done
  return 0
}
trap cleanup EXIT

_mktmp() {
  local d
  d="$(mktemp -d "${TMPDIR:-/tmp}/lv2bp.XXXXXX" 2>/dev/null)" || {
    echo "Failed to create temporary directory" >&2
    exit 1
  }
  CLEANUP_DIRS+=("$d")
  printf '%s' "$d"
}

# ── stubs ───────────────────────────────────────────────────────────────────
# A quota-bin stub ignores its args and cats a payload file (real or derived).
# The pump calls `bash <bin> json`.
_make_quota_bin() {  # $1=payload-file -> stub path
  local payload="$1" bin="$(_mktmp)/quota-bin.sh"
  cat >"$bin" <<STUB
#!/usr/bin/env bash
cat "$payload"
STUB
  chmod +x "$bin"
  printf '%s' "$bin"
}

# A liveness-bin stub ignores its args and cats a lanes JSON. The pump calls
# `timeout 20 bash <bin> --all --json --no-codex`.
_make_liveness_bin() {  # $1=json-file -> stub path
  local payload="$1" bin="$(_mktmp)/liveness-bin.sh"
  cat >"$bin" <<STUB
#!/usr/bin/env bash
cat "$payload"
STUB
  chmod +x "$bin"
  printf '%s' "$bin"
}

# A journal stub appends "<type>|<line>" to a logfile so dedupe/sweep/starved
# assertions can count emitted lines. jemit calls: <bin> append <task> <type> <line>.
_make_journal_stub() {  # $1=logfile -> stub path
  local logfile="$1" bin="$(_mktmp)/journal-bin.sh"
  : >"$logfile"
  cat >"$bin" <<STUB
#!/usr/bin/env bash
printf '%s|%s\n' "\$3" "\$4" >>"$logfile"
STUB
  chmod +x "$bin"
  printf '%s' "$bin"
}

# A dispatch stub records invocations and returns a configurable rc, emitting a
# worker_spawned line so the C-1 sidecar join can parse a dispatch-<sig8> id.
_make_dispatch_stub() {  # $1=dir -> "stub rc_file log_file"
  local dir="$1"
  local stub="${dir}/dispatch-stub.sh" rcfile="${dir}/dispatch-rc" logfile="${dir}/dispatch-log"
  echo 0 >"$rcfile"; : >"$logfile"
  cat >"$stub" <<STUB
#!/usr/bin/env bash
printf '%s\n' "\$1" >>"${logfile}"
# Mimic leadv2-dispatch-code.sh's stdout contract (C-1 sidecar seam).
printf 'worker_spawned model=glm task=aabbcc%02d attempt=1 handle=job-%d\n' "\$(wc -l <"${logfile}")" "\$(wc -l <"${logfile}")"
exit "\$(cat "${rcfile}")"
STUB
  chmod +x "$stub"
  printf '%s %s %s\n' "$stub" "$rcfile" "$logfile"
}

# Default empty liveness payload (no lanes). Tests needing live lanes override.
EMPTY_LIVENESS='{"lanes":[],"jobs":[],"availability":{},"count_live":0}'

# One isolated repo+state root pair, with tasks.yaml + active.yaml seeded.
_new_fixture() {
  local repo state
  repo="$(_mktmp)"; state="$(_mktmp)"
  (cd "$repo" && git init -q && git config user.email t@t.test && git config user.name t \
     && mkdir -p docs/leadv2 docs/handoff && echo init >README.md && git add -A \
     && git commit -q -m init)
  mkdir -p "${state}/docs/leadv2"
  cat >"${state}/docs/leadv2/active.yaml" <<'YAML'
meta:
  hard_limit: 6
sessions: []
YAML
  printf '%s %s\n' "$repo" "$state"
}

_write_tasks() {  # $1=repo $2=yaml-body
  cat >"${1}/docs/tasks.yaml" <<EOF
$2
EOF
}

_set_active() {  # $1=state-root $2=active.yaml-body
  mkdir -p "${1}/docs/leadv2"
  cat >"${1}/docs/leadv2/active.yaml" <<EOF
$2
EOF
}

_write_lanes_json() {  # $1=file $2=json-body
  printf '%s' "$2" >"$1"
}

# Build a liveness JSON with N live top-level lanes, without a fragile
# python %-format inside $() (bash 3.2 mangles nested quoting there). Uses
# printf -v, which is bash 3.2-safe.
_gen_lanes_json() {  # $1=count $2=outfile
  local n="$1" out="$2" i=0 body="" id
  for ((i=0; i<n; i++)); do
    [[ -n "$body" ]] && body+=","
    printf -v id 'dispatch-%02d' "$i"
    body+="{\"lane\":\"${id}\",\"verdict\":\"alive\",\"child_of\":null}"
  done
  printf '{"lanes":[%s],"count_live":%s}' "$body" "$n" >"$out"
}

# env-wrapped pump invocation lives in _run_pump_x below (defined after the
# stub helpers). MAX pinned to 6 (env wins over active.yaml) so floor/ceiling
# arithmetic is deterministic; liveness + quota default to isolated stubs
# unless the caller exports overrides.

# ── C-1 cases 1–5: the quota shape module (gate), fed the REAL capture ──────

test_shape_gate_pass_floor10() {
  local out rc=0
  out="$(python3 "$QUOTA_SHAPE" gate --floor 10 --json-file "$REAL_QUOTA_FIXTURE" 2>/dev/null)" || rc=$?
  if [[ "$rc" -eq 0 && "$out" == *verdict=pass* ]]; then
    pass "shape_gate_pass_floor10: real capture clears floor 10 (the regression that never existed)"
  else
    fail "shape_gate_pass_floor10: rc=$rc out=$out"
  fi
}

test_shape_gate_pass_floor30() {
  local out rc=0
  out="$(python3 "$QUOTA_SHAPE" gate --floor 30 --json-file "$REAL_QUOTA_FIXTURE" 2>/dev/null)" || rc=$?
  # glm binding=weekly is the tightest bucket (~32%); it still clears 30.
  if [[ "$rc" -eq 0 && "$out" == *verdict=pass* ]]; then
    pass "shape_gate_pass_floor30: tightest binding window still clears 30"
  else
    fail "shape_gate_pass_floor30: rc=$rc out=$out"
  fi
}

test_shape_gate_refuse_scaled() {
  # DERIVED (never hand-authored): scale every binding window below floor.
  local scaled rc=0
  scaled="$(_mktmp)/scaled.json"
  python3 - "$REAL_QUOTA_FIXTURE" "$scaled" <<'PY'
import json, sys
src, dst = sys.argv[1], sys.argv[2]
d = json.load(open(src))
def zap(win):
    if isinstance(win, dict):
        win["remaining_pct"] = 1.0
# glm
for wname in ("five_hour", "weekly"):
    if wname in d.get("glm", {}): zap(d["glm"][wname])
# codex
for w in d.get("codex", {}).get("windows", []): zap(w)
# anthropic
for a in d.get("anthropic", {}).get("accounts", []):
    for wname in ("five_hour", "seven_day"):
        if wname in a: zap(a[wname])
json.dump(d, open(dst, "w"))
PY
  python3 "$QUOTA_SHAPE" gate --floor 10 --json-file "$scaled" >/dev/null 2>&1 || rc=$?
  if [[ "$rc" -eq 1 ]]; then
    pass "shape_gate_refuse_scaled: all binding windows below floor -> refuse"
  else
    fail "shape_gate_refuse_scaled: expected refuse(rc=1), got rc=$rc"
  fi
}

test_shape_gate_failopen() {
  local rc1=0 rc2=0
  echo '{}' | python3 "$QUOTA_SHAPE" gate --floor 10 --stdin >/dev/null 2>&1 || rc1=$?
  printf 'not json' | python3 "$QUOTA_SHAPE" gate --floor 10 --stdin >/dev/null 2>&1 || rc2=$?
  if [[ "$rc1" -eq 0 && "$rc2" -eq 0 ]]; then
    pass "shape_gate_failopen: {} and non-JSON both pass (quota-reader outage never total-outages dispatch)"
  else
    fail "shape_gate_failopen: rc1=$rc1 rc2=$rc2"
  fi
}

test_shape_gate_codex_limit_reached() {
  # DERIVED: codex says limit_reached while its remaining_pct looks healthy; glm
  # and anthropic are forced below floor so codex is the only candidate.
  local deriv rc=0
  deriv="$(_mktmp)/codex-limited.json"
  python3 - "$REAL_QUOTA_FIXTURE" "$deriv" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
d["codex"]["limit_reached"] = True
for w in d["codex"]["windows"]: w["remaining_pct"] = 80.0   # healthy-looking
for wname in ("five_hour", "weekly"): d["glm"][wname]["remaining_pct"] = 1.0
for a in d["anthropic"]["accounts"]:
    for wname in ("five_hour", "seven_day"): a[wname]["remaining_pct"] = 1.0
json.dump(d, open(sys.argv[2], "w"))
PY
  python3 "$QUOTA_SHAPE" gate --floor 10 --json-file "$deriv" >/dev/null 2>&1 || rc=$?
  if [[ "$rc" -eq 1 ]]; then
    pass "shape_gate_codex_limit_reached: a provider that says stop is not rescued by a healthy-looking pct"
  else
    fail "shape_gate_codex_limit_reached: expected refuse, got rc=$rc"
  fi
}

# ── C-1 cases 6–9: live lane counting ───────────────────────────────────────
# These exercise the pump's status output (active count + lane names), driven
# by liveness stubs.

test_count_lane_from_liveness() {  # case 6
  local repo state lj bin
  read -r repo state < <(_new_fixture)
  lj="$(_mktmp)/lanes.json"
  _write_lanes_json "$lj" '{"lanes":[{"lane":"dispatch-aabbcc01","verdict":"alive","child_of":null}],"count_live":1}'
  bin="$(_make_liveness_bin "$lj")"
  _set_active "$state" 'meta: {hard_limit: 6}
sessions: []'
  local out
  out="$(LEADV2_BACKLOG_PUMP_LIVENESS_BIN="$bin" _run_pump_x "$repo" "$state" status 2>/dev/null)"
  if [[ "$out" == *"active=1"* && "$out" == *"dispatch-aabbcc01"* ]]; then
    pass "count_lane_from_liveness: a live dispatch lane is counted (active=1, not 0)"
  else
    fail "count_lane_from_liveness: active=1 expected, got: $out"
  fi
}

test_count_no_double_after_join() {  # case 7
  local repo state lj bin cache mapdir
  read -r repo state < <(_new_fixture)
  lj="$(_mktmp)/lanes.json"
  _write_lanes_json "$lj" '{"lanes":[{"lane":"dispatch-aaa","verdict":"alive","child_of":null}],"count_live":1}'
  bin="$(_make_liveness_bin "$lj")"
  _set_active "$state" 'meta: {hard_limit: 6}
sessions:
  - task_id: T1
    started_at: "2026-08-02T10:00:00Z"'
  # Sidecar already joined T1 -> dispatch-aaa.
  cache="$repo/.claude/cache/backlog-pump"; mapdir="$cache/backlog-pump-lane-map"
  mkdir -p "$mapdir"; printf '%s' "dispatch-aaa" >"$mapdir/T1"
  local out
  out="$(LEADV2_BACKLOG_PUMP_LIVENESS_BIN="$bin" _run_pump_x "$repo" "$state" status 2>/dev/null)"
  if [[ "$out" == *"active=1"* ]]; then
    pass "count_no_double_after_join: a task joined to a lane is not double-counted"
  else
    fail "count_no_double_after_join: active=1 expected, got: $out"
  fi
}

test_count_ignores_child_lanes() {  # case 8
  local repo state lj bin
  read -r repo state < <(_new_fixture)
  lj="$(_mktmp)/lanes.json"
  _write_lanes_json "$lj" '{"lanes":[
    {"lane":"dispatch-parent","verdict":"alive","child_of":null},
    {"lane":"dispatch-child","verdict":"alive","child_of":"dispatch-parent"}
  ],"count_live":1}'
  bin="$(_make_liveness_bin "$lj")"
  _set_active "$state" 'meta: {hard_limit: 6}
sessions: []'
  local out
  out="$(LEADV2_BACKLOG_PUMP_LIVENESS_BIN="$bin" _run_pump_x "$repo" "$state" status 2>/dev/null)"
  if [[ "$out" == *"active=1"* && "$out" != *"dispatch-child"* ]]; then
    pass "count_ignores_child_lanes: child_of lane rides a parent slot"
  else
    fail "count_ignores_child_lanes: active=1 expected, got: $out"
  fi
}

test_count_sweeps_stale_reservation() {  # case 9
  local repo state lj bin jlog jbin
  read -r repo state < <(_new_fixture)
  lj="$(_mktmp)/lanes.json"; _write_lanes_json "$lj" "$EMPTY_LIVENESS"
  bin="$(_make_liveness_bin "$lj")"
  # Reservation older than TTL, not joined.
  _set_active "$state" 'meta: {hard_limit: 6}
sessions:
  - task_id: T-stale
    started_at: "2026-08-01T00:00:00Z"'
  jlog="$(_mktmp)/journal.log"; jbin="$(_make_journal_stub "$jlog")"
  local out
  out="$(LEADV2_BACKLOG_PUMP_LIVENESS_BIN="$bin" LEADV2_JOURNAL_BIN="$jbin" \
         LEADV2_BACKLOG_PUMP_RESERVATION_TTL_S=60 _run_pump_x "$repo" "$state" status 2>/dev/null)"
  if [[ "$out" == *"active=0"* ]] && grep -q "pump_swept_stale_reservation" "$jlog"; then
    pass "count_sweeps_stale_reservation: stale reservation swept, not counted"
  else
    fail "count_sweeps_stale_reservation: active=0 + sweep expected; out=$out log=$(cat "$jlog")"
  fi
}

# ── C3b negative control: named mutation must be caught by ceiling_refuses_7th
test_control_ceiling_mutation_caught() {
  local mut_pump repo state lj bin stub rcfile logfile jlog jbin mut_status
  # NB: the mutated copy MUST live alongside the real pump script (not in an
  # arbitrary tmp dir) — leadv2-backlog-pump.sh resolves ALL sibling deps
  # (leadv2-tasks-lib.sh, leadv2-active-registry.sh, lib/leadv2-quota-shape.py,
  # leadv2-state-path.sh) via SCRIPT_DIR="$(dirname "${BASH_SOURCE[0]}")"; a
  # copy dropped into /tmp breaks every one of those sources and the pump
  # dies before it ever reaches the ceiling check, giving a false "caught".
  mut_pump="${PLUGIN_DIR}/scripts/.ctrl-mut-backlog-pump-$$.sh"
  trap 'rm -f "$mut_pump"' RETURN
  python3 - "$PUMP_SH" "$mut_pump" <<'PYEOF'
import sys
src, dst = sys.argv[1], sys.argv[2]
text = open(src, encoding="utf-8").read()
old = '  active="$LANE_COUNT"\n  cap=$(( MAX_CONCURRENT - active ))\n'
new = '  active="$LANE_COUNT"\n  cap=$(( MAX_CONCURRENT - active + 1 ))\n'
if old not in text:
    sys.exit(2)
open(dst, "w", encoding="utf-8").write(text.replace(old, new, 1))
PYEOF
  mut_status=$?
  if [[ $mut_status -ne 0 ]]; then
    fail "control: mutation source pattern not found (pump script drifted, update mutation)"
    return 0
  fi
  chmod +x "$mut_pump"
  read -r repo state < <(_new_fixture)
  _write_tasks "$repo" '- id: T7
  lane: action
  status: pending
  priority: high
  title: seventh candidate (control)
  created_at: "2026-01-01T00:00:00Z"
'
  lj="$(_mktmp)/lanes.json"
  _gen_lanes_json 6 "$lj"
  bin="$(_make_liveness_bin "$lj")"
  read -r stub rcfile logfile < <(_make_dispatch_stub "$state")
  jlog="$(_mktmp)/journal.log"; jbin="$(_make_journal_stub "$jlog")"
  local qbin lbin
  qbin="$(_make_quota_bin "$REAL_QUOTA_FIXTURE")"
  lbin="$bin"
  LEADV2_PROJECT_ROOT="$repo" PROJECT_ROOT="$repo" LEADV2_STATE_ROOT="${state}/docs/leadv2" \
  CLAUDE_PROJECT_DIR="$repo" \
  LEADV2_BACKLOG_PUMP=1 LEADV2_BACKLOG_PUMP_MAX=6 LEADV2_BACKLOG_PUMP_LIVENESS_CACHE_S=0 \
  LEADV2_BACKLOG_PUMP_DISPATCH_BIN="$stub" LEADV2_BACKLOG_PUMP_QUOTA_BIN="$qbin" \
  LEADV2_BACKLOG_PUMP_LIVENESS_BIN="$lbin" LEADV2_JOURNAL_BIN="$jbin" LEADV2_JUDGE_DISABLE=1 \
  bash "$mut_pump" check >/dev/null 2>&1
  # Mutation makes cap=1 at the ceiling (active=6): the 7th candidate wrongly
  # dispatches instead of being refused at_ceiling. That is the RED this
  # control proves the real (unmutated) suite would catch.
  if [[ -s "$logfile" ]] && ! grep -q "at_ceiling" "$jlog"; then
    pass "control: off-by-one ceiling mutation lets a 7th lane dispatch -> caught (real suite would go red)"
  else
    fail "control: mutation NOT caught — mutated pump still refused at_ceiling (dispatched=$(cat "$logfile" 2>/dev/null) log=$(cat "$jlog" 2>/dev/null))"
  fi
}

# ── C-1 cases 10–13: floor / ceiling / dedupe / starved ─────────────────────

test_ceiling_refuses_7th() {  # case 10
  local repo state lj bin stub rcfile logfile jlog jbin
  read -r repo state < <(_new_fixture)
  _write_tasks "$repo" '- id: T7
  lane: action
  status: pending
  priority: high
  title: seventh candidate
  created_at: "2026-01-01T00:00:00Z"
'
  lj="$(_mktmp)/lanes.json"
  # 6 live lanes -> at the ceiling (MAX pinned to 6).
  _gen_lanes_json 6 "$lj"
  bin="$(_make_liveness_bin "$lj")"
  read -r stub rcfile logfile < <(_make_dispatch_stub "$state")
  jlog="$(_mktmp)/journal.log"; jbin="$(_make_journal_stub "$jlog")"
  DISPATCH_STUB="$stub" LEADV2_BACKLOG_PUMP_LIVENESS_BIN="$bin" LEADV2_JOURNAL_BIN="$jbin" \
    _run_pump_x "$repo" "$state" check >/dev/null 2>&1
  if [[ ! -s "$logfile" ]] && grep -q "at_ceiling" "$jlog" && grep -q "ceiling=6" "$jlog"; then
    pass "ceiling_refuses_7th: 7th candidate refused with at_ceiling ceiling=6, no 7th lane"
  else
    fail "ceiling_refuses_7th: dispatched=$(cat "$logfile" 2>/dev/null) log=$(cat "$jlog")"
  fi
}

test_floor_dispatches_then_refuses() {  # case 11
  local repo state lj bin stub rcfile logfile qpayload
  # Derived payload factory: every binding window at a given pct.
  _scale_fixture() {  # $1=src $2=dst $3=pct
    python3 - "$1" "$2" "$3" <<'PY'
import json, sys
d=json.load(open(sys.argv[1])); v=float(sys.argv[3])
def s(w):
    if isinstance(w,dict): w["remaining_pct"]=v
for n in ("five_hour","weekly"):
    if n in d.get("glm",{}): s(d["glm"][n])
for w in d.get("codex",{}).get("windows",[]): s(w)
for a in d.get("anthropic",{}).get("accounts",[]):
    for n in ("five_hour","seven_day"):
        if n in a: s(a[n])
json.dump(d,open(sys.argv[2],"w"))
PY
  }

  # 5% -> below-floor bar (2) cleared -> dispatches.
  read -r repo state < <(_new_fixture)
  _write_tasks "$repo" '- id: Tf
  lane: action
  status: pending
  priority: high
  title: floor candidate 5pct
  created_at: "2026-01-01T00:00:00Z"
'
  lj="$(_mktmp)/lanes.json"
  _write_lanes_json "$lj" '{"lanes":[{"lane":"dispatch-one","verdict":"alive","child_of":null}],"count_live":1}'
  bin="$(_make_liveness_bin "$lj")"
  qpayload="$(_mktmp)/q5.json"; _scale_fixture "$REAL_QUOTA_FIXTURE" "$qpayload" 5
  read -r stub rcfile logfile < <(_make_dispatch_stub "$state"); echo 0 >"$rcfile"; : >"$logfile"
  DISPATCH_STUB="$stub" LEADV2_BACKLOG_PUMP_LIVENESS_BIN="$bin" \
    LEADV2_BACKLOG_PUMP_QUOTA_BIN="$(_make_quota_bin "$qpayload")" \
    _run_pump_x "$repo" "$state" check >/dev/null 2>&1
  local dispatched_at_5=0
  [[ -s "$logfile" ]] && dispatched_at_5=1

  # 1% -> under the below-floor bar -> refuses, no dispatch (fresh fixture so the
  # queue is non-empty and the refusal is quota-driven, not queue-empty).
  read -r repo state < <(_new_fixture)
  _write_tasks "$repo" '- id: Tf2
  lane: action
  status: pending
  priority: high
  title: floor candidate 1pct
  created_at: "2026-01-01T00:00:00Z"
'
  lj="$(_mktmp)/lanes.json"
  _write_lanes_json "$lj" '{"lanes":[{"lane":"dispatch-one","verdict":"alive","child_of":null}],"count_live":1}'
  bin="$(_make_liveness_bin "$lj")"
  qpayload="$(_mktmp)/q1.json"; _scale_fixture "$REAL_QUOTA_FIXTURE" "$qpayload" 1
  read -r stub rcfile logfile < <(_make_dispatch_stub "$state"); echo 0 >"$rcfile"; : >"$logfile"
  local jlog jbin; jlog="$(_mktmp)/journal.log"; jbin="$(_make_journal_stub "$jlog")"
  DISPATCH_STUB="$stub" LEADV2_BACKLOG_PUMP_LIVENESS_BIN="$bin" \
    LEADV2_BACKLOG_PUMP_QUOTA_BIN="$(_make_quota_bin "$qpayload")" LEADV2_JOURNAL_BIN="$jbin" \
    _run_pump_x "$repo" "$state" check >/dev/null 2>&1
  local refused_at_1=0
  grep -q "quota_floor" "$jlog" && grep -q "bar=below_floor" "$jlog" && refused_at_1=1

  if [[ "$dispatched_at_5" -eq 1 && "$refused_at_1" -eq 1 && ! -s "$logfile" ]]; then
    pass "floor_dispatches_then_refuses: 5% dispatches (below-floor bar), 1% refuses"
  else
    fail "floor_dispatches_then_refuses: d5=$dispatched_at_5 r1=$refused_at_1 log1=$(cat "$logfile" 2>/dev/null) j=$(cat "$jlog")"
  fi
}

test_refusal_dedupe_collapses() {  # case 12
  local repo state lj bin jlog jbin statefile i
  read -r repo state < <(_new_fixture)
  lj="$(_mktmp)/lanes.json"
  _gen_lanes_json 6 "$lj"
  bin="$(_make_liveness_bin "$lj")"
  jlog="$(_mktmp)/journal.log"; jbin="$(_make_journal_stub "$jlog")"
  for i in 1 2 3 4 5; do
    LEADV2_BACKLOG_PUMP_LIVENESS_BIN="$bin" LEADV2_JOURNAL_BIN="$jbin" \
      LEADV2_BACKLOG_PUMP_REFUSAL_QUIET_S=900 _run_pump_x "$repo" "$state" check >/dev/null 2>&1
  done
  local emitted refused_lines count
  refused_lines="$(grep -c 'pump_refused' "$jlog" 2>/dev/null || echo 0)"
  statefile="$repo/.claude/cache/backlog-pump/backlog-pump-refusal-state"
  count="$(awk -F'|' '{print $5}' "$statefile" 2>/dev/null || echo 0)"
  # First tick emitted immediately (repeats=1); ticks 2-5 suppressed. Then
  # backdate the burst window and fire once more: the suppressed count is
  # carried on the next emitted line as repeats=5.
  local first_epoch now backdated
  now="$(date +%s)"; backdated=$((now - 2000))
  if [[ -f "$statefile" ]]; then
    awk -F'|' -v be="$backdated" 'BEGIN{OFS="|"} {$4=be; print}' "$statefile" >"${statefile}.tmp" && mv "${statefile}.tmp" "$statefile"
  fi
  LEADV2_BACKLOG_PUMP_LIVENESS_BIN="$bin" LEADV2_JOURNAL_BIN="$jbin" \
    LEADV2_BACKLOG_PUMP_REFUSAL_QUIET_S=900 _run_pump_x "$repo" "$state" check >/dev/null 2>&1
  local carried
  carried="$(grep 'pump_refused' "$jlog" | tail -1 | grep -oE 'repeats=[0-9]+' | tail -1)"

  if [[ "$refused_lines" -eq 1 && "$carried" == "repeats=5" ]]; then
    pass "refusal_dedupe_collapses: 5 ticks -> 1 line; suppressed count carried on window expiry (repeats=5)"
  else
    fail "refusal_dedupe_collapses: lines=$refused_lines count=$count carried=$carried log=$(cat "$jlog")"
  fi
}

test_starved_not_refused_below_floor() {  # case 13
  local repo state lj bin jlog jbin
  read -r repo state < <(_new_fixture)
  _write_tasks "$repo" '[]'
  lj="$(_mktmp)/lanes.json"
  _write_lanes_json "$lj" '{"lanes":[{"lane":"dispatch-one","verdict":"alive","child_of":null}],"count_live":1}'
  bin="$(_make_liveness_bin "$lj")"
  jlog="$(_mktmp)/journal.log"; jbin="$(_make_journal_stub "$jlog")"
  LEADV2_BACKLOG_PUMP_LIVENESS_BIN="$bin" LEADV2_JOURNAL_BIN="$jbin" \
    _run_pump_x "$repo" "$state" check >/dev/null 2>&1
  if grep -q "pump_starved" "$jlog" && ! grep -q "pump_refused" "$jlog"; then
    pass "starved_not_refused_below_floor: below floor + empty queue -> pump_starved (distinct from a broken gate)"
  else
    fail "starved_not_refused_below_floor: log=$(cat "$jlog")"
  fi
}

# ── retained existing cases (adjusted for the new stubs) ────────────────────

test_kill_switch_off() {
  local repo state stub rcfile logfile
  read -r repo state < <(_new_fixture)
  _write_tasks "$repo" '- id: T-off
  lane: action
  status: pending
  priority: high
  title: must remain untouched while disabled
  created_at: "2026-01-01T00:00:00Z"
'
  read -r stub rcfile logfile < <(_make_dispatch_stub "$state")
  local before after
  before="$(cat "$repo/docs/tasks.yaml")"
  DISPATCH_STUB="$stub" LEADV2_BACKLOG_PUMP=0 _run_pump_x "$repo" "$state" check >/dev/null 2>&1
  after="$(cat "$repo/docs/tasks.yaml")"
  if [[ ! -s "$logfile" && "$before" == "$after" ]]; then
    pass "kill_switch_off: no dispatch and no queue mutation"
  else
    fail "kill_switch_off: pump changed state while disabled"
  fi
}

test_tree_mid_conflict() {
  local repo state stub rcfile logfile
  read -r repo state < <(_new_fixture)
  _write_tasks "$repo" '- id: T-conflict
  lane: action
  status: pending
  priority: high
  title: must not start during a merge conflict
  created_at: "2026-01-01T00:00:00Z"
'
  read -r stub rcfile logfile < <(_make_dispatch_stub "$state")
  git -C "$repo" rev-parse HEAD >"$repo/.git/MERGE_HEAD"
  DISPATCH_STUB="$stub" _run_pump_x "$repo" "$state" check >/dev/null 2>&1
  if [[ ! -s "$logfile" ]]; then
    pass "tree_mid_conflict: no dispatch while Git has MERGE_HEAD"
  else
    fail "tree_mid_conflict: dispatched into an unresolved tree"
  fi
}

test_tree_state_probe_failure() {
  # A non-Git fixture makes the state probe fail before any queue access. This
  # must remain fail-closed, but must never masquerade as a real conflict.
  local repo state output
  repo="$(_mktmp)"; state="$(_mktmp)"
  mkdir -p "${repo}/docs" "${state}/docs/leadv2"
  printf 'meta: {hard_limit: 6}\nsessions: []\n' >"${state}/docs/leadv2/active.yaml"
  output="$(LEADV2_BACKLOG_PUMP=1 _run_pump_x "$repo" "$state" check 2>&1)"
  if [[ "$output" == *"reason=tree_state_probe_failed rc=2"* && "$output" != *"reason=tree_mid_conflict"* ]]; then
    pass "tree_state_probe_failure: failed Git probe is fail-closed and truthfully labelled"
  else
    fail "tree_state_probe_failure: expected truthful probe failure, got: $output"
  fi
}

test_duplicate_signature_refused() {
  local repo state stub rcfile logfile
  read -r repo state < <(_new_fixture)
  _write_tasks "$repo" '- id: T-duplicate
  lane: action
  status: pending
  priority: high
  title: already represented by a dispatch signature
  created_at: "2026-01-01T00:00:00Z"
'
  read -r stub rcfile logfile < <(_make_dispatch_stub "$state")
  echo 2 >"$rcfile"
  DISPATCH_STUB="$stub" _run_pump_x "$repo" "$state" check >/dev/null 2>&1
  local item
  item="$(LEADV2_PROJECT_ROOT="$repo" PROJECT_ROOT="$repo" bash -c "source '$TASKS_LIB'; leadv2_tasks_by_id T-duplicate" 2>/dev/null)"
  if [[ -s "$logfile" && "$item" == *"status: pending"* && "$item" == *"by: null"* ]]; then
    pass "duplicate_signature_refused: ledger refusal unclaims without redispatch"
  else
    fail "duplicate_signature_refused: duplicate was not safely returned to queue"
  fi
}

test_judgment_class_excluded() {
  local repo state stub rcfile logfile
  read -r repo state < <(_new_fixture)
  _write_tasks "$repo" '- id: T-human
  lane: human-needed
  status: pending
  priority: critical
  title: approve the payment change
  created_at: "2026-01-01T00:00:00Z"
'
  read -r stub rcfile logfile < <(_make_dispatch_stub "$state")
  DISPATCH_STUB="$stub" _run_pump_x "$repo" "$state" check >/dev/null 2>&1
  if [[ ! -s "$logfile" ]]; then
    pass "judgment_class_excluded: human-needed lane never dispatched"
  else
    fail "judgment_class_excluded: dispatched a human-needed task: $(cat "$logfile")"
  fi

  read -r repo state < <(_new_fixture)
  _write_tasks "$repo" '- id: T-arch
  lane: action
  status: pending
  priority: high
  title: redesign the auth subsystem
  created_at: "2026-01-01T00:00:00Z"
'
  read -r stub rcfile logfile < <(_make_dispatch_stub "$state")
  echo 3 >"$rcfile"
  mkdir -p "${state}/docs/leadv2"; : >"${state}/docs/leadv2/open-threads.md"
  DISPATCH_STUB="$stub" _run_pump_x "$repo" "$state" check >/dev/null 2>&1
  local unclaimed=0
  grep -q "^[[:space:]]*status: pending" <(LEADV2_PROJECT_ROOT="$repo" PROJECT_ROOT="$repo" bash -c "source '$TASKS_LIB'; leadv2_tasks_by_id T-arch") 2>/dev/null && unclaimed=1
  if [[ "$unclaimed" -eq 1 ]] && grep -q "T-arch" "${state}/docs/leadv2/open-threads.md" 2>/dev/null; then
    pass "judgment_class_excluded: opus-arm candidate unclaimed + surfaced to founder"
  else
    fail "judgment_class_excluded: opus-arm candidate not properly unclaimed/surfaced"
  fi
}

test_empty_outcome_bounded() {
  local repo state
  read -r repo state < <(_new_fixture)
  _write_tasks "$repo" '- id: T-empty
  lane: action
  status: pending
  priority: high
  title: a task that never actually changes anything
  created_at: "2026-01-01T00:00:00Z"
'
  LEADV2_PROJECT_ROOT="$repo" PROJECT_ROOT="$repo" bash -c "source '$TASKS_LIB'; leadv2_tasks_claim T-empty --by tester" >/dev/null 2>&1
  LEADV2_PROJECT_ROOT="$repo" PROJECT_ROOT="$repo" LEADV2_STATE_ROOT="${state}/docs/leadv2" \
    LEADV2_JOURNAL_BIN=/bin/true LEADV2_OUTCOME_LEDGER_BIN=/nonexistent \
    bash "$PUMP_SH" reap T-empty >/dev/null 2>&1
  local status1
  status1="$(LEADV2_PROJECT_ROOT="$repo" PROJECT_ROOT="$repo" bash -c "source '$TASKS_LIB'; leadv2_tasks_by_id T-empty" 2>/dev/null | grep -E '^[[:space:]]*(status|lane):')"
  LEADV2_PROJECT_ROOT="$repo" PROJECT_ROOT="$repo" bash -c "source '$TASKS_LIB'; leadv2_tasks_claim T-empty --by tester" >/dev/null 2>&1
  LEADV2_PROJECT_ROOT="$repo" PROJECT_ROOT="$repo" LEADV2_STATE_ROOT="${state}/docs/leadv2" \
    LEADV2_JOURNAL_BIN=/bin/true LEADV2_OUTCOME_LEDGER_BIN=/nonexistent \
    bash "$PUMP_SH" reap T-empty >/dev/null 2>&1
  local lane2
  lane2="$(LEADV2_PROJECT_ROOT="$repo" PROJECT_ROOT="$repo" bash -c "source '$TASKS_LIB'; leadv2_tasks_by_id T-empty" 2>/dev/null | grep -E '^[[:space:]]*lane:' | awk '{print $2}')"
  if grep -q "status: pending" <<<"$status1" && [[ "$lane2" == "human-needed" ]]; then
    pass "empty_outcome_bounded: 1st empty -> requeued, 2nd consecutive -> parked (never spins forever)"
  else
    fail "empty_outcome_bounded: status1='$status1' lane2='$lane2'"
  fi
}

test_auto_dispatch() {
  local repo state stub rcfile logfile
  read -r repo state < <(_new_fixture)
  _write_tasks "$repo" '- id: T1
  lane: action
  status: pending
  priority: high
  title: fix the thing
  created_at: "2026-01-01T00:00:00Z"
'
  read -r stub rcfile logfile < <(_make_dispatch_stub "$state")
  echo 0 >"$rcfile"
  DISPATCH_STUB="$stub" _run_pump_x "$repo" "$state" check >/dev/null 2>&1
  if grep -q "fix the thing" "$logfile" 2>/dev/null; then
    pass "auto_dispatch: queued task dispatched with no human step"
  else
    fail "auto_dispatch: expected dispatch call, log=$(cat "$logfile" 2>/dev/null)"
  fi
}

# Internal wrapper that resolves the default quota/liveness stubs once and
# honours caller-exported overrides + DISPATCH_STUB.
_run_pump_x() {
  local repo="$1" state="$2"; shift 2
  local qbin lbin
  qbin="${LEADV2_BACKLOG_PUMP_QUOTA_BIN:-$(_make_quota_bin "$REAL_QUOTA_FIXTURE")}"
  if [[ -n "${LEADV2_BACKLOG_PUMP_LIVENESS_BIN:-}" ]]; then
    lbin="$LEADV2_BACKLOG_PUMP_LIVENESS_BIN"
  else
    local _ej="$(_mktmp)/empty.json"; printf '%s' "$EMPTY_LIVENESS" >"$_ej"; lbin="$(_make_liveness_bin "$_ej")"
  fi
  LEADV2_PROJECT_ROOT="$repo" PROJECT_ROOT="$repo" LEADV2_STATE_ROOT="${state}/docs/leadv2" \
  CLAUDE_PROJECT_DIR="$repo" \
  LEADV2_BACKLOG_PUMP="${LEADV2_BACKLOG_PUMP:-1}" \
  LEADV2_BACKLOG_PUMP_MAX="${LEADV2_BACKLOG_PUMP_MAX:-6}" \
  LEADV2_BACKLOG_PUMP_LIVENESS_CACHE_S="${LEADV2_BACKLOG_PUMP_LIVENESS_CACHE_S:-0}" \
  LEADV2_BACKLOG_PUMP_DISPATCH_BIN="${DISPATCH_STUB:-/bin/false}" \
  LEADV2_BACKLOG_PUMP_QUOTA_BIN="$qbin" \
  LEADV2_BACKLOG_PUMP_LIVENESS_BIN="$lbin" \
  LEADV2_JOURNAL_BIN="${LEADV2_JOURNAL_BIN:-/bin/true}" \
  LEADV2_JUDGE_DISABLE="${LEADV2_JUDGE_DISABLE:-1}" \
  bash "$PUMP_SH" "$@"
}

log "=== BACKLOG-PUMP-01 + C-1 test suite ==="
test_shape_gate_pass_floor10
test_shape_gate_pass_floor30
test_shape_gate_refuse_scaled
test_shape_gate_failopen
test_shape_gate_codex_limit_reached
test_count_lane_from_liveness
test_count_no_double_after_join
test_count_ignores_child_lanes
test_count_sweeps_stale_reservation
test_ceiling_refuses_7th
test_control_ceiling_mutation_caught
test_floor_dispatches_then_refuses
test_refusal_dedupe_collapses
test_starved_not_refused_below_floor
test_kill_switch_off
test_tree_mid_conflict
test_tree_state_probe_failure
test_duplicate_signature_refused
test_judgment_class_excluded
test_empty_outcome_bounded
test_auto_dispatch

log ""
log "=== Results: ${PASS} passed, ${FAIL} failed ==="
if [[ "$FAIL" -gt 0 ]]; then
  for e in "${ERRORS[@]}"; do log "$e"; done
  exit 1
fi
exit 0
