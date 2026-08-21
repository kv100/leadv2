#!/usr/bin/env bash
# V3-TIERED-REVIEW-01: machine round-0 must consume builder-selfcheck's
# verdict (HANDOFF/selfcheck.md) and short-circuit to a FAIL review-gate.md
# BEFORE any LLM round is spawned when selfcheck already found the diff
# fails mechanics (verdict: RED). A stub LLM arm (architect.sh) that would
# fail the test if invoked proves the LLM round was never paid for.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SCRIPTS_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
ENGINE="$SCRIPTS_ROOT/leadv2-review-run.sh"

PASS=0; FAIL=0
log()  { printf '%s\n' "$*"; }
pass() { log "PASS: $*"; PASS=$((PASS + 1)); }
fail() { log "FAIL: $*"; FAIL=$((FAIL + 1)); }

bash -n "$SCRIPT_DIR/test-review-machine-round0.sh" 2>/dev/null || { echo "ERROR: self syntax check failed"; exit 1; }

if [[ ! -f "$ENGINE" ]]; then
  fail "leadv2-review-run.sh does not exist"
  log "PASS=$PASS FAIL=$FAIL"; exit 1
fi
if ! grep -q "LEADV2_REVIEW_MACHINE_ROUND0" "$ENGINE" 2>/dev/null; then
  fail "round-0 machine gate not found in $ENGINE (not yet wired, or renamed)"
  log "PASS=$PASS FAIL=$FAIL"; exit 1
fi

setup_fixture() {  # <name> -> stdout: HANDOFF path; sets ROOT/DIFF via globals below
  local name="$1"
  ROOT="$TMP/$name/repo"
  mkdir -p "$ROOT/.claude/ref"
  HANDOFF="$ROOT/docs/handoff/dispatch-RND0$name"
  mkdir -p "$HANDOFF"
  DIFF="$HANDOFF/review.diff"
  printf 'diff --git a/x b/x\n+hello\n' > "$DIFF"
  cat > "$ROOT/.claude/ref/leadv2-routing.yaml" <<'YAML'
router:
  glm_policy:
    codex_quota_gate:
      review_arm_order: [glm, sonnet]
      review_threshold_pct: 90
      glm_review_threshold_pct: 90
      anthropic_review_threshold_pct: 95
YAML
}

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT

# A stub LLM arm that FAILS the test if ever invoked -- proves round-0 short-
# circuited before any LLM round was spawned.
poison_arm="$TMP/architect-poison.sh"
cat > "$poison_arm" <<'SH'
#!/usr/bin/env bash
role=""
while [[ $# -gt 0 ]]; do case "$1" in --role) role="$2"; shift 2 ;; *) shift ;; esac; done
[[ "$role" == "hack-detect" ]] && exit 0
echo "POISON_ARM_INVOKED" >> "${POISON_MARKER:-/dev/null}"
printf 'REVIEW_VERDICT: PASS\nREVIEW_FINDINGS: critical=0 high=0 medium=0 low=0\n'
SH
chmod +x "$poison_arm"

dispatch_stub="$TMP/dispatch.sh"
cat > "$dispatch_stub" <<'SH'
#!/usr/bin/env bash
exit 0
SH
chmod +x "$dispatch_stub"

# --- Case 1 (RED-must-catch): selfcheck.md verdict RED, diff_hash bound to
# the CURRENT diff -> engine must FAIL fast at round 0, write review-gate.md
# status=fail, and never invoke the poison arm.
setup_fixture "red"
red_hash="$(shasum -a 256 "$DIFF" | awk '{print $1}')"
printf '# builder selfcheck\nchecks: 3   failed: 1   skipped: 0\ndiff_hash: %s\n\nverdict: RED\n' "$red_hash" > "$HANDOFF/selfcheck.md"
poison_marker="$TMP/poison-red.marker"
rm -f "$poison_marker"

LEADV2_ROUTING_YAML="$ROOT/.claude/ref/leadv2-routing.yaml" \
LEADV2_DISPATCH_ARCHITECT_BIN="$poison_arm" \
LEADV2_DISPATCH_BIN="$dispatch_stub" \
LEADV2_REVIEW_FANOUT=2 \
POISON_MARKER="$poison_marker" \
bash "$ENGINE" --task RND0red --root "$ROOT" --handoff "$HANDOFF" --diff "$DIFF" --author codex >/dev/null 2>&1
rc=$?

status_line="$(sed -n 's/^status:[[:space:]]*//p' "$HANDOFF/review-gate.md" 2>/dev/null | head -n1)"
if [[ "$rc" -eq 7 && "$status_line" == "fail" && ! -f "$poison_marker" ]]; then
  pass "selfcheck RED -> rc=7, review-gate.md status=fail, LLM arm never invoked"
else
  fail "expected rc=7 status=fail no-LLM-invocation; got rc=$rc status='$status_line' poison_marker_exists=$([[ -f "$poison_marker" ]] && echo yes || echo no)"
fi
if grep -q 'reason: selfcheck_red_round0' "$HANDOFF/review-gate.md" 2>/dev/null; then
  pass "review-gate.md carries reason=selfcheck_red_round0"
else
  fail "review-gate.md missing reason=selfcheck_red_round0"
fi

# --- Case 2 (must NOT false-positive): selfcheck.md verdict GREEN -> engine
# must proceed to the LLM round (poison arm IS invoked here, deliberately --
# it is a normal arm in this case, not poison).
setup_fixture "green"
printf '# builder selfcheck\nchecks: 3   failed: 0   skipped: 0\n\nverdict: GREEN\n' > "$HANDOFF/selfcheck.md"
poison_marker2="$TMP/poison-green.marker"
rm -f "$poison_marker2"

LEADV2_ROUTING_YAML="$ROOT/.claude/ref/leadv2-routing.yaml" \
LEADV2_DISPATCH_ARCHITECT_BIN="$poison_arm" \
LEADV2_DISPATCH_BIN="$dispatch_stub" \
LEADV2_REVIEW_FANOUT=2 \
POISON_MARKER="$poison_marker2" \
bash "$ENGINE" --task RND0green --root "$ROOT" --handoff "$HANDOFF" --diff "$DIFF" --author codex >/dev/null 2>&1
rc2=$?

if [[ -f "$poison_marker2" ]]; then
  pass "selfcheck GREEN -> LLM round still ran (rc=$rc2), round-0 did not false-positive"
else
  fail "selfcheck GREEN wrongly short-circuited the LLM round (rc=$rc2)"
fi

# --- Case 3: no selfcheck.md at all (standalone invocation) -> must fall
# through unchanged, LLM round still runs.
setup_fixture "noartifact"
poison_marker3="$TMP/poison-noartifact.marker"
rm -f "$poison_marker3"

LEADV2_ROUTING_YAML="$ROOT/.claude/ref/leadv2-routing.yaml" \
LEADV2_DISPATCH_ARCHITECT_BIN="$poison_arm" \
LEADV2_DISPATCH_BIN="$dispatch_stub" \
LEADV2_REVIEW_FANOUT=2 \
POISON_MARKER="$poison_marker3" \
bash "$ENGINE" --task RND0noartifact --root "$ROOT" --handoff "$HANDOFF" --diff "$DIFF" --author codex >/dev/null 2>&1
rc3=$?

if [[ -f "$poison_marker3" ]]; then
  pass "no selfcheck.md -> LLM round still ran (rc=$rc3), no regression for standalone invocation"
else
  fail "no selfcheck.md wrongly short-circuited the LLM round (rc=$rc3)"
fi

# --- Case 4 (round-1 HIGH regression, stale-RED/current-diff-mismatch):
# selfcheck.md carries verdict RED but its diff_hash does not match the diff
# under review right now (a RED artifact left over from an earlier close
# attempt on a since-changed, now-healthy diff) -> engine must NOT fail-closed
# from round 0; it must fall through to the normal LLM round.
setup_fixture "stale"
printf '# builder selfcheck\nchecks: 3   failed: 1   skipped: 0\ndiff_hash: 0000000000000000000000000000000000000000000000000000000000000000\n\nverdict: RED\n' > "$HANDOFF/selfcheck.md"
poison_marker4="$TMP/poison-stale.marker"
rm -f "$poison_marker4"

LEADV2_ROUTING_YAML="$ROOT/.claude/ref/leadv2-routing.yaml" \
LEADV2_DISPATCH_ARCHITECT_BIN="$poison_arm" \
LEADV2_DISPATCH_BIN="$dispatch_stub" \
LEADV2_REVIEW_FANOUT=2 \
POISON_MARKER="$poison_marker4" \
bash "$ENGINE" --task RND0stale --root "$ROOT" --handoff "$HANDOFF" --diff "$DIFF" --author codex >/dev/null 2>&1
rc4=$?

if [[ -f "$poison_marker4" ]]; then
  pass "stale-RED (diff_hash mismatch) -> LLM round still ran (rc=$rc4), no fail-closed on unrelated verdict"
else
  fail "stale-RED (diff_hash mismatch) wrongly short-circuited the LLM round (rc=$rc4)"
fi

log ""
log "================================================"
log "  review machine-round0: PASS=$PASS FAIL=$FAIL"
log "================================================"
[[ "$FAIL" -eq 0 ]]
