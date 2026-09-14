#!/usr/bin/env bash
# run-all-triggers: leadv2-codex-drain-fit leadv2-codex-drain-fit.py leadv2-drain-weights leadv2-drain-weights.py leadv2-cost-actuals
#
# tests/test-codex-drain-fit.sh — CODEX-HAS-TOKENS-BUT-NO-DRAIN-SERIES-01
#
# Guards leadv2-codex-drain-fit.py, the tool that builds the codex drain
# series (util_codex readings from journal.md, joined to arm-registered's
# ground-truth codex spawns and their job-json request.model) and fits it
# with the SAME NNLS solver leadv2-drain-weights.py uses for anthropic/glm.
# Fixtures cover, by name (this lane exists because a missing/unread column
# in a fit output went unread twice — every count below is asserted, not
# eyeballed):
#   (0) bash -n / py_compile the two files under test.
#   (1) reset-spanning interval (Δpct<0) is dropped -> dropped_reset=1.
#   (2) idle interval (Δpct==0, zero attributed tokens) -> dropped_idle=1.
#   (3) a resolved codex spawn (arm-registered + job json + stub token total)
#       is counted in codex_tasks_resolved; an unresolved token total (stub
#       returns "-") is counted in codex_tasks_unresolved_token, never
#       silently dropped.
#   (4) gpt-6-astra (the dispatch launcher's default alias, NOT a fourth
#       model — leadv2-routing.yaml router.dispatch_ladder id=codex) is
#       excluded from per-model attribution: codex_tasks_no_job_model counts
#       it, "gpt-6-astra" never appears as a fitted column, and with only one
#       real per-model slug (gpt-5.6-terra) left the per-model fit reports
#       NOT-ENOUGH-DATA distinct_models=1 rather than fitting a false 2nd column.
#   (5) below MIN_INTERVALS, the top-level gate reports NOT-ENOUGH-DATA and
#       never prints a fit line (no invented weight on too little data).
#   (6) --min-intervals lowers the gate so the same fixture's fit lines do
#       print, and the aggregate fit line carries r2/max_abs_corr/degenerate_pairs
#       (the exact evidence quadruple the mission requires on every fit).
#
# Exit 0 = pass.
set -uo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/leadv2-temp.sh"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
FIT_PY="${LEADV2_CODEX_DRAIN_FIT_PY:-${SCRIPTS_ROOT}/leadv2-codex-drain-fit.py}"
DRAIN_PY="${SCRIPTS_ROOT}/leadv2-drain-weights.py"
COST_LIB="${SCRIPTS_ROOT}/lib/leadv2-cost-actuals.sh"

PASS=0; FAIL=0
log()  { printf -- '[TEST] %s\n' "$*"; }
pass() { PASS=$((PASS+1)); log "PASS: $1"; }
fail() { FAIL=$((FAIL+1)); log "FAIL: $1"; }

TMP="$(lv2_mktemp_dir "codex-drain")"
trap 'rm -rf "$TMP"' EXIT

# ---------------------------------------------------------------------------
# 0. static checks on both files this suite exercises.
# ---------------------------------------------------------------------------
if python3 -m py_compile "$FIT_PY"; then pass "0a py_compile leadv2-codex-drain-fit.py"; else fail "0a py_compile leadv2-codex-drain-fit.py"; fi
if python3 -m py_compile "$DRAIN_PY"; then pass "0b py_compile leadv2-drain-weights.py"; else fail "0b py_compile leadv2-drain-weights.py"; fi
if bash -n "$COST_LIB"; then pass "0c bash -n lib/leadv2-cost-actuals.sh"; else fail "0c bash -n lib/leadv2-cost-actuals.sh"; fi

# ---------------------------------------------------------------------------
# Fixture: five util_codex readings an hour apart -> four intervals:
#   E1->E2 delta=+40 (real, task A / terra, 1_000_000 tok)
#   E2->E3 delta=-45 (reset -> dropped_reset)
#   E3->E4 delta=0, no tokens in range -> dropped_idle
#   E4->E5 delta=+25 (real, task B / astra-aliased, 2_000_000 tok)
# plus task C, same window as A, whose token stub deliberately returns "-".
# ---------------------------------------------------------------------------
epoch() { python3 -c "import datetime,sys; print(int(datetime.datetime.fromisoformat(sys.argv[1]).timestamp()))" "$1"; }
T1="2026-09-14T00:00:00+00:00"; T2="2026-09-14T01:00:00+00:00"
T3="2026-09-14T02:00:00+00:00"; T4="2026-09-14T03:00:00+00:00"
T5="2026-09-14T04:00:00+00:00"
E1="$(epoch "$T1")"; E2="$(epoch "$T2")"; E4="$(epoch "$T4")"; E5="$(epoch "$T5")"

# One shared journal carries the drain readings -- util_codex readings are
# a GLOBAL codex-account series (any task's journal contributes a sample),
# so a realistic fixture puts them in exactly one place; duplicating the same
# five readings across multiple task dirs would just manufacture spurious
# zero-delta (idle) intervals between the duplicate copies.
STATE_ROOT="$TMP/state"
mkdir -p "$STATE_ROOT/repo1/tasks/SHARED01"
cat > "$STATE_ROOT/repo1/tasks/SHARED01/journal.md" <<EOF
- ${T1} [decision] route_resolved arm=codex arbiter_pick=codex util_codex=10
- ${T2} [decision] route_resolved arm=codex arbiter_pick=codex util_codex=50
- ${T3} [decision] route_resolved arm=codex arbiter_pick=codex util_codex=5
- ${T4} [decision] route_resolved arm=codex arbiter_pick=codex util_codex=5
- ${T5} [decision] route_resolved arm=codex arbiter_pick=codex util_codex=30
EOF

ROOT_A="$TMP/repoA"; ROOT_B="$TMP/repoB"; ROOT_C="$TMP/repoC"
mkdir -p "$ROOT_A/docs/handoff/dispatch-AAAAAAA1" "$ROOT_B/docs/handoff/dispatch-AAAAAAA2" "$ROOT_C/docs/handoff/dispatch-AAAAAAA3"
EPOCH_A=$((E1 + 1800))   # inside (E1,E2] -> interval1 (kept, real)
EPOCH_B=$((E4 + 1800))   # inside (E4,E5] -> interval4 (kept, real)
EPOCH_C=$((E1 + 2400))   # inside (E1,E2] as well; token total unresolved
printf 'arm=codex handle=handle-terra-1 epoch=%s LEAD_SESSION=x\n' "$EPOCH_A" > "$ROOT_A/docs/handoff/dispatch-AAAAAAA1/arm-registered"
printf 'arm=codex handle=handle-astra-1 epoch=%s LEAD_SESSION=x\n' "$EPOCH_B" > "$ROOT_B/docs/handoff/dispatch-AAAAAAA2/arm-registered"
printf 'arm=codex handle=handle-ghost-1 epoch=%s LEAD_SESSION=x\n' "$EPOCH_C" > "$ROOT_C/docs/handoff/dispatch-AAAAAAA3/arm-registered"

CODEX_STATE_ROOT="$TMP/codex-guard-state"
mkdir -p "$CODEX_STATE_ROOT/ws1/jobs"
cat > "$CODEX_STATE_ROOT/ws1/jobs/handle-terra-1.json" <<'JSON'
{"id":"handle-terra-1","status":"completed","request":{"model":"gpt-5.6-terra"}}
JSON
cat > "$CODEX_STATE_ROOT/ws1/jobs/handle-astra-1.json" <<'JSON'
{"id":"handle-astra-1","status":"completed","request":{"model":"gpt-6-astra"}}
JSON
# handle-ghost-1 gets no job json at all -- irrelevant, its token total is
# already unresolved via the stub below.

STUB_LIB="$TMP/cost-actuals-stub.sh"
cat > "$STUB_LIB" <<'SH'
#!/usr/bin/env bash
leadv2_lane_token_total() {
  case "$2" in
    AAAAAAA1) echo 1000000 ;;
    AAAAAAA2) echo 2000000 ;;
    *) echo - ;;
  esac
}
SH

RUN_ENV=(
  LEADV2_STATE_GLOB="$STATE_ROOT/*/tasks/*/journal.md"
  LEADV2_CODEX_ARM_REGISTERED_GLOBS="$ROOT_A/docs/handoff/dispatch-*/arm-registered,$ROOT_B/docs/handoff/dispatch-*/arm-registered,$ROOT_C/docs/handoff/dispatch-*/arm-registered"
  LEADV2_COST_ACTUALS_SH="$STUB_LIB"
  CODEX_GUARD_STATE_ROOT="$CODEX_STATE_ROOT"
)

# ---------------------------------------------------------------------------
# 5. default MIN_INTERVALS gate: only 2 kept intervals out of this fixture
#    (well under 12) -> NOT-ENOUGH-DATA, no fit line printed at all.
# ---------------------------------------------------------------------------
OUT_DEFAULT="$(env "${RUN_ENV[@]}" python3 "$FIT_PY" 2>&1)"
if [[ "$OUT_DEFAULT" == *"NOT-ENOUGH-DATA"* && "$OUT_DEFAULT" != *"weights="* ]]; then
  pass "5 below MIN_INTERVALS -> NOT-ENOUGH-DATA, no fit line printed"
else
  fail "5 got: [$OUT_DEFAULT]"
fi

# ---------------------------------------------------------------------------
# 1/2/3/4/6: force the gate down with --min-intervals so the fit lines print,
# and assert every named count in the base summary line.
# ---------------------------------------------------------------------------
OUT="$(env "${RUN_ENV[@]}" python3 "$FIT_PY" --min-intervals 2 2>&1)"
log "fit output:"
printf '%s\n' "$OUT" | sed 's/^/  /'

if [[ "$OUT" == *"kept=2 "* ]]; then pass "1a kept=2 (only the two real-delta intervals survive)"; else fail "1a kept count wrong: [$OUT]"; fi
if [[ "$OUT" == *"dropped_reset=1 "* ]]; then pass "1b dropped_reset=1 (E2->E3 delta=-45, reset artifact)"; else fail "1b dropped_reset wrong: [$OUT]"; fi
if [[ "$OUT" == *"dropped_idle=1 "* ]]; then pass "2 dropped_idle=1 (E3->E4 delta=0, zero tokens)"; else fail "2 dropped_idle wrong: [$OUT]"; fi
if [[ "$OUT" == *"codex_tasks_resolved=2 "* ]]; then pass "3a codex_tasks_resolved=2 (task A + task B)"; else fail "3a resolved wrong: [$OUT]"; fi
if [[ "$OUT" == *"codex_tasks_unresolved_token=1 "* ]]; then pass "3b codex_tasks_unresolved_token=1 (task C, stub returns -)"; else fail "3b unresolved wrong: [$OUT]"; fi
if [[ "$OUT" == *"codex_tasks_no_job_model=1 "* ]]; then pass "4a codex_tasks_no_job_model=1 (task B's astra alias excluded)"; else fail "4a no_job_model wrong: [$OUT]"; fi
if [[ "$OUT" != *"gpt-6-astra"* ]]; then pass "4b gpt-6-astra never appears as a fitted column"; else fail "4b astra leaked into output: [$OUT]"; fi
if [[ "$OUT" == *"per_model NOT-ENOUGH-DATA distinct_models=1"* ]]; then
  pass "4c per-model fit correctly sees only 1 real slug (terra) after excluding astra"
else
  fail "4c per-model distinct_models wrong: [$OUT]"
fi
if [[ "$OUT" =~ r2=-?[0-9]+\.[0-9]+\ max_abs_corr=[0-9]+\.[0-9]+\ degenerate_pairs=[0-9]+ ]]; then
  pass "6 aggregate fit line carries r2/max_abs_corr/degenerate_pairs together"
else
  fail "6 aggregate fit line missing the required evidence quadruple: [$OUT]"
fi

printf 'SUMMARY pass=%d fail=%d\n' "$PASS" "$FAIL"
[[ "$FAIL" -eq 0 ]]
