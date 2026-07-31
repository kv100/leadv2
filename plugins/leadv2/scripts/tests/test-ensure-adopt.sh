#!/usr/bin/env bash
# tests/test-ensure-adopt.sh — SESSION-CLOSE-FIXES-01 fix 1 tests for
# leadv2-supervise-loop.sh --ensure / bare-invocation ownership behaviour.
#
# Before fix 1A/1B, the bash writer and python reader normalised `ps -o
# lstart=` differently (trailing space vs trimmed), so the corroboration
# branch NEVER matched and every --ensure spawned a sibling loop. These
# cases pin the fixed behaviour:
#   1. healthy loop (live pid + matching birth + fresh heartbeat) + --ensure
#      -> EXISTING: exit 0, log "adopt existing loop pid=", sentinel pid
#      unchanged (no second process).
#   2. live pid + matching birth BUT stale heartbeat + --ensure -> NOT live:
#      fall through to NEW (claim + run = respawn once); sentinel names the
#      new pid. (Fix 1B freshness predicate.)
#   3. sentinel names a different LIVE loop, invoked WITHOUT --ensure ->
#      FOREIGN: exit 0, no-op, sentinel untouched. (Fix 1C single-owner.)
#
# A long-lived `sleep` stands in for the "other loop" so pid + birth are real
# ps values, exercising the actual normaliser. State is sandboxed via
# LEADV2_STATE_ROOT + LEADV2_PROJECT_ROOT into a throwaway fixture; the real
# crontab is never touched (LEADV2_SUPERVISE_BEAT_CRON=0 + CRONTAB_BIN stub).
# Run: bash scripts/tests/test-ensure-adopt.sh

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOOP="${SCRIPT_DIR}/leadv2-supervise-loop.sh"
RESOLVER="${SCRIPT_DIR}/leadv2-state-path.sh"
source "${SCRIPT_DIR}/leadv2-temp.sh"

PASS=0
FAIL=0
log()  { printf -- '[TEST] %s\n' "$*"; }
pass() { PASS=$(( PASS + 1 )); log "PASS: $1"; }
fail() { FAIL=$(( FAIL + 1 )); log "FAIL: $1"; }

if bash -n "${LOOP}" 2>/dev/null; then pass "bash -n supervise-loop"; else fail "bash -n supervise-loop"; fi
[[ -x "$RESOLVER" ]] || { fail "resolver not executable — cannot stage fixture"; log "=== ${PASS} passed, ${FAIL} failed ==="; exit 1; }

# Reap every sleep stand-in + stray --ensure we spawn so no test leaks.
_SLEEPS=()
_ENSURES=()
cleanup() {
  for p in "${_SLEEPS[@]:-}";   do kill "$p" 2>/dev/null || true; done
  for p in "${_ENSURES[@]:-}";  do kill "$p" 2>/dev/null || true; done
}
trap cleanup EXIT

# Mirror the loop's _pid_birth byte-for-byte (fix 1A normaliser).
norm_birth() { ps -o lstart= -p "$1" 2>/dev/null | tr -s ' ' | sed -e 's/^ *//' -e 's/ *$//'; }

# Write the ownership sentinel for a stand-in loop pid.
write_sentinel() {  # <pid>
  local pid="$1" sbirth
  sbirth="$(norm_birth "$pid")"
  python3 -c "
import json,sys,tempfile,os,datetime
path,pid,birth=sys.argv[1:4]
out={'pid':int(pid),'pid_birth':birth,'started_at':datetime.datetime.now(datetime.timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ')}
d=os.path.dirname(path) or '.'
os.makedirs(d,exist_ok=True)
fd,tmp=tempfile.mkstemp(dir=d,suffix='.tmp')
with os.fdopen(fd,'w') as fh: json.dump(out,fh)
os.replace(tmp,path)
" "$SENTINEL" "$pid" "$sbirth"
}

# Read the recorded owner pid from the sentinel.
read_sentinel_pid() {
  python3 -c "
import json,sys
try:
    print(json.load(open(sys.argv[1])).get('pid'))
except Exception:
    print('ERR')
" "$SENTINEL"
}

# ── Fixture repo + isolated control-plane state dir ────────────────────────
FIXTURE="$(lv2_mktemp_dir ensure-adopt-fx)/repo"
mkdir -p "$FIXTURE/.claude/scripts"
( cd "$FIXTURE" && git init -q && git config user.email t@t.com && git config user.name t )
lv2_assert_scratch_repo "$FIXTURE"

STATE_ROOT="$(lv2_mktemp_dir ensure-adopt-state)"
mkdir -p "$STATE_ROOT"
SENTINEL="${STATE_ROOT}/.supervise-loop.json"
HEARTBEAT="${STATE_ROOT}/.supervise-loop.heartbeat"
LOG_FILE="${STATE_ROOT}/supervise-loop.log"

# Crontab stub — never installed (BEAT_CRON=0) but present so any stray call
# is a no-op against a fake binary, never the real crontab.
CRONTAB_STUB="$(lv2_mktemp_dir ensure-cron)/crontab"
cat > "$CRONTAB_STUB" <<'STUB'
#!/usr/bin/env bash
exit 0
STUB
chmod +x "$CRONTAB_STUB"

common_env() {
  LEADV2_PROJECT_ROOT="$FIXTURE" \
  LEADV2_STATE_ROOT="$STATE_ROOT" \
  LEADV2_SUPERVISE_BEAT_CRON=0 \
  CRONTAB_BIN="$CRONTAB_STUB" \
  LEADV2_SUPERVISE_EVENT_POLL_S=1 \
  LEADV2_SUPERVISE_LOOP_MAX_CYCLES=1 \
  CLAUDE_PROJECT_DIR="" \
  HOME="${HOME}" \
  "$@"
}

# ── Case 1: healthy loop + --ensure -> ADOPT (no sibling) ───────────────────
sleep 300 & _SLEEPS+=("$!"); OTHER1=$!
write_sentinel "$OTHER1"
: >"$HEARTBEAT"           # fresh mtime -> adopt-safe
out="$(common_env bash "$LOOP" --ensure 2>&1)"; rc=$?
sp="$(read_sentinel_pid)"
if [ "$rc" = "0" ]; then pass "case1: --ensure exits 0"; else fail "case1: --ensure exit=$rc (want 0) out=$out"; fi
if grep -q "adopt existing loop pid=${OTHER1}" "$LOG_FILE" 2>/dev/null; then
  pass "case1: adopt line in LOG_FILE"
else fail "case1: adopt line NOT in LOG_FILE (out=$out; log=$(cat "$LOG_FILE" 2>/dev/null))"
fi
if [ "$sp" = "$OTHER1" ]; then pass "case1: sentinel pid unchanged ($sp)"; else fail "case1: sentinel pid changed to $sp (want $OTHER1) — a sibling was started"; fi

# ── Case 2: live pid + matching birth but STALE heartbeat -> NEW (claim) ────
sleep 300 & _SLEEPS+=("$!"); OTHER2=$!
write_sentinel "$OTHER2"
# Age the heartbeat 2h past the adopt threshold (default 600s).
python3 -c "
import os,sys,time
p=sys.argv[1]; open(p,'a').close(); os.utime(p,(time.time()-7200,)*2)
" "$HEARTBEAT"
common_env bash "$LOOP" --ensure >/dev/null 2>&1 &
_ENSURES+=("$!"); ENS_PID=$!
# The claim happens inside PYENSURE before the loop body, so the sentinel is
# overwritten almost immediately.
i=0; while [ "$i" -lt 30 ]; do sp2="$(read_sentinel_pid)"; [ "$sp2" != "$OTHER2" ] && break; i=$((i+1)); sleep 0.1; done
sp2="$(read_sentinel_pid)"
# The new owner pid is the loop's own $$, recorded in its started log line.
NEWPID="$(grep -o 'started pid=[0-9]*' "$LOG_FILE" 2>/dev/null | tail -1 | grep -o '[0-9]*$' || true)"
if [ "$sp2" != "$OTHER2" ]; then pass "case2: stale-hb owner displaced (no adopt, respawned)"; else fail "case2: stale owner was wrongly adopted (sentinel still $OTHER2)"; fi
if [ -n "$NEWPID" ] && [ "$sp2" = "$NEWPID" ]; then pass "case2: sentinel names the new owner pid ($sp2)"; else fail "case2: sentinel pid=$sp2 does not match started pid=${NEWPID:-<none>}"; fi

# ── Case 3: live owner + NO --ensure -> FOREIGN no-op ───────────────────────
sleep 300 & _SLEEPS+=("$!"); OTHER3=$!
write_sentinel "$OTHER3"
: >"$HEARTBEAT"
out="$(common_env bash "$LOOP" 2>&1)"; rc=$?
sp3="$(read_sentinel_pid)"
if [ "$rc" = "0" ]; then pass "case3: bare invocation exits 0"; else fail "case3: bare invocation exit=$rc (want 0) out=$out"; fi
if grep -q "another loop owns this repo (pid=${OTHER3})" "$LOG_FILE" 2>/dev/null; then
  pass "case3: FOREIGN line in LOG_FILE for pid=${OTHER3}"
else fail "case3: missing FOREIGN line (out=$out; log=$(cat "$LOG_FILE" 2>/dev/null))"
fi
if [ "$sp3" = "$OTHER3" ]; then pass "case3: sentinel untouched ($sp3)"; else fail "case3: sentinel clobbered to $sp3 (want $OTHER3) — bare path overwrote a live owner"; fi

log ""
log "=== ${PASS} passed, ${FAIL} failed ==="
[ "$FAIL" = "0" ]
