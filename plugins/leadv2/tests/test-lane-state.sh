#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
LIB="${ROOT}/plugins/leadv2/scripts/lib/leadv2-lane-state.sh"
FIX="$(mktemp -d "${TMPDIR:-/tmp}/lv2-lane-state.XXXXXX")"
cleanup() { [[ -n "${P1:-}" ]] && kill -9 "$P1" 2>/dev/null || true; [[ -n "${P2:-}" ]] && kill -9 "$P2" 2>/dev/null || true; rm -rf "$FIX"; }
trap cleanup EXIT
pass() { printf 'PASS %s\n' "$1"; }
fail() { printf 'FAIL %s\n' "$1" >&2; exit 1; }

git -C "$FIX" init -q
git -C "$FIX" config user.email test@example.invalid
git -C "$FIX" config user.name test
touch "$FIX/.keep"; git -C "$FIX" add .keep; git -C "$FIX" commit -qm init
mkdir -p "$FIX/docs/leadv2" "$FIX/.claude/worktrees"
printf 'sessions: []\n' > "$FIX/docs/leadv2/active.yaml"
export LEADV2_PROJECT_ROOT="$FIX" LEADV2_STATE_ROOT="$FIX/docs/leadv2"
export LEADV2_LANE_STATE_TEST_BIRTH_FILE="$FIX/births.tsv" LEADV2_LANE_STATE_TEST_PS_FILE="$FIX/ps.txt" LEADV2_LANE_STATE_TEST_WORKTREES_FILE="$FIX/worktrees.txt"
birth() { printf '%s\t%s\n' "$1" "$2" >> "$LEADV2_LANE_STATE_TEST_BIRTH_FILE"; }
source "$LIB"

sleep 60 & P1=$!
birth "$P1" 'Mon Jan  1 00:00:00 2024'
lane_register lane-a lead-1 "$FIX/.claude/worktrees/lane-a" build "$P1"
lane_alive lane-a || fail 'new row is live'
pass 'register records a PID start time and lane_alive accepts it'

kill -9 "$P1"; wait "$P1" 2>/dev/null || true; P1=''
lane_reconcile
python3 - "$FIX/docs/leadv2/active.yaml" <<'PY' || exit 1
import sys,yaml
r=yaml.safe_load(open(sys.argv[1]))['sessions'][0]
assert r['dead_at'] and r['lane_events'][-1]['event']=='reconciled_dead'
PY
pass 'kill -9 then reconcile marks the row dead (negative control)'

sleep 60 & P1=$!
birth "$P1" 'Tue Jan  2 00:00:00 2024'
lane_register lane-reuse lead-1 "$FIX/.claude/worktrees/lane-reuse" build "$P1"
kill -9 "$P1"; wait "$P1" 2>/dev/null || true
sleep 60 & P2=$!
birth "$P2" 'Wed Jan  3 00:00:00 2024'
python3 - "$FIX/docs/leadv2/active.yaml" "$P2" <<'PY'
import sys,yaml
p=sys.argv[1]; d=yaml.safe_load(open(p)); r=next(x for x in d['sessions'] if x['task_id']=='lane-reuse'); r['pid']=int(sys.argv[2]); open(p,'w').write(yaml.safe_dump(d,sort_keys=False))
PY
if lane_alive lane-reuse; then fail 'pid reuse must not be alive'; fi
pass 'PID-reuse simulation rejects mismatched start time (negative control)'

sleep 60 & P1=$!
birth "$P1" 'Thu Jan  4 00:00:00 2024'
lane_register lane-1 cap-session "$FIX/.claude/worktrees/lane-1" build "$P1"
sleep 60 & P2=$!
birth "$P2" 'Fri Jan  5 00:00:00 2024'
lane_register lane-2 cap-session "$FIX/.claude/worktrees/lane-2" build "$P2"
sleep 60 & P3=$!
if lane_register lane-3 cap-session "$FIX/.claude/worktrees/lane-3" build "$P3"; then fail 'third lane was admitted'; else rc=$?; [[ $rc -eq 3 ]] || fail "third lane rc=$rc"; fi
kill -9 "$P3" 2>/dev/null || true; wait "$P3" 2>/dev/null || true; unset P3
pass 'third live lane for one lead session is refused with rc=3 (negative control)'

git -C "$FIX" worktree add -q "$FIX/.claude/worktrees/orphan-live" -b orphan-live
bash -c 'while :; do sleep 1; done' -- "$FIX/.claude/worktrees/orphan-live" & P3=$!
birth "$P3" 'Sat Jan  6 00:00:00 2024'
printf '%s Sat Jan  6 00:00:00 2024 bash -- %s\n' "$P3" "$FIX/.claude/worktrees/orphan-live" > "$LEADV2_LANE_STATE_TEST_PS_FILE"
printf 'worktree %s\nworktree %s\n' "$FIX" "$FIX/.claude/worktrees/orphan-live" > "$LEADV2_LANE_STATE_TEST_WORKTREES_FILE"
lane_reconcile
python3 - "$FIX/docs/leadv2/active.yaml" <<'PY' || exit 1
import sys,yaml
rows=yaml.safe_load(open(sys.argv[1]))['sessions']
assert any(r.get('worktree','').endswith('/orphan-live') and r.get('recovered') for r in rows)
PY
pass 'orphan worktree with a live process is recovered (negative control)'
