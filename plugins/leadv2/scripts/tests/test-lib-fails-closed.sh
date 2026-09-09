#!/usr/bin/env bash
# tests/test-lib-fails-closed.sh — WAVE0-LIB-SWALLOWS-ITS-OWN-FAILURE-01 (T-10)
#
# One positive + one negative case per row of the nine state-layer writers
# that used to swallow their own write failure. The invariant under test: a
# state-layer function's rc says whether its artifact exists on disk, and a
# refused write prints a counted line ([<component>] wrote=0|renamed=0|
# matched=0|write_failed=1 ... reason=<word>) instead of silence.
#
# Second pass = the mission's negative control: for each of the nine rows,
# re-insert the swallow into a THROWAWAY COPY of that row's file and prove
# that exactly that row's case goes red (mutations=9 detected=9). The real
# tree is never mutated.
#
# run-all-triggers: self-select -- this file lives at
# plugins/leadv2/scripts/tests/test-*.sh, which tests/run-all.sh's own
# "a changed test suite selects itself" rule (tests/run-all.sh:452-460) and
# leadv2-dod-gate.sh::_dod_check_c's self-selecting-conventional-dirs list
# both already recognize. No EXTRA_SUITE_MAP row, no run-all.sh edit.
#
# Bash 3.2 safe: no mapfile, no ${var^^}, no associative arrays. Root-uid
# runs skip the chmod-based negatives with an explicit PASS line (a root
# process ignores directory write bits -- GNU-mktemp/root-mask memory).
set -uo pipefail

# Re-exec under bash when invoked from zsh (same guard, same reason, as
# test-state-layer-silent-write.sh).
if [ -z "${BASH_VERSION:-}" ]; then
  if command -v bash >/dev/null 2>&1; then
    exec bash "$0" "$@"
  fi
  printf 'FAIL: this suite needs bash; none found.\n' >&2
  exit 2
fi

_tlc_src="${BASH_SOURCE[0]:-}"
if [[ -z "${_tlc_src}" && -f "${0:-}" ]]; then _tlc_src="$0"; fi
HERE="$(cd "$(dirname "$_tlc_src")" && pwd)"
SCRIPTS_DIR="$(cd "${HERE}/.." && pwd)"

PASS=0
FAIL=0
FAILED_NAMES=()
ok()  { printf 'PASS: %s\n' "$1"; PASS=$((PASS + 1)); }
bad() { printf 'FAIL: %s -- %s\n' "$1" "$2"; FAIL=$((FAIL + 1)); FAILED_NAMES+=("$1"); }

IS_ROOT=0
[[ "$(id -u)" == "0" ]] && IS_ROOT=1

WORK="$(mktemp -d "${TMPDIR:-/tmp}/lib-fails-closed.XXXXXX")"
_RO_DIRS=()
cleanup() {
  for d in "${_RO_DIRS[@]:-}"; do [[ -n "$d" ]] && chmod 0755 "$d" 2>/dev/null; done
  rm -rf "${WORK}" 2>/dev/null
  return 0
}
trap cleanup EXIT INT TERM

# Never let an ambient harness pin leak a write into a real checkout or the
# shared control plane (TESTS-POLLUTE-REAL-JOURNAL-01, shared-sink memory):
# every fixture below re-pins LEADV2_PROJECT_ROOT/LEADV2_STATE_ROOT itself,
# but the CLAUDE_* rungs sit ABOVE those, so they must go.
unset CLAUDE_PROJECT_ROOT CLAUDE_PROJECT_DIR PROJECT_ROOT LEADV2_PROJECT_ROOT 2>/dev/null

# <tree-root> -> a writable throwaway copy of the whole scripts dir (APFS
# clonefile via cp -c where available -- cheap; plain copy otherwise).
mk_tree() { # $1 = source scripts dir
  local t
  t="$(mktemp -d "${WORK}/tree.XXXXXX")"
  cp -cR "$1" "$t/scripts" 2>/dev/null || cp -R "$1" "$t/scripts"
  printf '%s' "$t/scripts"
}

# python patcher for the mutation pass: exactly-once old->new replacement,
# refuses (exit 22) on zero or multiple matches -- a mutation that did not
# land is a broken control, not a pass.
mutate() { # $1=file $2=old $3=new
  python3 - "$1" "$2" "$3" <<'PYMUT'
import sys
path, old, new = sys.argv[1], sys.argv[2], sys.argv[3]
s = open(path, encoding='utf-8').read()
n = s.count(old)
if n != 1:
    print('MUTATE-ERROR: %d occurrences (want 1) in %s' % (n, path), file=sys.stderr)
    sys.exit(22)
open(path, 'w', encoding='utf-8').write(s.replace(old, new))
PYMUT
}

# ╂ Row 1 — lib/leadv2-receipt-freshness.sh: rc 2 + renamed=0 when the stale
# receipt cannot be renamed; rc 0 + renamed=1 when it can.
case_1() { # $1=TREE
  local TREE="$1" FX out
  FX="$(mktemp -d "${WORK}/r1.XXXXXX")"
  printf 'tasks:\n  - id: T1\n    status: queued\n' > "${FX}/tasks.yaml"
  mkdir -p "${FX}/comp"
  printf '{"x":1}\n' > "${FX}/comp/r1.json"
  out="$(bash -c 'source "$1/lib/leadv2-receipt-freshness.sh"; set +e
    leadv2_receipt_is_stale T1 "$2/r1.json" "$3/tasks.yaml" ""; echo "rc=$?"' _ "$TREE" "$FX/comp" "$FX" 2>&1)"
  if [[ "${out}" == *'rc=0'* && "${out}" == *'renamed=1'* ]] && ls "${FX}"/comp/r1.json.stale-* >/dev/null 2>&1; then
    ok "row1 receipt: stale receipt renamed -> rc=0 renamed=1 dest on disk"
  else
    bad "row1 receipt: rename case" "out=${out}"
  fi
  if [[ "${IS_ROOT}" == "1" ]]; then ok "row1 receipt: RO-dir negative skipped root"; return 0; fi
  mkdir -p "${FX}/ro"; printf '{"x":1}\n' > "${FX}/ro/r2.json"; chmod 0555 "${FX}/ro"; _RO_DIRS+=("${FX}/ro")
  out="$(bash -c 'source "$1/lib/leadv2-receipt-freshness.sh"; set +e
    leadv2_receipt_is_stale T1 "$2/r2.json" "$3/tasks.yaml" ""; echo "rc=$?"' _ "$TREE" "$FX/ro" "$FX" 2>&1)"
  if [[ "${out}" == *'rc=2'* && "${out}" == *'renamed=0 reason=rename_failed'* ]]; then
    ok "row1 receipt: rename refused -> rc=2 renamed=0 reason=rename_failed"
  else
    bad "row1 receipt: RO rename case" "out=${out}"
  fi
}

# ╂ Row 2 — lib/leadv2-freepool-gate.sh record: rc 2 + wrote=0 on bad latency
# and on an unwritable state file; rc 0 + wrote=1 results=N otherwise.
case_2() { # $1=TREE
  local TREE="$1" FX out
  FX="$(mktemp -d "${WORK}/r2.XXXXXX")"; mkdir -p "${FX}/st"
  out="$(LEADV2_FREEPOOL_STATE_DIR="${FX}/st" bash "${TREE}/lib/leadv2-freepool-gate.sh" record 1 abc 2>&1; echo "rc=$?")"
  if [[ "${out}" == *'rc=2'* && "${out}" == *'[freepool-record] wrote=0 reason=bad_latency value=abc'* ]]; then
    ok "row2 freepool: bad latency -> rc=2 wrote=0 reason=bad_latency"
  else
    bad "row2 freepool: bad latency case" "out=${out}"
  fi
  out="$(LEADV2_FREEPOOL_STATE_DIR="${FX}/st" bash "${TREE}/lib/leadv2-freepool-gate.sh" record 1 0.5 2>&1; echo "rc=$?")"
  if [[ "${out}" == *'rc=0'* && "${out}" == *'[freepool-record] wrote=1 results=1 path='* ]] \
     && grep -q '"latency_s": 0.5' "${FX}/st/freepool-arm-state.json" 2>/dev/null; then
    ok "row2 freepool: good record -> rc=0 wrote=1 results=1, state file updated"
  else
    bad "row2 freepool: good record case" "out=${out}"
  fi
  if [[ "${IS_ROOT}" == "1" ]]; then ok "row2 freepool: RO-state negative skipped root"; return 0; fi
  mkdir -p "${FX}/ro"; printf '{"results": []}' > "${FX}/ro/freepool-arm-state.json"
  chmod 0555 "${FX}/ro"; _RO_DIRS+=("${FX}/ro")
  out="$(LEADV2_FREEPOOL_STATE_DIR="${FX}/ro" bash "${TREE}/lib/leadv2-freepool-gate.sh" record 1 0.5 2>&1; echo "rc=$?")"
  if [[ "${out}" == *'rc=2'* && "${out}" == *'[freepool-record] wrote=0 reason=state_write_error path='* ]]; then
    ok "row2 freepool: RO state dir -> rc=2 wrote=0 reason=state_write_error"
  else
    bad "row2 freepool: RO state case" "out=${out}"
  fi
}

# ╂ Row 3 — lib/leadv2-lane-state.sh deregister: rc 2 + matched=0 (and NO
# rewrite) when no live row matches; rc 0 + matched=1 when it does.
case_3() { # $1=TREE
  local TREE="$1" FX out
  FX="$(mktemp -d "${WORK}/r3.XXXXXX")"; ( cd "${FX}" && git init -q ) >/dev/null 2>&1
  out="$(cd "${FX}" && LEADV2_PROJECT_ROOT="${FX}" LEADV2_STATE_ROOT="${FX}/state" \
    bash -c 'source "$1/lib/leadv2-lane-state.sh"; set +e
      lane_register tsk1 lead1 /tmp/wt spawning $$ >/dev/null 2>&1
      lane_deregister tsk1 closed; echo "rc=$?"' _ "$TREE" 2>&1)"
  if [[ "${out}" == *'rc=0'* && "${out}" == *'[lane-state] deregister task=tsk1 matched=1'* ]]; then
    ok "row3 lane-state: live row deregistered -> rc=0 matched=1"
  else
    bad "row3 lane-state: matched case" "out=${out}"
  fi
  out="$(cd "${FX}" && LEADV2_PROJECT_ROOT="${FX}" LEADV2_STATE_ROOT="${FX}/state" \
    bash -c 'source "$1/lib/leadv2-lane-state.sh"; set +e
      lane_deregister nobody closed; echo "rc=$?"' _ "$TREE" 2>&1)"
  if [[ "${out}" == *'rc=2'* && "${out}" == *'[lane-state] deregister task=nobody matched=0 reason=no_live_row'* ]]; then
    ok "row3 lane-state: unknown task -> rc=2 matched=0 reason=no_live_row"
  else
    bad "row3 lane-state: no-live-row case" "out=${out}"
  fi
}

# ╂ Row 4 — leadv2-journal.sh append: rc 2 + write_failed=1 when mkdir or the
# append refuses; rc 0 and the line on disk otherwise. Read verbs keep rc 0.
case_4() { # $1=TREE
  local TREE="$1" FX out jpath
  FX="$(mktemp -d "${WORK}/r4.XXXXXX")"; ( cd "${FX}" && git init -q ) >/dev/null 2>&1
  out="$(cd "${FX}" && LEADV2_PROJECT_ROOT="${FX}" LEADV2_STATE_ROOT="${FX}/state" \
    bash "${TREE}/leadv2-journal.sh" append T4 note "hello fails-closed" 2>&1; echo "rc=$?")"
  jpath="$(cd "${FX}" && LEADV2_PROJECT_ROOT="${FX}" LEADV2_STATE_ROOT="${FX}/state" \
    bash "${TREE}/leadv2-journal.sh" path T4 2>/dev/null)"
  if [[ "${out}" == *'rc=0'* && "${out}" != *'write_failed'* ]] && [[ -f "${jpath}" ]] \
     && grep -q 'hello fails-closed' "${jpath}" 2>/dev/null; then
    ok "row4 journal: append lands -> rc=0, line on disk at ${jpath#${FX}/}"
  else
    bad "row4 journal: append case" "out=${out} jpath=${jpath}"
  fi
  out="$(cd "${FX}" && LEADV2_PROJECT_ROOT="${FX}" LEADV2_STATE_ROOT="${FX}/state" \
    bash "${TREE}/leadv2-journal.sh" tail T4 2>&1; echo "rc=$?")"
  if [[ "${out}" == *'rc=0'* ]]; then
    ok "row4 journal: read verb tail -> rc=0 (unchanged contract)"
  else
    bad "row4 journal: tail case" "out=${out}"
  fi
  if [[ "${IS_ROOT}" == "1" ]]; then ok "row4 journal: RO negatives skipped root"; return 0; fi
  # Negative 1 -- BOTH layouts must refuse: a read-only parent kills the
  # canonical state root, but journal.sh then falls back to the per-checkout
  # layout under ${PROJECT_ROOT}/docs/leadv2 (measured: the line landed there
  # with rc=0 when only the canonical root was blocked). Read-only on BOTH
  # leaves the append no writable home -> the mkdir guard fires.
  mkdir -p "${FX}/ro" "${FX}/docs/leadv2"; chmod 0555 "${FX}/ro" "${FX}/docs/leadv2"
  _RO_DIRS+=("${FX}/ro" "${FX}/docs/leadv2")
  out="$(cd "${FX}" && LEADV2_PROJECT_ROOT="${FX}" LEADV2_STATE_ROOT="${FX}/ro/state" \
    bash "${TREE}/leadv2-journal.sh" append T5 note "never lands" 2>&1; echo "rc=$?")"
  if [[ "${out}" == *'rc=2'* && "${out}" == *'write_failed=1'* && "${out}" == *'reason=mkdir'* ]] \
     && [[ ! -e "${FX}/docs/leadv2/tasks/T5/journal.md" ]]; then
    ok "row4 journal: no writable layout -> rc=2 write_failed=1 reason=mkdir, no fallback artifact"
  else
    bad "row4 journal: mkdir-refused case" "out=${out}"
  fi
  # Negative 2 -- the layout exists but the journal FILE is not writable: the
  # append itself must refuse loudly (reason=append), never vanish.
  chmod 0444 "${jpath}"
  out="$(cd "${FX}" && LEADV2_PROJECT_ROOT="${FX}" LEADV2_STATE_ROOT="${FX}/state" \
    bash "${TREE}/leadv2-journal.sh" append T4 note "still never lands" 2>&1; echo "rc=$?")"
  chmod 0644 "${jpath}" 2>/dev/null
  if [[ "${out}" == *'rc=2'* && "${out}" == *'write_failed=1'* && "${out}" == *'reason=append'* ]] \
     && ! grep -q 'still never lands' "${jpath}" 2>/dev/null; then
    ok "row4 journal: append refused on RO file -> rc=2 write_failed=1 reason=append, line not on disk"
  else
    bad "row4 journal: append-refused case" "out=${out}"
  fi
}

# ╂ Row 5 — lib/leadv2-brain-record.sh: rc 2 + wrote=0 reason=empty_task_id on
# an empty task id; rc 0 + wrote=1 + file on disk otherwise.
case_5() { # $1=TREE
  local TREE="$1" FX out
  FX="$(mktemp -d "${WORK}/r5.XXXXXX")"
  out="$(bash -c 'source "$1/lib/leadv2-brain-record.sh" >/dev/null 2>&1; set +e
    leadv2_brain_write_yaml "$2" "" Standard computed "{}" classify r; echo "rc=$?"' _ "$TREE" "$FX" 2>&1)"
  if [[ "${out}" == *'rc=2'* && "${out}" == *'[brain] wrote=0 reason=empty_task_id'* ]]; then
    ok "row5 brain: empty task_id -> rc=2 wrote=0 reason=empty_task_id"
  else
    bad "row5 brain: empty task case" "out=${out}"
  fi
  out="$(bash -c 'source "$1/lib/leadv2-brain-record.sh" >/dev/null 2>&1; set +e
    leadv2_brain_write_yaml "$2" brain1 Standard computed "{}" classify r; echo "rc=$?"' _ "$TREE" "$FX" 2>&1)"
  if [[ "${out}" == *'rc=0'* && "${out}" == *'[brain] wrote=1 path='* ]] \
     && grep -q 'class: Standard' "${FX}/docs/handoff/brain1/brain.yaml" 2>/dev/null; then
    ok "row5 brain: good write -> rc=0 wrote=1, brain.yaml on disk"
  else
    bad "row5 brain: good write case" "out=${out}"
  fi
}

# ╂ Row 6 — leadv2-lanes-snapshot.sh truth-breaches cache: prints
# wrote=1 / wrote=0 reason=<step> on stderr while the script's rc and stdout
# are UNCHANGED either way (the block is documented non-fatal by design).
case_6() { # $1=TREE
  local TREE="$1" FX rc1 rc2 out1 out2
  FX="$(mktemp -d "${WORK}/r6.XXXXXX")"; ( cd "${FX}" && git init -q ) >/dev/null 2>&1
  ( cd "${FX}" && LEADV2_PROJECT_ROOT="${FX}" LEADV2_STATE_ROOT="${FX}/state" \
    LEADV2_LANES_ALL_REPOS=0 timeout 90 bash "${TREE}/leadv2-lanes-snapshot.sh" --json ) \
    >/dev/null 2>"${FX}/err1"; rc1=$?
  out1="$(cat "${FX}/err1")"
  if [[ "${out1}" == *'[lanes-snapshot] truth_breaches_cache wrote=1 path='* ]]; then
    ok "row6 snapshot: writable state -> truth_breaches_cache wrote=1"
  else
    bad "row6 snapshot: writable case" "err=${out1}"
  fi
  if [[ "${IS_ROOT}" == "1" ]]; then ok "row6 snapshot: RO negative skipped root"; return 0; fi
  chmod 0555 "${FX}/state"; _RO_DIRS+=("${FX}/state")
  ( cd "${FX}" && LEADV2_PROJECT_ROOT="${FX}" LEADV2_STATE_ROOT="${FX}/state" \
    LEADV2_LANES_ALL_REPOS=0 timeout 90 bash "${TREE}/leadv2-lanes-snapshot.sh" --json ) \
    >/dev/null 2>"${FX}/err2"; rc2=$?
  out2="$(cat "${FX}/err2")"
  if [[ "${out2}" == *'truth_breaches_cache wrote=0 reason='* && "${rc2}" == "${rc1}" ]]; then
    ok "row6 snapshot: RO state -> wrote=0 reason=<step> and script rc unchanged (${rc1})"
  else
    bad "row6 snapshot: RO case" "err=${out2} rc_writable=${rc1} rc_ro=${rc2}"
  fi
}

# ╂ Row 7 — leadv2-phase-record.sh _emit: a phase record lands a
# `[phase] phase_recorded ...` line in the task's journal (first time ever --
# the old call shape never reached the journal); a failing journal is loud
# (journal_write_failed + journal_events_missed) without changing record's rc.
case_7() { # $1=TREE
  local TREE="$1" FX out jpath
  FX="$(mktemp -d "${WORK}/r7.XXXXXX")"; ( cd "${FX}" && git init -q ) >/dev/null 2>&1
  mkdir -p "${FX}/docs/handoff/dispatch-ab12cd34"
  ( cd "${FX}" && LEADV2_PROJECT_ROOT="${FX}" LEADV2_STATE_ROOT="${FX}/state" \
    LEADV2_DISPATCH_CACHE_DIR="${FX}/cache" \
    bash "${TREE}/leadv2-phase-record.sh" record ab12cd34 classify --status done >/dev/null 2>&1 ); local rcpos=$?
  jpath="$(cd "${FX}" && LEADV2_PROJECT_ROOT="${FX}" LEADV2_STATE_ROOT="${FX}/state" \
    bash "${TREE}/leadv2-journal.sh" path ab12cd34 2>/dev/null)"
  if [[ "${rcpos}" == "0" && -n "${jpath}" ]] && grep -q '\[phase\] phase_recorded phase=classify task=ab12cd34 status=done' "${jpath}" 2>/dev/null; then
    ok "row7 phase-record: journal line '- [phase] phase_recorded ...' landed (rc=0)"
  else
    bad "row7 phase-record: journal line case" "rc=${rcpos} jpath=${jpath} content=$(cat "${jpath}" 2>/dev/null)"
  fi
  printf '#!/usr/bin/env bash\nexit 1\n' > "${WORK}/badjournal.sh"; chmod +x "${WORK}/badjournal.sh"
  out="$(cd "${FX}" && LEADV2_PROJECT_ROOT="${FX}" LEADV2_STATE_ROOT="${FX}/state" \
    LEADV2_JOURNAL_BIN="${WORK}/badjournal.sh" LEADV2_DISPATCH_CACHE_DIR="${FX}/cache" \
    bash "${TREE}/leadv2-phase-record.sh" record ab12cd34 build --status running --handle h1 2>&1; echo "rc=$?")"
  if [[ "${out}" == *'rc=0'* && "${out}" == *'[phase-record] journal_write_failed=1 event=phase_recorded task=ab12cd34'* \
     && "${out}" == *'[phase-record] journal_events_missed=1'* ]]; then
    ok "row7 phase-record: failing journal -> loud lines, record rc still 0"
  else
    bad "row7 phase-record: failing-journal case" "out=${out}"
  fi
}

# ╂ Row 8 — lib/leadv2-dod-gate.sh: rc 0 + dod_report wrote=1 when out_md
# persists; checks pass but rc 4 + wrote=0 reason=<step> when it cannot
# (rc 2 is taken by "undetermined" -- the collision is why 4).
case_8() { # $1=TREE
  local TREE="$1" FX REPO TD DF out
  FX="$(mktemp -d "${WORK}/r8.XXXXXX")"
  REPO="${FX}/repo"; mkdir -p "${REPO}"
  ( cd "${REPO}" && git init -q -b main && git -c user.email=t@t -c user.name=t commit -q --allow-empty -m base && git checkout -q -b lane ) >/dev/null 2>&1
  TD="${REPO}/docs/handoff/T1"; mkdir -p "${TD}"
  printf 'Nothing further needed from the worker for this fixture.\n' > "${TD}/brief.md"
  ( cd "${REPO}" && git add -A && git -c user.email=t@t -c user.name=t commit -q -m step ) >/dev/null 2>&1
  printf -- '--- a/plugins/x.sh\n+++ b/plugins/x.sh\n@@ -x +y\n' > "${FX}/diff.txt"
  mkdir -p "${FX}/out"
  out="$(cd "${REPO}" && bash "${TREE}/lib/leadv2-dod-gate.sh" "${REPO}" "${TD}" "${FX}/diff.txt" "${FX}/out/dod-gate.md" 2>/dev/null; echo "rc=$?")"
  if [[ "${out}" == *'rc=0'* && "${out}" == *'dod_report wrote=1 path='* ]] && [[ -f "${FX}/out/dod-gate.md" ]]; then
    ok "row8 dod-gate: pass + persisted -> rc=0 dod_report wrote=1"
  else
    bad "row8 dod-gate: pass case" "out=${out}"
  fi
  if [[ "${IS_ROOT}" == "1" ]]; then ok "row8 dod-gate: RO negative skipped root"; return 0; fi
  mkdir -p "${FX}/ro"; chmod 0555 "${FX}/ro"; _RO_DIRS+=("${FX}/ro")
  out="$(cd "${REPO}" && bash "${TREE}/lib/leadv2-dod-gate.sh" "${REPO}" "${TD}" "${FX}/diff.txt" "${FX}/ro/dod-gate.md" 2>/dev/null; echo "rc=$?")"
  if [[ "${out}" == *'rc=4'* && "${out}" == *'dod_report wrote=0 path='* && "${out}" == *'reason='* ]] \
     && [[ ! -e "${FX}/ro/dod-gate.md" ]]; then
    ok "row8 dod-gate: checks pass, out_md refused -> rc=4 dod_report wrote=0 reason=<step>"
  else
    bad "row8 dod-gate: unwritable out case" "out=${out}"
  fi
}

# ╂ Row 9 — lib/leadv2-worker-epilogue.sh: rc 0 + wrote=N write_failed=0 when
# the appends land; rc 2 + reason=run_dir_missing / write_failed=M when not.
case_9() { # $1=TREE
  local TREE="$1" FX REPO RD out
  FX="$(mktemp -d "${WORK}/r9.XXXXXX")"
  REPO="${FX}/repo"; RD="${FX}/run"; mkdir -p "${REPO}" "${RD}"
  ( cd "${REPO}" && git init -q && git -c user.email=t@t -c user.name=t commit -q --allow-empty -m base ) >/dev/null 2>&1
  out="$(bash -c 'source "$1/lib/leadv2-worker-epilogue.sh"; set +e
    leadv2_worker_commit_epilogue "$2" "$3" 2>&1; echo "rc=$?"' _ "$TREE" "$RD" "$REPO" 2>&1)"
  if [[ "${out}" == *'[epilogue] wrote='* && "${out}" == *'write_failed=0'* && "${out}" == *'rc=0'* ]] \
     && grep -q 'worker_exit=clean' "${RD}/progress.log" 2>/dev/null; then
    ok "row9 epilogue: clean tree -> rc=0 wrote=N write_failed=0, progress.log written"
  else
    bad "row9 epilogue: clean case" "out=${out} log=$(cat "${RD}/progress.log" 2>/dev/null)"
  fi
  out="$(bash -c 'source "$1/lib/leadv2-worker-epilogue.sh"; set +e
    leadv2_worker_commit_epilogue "$2/nope" "$3" 2>&1; echo "rc=$?"' _ "$TREE" "$FX" "$REPO" 2>&1)"
  if [[ "${out}" == *'rc=2'* && "${out}" == *'[epilogue] wrote=0 write_failed=0 reason=run_dir_missing'* ]]; then
    ok "row9 epilogue: missing run_dir -> rc=2 reason=run_dir_missing"
  else
    bad "row9 epilogue: run_dir-missing case" "out=${out}"
  fi
  if [[ "${IS_ROOT}" == "1" ]]; then ok "row9 epilogue: RO negative skipped root"; return 0; fi
  local RD2="${FX}/runro"; mkdir -p "${RD2}"; chmod 0555 "${RD2}"; _RO_DIRS+=("${RD2}")
  out="$(bash -c 'source "$1/lib/leadv2-worker-epilogue.sh"; set +e
    leadv2_worker_commit_epilogue "$2" "$3" 2>&1; echo "rc=$?"' _ "$TREE" "$RD2" "$REPO" 2>&1)"
  if [[ "${out}" == *'rc=2'* && "${out}" == *'write_failed='* && "${out}" != *'write_failed=0'* ]]; then
    ok "row9 epilogue: unwritable run_dir -> rc=2 write_failed=M"
  else
    bad "row9 epilogue: RO case" "out=${out}"
  fi
}

# ────────────────────────────────────────────────────────────────────────────
# Green pass: every row's positive + negative cases against the REAL tree.
# ────────────────────────────────────────────────────────────────────────────
CASE_FNS=(case_1 case_2 case_3 case_4 case_5 case_6 case_7 case_8 case_9)
ROW_NAMES=(receipt freepool lane-state journal brain snapshot phase-record dod-gate epilogue)

green_pass() {
  local i
  printf -- '--- green pass (real tree, one positive + one negative per row)\n'
  for i in 0 1 2 3 4 5 6 7 8; do
    "${CASE_FNS[$i]}" "${SCRIPTS_DIR}"
  done
}

# ────────────────────────────────────────────────────────────────────────────
# Mutation pass (the mission's negative control): copy the tree, re-insert
# ONE row's swallow via an exactly-once patch, and prove that exactly that
# row's case goes red on the mutated copy.
# ────────────────────────────────────────────────────────────────────────────

# mutate_row <N> <tree-scripts-root> — applies row N's swallow; rc 0 ok.
mutate_row() {
  local n="$1" s="$2" f=""
  case "$n" in
    1) f="lib/leadv2-receipt-freshness.sh"
       mutate "${s}/${f}" \
'  _leadv2_receipt_log "$log_file" "renamed=0 reason=rename_failed dest=${dest}"
  return 2' \
'  _leadv2_receipt_log "$log_file" "renamed=0 reason=rename_failed dest=${dest}"
  return 0' ;;
    2) f="lib/leadv2-freepool-gate.sh"
       mutate "${s}/${f}" \
'  if [[ "${_fr_rc}" -ne 0 ]]; then
    printf '"'"'[freepool-record] wrote=0 reason=state_write_error path=%s\n'"'"' "${FREEPOOL_STATE_FILE}" >&2
    return 2
  fi' \
'  if [[ "${_fr_rc}" -ne 0 ]]; then
    printf '"'"'[freepool-record] wrote=0 reason=state_write_error path=%s\n'"'"' "${FREEPOOL_STATE_FILE}" >&2
    return 0
  fi' ;;
    3) f="lib/leadv2-lane-state.sh"
       mutate "${s}/${f}" \
"      print('[lane-state] deregister task=%s matched=0 reason=no_live_row' % task, file=sys.stderr)
      sys.exit(2)" \
"      print('[lane-state] deregister task=%s matched=0 reason=no_live_row' % task, file=sys.stderr)
      sys.exit(0)" ;;
    # Row 4's original swallow was `trap 'exit 0' ERR`, but that trap
    # can no longer fire on the refusal path (both guards are ||-wrapped, and
    # bash never runs the ERR trap for commands in a || context) -- keeping it
    # as the mutation would be a vacuous control. Re-insert the OTHER half of
    # the row's original vocabulary instead: the bare `|| true` on the append
    # write, which negative 2 (RO journal file) must catch.
    4) f="leadv2-journal.sh"
       mutate "${s}/${f}" \
'    printf -- '"'"'- %s [%s] %s\n'"'"' "$UTC_ISO" "$TYPE" "$TEXT" >> "$JOURNAL_FILE" 2>/dev/null \
      || { log_err "write_failed=1 path=$JOURNAL_FILE reason=append"; exit 2; }' \
'    printf -- '"'"'- %s [%s] %s\n'"'"' "$UTC_ISO" "$TYPE" "$TEXT" >> "$JOURNAL_FILE" 2>/dev/null || true' ;;
    5) f="lib/leadv2-brain-record.sh"
       mutate "${s}/${f}" \
"    printf '[brain] wrote=0 reason=empty_task_id\n' >&2
    return 2" \
"    printf '[brain] wrote=0 reason=empty_task_id\n' >&2
    return 0" ;;
    6) f="leadv2-lanes-snapshot.sh"
       mutate "${s}/${f}" \
"|| { printf '[lanes-snapshot] truth_breaches_cache wrote=0 reason=write path=%s\n' \"\$TRUTH_BREACHES_FILE\" >&2; _tb_skip=1; }" \
"|| { _tb_skip=1; }" ;;
    7) f="leadv2-phase-record.sh"
       mutate "${s}/${f}" \
'  if ! LEADV2_PROJECT_ROOT="${PROJECT_ROOT}" bash "${JOURNAL_BIN}" append "${_e_task}" "${_e_type}" "${_e_event} ${_e_text}" >/dev/null 2>&1; then
    printf '\''[phase-record] journal_write_failed=1 event=%s task=%s\n'\'' "${_e_event}" "${_e_task}" >&2
    return 2
  fi' \
'  LEADV2_PROJECT_ROOT="${PROJECT_ROOT}" bash "${JOURNAL_BIN}" append "${_e_task}" "${_e_type}" "${_e_event} ${_e_text}" >/dev/null 2>&1 || true' ;;
    8) f="lib/leadv2-dod-gate.sh"
       mutate "${s}/${f}" \
'  [[ ${report_written} -eq 1 ]] || return 4
  return 0' \
'  [[ ${report_written} -eq 1 ]] || return 0
  return 0' ;;
    9) f="lib/leadv2-worker-epilogue.sh"
       mutate "${s}/${f}" \
'  printf '\''[epilogue] wrote=%s write_failed=%s path=%s\n'\'' "${_ep_wrote}" "${_ep_failed}" "${run_dir}" >&2
  if [[ "${_ep_failed}" -eq 0 ]]; then
    return 0
  fi
  return 2' \
'  printf '\''[epilogue] wrote=%s write_failed=%s path=%s\n'\'' "${_ep_wrote}" "${_ep_failed}" "${run_dir}" >&2
  if [[ "${_ep_failed}" -eq 0 ]]; then
    return 0
  fi
  return 0' ;;
    *) printf 'unknown row %s\n' "$n" >&2; return 9 ;;
  esac
}

# run_mutation <N>: rc 0 = detected (the mutated row's case FAILED its
# assertions, i.e. the swallow defeated detection and the suite noticed).
# The case runs WITHOUT a subshell so its ok/bad calls move THIS shell's
# counters -- the FAIL delta is the detection signal -- and the counters are
# restored afterwards so the mutation pass never pollutes the green summary.
run_mutation() {
  local n="$1" tree pass_before fail_before names_len idx=$((n - 1))
  tree="$(mk_tree "${SCRIPTS_DIR}")"
  if ! mutate_row "$n" "$tree"; then
    bad "mutation ${n} ${ROW_NAMES[$idx]}: patch applied exactly once" "mutate rc=$?"
    rm -rf "$(dirname "$tree")" 2>/dev/null
    return 1
  fi
  pass_before="${PASS}"; fail_before="${FAIL}"; names_len="${#FAILED_NAMES[@]}"
  "${CASE_FNS[$idx]}" "$tree" >/dev/null 2>&1
  local detected=0
  [[ "${FAIL}" -gt "${fail_before}" ]] && detected=1
  # Restore the summary counters: a mutation-run red is the SIGNAL, not a
  # suite failure; only a NOT-DETECTED mutation is one. (The case's stdout/
  # stderr is already discarded above; only the counters leak.)
  PASS="${pass_before}"
  FAIL="${fail_before}"
  if [[ "${names_len}" -gt 0 ]]; then
    FAILED_NAMES=("${FAILED_NAMES[@]:0:${names_len}}")
  else
    FAILED_NAMES=()
  fi
  rm -rf "$(dirname "$tree")" 2>/dev/null
  if [[ "${detected}" == "1" ]]; then
    printf 'mutation %s %-12s DETECTED (row case went red on the mutated copy)\n' "$n" "${ROW_NAMES[$idx]}"
    return 0
  fi
  printf 'mutation %s %-12s NOT DETECTED -- the re-inserted swallow passed its own case\n' "$n" "${ROW_NAMES[$idx]}"
  return 1
}

mutation_pass() {
  local n detected=0 total=0
  printf -- '--- mutation pass (swallow re-inserted per row, in a throwaway copy)\n'
  for n in 1 2 3 4 5 6 7 8 9; do
    total=$((total + 1))
    if run_mutation "$n"; then detected=$((detected + 1)); fi
  done
  printf 'mutations=%s detected=%s\n' "${total}" "${detected}"
  if [[ "${detected}" -ne "${total}" ]]; then
    bad "mutation pass: every re-inserted swallow caught" "detected=${detected}/${total}"
    return 1
  fi
  ok "mutation pass: every re-inserted swallow caught by exactly its own row's case"
  return 0
}

usage() {
  printf 'Usage: %s [--mutate <1-9>]\n' "$0"
  printf '  (no args)      green pass over the real tree + all nine mutations\n'
  printf '  --mutate <N>   single mutation N only (debugging the control)\n'
}

ONLY_MUTATE=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --mutate) ONLY_MUTATE="${2:-}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) usage >&2; exit 2 ;;
  esac
done

if [[ -n "${ONLY_MUTATE}" ]]; then
  if ! [[ "${ONLY_MUTATE}" =~ ^[1-9]$ ]]; then usage >&2; exit 2; fi
  if run_mutation "${ONLY_MUTATE}"; then
    printf -- '%d passed, %d failed\n' "${PASS}" "${FAIL}"
    exit 0
  fi
  printf -- '%d passed, %d failed\n' "${PASS}" "${FAIL}"
  exit 1
fi

green_pass
mutation_pass

printf -- '---\n%d passed, %d failed\n' "${PASS}" "${FAIL}"
if [[ ${FAIL} -gt 0 ]]; then
  printf 'Failed assertions:\n'
  for n in "${FAILED_NAMES[@]}"; do printf '  - %s\n' "$n"; done
  exit 1
fi
exit 0
