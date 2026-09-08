#!/usr/bin/env bash
# run-all-triggers: leadv2-complexity-estimate
# test-complexity-estimate-easy-half.sh — PHASES-ARE-NOT-SCALED-BY-COMPLEXITY-01 (row f33ff575078f)
#
# Proves the standalone estimator (lib/leadv2-complexity-estimate.py) reaches
# BOTH ends of the route it draws: a trivial mission must actually resolve to
# pipeline_route=brief_direct review_rounds=1 (the "easy half" that has never
# once fired in nine live complexity_gate_applied rows -- design doc §8), and
# a heavy multi-subsystem mission must resolve deeper. Asserting only the
# plan_first/complex row is not a control -- it is the constant this task
# exists to break, so every check below asserts both ends.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB="${SCRIPT_DIR}/../lib/leadv2-complexity-estimate.py"
PASS=0; FAIL=0
pass(){ printf 'PASS: %s\n' "$1"; PASS=$((PASS+1)); }
fail(){ printf 'FAIL: %s\n' "$1"; FAIL=$((FAIL+1)); }

[[ -f "$LIB" ]] || { printf 'FAIL: estimator missing at %s\n' "$LIB"; exit 1; }

est(){ python3 "$LIB" "$@"; }

# ── fixture: a genuinely trivial mission (one-line docs edit, one file) ─────
TRIVIAL_MISSION="Fix a typo in the README installation section."
out_trivial="$(est --mission "$TRIVIAL_MISSION" --write-set "README.md")"

# ── fixture: a heavy multi-subsystem mission (long, several files, 4 subsystems) ─
COMPLEX_MISSION="Rewrite the auth middleware end to end: migrate the session
table to the new schema, update every service that reads a session, and
adjust the deploy pipeline so the migration runs before traffic is cut over.
This touches the API layer, the background worker, the database migration
scripts, and the deploy config -- coordinate the rollout across services so
no request is served against a half-migrated session table. $(printf 'x%.0s' $(seq 1 1300))"
COMPLEX_WRITE_SET="services/api/auth.py,services/worker/session.py,migrations/002_session.sql,deploy/pipeline.yaml,gateway/proxy.py"
out_complex="$(est --mission "$COMPLEX_MISSION" --write-set "$COMPLEX_WRITE_SET")"

# ── (1) the easy half is reachable: trivial -> brief_direct, review_rounds=1 ─
if [[ "$out_trivial" == *'pipeline_route=brief_direct'* && "$out_trivial" == *'review_rounds=1'* ]]; then
  pass "trivial mission resolves brief_direct/review_rounds=1 (easy half is reachable): $out_trivial"
else
  fail "trivial mission did not reach the easy half: $out_trivial"
fi

# ── (2) a heavy multi-subsystem mission resolves DEEPER, never brief_direct ──
if [[ "$out_complex" == *'pipeline_route=plan_first'* && "$out_complex" == *'review_rounds=3'* ]]; then
  pass "heavy multi-subsystem mission resolves plan_first/review_rounds=3: $out_complex"
else
  fail "heavy mission did not resolve deeper: $out_complex"
fi

# ── (3) flag is the exception, not the default: neither verdict above is flag ─
if [[ "$out_trivial" != *'complexity_source=flag'* && "$out_complex" != *'complexity_source=flag'* ]]; then
  pass "complexity_source is not flag by default for either fixture"
else
  fail "flag leaked into a default (non-override) verdict: trivial=$out_trivial complex=$out_complex"
fi

# ── (4) asymmetry: NO signal at all resolves DEEPER, never to the easy half ──
out_unknown="$(est --mission "" --write-set "")"
if [[ "$out_unknown" == *'complexity_source=unknown'* && "$out_unknown" == *'pipeline_route=plan_first'* && "$out_unknown" == *'review_rounds=2'* ]]; then
  pass "no-signal input resolves deeper (standard/plan_first), never brief_direct: $out_unknown"
else
  fail "no-signal input did not resolve to the deeper floor: $out_unknown"
fi

# ── (5) flag IS reachable when the operator explicitly asks for an override ──
out_flag="$(est --mission "$TRIVIAL_MISSION" --write-set "README.md" --declared-class Heavy --flag)"
if [[ "$out_flag" == *'complexity_source=flag'* && "$out_flag" == *'complexity=complex'* && "$out_flag" == *'pipeline_route=plan_first'* && "$out_flag" == *'review_rounds=3'* ]]; then
  pass "explicit operator override still reaches complexity_source=flag: $out_flag"
else
  fail "explicit override did not resolve to flag/complex: $out_flag"
fi

printf 'SUMMARY: pass=%s fail=%s\n' "$PASS" "$FAIL"
(( FAIL == 0 ))
