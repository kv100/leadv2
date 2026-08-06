#!/usr/bin/env bash
# ONE-PATH-EVERYWHERE-01 T3: for every verified finding, verifier_arm != arm
# (a finding's raiser can never be its own verifier). INVARIANT per design §2
# step 7. Stubbed providers, no live network. FAILS against a stash of the engine.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SCRIPTS_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
ENGINE="$SCRIPTS_ROOT/leadv2-review-run.sh"

PASS=0; FAIL=0
log()  { printf '%s\n' "$*"; }
pass() { log "PASS: $*"; PASS=$((PASS + 1)); }
fail() { log "FAIL: $*"; FAIL=$((FAIL + 1)); }

bash -n "$SCRIPT_DIR/test-review-engine-verifier-distinct-arm.sh" 2>/dev/null || { echo "ERROR: self syntax check failed"; exit 1; }

if [[ ! -f "$ENGINE" ]]; then
  fail "leadv2-review-run.sh does not exist"
  log "PASS=$PASS FAIL=$FAIL"; exit 1
fi

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
ROOT="$TMP/repo"
mkdir -p "$ROOT/.claude/ref"
HANDOFF="$ROOT/docs/handoff/dispatch-T3DISTINCT"
mkdir -p "$HANDOFF"
DIFF="$HANDOFF/review.diff"
printf 'diff --git a/x b/x\n+hello\n' > "$DIFF"

cat > "$TMP/resolver.py" <<'PY'
#!/usr/bin/env python3
print("reviewer=codex")
print("pool=codex:ok:,glm:ok:,sonnet:ok:")
print("refusal=")
PY
chmod +x "$TMP/resolver.py"

cat > "$TMP/codex.sh" <<'SH'
#!/usr/bin/env bash
printf 'REVIEW_VERDICT: FAIL\nREVIEW_FINDINGS: critical=0 high=1 medium=0 low=0\n'
printf 'FINDING: severity=High file=src/y.py line=5 dimension=correctness desc=race condition\n'
SH
chmod +x "$TMP/codex.sh"

cat > "$TMP/glm.sh" <<'SH'
#!/usr/bin/env bash
out=""
while [[ $# -gt 0 ]]; do case "$1" in --out) out="$2"; shift 2 ;; *) shift ;; esac; done
printf 'REVIEW_VERDICT: PASS\nREVIEW_FINDINGS: critical=0 high=0 medium=0 low=0\n' > "$out"
SH
chmod +x "$TMP/glm.sh"

cat > "$TMP/architect.sh" <<'SH'
#!/usr/bin/env bash
role=""
while [[ $# -gt 0 ]]; do case "$1" in --role) role="$2"; shift 2 ;; *) shift ;; esac; done
[[ "$role" == "hack-detect" ]] && exit 0
printf 'VERIFY_VERDICT: refuted\n'
SH
chmod +x "$TMP/architect.sh"

cat > "$TMP/dispatch.sh" <<'SH'
#!/usr/bin/env bash
exit 0
SH
chmod +x "$TMP/dispatch.sh"

LEADV2_GLM_POLICY_RESOLVER="$TMP/resolver.py" \
LEADV2_DISPATCH_CODEX_BIN="$TMP/codex.sh" \
LEADV2_DISPATCH_GLM_BIN="$TMP/glm.sh" \
LEADV2_DISPATCH_ARCHITECT_BIN="$TMP/architect.sh" \
LEADV2_DISPATCH_BIN="$TMP/dispatch.sh" \
LEADV2_REVIEW_FANOUT=2 \
bash "$ENGINE" --task T3DISTINCT --root "$ROOT" --handoff "$HANDOFF" --diff "$DIFF" --author sonnet >/dev/null 2>&1

JSON="$HANDOFF/review-findings.json"
if [[ ! -f "$JSON" ]]; then
  fail "review-findings.json missing"
  log "PASS=$PASS FAIL=$FAIL"; exit 1
fi

violation="$(python3 - "$JSON" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
bad = [f for f in d.get("findings", [])
       if f.get("verifier_verdict") in ("upheld", "refuted") and f.get("verifier_arm") == f.get("arm")]
print(len(bad))
PY
)"

if [[ "$violation" == "0" ]]; then
  pass "no verified finding has verifier_arm == arm"
else
  fail "$violation finding(s) have verifier_arm == arm"
fi

log ""
log "================================================"
log "  review-engine verifier-distinct-arm: PASS=$PASS FAIL=$FAIL"
log "================================================"
[[ "$FAIL" -eq 0 ]]
