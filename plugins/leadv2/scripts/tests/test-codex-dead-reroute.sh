#!/usr/bin/env bash
# tests/test-codex-dead-reroute.sh — QUOTA-GATE-PARITY-01 deliverable 3
#
# With a codex quota-cache fixture reporting limit_reached=true (null pct), the
# review-pool resolver (lib/leadv2-glm-policy-resolve.py --review-pool) must
# resolve codex:blocked:100 and hand the review to the next :ok: arm, AND the
# shared lib/leadv2-review-reroute-note.sh helper must emit exactly one
# `codex_dead_reroute` line for that pool -- asserted once against the helper
# directly (its output is byte-identical regardless of which of the two call
# sites invokes it) and then confirmed present at BOTH call sites
# (leadv2-review-run.sh, leadv2-dispatch-product-close.sh) by source inspection,
# since the mission-noted risk is exactly that one of the two independent
# copies gets the emit and the other doesn't.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
RESOLVE_PY="${SCRIPTS_ROOT}/lib/leadv2-glm-policy-resolve.py"
REROUTE_LIB="${SCRIPTS_ROOT}/lib/leadv2-review-reroute-note.sh"
ROUTING_YAML="${SCRIPTS_ROOT}/../config/leadv2-routing.yaml"
REVIEW_RUN_SH="${SCRIPTS_ROOT}/leadv2-review-run.sh"
PRODUCT_CLOSE_SH="${SCRIPTS_ROOT}/leadv2-dispatch-product-close.sh"

PASS=0; FAIL=0; ERRORS=()
log()  { printf -- '[TEST] %s\n' "$*"; }
pass() { PASS=$((PASS + 1)); log "PASS: $1"; }
fail() { FAIL=$((FAIL + 1)); ERRORS+=("FAIL: $1"); log "FAIL: $1 -- ${2:-}"; }

tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT

if bash -n "$REROUTE_LIB"; then pass "bash -n clean (lib/leadv2-review-reroute-note.sh)"; else fail "bash -n reroute lib"; fi
if python3 -m py_compile "$RESOLVE_PY"; then pass "py_compile clean (lib/leadv2-glm-policy-resolve.py)"; else fail "py_compile resolve.py"; fi

# ── fake quota-live: codex limit_reached with null pct; glm/anthropic ok ────
FAKE_LIVE="${tmp}/fake-live.sh"
cat > "$FAKE_LIVE" <<'EOF'
#!/usr/bin/env bash
case "${1:-}" in
  codex) printf '{"status":"ok","binding_window":"weekly","windows":[{"kind":"weekly","limit_reached":true,"used_percent":null}]}' ;;
  glm) printf '{"status":"ok","five_hour":{"pct":10},"weekly":{"pct":10}}' ;;
  anthropic) printf '{"status":"ok","accounts":[{"active":true,"seven_day_pct":10,"five_hour_pct":10}]}' ;;
  *) printf '{"status":"unknown"}' ;;
esac
exit 0
EOF
chmod +x "$FAKE_LIVE"

LOCKOUT_DIR="${tmp}/lockout"; mkdir -p "$LOCKOUT_DIR"

resolver_out="$(LEADV2_QUOTA_LOCKOUT_DIR="$LOCKOUT_DIR" python3 "$RESOLVE_PY" \
  --routing-yaml "$ROUTING_YAML" --job review --base-arm codex --review-pool \
  --author sonnet --signals '{}' --quota-live "$FAKE_LIVE" 2>&1)"
reviewer="$(sed -n 's/^reviewer=//p' <<<"$resolver_out" | head -1)"
pool="$(sed -n 's/^pool=//p' <<<"$resolver_out" | head -1)"

if grep -q 'codex:blocked:100' <<<"$pool"; then
  pass "resolver: codex limit_reached (null pct) -> codex:blocked:100 in pool"
else
  fail "resolver codex disposition" "pool=${pool} out=${resolver_out}"
fi

if [[ -n "$reviewer" && "$reviewer" != "codex" ]]; then
  pass "resolver: reviewer rerouted away from dead codex (reviewer=${reviewer})"
else
  fail "resolver reviewer reroute" "reviewer=${reviewer} pool=${pool}"
fi

# ── shared reroute-note helper: exactly one codex_dead_reroute line ─────────
source "$REROUTE_LIB"
note="$(leadv2_review_reroute_note dispatch-test123 "$pool" "$reviewer")"
if grep -q "^codex_dead_reroute task=dispatch-test123 from=codex to=${reviewer} codex=codex:blocked:100" <<<"$note"; then
  pass "reroute-note: emits codex_dead_reroute naming dead codex + new reviewer"
else
  fail "reroute-note content" "note=${note}"
fi
if [[ "$(wc -l <<<"$note" | tr -d ' ')" == "1" ]]; then
  pass "reroute-note: exactly one line"
else
  fail "reroute-note line count" "note=${note}"
fi

# ── silent when codex is healthy (no false positives) ───────────────────────
healthy_note="$(leadv2_review_reroute_note dispatch-test123 "codex:ok:5,glm:ok:10" "codex")"
if [[ -z "$healthy_note" ]]; then
  pass "reroute-note: silent when codex is the (healthy) reviewer"
else
  fail "reroute-note false positive" "note=${healthy_note}"
fi

# ── both independent call sites source the shared lib and call it right
#    after their resolver_out parse (this is the "one of two copies drifts"
#    risk named in the architect prepass §1.4) ───────────────────────────────
if grep -q 'source "\${SCRIPT_DIR}/lib/leadv2-review-reroute-note.sh"' "$REVIEW_RUN_SH" \
   && grep -q 'leadv2_review_reroute_note "\${TASK}" "\${pool}" "\${reviewer}"' "$REVIEW_RUN_SH"; then
  pass "leadv2-review-run.sh: sources + calls the shared reroute-note helper"
else
  fail "leadv2-review-run.sh missing reroute-note wiring"
fi
if grep -q 'source "\${SCRIPT_DIR}/lib/leadv2-review-reroute-note.sh"' "$PRODUCT_CLOSE_SH" \
   && grep -q 'leadv2_review_reroute_note "\${TASK}" "\${pool}" "\${reviewer}"' "$PRODUCT_CLOSE_SH"; then
  pass "leadv2-dispatch-product-close.sh: sources + calls the shared reroute-note helper"
else
  fail "leadv2-dispatch-product-close.sh missing reroute-note wiring"
fi
if bash -n "$REVIEW_RUN_SH"; then pass "bash -n clean (leadv2-review-run.sh)"; else fail "bash -n review-run.sh"; fi
if bash -n "$PRODUCT_CLOSE_SH"; then pass "bash -n clean (leadv2-dispatch-product-close.sh)"; else fail "bash -n product-close.sh"; fi

echo
echo "=== ${PASS} passed, ${FAIL} failed ==="
if [[ ${FAIL} -gt 0 ]]; then
  printf '%s\n' "${ERRORS[@]}"
  exit 1
fi
exit 0
