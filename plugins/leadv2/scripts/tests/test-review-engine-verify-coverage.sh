#!/usr/bin/env bash
# ONE-PATH-EVERYWHERE-01 T2: every Critical/High finding in review-findings.json
# must carry a verifier_verdict (upheld|refuted|unverified — never absent).
# Stubbed providers, no live network. FAILS against a stash of the engine.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SCRIPTS_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
ENGINE="$SCRIPTS_ROOT/leadv2-review-run.sh"

PASS=0; FAIL=0
log()  { printf '%s\n' "$*"; }
pass() { log "PASS: $*"; PASS=$((PASS + 1)); }
fail() { log "FAIL: $*"; FAIL=$((FAIL + 1)); }

bash -n "$SCRIPT_DIR/test-review-engine-verify-coverage.sh" 2>/dev/null || { echo "ERROR: self syntax check failed"; exit 1; }

if [[ ! -f "$ENGINE" ]]; then
  fail "leadv2-review-run.sh does not exist"
  log "PASS=$PASS FAIL=$FAIL"; exit 1
fi

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
ROOT="$TMP/repo"
mkdir -p "$ROOT/.claude/ref"
HANDOFF="$ROOT/docs/handoff/dispatch-T2VERIFY"
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

# codex raises one Critical finding
cat > "$TMP/codex.sh" <<'SH'
#!/usr/bin/env bash
printf 'REVIEW_VERDICT: FAIL\nREVIEW_FINDINGS: critical=1 high=0 medium=0 low=0\n'
printf 'FINDING: severity=Critical file=src/x.py line=10 dimension=correctness desc=off by one\n'
SH
chmod +x "$TMP/codex.sh"

cat > "$TMP/glm.sh" <<'SH'
#!/usr/bin/env bash
out=""
while [[ $# -gt 0 ]]; do case "$1" in --out) out="$2"; shift 2 ;; *) shift ;; esac; done
{
  printf 'REVIEW_VERDICT: PASS_WITH_NITS\nREVIEW_FINDINGS: critical=0 high=0 medium=0 low=0\n'
} > "$out"
SH
chmod +x "$TMP/glm.sh"

# architect stub also serves as the verifier arm for critic role, and as hack-detect (empty)
cat > "$TMP/architect.sh" <<'SH'
#!/usr/bin/env bash
role=""
while [[ $# -gt 0 ]]; do case "$1" in --role) role="$2"; shift 2 ;; *) shift ;; esac; done
if [[ "$role" == "hack-detect" ]]; then
  exit 0
fi
printf 'VERIFY_VERDICT: upheld\n'
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
bash "$ENGINE" --task T2VERIFY --root "$ROOT" --handoff "$HANDOFF" --diff "$DIFF" --author sonnet >/dev/null 2>&1
rc=$?

# rc 7 == FAIL verdict (existing lane contract) — expected here since codex raised Critical.
if [[ $rc -ne 7 ]]; then
  fail "engine exited $rc, expected 7 (FAIL verdict)"
fi

JSON="$HANDOFF/review-findings.json"
if [[ ! -f "$JSON" ]]; then
  fail "review-findings.json missing"
else
  crit_count="$(grep -oE '"severity":"Critical"' "$JSON" | wc -l | tr -d ' ')"
  verdict_count="$(grep -oE '"severity":"Critical"[^}]*"verifier_verdict":"(upheld|refuted|unverified)"' "$JSON" | wc -l | tr -d ' ')"
  if [[ "$crit_count" -ge 1 && "$crit_count" == "$verdict_count" ]]; then
    pass "every Critical finding ($crit_count) carries a verifier_verdict"
  else
    fail "Critical findings=$crit_count, findings-with-verdict=$verdict_count"
  fi
fi

log ""
log "================================================"
log "  review-engine verify-coverage: PASS=$PASS FAIL=$FAIL"
log "================================================"
[[ "$FAIL" -eq 0 ]]
