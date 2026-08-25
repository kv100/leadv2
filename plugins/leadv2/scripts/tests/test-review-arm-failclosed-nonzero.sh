#!/usr/bin/env bash
# REVIEW-ARM-FAILCLOSED-02 (2026-08-25).
#
# THE DEFECT THIS TEST PINS: with a caller running the engine under `set -e`
# (bash -e leadv2-review-run.sh), a reviewer arm whose stub exits nonzero
# aborted _engine_arm_job mid-function, so review-<arm>.rc was NEVER written;
# the parent then hit its inline infra-retry `run_reviewer_arm` bare call,
# which -e aborted too — and the whole engine died with NO review-gate.md,
# NO terminal review-gate status, exit = the stub's rc. Verified red on the
# pre-change file (engine exit 3, empty handoff for gates, no .rc).
#
# Fix contract pinned here:
#   1. review-<arm>.rc is ALWAYS written, carrying the arm's real nonzero rc.
#   2. The parent survives, classifies the failed/empty arms and emits a
#      TERMINAL gate: status: blocked, reason: provider_error, rc: <real rc>,
#      arm_rc: <arm>=<rc>[,...] naming every arm that produced no verdict.
#   3. The happy path is untouched (a healthy arm still gates status: pass).
#
# Uses the REAL resolver (lib/leadv2-glm-policy-resolve.py) with a stubbed
# --quota-live reader and stubbed reviewer binaries. No network, no provider.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SCRIPTS_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
# ENGINE may be overridden so this same suite can be run against the PRE-change
# file extracted from git (RED-then-GREEN evidence).
ENGINE="${LEADV2_TEST_ENGINE:-$SCRIPTS_ROOT/leadv2-review-run.sh}"

PASS=0; FAIL=0
log()  { printf '%s\n' "$*"; }
pass() { log "PASS: $*"; PASS=$((PASS + 1)); }
fail() { log "FAIL: $*"; FAIL=$((FAIL + 1)); }

bash -n "$0" 2>/dev/null || { echo "ERROR: self syntax check failed"; exit 1; }

if [[ ! -f "$ENGINE" ]]; then
  fail "engine not found: $ENGINE"
  log "PASS=$PASS FAIL=$FAIL"; exit 1
fi

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT

# --- shared stubs ----------------------------------------------------------
# codex weekly 98% (>= review_threshold_pct 95 -> blocked)
# glm       95% (>= glm_review_threshold_pct 90 -> blocked)
# anthropic 30% (<  anthropic_review_threshold_pct 95 -> opus & sonnet ok)
# author=glm in every case, so the ok pool is exactly [opus, sonnet].
cat > "$TMP/quota-live.sh" <<'SH'
#!/usr/bin/env bash
case "$1" in
  codex)     printf '{"status":"ok","binding_window":"primary","windows":[{"kind":"primary","used_percent":98.0}]}\n' ;;
  glm)       printf '{"status":"ok","five_hour":{"pct":95.0},"weekly":{"pct":95.0}}\n' ;;
  anthropic) printf '{"status":"ok","accounts":[{"active":true,"account_label":"a","five_hour_pct":30.0,"seven_day_pct":30.0}]}\n' ;;
  *)         printf '{"status":"ok"}\n' ;;
esac
SH
chmod +x "$TMP/quota-live.sh"

# Failing reviewer stub (MODE=partial): writes a mid-stream body with no
# REVIEW_VERDICT, then exits 3 — the exact "nonzero empty reviewer arm" shape
# (no usable verdict either way). MODE=healthy writes a real PASS verdict
# padded past the 300-byte body floor so the happy path reaches its gate.
cat > "$TMP/architect.sh" <<'SH'
#!/usr/bin/env bash
role=""; mode="${REVIEW_STUB_MODE:-partial}"
while [[ $# -gt 0 ]]; do case "$1" in --role) role="$2"; shift 2 ;; *) shift ;; esac; done
[[ "$role" == "hack-detect" ]] && exit 0
if [[ "$mode" == "healthy" ]]; then
  printf 'REVIEW_VERDICT: PASS\nREVIEW_FINDINGS: critical=0 high=0 medium=0 low=0\n'
  printf 'Reviewed the diff end to end and found nothing blocking. '
  printf 'This padding exists only so the engine body-persist floor (300 bytes) is cleared '
  printf 'and the run reaches the gate-write path. No correctness problem was identified.\n'
  exit 0
fi
printf 'partial reviewer stream, died before verdict\n'
exit 3
SH
chmod +x "$TMP/architect.sh"

cat > "$TMP/dispatch.sh" <<'SH'
#!/usr/bin/env bash
exit 0
SH
chmod +x "$TMP/dispatch.sh"

# mk_case <task> <fanout> <stub-mode> [inv] -> runs the engine (inv "e" = under
# `bash -e`, the pinned-defect invocation; "plain" = normal), echoes
# "<engine-exit> <handoff-dir>".
mk_case() {
  local task="$1" fanout="$2" mode="$3" inv="${4:-e}"
  local bashflags=()
  [[ "$inv" == "e" ]] && bashflags=(-e)
  local root="$TMP/repo-$task"
  local handoff="$root/docs/handoff/dispatch-$task"
  mkdir -p "$root/.claude/ref" "$handoff"
  cat > "$root/.claude/ref/leadv2-routing.yaml" <<'YAML'
router:
  glm_policy:
    codex_quota_gate:
      review_arm_order: [codex, glm, opus, sonnet]
      review_threshold_pct: 95
      glm_review_threshold_pct: 90
      anthropic_review_threshold_pct: 95
YAML
  printf 'diff --git a/x b/x\n--- a/x\n+++ b/x\n@@ -1 +1 @@\n-old\n+new\n' > "$handoff/review.diff"
  LEADV2_ROUTING_YAML="$root/.claude/ref/leadv2-routing.yaml" \
  GLM_POLICY_QUOTA_LIVE="$TMP/quota-live.sh" \
  LEADV2_DISPATCH_ARCHITECT_BIN="$TMP/architect.sh" \
  LEADV2_DISPATCH_BIN="$TMP/dispatch.sh" \
  LEADV2_REVIEW_FANOUT="$fanout" \
  REVIEW_STUB_MODE="$mode" \
  bash ${bashflags[@]+"${bashflags[@]}"} "$ENGINE" --task "$task" --root "$root" --handoff "$handoff" \
    --diff "$handoff/review.diff" --author glm >/dev/null 2>"$TMP/$task.err"
  local rc=$?
  printf '%s %s' "$rc" "$handoff"
}

rc_of()   { printf '%s' "${1%% *}"; }
dir_of()  { printf '%s' "${1#* }"; }

# ===========================================================================
# CASE 1 — nonzero reviewer arm with a PARTIAL body (infra_worker_died retry
# path). Pre-fix this was the silent death: the parent's bare inline
# run_reviewer_arm aborts under -e, no gate at all, engine exit 3.
# ===========================================================================
C1="$(mk_case FCPARTIAL 1 partial)"; C1_RC="$(rc_of "$C1")"; C1_H="$(dir_of "$C1")"

if [[ -s "$C1_H/review-gate.md" ]]; then
  pass "case1: engine wrote a terminal review-gate.md (rc=${C1_RC})"
  log "--- case1 gate ---"; cat "$C1_H/review-gate.md"; log "-----------------"
  grep -q '^status: blocked$' "$C1_H/review-gate.md" \
    && pass "case1: status is blocked" \
    || fail "case1: status is not blocked: $(sed -n 's/^status: //p' "$C1_H/review-gate.md" | head -n1)"
  grep -q '^reason: provider_error$' "$C1_H/review-gate.md" \
    && pass "case1: reason is provider_error" \
    || fail "case1: reason is not provider_error"
  grep -q '^rc: 3$' "$C1_H/review-gate.md" \
    && pass "case1: gate reports the REAL arm rc (3), not the cat-fallback 1" \
    || fail "case1: gate rc line wrong: $(grep '^rc:' "$C1_H/review-gate.md")"
else
  fail "case1: NO review-gate.md — engine exited silently (rc=${C1_RC}), the exact defect this suite pins"
fi

if [[ -f "$C1_H/review-opus.rc" ]]; then
  _c1_rc="$(cat "$C1_H/review-opus.rc")"
  [[ "$_c1_rc" == "3" ]] \
    && pass "case1: review-opus.rc written and carries the real rc (3)" \
    || fail "case1: review-opus.rc = '$_c1_rc', expected 3"
else
  fail "case1: review-opus.rc was never written (run_reviewer_arm abort bypassed the .rc write)"
fi

[[ "$C1_RC" == "6" ]] \
  && pass "case1: engine exit is the blocked-gate code 6 (not the stub's 3)" \
  || fail "case1: engine exit ${C1_RC}, expected 6"

# ===========================================================================
# CASE 2 — nonzero EMPTY reviewer arms across a 2-arm fan-out. Both arms exit
# 3 with no verdict; every arm must get its .rc and the terminal gate must
# name each failed arm via arm_rc:.
# ===========================================================================
C2="$(mk_case FCEMPTY 2 partial)"; C2_RC="$(rc_of "$C2")"; C2_H="$(dir_of "$C2")"

for _arm in opus sonnet; do
  if [[ -f "$C2_H/review-${_arm}.rc" && "$(cat "$C2_H/review-${_arm}.rc")" == "3" ]]; then
    pass "case2: review-${_arm}.rc written with rc 3"
  else
    fail "case2: review-${_arm}.rc missing or wrong: '$(cat "$C2_H/review-${_arm}.rc" 2>/dev/null)'"
  fi
done

if [[ -s "$C2_H/review-gate.md" ]]; then
  pass "case2: terminal review-gate.md written despite every arm failing (rc=${C2_RC})"
  log "--- case2 gate ---"; cat "$C2_H/review-gate.md"; log "-----------------"
  grep -q '^arm_rc: opus=3,sonnet=3$' "$C2_H/review-gate.md" \
    && pass "case2: gate classifies every failed arm (arm_rc: opus=3,sonnet=3)" \
    || fail "case2: arm_rc line wrong: $(grep '^arm_rc:' "$C2_H/review-gate.md")"
else
  fail "case2: NO review-gate.md — silent exit (rc=${C2_RC})"
fi

[[ "$C2_RC" == "6" ]] \
  && pass "case2: engine exit 6" \
  || fail "case2: engine exit ${C2_RC}, expected 6"

# ===========================================================================
# CASE 3 — happy-path guard (normal invocation, no -e): the || capture must
# not weaken a healthy arm. Run in the production invocation mode.
# ===========================================================================
C3="$(mk_case FCHEALTHY 1 healthy plain)"; C3_RC="$(rc_of "$C3")"; C3_H="$(dir_of "$C3")"

if [[ -s "$C3_H/review-gate.md" ]] && grep -q '^status: pass$' "$C3_H/review-gate.md"; then
  pass "case3: healthy arm still gates status: pass"
else
  fail "case3: healthy arm no longer passes: $(sed -n 's/^status: //p' "$C3_H/review-gate.md" 2>/dev/null | head -n1) (rc=${C3_RC})"
fi

[[ -f "$C3_H/review-opus.rc" && "$(cat "$C3_H/review-opus.rc")" == "0" ]] \
  && pass "case3: review-opus.rc = 0 on the happy path" \
  || fail "case3: review-opus.rc missing/nonzero on happy path"

[[ "$C3_RC" == "0" ]] \
  && pass "case3: engine exit 0" \
  || fail "case3: engine exit ${C3_RC}, expected 0"

# ===========================================================================
# CASE 4 — REVIEW-TERMINAL-PASS-01: a HEALTHY no-findings review under the
# `bash -e` invocation. The engine sets its own `set -uo pipefail`, so under
# a caller's -e a no-match `grep '^FINDING:' | while` and a no-match
# `$(grep -oE ... | wc -l | tr ...)` assignment both return 1 (pipefail)
# and errexit-abort the engine BEFORE the terminal pass review-gate.md is
# written. Pre-fix: engine exit 1, no gate. Pinned contract: exit 0 and
# status: pass, same as the plain invocation in case 3.
# ===========================================================================
C4="$(mk_case FCPASSE 1 healthy e)"; C4_RC="$(rc_of "$C4")"; C4_H="$(dir_of "$C4")"

if [[ -s "$C4_H/review-gate.md" ]] && grep -q '^status: pass$' "$C4_H/review-gate.md"; then
  pass "case4: healthy no-findings review under bash -e writes status: pass review-gate.md"
else
  fail "case4: no pass gate under bash -e: $(sed -n 's/^status: //p' "$C4_H/review-gate.md" 2>/dev/null | head -n1) (rc=${C4_RC}) — no-match grep pipeline aborted the engine before the terminal write"
fi

[[ -f "$C4_H/review-opus.rc" && "$(cat "$C4_H/review-opus.rc")" == "0" ]] \
  && pass "case4: review-opus.rc = 0 under bash -e" \
  || fail "case4: review-opus.rc missing/nonzero under bash -e: '$(cat "$C4_H/review-opus.rc" 2>/dev/null)'"

[[ "$C4_RC" == "0" ]] \
  && pass "case4: engine exit 0 under bash -e" \
  || fail "case4: engine exit ${C4_RC} under bash -e, expected 0"

log "PASS=$PASS FAIL=$FAIL"
[[ "$FAIL" -eq 0 ]]
