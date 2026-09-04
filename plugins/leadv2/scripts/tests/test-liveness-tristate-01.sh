#!/usr/bin/env bash
# changed-scope triggers, self-registered (SD-SUITE-MAP-SERIALIZES-EVERY-WAVE-01, migrated from tests/run-all.sh EXTRA_SUITE_MAP; discovered by scan_suite_triggers):
# run-all-triggers: leadv2-lane-heartbeat.sh leadv2-lane-state.sh leadv2-watch-lifecycle.sh
# tests/test-liveness-tristate-01.sh — LIVENESS-HAS-NO-SUITE-01.
#
# 2026-09-03: three sessions got the answer to "is this lane alive" wrong
# twelve measured times in one evening (see docs/handoff/LIVENESS-HAS-NO-
# SUITE-01/report.md for the full census and per-case citations). None of
# the twelve was covered by any suite. This suite locks four of the rules
# the mission called out onto the specific functions in THIS repo that
# already (mostly) implement them — never a teaching-example fixture — via
# mutation-tested negative controls applied to SCRATCH copies (the tracked
# files are never modified by this suite; off_limits per lane-mission.md).
#
# Checks:
#   T1  lane_alive() (lib/leadv2-lane-state.sh) must answer dead (rc 1), not
#       alive (rc 0), when a genuinely-alive pid's OBSERVED start time does
#       not match the RECORDED one (case 5: pid reuse). A bare `kill -0`
#       would get this wrong; lane_alive's (pid, start-time) pair must not.
#       NC: mutate the tri-corroboration comparison inside
#       _lv2_lane_state_mutate() on a scratch copy -> same scenario now
#       answers alive -> must be caught (baseline_rc=0 vs mutated_rc=1 diff).
#   T2  leadv2-lane-heartbeat.sh `status` on a task_id with NO record must
#       return an exit code DISTINCT from both a live answer (rc 0,
#       status=running) and a dead answer (rc 0, status=dead) — cases 4 and
#       12 require this to be representable in the return value, not only
#       in printed text. NC: mutate the not_found branch on a scratch copy
#       to exit 0 -> unknown collapses onto the same rc as alive/dead.
#   T3  static: neither lib/leadv2-lane-state.sh nor
#       lib/leadv2-watch-lifecycle.sh contains a liveness check that matches
#       a process BY NAME PATTERN across the process table (`pgrep -f`,
#       `ps ... | grep`) — cases 1, 2, 3, 11. NC: insert a `pgrep -f` line
#       inside a real function body on a scratch copy -> scanner must name
#       file:line.
#   T4  static: neither of those two files reads `$?` after a value-losing
#       pipe stage (head/tail/wc/sort/uniq/column) instead of from the
#       command itself — cases 7, 8. NC: insert `cmd | head -3` then a
#       following `rc=$?` inside a real function body on a scratch copy ->
#       scanner must name file:line.
#   T5  static (SCANNER-MISSES-PS-SUBSTRING-01, 2026-09-04): the T3 idioms
#       (`pgrep -f`, `ps | grep`) are two spellings of a CLASS — "a liveness
#       decision made by enumerating the process table and selecting rows by
#       TEXT membership instead of by a numeric pid taken from a record".
#       A third spelling — `ps -axo` + `if worktree not in line` — was live
#       in lib/leadv2-lane-state.sh reconcile() and T3 stayed green over it;
#       the recovered rows it fabricates resurrected closed lanes twice in
#       one evening (see docs/handoff/SCANNER-MISSES-PS-SUBSTRING-01/).
#       T5 scans the same two files for the class: (a) any process-table
#       ENUMERATION (`pgrep` with any flags; `ps` with table-wide flags
#       -e/-A/-a/-ax/-axo/-eo/-ef/aux/ax; listing /proc), then (b) a TEXT
#       row-select within the same function (`not in`, `x in line`, grep,
#       `=~`, `case`, `.find(`, `== *...*`). Per-pid lookups (`ps -p <pid>
#       -o ...`, reading /proc/<pid>/stat for a recorded pid) are NOT
#       enumeration and stay green by design — wl_cmdline_match() in
#       watch-lifecycle.sh is the sanctioned per-pid form.
#       DELIBERATE RED: this check currently FAILS on the live lane-state.sh
#       violator; lane-mission.md forbids fixing lib/ in this lane, so the
#       red stands until the reconcile() fix lands and then goes green. The
#       findings census repo-wide lives in report.md, not in this suite.
#
# Known real violators OUTSIDE this suite's two-file scan scope
# (leadv2-fanout.sh:1244 `pgrep -f "/leadv2 ${tid}"`, leadv2-spawn-rate.sh:119
# `ps ... | grep -E 'leadv2-(...)'`) are documented in report.md as findings,
# not fixed here: lane-mission.md forbids editing plugins/leadv2/scripts/*.sh
# in this lane ("если перепись нашла нарушителя, это находка в отчёт, а не
# правка в этой линии").
#
# Bash 3.2 compatible (no assoc arrays, no ${x^^}).
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
LANE_STATE_SH="${SCRIPTS_ROOT}/lib/leadv2-lane-state.sh"
WATCH_LIFECYCLE_SH="${SCRIPTS_ROOT}/lib/leadv2-watch-lifecycle.sh"
HEARTBEAT_SH="${SCRIPTS_ROOT}/leadv2-lane-heartbeat.sh"
REGISTRY_SH="${SCRIPTS_ROOT}/leadv2-active-registry.sh"
STATE_PATH_SH="${SCRIPTS_ROOT}/leadv2-state-path.sh"

PASS=0; FAIL=0; ERRORS=()
log()  { printf -- '[TEST] %s\n' "$*"; }
pass() { PASS=$((PASS + 1)); log "PASS: $1"; }
fail() { FAIL=$((FAIL + 1)); ERRORS+=("FAIL: $1"); log "FAIL: $1"; }

SCRATCH_FILES=()
cleanup() { local f; for f in "${SCRATCH_FILES[@]:-}"; do [[ -n "$f" ]] && rm -f "$f"; done; }
trap cleanup EXIT

_new_sandbox() {
  local d
  d="$(mktemp -d "${TMPDIR:-/tmp}/lv2-liveness-test.XXXXXX")"
  mkdir -p "${d}/proj" "${d}/state"
  (cd "${d}/proj" && git init -q) >/dev/null 2>&1
  printf -- '%s' "$d"
}

# ── T1: (pid, start-time) pair -- pid reuse must resolve to dead ────────────

test_1_mismatched_start_time_is_dead() {
  log "T1: lane_alive() with a mismatched start time -> dead, not alive"
  local sandbox yaml rc_lane rc_naive
  sandbox="$(_new_sandbox)"

  LEADV2_PROJECT_ROOT="${sandbox}/proj" LEADV2_STATE_ROOT="${sandbox}/state" bash -c '
    source "'"$LANE_STATE_SH"'"
    lane_register "T1" "sess1" "'"${sandbox}"'/proj" "phase1" "'"$$"'"
  ' >/dev/null

  yaml="$(LEADV2_PROJECT_ROOT="${sandbox}/proj" LEADV2_STATE_ROOT="${sandbox}/state" \
    bash "$STATE_PATH_SH" --no-link active.yaml)"

  # Simulate pid reuse: the recorded start time no longer matches what `ps`
  # observes for this still-genuinely-alive pid ($$ of this test process).
  python3 -c "
import yaml
with open('${yaml}', encoding='utf-8') as f: d = yaml.safe_load(f)
d['sessions'][0]['pid_start_time'] = 'Mon Jan  1 00:00:00 1970'
with open('${yaml}', 'w', encoding='utf-8') as f: yaml.safe_dump(d, f, default_flow_style=False, sort_keys=False)
"

  LEADV2_PROJECT_ROOT="${sandbox}/proj" LEADV2_STATE_ROOT="${sandbox}/state" bash -c '
    source "'"$LANE_STATE_SH"'"
    lane_alive "T1"
  ' >/dev/null 2>&1
  rc_lane=$?
  kill -0 "$$" 2>/dev/null; rc_naive=$?

  if [[ "$rc_naive" -eq 0 && "$rc_lane" -eq 1 ]]; then
    pass "T1: pid genuinely alive (naive kill-0 rc=$rc_naive) but lane_alive correctly says dead (rc=$rc_lane) on start-time mismatch"
  else
    fail "T1: expected naive_rc=0 (genuinely alive) and lane_alive_rc=1 (dead on mismatch); got naive_rc=$rc_naive lane_alive_rc=$rc_lane"
  fi
  rm -rf "$sandbox"
}

# T1 negative control: mutate the tri-corroboration comparison on a scratch
# copy so a mismatched start time no longer matters -> the same scenario
# above must now report alive (rc 0), proving T1 actually bites.
test_1nc_mutation_caught() {
  log "T1-NC: mutating alive()'s pair comparison must flip T1's verdict"
  local scratch sandbox yaml rc_mutated
  scratch="${SCRIPTS_ROOT}/lib/.nc-mutated-leadv2-lane-state.sh"
  SCRATCH_FILES+=("$scratch")

  # Mutation INSIDE the function body (not top-of-file): the return line of
  # alive() -- the exact tri-corroboration this suite locks -- becomes
  # "always true if the pid answers kill(pid,0)", i.e. the bare-kill-0 bug
  # case 5 describes.
  sed 's|    return bool(recorded and observed and recorded == observed)|    return True  # NC-MUTATION: start-time corroboration dropped|' \
    "$LANE_STATE_SH" > "$scratch"
  if cmp -s "$LANE_STATE_SH" "$scratch"; then
    fail "T1-NC: mutation pattern not found in $LANE_STATE_SH -- update this NC (the source line changed)"
    return
  fi

  sandbox="$(_new_sandbox)"
  LEADV2_PROJECT_ROOT="${sandbox}/proj" LEADV2_STATE_ROOT="${sandbox}/state" bash -c '
    source "'"$scratch"'"
    lane_register "T1NC" "sess1" "'"${sandbox}"'/proj" "phase1" "'"$$"'"
  ' >/dev/null
  yaml="$(LEADV2_PROJECT_ROOT="${sandbox}/proj" LEADV2_STATE_ROOT="${sandbox}/state" \
    bash "$STATE_PATH_SH" --no-link active.yaml)"
  python3 -c "
import yaml
with open('${yaml}', encoding='utf-8') as f: d = yaml.safe_load(f)
d['sessions'][0]['pid_start_time'] = 'Mon Jan  1 00:00:00 1970'
with open('${yaml}', 'w', encoding='utf-8') as f: yaml.safe_dump(d, f, default_flow_style=False, sort_keys=False)
"
  LEADV2_PROJECT_ROOT="${sandbox}/proj" LEADV2_STATE_ROOT="${sandbox}/state" bash -c '
    source "'"$scratch"'"
    lane_alive "T1NC"
  ' >/dev/null 2>&1
  rc_mutated=$?

  log "T1-NC: baseline_rc=1 (from T1, unmutated) mutated_rc=${rc_mutated}"
  if [[ "$rc_mutated" -eq 0 ]]; then
    pass "T1-NC: mutated alive() now (wrongly) reports the reused pid as alive (rc=0) -- the negative control is red as required, proving T1 is falsifiable"
  else
    fail "T1-NC: mutation did not flip the verdict (mutated_rc=$rc_mutated) -- T1 would not catch this regression"
  fi
  rm -rf "$sandbox"
}

# ── T2: absent record -> unknown, distinct return value from both extremes ──

_hb_status_rc() { # <hb_script> <sandbox> <task_id> -> sets HB_JSON, returns rc
  HB_JSON="$(LEADV2_PROJECT_ROOT="${2}/proj" LEADV2_STATE_ROOT="${2}/state" \
    bash "$1" status "$3" --json 2>/dev/null)"
  return $?
}

test_2_absent_record_distinct_rc() {
  log "T2: no record at all -> return code distinct from BOTH alive and dead"
  local sandbox rc_unknown rc_alive rc_dead
  sandbox="$(_new_sandbox)"

  # A registered, fresh row -> alive/running.
  LEADV2_PROJECT_ROOT="${sandbox}/proj" LEADV2_STATE_ROOT="${sandbox}/state" bash -c '
    source "'"$REGISTRY_SH"'"
    leadv2_active_register "ALIVE" "Standard" "'"${sandbox}"'/proj" "test-branch" "false"
    leadv2_active_heartbeat "ALIVE" "doing work"
  ' >/dev/null

  # A registered, stale-heartbeat row with a confirmed-dead local pid -> dead.
  LEADV2_PROJECT_ROOT="${sandbox}/proj" LEADV2_STATE_ROOT="${sandbox}/state" bash -c '
    source "'"$REGISTRY_SH"'"
    leadv2_active_register "DEAD" "Standard" "'"${sandbox}"'/proj" "test-branch" "false"
  ' >/dev/null
  local yaml old_ts
  yaml="$(LEADV2_PROJECT_ROOT="${sandbox}/proj" LEADV2_STATE_ROOT="${sandbox}/state" \
    bash "$STATE_PATH_SH" --no-link active.yaml)"
  old_ts="$(python3 -c "import datetime; print((datetime.datetime.now(datetime.timezone.utc)-datetime.timedelta(minutes=60)).strftime('%Y-%m-%dT%H:%M:%SZ'))")"
  python3 -c "
import yaml
with open('${yaml}', encoding='utf-8') as f: d = yaml.safe_load(f)
for s in d.get('sessions') or []:
    if s.get('task_id') == 'DEAD':
        s['pid'] = 999999
        s['last_pulse_at'] = '${old_ts}'
with open('${yaml}', 'w', encoding='utf-8') as f: yaml.safe_dump(d, f, default_flow_style=False, sort_keys=False)
"

  local json_alive json_dead json_unknown
  _hb_status_rc "$HEARTBEAT_SH" "$sandbox" "ALIVE"; rc_alive=$?; json_alive="$HB_JSON"
  _hb_status_rc "$HEARTBEAT_SH" "$sandbox" "DEAD"; rc_dead=$?; json_dead="$HB_JSON"
  _hb_status_rc "$HEARTBEAT_SH" "$sandbox" "NEVER-REGISTERED"; rc_unknown=$?; json_unknown="$HB_JSON"

  log "T2: rc_alive=$rc_alive ($json_alive) rc_dead=$rc_dead ($json_dead) rc_unknown=$rc_unknown ($json_unknown)"
  if [[ "$rc_alive" -eq 0 && "$rc_dead" -eq 0 && "$rc_unknown" -ne 0 && "$rc_unknown" -ne "$rc_alive" ]]; then
    pass "T2: absent-record rc=$rc_unknown differs from both alive(rc=$rc_alive) and dead(rc=$rc_dead) in the RETURN VALUE, not only in text"
  else
    fail "T2: expected rc_unknown distinct from rc_alive=$rc_alive and rc_dead=$rc_dead; got rc_unknown=$rc_unknown"
  fi
  rm -rf "$sandbox"
}

# T2 negative control: mutate the not_found branch on a scratch copy to exit
# 0 (collapse "unknown" onto the same rc as every real verdict) -> must be
# caught.
test_2nc_mutation_caught() {
  log "T2-NC: mutating the not_found exit code must collapse it onto rc=0"
  local scratch sandbox rc_mutated
  scratch="${SCRIPTS_ROOT}/.nc-mutated-leadv2-lane-heartbeat.sh"
  SCRATCH_FILES+=("$scratch")

  python3 - "$HEARTBEAT_SH" "$scratch" <<'PY'
import sys
src, dst = sys.argv[1], sys.argv[2]
with open(src, encoding='utf-8') as f:
    text = f.read()
needle = 'if not all_mode and not rows:\n    print(json.dumps({"error": "not_found", "message": f"task_id {task_id} not in active.yaml"}))\n    sys.exit(4)'
replacement = 'if not all_mode and not rows:\n    print(json.dumps({"error": "not_found", "message": f"task_id {task_id} not in active.yaml"}))\n    sys.exit(0)  # NC-MUTATION: unknown collapsed onto the same rc as a real verdict'
if needle not in text:
    print("NC-SETUP-FAIL: not_found block not found verbatim", file=sys.stderr)
    sys.exit(2)
with open(dst, 'w', encoding='utf-8') as f:
    f.write(text.replace(needle, replacement, 1))
PY
  if [[ $? -ne 0 ]]; then
    fail "T2-NC: mutation setup failed -- update this NC (the source block changed)"
    return
  fi

  sandbox="$(_new_sandbox)"
  LEADV2_PROJECT_ROOT="${sandbox}/proj" LEADV2_STATE_ROOT="${sandbox}/state" bash -c '
    source "'"$REGISTRY_SH"'"
    leadv2_active_register "OTHER" "Standard" "'"${sandbox}"'/proj" "test-branch" "false"
  ' >/dev/null
  LEADV2_PROJECT_ROOT="${sandbox}/proj" LEADV2_STATE_ROOT="${sandbox}/state" \
    bash "$scratch" status "NEVER-REGISTERED" --json >/dev/null 2>&1
  rc_mutated=$?

  log "T2-NC: baseline_rc=4 (from T2, unmutated) mutated_rc=${rc_mutated}"
  if [[ "$rc_mutated" -eq 0 ]]; then
    pass "T2-NC: mutated not_found path now (wrongly) returns rc=0, indistinguishable from a real verdict -- the negative control is red as required"
  else
    fail "T2-NC: mutation did not collapse the rc (mutated_rc=$rc_mutated) -- T2 would not catch this regression"
  fi
  rm -rf "$sandbox"
}

# ── T3: static -- no process-name-pattern liveness check ────────────────────

_scan_process_name_pattern() { # <file>...
  python3 - "$@" <<'PY'
import re, sys
patt = re.compile(r'pgrep\s+-f|ps\b[^\n]*\|\s*grep')
bad = 0
for path in sys.argv[1:]:
    with open(path, encoding='utf-8') as f:
        for i, line in enumerate(f, 1):
            if patt.search(line):
                print("%s:%d: process-name-pattern liveness check: %s" % (path, i, line.strip()))
                bad += 1
sys.exit(1 if bad else 0)
PY
}

test_3_no_process_name_pattern() {
  log "T3: static scan -- no pgrep -f / ps|grep in the two canonical liveness libs"
  local out rc
  out="$(_scan_process_name_pattern "$LANE_STATE_SH" "$WATCH_LIFECYCLE_SH")"
  rc=$?
  if [[ "$rc" -eq 0 ]]; then
    pass "T3: no process-name-pattern liveness check found in scan scope"
  else
    fail "T3: process-name-pattern liveness check(s) found:\n${out}"
  fi
}

test_3nc_mutation_caught() {
  log "T3-NC: inserting a pgrep -f line inside a real function body must be caught"
  local scratch out rc
  scratch="${SCRIPTS_ROOT}/lib/.nc-pattern-leadv2-lane-state.sh"
  SCRATCH_FILES+=("$scratch")
  awk '
    { print }
    /^_lv2_lane_state_mutate\(\) \{/ { print "  pgrep -f \"$1\" >/dev/null 2>&1 && return 0  # NC-MUTATION" }
  ' "$LANE_STATE_SH" > "$scratch"
  if cmp -s "$LANE_STATE_SH" "$scratch"; then
    fail "T3-NC: insertion anchor not found -- update this NC"
    return
  fi
  out="$(_scan_process_name_pattern "$scratch")"
  rc=$?
  log "T3-NC: baseline_rc=0 (from T3, unmutated) mutated_rc=${rc}"
  if [[ "$rc" -ne 0 ]] && printf '%s' "$out" | grep -q "${scratch}:"; then
    pass "T3-NC: scanner caught the injected pgrep -f and named file:line -- $(printf '%s' "$out" | head -1)"
  else
    fail "T3-NC: scanner did not flag the injected pgrep -f (rc=$rc, out=$out)"
  fi
}

# ── T4: static -- no $? read after a value-losing pipe stage ────────────────

_scan_pipeline_rc_capture() { # <file>...
  python3 - "$@" <<'PY'
import re, sys
pipe_patt = re.compile(r'\|\s*(head|tail|wc|sort|uniq|column)\b')
bad = 0
for path in sys.argv[1:]:
    with open(path, encoding='utf-8') as f:
        lines = f.readlines()
    for i, line in enumerate(lines):
        if 'PIPESTATUS' in line:
            continue
        if not pipe_patt.search(line):
            continue
        window = [line] + lines[i + 1:i + 3]
        for w in window:
            if 'PIPESTATUS' in w:
                break
            if re.search(r'\$\?', w):
                print("%s:%d: $? read after a value-losing pipe stage instead of from the command itself: %s"
                      % (path, i + 1, line.strip()))
                bad += 1
                break
sys.exit(1 if bad else 0)
PY
}

test_4_no_pipeline_rc_after_filter() {
  log "T4: static scan -- no \$? captured after head/tail/wc/sort/uniq in the two canonical liveness libs"
  local out rc
  out="$(_scan_pipeline_rc_capture "$LANE_STATE_SH" "$WATCH_LIFECYCLE_SH")"
  rc=$?
  if [[ "$rc" -eq 0 ]]; then
    pass "T4: no post-filter-pipe \$? capture found in scan scope"
  else
    fail "T4: post-filter-pipe \$? capture(s) found:\n${out}"
  fi
}

test_4nc_mutation_caught() {
  log "T4-NC: inserting a piped-through-head command + trailing \$? read must be caught"
  local scratch out rc
  scratch="${SCRIPTS_ROOT}/lib/.nc-pipe-leadv2-lane-state.sh"
  SCRATCH_FILES+=("$scratch")
  awk '
    { print }
    /^_lv2_lane_state_mutate\(\) \{/ {
      print "  ps -eo pid,comm | head -3  # NC-MUTATION"
      print "  local _nc_rc=$?"
    }
  ' "$LANE_STATE_SH" > "$scratch"
  if cmp -s "$LANE_STATE_SH" "$scratch"; then
    fail "T4-NC: insertion anchor not found -- update this NC"
    return
  fi
  out="$(_scan_pipeline_rc_capture "$scratch")"
  rc=$?
  log "T4-NC: baseline_rc=0 (from T4, unmutated) mutated_rc=${rc}"
  if [[ "$rc" -ne 0 ]] && printf '%s' "$out" | grep -q "${scratch}:"; then
    pass "T4-NC: scanner caught the post-filter-pipe \$? read and named file:line -- $(printf '%s' "$out" | head -1)"
  else
    fail "T4-NC: scanner did not flag the injected pattern (rc=$rc, out=$out)"
  fi
}

# ── T5: static -- no text-matched process-table liveness decision ────────────
# Class check (see header). Detects: (a) the two locked T3 idioms verbatim,
# (b) process-table enumeration followed within a 15-line window by a TEXT
# row-select (`not in`, `x in line`, grep, `=~`, `case`, `.find(`, `== *..*`),
# (c) /proc LISTING (listdir/iterdir/scandir, /proc/[0-9]* glob) followed by a
# text row-select. Per-pid ps (`ps -p`, `ps -o ... -p`) and per-pid
# /proc/<pid>/stat reads are not enumeration and never open a window.

_scan_text_matched_process_table() { # <file>...
  python3 - "$@" <<'PY'
import re, sys
IDIOM = re.compile(r'pgrep\s+-f|ps\b[^\n]*\|\s*grep')
ENUM  = re.compile(r'\bps\b[^|;&\n]*')
# table-wide ps flags: -e/-A/-a/-ax/-axo/-eo/-ef/-Ao/... ('a'/'A'/'e' anywhere
# in a dash-token). (?<![a-zA-Z]) not \b: '-axo' after a quote has no \b.
ENUM_FLAG = re.compile(r'(?<![a-zA-Z])-[a-zA-Z]*[eEaA][a-zA-Z]*\b|(?<!\S)(?:ax|aux)\b')
PROC_LIST = re.compile(r"(?:listdir|scandir|iterdir)\s*\(\s*['\"]/proc|/proc/\[[0-9]\*?\]")
TEXT  = re.compile(r"\bnot\s+in\s+\w+"
                   r"|\b(?:if|elif|while)\b[^:\n]*\b\w+\s+in\s+\w+"
                   r"|\bgrep\b|\.find\(|=~|\bcase\s+\S+\s+in\b|==\s*['\"]?\*")
WINDOW = 15
bad = 0
for path in sys.argv[1:]:
    with open(path, encoding='utf-8') as f:
        lines = f.readlines()
    for i, line in enumerate(lines):
        if line.lstrip().startswith('#'):
            continue
        hit = None
        if IDIOM.search(line):
            hit = 'named idiom (pgrep -f / ps|grep)'
        else:
            m = ENUM.search(line)
            if m and ENUM_FLAG.search(line[m.start():m.end()]):
                hit = 'ps table-wide enumeration'
            elif PROC_LIST.search(line):
                hit = '/proc listing'
        if hit:
            for w in lines[i:i + WINDOW + 1]:
                if w.lstrip().startswith('#'):
                    continue
                tm = TEXT.search(w)
                if tm:
                    print("%s:%d: liveness by process-table enumeration + TEXT row-select (%s; text select: %s)"
                          % (path, i + 1, hit, w.strip()))
                    bad += 1
                    break
sys.exit(1 if bad else 0)
PY
}

test_5_no_text_matched_process_table() {
  log "T5: static scan -- no ps/pgrep//proc enumeration + text row-select in the two canonical liveness libs"
  local out rc
  out="$(_scan_text_matched_process_table "$LANE_STATE_SH" "$WATCH_LIFECYCLE_SH")"
  rc=$?
  if [[ "$rc" -eq 0 ]]; then
    pass "T5: no text-matched process-table liveness decision found in scan scope"
  else
    # DELIBERATE RED: the known live violator (lane-state.sh reconcile) is
    # expected here until the fix lane lands; every finding must be a real
    # class member, not scanner noise. Findings census: report.md.
    fail "T5: text-matched process-table liveness decision(s) found (expected: the known lane-state.sh reconcile violator; any OTHER line is a new finding for the report):\n${out}"
  fi
}

# T5-NC (a): the form T3 missed — `ps -axo` enumeration + `not in` text
# select, inserted INSIDE a real function body of a scratch copy of a CLEAN
# file (watch-lifecycle.sh scans green at baseline). Scanner must name file:line.
test_5nc_substring_caught() {
  log "T5-NC: inserting ps -axo + 'not in' row-select inside a real function body must be caught"
  local scratch out rc
  scratch="${SCRIPTS_ROOT}/lib/.nc-substr-leadv2-watch-lifecycle.sh"
  SCRATCH_FILES+=("$scratch")
  awk '
    { print }
    /^wl_cmdline_match\(\) \{/ {
      print "  ps -axo pid=,command= 2>/dev/null | while read -r _nc_line; do"
      print "    if [[ \"$1\" not in \"$_nc_line\" ]]; then continue; fi  # NC-MUTATION: substring row-select"
      print "  done"
    }
  ' "$WATCH_LIFECYCLE_SH" > "$scratch"
  if cmp -s "$WATCH_LIFECYCLE_SH" "$scratch"; then
    fail "T5-NC: insertion anchor not found -- update this NC"
    return
  fi
  out="$(_scan_text_matched_process_table "$scratch")"
  rc=$?
  log "T5-NC: baseline_rc=0 (watch-lifecycle.sh unmutated) mutated_rc=${rc}"
  if [[ "$rc" -ne 0 ]] && printf '%s' "$out" | grep -q "${scratch}:"; then
    pass "T5-NC: scanner caught the injected ps -axo + not-in row-select and named file:line -- $(printf '%s' "$out" | head -1)"
  else
    fail "T5-NC: scanner did not flag the injected substring row-select (rc=$rc, out=$out)"
  fi
}

# T5-NC (b): backward compatibility — the OLD `pgrep -f` control must still
# bite under the class scanner (it is a class member: pgrep always selects by
# name pattern).
test_5ncb_pgrep_f_caught() {
  log "T5-NCb: injected pgrep -f must still be caught by the class scanner"
  local scratch out rc
  scratch="${SCRIPTS_ROOT}/lib/.nc-pgrepf-leadv2-watch-lifecycle.sh"
  SCRATCH_FILES+=("$scratch")
  awk '
    { print }
    /^wl_cmdline_match\(\) \{/ { print "  pgrep -f \"$2\" >/dev/null 2>&1 && return 0  # NC-MUTATION" }
  ' "$WATCH_LIFECYCLE_SH" > "$scratch"
  if cmp -s "$WATCH_LIFECYCLE_SH" "$scratch"; then
    fail "T5-NCb: insertion anchor not found -- update this NC"
    return
  fi
  out="$(_scan_text_matched_process_table "$scratch")"
  rc=$?
  log "T5-NCb: baseline_rc=0 mutated_rc=${rc}"
  if [[ "$rc" -ne 0 ]] && printf '%s' "$out" | grep -q "${scratch}:"; then
    pass "T5-NCb: class scanner still catches pgrep -f -- $(printf '%s' "$out" | head -1)"
  else
    fail "T5-NCb: scanner did not flag the injected pgrep -f (rc=$rc, out=$out)"
  fi
}

# T5-NC (c): backward compatibility — the OLD `ps | grep` control must still
# bite under the class scanner.
test_5ncc_pipe_grep_caught() {
  log "T5-NCc: injected ps | grep must still be caught by the class scanner"
  local scratch out rc
  scratch="${SCRIPTS_ROOT}/lib/.nc-pipegrep-leadv2-watch-lifecycle.sh"
  SCRATCH_FILES+=("$scratch")
  awk '
    { print }
    /^wl_cmdline_match\(\) \{/ { print "  ps -Ao command= | grep -q \"$2\"  # NC-MUTATION" }
  ' "$WATCH_LIFECYCLE_SH" > "$scratch"
  if cmp -s "$WATCH_LIFECYCLE_SH" "$scratch"; then
    fail "T5-NCc: insertion anchor not found -- update this NC"
    return
  fi
  out="$(_scan_text_matched_process_table "$scratch")"
  rc=$?
  log "T5-NCc: baseline_rc=0 mutated_rc=${rc}"
  if [[ "$rc" -ne 0 ]] && printf '%s' "$out" | grep -q "${scratch}:"; then
    pass "T5-NCc: class scanner still catches ps | grep -- $(printf '%s' "$out" | head -1)"
  else
    fail "T5-NCc: scanner did not flag the injected ps | grep (rc=$rc, out=$out)"
  fi
}

# T5-FP guard: the sanctioned per-pid forms must NOT be flagged — wl_cmdline_match
# (ps -p <pid> -o command= + glob) is exactly the pattern the class check must
# leave green. Inserted nothing; scan the pristine file for this function only
# by checking the whole file stays green (it does at baseline).
test_5fp_per_pid_lookup_stays_green() {
  log "T5-FP: per-pid ps -p/-o lookups in watch-lifecycle.sh must stay green"
  local out rc
  out="$(_scan_text_matched_process_table "$WATCH_LIFECYCLE_SH")"
  rc=$?
  if [[ "$rc" -eq 0 ]]; then
    pass "T5-FP: no false positive on wl_cmdline_match / wl_pidfile_live (per-pid ps -p ... -o command= + == *needle*)"
  else
    fail "T5-FP: scanner flagged a sanctioned per-pid form in watch-lifecycle.sh:\n${out}"
  fi
}

# ── syntax guard on everything this suite touches ────────────────────────────

test_0_syntax() {
  log "T0: bash -n on the two canonical liveness libs + heartbeat reader"
  if bash -n "$LANE_STATE_SH" 2>/dev/null && bash -n "$WATCH_LIFECYCLE_SH" 2>/dev/null && bash -n "$HEARTBEAT_SH" 2>/dev/null; then
    pass "T0: bash -n OK"
  else
    fail "T0: bash -n FAILED"
  fi
}

test_0_syntax
test_1_mismatched_start_time_is_dead
test_1nc_mutation_caught
test_2_absent_record_distinct_rc
test_2nc_mutation_caught
test_3_no_process_name_pattern
test_3nc_mutation_caught
test_4_no_pipeline_rc_after_filter
test_4nc_mutation_caught
test_5_no_text_matched_process_table
test_5nc_substring_caught
test_5ncb_pgrep_f_caught
test_5ncc_pipe_grep_caught
test_5fp_per_pid_lookup_stays_green

echo ""
echo "=== test-liveness-tristate-01.sh: ${PASS} passed, ${FAIL} failed ==="
if [[ "$FAIL" -gt 0 ]]; then
  printf '%s\n' "${ERRORS[@]}"
  exit 1
fi
exit 0
