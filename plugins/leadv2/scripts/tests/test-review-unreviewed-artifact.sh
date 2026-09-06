#!/usr/bin/env bash
# run-all-triggers: leadv2-review-run.sh
# test-review-unreviewed-artifact.sh — DISPATCHER-BRANCH-RESIDUE-01 (worktree-100a892d
# §3.1 residue): the engine path's two "no reviewer was ever seated" exits must emit
# the SAME 8-field unreviewed artifact the close-gate's _pc_write_unreviewed has shipped
# since dispatch-8e2a32be (refusal:/resolver_rc:/resolver_stderr:/merge_blocked:), never
# the lossy 4-field shape (bare `pool:` / empty `tried:`) that made the live
# dispatch-4c9ddb05 review-gate.md undiagnosable.
#
# Hermetic: LEADV2_GLM_POLICY_RESOLVER swaps in stub resolvers; no arms ever run on
# these paths (the gate exits before any spawn); no live provider/network calls.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SCRIPTS_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
ENGINE="${SCRIPTS_ROOT}/leadv2-review-run.sh"

PASS=0; FAIL=0
pass() { printf 'PASS: %s\n' "$*"; PASS=$((PASS + 1)); }
fail() { printf 'FAIL: %s\n' "$*"; FAIL=$((FAIL + 1)); }

bash -n "$ENGINE" || { echo "ERROR: engine syntax check failed"; exit 1; }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/leadv2-unrev-artifact.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

mk_fixture() { # <tag> -> ROOT/HANDOFF/DIFF
  local tag="$1"
  ROOT="$TMP/repo-$tag"
  mkdir -p "$ROOT/.claude/ref"
  HANDOFF="$ROOT/docs/handoff/dispatch-UNREV$tag"
  mkdir -p "$HANDOFF"
  DIFF="$HANDOFF/review.diff"
  printf 'diff --git a/x b/x\n+hello\n' > "$DIFF"
}

# 8-field shape assertions shared by both scenarios: every previously-absent field
# must now be present and non-empty (literal "-" for genuinely-empty values).
assert_full_shape() { # <label> <gate-file>
  local label="$1" gate="$2" ok=1
  grep -q '^status: unreviewed$'      "$gate" || { fail "$label: status: unreviewed missing"; ok=0; }
  grep -q '^reason: all_arms_unavailable$' "$gate" || { fail "$label: reason missing"; ok=0; }
  grep -q '^refusal: .\+$'            "$gate" || { fail "$label: refusal missing/empty"; ok=0; }
  grep -qE '^resolver_rc: [0-9]+$'    "$gate" || { fail "$label: resolver_rc missing/not-numeric"; ok=0; }
  grep -qE '^resolver_stderr: .+$'    "$gate" || { fail "$label: resolver_stderr missing"; ok=0; }
  grep -q '^merge_blocked: true$'     "$gate" || { fail "$label: merge_blocked: true missing"; ok=0; }
  grep -q '^tried: .\+$'              "$gate" || { fail "$label: tried missing/empty"; ok=0; }
  (( ok )) && pass "$label: full 8-field unreviewed artifact"
}

# ── T1: resolver returns an empty pool (reviewer empty, rc 0) — first unreviewed exit ──
cat > "$TMP/resolver-empty.py" <<'PY'
#!/usr/bin/env python3
print("reviewer=")
print("pool=")
print("refusal=all_review_arms_unavailable")
PY
chmod +x "$TMP/resolver-empty.py"

mk_fixture empty
LEADV2_GLM_POLICY_RESOLVER="$TMP/resolver-empty.py" \
LEADV2_REVIEW_FANOUT=1 \
bash "$ENGINE" --task UNREVempty --root "$ROOT" --handoff "$HANDOFF" \
  --diff "$DIFF" --author sonnet >/dev/null 2>"$TMP/t1.err"
rc1=$?
if [[ $rc1 -eq 9 ]]; then
  pass "T1: empty pool exits 9"
else
  fail "T1: expected exit 9, got $rc1 (err tail: $(tail -1 "$TMP/t1.err"))"
fi
assert_full_shape "T1" "$HANDOFF/review-gate.md"
grep -q '^refusal: all_review_arms_unavailable$' "$HANDOFF/review-gate.md" \
  && pass "T1: refusal carries the resolver's named refusal" \
  || fail "T1: refusal value lost"

# ── T2: resolver CRASHES (rc 2, no pool= line at all) — fail closed, loud, 8 fields ──
cat > "$TMP/resolver-crash.py" <<'PY'
#!/usr/bin/env python3
import sys
sys.stderr.write("simulated resolver crash: bad --routing-yaml\n")
sys.exit(2)
PY
chmod +x "$TMP/resolver-crash.py"

mk_fixture crash
LEADV2_GLM_POLICY_RESOLVER="$TMP/resolver-crash.py" \
LEADV2_REVIEW_FANOUT=1 \
bash "$ENGINE" --task UNREVcrash --root "$ROOT" --handoff "$HANDOFF" \
  --diff "$DIFF" --author sonnet >/dev/null 2>"$TMP/t2.err"
rc2=$?
if [[ $rc2 -eq 9 ]]; then
  pass "T2: crashed resolver fails closed to exit 9"
else
  fail "T2: expected exit 9, got $rc2 (err tail: $(tail -1 "$TMP/t2.err"))"
fi
assert_full_shape "T2" "$HANDOFF/review-gate.md"
grep -q '^refusal: resolver_error_failclosed$' "$HANDOFF/review-gate.md" \
  && pass "T2: refusal names resolver_error_failclosed" \
  || fail "T2: fail-closed refusal lost"
grep -q '^resolver_rc: 2$' "$HANDOFF/review-gate.md" \
  && pass "T2: resolver_rc records the REAL rc (2), not a dash" \
  || fail "T2: resolver_rc wrong (want 2): $(grep '^resolver_rc:' "$HANDOFF/review-gate.md")"
# the stderr artifact must actually exist and carry the crash line
stderr_path="$(sed -n 's/^resolver_stderr: //p' "$HANDOFF/review-gate.md" | head -n1)"
if [[ "${stderr_path}" != "-" && -f "$ROOT/${stderr_path}" ]] \
  && grep -q 'simulated resolver crash' "$ROOT/${stderr_path}"; then
  pass "T2: resolver_stderr points at a real artifact carrying the crash text"
else
  fail "T2: resolver_stderr artifact missing/empty (path='${stderr_path}')"
fi

printf 'PASS=%d FAIL=%d\n' "$PASS" "$FAIL"
(( FAIL == 0 ))
