#!/usr/bin/env bash
# tests/test-supervise-sentinel-readonly.sh — SENTINEL-ON-PROBE-01
# Asserts the `.supervise-active` sentinel is written ONLY on entry/attach, never
# by read-only probes (--json / --since / --print). A probe must neither CREATE
# the sentinel nor REFRESH an existing one's content/mtime.
# Usage: bash tests/test-supervise-sentinel-readonly.sh
# Exit 0 = all pass; non-zero = failure count
set -euo pipefail

SUP="${BASH_SOURCE[0]%/*}/../scripts/leadv2-supervise.sh"
PASS=0
FAIL=0

pass() { echo "PASS: $1"; PASS=$(( PASS + 1 )); }
fail() { echo "FAIL: $1"; FAIL=$(( FAIL + 1 )); }

# ── Sandbox: scratch repo (no remote ⇒ not a real-checkout for the state-path
# safety net) + an isolated control-plane root. Every call threads both
# LEADV2_PROJECT_ROOT and LEADV2_STATE_ROOT so nothing escapes to a real repo.
TMP_DIR="$(mktemp -d)"
cleanup() { rm -rf "$TMP_DIR"; }
trap cleanup EXIT

REPO_DIR="${TMP_DIR}/repo"
mkdir -p "$REPO_DIR"
(cd "$REPO_DIR" && git init -q && git config user.email t@t.com && git config user.name t && git commit -q --allow-empty -m init)

STATE_DIR="${TMP_DIR}/state"
mkdir -p "$STATE_DIR"
SENTINEL="${STATE_DIR}/.supervise-active"

run_supervise() {
  # Probes/entry may legitimately exit non-zero downstream (no active.yaml etc);
  # the SENTINEL side effect is what we assert, so tolerate any exit code.
  LEADV2_PROJECT_ROOT="$REPO_DIR" LEADV2_STATE_ROOT="$STATE_DIR" \
    bash "$SUP" "$@" >/dev/null 2>&1 || true
}

# Expected durable pid that supervise.sh will stamp when run as a direct child
# of THIS test shell (its $PPID = $$). Reproduces _lv2_durable_pid's ancestor
# walk from $$ so it is correct both standalone and nested in a live Claude
# session (where the walk finds the outer claude process).
expected_pid() {
  python3 - "$$" <<'PYEOF'
import sys, subprocess
def ppid_of(pid):
    try:
        r = subprocess.run(['ps','-o','ppid=','-p',str(pid)],capture_output=True,text=True,timeout=2)
        s=r.stdout.strip(); return int(s) if s else None
    except Exception: return None
def comm_of(pid):
    try:
        r = subprocess.run(['ps','-o','comm=','-p',str(pid)],capture_output=True,text=True,timeout=2)
        return r.stdout.strip().split('/')[-1].lower()
    except Exception: return ''
pid=int(sys.argv[1]); seen=set()
while pid and pid>1 and pid not in seen:
    seen.add(pid)
    if 'claude' in comm_of(pid): print(pid,end=''); sys.exit(0)
    nxt=ppid_of(pid)
    if nxt is None or nxt==pid or nxt==1: break
    pid=nxt
print(pid,end='')
PYEOF
}

# ── bash -n syntax gate ────────────────────────────────────────────────────
if bash -n "$SUP" 2>/dev/null; then pass "bash -n syntax"; else fail "bash -n syntax"; fi

# ── Case 1: --json creates no sentinel in a fresh sandbox ──────────────────
rm -f "$SENTINEL"
run_supervise --json
if [[ ! -e "$SENTINEL" ]]; then
  pass "case1: --json leaves no sentinel"
else
  fail "case1: --json wrote a sentinel"
fi

# ── Case 2: --json preserves a pre-seeded sentinel (content + mtime) ───────
rm -f "$SENTINEL"
SEED='{"pid": 999999, "started_at": "1999-01-01T00:00:00Z", "mode": "interactive-lanes"}'
printf '%s' "$SEED" > "$SENTINEL"
SEED_BEFORE="$(cat "$SENTINEL")"
# Set mtime to a fixed old value, then read it back.
touch -t 200001010000.00 "$SENTINEL"
MTIME_BEFORE="$(stat -f '%m' "$SENTINEL")"
run_supervise --json
MTIME_AFTER="$(stat -f '%m' "$SENTINEL" 2>/dev/null || echo MISSING)"
SEED_AFTER="$(cat "$SENTINEL" 2>/dev/null || echo MISSING)"
if [[ "$SEED_BEFORE" == "$SEED_AFTER" && "$MTIME_BEFORE" == "$MTIME_AFTER" ]]; then
  pass "case2: --json preserves seeded sentinel content+mtime"
else
  fail "case2: --json mutated seeded sentinel (mtime ${MTIME_BEFORE}->${MTIME_AFTER}, content changed=$([[ "$SEED_BEFORE" != "$SEED_AFTER" ]] && echo yes || echo no))"
fi

# ── Case 3: entry path writes sentinel with caller pid + valid JSON ────────
rm -f "$SENTINEL"
EXPID="$(expected_pid)"
run_supervise --enter
if [[ ! -f "$SENTINEL" ]]; then
  fail "case3: --enter did not create sentinel"
else
  VALID=$(python3 - "$SENTINEL" "$EXPID" <<'PYEOF' || echo 0
import json, sys, os
path, expid = sys.argv[1], sys.argv[2]
try:
    with open(path) as fh:
        d = json.load(fh)
except Exception:
    print(0); sys.exit(0)
ok = ("pid" in d and "started_at" in d and "mode" in d
      and isinstance(d["pid"], int) and d["pid"] > 0
      and str(d["pid"]) == str(expid))
print(1 if ok else 0)
PYEOF
  )
  if [[ "$VALID" == "1" ]]; then
    pass "case3: --enter writes sentinel pid=$EXPID with valid JSON"
  else
    CONTENT="$(cat "$SENTINEL" 2>/dev/null || echo MISSING)"
    fail "case3: --enter sentinel invalid/missing keys (expected pid=$EXPID, got: $CONTENT)"
  fi
fi

# ── Case 4: bare invocation also writes (interactive attach path) ──────────
rm -f "$SENTINEL"
run_supervise
if [[ -f "$SENTINEL" ]]; then
  pass "case4: bare invocation writes sentinel (entry path unchanged)"
else
  fail "case4: bare invocation wrote no sentinel (entry path regressed?)"
fi

echo "----"
echo "PASS=$PASS FAIL=$FAIL"
[[ "$FAIL" -eq 0 ]]
