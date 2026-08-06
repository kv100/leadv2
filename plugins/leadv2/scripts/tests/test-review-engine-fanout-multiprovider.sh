#!/usr/bin/env bash
# ONE-PATH-EVERYWHERE-01 T1: fan-out must include >=2 DISTINCT providers, not
# 2 Claude models wearing different names. Stubs codex/glm/architect provider
# bins; no live provider/network calls. FAILS against a stash of the engine
# (i.e. against main, which has no leadv2-review-run.sh at all).
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SCRIPTS_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
ENGINE="$SCRIPTS_ROOT/leadv2-review-run.sh"

PASS=0; FAIL=0
log()  { printf '%s\n' "$*"; }
pass() { log "PASS: $*"; PASS=$((PASS + 1)); }
fail() { log "FAIL: $*"; FAIL=$((FAIL + 1)); }

bash -n "$SCRIPT_DIR/test-review-engine-fanout-multiprovider.sh" 2>/dev/null || { echo "ERROR: self syntax check failed"; exit 1; }

if [[ ! -f "$ENGINE" ]]; then
  fail "leadv2-review-run.sh does not exist"
  log "PASS=$PASS FAIL=$FAIL"; exit 1
fi

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
ROOT="$TMP/repo"
mkdir -p "$ROOT/.claude/ref"
HANDOFF="$ROOT/docs/handoff/dispatch-T1FANOUT"
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
printf 'REVIEW_VERDICT: PASS\nREVIEW_FINDINGS: critical=0 high=0 medium=0 low=0\n'
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
printf 'REVIEW_VERDICT: PASS\nREVIEW_FINDINGS: critical=0 high=0 medium=0 low=0\n'
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
bash "$ENGINE" --task T1FANOUT --root "$ROOT" --handoff "$HANDOFF" --diff "$DIFF" --author sonnet >/dev/null 2>&1
rc=$?

if [[ $rc -ne 0 ]]; then
  fail "engine exited $rc, expected 0"
else
  arms_line="$(sed -n 's/^arms:[[:space:]]*//p' "$HANDOFF/review-gate.md" 2>/dev/null | head -n1)"
  distinct_count="$(printf '%s\n' "$arms_line" | tr ',' '\n' | grep -v '^$' | sort -u | wc -l | tr -d ' ')"
  # Must NOT be two Claude models (sonnet/opus) — codex+glm are both non-Anthropic.
  if [[ "$distinct_count" -ge 2 ]] && ! printf '%s' "$arms_line" | grep -qE '^(sonnet|opus),(sonnet|opus)$'; then
    pass "arms: line has >=2 distinct providers ($arms_line)"
  else
    fail "arms line does not show >=2 distinct providers: '$arms_line'"
  fi
fi

log ""
log "================================================"
log "  review-engine fan-out multiprovider: PASS=$PASS FAIL=$FAIL"
log "================================================"
[[ "$FAIL" -eq 0 ]]
