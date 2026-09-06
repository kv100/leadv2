#!/usr/bin/env bash
# run-all-triggers: leadv2-active-registry
# test-stale-row-starting-grace.sh — STALE-ROW-STARTING-GRACE-01 coverage:
# rejected-dispatch rows (dead pid, phase spawning/build) must NOT count as
# active sessions in check_limits nor inflate the `Active sessions (N / max)`
# header, and leadv2_active_unregister must be able to shed only the dead
# rows of a task_id that also owns a LIVE row.
#
# Measured live 2026-09-06: 10 non-stale rows, 7 dead-pid tombstones,
# `check_limits` refused "hard limit reached: 10/5" on every class while the
# actual dispatch admission (register's writeset scan) passed rc=0 — the
# tombstones ate a limit nothing on the dispatch path even consults.
#
# Negative control (mutation-proven): in a TEMP COPY of
# leadv2-active-registry.sh, the body of _row_dead() is mutated to
# `return False  # MUTATION` (inside the function body, never top-level).
# That reverts both the check_limits filter and the list header to counting
# tombstones and MUST turn checks A1 and B red. Run with
# STALE_ROW_GRACE_MUTATION=1 to execute the mutation leg.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REGISTRY_SH="${SCRIPT_DIR}/../leadv2-active-registry.sh"

FAILS=0
ok()   { echo "  PASS: $1"; }
fail() { echo "  FAIL: $1"; FAILS=$((FAILS+1)); }

# ── sandbox: registry state in a temp dir via a stub state-path resolver ──
SB="$(mktemp -d /tmp/stale-row-grace-test.XXXXXX)"
trap 'rm -rf "$SB"' EXIT
mkdir -p "$SB/state"

cat > "$SB/stub-resolver.sh" <<STUB
#!/bin/bash
echo "$SB/state/\${1##*/}"
STUB
chmod +x "$SB/stub-resolver.sh"

export LEADV2_STATE_PATH_BIN="$SB/stub-resolver.sh"
export LEADV2_PROJECT_ROOT="${SCRIPT_DIR}/../../../../../"

YAML="$SB/state/active.yaml"

write_yaml() { # <hard_limit> ; rows are appended by python below
  cat > "$YAML" <<YAMLEOF
meta:
  hard_limit: $1
  heavy_max: 3
  heavy_strategic_solo: false
  standard_max: 4
sessions: []
YAMLEOF
}

add_row() { # task_id session_id pid stale phase
  python3 - "$YAML" "$1" "$2" "$3" "$4" "$5" <<'PYROW'
import sys, yaml
f, tid, sid, pid, stale, phase = sys.argv[1:7]
d = yaml.safe_load(open(f)) or {}
row = {"task_id": tid, "session_id": sid, "phase": phase, "class": "Light",
       "pid": None if pid in ("None", "") else int(pid),
       "stale": stale == "true", "started_at": "2026-09-05T00:00:00Z"}
d["sessions"].append(row)
yaml.safe_dump(d, open(f, "w"), sort_keys=False)
PYROW
}

count_rows() {
  python3 -c "import yaml,sys;print(len((yaml.safe_load(open(sys.argv[1])) or {'sessions':[]})['sessions']))" "$YAML"
}

row_exists() { # task_id session_id -> 0/1
  python3 - "$YAML" "$1" "$2" <<'PYE'
import sys, yaml
f, tid, sid = sys.argv[1:4]
d = yaml.safe_load(open(f)) or {}
print(1 if any(s.get("task_id")==tid and s.get("session_id")==sid for s in d["sessions"]) else 0)
PYE
}

# a pid that is PROVABLY dead: spawn+wait a short-lived process, then reuse its pid
DEAD_PID="$(python3 -c 'import os,subprocess,time
p=subprocess.Popen(["/bin/sleep","0.1"]);p.wait();print(p.pid)')"
# a SECOND provably-dead pid, for a fixture row that needs to be genuinely
# dead but distinct from DEAD_PID (C1 exercises removing 2 dead rows in one
# call, not 1).
DEAD_PID2="$(python3 -c 'import os,subprocess,time
p=subprocess.Popen(["/bin/sleep","0.1"]);p.wait();print(p.pid)')"

SRC="${REGISTRY_SH}"
if [[ "${STALE_ROW_GRACE_MUTATION:-0}" == "1" ]]; then
  SRC="$SB/mutated-registry.sh"
  python3 - "$REGISTRY_SH" "$SRC" <<'PYMUT'
import sys
src, dst = sys.argv[1:3]
s = open(src).read()
# MUTATION (inside function body): _row_dead always answers False ->
# tombstones count again in check_limits and the list header.
target = 'return pid not in (None, "", "null", "None") and not _pid_alive(pid)'
assert s.count(target) == 2, f"mutation anchor count={s.count(target)}"
s = s.replace(target, "return False  # MUTATION")
open(dst, "w").write(s)
PYMUT
  echo "== mutation leg: _row_dead() -> return False (tombstones count again)"
fi

# shellcheck disable=SC1090
source "$SRC"

echo "== A. check_limits ignores dead-pid tombstones, keeps live and pid=None rows"
write_yaml 1                       # hard_limit=1: ONE counted row refuses
add_row TOMB-01 s-tomb-1 "$DEAD_PID" false spawning
rc=0; leadv2_active_check_limits light 2>/dev/null || rc=$?
[[ $rc -eq 0 ]] && ok "A1 dead-pid row does not count (rc=0 at 1/1 counted)" \
                 || fail "A1 dead-pid row still counted (rc=$rc)"

add_row LIVE-01 s-live-1 $$ false build
rc=0; leadv2_active_check_limits light 2>/dev/null || rc=$?
[[ $rc -eq 1 ]] && ok "A2 live-pid row still blocks (rc=1)" \
                 || fail "A2 live-pid row no longer blocks (rc=$rc)"

write_yaml 1
add_row NOPID-01 s-nopid-1 None false recovered_unowned
rc=0; leadv2_active_check_limits light 2>/dev/null || rc=$?
[[ $rc -eq 1 ]] && ok "A3 pid=None row still counts (fail-closed, rc=1)" \
                 || fail "A3 pid=None row dropped from count (rc=$rc)"

add_row STALE-01 s-stale-1 "$DEAD_PID" true build
rc=0; leadv2_active_check_limits light 2>/dev/null || rc=$?
[[ $rc -eq 1 ]] && ok "A4 stale:true row still not counted (only pid=None row counts, rc=1)" \
                 || fail "A4 stale flag regression (rc=$rc)"

echo "== B. list header counts liveness-honest rows and marks DEAD"
write_yaml 5
add_row TOMB-02 s-tomb-2 "$DEAD_PID" false spawning
add_row LIVE-02 s-live-2 $$ false build
hdr="$(leadv2_active_list 2>/dev/null | head -1)"
[[ "$hdr" == "Active sessions (1 / 5 max):" ]] \
  && ok "B1 header counts 1 live row, not 2 ($hdr)" \
  || fail "B1 header wrong: $hdr"
leadv2_active_list 2>/dev/null | grep -q "s-tomb-2.*DEAD" \
  && ok "B2 dead row rendered and marked DEAD" \
  || fail "B2 dead row not marked DEAD in table"

echo "== C. unregister selectors"
write_yaml 9
add_row M-01 s-m-dead-1 "$DEAD_PID" false spawning
add_row M-01 s-m-dead-2 "$DEAD_PID2" false spawning   # second genuinely-dead pid
add_row M-01 s-m-eperm-1 1 false spawning             # pid 1: EPERM -> ALIVE, must survive --dead
add_row M-01 s-m-live-1 $$ false build                # LIVE row, same task_id
add_row OTHER-01 s-other-1 "$DEAD_PID" false build
before="$(count_rows)"
leadv2_active_unregister M-01 --dead 2>/dev/null
after="$(count_rows)"
[[ $((before - after)) -eq 2 ]] \
  && ok "C1 --dead removed exactly the 2 genuinely-dead rows ($before -> $after)" \
  || fail "C1 --dead removed wrong count ($before -> $after)"
[[ "$(row_exists M-01 s-m-live-1)" == "1" ]] \
  && ok "C2 paired negative: LIVE row of same task_id survived" \
  || fail "C2 LIVE row of same task_id was deleted"
# ACTIVE-REGISTRY-FIVE-EPERM-COLLAPSING-PID-ALIVE-01 pair control, other
# direction: an EPERM-owned pid (process exists, foreign-owned -- alive)
# must NOT be treated as dead by --dead. Before the fix, pid=1 (EPERM on a
# non-root test run) was misread as dead and removed alongside the genuinely
# dead rows; this fixture used to encode that bug as its own expectation.
[[ "$(row_exists M-01 s-m-eperm-1)" == "1" ]] \
  && ok "C1b pair control: EPERM-owned pid (1) is alive, not removed by --dead" \
  || fail "C1b EPERM-owned pid (1) was wrongly removed by --dead"
[[ "$(row_exists OTHER-01 s-other-1)" == "1" ]] \
  && ok "C3 other task_id untouched" \
  || fail "C3 other task_id row deleted"

write_yaml 9
add_row M-02 s-m2-a "$DEAD_PID" false build
add_row M-02 s-m2-b $$ false build
leadv2_active_unregister M-02 --session-id s-m2-a 2>/dev/null
[[ "$(row_exists M-02 s-m2-a)" == "0" && "$(row_exists M-02 s-m2-b)" == "1" ]] \
  && ok "C4 --session-id removed only the matching row" \
  || fail "C4 --session-id selector wrong"

write_yaml 9
add_row M-03 s-m3-a "$DEAD_PID" false build
add_row M-03 s-m3-b $$ false build
leadv2_active_unregister M-03 --pid "$DEAD_PID" 2>/dev/null
[[ "$(row_exists M-03 s-m3-a)" == "0" && "$(row_exists M-03 s-m3-b)" == "1" ]] \
  && ok "C5 --pid removed only the exact-pid row" \
  || fail "C5 --pid selector wrong"

write_yaml 9
add_row M-04 s-m4-nopid None false recovered_unowned
leadv2_active_unregister M-04 --dead 2>/dev/null
[[ "$(row_exists M-04 s-m4-nopid)" == "1" ]] \
  && ok "C6 --dead never removes a pid=None row (fail-closed)" \
  || fail "C6 --dead removed a pid=None row"

write_yaml 9
add_row M-05 s-m5-a "$DEAD_PID" false build
add_row M-05 s-m5-b $$ false build
leadv2_active_unregister M-05 2>/dev/null
[[ "$(count_rows)" == "0" ]] \
  && ok "C7 legacy bare unregister still removes ALL rows of the task_id" \
  || fail "C7 legacy unregister behavior changed ($(count_rows) rows left)"

if [[ "${STALE_ROW_GRACE_MUTATION:-0}" == "1" ]]; then
  echo
  if [[ $FAILS -gt 0 ]]; then
    echo "MUTATION KILLED: suite is red under _row_dead()->False ($FAILS fail(s))"
    exit 1
  else
    echo "MUTATION SURVIVED: suite stayed green — the controls prove nothing"
    exit 1
  fi
fi

echo
if [[ $FAILS -eq 0 ]]; then
  echo "stale-row-starting-grace: ALL GREEN"
  exit 0
else
  echo "stale-row-starting-grace: $FAILS FAIL(S)"
  exit 1
fi
