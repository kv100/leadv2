#!/usr/bin/env bash
# ARBITER-SCORING-DESIGN-01 step 2 (docs/handoff/F1-ARBITER-SCORING-20260907/
# design.md §5.1, §7.1, §7.2): task-judge complexity_basis + dispatcher
# complexity_source / declared-class floor. Still off by default --
# FIT_MODE=off throughout; what is pinned here is PROVENANCE, not picks.
#
# Part A exercises the REAL leadv2-task-judge.sh through its test seams
# (LEADV2_JUDGE_DISABLE / stub claude bin / journal stub / cache dir):
#   - fallback estimate records which branch decided (class_hint vs
#     line_count), judge branch stamps 'judge'
#   - the journal line carries complexity_basis=<basis|none>
#   - a cached estimate written BEFORE the field existed still validates
#     (§7.2: never add the key to REQUIRED -- the old est[field] read made
#     every ALLOWED key de-facto REQUIRED and would have failed every cache)
#   - an off-vocabulary basis in a cached estimate is rejected -> fallback
#
# Part B drives the REAL leadv2-dispatch-code.sh --no-spawn with a stub
# task-judge and asserts the §5.1 degradation table on the route_resolved
# journal line (the arbiter fit token rides along via _arb_util):
#   judge estimate                    -> complexity_source=judge   conf=0.9
#   fallback + line_count             -> complexity_source=heuristic conf=0.4
#   fallback + class_hint             -> complexity_source=flag     conf=0.7
#   --task-class heavy + simple judge -> floor simple->complex, source=flag
#   --task-class light + complex judge-> NEVER lowered, no floor line
#   old-caller estimate (no fields)   -> complexity_source=unknown  conf=0.0
#
# Part C is the §9.3 row-4 negative control: a THROWAWAY mutated copy with
# the complexity_source descriptor key stripped must show unknown on every
# run (execution-proven by the token itself), while the real file shows none.
#
# run-all-triggers: leadv2-dispatch-code leadv2-task-judge
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_ROOT="$(cd "${SCRIPT_DIR}/../scripts" && pwd)"
JUDGE_BIN="${SCRIPTS_ROOT}/leadv2-task-judge.sh"
DISPATCH_BIN="${SCRIPTS_ROOT}/leadv2-dispatch-code.sh"
ROUTING="${SCRIPTS_ROOT}/../config/leadv2-routing.yaml"

PASS=0; FAIL=0
pass() { printf 'PASS: %s\n' "$1"; PASS=$((PASS + 1)); }
fail() { printf 'FAIL: %s -- %s\n' "$1" "${2:-}"; FAIL=$((FAIL + 1)); }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/cx-source.XXXXXX")"
trap '[[ "${CXPROV_KEEP_LOGS:-0}" == "1" ]] || rm -rf "$TMP"' EXIT

bash -n "$JUDGE_BIN"   || { fail "bash syntax: judge";   exit 1; }
bash -n "$DISPATCH_BIN" || { fail "bash syntax: dispatch"; exit 1; }
pass "bash syntax: judge + dispatch"

field() { python3 -c 'import json,sys; print(json.load(sys.stdin).get(sys.argv[1],""))' "$1"; }

# ── Part A: real task-judge ───────────────────────────────────────────────
printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$4" >> "%s/journal-capture.txt"\n' "$TMP" > "$TMP/jstub.sh"
chmod +x "$TMP/jstub.sh"
cat > "$TMP/claude.sh" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' '{"is_error":false,"result":"```json\n{\"complexity\":\"simple\",\"subsystems_touched\":2,\"needs_live_verification\":false,\"risk_class\":\"none\",\"duration_class\":\"short\",\"work_kind\":\"build\"}\n```","type":"result"}'
EOF
chmod +x "$TMP/claude.sh"

run_judge() { # <env-assignments-callback-free: caller pre-exports> <mission> <args...>
  local mf="$1"; shift
  bash "$JUDGE_BIN" --mission-file "$mf" "$@"
}

# A1 fallback + class hint -> class_hint basis
printf 'fix the bug\n' > "$TMP/m1"
out="$(LEADV2_JUDGE_DISABLE=1 LEADV2_JUDGE_CACHE_DIR="$TMP/c1" LEADV2_JUDGE_JOURNAL_BIN="$TMP/jstub.sh" \
  run_judge "$TMP/m1" --task-id dispatch-deadbeefa1 --class Standard)"
[[ "$(field complexity_basis <<<"$out")" == "class_hint" && "$(field complexity <<<"$out")" == "standard" ]] \
  && pass "A1 fallback --class Standard -> complexity_basis=class_hint" \
  || fail "A1 fallback --class Standard" "got: $out"

# A2 fallback, line-count branches (short / >300 lines)
printf 'one line\n' > "$TMP/m2"
out="$(LEADV2_JUDGE_DISABLE=1 LEADV2_JUDGE_CACHE_DIR="$TMP/c2" LEADV2_JUDGE_JOURNAL_BIN="$TMP/jstub.sh" \
  run_judge "$TMP/m2" --task-id dispatch-deadbeefa2)"
[[ "$(field complexity_basis <<<"$out")" == "line_count" && "$(field complexity <<<"$out")" == "trivial" ]] \
  && pass "A2a fallback no class, <=30 lines -> line_count/trivial" \
  || fail "A2a fallback line_count trivial" "got: $out"
for i in $(seq 1 320); do printf 'line %d of a long mission\n' "$i"; done > "$TMP/m3"
out="$(LEADV2_JUDGE_DISABLE=1 LEADV2_JUDGE_CACHE_DIR="$TMP/c3" LEADV2_JUDGE_JOURNAL_BIN="$TMP/jstub.sh" \
  run_judge "$TMP/m3" --task-id dispatch-deadbeefa3)"
[[ "$(field complexity_basis <<<"$out")" == "line_count" && "$(field complexity <<<"$out")" == "complex" ]] \
  && pass "A2b fallback no class, >300 lines -> line_count/complex" \
  || fail "A2b fallback line_count complex" "got: $out"

# A3 judge branch stamps basis=judge (wrapper's knowledge, never the model's)
printf 'probe mission\n' > "$TMP/m4"
out="$(LEADV2_JUDGE_CLAUDE_BIN="$TMP/claude.sh" LEADV2_JUDGE_CACHE_DIR="$TMP/c4" \
  run_judge "$TMP/m4" --task-id dispatch-deadbeefa4)"
[[ "$(field estimate_source <<<"$out")" == "judge" && "$(field complexity_basis <<<"$out")" == "judge" ]] \
  && pass "A3 judge branch -> complexity_basis=judge" \
  || fail "A3 judge branch" "got: $out"

# A4 journal line carries the token on every branch
if grep -q 'complexity_basis=class_hint' "$TMP/journal-capture.txt" \
   && grep -q 'complexity_basis=line_count' "$TMP/journal-capture.txt"; then
  pass "A4 journal route_v2_estimate lines carry complexity_basis=<basis>"
else
  fail "A4 journal token" "$(cat "$TMP/journal-capture.txt" 2>/dev/null)"
fi

# A5 cached estimate written BEFORE the field existed still validates
printf 'cache probe\n' > "$TMP/m5"
LEADV2_JUDGE_CLAUDE_BIN="$TMP/claude.sh" LEADV2_JUDGE_CACHE_DIR="$TMP/c5" \
  run_judge "$TMP/m5" --task-id dispatch-deadbeefa5 >/dev/null
CF="$(ls "$TMP/c5"/*.json 2>/dev/null | head -1)"
[[ -n "$CF" ]] || { fail "A5 cache seed" "no cache file written"; }
if [[ -n "$CF" ]]; then
  python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); d.pop("complexity_basis",None); json.dump(d,open(sys.argv[1],"w"))' "$CF"
  out="$(LEADV2_JUDGE_CLAUDE_BIN="$TMP/claude.sh" LEADV2_JUDGE_CACHE_DIR="$TMP/c5" LEADV2_JUDGE_JOURNAL_BIN="$TMP/jstub.sh" \
    run_judge "$TMP/m5" --task-id dispatch-deadbeefa5)"
  if [[ "$(field complexity <<<"$out")" == "simple" ]] && ! grep -q complexity_basis <<<"$out"; then
    grep -q 'complexity_basis=none' "$TMP/journal-capture.txt" \
      && pass "A5 old cached estimate validates (cache_hit) + journals complexity_basis=none" \
      || fail "A5 journal 'none' token missing" "$(tail -1 "$TMP/journal-capture.txt")"
  else
    fail "A5 old cached estimate rejected" "got: $out"
  fi
fi

# A6 off-vocabulary basis in a cached estimate is rejected -> re-derived
printf 'offvocab probe\n' > "$TMP/m6"
out="$(LEADV2_JUDGE_DISABLE=1 LEADV2_JUDGE_CACHE_DIR="$TMP/c6" run_judge "$TMP/m6" --task-id dispatch-deadbeefa6)"
SIG8="$(field estimate_id <<<"$out")"
mkdir -p "$TMP/c6bad"
printf '%s' '{"estimate_v":1,"complexity":"simple","subsystems_touched":2,"needs_live_verification":false,"risk_class":"none","duration_class":"short","work_kind":"build","estimate_id":"'"${SIG8}"'","estimate_source":"judge","flag_source":"judge","complexity_basis":"bogus"}' > "$TMP/c6bad/${SIG8}.json"
out="$(LEADV2_JUDGE_DISABLE=1 LEADV2_JUDGE_CACHE_DIR="$TMP/c6bad" run_judge "$TMP/m6" --task-id dispatch-deadbeefa6)"
[[ "$(field complexity_basis <<<"$out")" == "line_count" ]] \
  && pass "A6 off-vocab cached basis rejected -> fallback re-derives" \
  || fail "A6 off-vocab basis" "got: $out"

# ── Part B: real dispatch-code, stub task-judge, §5.1 table ───────────────
quota_json() {
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
printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$ROUTE_TEST_QUOTA"\n' > "$TMP/live.sh"
printf '#!/usr/bin/env bash\nexit 0\n' > "$TMP/free.sh"
chmod +x "$TMP/live.sh" "$TMP/free.sh"
HEALTHY_QUOTA="$(quota_json 20 20 20)"

cat > "$TMP/task-judge.sh" <<'EOF'
#!/usr/bin/env bash
printf '%s' "$CX_PROBE_ESTIMATE"
EOF
chmod +x "$TMP/task-judge.sh"
printf '#!/usr/bin/env bash\nprintf "PID=%%s LABEL=t SESSION_ID=t\\n" "$$"\n' > "$TMP/worker.sh"
chmod +x "$TMP/worker.sh"

setup_repo() { # <dir> <suffix>
  local repo="$1"
  mkdir -p "$repo/.claude/ref" "$repo/docs/leadv2" "$repo/docs/leadv2/tasks"
  git -C "$repo" init -q -b main
  git -C "$repo" config user.email t@e.com; git -C "$repo" config user.name t
  : > "$repo/seed"; git -C "$repo" add seed; git -C "$repo" commit -qm seed
  cp "$ROUTING" "$repo/.claude/ref/leadv2-routing.yaml"
}

est() { # <id> <source> <complexity> <basis> -> estimate JSON
  printf '{"estimate_v":1,"complexity":"%s","subsystems_touched":1,"needs_live_verification":false,"risk_class":"none","duration_class":"short","work_kind":"build","estimate_id":"%s","estimate_source":"%s","flag_source":"%s"%s}' \
    "$3" "$1" "$2" "$([[ "$2" == judge ]] && printf judge || printf title)" \
    "$([[ -n "${4:-}" ]] && printf ',"complexity_basis":"%s"' "$4")"
}

run_dispatch() { # <bin> <repo> <suffix> -> dispatch stdout on stdout
  local bin="$1" repo="$2" suffix="$3"; shift 3
  (cd "$repo" && LEADV2_STATE_ROOT="$TMP/state-root-$suffix" \
    LEADV2_ROUTE_ARBITER_QUOTA_LIVE="$TMP/live.sh" \
    LEADV2_ROUTE_ARBITER_FREEPOOL_GATE="$TMP/free.sh" \
    LEADV2_ROUTE_ARBITER_STATE_FILE="$TMP/state-dispatch-$suffix" \
    ROUTE_TEST_QUOTA="$HEALTHY_QUOTA" \
    CLAUDE_PROJECT_ROOT="$repo" LEADV2_PROJECT_ROOT="$repo" \
    LEADV2_DISPATCH_CACHE_DIR="$TMP/cache-$suffix" \
    LEADV2_DISPATCH_E2E_GATE=0 LEADV2_DISPATCH_REVIEW_GATE=0 LEADV2_DISPATCH_ARCHITECT_GATE=0 \
    LEADV2_REQUIRE_PHASES=0 \
    LEADV2_ROUTER_V2=0 LEADV2_EXCLUDED_ARMS=__none__ LEADV2_LANE_SHAPE=off \
    LEADV2_BURN_GOVERNOR=0 LEADV2_ARM_EARLY_VERDICT_S=0 \
    LEADV2_TASK_JUDGE_BIN="$TMP/task-judge.sh" \
    LEADV2_DISPATCH_SUBSESSION_BIN="$TMP/worker.sh" \
    bash "$bin" "cx-source suite $suffix ${TMP}" \
      --kind code --no-spawn --writes src/x.py "$@" 2>&1)
}

b_case() { # <suffix> <estimate> <expected-source> <expected-conf> [args...] -> greps the journal
  local suffix="$1" estimate="$2" cxsrc="$3" conf="$4"; shift 4
  local repo="$TMP/repo-$suffix"
  setup_repo "$repo"
  CX_PROBE_ESTIMATE="$estimate" run_dispatch "$DISPATCH_BIN" "$repo" "$suffix" "$@" > "$TMP/out-$suffix.log"
  local line
  line="$(grep -rh 'route_resolved by=arbiter' "$TMP/state-root-$suffix" 2>/dev/null | tail -1)"
  if [[ -z "$line" ]]; then
    fail "B/$suffix" "no route_resolved line (log: $TMP/out-$suffix.log)"
    return 0
  fi
  if printf '%s' "$line" | grep -q " complexity_source=$cxsrc conf=$conf "; then
    pass "B/$suffix complexity_source=$cxsrc conf=$conf"
  else
    fail "B/$suffix complexity_source=$cxsrc conf=$conf" "$line"
  fi
}

# §5.1 row judge
b_case b1 "$(est p0001 judge simple judge)"              judge    0.9
# §5.1 row heuristic (the live-path positive control)
b_case b2 "$(est p0002 fallback trivial line_count)"     heuristic 0.4
# §5.1 row flag via fallback class_hint (the shape the live path produces)
b_case b3 "$(est p0003 fallback standard class_hint)"    flag     0.7
# §5.1 row flag via declared-class floor: --task-class heavy + judge simple
b_case b4 "$(est p0004 judge simple judge)"              flag     0.7 --task-class heavy
if grep -qrh 'complexity_floor_applied task=[0-9a-f]\{8\} from=simple to=complex source=flag by=flag' "$TMP/state-root-b4" 2>/dev/null; then
  pass "B/b4 floor line: from=simple to=complex source=flag by=flag"
else
  fail "B/b4 floor line" "$(grep -rh complexity_floor "$TMP/state-root-b4" 2>/dev/null)"
fi
# never-lowers: --task-class light + judge complex -> stays complex, no floor
b_case b5 "$(est p0005 judge complex judge)"             judge    0.9 --task-class light
if grep -qrh 'complexity_floor_applied' "$TMP/state-root-b5" 2>/dev/null; then
  fail "B/b5 never-lower" "floor fired on a complex estimate"
else
  if grep -qrh 'route_resolved by=arbiter' "$TMP/state-root-b5" 2>/dev/null \
     && grep -rh 'route_resolved by=arbiter' "$TMP/state-root-b5" | tail -1 | grep -q 'complexity=complex'; then
    pass "B/b5 never-lowers: complexity stays complex, no floor line"
  else
    fail "B/b5 complexity=complex not visible on route_resolved" "$(grep -rh 'route_resolved by=arbiter' "$TMP/state-root-b5" 2>/dev/null | tail -1)"
  fi
fi
# §5.1 row unknown: old-caller estimate without the fields -> cautious prior
b_case b6 "$(est p0006 fallback simple '')"              unknown  0.0

# ── Part C: §9.3 row 4 negative control (throwaway mutated copy) ──────────
MUT_PLUGIN_ROOT="$TMP/mutated-plugin"
mkdir -p "$MUT_PLUGIN_ROOT"
cp -R "$SCRIPTS_ROOT" "$MUT_PLUGIN_ROOT/scripts"
cp -R "${SCRIPTS_ROOT}/../config" "$MUT_PLUGIN_ROOT/config"
MUT_BIN="${MUT_PLUGIN_ROOT}/scripts/leadv2-dispatch-code.sh"
python3 - "$MUT_BIN" <<'PY'
import sys
path = sys.argv[1]
src = open(path).read()
anchor = ',"complexity_source":sys.argv[12]'
n = src.count(anchor)
if n != 1:
    sys.exit('mutation anchor %r found %d times (expected 1) -- zero-match/ambiguous, '
             'the control cannot run; re-anchor it, do not silence it' % (anchor, n))
open(path, 'w').write(src.replace(anchor, ''))
PY
if [[ $? -ne 0 ]]; then
  fail "C mutation anchor" "not found in production file"
else
  bash -n "$MUT_BIN" || fail "C mutated copy fails bash -n"
  MUT_UNKNOWN=0; MUT_LINES=0
  for i in 1 2 3; do
    repo="$TMP/repo-mut$i"; setup_repo "$repo"
    CX_PROBE_ESTIMATE="$(est "p100$i" fallback standard class_hint)" \
      run_dispatch "$MUT_BIN" "$repo" "mut$i" > "$TMP/out-mut$i.log"
    line="$(grep -rh 'route_resolved by=arbiter' "$TMP/state-root-mut$i" 2>/dev/null | tail -1)"
    [[ -n "$line" ]] || continue
    MUT_LINES=$((MUT_LINES + 1))
    printf '%s' "$line" | grep -q ' complexity_source=unknown conf=0.0 ' && MUT_UNKNOWN=$((MUT_UNKNOWN + 1))
  done
  if [[ ${MUT_LINES} -eq 3 && ${MUT_UNKNOWN} -eq 3 ]]; then
    pass "C mutated copy: complexity_source=unknown on 3/3 runs (control EXECUTED)"
  else
    fail "C mutated copy" "unknown ${MUT_UNKNOWN}/${MUT_LINES} (expected 3/3)"
  fi
fi
# and on the real file the ONLY unknown is b6 -- the old-caller estimate
# that legitimately has no source fields (§5.1 unknown row). Every line
# whose estimate carried a real source must be non-unknown; state the
# count so a future regression reads as a number, not a vibe.
REAL_LINES=0; REAL_UNKNOWN=0; B6_UNKNOWN=0
for s in b1 b2 b3 b4 b5 b6; do
  line="$(grep -rh 'route_resolved by=arbiter' "$TMP/state-root-$s" 2>/dev/null | tail -1)"
  [[ -n "$line" ]] || continue
  REAL_LINES=$((REAL_LINES + 1))
  if printf '%s' "$line" | grep -q ' complexity_source=unknown '; then
    REAL_UNKNOWN=$((REAL_UNKNOWN + 1))
    [[ "$s" == "b6" ]] && B6_UNKNOWN=1
  fi
done
if [[ ${REAL_LINES} -eq 6 && ${REAL_UNKNOWN} -eq 1 && ${B6_UNKNOWN} -eq 1 ]]; then
  pass "C real file: unknown on exactly 1/6 lines, and it is the b6 old-caller case (0/5 among real sources)"
else
  fail "C real file" "unknown ${REAL_UNKNOWN}/${REAL_LINES} b6_unknown=${B6_UNKNOWN} (expected exactly 1/6, on b6)"
fi

echo "---"
echo "PASS=$PASS FAIL=$FAIL"
[[ ${FAIL} -eq 0 ]]
