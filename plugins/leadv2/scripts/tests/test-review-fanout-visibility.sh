#!/usr/bin/env bash
# REVIEW-FANOUT-VISIBILITY-01 (R2, 2026-08-22).
#
# THE DEFECT THIS TEST PINS: when the reviewer pool can only offer 1 live arm,
# leadv2-review-run.sh still fanned out, still computed a "union" verdict, and
# wrote review-gate.md with `arms: opus` and the SAME `status:` line a genuine
# 3-arm union writes. A reader could not tell a 3-opinion gate from a 1-opinion
# gate. That is the lying-green disease: a gate that silently degrades to a
# weaker check while still reporting its strong name.
#
# The engine must therefore state, in the artifact itself, requested-vs-achieved
# fan-out width AND why each missing arm was missing.
#
# Uses the REAL resolver (lib/leadv2-glm-policy-resolve.py) with a stubbed
# --quota-live reader and a stubbed reviewer binary. No network, no provider.
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

# Reviewer stub: stdout becomes review-<arm>.md. Padded past the 300-byte
# body-persist floor so the run reaches the verdict/gate-write path.
cat > "$TMP/architect.sh" <<'SH'
#!/usr/bin/env bash
role=""
while [[ $# -gt 0 ]]; do case "$1" in --role) role="$2"; shift 2 ;; *) shift ;; esac; done
[[ "$role" == "hack-detect" ]] && exit 0
printf 'REVIEW_VERDICT: PASS\nREVIEW_FINDINGS: critical=0 high=0 medium=0 low=0\n'
printf 'Reviewed the diff end to end and found nothing blocking. '
printf 'This padding exists only so the engine body-persist floor (300 bytes) is cleared '
printf 'and the run reaches the gate-write path where the fan-out visibility line is emitted. '
printf 'No correctness, contract, census or evidence problem was identified in this fixture diff.\n'
SH
chmod +x "$TMP/architect.sh"

cat > "$TMP/dispatch.sh" <<'SH'
#!/usr/bin/env bash
exit 0
SH
chmod +x "$TMP/dispatch.sh"

# mk_case <task> <author> <fanout> -> echoes the HANDOFF dir, runs the engine.
mk_case() {
  local task="$1" author="$2" fanout="$3"
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
  bash "$ENGINE" --task "$task" --root "$root" --handoff "$handoff" \
    --diff "$handoff/review.diff" --author "$author" >/dev/null 2>&1
  printf '%s' "$handoff/review-gate.md"
}

# ===========================================================================
# CASE 1 — DEGRADED. author=sonnet, so of [codex, glm, opus, sonnet] only opus
# is :ok:. Requested fan-out 3, achievable 1. This is the exact live shape
# observed on 2026-08-22 (codex 98%, glm 90%, author sonnet -> `arms: opus`).
# ===========================================================================
GATE1="$(mk_case FVDEGRADE sonnet 3)"

if [[ ! -s "$GATE1" ]]; then
  fail "case1: engine wrote no review-gate.md at all"
else
  log "--- case1 gate head ---"; sed -n '1,4p' "$GATE1"; log "-----------------------"

  # Fixture sanity: if this is not a 1-arm run, the whole case proves nothing.
  arms1="$(sed -n 's/^arms:[[:space:]]*//p' "$GATE1" | head -n1)"
  if [[ "$arms1" != "opus" ]]; then
    fail "case1 FIXTURE BROKEN: expected a single-arm run (arms: opus), got 'arms: $arms1'"
  else
    pass "case1 fixture: pool genuinely degraded to one arm (arms: $arms1)"

    fl1="$(sed -n 's/^fanout:[[:space:]]*//p' "$GATE1" | head -n1)"
    if [[ -z "$fl1" ]]; then
      fail "case1: review-gate.md carries NO 'fanout:' line — a 1-of-3 arm gate is indistinguishable from a full 3-arm union"
    else
      pass "case1: fanout line present: $fl1"

      case "$fl1" in
        "1/3 "*) pass "case1: fanout states achieved/requested = 1/3" ;;
        *) fail "case1: fanout line does not open with '1/3' (got: $fl1)" ;;
      esac
      case "$fl1" in
        *"degraded=true"*) pass "case1: degraded=true" ;;
        *) fail "case1: degraded flag is not true (got: $fl1)" ;;
      esac
      case "$fl1" in
        *"pool_ok=1"*) pass "case1: pool_ok=1 recorded" ;;
        *) fail "case1: pool_ok not reported as 1 (got: $fl1)" ;;
      esac
      case "$fl1" in
        *"reason=pool_offered_1_ok_arms"*) pass "case1: reason names the pool as the cause" ;;
        *) fail "case1: reason does not name pool width (got: $fl1)" ;;
      esac
      # Every excluded arm must be named WITH its disposition, not just omitted.
      for want in "codex=blocked:98" "glm=blocked:95" "sonnet=author"; do
        case "$fl1" in
          *"$want"*) pass "case1: excluded arm named with reason: $want" ;;
          *) fail "case1: excluded arm '$want' missing from fanout line (got: $fl1)" ;;
        esac
      done
    fi

    if grep -q '^fanout_degraded:' "$GATE1"; then
      pass "case1: explicit human-readable fanout_degraded: line present"
      if grep -q '^fanout_degraded:.*WEAKER' "$GATE1"; then
        pass "case1: fanout_degraded line says the gate is WEAKER than its name"
      else
        fail "case1: fanout_degraded line does not state the check is weaker"
      fi
    else
      fail "case1: no 'fanout_degraded:' line — degradation is not stated in plain words"
    fi

    # Contract regression: the pre-existing additive lines must survive byte-shape.
    grep -q '^arms: opus$' "$GATE1"   && pass "case1: 'arms:' line contract unchanged" \
                                      || fail "case1: 'arms:' line contract changed"
    grep -q '^verified: ' "$GATE1"    && pass "case1: 'verified:' line still emitted" \
                                      || fail "case1: 'verified:' line lost"
    grep -q '^status: ' "$GATE1"      && pass "case1: 'status:' line still emitted" \
                                      || fail "case1: 'status:' line lost"
  fi
fi

# ===========================================================================
# CASE 2 — NOT DEGRADED. author=glm, so opus AND sonnet are both :ok:.
# Requested fan-out 2, achieved 2. The engine must NOT cry degradation on a
# healthy run — a warning that always fires is a warning nobody reads.
# ===========================================================================
GATE2="$(mk_case FVHEALTHY glm 2)"

if [[ ! -s "$GATE2" ]]; then
  fail "case2: engine wrote no review-gate.md at all"
else
  log "--- case2 gate head ---"; sed -n '1,4p' "$GATE2"; log "-----------------------"
  arms2="$(sed -n 's/^arms:[[:space:]]*//p' "$GATE2" | head -n1)"
  if [[ "$arms2" != "opus,sonnet" ]]; then
    fail "case2 FIXTURE BROKEN: expected a two-arm run (arms: opus,sonnet), got 'arms: $arms2'"
  else
    pass "case2 fixture: two arms genuinely ran (arms: $arms2)"
    fl2="$(sed -n 's/^fanout:[[:space:]]*//p' "$GATE2" | head -n1)"
    if [[ -z "$fl2" ]]; then
      fail "case2: review-gate.md carries NO 'fanout:' line"
    else
      pass "case2: fanout line present: $fl2"
      case "$fl2" in
        "2/2 "*"degraded=false"*) pass "case2: healthy run reports 2/2 degraded=false" ;;
        *) fail "case2: healthy run did not report '2/2 ... degraded=false' (got: $fl2)" ;;
      esac
    fi
    if grep -q '^fanout_degraded:' "$GATE2"; then
      fail "case2: fanout_degraded: line emitted on a HEALTHY full-width run (false alarm)"
    else
      pass "case2: no false fanout_degraded: alarm on a full-width run"
    fi
  fi
fi

# ===========================================================================
# CASE 3 — FLOOR-SOURCED ARM, unit level. When every arm is quota-blocked or
# author-excluded, the resolver falls to its emergency rank-table floor and
# appends `<arm>:floor:<pct|degraded>` — an arm that bypassed lockout AND quota
# gating entirely. Such a reviewer must NOT read as identical to a healthy
# quota-cleared one, so the fan-out line reports source=floor.
#
# Driving the floor end-to-end needs a full ladder/rank-table fixture, so this
# case exercises the SHIPPED helper bytes directly: both functions are extracted
# verbatim from the engine with awk and sourced, then run against a synthetic
# ${pool}. This is the shipped source, not a copy maintained in the test.
# ===========================================================================
HELPERS="$TMP/helpers.sh"
{
  awk '/^_engine_pool_excluded\(\) \{/,/^\}/' "$ENGINE"
  awk '/^_engine_arm_from_floor\(\) \{/,/^\}/' "$ENGINE"
} > "$HELPERS"

if [[ ! -s "$HELPERS" ]] || ! grep -q '^_engine_arm_from_floor()' "$HELPERS"; then
  fail "case3: engine exposes no _engine_arm_from_floor / _engine_pool_excluded helpers to extract"
else
  pass "case3: helpers extracted from the shipped engine source"
  # shellcheck source=/dev/null
  source "$HELPERS"

  pool="codex:blocked:98,glm:blocked:90,opus:floor:degraded,sonnet:author:"
  if _engine_arm_from_floor opus; then
    pass "case3: floor-sourced arm detected (opus:floor:degraded)"
  else
    fail "case3: floor-sourced arm NOT detected — a quota-bypassing reviewer would read as healthy"
  fi
  if _engine_arm_from_floor sonnet; then
    fail "case3: non-floor arm falsely reported as floor-sourced"
  else
    pass "case3: non-floor arm not falsely flagged"
  fi

  got3="$(_engine_pool_excluded "opus")"
  if [[ "$got3" == "codex=blocked:98,glm=blocked:90,sonnet=author" ]]; then
    pass "case3: excluded rendering exact ($got3)"
  else
    fail "case3: excluded rendering wrong — want 'codex=blocked:98,glm=blocked:90,sonnet=author', got '$got3'"
  fi

  # An arm that DID run must never appear in the excluded list.
  case "$(_engine_pool_excluded "opus,sonnet")" in
    *sonnet*) fail "case3: a ran arm leaked into the excluded list" ;;
    *) pass "case3: ran arms are excluded from the excluded list" ;;
  esac
fi

log ""
log "================================================"
log "  review fanout visibility: PASS=$PASS FAIL=$FAIL"
log "================================================"
[[ "$FAIL" -eq 0 ]]
