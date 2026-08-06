#!/usr/bin/env bash
# ONE-PATH-EVERYWHERE-01 T4 (risk A5 / m3-market rollout blocker, mandatory):
# codex_enabled=false (codex absent from review_arm_order, m3-market shape) +
# GLM over its quota band must still produce a NON-EMPTY pool — i.e. the engine
# must NOT collapse to all_arms_unavailable just because codex+glm are both out.
# Uses the REAL resolver script (leadv2-glm-policy-resolve.py), not a stub, with
# a stubbed --quota-live reader — no live provider/network calls.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SCRIPTS_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
ENGINE="$SCRIPTS_ROOT/leadv2-review-run.sh"
RESOLVER="$SCRIPTS_ROOT/lib/leadv2-glm-policy-resolve.py"

PASS=0; FAIL=0
log()  { printf '%s\n' "$*"; }
pass() { log "PASS: $*"; PASS=$((PASS + 1)); }
fail() { log "FAIL: $*"; FAIL=$((FAIL + 1)); }

bash -n "$SCRIPT_DIR/test-review-engine-pool-degrades.sh" 2>/dev/null || { echo "ERROR: self syntax check failed"; exit 1; }

if [[ ! -f "$ENGINE" ]]; then
  fail "leadv2-review-run.sh does not exist"
  log "PASS=$PASS FAIL=$FAIL"; exit 1
fi

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
ROOT="$TMP/repo"
mkdir -p "$ROOT/.claude/ref"
HANDOFF="$ROOT/docs/handoff/dispatch-T4DEGRADE"
mkdir -p "$HANDOFF"
DIFF="$HANDOFF/review.diff"
printf 'diff --git a/x b/x\n+hello\n' > "$DIFF"

# m3-market shape: codex is NOT in review_arm_order (codex_enabled=false), glm
# over its 90pct review band, sonnet reads unknown (fails open -> eligible).
cat > "$ROOT/.claude/ref/leadv2-routing.yaml" <<'YAML'
router:
  glm_policy:
    codex_quota_gate:
      review_arm_order: [glm, sonnet]
      review_threshold_pct: 90
      glm_review_threshold_pct: 90
      anthropic_review_threshold_pct: 95
YAML

cat > "$TMP/quota-live.sh" <<'SH'
#!/usr/bin/env bash
case "$1" in
  glm) printf '{"status":"ok","five_hour":{"pct":95.0},"weekly":{"pct":95.0}}\n' ;;
  anthropic) printf '{"status":"ok"}\n' ;;
  *) printf '{"status":"ok"}\n' ;;
esac
SH
chmod +x "$TMP/quota-live.sh"

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

# Sanity: confirm the real resolver's pool is non-empty for this shape (author=codex,
# so codex's own absence from the order doesn't self-exclude — mirrors an m3-market
# author dispatching without a codex arm at all).
resolver_out="$(python3 "$RESOLVER" --routing-yaml "$ROOT/.claude/ref/leadv2-routing.yaml" \
  --job review --base-arm codex --review-pool --author codex --signals '{}' \
  --quota-live "$TMP/quota-live.sh")"
pool_line="$(printf '%s\n' "$resolver_out" | sed -n 's/^pool=//p')"
if [[ -z "$pool_line" ]]; then
  fail "resolver itself returned an empty pool for the m3-market fixture — test fixture is broken"
  log "PASS=$PASS FAIL=$FAIL"; exit 1
fi
pass "resolver pool non-empty for m3-market shape: $pool_line"

LEADV2_ROUTING_YAML="$ROOT/.claude/ref/leadv2-routing.yaml" \
GLM_POLICY_QUOTA_LIVE="$TMP/quota-live.sh" \
LEADV2_DISPATCH_ARCHITECT_BIN="$TMP/architect.sh" \
LEADV2_DISPATCH_BIN="$TMP/dispatch.sh" \
LEADV2_REVIEW_FANOUT=2 \
bash "$ENGINE" --task T4DEGRADE --root "$ROOT" --handoff "$HANDOFF" --diff "$DIFF" --author codex >/dev/null 2>&1
rc=$?

if [[ $rc -eq 9 ]]; then
  fail "engine exited 9 (all_arms_unavailable) despite a non-empty degraded pool"
else
  status_line="$(sed -n 's/^status:[[:space:]]*//p' "$HANDOFF/review-gate.md" 2>/dev/null | head -n1)"
  if [[ "$status_line" == "unreviewed" ]]; then
    fail "review-gate.md status=unreviewed on a degraded-but-non-empty pool"
  else
    pass "engine produced status=$status_line (rc=$rc) on degraded pool, not all_arms_unavailable"
  fi
fi

log ""
log "================================================"
log "  review-engine pool-degrades: PASS=$PASS FAIL=$FAIL"
log "================================================"
[[ "$FAIL" -eq 0 ]]
