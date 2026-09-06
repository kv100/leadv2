#!/usr/bin/env bash
# measure-before-fix.sh — LANE-ALIVE-PREDICATE-CALLS-A-LIVE-LANE-DEAD-01
#
# Step 1 of the brief: run the UNMODIFIED lib/leadv2-lane-state.sh `alive`
# predicate against real, заведомо живые pids and show WHICH line returns
# False — the os.kill classification or the birth comparison. Also scans the
# live registries for rows already stamped dead_at whose pid still exists
# (the smoking gun of a false-dead verdict).
#
# Run: bash docs/handoff/LANE-ALIVE-PREDICATE-CALLS-A-LIVE-LANE-DEAD-01/measure-before-fix.sh
# Read-only for production state; writes only under mktemp.

set -uo pipefail
LEADV2_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
LIB="${LEADV2_ROOT}/plugins/leadv2/scripts/lib/leadv2-lane-state.sh"

TMP="$(mktemp -d "${TMPDIR:-/tmp}/lane-alive-measure.XXXXXX")"
SLEEP_PIDS=()
cleanup() { (( ${#SLEEP_PIDS[@]} )) && kill ${SLEEP_PIDS[@]} 2>/dev/null; rm -rf "$TMP"; }
trap cleanup EXIT

REPO="$TMP/repo"; STATE_ROOT="$TMP/state"
mkdir -p "$REPO/.claude/worktrees" "$STATE_ROOT"

new_sleeper() { sleep 300 </dev/null >/dev/null 2>&1 & echo $!; }
birth_of() { ps -o lstart= -p "$1" 2>/dev/null | tr -s ' ' | sed -e 's/^ *//' -e 's/ *$//'; }

write_row() { # <task> <pid> <pid_start_time> -> row into $STATE_ROOT/active.yaml
  python3 - "$STATE_ROOT/active.yaml" "$1" "$2" "$3" <<'PY'
import os, sys, yaml
path, task, pid, birth = sys.argv[1:5]
os.makedirs(os.path.dirname(path), exist_ok=True)
data = {}
if os.path.exists(path):
    data = yaml.safe_load(open(path, encoding='utf-8')) or {}
rows = data.get('sessions') or []
rows[:] = [r for r in rows if r.get('task_id') != task]
rows.append({'task_id': task, 'session_id': 'lead', 'lead_session_id': 'lead',
             'worktree': '/tmp/nowhere', 'phase': 'build', 'pid': int(pid),
             'pid_start_time': birth, 'started_at': '2026-09-06T00:00:00Z',
             'updated_at': '2026-09-06T00:00:00Z', 'dead_at': None,
             'recovered': False, 'lane_events': []})
yaml.safe_dump({'meta': {}, 'sessions': rows}, open(path, 'w', encoding='utf-8'),
               default_flow_style=False, sort_keys=False)
PY
}

probe_alive() { # <task> [extra env as VAR=VAL pairs via PROBE_ENV] -> prints rc (0=live, 1=dead)
  env LEADV2_PROJECT_ROOT="$REPO" LEADV2_STATE_ROOT="$STATE_ROOT" ${PROBE_ENV:-} \
    bash -c "source '$LIB'; lane_alive '$1'" >/dev/null 2>&1
  echo $?
}

echo "=== lib under test: ${LIB} md5=$(md5 -q "$LIB" 2>/dev/null || md5sum "$LIB" | cut -d' ' -f1)"
echo

# --- M1 baseline: live pid + correct birth -> must be rc0 (harness validity)
P="$(new_sleeper)"; SLEEP_PIDS+=("$P"); B="$(birth_of "$P")"
write_row M1-live "$P" "$B"
echo "[M1] baseline live pid=$P kill-0:$(kill -0 "$P" 2>/dev/null && echo rc0 || echo rc$?) birth='${B:0:16}…' lane_alive rc=$(probe_alive M1-live)  (expect 0)"
echo

# --- M2 recorded birth EMPTY (register-time ps failure) on a LIVE pid
write_row M2-empty-recorded "$P" ""
echo "[M2] LIVE pid=$P kill-0:$(kill -0 "$P" 2>/dev/null && echo rc0 || echo rc$?) pid_start_time='' (empty) lane_alive rc=$(probe_alive M2-empty-recorded)  (0 would be correct)"
echo "     -> os.kill SUCCEEDED above, so the False verdict comes from the birth-comparison line, not from os.kill"
echo

# --- M3 observed birth EMPTY (check-time ps failure) on a LIVE pid
: > "$TMP/birth.fixture"
printf '%s\t\n' "$P" >> "$TMP/birth.fixture"   # fixture returns '' for this pid
write_row M3-empty-observed "$P" "$B"
PROBE_ENV="LEADV2_LANE_STATE_TEST_BIRTH_FILE=$TMP/birth.fixture"
echo "[M3] LIVE pid=$P correct recorded birth, but birth() observes '' (fixture simulates ps failure/timeout) lane_alive rc=$(probe_alive M3-empty-observed)  (0 would be correct)"
PROBE_ENV=""
echo

# --- M4 EPERM: a live process owned by root (exists; we may not signal it)
ROOTPID="$(ps -axo pid=,user= | awk '$2=="root" && $1>1 {print $1; exit}')"
if [[ -n "${ROOTPID:-}" ]]; then
  RB="$(birth_of "$ROOTPID")"
  KERR="$(kill -0 "$ROOTPID" 2>&1 >/dev/null; true)"
  [[ -z "$KERR" ]] && KERR="(rc0, no error)"
  PYCLS="$(python3 - "$ROOTPID" <<'PY'
import os, sys
try:
    os.kill(int(sys.argv[1]), 0); print('rc0 (no exception)')
except PermissionError: print('PermissionError (EPERM)')
except ProcessLookupError: print('ProcessLookupError (ESRCH)')
except OSError as e: print(f'OSError: {e}')
PY
)"
  write_row M4-eperm "$ROOTPID" "$RB"
  echo "[M4] root-owned LIVE pid=$ROOTPID kill-0 stderr: '${KERR}' python os.kill: ${PYCLS} real birth recorded lane_alive rc=$(probe_alive M4-eperm)  (0 would be correct — EPERM means the process EXISTS)"
else
  echo "[M4] SKIP: no root-owned pid>1 found on this machine"
fi
echo

# --- M5 genuinely dead pid (killed + reaped) must stay dead
DP="$(new_sleeper)"; DB="$(birth_of "$DP")"; kill "$DP" 2>/dev/null; wait "$DP" 2>/dev/null
write_row M5-dead "$DP" "$DB"
echo "[M5] DEAD pid=$DP (killed+waited, ESRCH expected) kill-0:$(kill -0 "$DP" 2>/dev/null && echo rc0 || echo rc$?) lane_alive rc=$(probe_alive M5-dead)  (1 is CORRECT — a real death must stay dead)"
echo

# --- M6 pid-reuse shape: live pid + WRONG recorded birth -> dead is correct
write_row M6-mismatch "$P" "Mon Jan  1 00:00:00 1999"
echo "[M6] LIVE pid=$P with MISMATCHED recorded birth (pid-reuse shape) lane_alive rc=$(probe_alive M6-mismatch)  (1 is CORRECT — mismatch means the recorded process is gone)"
echo

# --- M7 live-registry scan: rows stamped dead_at whose pid still EXISTS
echo "[M7] live registry scan — false-dead victims already on disk:"
python3 - <<'PY'
import glob, os
try:
    import yaml
except ImportError:
    print("    (pyyaml missing — skip)"); raise SystemExit
found = 0
for path in sorted(glob.glob(os.path.expanduser('~/.claude/leadv2-state/*/active.yaml'))):
    try:
        data = yaml.safe_load(open(path, encoding='utf-8')) or {}
    except OSError:
        continue
    for r in data.get('sessions') or []:
        pid = r.get('pid')
        if not pid or not r.get('dead_at'):
            continue
        try:
            os.kill(int(pid), 0); state = 'EXISTS(rc0)'
        except PermissionError:
            state = 'EXISTS(EPERM)'
        except (ProcessLookupError, ValueError, TypeError, OSError):
            continue
        events = [e.get('event') for e in (r.get('lane_events') or [])][-3:]
        found += 1
        print(f"    {path}: task={r.get('task_id')} pid={pid} {state} "
              f"pid_start_time={r.get('pid_start_time')!r} dead_at={r.get('dead_at')} last_events={events}")
print(f"    total rows dead_at-stamped whose pid still exists: {found}")
PY
echo
echo "=== measurement done"
