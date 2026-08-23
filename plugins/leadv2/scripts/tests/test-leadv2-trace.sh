#!/usr/bin/env bash
# tests/test-leadv2-trace.sh — Mission B round 2: writer schema, concurrency,
# OFF-path cost, reader arithmetic, and the two defects found in the round-2
# architect prepass (docs/handoff/dispatch-dfbbd78d).
#
# Sandbox: every group gets its own mktemp -d and its own LEADV2_STATE_ROOT.
# The trace writer always resolves its sink via `leadv2-state-path.sh
# --no-link traces`, and --no-link never triggers the real-checkout abort
# guard (state-path.sh:185, NO_LINK -eq 0 required) — so LEADV2_STATE_ROOT is
# a safe sandbox lever here with no extra guard-dodging needed. No group
# writes under docs/leadv2 or touches HOME.
#
# Run: bash plugins/leadv2/scripts/tests/test-leadv2-trace.sh

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LIB="${SCRIPT_DIR}/lib/leadv2-trace.sh"
REPORT="${SCRIPT_DIR}/leadv2-trace-report.sh"
STATE_PATH_BIN="${SCRIPT_DIR}/leadv2-state-path.sh"
FIXTURES="${SCRIPT_DIR}/tests/fixtures/trace"

PASS=0
FAIL=0
log()  { printf -- '[TEST] %s\n' "$*"; }
pass() { PASS=$((PASS + 1)); log "PASS: $1"; }
fail() { FAIL=$((FAIL + 1)); log "FAIL: $1"; }

TMPROOT="$(mktemp -d "${TMPDIR:-/tmp}/lv2-trace-test.XXXXXX")"
trap 'rm -rf "$TMPROOT"' EXIT

# ─────────────────────────────────────────────────────────────────────────
# Group 1 — writer schema and monotonicity
# ─────────────────────────────────────────────────────────────────────────
group1() {
  local sbx="$TMPROOT/g1"
  mkdir -p "$sbx"

  # 1.1 schema + required keys
  (
    export LEADV2_STATE_ROOT="$sbx/schema"
    export LEADV2_TRACE_ID="t-schema"
    export LEADV2_STATE_PATH_BIN="$STATE_PATH_BIN"
    # shellcheck source=../lib/leadv2-trace.sh
    source "$LIB"
    lv2_trace_begin s1
    lv2_trace_end 0
  )
  local sink="$sbx/schema/traces/t-schema.ndjson"
  if [[ -f "$sink" && "$(wc -l < "$sink" | tr -d ' ')" == "1" ]]; then
    pass "1.1 exactly one record written"
  else
    fail "1.1 exactly one record written (sink=$sink)"
  fi
  if python3 - "$sink" <<'PY'
import json, sys
rec = json.loads(open(sys.argv[1]).readline())
required = ["trace_id","span","script","pid","ppid","t_start_ns","t_end_ns",
            "duration_ms","exit_code","child_exec_count"]
missing = [k for k in required if k not in rec]
sys.exit(1 if missing else 0)
PY
  then pass "1.1 all required keys present"; else fail "1.1 all required keys present"; fi
  if python3 - "$sink" <<'PY'
import json, sys
rec = json.loads(open(sys.argv[1]).readline())
sys.exit(0 if ("child_exec_count" in rec and rec["child_exec_count"] is None) else 1)
PY
  then pass "1.1 child_exec_count present and null (honest not-measured)"; else fail "1.1 child_exec_count present and null"; fi

  # 1.2 exit_code round-trip
  local sink2="$sbx/schema/traces/t-schema.ndjson"
  : > "$sink2"
  (
    export LEADV2_STATE_ROOT="$sbx/schema"
    export LEADV2_TRACE_ID="t-schema"
    export LEADV2_STATE_PATH_BIN="$STATE_PATH_BIN"
    source "$LIB"
    lv2_trace_begin s1
    lv2_trace_end 7
  )
  if grep -q '"exit_code":7' "$sink2"; then pass "1.2 exit_code round-trips non-zero"; else fail "1.2 exit_code round-trips non-zero"; fi

  # 1.3 nesting / parent_span
  : > "$sink2"
  (
    export LEADV2_STATE_ROOT="$sbx/schema"
    export LEADV2_TRACE_ID="t-schema"
    export LEADV2_STATE_PATH_BIN="$STATE_PATH_BIN"
    source "$LIB"
    lv2_trace_begin a
    lv2_trace_begin b
    lv2_trace_end 0
    lv2_trace_end 0
  )
  if [[ "$(wc -l < "$sink2" | tr -d ' ')" == "2" ]] \
     && grep -q '"span":"b".*"parent_span":"a"' "$sink2" \
     && grep -q '"span":"a".*"parent_span":null' "$sink2"; then
    pass "1.3 nesting: inner has parent_span, outer does not"
  else
    fail "1.3 nesting: inner has parent_span, outer does not"
  fi

  # 1.4 monotonicity under a stubbed (backwards) wall clock
  local fakebin="$sbx/fakebin"
  mkdir -p "$fakebin"
  cat > "$fakebin/date" <<'SH'
#!/usr/bin/env bash
if [[ "$*" == *"+%FT%TZ"* ]]; then echo "2020-01-01T00:00:00Z"; exit 0; fi
if [[ "$*" == *"+%Y%m%d"* ]]; then echo "20200101"; exit 0; fi
exec /bin/date "$@"
SH
  chmod +x "$fakebin/date"
  local sink3="$sbx/schema/traces/t-mono.ndjson"
  (
    export PATH="$fakebin:$PATH"
    export LEADV2_STATE_ROOT="$sbx/schema"
    export LEADV2_TRACE_ID="t-mono"
    export LEADV2_STATE_PATH_BIN="$STATE_PATH_BIN"
    source "$LIB"
    lv2_trace_begin span1
    sleep 0.05
    lv2_trace_end 0
  )
  if python3 - "$sink3" <<'PY'
import json, sys
rec = json.loads(open(sys.argv[1]).readline())
ok = (rec["duration_ms"] > 0 and rec["t_end_ns"] > rec["t_start_ns"]
      and rec["clock_source"] in ("monotonic_perl", "monotonic_python")
      and rec["wall_iso"] == "2020-01-01T00:00:00Z")
sys.exit(0 if ok else 1)
PY
  then pass "1.4 monotonic timing survives a backwards wall clock; wall_iso is cosmetic only"; else fail "1.4 monotonicity under backwards wall clock"; fi

  # 1.5 id boundary cases
  local ok64="a$(printf 'x%.0s' $(seq 1 63))" # 64 chars
  local sink64="$sbx/schema/traces/${ok64}.ndjson"
  (
    export LEADV2_STATE_ROOT="$sbx/schema"
    export LEADV2_TRACE_ID="$ok64"
    export LEADV2_STATE_PATH_BIN="$STATE_PATH_BIN"
    source "$LIB"
    lv2_trace_begin s
    lv2_trace_end 0
  )
  [[ -f "$sink64" ]] && pass "1.5 64-char id accepted" || fail "1.5 64-char id accepted"

  local bad65="a$(printf 'x%.0s' $(seq 1 64))" # 65 chars
  local out65
  out65="$( (
    export LEADV2_STATE_ROOT="$sbx/schema"
    export LEADV2_TRACE_ID="$bad65"
    export LEADV2_STATE_PATH_BIN="$STATE_PATH_BIN"
    source "$LIB"
    lv2_trace_begin s
    lv2_trace_end 0
  ) 2>&1 )"
  if [[ ! -f "$sbx/schema/traces/${bad65}.ndjson" ]] && printf '%s' "$out65" | grep -q '\[trace\] disabled'; then
    pass "1.5 65-char id disables trace with a diagnostic"
  else
    fail "1.5 65-char id disables trace with a diagnostic"
  fi

  (
    export LEADV2_STATE_ROOT="$sbx/schema"
    export LEADV2_TRACE_ID="../../evil"
    export LEADV2_STATE_PATH_BIN="$STATE_PATH_BIN"
    source "$LIB"
    lv2_trace_begin s
    lv2_trace_end 0
  ) >/dev/null 2>&1
  if [[ -z "$(find "$sbx/schema" -iname '*evil*' 2>/dev/null)" ]]; then
    pass "1.5 path-traversal id writes nothing named after it (charset whitelist holds)"
  else
    fail "1.5 path-traversal id writes nothing named after it"
  fi
}

# ─────────────────────────────────────────────────────────────────────────
# Group 2 — append under concurrency
# ─────────────────────────────────────────────────────────────────────────
group2() {
  local sbx="$TMPROOT/g2"
  mkdir -p "$sbx"
  local n=24 per=25
  local pids=()
  for i in $(seq 1 "$n"); do
    (
      export LEADV2_STATE_ROOT="$sbx"
      export LEADV2_TRACE_ID="t-concurrent"
      export LEADV2_STATE_PATH_BIN="$STATE_PATH_BIN"
      source "$LIB"
      for j in $(seq 1 "$per"); do
        lv2_trace_begin "w${i}-${j}"
        # shellcheck disable=SC2181
        python3 -c "import time,random;time.sleep(random.random()*0.005)" 2>/dev/null || true
        lv2_trace_end 0
      done
    ) &
    pids+=("$!")
  done
  for p in "${pids[@]}"; do wait "$p"; done

  local sink="$sbx/traces/t-concurrent.ndjson"
  local expect=$((n * per))
  local got
  got="$(wc -l < "$sink" 2>/dev/null | tr -d ' ')"
  [[ "$got" == "$expect" ]] && pass "2 line count == ${expect}" || fail "2 line count == ${expect} (got ${got:-0})"

  if python3 - "$sink" <<'PY'
import json, sys
bad = 0
for i, line in enumerate(open(sys.argv[1])):
    line = line.rstrip("\n")
    if not line:
        continue
    try:
        json.loads(line)
    except Exception:
        bad += 1
        print(f"line {i}: {line[:80]}", file=sys.stderr)
sys.exit(1 if bad else 0)
PY
  then pass "2 every line parses standalone as JSON"; else fail "2 every line parses standalone as JSON"; fi

  if grep -qE '\}\{|"trace_id".*"trace_id"' "$sink" 2>/dev/null; then
    fail "2 no interleaving signature (}{  or duplicate trace_id in one line)"
  else
    pass "2 no interleaving signature (}{  or duplicate trace_id in one line)"
  fi

  if python3 - "$sink" "$n" "$per" <<'PY'
import json, sys
n, per = int(sys.argv[2]), int(sys.argv[3])
seen = set()
dup = missing = 0
for line in open(sys.argv[1]):
    line = line.strip()
    if not line:
        continue
    rec = json.loads(line)
    key = rec["span"]
    if key in seen:
        dup += 1
    seen.add(key)
expected = {f"w{i}-{j}" for i in range(1, n + 1) for j in range(1, per + 1)}
missing = len(expected - seen)
extra = len(seen - expected)
sys.exit(0 if (dup == 0 and missing == 0 and extra == 0) else 1)
PY
  then pass "2 multiset of (pid,span_index) pairs is exactly the expected 600 — none lost, none duplicated"
  else fail "2 multiset of (pid,span_index) pairs is exactly the expected 600"; fi
}

# ─────────────────────────────────────────────────────────────────────────
# Group 3 — OFF costs nothing
# ─────────────────────────────────────────────────────────────────────────
group3() {
  local sbx="$TMPROOT/g3"
  mkdir -p "$sbx"

  # 3.1 behavioural: dispatch resolve-only path with LEADV2_TRACE unset
  local DC="${SCRIPT_DIR}/leadv2-dispatch-code.sh"
  if [[ -x "$DC" ]]; then
    (
      unset LEADV2_TRACE
      export LEADV2_STATE_ROOT="$sbx/behav"
      export LEADV2_STATE_PATH_BIN="$STATE_PATH_BIN"
      export LEADV2_DISPATCH_SPAWN=0
      bash "$DC" --help >/dev/null 2>&1 || true
    )
    local ndjson_count trace_dir_count
    ndjson_count="$(find "$sbx/behav" -name '*.ndjson' 2>/dev/null | wc -l | tr -d ' ')"
    trace_dir_count="$(find "$sbx/behav" -type d -name traces 2>/dev/null | wc -l | tr -d ' ')"
    log "3.1 find(*.ndjson)='' find(traces dir)='' — ndjson=${ndjson_count} traces_dir=${trace_dir_count}"
    if [[ "$ndjson_count" == "0" && "$trace_dir_count" == "0" ]]; then
      pass "3.1 OFF path creates zero ndjson files and never creates the traces dir"
    else
      fail "3.1 OFF path creates zero ndjson files and never creates the traces dir"
    fi
  else
    fail "3.1 leadv2-dispatch-code.sh not found/executable at $DC"
  fi

  # 3.2 static: else-arm of the load stanza is the ':' builtin at all nine sites
  local -a SITES=(
    "leadv2-dispatch-code.sh" "leadv2-review-run.sh" "leadv2-router.sh"
    "leadv2-lanes-snapshot.sh" "leadv2-backlog-pump.sh"
    "leadv2-status-collector.sh" "codex-task.sh" "glm-coder.sh" "kimi-coder.sh"
  )
  local needle='lv2_trace_begin() { :; }; lv2_trace_end() { :; }; lv2_trace_arm_exit() { :; }'
  local static_ok=1
  local hits=0
  for f in "${SITES[@]}"; do
    local path="${SCRIPT_DIR}/${f}"
    if grep -qF "$needle" "$path" 2>/dev/null; then
      hits=$((hits + 1))
    else
      static_ok=0
      log "3.2 missing/different else-arm in $f"
    fi
  done
  if [[ "$static_ok" == "1" && "$hits" == "9" ]]; then
    pass "3.2 all nine load stanzas' OFF else-arm is the ':' builtin (no subshell, no exec, no file open)"
  else
    fail "3.2 all nine load stanzas' OFF else-arm is the ':' builtin (hits=${hits}/9)"
  fi

  # 3.3 dynamic exec count via PATH-shim wrappers around perl/python3/awk/basename/date
  local execlog="$sbx/execs.log"
  local wrapbin="$sbx/wrapbin"
  mkdir -p "$wrapbin"
  : > "$execlog"
  for tool in perl python3 awk basename date; do
    real="$(command -v "$tool")"
    cat > "$wrapbin/$tool" <<SH
#!/usr/bin/env bash
printf '%s\n' "$tool" >> "$execlog"
exec "$real" "\$@"
SH
    chmod +x "$wrapbin/$tool"
  done

  : > "$execlog"
  (
    trap - EXIT
    export PATH="$wrapbin:$PATH"
    unset LEADV2_TRACE
    export LEADV2_STATE_ROOT="$sbx/dyn-off"
    export LEADV2_TRACE_ID="t-dyn"
    export LEADV2_STATE_PATH_BIN="$STATE_PATH_BIN"
    if [[ "${LEADV2_TRACE:-0}" == "1" ]]; then . "$LIB"
    else lv2_trace_begin() { :; }; lv2_trace_end() { :; }; lv2_trace_arm_exit() { :; }; fi
    lv2_trace_arm_exit "lane"
    lv2_trace_begin "child"
    lv2_trace_end 0
  )
  local off_count
  off_count="$(wc -l < "$execlog" | tr -d ' ')"

  : > "$execlog"
  (
    trap - EXIT
    export PATH="$wrapbin:$PATH"
    export LEADV2_TRACE=1
    export LEADV2_STATE_ROOT="$sbx/dyn-on"
    export LEADV2_TRACE_ID="t-dyn"
    export LEADV2_STATE_PATH_BIN="$STATE_PATH_BIN"
    if [[ "${LEADV2_TRACE:-0}" == "1" ]]; then . "$LIB"
    else lv2_trace_begin() { :; }; lv2_trace_end() { :; }; lv2_trace_arm_exit() { :; }; fi
    lv2_trace_arm_exit "lane"
    lv2_trace_begin "child"
    lv2_trace_end 0
  )
  local on_count
  on_count="$(wc -l < "$execlog" | tr -d ' ')"

  log "3.3 OFF exec count=${off_count} ON exec count=${on_count}"
  if [[ "$off_count" == "0" ]]; then
    pass "3.3 OFF run makes zero exec calls through perl/python3/awk/basename/date"
  else
    fail "3.3 OFF run makes zero exec calls through perl/python3/awk/basename/date (got ${off_count})"
  fi
  if [[ "$on_count" -gt "$off_count" ]]; then
    pass "3.3 ON run's exec count is strictly greater than OFF's (${on_count} > ${off_count})"
  else
    fail "3.3 ON run's exec count is strictly greater than OFF's (on=${on_count} off=${off_count})"
  fi
}

# ─────────────────────────────────────────────────────────────────────────
# Group 4 — reader
# ─────────────────────────────────────────────────────────────────────────
group4() {
  local out

  out="$(bash "$REPORT" "$FIXTURES/single" 2>&1)"
  if printf '%s' "$out" | grep -E '^lane' | grep -q '(raw)'; then
    pass "4 single-sample fixture: p50/p95/max equal, marked (raw)"
  else
    fail "4 single-sample fixture: p50/p95/max equal, marked (raw) — got: $out"
  fi
  if printf '%s' "$out" | grep -E '^lane' | awk '{print ($2==1 && $3==$4 && $4==$5)}' | grep -q 1; then
    pass "4 single-sample fixture: count=1 and p50==p95==max"
  else
    fail "4 single-sample fixture: count=1 and p50==p95==max — got: $out"
  fi

  out="$(bash "$REPORT" "$FIXTURES/even" 2>&1)"
  if printf '%s' "$out" | grep -E '^step' | awk '{exit !($3==3 && $4==100)}'; then
    pass "4 even-sample fixture: p50_ms=3, p95_ms=100 (pinned percentile arithmetic)"
  else
    fail "4 even-sample fixture: p50_ms=3, p95_ms=100 — got: $out"
  fi

  out="$(bash "$REPORT" "$FIXTURES/lane-total" 2>&1)"
  if printf '%s' "$out" | grep -E '^t-lane' | awk '{exit !($2==1000 && $3==400 && $4==600)}'; then
    pass "4 lane-total fixture: lane_ms=1000 child_span_ms_sum=400 unattributed=600"
  else
    fail "4 lane-total fixture: lane_ms=1000 child_span_ms_sum=400 unattributed=600 — got: $out"
  fi

  out="$(bash "$REPORT" "$FIXTURES/malformed" 2>&1)"
  local rc_mal=$?
  if printf '%s' "$out" | grep -q 'malformed_lines: 1'; then
    pass "4 malformed fixture: malformed_lines=1 (empty line not counted)"
  else
    fail "4 malformed fixture: malformed_lines=1 — got: $out"
  fi
  [[ "$rc_mal" == "0" ]] && pass "4 malformed fixture: rc=0 (not fatal)" || fail "4 malformed fixture: rc=0"

  local missing_out
  missing_out="$(bash "$REPORT" "$TMPROOT/does-not-exist" 2>&1)"
  local rc_missing=$?
  [[ "$rc_missing" == "1" ]] && pass "4 nonexistent path: rc=1" || fail "4 nonexistent path: rc=1 (got ${rc_missing})"
  if printf '%s' "$missing_out" | grep -q 'no trace data found'; then
    pass "4 nonexistent path: prints 'no trace data found'"
  else
    fail "4 nonexistent path: prints 'no trace data found' — got: $missing_out"
  fi

  local emptydir="$TMPROOT/g4-empty"
  mkdir -p "$emptydir"
  bash "$REPORT" "$emptydir" >/dev/null 2>&1
  local rc_empty=$?
  [[ "$rc_empty" == "0" ]] && pass "4 empty dir: rc=0" || fail "4 empty dir: rc=0 (got ${rc_empty})"

  out="$(bash "$REPORT" "$FIXTURES/noisefloor" 2>&1)"
  if printf '%s' "$out" | grep -q 'noise floor'; then
    pass "4 noise-floor footer fires for a span whose p50 is below 10x instrument cost"
  else
    fail "4 noise-floor footer fires (got: $out)"
  fi

  out="$(bash "$REPORT" "$FIXTURES/single" --json 2>&1)"
  if python3 -c "import json,sys; d=json.loads(sys.argv[1]); assert 'spans' in d and 'traces' in d and 'malformed_lines' in d" "$out" 2>/dev/null; then
    pass "4 --json mode: output parses and carries spans/traces/malformed_lines"
  else
    fail "4 --json mode: output parses and carries spans/traces/malformed_lines"
  fi
}

# ─────────────────────────────────────────────────────────────────────────
# Group 5 — the two defects, red-first
# ─────────────────────────────────────────────────────────────────────────
group5() {
  local sbx="$TMPROOT/g5"
  mkdir -p "$sbx"

  # 5a — Defect B: a clock failure at exit must not hang the host script
  local hangbin="$sbx/hangbin"
  mkdir -p "$hangbin"
  cat > "$hangbin/perl" <<'SH'
#!/usr/bin/env bash
exit 1
SH
  cat > "$hangbin/python3" <<'SH'
#!/usr/bin/env bash
exit 1
SH
  chmod +x "$hangbin/perl" "$hangbin/python3"

  local hostscript="$sbx/host.sh"
  cat > "$hostscript" <<SH
#!/usr/bin/env bash
export LEADV2_STATE_ROOT="$sbx/state"
export LEADV2_TRACE_ID="t-hang"
export LEADV2_STATE_PATH_BIN="$STATE_PATH_BIN"
source "$LIB"
lv2_trace_arm_exit "hang"
export PATH="$hangbin:\$PATH"
exit 0
SH
  timeout 10 bash "$hostscript" >"$sbx/hang.out" 2>&1
  local rc_hang=$?
  log "5a run rc=${rc_hang} (124 == timed out / hung; anything else == returned to the prompt)"
  if [[ "$rc_hang" != "124" ]]; then
    pass "5a a script that armed the trace and then lost its clock returns to the shell prompt instead of hanging"
  else
    fail "5a a script that armed the trace and then lost its clock returns to the shell prompt instead of hanging (timed out, rc=124)"
  fi

  # 5b — EXIT-trap ordering lint: no `trap ... EXIT` after the arm_exit call
  local -a ARM_SITES=(
    "leadv2-dispatch-code.sh" "leadv2-review-run.sh" "leadv2-router.sh"
    "leadv2-lanes-snapshot.sh" "leadv2-status-collector.sh"
  )
  local lint_ok=1
  for f in "${ARM_SITES[@]}"; do
    local path="${SCRIPT_DIR}/${f}"
    local arm_line
    arm_line="$(grep -n 'lv2_trace_arm_exit "' "$path" | head -1 | cut -d: -f1)"
    if [[ -z "$arm_line" ]]; then
      lint_ok=0
      log "5b $f: no lv2_trace_arm_exit call found"
      continue
    fi
    local later
    later="$(awk -F: -v n="$arm_line" '$1>n' <(grep -n "trap .* EXIT" "$path"))"
    if [[ -n "$later" ]]; then
      lint_ok=0
      log "5b $f: trap ... EXIT installed after arm_exit line ${arm_line}: ${later}"
    fi
  done
  if [[ "$lint_ok" == "1" ]]; then
    pass "5b no host installs its own EXIT trap after lv2_trace_arm_exit (single-trap-slot hazard)"
  else
    fail "5b no host installs its own EXIT trap after lv2_trace_arm_exit"
  fi

  # 5c — Defect A: the four SCRIPT_DIR-less seams must be able to write
  local SC="${SCRIPT_DIR}/leadv2-status-collector.sh"
  local elsewhere="$sbx/elsewhere"
  mkdir -p "$elsewhere"
  (
    cd "$elsewhere" || exit 1
    export LEADV2_TRACE=1
    export LEADV2_STATE_ROOT="$sbx/defect-a"
    export LEADV2_TRACE_ID="t-defect-a"
    unset LEADV2_STATE_PATH_BIN
    bash "$SC" >/dev/null 2>&1 || true
  )
  local recfile="$sbx/defect-a/traces/t-defect-a.ndjson"
  if [[ -f "$recfile" ]] && grep -q '"span":"status.collect"' "$recfile"; then
    pass "5c status.collect writes a record even when invoked from a CWD that is not the scripts dir"
  else
    fail "5c status.collect writes a record even when invoked from a foreign CWD (file=${recfile})"
  fi
}

group1
group2
group3
group4
group5

log "----"
log "PASS=${PASS} FAIL=${FAIL}"
[[ "$FAIL" -eq 0 ]]
exit $?
