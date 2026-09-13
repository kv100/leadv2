#!/usr/bin/env bash
# tests/test-lane-registry-drops-finished-lanes.sh —
# THE-LANE-REGISTRY-ONLY-EVER-GROWS-01 (founder order 2026-09-13, verbatim:
# "не просто заведи ряд, а почини").
#
# A finished lane must LEAVE docs/leadv2/active.yaml. The reaper lives in
# lib/leadv2-lane-state.sh's reconcile op (the single writer for lane
# lifecycle, run by the SessionStart hook and every dispatch) and drops a
# tombstoned row ONLY on evidence the lane's ending itself wrote:
#   - glm arm: newest ~/.claude/cache/glm-runs/*-<sig>-*/meta.yaml
#     status complete|failed (or an exit_code file);
#   - any arm: a terminal dispatch-ledger record for the sig;
#   - any arm (the codex shape that writes nothing else): the sig is absent
#     from a NON-EMPTY open-backlog mirror (docs/tasks.yaml lists open work
#     items only — a closed row leaves it).
# A lane whose journal.jsonl is still growing is NEVER removed, whatever
# the terminal markers say. meta.rendered_at is restamped by every sweep.
#
# Pins (each has a declared negative control, run RED inside this suite on
# a mutated scratch copy of the lib, anchored on an exact source string
# asserted count==1 before replacing, applied inside the file under test):
#   1. terminal glm run dir            -> row gone      (MUTATION-A)
#   2. growing journal                 -> row stays     (MUTATION-B)
#   3. closed backlog row              -> row gone      (MUTATION-C)
#   4. pulse ghost count over a reaped registry with no live lanes == 0
#                                      -> reaping disabled makes it 1 (MUTATION-D)
#
# Run: bash plugins/leadv2/scripts/tests/test-lane-registry-drops-finished-lanes.sh
# run-all-triggers: leadv2-lane-state anti-silence-pulse
# Exit 0 = all pass; non-zero = failures found.

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
LIB="${LEADV2_LANE_STATE_LIB_OVERRIDE:-${SCRIPTS_DIR}/lib/leadv2-lane-state.sh}"
PULSE_SH="${SCRIPTS_DIR}/anti-silence-pulse.sh"

PASS=0; FAIL=0; ERRORS=()
pass() { PASS=$((PASS + 1)); printf '[TEST] PASS: %s\n' "$1"; }
fail() { FAIL=$((FAIL + 1)); ERRORS+=("$1"); printf '[TEST] FAIL: %s\n' "$1"; }

SB="$(mktemp -d "${TMPDIR:-/tmp}/lane-reap.XXXXXX")"
trap 'rm -rf "$SB"' EXIT
REPO="$SB/repo"; STATE_ROOT="$SB/state"; GLM="$SB/glm-runs"
PULSE_TASKS="$SB/pulse-tasks"
mkdir -p "$REPO/.claude/worktrees" "$STATE_ROOT" "$GLM" "$PULSE_TASKS"

YAML="$STATE_ROOT/active.yaml"
TASKS_YAML="$REPO/docs/tasks.yaml"
LEDGER="$STATE_ROOT/dispatch-ledger.jsonl"
mkdir -p "$REPO/docs"
: > "$SB/wt.txt"   # empty worktree fixture: no orphan adoption in this suite

write_registry() { # <file>
  cat > "$1" <<'YAMLEOF'
meta:
  hard_limit: 5
  heavy_max: 3
  heavy_strategic_solo: false
  rendered_at: '2020-01-01T00:00:00Z'
  standard_max: 4
sessions: []
YAMLEOF
}

# add_row <file> <task_id> <pid> <dead_at_seconds|none>
add_row() {
  python3 - "$1" "$2" "$3" "$4" "$REPO/.claude/worktrees/$2" <<'PYROW'
import sys, datetime, os, yaml
f, tid, pid, dead, wt = sys.argv[1:6]
def iso(offset_s):
    t = datetime.datetime.now(datetime.timezone.utc) - datetime.timedelta(seconds=offset_s)
    return t.strftime('%Y-%m-%dT%H:%M:%SZ')
d = yaml.safe_load(open(f)) or {}
d.setdefault('sessions', []).append({
    'task_id': tid,
    'session_id': 's-test', 'lead_session_id': 's-test',
    'worktree': wt, 'phase': 'build', 'class': 'Standard',
    'pid': int(pid), 'pid_birth': '', 'pid_role': 'lead_durable',
    'started_at': iso(7200), 'first_seen_at': iso(7200),
    'updated_at': iso(3600), 'dead_at': None if dead == 'none' else iso(int(dead)),
    'recovered': False, 'lane_events': [],
})
yaml.safe_dump(d, open(f, 'w'), sort_keys=False)
PYROW
}

# add_row_shaped <file> <tid> <pid|none> <dead_at_seconds|none> <backend>
#   <log_path> [recovered] [updated_age_s]
# Round-2 (THE-LANE-REGISTRY-ONLY-EVER-GROWS-01 R2): the shape that OCCURS —
# a pid that is genuinely alive (this suite's own $$), its real pid_start_time
# (so proc_verdict says 'live'), pid_role lead_durable, proc_kind interactive,
# backend terminal, no glm run dir, dead_at null. Round-1's add_row used a
# dead pid with pid_birth '', which proc_verdict reads as 'unknown', never
# exercising the live-lead-owned row.
add_row_shaped() {
  local f="$1" tid="$2" pid="$3" dead="$4" backend="$5" logp="$6" rec="${7:-false}" upd="${8:-3600}"
  # worktree basename is the BARE sig (dispatch-code.sh names the worktree
  # <sig8> while the row's task_id is dispatch-<sig8>) — _reap_sig reads it.
  local wt="$REPO/.claude/worktrees/${tid#dispatch-}"
  python3 - "$f" "$tid" "$pid" "$dead" "$wt" "$backend" "$logp" "$rec" "$upd" "$pid" <<'PYROW2'
import sys, datetime, subprocess, yaml
f, tid, pid, dead, wt, backend, logp, rec, upd, pidarg = sys.argv[1:11]
def iso(offset_s):
    t = datetime.datetime.now(datetime.timezone.utc) - datetime.timedelta(seconds=offset_s)
    return t.strftime('%Y-%m-%dT%H:%M:%SZ')
birth = ''
if pidarg != 'none':
    try:
        birth = ' '.join(subprocess.run(['ps','-o','lstart=','-p',pidarg], text=True, capture_output=True, timeout=2).stdout.split())
    except Exception:
        birth = ''
d = yaml.safe_load(open(f)) or {}
d.setdefault('sessions', []).append({
    'task_id': tid,
    'session_id': 's-test', 'lead_session_id': 's-test',
    'worktree': wt, 'phase': 'build', 'class': 'Standard',
    'pid': None if pid == 'none' else int(pid),
    'pid_start_time': birth, 'pid_birth': birth,
    'pid_role': 'lead_durable', 'proc_kind': 'interactive',
    'backend': backend, 'log_path': logp,
    'started_at': iso(7200), 'first_seen_at': iso(7200),
    'updated_at': iso(int(upd)),
    'dead_at': None if dead == 'none' else iso(int(dead)),
    'recovered': rec == 'true', 'lane_events': [],
})
yaml.safe_dump(d, open(f, 'w'), sort_keys=False)
PYROW2
}

# mk_glm <sig> <status> <journal_age_s> -- a run dir the worker's runner wrote
mk_glm() {
  local sig="$1" status="$2" age="$3"
  local d="$GLM/260913-000000-${sig}-0001"
  mkdir -p "$d"
  printf 'run_id: 260913-000000-%s-0001\nrepo: %s\nstatus: %s\nexit_code:\n' "$sig" "$sig" "$status" > "$d/meta.yaml"
  printf '{"ts":"x","event":"beat"}\n' > "$d/journal.jsonl"
  python3 - "$d" "$age" <<'PYUT'
import os, sys, time
d, age = sys.argv[1], int(sys.argv[2])
t = time.time() - age
os.utime(os.path.join(d, 'journal.jsonl'), (t, t))
os.utime(d, (t, t))
PYUT
}

run_reap() { # <lib-path> <state-root> -- one reconcile pass over that root's active.yaml
  LEADV2_PROJECT_ROOT="$REPO" \
  LEADV2_STATE_ROOT="$2" \
  LEADV2_LANE_STATE_TEST_WORKTREES_FILE="$SB/wt.txt" \
  LEADV2_REAP_GLM_RUNS_DIR="$GLM" \
  LEADV2_REAP_TASKS_YAML="$TASKS_YAML" \
  LEADV2_REAP_DISPATCH_LEDGER="$LEDGER" \
    bash -c "source '$1'; lane_reconcile" 2>"$SB/reap.err"
}

n_sessions() { python3 -c "import yaml,sys;print(len((yaml.safe_load(open(sys.argv[1])) or {'sessions':[]})['sessions']))" "$1"; }
has_row() { python3 -c "
import yaml,sys
d=yaml.safe_load(open(sys.argv[2])) or {}
print(1 if any(r.get('task_id')==sys.argv[1] for r in d.get('sessions',[])) else 0)" "$1" "$2"; }
rendered_at() { python3 -c "
import yaml,sys
d=yaml.safe_load(open(sys.argv[1])) or {}
print((d.get('meta') or {}).get('rendered_at') or '')" "$1"; }

# ── shared fixture world ───────────────────────────────────────────────────
# Open-backlog mirror: two OPEN rows — ffff6666ffff (the green-leg keeper)
# and aa11aa11aa11 (NC-A's isolated fixture: OPEN in the mirror and absent
# from the ledger, so the glm run dir is the ONLY terminal leg that can drop
# it). Every other sig is a closed backlog row (absent from a non-empty
# mirror).
cat > "$TASKS_YAML" <<'TASKS'
# GENERATED FILE — DO NOT EDIT BY HAND.
total_open: 2
tasks:
- id: ffff6666ffff
  node_id: human:test
  source: human
  status: queued
- id: aa11aa11aa11
  node_id: human:test
  source: human
  status: queued
TASKS

# ledger: terminal records (the codex/product-close shape). aaaa1111aaaa's
# entry exists for the pulse leg, whose registry must reap WITHOUT a glm
# run dir (the codex-arm shape) while staying terminal-positive.
printf '{"ts":"2026-09-13T00:00:00Z","task_sig":"dddd4444dddd","terminal":"done","cause":"closed"}\n' > "$LEDGER"
printf '{"ts":"2026-09-13T00:00:00Z","task_sig":"aaaa1111aaaa","terminal":"done","cause":"closed"}\n' >> "$LEDGER"
# round-2: a NON-terminal sig->founder mapping record, so an 8-hex dispatch sig
# can be resolved to its founder id without itself being terminal evidence.
printf '{"ts":"2026-09-13T00:00:00Z","task_sig":"ab12cd35","founder_task_id":"999944449999","cause":"registered"}\n' >> "$LEDGER"

# dead-but-not-tombstoned-yet pids: 4000001+ never exist on this host
DEAD_PID=4000001

# ═══ Pin 1 + 2 + 3 (green legs over one registry) ═════════════════════════
write_registry "$YAML"
add_row "$YAML" aaaa1111aaaa $DEAD_PID 3600   # glm terminal, journal stale -> DROP
mk_glm aaaa1111aaaa complete 1800
add_row "$YAML" bbbb2222bbbb $DEAD_PID 3600   # glm terminal BUT journal growing -> KEEP
mk_glm bbbb2222bbbb complete 0
add_row "$YAML" cccc3333cccc $DEAD_PID 3600   # no glm, no ledger, backlog closed -> DROP
add_row "$YAML" dddd4444dddd $DEAD_PID 3600   # ledger terminal -> DROP
add_row "$YAML" eeee5555eeee $DEAD_PID 3600   # glm run still running -> KEEP (never evict live)
mk_glm eeee5555eeee running 1800
add_row "$YAML" ffff6666ffff $DEAD_PID 3600   # backlog row still OPEN -> KEEP
add_row "$YAML" gggg77777777 $DEAD_PID 3600   # dead twin of a live-row sig -> DROP (identity, not sig)
add_row "$YAML" gggg77777777 $((DEAD_PID + 2)) none  # live sibling same sig -> KEEP
mk_glm gggg77777777 complete 1800
add_row "$YAML" hhhh88888888 $DEAD_PID 30     # tombstone younger than grace -> KEEP this pass

run_reap "$LIB" "$STATE_ROOT"; REAP_RC=$?

[[ $REAP_RC -eq 0 ]] && pass "reap pass rc=0" || fail "reap pass rc=$REAP_RC"

[[ "$(has_row aaaa1111aaaa "$YAML")" == 0 ]] \
  && pass "P1: terminal glm run dir -> row gone" \
  || fail "P1: terminal glm run dir row survived"
if [[ "$(has_row bbbb2222bbbb "$YAML")" == 1 ]]; then
  pass "P2: growing journal -> row still there (never evict)"
else
  fail "P2: growing-journal lane was evicted"
fi
if [[ "$(has_row cccc3333cccc "$YAML")" == 0 ]]; then
  pass "P3: closed backlog row does not keep the row alive"
else
  fail "P3: closed-backlog lane survived (codex shape never leaves)"
fi
if [[ "$(has_row dddd4444dddd "$YAML")" == 0 ]]; then
  pass "P3b: terminal dispatch-ledger record -> row gone"
else
  fail "P3b: terminal ledger record did not release the row"
fi
if [[ "$(has_row eeee5555eeee "$YAML")" == 1 ]]; then
  pass "P2b: glm run dir still running -> row still there"
else
  fail "P2b: running lane evicted (the never-evict-live rule)"
fi
if [[ "$(has_row ffff6666ffff "$YAML")" == 1 ]]; then
  pass "P3c: open backlog row keeps an in-flight armless lane"
else
  fail "P3c: open-backlog lane dropped (absence was read as closed)"
fi
if [[ "$(has_row gggg77777777 "$YAML")" == 1 ]]; then
  pass "P4-pre: row-identity reap — live sibling survived its dead twin"
else
  fail "P4-pre: live sibling reaped with its dead twin (sig-scoped bug)"
fi
if [[ "$(has_row hhhh88888888 "$YAML")" == 1 ]]; then
  pass "P4-grace: fresh tombstone kept this pass (two-pass honesty)"
else
  fail "P4-grace: fresh tombstone reaped in the same pass that stamped it"
fi
if [[ "$(n_sessions "$YAML")" == 5 ]]; then
  pass "census: exactly the 5 justified keepers remain (bbbb fresh, eeee running, ffff open-backlog, gggg live sibling, hhhh grace)"
else
  fail "census: expected 5 keepers, got $(n_sessions "$YAML")"
fi
if [[ "$(rendered_at "$YAML")" != "2020-01-01T00:00:00Z" && -n "$(rendered_at "$YAML")" ]]; then
  pass "rendered_at restamped by the sweep ($(rendered_at "$YAML"))"
else
  fail "rendered_at not restamped — still the fixture value"
fi
if grep -q "finished_rows_reaped=aaaa1111aaaa" "$SB/reap.err" && grep -q "cccc3333cccc" "$SB/reap.err"; then
  pass "reap stderr names the dropped sigs"
else
  fail "reap stderr missing finished_rows_reaped line: $(head -3 "$SB/reap.err")"
fi

# ═══ Pin 4: the pulse ghost count over a reaped registry ══════════════════
PULSE_NOW=1735500000
PULSE_PROBE="$SB/liveness-stub.sh"
cat > "$PULSE_PROBE" <<'PROBE'
#!/usr/bin/env bash
printf '%s\n' "${PULSE_TEST_PROBE_JSON:-{\"lanes\":[]}}"
PROBE
chmod +x "$PULSE_PROBE"
# The pulse's glm tier must not see the reap fixtures: their mtimes are real
# wall-clock while the beat runs on the fixed PULSE_NOW, which would read as
# age 0 ("glm-поток", live). The ghost leg's evidence is the lane journal.
PULSE_GLIM="$SB/pulse-glm"
mkdir -p "$PULSE_GLIM"

set_pulse_journal_age() { # <task_id> <age_s>
  local dir="$PULSE_TASKS/$1"
  mkdir -p "$dir"
  local j="$dir/journal.md"
  [[ -f "$j" ]] || printf -- '- 2026-01-01T00:00:00Z [phase] beat task=%s\n' "$1" > "$j"
  python3 -c "
import os
t = $PULSE_NOW - $2
os.utime('$j', (t, t))"
}

run_pulse() { # <registry-file>
  ACTIVE_YAML="$1" TASKS_DIR="$PULSE_TASKS" \
  ANTI_SILENCE_GLM_RUNS_DIR="$PULSE_GLIM" ANTI_SILENCE_STATE_ROOT="$SB/pulse-state" \
  CLAUDE_PROJECT_DIR="$REPO" \
  PULSE_LOG_FILE="$SB/pulse.log" PULSE_PID_FILE="$SB/pulse.pid" \
  LEADV2_LANE_LIVENESS_SCRIPT="$PULSE_PROBE" \
    bash "$PULSE_SH" --once "--now=${PULSE_NOW}" 2>"$SB/pulse.err"
}

# one dead lane whose journal is 31min old — the exact pre-reap ghost shape.
# No glm run dir: the codex-arm shape, reaped via the ledger terminal record.
GHOST_STATE="$SB/ghost-state"; mkdir -p "$GHOST_STATE"
GHOST_YAML="$GHOST_STATE/active.yaml"
write_registry "$GHOST_YAML"
add_row "$GHOST_YAML" aaaa1111aaaa $DEAD_PID 3600
set_pulse_journal_age aaaa1111aaaa 1860

# sanity: BEFORE the reap the pulse counts it (proves the fixture bites)
export PULSE_TEST_PROBE_JSON='{"lanes":[]}'
PRE_OUT="$(run_pulse "$GHOST_YAML")"
if printf '%s' "$PRE_OUT" | grep -q 'призраки: 1'; then
  pass "P4-pre: unreaped registry renders призраки: 1 (fixture bites)"
else
  fail "P4-pre: expected призраки: 1 before the reap, got: $(printf '%s' "$PRE_OUT" | head -2)"
fi

run_reap "$LIB" "$GHOST_STATE"
if [[ "$(n_sessions "$GHOST_YAML")" == 0 ]]; then
  pass "P4: reaped registry holds no rows"
else
  fail "P4: reaped registry still holds $(n_sessions "$GHOST_YAML") row(s)"
fi
POST_OUT="$(run_pulse "$GHOST_YAML")"
if printf '%s' "$POST_OUT" | grep -q 'призраки'; then
  fail "P4: ghost count not 0 over a reaped registry: $(printf '%s' "$POST_OUT" | tail -2)"
elif printf '%s' "$POST_OUT" | grep -Eq 'live=0|подавлена'; then
  pass "P4: pulse ghost count over a registry with no live lanes is 0"
else
  fail "P4: unexpected pulse output: $(printf '%s' "$POST_OUT" | head -2)"
fi

# ═══ Round-2 pins: the lead-owned row for CLOSED work (separate registries —
# the shared-world census pin above asserts exactly its own 5 keepers).
# Precedence under test: positive work evidence > backlog closure > liveness
# of any pid. A live lead_durable pid proves the LEAD process is alive, not
# the lane; it must not pin a row whose backlog row is closed.
R2_STATE="$SB/r2"; mkdir -p "$R2_STATE"
R2_YAML="$R2_STATE/active.yaml"

# P3d: lead-owned (live pid $$, backend terminal, no glm dir, no tombstone),
# backlog row CLOSED -> row must leave. Round-1 lib kept it forever (RED there).
write_registry "$R2_YAML"
add_row_shaped "$R2_YAML" 999911119999 $$ none terminal "docs/handoff/dispatch-xxxx/developer.stream.jsonl"
run_reap "$LIB" "$R2_STATE" || true
if [[ "$(has_row 999911119999 "$R2_YAML")" == 0 ]]; then
  pass "P3d: live lead-owned pid does not pin a closed-backlog row"
else
  fail "P3d: lead-owned closed-backlog row survived (ghost forever)"
fi

# P3e: same shape, backlog row OPEN -> in-flight armless lane survives.
write_registry "$R2_YAML"
add_row_shaped "$R2_YAML" ffff6666ffff $$ none terminal "docs/handoff/dispatch-xxxx/developer.stream.jsonl"
run_reap "$LIB" "$R2_STATE" || true
if [[ "$(has_row ffff6666ffff "$R2_YAML")" == 1 ]]; then
  pass "P3e: lead-owned row with OPEN backlog row stays (live lane never evicted)"
else
  fail "P3e: open-backlog lead-owned lane dropped"
fi

# P3f: lead-owned closed shape BUT glm journal growing -> stays (positive
# evidence outranks backlog closure).
write_registry "$R2_YAML"
add_row_shaped "$R2_YAML" 999922229999 $$ none terminal "docs/handoff/dispatch-xxxx/developer.stream.jsonl"
mk_glm 999922229999 complete 0
run_reap "$LIB" "$R2_STATE" || true
if [[ "$(has_row 999922229999 "$R2_YAML")" == 1 ]]; then
  pass "P3f: growing journal outranks a closed backlog row (row stays)"
else
  fail "P3f: fresh-journal lead-owned lane evicted"
fi

# P3g: 8-hex dispatch sig, live pid, no glm, NOT in the ledger sig->founder
# map -> the backlog leg must ABSTAIN (an 8-hex sig is never in the 12-hex
# mirror; treating absence as closed would evict every live codex/claude lane).
write_registry "$R2_YAML"
add_row_shaped "$R2_YAML" dispatch-ab12cd34 $$ none terminal "docs/handoff/dispatch-ab12cd34/developer.stream.jsonl"
run_reap "$LIB" "$R2_STATE" || true
if [[ "$(has_row dispatch-ab12cd34 "$R2_YAML")" == 1 ]]; then
  pass "P3g: unresolved 8-hex sig abstains — live dispatch-<sig8> lane stays"
else
  fail "P3g: live 8-hex dispatch lane evicted (namespace guard missing)"
fi

# P3h: 8-hex sig RESOLVABLE via a non-terminal ledger record to a CLOSED
# founder id -> row leaves (the resolved form of the backlog leg).
write_registry "$R2_YAML"
add_row_shaped "$R2_YAML" dispatch-ab12cd35 $$ none terminal "docs/handoff/dispatch-ab12cd35/developer.stream.jsonl"
run_reap "$LIB" "$R2_STATE" || true
if [[ "$(has_row dispatch-ab12cd35 "$R2_YAML")" == 0 ]]; then
  pass "P3h: 8-hex sig resolved to a closed founder id -> row gone"
else
  fail "P3h: ledger-resolvable closed lane survived"
fi

# P5: recovered_unowned, pidless, ALREADY tombstoned >grace, backlog closed ->
# drops THIS pass (round-1 kept it until the 86400s retention; 577cc2d2b7d4
# is exactly this shape on the live tree).
write_registry "$R2_YAML"
add_row_shaped "$R2_YAML" 999933339999 none 3600 terminal "docs/handoff/dispatch-kkkk/developer.stream.jsonl" true 3600
run_reap "$LIB" "$R2_STATE" || true
if [[ "$(has_row 999933339999 "$R2_YAML")" == 0 ]]; then
  pass "P5: tombstoned recovered row with closed backlog drops this pass"
else
  fail "P5: tombstoned recovered closed row waits for the 86400s retention"
fi

# P5b: recovered, tombstoned, backlog OPEN -> stays (retention owns visibility).
write_registry "$R2_YAML"
add_row_shaped "$R2_YAML" ffff6666ffff none 3600 terminal "docs/handoff/dispatch-ffff/developer.stream.jsonl" true 3600
run_reap "$LIB" "$R2_STATE" || true
if [[ "$(has_row ffff6666ffff "$R2_YAML")" == 1 ]]; then
  pass "P5b: tombstoned recovered row with OPEN backlog stays"
else
  fail "P5b: open-backlog recovered row dropped"
fi

# P7: lead-owned closed shape touched 30s ago (updated_at, no tombstone) ->
# grace window applies to last touch, not only to tombstones: stays this pass.
write_registry "$R2_YAML"
add_row_shaped "$R2_YAML" 999944449999 $$ none terminal "docs/handoff/dispatch-jjjj/developer.stream.jsonl" false 30
run_reap "$LIB" "$R2_STATE" || true
if [[ "$(has_row 999944449999 "$R2_YAML")" == 1 ]]; then
  pass "P7: row updated inside the grace window is not judged this pass"
else
  fail "P7: freshly-updated lead-owned row reaped without grace"
fi

# ═══ Negative controls: mutated scratch copies, each run and shown RED ════
mutate_lib() { # <anchor> <replacement> -> mutated copy at $SB/mutlib/
  local anchor="$1" replacement="$2"
  rm -rf "$SB/mutlib"; mkdir -p "$SB/mutlib/lib"
  cp "${SCRIPTS_DIR}/leadv2-state-path.sh" "$SB/mutlib/"
  cp "${SCRIPTS_DIR}/leadv2-portable-lock.sh" "$SB/mutlib/"
  cp "$LIB" "$SB/mutlib/lib/leadv2-lane-state.sh"
  python3 - "$SB/mutlib/lib/leadv2-lane-state.sh" "$anchor" "$replacement" <<'PYMUT'
import sys
p, anchor, replacement = sys.argv[1:4]
s = open(p, encoding='utf-8').read()
n = s.count(anchor)
assert n == 1, f'anchor count {n} != 1: {anchor!r}'
open(p, 'w', encoding='utf-8').write(s.replace(anchor, replacement))
PYMUT
}

# MUTATION-A: terminal-status recognition reverted -> pin 1 goes RED
mutate_lib \
  "terminal=st in ('complete','failed') or os.path.exists(os.path.join(newest,'exit_code'))" \
  "terminal=False  # MUTATION-A"
A_STATE="$SB/mut-a"; mkdir -p "$A_STATE"
A_YAML="$A_STATE/active.yaml"; write_registry "$A_YAML"
add_row "$A_YAML" aa11aa11aa11 $DEAD_PID 3600
mk_glm aa11aa11aa11 complete 1800
run_reap "$SB/mutlib/lib/leadv2-lane-state.sh" "$A_STATE" || true
if [[ "$(has_row aa11aa11aa11 "$A_YAML")" == 1 ]]; then
  pass "NC-A RED: mutant kept the terminal-run-dir row (anchor proves pin 1)"
else
  fail "NC-A: mutant still green — control proves nothing"
fi
run_reap "$LIB" "$A_STATE" || true
if [[ "$(has_row aa11aa11aa11 "$A_YAML")" == 0 ]]; then
  pass "NC-A GREEN: clean lib drops the same isolated fixture"
else
  fail "NC-A GREEN: clean lib kept the isolated terminal row — glm leg untested"
fi

# MUTATION-B: journal-growth keep guard removed -> pin 2 goes RED
mutate_lib \
  "if fresh:" \
  "if False:  # MUTATION-B"
B_STATE="$SB/mut-b"; mkdir -p "$B_STATE"
B_YAML="$B_STATE/active.yaml"; write_registry "$B_YAML"
add_row "$B_YAML" bbbb2222bbbb $DEAD_PID 3600
mk_glm bbbb2222bbbb complete 0
run_reap "$SB/mutlib/lib/leadv2-lane-state.sh" "$B_STATE" || true
if [[ "$(has_row bbbb2222bbbb "$B_YAML")" == 0 ]]; then
  pass "NC-B RED: mutant evicted the growing-journal lane (anchor proves pin 2)"
else
  fail "NC-B: mutant still green — control proves nothing"
fi

# MUTATION-C: backlog-closed leg disabled -> pin 3 goes RED
# (round-2: anchor updated to the namespace-safe founder form of the line)
mutate_lib \
  "return bool(_open_ids) and founder is not None and founder not in _open_ids" \
  "return False  # MUTATION-C"
C_STATE="$SB/mut-c"; mkdir -p "$C_STATE"
C_YAML="$C_STATE/active.yaml"; write_registry "$C_YAML"
add_row "$C_YAML" cccc3333cccc $DEAD_PID 3600
run_reap "$SB/mutlib/lib/leadv2-lane-state.sh" "$C_STATE" || true
if [[ "$(has_row cccc3333cccc "$C_YAML")" == 1 ]]; then
  pass "NC-C RED: mutant kept the closed-backlog row (anchor proves pin 3)"
else
  fail "NC-C: mutant still green — control proves nothing"
fi
run_reap "$LIB" "$C_STATE" || true
if [[ "$(has_row cccc3333cccc "$C_YAML")" == 0 ]]; then
  pass "NC-C GREEN: clean lib drops the closed-backlog row"
else
  fail "NC-C GREEN: clean lib kept the closed-backlog row"
fi

# MUTATION-D: reap application removed -> the pulse ghost count stays 1
mutate_lib \
  "rows[:]=[r for r in rows if id(r) not in _drop_ids]" \
  "pass  # MUTATION-D"
D_STATE="$SB/mut-d"; mkdir -p "$D_STATE"
D_YAML="$D_STATE/active.yaml"; write_registry "$D_YAML"
add_row "$D_YAML" aaaa1111aaaa $DEAD_PID 3600
set_pulse_journal_age aaaa1111aaaa 1860
run_reap "$SB/mutlib/lib/leadv2-lane-state.sh" "$D_STATE" || true
D_OUT="$(run_pulse "$D_YAML")"
if [[ "$(n_sessions "$D_YAML")" == 1 ]] && printf '%s' "$D_OUT" | grep -q 'призраки: 1'; then
  pass "NC-D RED: with reaping disabled the registry keeps the row and the pulse renders призраки: 1"
else
  fail "NC-D: mutant still green — control proves nothing ($(n_sessions "$D_YAML") rows; out: $(printf '%s' "$D_OUT" | tail -1))"
fi
run_reap "$LIB" "$D_STATE" || true
D_OUT2="$(run_pulse "$D_YAML")"
if [[ "$(n_sessions "$D_YAML")" == 0 ]] && ! printf '%s' "$D_OUT2" | grep -q 'призраки'; then
  pass "NC-D GREEN: clean lib reaps the same row and the ghost count drops to 0"
else
  fail "NC-D GREEN: clean lib left the ghost standing ($(n_sessions "$D_YAML") rows; out: $(printf '%s' "$D_OUT2" | tail -1))"
fi

# MUTATION-E: round-2 precondition reverted to tombstone-only dating -> P3d
# goes RED (the lead-owned closed row with dead_at null is never judged).
mutate_lib \
  "age = dead_age(row) if row.get('dead_at') else updated_age(row)" \
  "age = dead_age(row)  # MUTATION-E"
E_STATE="$SB/mut-e"; mkdir -p "$E_STATE"
E_YAML="$E_STATE/active.yaml"; write_registry "$E_YAML"
add_row_shaped "$E_YAML" 999911119999 $$ none terminal "docs/handoff/dispatch-xxxx/developer.stream.jsonl"
run_reap "$SB/mutlib/lib/leadv2-lane-state.sh" "$E_STATE" || true
if [[ "$(has_row 999911119999 "$E_YAML")" == 1 ]]; then
  pass "NC-E RED: mutant kept the live-pid closed-backlog row (anchor proves P3d)"
else
  fail "NC-E: mutant still green — control proves nothing"
fi
run_reap "$LIB" "$E_STATE" || true
if [[ "$(has_row 999911119999 "$E_YAML")" == 0 ]]; then
  pass "NC-E GREEN: clean lib drops the same lead-owned fixture"
else
  fail "NC-E GREEN: clean lib kept the lead-owned closed row"
fi

# MUTATION-F: namespace guard removed from the backlog leg -> P3g goes RED
# (every unresolved 8-hex dispatch lane reads as closed and is evicted).
mutate_lib \
  "and founder is not None and founder not in _open_ids" \
  "and founder not in _open_ids  # MUTATION-F"
F_STATE="$SB/mut-f"; mkdir -p "$F_STATE"
F_YAML="$F_STATE/active.yaml"; write_registry "$F_YAML"
add_row_shaped "$F_YAML" dispatch-ab12cd34 $$ none terminal "docs/handoff/dispatch-ab12cd34/developer.stream.jsonl"
run_reap "$SB/mutlib/lib/leadv2-lane-state.sh" "$F_STATE" || true
if [[ "$(has_row dispatch-ab12cd34 "$F_YAML")" == 0 ]]; then
  pass "NC-F RED: mutant evicted the unresolved 8-hex live lane (anchor proves P3g)"
else
  fail "NC-F: mutant still green — control proves nothing"
fi
# fresh fixture for GREEN: the RED mutant already consumed the row above
write_registry "$F_YAML"
add_row_shaped "$F_YAML" dispatch-ab12cd34 $$ none terminal "docs/handoff/dispatch-ab12cd34/developer.stream.jsonl"
run_reap "$LIB" "$F_STATE" || true
if [[ "$(has_row dispatch-ab12cd34 "$F_YAML")" == 1 ]]; then
  pass "NC-F GREEN: clean lib keeps the same 8-hex lane"
else
  fail "NC-F GREEN: clean lib evicted the unresolved 8-hex lane"
fi

# MUTATION-G: recovered skip restored to blanket -> P5 goes RED (the
# tombstoned recovered row waits for the 86400s retention again).
mutate_lib \
  "if row.get('recovered') and not row.get('dead_at'): continue" \
  "if row.get('recovered'): continue  # MUTATION-G"
G_STATE="$SB/mut-g"; mkdir -p "$G_STATE"
G_YAML="$G_STATE/active.yaml"; write_registry "$G_YAML"
add_row_shaped "$G_YAML" 999933339999 none 3600 terminal "docs/handoff/dispatch-kkkk/developer.stream.jsonl" true 3600
run_reap "$SB/mutlib/lib/leadv2-lane-state.sh" "$G_STATE" || true
if [[ "$(has_row 999933339999 "$G_YAML")" == 1 ]]; then
  pass "NC-G RED: mutant kept the tombstoned recovered closed row (anchor proves P5)"
else
  fail "NC-G: mutant still green — control proves nothing"
fi
run_reap "$LIB" "$G_STATE" || true
if [[ "$(has_row 999933339999 "$G_YAML")" == 0 ]]; then
  pass "NC-G GREEN: clean lib drops it this pass"
else
  fail "NC-G GREEN: clean lib kept the recovered closed row"
fi

printf '[TEST] %s: %d passed, %d failed\n' "test-lane-registry-drops-finished-lanes" "$PASS" "$FAIL"
if (( FAIL > 0 )); then
  printf '[TEST] failures:\n'; printf '  - %s\n' "${ERRORS[@]}"
  exit 1
fi
exit 0
