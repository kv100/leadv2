#!/usr/bin/env bash
# changed-scope triggers, self-registered (scan_suite_triggers convention):
# run-all-triggers: leadv2-dispatch-code leadv2-route-arbiter
# W1-ARBITER-BYPASSED-ON-DISPATCH-01 -- the arbiter was healthy and the road
# into it was not. Live 2026-09-10 (lane b0ec3b03, task 84d8f25ae5eb):
#   dispatch_classified class=non_product reason=explicit_kind_plugin kind=plugin
#   launchable_seam task=b0ec3b03 source=registry kind=plugin     <- seam answered EMPTY, rc=0
#   arbiter_broken task=b0ec3b03 rc=68 reason=fail_open_to_ladder arb_reason=pool_empty_all_excluded arb_kind=code
#   route_resolved by=router router=v1 model=glm rule=none reason=glm_default after=fail_open
# Mechanism: 'plugin' is in NO capability_matrix kinds row, so the seam's
# registry lookup answered arm_not_capable_for_kind for every arm and printed
# an empty csv as a SUCCESS. The arbiter received launchable_arms=[] (a list,
# never None), staged every arm not_launchable, refused pool_empty_all_excluded
# (rc=68) -- and the dispatcher fail-opened to the legacy ladder, so every §1
# arbiter-side behaviour (balancing/forecast/granularity) was dead in prod.
# The same descriptor with the seam answering for the code vocabulary gives
# rc=0 arm=glm -- the arbiter coerces plugin->code itself (kind_unmapped).
#
# Fix under test (leadv2-dispatch-code.sh, _arm_launchable_arms only):
#   guard 1 -- a kind outside the matrix's own kinds vocabulary is queried as
#              'code' (the arbiter's own coercion rule, matrix as vocabulary),
#              journalled as kind_mapped=<orig>->code;
#   guard 2 -- an EMPTY successful answer is seam degradation, not a routing
#              verdict: legacy fail-open ladder + reason=registry_empty_answer.
# The two guards mask each other at the OUTCOME level (guard 2 rescues a
# broken guard 1), so the seam-line assertion (source=registry
# kind_mapped=plugin->code) is what detects a guard-1 regression -- this is
# exactly what the mutation control at the bottom reverses.
#
# Also pins: a genuinely empty launchable signal / a genuinely empty pool
# still refuse LOUDLY (rc=68 + reason line, never a silent substitution), and
# the fail-open counter (fail_open_count=) counts distinct task signatures.
# Hermetic: quota/freepool-gate/arbiter state are test seams; --no-spawn; the
# real worker process never runs.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
DISPATCH_BIN="${SCRIPTS_ROOT}/leadv2-dispatch-code.sh"
ARBITER_LIB="${SCRIPTS_ROOT}/lib/leadv2-route-arbiter.sh"
ROUTING="${SCRIPTS_ROOT}/../config/leadv2-routing.yaml"

PASS=0; FAIL=0
pass() { printf 'PASS: %s\n' "$1"; PASS=$((PASS + 1)); }
fail() { printf 'FAIL: %s -- %s\n' "$1" "${2:-}"; FAIL=$((FAIL + 1)); }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/arb-seam-plugin.XXXXXX")"
trap '[[ "${ARBSEAM_KEEP_LOGS:-0}" == "1" ]] || rm -rf "$TMP"' EXIT

bash -n "$DISPATCH_BIN" || { fail "bash syntax: dispatch"; exit 1; }
pass "bash syntax: dispatch"

quota_json() { # <glm_pct> <codex_pct> <claude_pct> -- all healthy (low pct)
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
LOW_QUOTA="$(quota_json 20 20 20)"

cat > "$TMP/live.sh" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$ROUTE_TEST_QUOTA"
EOF
cat > "$TMP/free.sh" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
chmod +x "$TMP/live.sh" "$TMP/free.sh"

# Failure-memory journals the arbiter reads: real files, zero rows, so the
# arbiter's answer is no_history instead of inheriting this machine's day.
: > "$TMP/events-empty.jsonl"
: > "$TMP/ledger-empty.jsonl"

setup_repo() { # <dir>
  local repo="$1"
  mkdir -p "$repo/.claude/ref" "$repo/docs/leadv2" "$repo/docs/leadv2/tasks"
  git -C "$repo" init -q -b main
  git -C "$repo" config user.email t@e.com; git -C "$repo" config user.name t
  : > "$repo/seed"; git -C "$repo" add seed; git -C "$repo" commit -qm seed
  # The REAL routing yaml, unmodified: this suite pins the production shape
  # (plugin is in no kinds row of the shipped matrix).
  cp "$ROUTING" "$repo/.claude/ref/leadv2-routing.yaml"
}

WORKER="$TMP/worker.sh"
printf '#!/usr/bin/env bash\nprintf "PID=%%s LABEL=t SESSION_ID=t\\n" "$$"\n' > "$WORKER"
chmod +x "$WORKER"

# Judge /bin/false + --task-class standard (the test-freepool-gets-work.sh
# recipe): a stub judge answering {"complexity":"standard"} flips the
# pipeline to plan_first and the architect prepass parks the task before the
# arbiter is ever consulted; a dead judge makes the dispatch honour the
# explicit --task-class and route direct.
export TASK_JUDGE_BIN=/bin/false

# run_dispatch <dispatch_bin> <repo_dir> <suffix> <kind> [arbiter_lib_override] [writes_csv] [state_root_suffix]
run_dispatch() {
  local bin="$1" repo="$2" suffix="$3" kind="$4" arblib="${5:-}" writes="${6:-}" stroot="${7:-$3}"
  (
    cd "$repo" || exit 1
    # exports in a subshell -- an `${x:+VAR=...}` word in assignment-prefix
    # position stops being an assignment once expanded, becomes the command,
    # and silently kills the whole run (caught on the first suite run: every
    # g-case was grepping an empty log).
    export LEADV2_STATE_ROOT="$TMP/state-root-$stroot"
    export LEADV2_ROUTE_ARBITER_QUOTA_LIVE="$TMP/live.sh"
    export LEADV2_ROUTE_ARBITER_FREEPOOL_GATE="$TMP/free.sh"
    export LEADV2_ROUTE_ARBITER_STATE_FILE="$TMP/state-dispatch-$suffix"
    [[ -n "$arblib" ]] && export LEADV2_ROUTE_ARBITER_LIB="$arblib"
    export ROUTE_TEST_QUOTA="$LOW_QUOTA"
    export ROUTE_ARBITER_EVENTS_JOURNAL="$TMP/events-empty.jsonl"
    export ROUTE_ARBITER_FAILURE_LEDGER="$TMP/ledger-empty.jsonl"
    export CLAUDE_PROJECT_ROOT="$repo" LEADV2_PROJECT_ROOT="$repo"
    export LEADV2_DISPATCH_CACHE_DIR="$TMP/cache-$suffix"
    export LEADV2_DISPATCH_E2E_GATE=0 LEADV2_DISPATCH_REVIEW_GATE=0 LEADV2_DISPATCH_ARCHITECT_GATE=0
    export LEADV2_REQUIRE_PHASES=0
    export LEADV2_ROUTER_V2=0 LEADV2_EXCLUDED_ARMS=__none__ LEADV2_LANE_SHAPE=off
    export LEADV2_BURN_GOVERNOR=0 LEADV2_ARM_EARLY_VERDICT_S=0
    export LEADV2_TASK_JUDGE_BIN="$TASK_JUDGE_BIN"
    export LEADV2_DISPATCH_SUBSESSION_BIN="$WORKER"
    if [[ -n "$writes" ]]; then
      exec bash "$bin" "arbiter seam probe ${suffix} ${TMP}" \
        --kind "$kind" --task-class standard --protected --no-spawn --writes "$writes" 2>&1
    else
      exec bash "$bin" "arbiter seam probe ${suffix} ${TMP}" \
        --kind "$kind" --task-class standard --protected --no-spawn 2>&1
    fi
  ) || true
}

# assert_routed_via_arbiter <label> <output> <logpath>
assert_routed_via_arbiter() {
  local label="$1" out="$2" log="$3"
  if printf '%s\n' "$out" | grep -q 'route_resolved by=arbiter role=worker'; then
    pass "($label) dispatch resolves the arm THROUGH the arbiter"
  else
    fail "($label) no arbiter decision line (route_resolved by=arbiter)" "log: $log"
  fi
  if printf '%s\n' "$out" | grep -q 'fail_open_to_ladder'; then
    fail "($label) fail-open to the ladder fired -- the arbiter was bypassed" "log: $log"
  else
    pass "($label) no fail_open_to_ladder on the production path"
  fi
}

# ── g1: the mission's manual form -- kind=code, protected=true, standard ──
REPO_G1="$TMP/repo-g1"; setup_repo "$REPO_G1"
out_g1="$(run_dispatch "$DISPATCH_BIN" "$REPO_G1" g1 code "" "src/x.py")"
printf '%s\n' "$out_g1" > "$TMP/g1.log"
assert_routed_via_arbiter g1 "$out_g1" "$TMP/g1.log"

# ── g2: the LIVE broken form -- kind=plugin (declared non-product), no
# writes, manual --protected: byte-for-byte the b0ec3b03 shape ─────────────
REPO_G2="$TMP/repo-g2"; setup_repo "$REPO_G2"
out_g2="$(run_dispatch "$DISPATCH_BIN" "$REPO_G2" g2 plugin)"
printf '%s\n' "$out_g2" > "$TMP/g2.log"
assert_routed_via_arbiter g2 "$out_g2" "$TMP/g2.log"
if printf '%s\n' "$out_g2" | grep -q 'launchable_seam task=[0-9a-f]\{8\} source=registry kind=plugin kind_mapped=plugin->code'; then
  pass "(g2) seam queries the matrix vocabulary and says so (kind_mapped=plugin->code)"
else
  fail "(g2) seam did not answer from the code vocabulary with a kind_mapped line -- guard 1 regressed (guard 2 would mask it at the outcome level, this line is the detector)" "log: $TMP/g2.log"
fi

# ── g3: the live input replayed straight into the arbiter: launchable_arms=[]
# (what the pre-fix seam handed it for kind=plugin) must STILL be a loud
# refusal -- an empty launchable signal is never a silent substitution ────
out_g3="$(LEADV2_ROUTE_ARBITER_QUOTA_LIVE="$TMP/live.sh" \
  LEADV2_ROUTE_ARBITER_FREEPOOL_GATE="$TMP/free.sh" \
  LEADV2_ROUTE_ARBITER_STATE_FILE="$TMP/state-g3" \
  ROUTE_TEST_QUOTA="$LOW_QUOTA" \
  ROUTE_ARBITER_EVENTS_JOURNAL="$TMP/events-empty.jsonl" \
  ROUTE_ARBITER_FAILURE_LEDGER="$TMP/ledger-empty.jsonl" \
  bash "$ARBITER_LIB" worker '{"kind":"plugin","size":"standard","protected":true,"safety":false,"ui_judgment":false,"task":"repro0001","allowed_arms":["glm","glm-flash","codex","sonnet","freepool"],"launchable_arms":[],"arm_pool":null,"complexity":"unknown","duration_class":"unknown","test_only":0,"requested_arm":"","complexity_source":"unknown"}' 2>&1)"; rc_g3=$?
printf '%s\n' "$out_g3" > "$TMP/g3.log"
if [[ $rc_g3 -eq 68 ]] && printf '%s\n' "$out_g3" | grep -q 'reason=pool_empty_all_excluded'; then
  pass "(g3) empty launchable signal still refuses loudly (rc=68 pool_empty_all_excluded)"
else
  fail "(g3) refusal on a genuinely empty launchable set was not preserved" "rc=$rc_g3 log: $TMP/g3.log"
fi
if printf '%s\n' "$out_g3" | grep -q 'arm_excluded=.*not_launchable'; then
  pass "(g3) refusal names the not_launchable stage per arm"
else
  fail "(g3) refusal line lacks per-arm not_launchable attribution" "log: $TMP/g3.log"
fi

# ── g4: a genuinely empty POOL (explicit --arm-pool of an untrusted arm on a
# protected path) must also stay a loud refusal, not a silent pick ─────────
out_g4="$(LEADV2_ROUTE_ARBITER_QUOTA_LIVE="$TMP/live.sh" \
  LEADV2_ROUTE_ARBITER_FREEPOOL_GATE="$TMP/free.sh" \
  LEADV2_ROUTE_ARBITER_STATE_FILE="$TMP/state-g4" \
  ROUTE_TEST_QUOTA="$LOW_QUOTA" \
  ROUTE_ARBITER_EVENTS_JOURNAL="$TMP/events-empty.jsonl" \
  ROUTE_ARBITER_FAILURE_LEDGER="$TMP/ledger-empty.jsonl" \
  bash "$ARBITER_LIB" worker '{"kind":"code","size":"standard","protected":true,"safety":false,"ui_judgment":false,"task":"repro0002","allowed_arms":null,"launchable_arms":["glm","codex","sonnet"],"arm_pool":["glm-flash"],"complexity":"unknown","duration_class":"unknown","test_only":0,"requested_arm":"","complexity_source":"unknown"}' 2>&1)"; rc_g4=$?
printf '%s\n' "$out_g4" > "$TMP/g4.log"
if [[ $rc_g4 -eq 68 ]] && printf '%s\n' "$out_g4" | grep -q 'reason=pool_empty_all_excluded'; then
  pass "(g4) genuinely empty pool still refuses loudly (rc=68)"
else
  fail "(g4) empty-pool refusal not preserved" "rc=$rc_g4 log: $TMP/g4.log"
fi

# ── g5: fail-open stays, and is COUNTED -- a faulting arbiter (stub lib,
# rc=68) must journal reason + fail_open_count, and distinct task signatures
# must increment the day counter (2 dispatches -> 1, then 2) ───────────────
FAKE_ARBITER="$TMP/fake-arbiter.sh"
cat > "$FAKE_ARBITER" <<'EOF'
route_arbiter() { # <mode> <descriptor-json> -- deterministic fault, rc=68
  printf 'arm=refuse model=none tier=none reason=pool_empty_all_excluded kind=code chain=\n'
  return 68
}
EOF
REPO_G5="$TMP/repo-g5"; setup_repo "$REPO_G5"
out_g5a="$(run_dispatch "$DISPATCH_BIN" "$REPO_G5" g5a code "$FAKE_ARBITER" "src/x.py" g5)"
printf '%s\n' "$out_g5a" > "$TMP/g5a.log"
if printf '%s\n' "$out_g5a" | grep -q 'arbiter_broken task=[0-9a-f]\{8\} rc=68 reason=fail_open_to_ladder fail_open_count=1'; then
  pass "(g5) arbiter fault fail-opens loudly with a counted reason (fail_open_count=1)"
else
  fail "(g5) fail-open line missing or uncounted" "log: $TMP/g5a.log"
fi
out_g5b="$(run_dispatch "$DISPATCH_BIN" "$REPO_G5" g5b code "$FAKE_ARBITER" "src/y.py" g5)"
printf '%s\n' "$out_g5b" > "$TMP/g5b.log"
if printf '%s\n' "$out_g5b" | grep -q 'fail_open_count=2'; then
  pass "(g5) second distinct task signature increments the day counter (fail_open_count=2)"
else
  fail "(g5) day counter did not increment across task signatures" "log: $TMP/g5b.log"
fi
if grep -q '^count=2$' "$TMP"/state-root-g5/.arbiter-fail-open-[0-9]* 2>/dev/null; then
  pass "(g5) counter day-file exists under the redirected state root (hermetic, count=2)"
else
  fail "(g5) counter day-file not found under suite state root" "find in: $TMP/state-root-g5/.arbiter-fail-open-*"
fi

# ── RED-capable: revert guard 1 on a throwaway copy (the exact mutation the
# lead re-runs via leadv2-mutation-control.sh on the real file) and prove the
# seam-line detector loses its anchor. Outcome-level rescue by guard 2 is
# expected and documented -- that is WHY the seam line is the detector. ────
MUT_PLUGIN_ROOT="$TMP/mutated-plugin"
mkdir -p "$MUT_PLUGIN_ROOT"
cp -R "$SCRIPTS_ROOT" "$MUT_PLUGIN_ROOT/scripts"
cp -R "${SCRIPTS_ROOT}/../config" "$MUT_PLUGIN_ROOT/config"
MUT_BIN="${MUT_PLUGIN_ROOT}/scripts/leadv2-dispatch-code.sh"
python3 - "$MUT_BIN" <<'PY' || { fail "(red) mutation anchor not found -- control not falsifiable" "zero-match"; }
import sys
path = sys.argv[1]
src = open(path).read()
anchor = "query_kind = kind if kind in known_kinds else 'code'"
n = src.count(anchor)
if n != 1:
    sys.exit('mutation anchor %r found %d times in %s (expected exactly 1) -- '
             'zero-match/ambiguous, hard failure. The vocabulary coercion lives '
             'in _arm_launchable_arms (W1-ARBITER-BYPASSED-ON-DISPATCH-01 '
             'guard 1); re-anchor this control, do not silence it.'
             % (anchor, n, path))
open(path, 'w').write(src.replace(anchor, 'query_kind = kind'))
PY
bash -n "$MUT_BIN" || { fail "(red) mutated copy fails bash -n"; exit 1; }
REPO_RED="$TMP/repo-red"; setup_repo "$REPO_RED"
out_red="$(run_dispatch "$MUT_BIN" "$REPO_RED" red plugin)"
printf '%s\n' "$out_red" > "$TMP/red.log"
if printf '%s\n' "$out_red" | grep -q 'source=registry kind=plugin kind_mapped=plugin->code'; then
  fail "(red) guard-1 revert did not remove the kind_mapped line -- control is not falsifiable" "log: $TMP/red.log"
else
  pass "(red) with the vocabulary coercion reverted, the kind_mapped seam line is gone (suite red under this mutation)"
fi
if printf '%s\n' "$out_red" | grep -q 'launchable_seam task=[0-9a-f]\{8\} source=legacy kind=plugin reason=registry_empty_answer'; then
  pass "(red) ...and guard 2 says so by name: source=legacy reason=registry_empty_answer (the documented outcome-level rescue)"
else
  fail "(red) guard-2 degradation line absent under guard-1 revert" "log: $TMP/red.log"
fi

echo "---"
echo "PASS=$PASS FAIL=$FAIL"
[[ $FAIL -eq 0 ]]
