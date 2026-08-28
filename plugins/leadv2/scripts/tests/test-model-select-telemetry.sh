#!/usr/bin/env bash
# FP-06 (2026-08-28) — model-selection telemetry suite.
#
# Contract: leadv2-dispatch-code.sh emits ONE machine-parseable journal row
# per dispatch attempt at the attempt's terminal:
#   model_select_telemetry task=<sig8> role=worker class=<class>
#     work_kind=<wk> arm=<arm> model=<model> fallback_depth=<N>
#     floor=<applied|none> spawn_to_terminal_s=<S> terminal=<win|fail>
#     cause=<c>
# and appends the same row as CSV to docs/leadv2/model-select-telemetry.csv
# (header auto-created, exactly once) so FP-04's 20-diff quality gate has a
# dataset.
#
# Test (a): the line is present on a stubbed WIN (freepool bulk build with a
# live stub worker -> confirmed spawn -> terminal=win) AND on a stubbed
# no_work FAIL (stub launcher produces nothing and dies -> chain exhausted ->
# terminal=fail), with every field present and parseable.
# Test (b): CSV row appended, header written once across both dispatches.
#
# NEGATIVE CONTROL (mission test d, declared here, RUN RED): a throwaway copy
# of dispatch-code with the win-terminal telemetry call removed re-runs the
# EXACT win probe and must produce NO model_select_telemetry line and NO CSV
# row -- proving (a)'s assertion is load-bearing, not tautological. The copy
# lives in the scripts dir only so SCRIPT_DIR sibling resolution (lib/,
# launchers, bins) still works; the trap removes it.
#
# Hermetic: no network, no live proxy, no real dispatch. Same seams as the
# FP-08 floor suite (LEADV2_ROUTE_ARBITER_*, LEADV2_DISPATCH_*_BIN).
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
DISPATCH_BIN="${SCRIPTS_ROOT}/leadv2-dispatch-code.sh"
ROUTING="${SCRIPTS_ROOT}/../config/leadv2-routing.yaml"
NEGCTRL="${SCRIPTS_ROOT}/.fp06-negctrl-dispatch-tmp.sh"

PASS=0; FAIL=0
pass() { printf 'PASS: %s\n' "$1"; PASS=$((PASS + 1)); }
fail() { printf 'FAIL: %s -- %s\n' "$1" "${2:-}"; FAIL=$((FAIL + 1)); }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/fp06-telem.XXXXXX")"
cleanup() { rm -f "$NEGCTRL"; [[ "${FP06_KEEP_LOGS:-0}" == "1" ]] || rm -rf "$TMP"; }
trap cleanup EXIT

bash -n "$DISPATCH_BIN" || { fail "bash syntax: dispatch"; exit 1; }
pass "bash syntax: dispatch"

# ── fixtures (same shape as test-freepool-capability-floor.sh) ──────────────
cat > "$TMP/live.sh" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$ROUTE_TEST_QUOTA"
EOF
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
# every paid provider capped -> freepool is the only capable arm (bulk build)
ALL_CAPPED="$(quota_json 99 99 99)"

mk_repo() { # <dir>
  mkdir -p "$1/.claude/ref" "$1/docs/leadv2" "$1/docs/leadv2/tasks"
  git -C "$1" init -q -b main
  git -C "$1" config user.email t@e.com; git -C "$1" config user.name t
  : > "$1/seed"; git -C "$1" add seed; git -C "$1" commit -qm seed
  cp "$ROUTING" "$1/.claude/ref/leadv2-routing.yaml"
}

WORKER="$TMP/worker.sh"
printf '#!/usr/bin/env bash\nprintf "PID=%%s LABEL=t SESSION_ID=t\\n" "$$"\n' > "$WORKER"
chmod +x "$WORKER"

# Hermetic admission: trivial estimate -> Light (never floored), work_kind=build.
cat > "$TMP/judge-light.sh" <<'JEOF'
#!/usr/bin/env bash
printf '%s\n' '{"complexity":"trivial","work_kind":"build","estimate_source":"fallback"}'
JEOF
chmod +x "$TMP/judge-light.sh"

# (a-win) freepool stub: bg -> live handle, status -> running. The win
# terminal fires at spawn CONFIRM time, so no background completion is needed.
FP_RUNS="$TMP/freepool-runs"; mkdir -p "$FP_RUNS"
cat > "$TMP/freepool-win-stub.sh" <<STUB
#!/usr/bin/env bash
RUNS="\${FP_STUB_RUNS:-$FP_RUNS}"
case "\${1:-}" in
  bg)
    shift
    id="run-\$\$"
    mkdir -p "\$RUNS/\$id"
    printf 'status: running\npid: %s\n' "\$\$" > "\$RUNS/\$id/meta.yaml"
    printf '%s\n' "\$id"
    ;;
  status)
    cat "\$RUNS/\${2:-}/meta.yaml" 2>/dev/null
    ;;
  *) exit 2 ;;
esac
STUB
chmod +x "$TMP/freepool-win-stub.sh"

# (a-fail) freepool stub that produces NOTHING and dies (no_work shape: no
# run dir, no handle ever live, launcher exit 99 with no refusal marker).
cat > "$TMP/freepool-fail-stub.sh" <<'STUB'
#!/usr/bin/env bash
printf 'status: failed\nexit_code: 1\n' >&2
exit 99
STUB
chmod +x "$TMP/freepool-fail-stub.sh"

for _arm in glm kimi codex; do
  printf '#!/usr/bin/env bash\nprintf "POISON: real provider spawn attempted\\n" >&2\nexit 99\n' > "$TMP/poison-${_arm}.sh"
  chmod +x "$TMP/poison-${_arm}.sh"
done

run_dispatch() { # <repo_dir> <freepool_stub> <unique-mission>
  (cd "$1" && \
   LEADV2_STATE_ROOT="$TMP/state-root-$3" \
   LEADV2_ROUTE_ARBITER_QUOTA_LIVE="$TMP/live.sh" \
   LEADV2_ROUTE_ARBITER_FREEPOOL_GATE="$TMP/free.sh" \
   LEADV2_ROUTE_ARBITER_STATE_FILE="$TMP/state-$3" \
   ROUTE_TEST_QUOTA="$ALL_CAPPED" \
   CLAUDE_PROJECT_ROOT="$1" LEADV2_PROJECT_ROOT="$1" \
   LEADV2_DISPATCH_CACHE_DIR="$TMP/cache-$3" \
   LEADV2_DISPATCH_E2E_GATE=0 LEADV2_DISPATCH_REVIEW_GATE=0 LEADV2_DISPATCH_ARCHITECT_GATE=0 \
   LEADV2_ROUTER_V2=0 LEADV2_EXCLUDED_ARMS=__none__ LEADV2_LANE_SHAPE=off \
   LEADV2_BURN_GOVERNOR=0 \
   LEADV2_TASK_JUDGE_BIN="$TMP/judge-light.sh" \
   LEADV2_ARM_EARLY_VERDICT_S=1 LEADV2_ARM_EARLY_VERDICT_POLL_S=0.2 \
   LEADV2_DISPATCH_FREEPOOL_BIN="$2" FP_STUB_RUNS="$FP_RUNS" \
   LEADV2_DISPATCH_GLM_BIN="$TMP/poison-glm.sh" \
   LEADV2_DISPATCH_KIMI_BIN="$TMP/poison-kimi.sh" \
   LEADV2_DISPATCH_CODEX_BIN="$TMP/poison-codex.sh" \
   LEADV2_DISPATCH_SUBSESSION_BIN="$WORKER" \
   bash "${4:-$DISPATCH_BIN}" "FP-06 telemetry probe $3" \
     --kind code --task-class bulk --writes src/x.py 2>&1 || true)
}

# every field, present and parseable (shared by win and fail rows)
TELEM_RE='model_select_telemetry task=[0-9a-f]{8} role=worker class=[a-z]+ work_kind=[a-z-]+ arm=[a-z-]+ model=[^ ]+ fallback_depth=[0-9]+ floor=(applied|none) spawn_to_terminal_s=[0-9]+ terminal=(win|fail) cause=[a-z_]+'

# ── (a) WIN: stubbed freepool worker -> confirmed spawn -> terminal=win ────
REPO1="$TMP/repo1"; mk_repo "$REPO1"
win_out="$(run_dispatch "$REPO1" "$TMP/freepool-win-stub.sh" win)"
printf '%s\n' "$win_out" > "$TMP/win-out.log"
win_line="$(printf '%s\n' "$win_out" | grep -E 'model_select_telemetry' | tail -1)"
if printf '%s' "$win_line" | grep -qE "$TELEM_RE"; then
  pass "(a) win: telemetry line present with every field parseable"
else
  fail "(a) win: telemetry line missing/unparseable (line: '$win_line'; log: $TMP/win-out.log)"
fi
if printf '%s' "$win_line" | grep -q 'terminal=win cause=worker_spawned'; then
  pass "(a) win: terminal=win cause=worker_spawned"
else
  fail "(a) win: wrong terminal/cause ($win_line)"
fi
if printf '%s\n' "$win_out" | grep -q 'route_resolved by=arbiter role=worker arm=freepool'; then
  pass "(a) win: probe really dispatched via freepool"
else
  fail "(a) win: probe did not dispatch via freepool (log: $TMP/win-out.log)"
fi

# ── (a) FAIL: stub that produces no work and dies -> chain exhausted ────────
REPO2="$TMP/repo2"; mk_repo "$REPO2"
fail_out="$(run_dispatch "$REPO2" "$TMP/freepool-fail-stub.sh" fail)"
printf '%s\n' "$fail_out" > "$TMP/fail-out.log"
fail_line="$(printf '%s\n' "$fail_out" | grep -E 'model_select_telemetry' | tail -1)"
if printf '%s' "$fail_line" | grep -qE "$TELEM_RE"; then
  pass "(a) fail: telemetry line present with every field parseable"
else
  fail "(a) fail: telemetry line missing/unparseable (line: '$fail_line'; log: $TMP/fail-out.log)"
fi
if printf '%s' "$fail_line" | grep -q 'terminal=fail cause=all_arms_unavailable'; then
  pass "(a) fail: terminal=fail cause=all_arms_unavailable"
else
  fail "(a) fail: wrong terminal/cause ($fail_line)"
fi
if printf '%s' "$fail_line" | grep -q 'arm=freepool'; then
  pass "(a) fail: failing arm recorded"
else
  fail "(a) fail: arm field wrong ($fail_line)"
fi

# ── (b) CSV: row per dispatch, header exactly once ──────────────────────────
CSV="$REPO2/docs/leadv2/model-select-telemetry.csv"
win_csv="$REPO1/docs/leadv2/model-select-telemetry.csv"
if [[ -f "$win_csv" && -f "$CSV" ]]; then
  pass "(b) CSV file created under docs/leadv2 for each repo"
else
  fail "(b) CSV file missing (win: ${win_csv}, fail: ${CSV})"
fi
h1="$(grep -c '^task,role,class,work_kind,arm,model,fallback_depth,floor,spawn_to_terminal_s,terminal,cause$' "$CSV" 2>/dev/null || true)"
if [[ "${h1:-0}" -eq 1 ]]; then
  pass "(b) CSV header written exactly once"
else
  fail "(b) CSV header count != 1 ($h1; file: $(cat "$CSV" 2>/dev/null | head -3))"
fi
if tail -1 "$CSV" 2>/dev/null | grep -qE "^[0-9a-f]{8},worker,[a-z]+,[a-z-]+,freepool,.+,[0-9]+,(applied|none),[0-9]+,fail,all_arms_unavailable$"; then
  pass "(b) fail dispatch appended a matching CSV row"
else
  fail "(b) fail CSV row wrong ($(tail -1 "$CSV" 2>/dev/null))"
fi
if tail -1 "$win_csv" 2>/dev/null | grep -qE "^[0-9a-f]{8},worker,[a-z]+,[a-z-]+,freepool,.+,[0-9]+,(applied|none),[0-9]+,win,worker_spawned$"; then
  pass "(b) win dispatch appended a matching CSV row"
else
  fail "(b) win CSV row wrong ($(tail -1 "$win_csv" 2>/dev/null))"
fi

# ── (d) NEGATIVE CONTROL — RUN RED (mission test d) ─────────────────────────
# Remove the win-terminal telemetry call from a throwaway copy, re-run the
# EXACT win probe against the copy, and require the (a) assertions to go RED:
# no journal line AND no CSV row. If either survives, (a) was tautological.
sed 's/^      _model_select_telemetry win worker_spawned "${candidate}"$/      : # fp06-negctl: win telemetry removed/' \
  "$DISPATCH_BIN" > "$NEGCTRL"
if grep -q 'fp06-negctl' "$NEGCTRL" && ! grep -q '^      _model_select_telemetry win' "$NEGCTRL"; then
  pass "(negative-control) telemetry call removed from a throwaway dispatch copy"
else
  fail "(negative-control) mutation did not land — control is void"
fi
bash -n "$NEGCTRL" || { fail "(negative-control) mutated copy fails bash -n"; exit 1; }
REPO3="$TMP/repo3"; mk_repo "$REPO3"
neg_out="$(run_dispatch "$REPO3" "$TMP/freepool-win-stub.sh" neg "$NEGCTRL")"
printf '%s\n' "$neg_out" > "$TMP/neg-out.log"
neg_csv="$REPO3/docs/leadv2/model-select-telemetry.csv"
neg_red=0
printf '%s\n' "$neg_out" | grep -q 'model_select_telemetry' || neg_red=$((neg_red + 1))  # (a) journal assertion goes red
[[ ! -f "$neg_csv" ]] && neg_red=$((neg_red + 1))                                      # (b) CSV assertion goes red
if [[ "$neg_red" -eq 2 ]]; then
  pass "(negative-control) with emission removed, (a)+(b) run RED: no journal line, no CSV"
else
  fail "(negative-control) telemetry survived the mutation — (a)/(b) not load-bearing (log: $TMP/neg-out.log; csv: ${neg_csv})"
fi
# the mutated copy still WINS the dispatch itself (telemetry removal must not
# change the outcome) -- proves the control neutralized telemetry, not spawning
if printf '%s\n' "$neg_out" | grep -q 'route_resolved by=router router=arbiter model=freepool'; then
  pass "(negative-control) mutated copy still spawns freepool (only telemetry is gone)"
else
  fail "(negative-control) mutation broke the dispatch itself, control is invalid (log: $TMP/neg-out.log)"
fi

printf '\n=== %d passed, %d failed ===\n' "${PASS}" "${FAIL}"
[[ "${FAIL}" == 0 ]]
