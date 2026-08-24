#!/usr/bin/env bash
# test-leadv2-review-routing.sh — engine degradation suite (dispatch-4fb7381a, per
# dispatch-75d151fe-architect §2b). Rewritten from a workflows/leadv2-review.js harness
# (that file is deleted, see dispatch-75d151fe-architect §1/§5) to run the REAL sole-owner
# engine (leadv2-review-run.sh) end to end with stubbed provider bins. No live
# provider/network calls.
#
# KNOWN COVERAGE DELTA: the original suite asserted a critic prompt-BREADTH promotion —
# a narrow "structural cross-check" prompt vs. a full "adversarial code review" prompt,
# chosen based on whether Codex was available. The engine has NO analogue: its
# degradation model is classify_arm_failure() + next_ok_arm_after() rotating to the next
# :ok: arm in the resolver's pool (a distinct PROVIDER, not a distinct PROMPT BREADTH for
# the same provider). Per architect §2b this is a real, permanent coverage delta, not
# something to invent in the engine to satisfy an old test. Recorded here and in
# plugins/leadv2/docs/phases.md.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SCRIPTS_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
ENGINE="$SCRIPTS_ROOT/leadv2-review-run.sh"

PASS=0; FAIL=0
log()  { printf '%s\n' "$*"; }
pass() { log "PASS: $*"; PASS=$((PASS + 1)); }
fail() { log "FAIL: $*"; FAIL=$((FAIL + 1)); }

bash -n "$SCRIPT_DIR/test-leadv2-review-routing.sh" 2>/dev/null || { echo "ERROR: self syntax check failed"; exit 1; }

if [[ ! -f "$ENGINE" ]]; then
  fail "leadv2-review-run.sh does not exist"
  log "PASS=$PASS FAIL=$FAIL"; exit 1
fi

# --- shared fixture builders ---------------------------------------------------
mk_fixture() { # <tag> -> sets ROOT/HANDOFF/DIFF, mkdirs
  local tag="$1"
  ROOT="$TMP/repo-$tag"
  mkdir -p "$ROOT/.claude/ref"
  HANDOFF="$ROOT/docs/handoff/dispatch-ROUTE$tag"
  mkdir -p "$HANDOFF"
  DIFF="$HANDOFF/review.diff"
  printf 'diff --git a/x b/x\n+hello\n' > "$DIFF"
}

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT

cat > "$TMP/resolver.py" <<'PY'
#!/usr/bin/env python3
print("reviewer=codex")
print("pool=codex:ok:,glm:ok:,sonnet:ok:")
print("refusal=")
PY
chmod +x "$TMP/resolver.py"

cat > "$TMP/codex-ok.sh" <<'SH'
#!/usr/bin/env bash
printf 'REVIEW_VERDICT: PASS\nREVIEW_FINDINGS: critical=0 high=0 medium=0 low=0\n'
SH
chmod +x "$TMP/codex-ok.sh"

# Simulates a quota-refused Codex (LEADV2_DISPATCH_REFUSED marker + rc=75, the
# `classify_arm_failure` refused_quota path).
cat > "$TMP/codex-refused.sh" <<'SH'
#!/usr/bin/env bash
printf 'LEADV2_DISPATCH_REFUSED: quota\n' >&2
exit 75
SH
chmod +x "$TMP/codex-refused.sh"

cat > "$TMP/glm.sh" <<'SH'
#!/usr/bin/env bash
out=""
while [[ $# -gt 0 ]]; do case "$1" in --out) out="$2"; shift 2 ;; *) shift ;; esac; done
# Match the real glm-coder transport: its generic run path persists Claude's
# JSON envelope, while the review engine must materialize `result` before
# parsing its verdict contract.
printf '%s\n' '{"is_error":false,"result":"REVIEW_VERDICT: PASS\nREVIEW_FINDINGS: critical=0 high=0 medium=0 low=0\nClean."}' > "$out"
SH
chmod +x "$TMP/glm.sh"

cat > "$TMP/architect.sh" <<'SH'
#!/usr/bin/env bash
role=""
while [[ $# -gt 0 ]]; do case "$1" in --role) role="$2"; shift 2 ;; *) shift ;; esac; done
[[ "$role" == "hack-detect" ]] && exit 0
printf 'REVIEW_VERDICT: PASS\nREVIEW_FINDINGS: critical=0 high=0 medium=0 low=0\n'
SH
chmod +x "$TMP/architect.sh"

cat > "$TMP/dispatch.sh" <<'SH'
#!/usr/bin/env bash
exit 0
SH
chmod +x "$TMP/dispatch.sh"

# --- Scenario 1: normal round -- codex is the base arm and the first fan-out arm -------
mk_fixture normal
LEADV2_GLM_POLICY_RESOLVER="$TMP/resolver.py" \
LEADV2_DISPATCH_CODEX_BIN="$TMP/codex-ok.sh" \
LEADV2_DISPATCH_GLM_BIN="$TMP/glm.sh" \
LEADV2_DISPATCH_ARCHITECT_BIN="$TMP/architect.sh" \
LEADV2_DISPATCH_BIN="$TMP/dispatch.sh" \
LEADV2_REVIEW_FANOUT=1 \
bash "$ENGINE" --task ROUTEnormal --root "$ROOT" --handoff "$HANDOFF" --diff "$DIFF" --author sonnet >/dev/null 2>"$TMP/normal.err"
rc=$?
arms_line="$(sed -n 's/^arms:[[:space:]]*//p' "$HANDOFF/review-gate.md" 2>/dev/null | head -n1)"
if [[ $rc -eq 0 && "$arms_line" == codex* ]]; then
  pass "normal round: codex is base-arm and ran as the (first) fan-out arm — arms: $arms_line"
else
  fail "normal round: expected codex as base/first arm, got rc=$rc arms='$arms_line'"
fi

# --- Scenario 2: codex unavailable -- pool degrades to a distinct non-codex arm, logged
mk_fixture unavailable
LEADV2_GLM_POLICY_RESOLVER="$TMP/resolver.py" \
LEADV2_DISPATCH_CODEX_BIN="$TMP/codex-refused.sh" \
LEADV2_DISPATCH_GLM_BIN="$TMP/glm.sh" \
LEADV2_DISPATCH_ARCHITECT_BIN="$TMP/architect.sh" \
LEADV2_DISPATCH_BIN="$TMP/dispatch.sh" \
LEADV2_REVIEW_FANOUT=1 \
bash "$ENGINE" --task ROUTEunavail --root "$ROOT" --handoff "$HANDOFF" --diff "$DIFF" --author sonnet >/dev/null 2>"$TMP/unavail.err"
rc=$?
arms_line="$(sed -n 's/^arms:[[:space:]]*//p' "$HANDOFF/review-gate.md" 2>/dev/null | head -n1)"
if [[ $rc -eq 0 && -n "$arms_line" && "$arms_line" != codex* && "$arms_line" != *codex* ]]; then
  pass "codex-unavailable round: pool reselected to a distinct non-codex arm — arms: $arms_line"
else
  fail "codex-unavailable round: expected reselection off codex, got rc=$rc arms='$arms_line'"
fi

if grep -q 'review_gate task=ROUTEunavail status=arm_refused arm=codex reason=refused_quota' "$TMP/unavail.err"; then
  pass "codex-unavailable round: arm_refused/refused_quota logged on the human-visible stderr line"
else
  fail "codex-unavailable round: expected arm_refused log line naming codex/refused_quota not found"
  log "  --- engine stderr ---"
  sed 's/^/  /' "$TMP/unavail.err"
fi

log ""
log "================================================"
log "  review routing (engine degradation): PASS=$PASS FAIL=$FAIL"
log "================================================"
[[ "$FAIL" -eq 0 ]]
