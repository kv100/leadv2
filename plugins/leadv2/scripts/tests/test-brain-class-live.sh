#!/usr/bin/env bash
# test-brain-class-live.sh — BRAIN-CLASS-LIVE-01 coverage: the judge-derived
# class is a FLOOR over a declared --task-class, every decision is journaled
# in the class_escalated/class_floor_held/declared_fallback vocabulary, and
# docs/handoff/<task>/brain.yaml + the brain_decision line are what the
# phase-precondition guard later enforces (both at intake and on a
# same-task re-entry via cmd_advance_arm's _resolve_class_with_brain_floor).
#
# Negative control (mutation-proven): _admission_classify's judge call is
# replaced with an unconditional `return 0` (skip) right before the
# `bash "${TASK_JUDGE_BIN}" ...` line, on a temp copy of dispatch-code.sh.
# That mutation must turn (a) and (d) red -- with the judge never called,
# there is no estimate to escalate from and no fresh brain.yaml to read.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DISPATCH_SH="${SCRIPT_DIR}/../leadv2-dispatch-code.sh"

PASS=0; FAIL=0
pass(){ printf 'PASS: %s\n' "$1"; PASS=$((PASS+1)); }
fail(){ printf 'FAIL: %s\n' "$1" >&2; FAIL=$((FAIL+1)); }

# stub judge: prints a fixed TaskEstimate JSON, always rc 0
mkstub_judge() { # <dir> <complexity> <subsystems> <risk> [work_kind]
  local dir="$1" cx="$2" subs="$3" risk="$4" wk="${5:-build}"
  local f="${dir}/judge-stub.sh"
  cat > "$f" <<EOF
#!/usr/bin/env bash
printf '{"complexity":"${cx}","subsystems_touched":${subs},"risk_class":"${risk}","work_kind":"${wk}","duration_class":"long","estimate_source":"judge"}'
exit 0
EOF
  chmod +x "$f"
  printf '%s' "$f"
}

mkstub_judge_fail() { # <dir> -> stub bin that fails outright
  local dir="$1"
  local f="${dir}/judge-fail.sh"
  cat > "$f" <<'EOF'
#!/usr/bin/env bash
exit 7
EOF
  chmod +x "$f"
  printf '%s' "$f"
}

# run_classify <dispatch_sh> <project_root> <judge_bin> <task_id> <sig8> <explicit> <flagged> <mission>
# -> stdout: journal lines (stderr of the sourced call, which is where emit()
# lands when JOURNAL_TASK's journal write is unavailable/irrelevant to this
# unit slice) followed by a line "CLASS=<c> SOURCE=<s>"
run_classify() {
  local dsh="$1" root="$2" judge="$3" task_id="$4" sig8="$5" explicit="$6" flagged="$7" mission="$8"
  # Hermetic root: FOREIGN-PROJECT-ROOT-GUARD-01 resolves the env root as
  # CLAUDE_PROJECT_ROOT > CLAUDE_PROJECT_DIR > PROJECT_ROOT > LEADV2_PROJECT_ROOT,
  # so a caller-session leak of the three higher-precedence spellings (the
  # live-proof harness exports all of them to its fixture repo) outranks this
  # suite's own PROJECT_ROOT, the guard sees env!=cwd, and every brain.yaml /
  # journal artifact lands in the caller's repo instead of ${root}. Blank them
  # out (empty == unset under the resolver's ${VAR:-} chain) so ${root} wins.
  blank_project_root_env \
    LEADV2_DISPATCH_SOURCE_ONLY=1 PROJECT_ROOT="${root}" LEADV2_TASK_JUDGE_BIN="${judge}" \
    founder_task_id="${task_id}" JOURNAL_TASK="${task_id}" \
    bash -c '
      source "$1"
      _admission_classify "$2" "$3" "$4" "$5" "$6"
      echo "CLASS=${ADMISSION_CLASS} SOURCE=${ADMISSION_SOURCE}"
    ' _ "${dsh}" "${mission}" "sig-$(date +%s%N)-$$-${sig8}" "${sig8}" "${explicit}" "${flagged}" 2>&1
}

journal_file() { # <root> <task_id>
  find "$1/docs/leadv2/tasks/$2" -iname '*journal*' 2>/dev/null | head -1
}

# journal_read_wait <root> <task_id> -> stdout: journal file content, polling
# briefly if it is not there / not yet non-empty on the first look.
#
# R3 review fix (fix-round-4, item 2): cases (a) and (b) were reported flaky
# (~1 in 3 per the round-4 brief; reproduced here at ~1 in 19 full-suite runs,
# 0 in 80 tight isolated repro loops of (a)/(b) alone -- see report.md for the
# repro transcript). Root-caused to: `leadv2_brain_record`'s caller in
# leadv2-dispatch-code.sh wraps that call in `2>/dev/null` (deliberate --
# a brain-record failure must never spam or refuse a live dispatch), which
# means `out_a`/`out_b` NEVER carry the class_escalated/class_floor_held line
# on this path -- the journal FILE on disk is the ONLY place that decision is
# ever recorded. `leadv2-journal.sh append` is synchronous (the subprocess
# has exited by the time `$(...)` returns, so there is no async propagation
# delay in principle) but this repo is a live, heavily-concurrent shared dev
# machine -- the same canonical scripts this suite sources are being read by
# other leadv2 lanes' processes at the same time -- and `emit()`'s journal
# write is best-effort (`|| true`) with `leadv2-journal.sh` itself running
# under `trap 'exit 0' ERR`, so a rare scheduler/fork-exec hiccup around that
# one subprocess call silently no-ops instead of surfacing. A single,
# unretried read of that file is therefore the single point of failure this
# helper removes: it polls briefly (5 x 50ms, 250ms bounded) for non-empty
# content before giving up -- the exact assertion string still must appear,
# nothing here weakens what is checked.
journal_read_wait() {
  local root="$1" task_id="$2" tries=5 f content=""
  while (( tries > 0 )); do
    f="$(journal_file "${root}" "${task_id}")"
    if [[ -f "${f}" ]]; then
      content="$(cat "${f}")"
      [[ -n "${content}" ]] && { printf '%s' "${content}"; return 0; }
    fi
    tries=$((tries-1))
    (( tries > 0 )) && sleep 0.05
  done
  printf '%s' "${content}"
}

# blank_project_root_env <cmd...> -- run <cmd...> with CLAUDE_PROJECT_ROOT,
# CLAUDE_PROJECT_DIR and LEADV2_PROJECT_ROOT blanked (see the comment in
# run_classify for why this must precede every sourced dispatch-code.sh call,
# including the (d) re-entry path which is NOT routed through run_classify).
blank_project_root_env() {
  env CLAUDE_PROJECT_ROOT= CLAUDE_PROJECT_DIR= LEADV2_PROJECT_ROOT= "$@"
}

# ── (a) light mission touching hooks/+safety -> escalated to Standard|Heavy ──
TMP_A="$(mktemp -d)"
JUDGE_A="$(mkstub_judge "${TMP_A}" complex 4 safety_publish_payments build)"
out_a="$(run_classify "${DISPATCH_SH}" "${TMP_A}" "${JUDGE_A}" "dispatch-brainA" "brainA01" "Light" "1" \
  "touch hooks/pre-commit.sh and safety/gate.sh")"
jf_a_content="$(journal_read_wait "${TMP_A}" "dispatch-brainA")"
if printf '%s' "${out_a}" "${jf_a_content}" | grep -q 'class_escalated task=brainA01 from=Light to=\(Standard\|Heavy\)'; then
  pass "(a) light+risk mission escalates to Standard|Heavy, journaled"
else
  fail "(a) missing class_escalated line: ${out_a}"
fi
[[ -f "${TMP_A}/docs/handoff/dispatch-brainA/brain.yaml" ]] \
  && grep -q '^class_source: escalated' "${TMP_A}/docs/handoff/dispatch-brainA/brain.yaml" \
  && pass "(a) brain.yaml class_source=escalated" \
  || fail "(a) brain.yaml missing or wrong class_source"
rm -rf "${TMP_A}"

# ── (b) trivial mission declared Heavy -> class_floor_held, stays Heavy ─────
TMP_B="$(mktemp -d)"
JUDGE_B="$(mkstub_judge "${TMP_B}" trivial 1 none build)"
out_b="$(run_classify "${DISPATCH_SH}" "${TMP_B}" "${JUDGE_B}" "dispatch-brainB" "brainB01" "Heavy" "1" \
  "one-line typo fix")"
jf_b_content="$(journal_read_wait "${TMP_B}" "dispatch-brainB")"
if printf '%s' "${out_b}" "${jf_b_content}" | grep -q 'class_floor_held task=brainB01 declared=Heavy'; then
  pass "(b) trivial-but-declared-Heavy holds the floor, journaled"
else
  fail "(b) missing class_floor_held line: ${out_b}"
fi
printf '%s' "${out_b}" | grep -q 'CLASS=Heavy ' \
  && pass "(b) final class stays Heavy" || fail "(b) class did not stay Heavy: ${out_b}"
rm -rf "${TMP_B}"

# ── (c) judge fails outright -> declared_fallback, dispatch proceeds ────────
TMP_C="$(mktemp -d)"
JUDGE_C="$(mkstub_judge_fail "${TMP_C}")"
out_c="$(run_classify "${DISPATCH_SH}" "${TMP_C}" "${JUDGE_C}" "dispatch-brainC" "brainC01" "Standard" "1" \
  "some mission")"
jf_c="$(journal_file "${TMP_C}" "dispatch-brainC")"
if printf '%s' "${out_c}" "$( [[ -f "${jf_c}" ]] && cat "${jf_c}" )" | grep -q 'class_source=declared_fallback'; then
  pass "(c) judge failure -> declared_fallback"
else
  fail "(c) missing declared_fallback: ${out_c}"
fi
printf '%s' "${out_c}" | grep -q 'CLASS=Standard ' \
  && pass "(c) dispatch proceeds with declared class, no refusal" \
  || fail "(c) did not proceed with declared class: ${out_c}"
rm -rf "${TMP_C}"

# ── (c2) judge fails AND declared=Heavy -> floor holds at Heavy, not the ──
# old hard-coded Standard. This is the exact case round-1 review found
# uncovered: explicit=Standard (case c) passes identically whether or not
# _judge_fail_floor exists, since Standard==Standard either way.
TMP_C2="$(mktemp -d)"
JUDGE_C2="$(mkstub_judge_fail "${TMP_C2}")"
out_c2="$(run_classify "${DISPATCH_SH}" "${TMP_C2}" "${JUDGE_C2}" "dispatch-brainC2" "brainC201" "Heavy" "1" \
  "some heavy mission")"
printf '%s' "${out_c2}" | grep -q 'CLASS=Heavy ' \
  && pass "(c2) judge failure + declared=Heavy floors admission class at Heavy" \
  || fail "(c2) judge failure did not floor at Heavy: ${out_c2}"
[[ -f "${TMP_C2}/docs/handoff/dispatch-brainC2/brain.yaml" ]] \
  && grep -q '^class: Heavy' "${TMP_C2}/docs/handoff/dispatch-brainC2/brain.yaml" \
  && pass "(c2) brain.yaml records class: Heavy under judge-fail floor" \
  || fail "(c2) brain.yaml missing or wrong class for judge-fail floor"
rm -rf "${TMP_C2}"

# ── (c3) judge fails AND declared=Strategic -> floor holds at Strategic ─────
TMP_C3="$(mktemp -d)"
JUDGE_C3="$(mkstub_judge_fail "${TMP_C3}")"
out_c3="$(run_classify "${DISPATCH_SH}" "${TMP_C3}" "${JUDGE_C3}" "dispatch-brainC3" "brainC301" "Strategic" "1" \
  "some strategic mission")"
printf '%s' "${out_c3}" | grep -q 'CLASS=Strategic ' \
  && pass "(c3) judge failure + declared=Strategic floors admission class at Strategic" \
  || fail "(c3) judge failure did not floor at Strategic: ${out_c3}"
[[ -f "${TMP_C3}/docs/handoff/dispatch-brainC3/brain.yaml" ]] \
  && grep -q '^class: Strategic' "${TMP_C3}/docs/handoff/dispatch-brainC3/brain.yaml" \
  && pass "(c3) brain.yaml records class: Strategic under judge-fail floor" \
  || fail "(c3) brain.yaml missing or wrong class for judge-fail floor"
rm -rf "${TMP_C3}"

# ── (c4) judge fails AND declared=Light -> floor never LOWERS below Standard ─
TMP_C4="$(mktemp -d)"
JUDGE_C4="$(mkstub_judge_fail "${TMP_C4}")"
out_c4="$(run_classify "${DISPATCH_SH}" "${TMP_C4}" "${JUDGE_C4}" "dispatch-brainC4" "brainC401" "Light" "1" \
  "some light mission")"
printf '%s' "${out_c4}" | grep -q 'CLASS=Standard ' \
  && pass "(c4) judge failure + declared=Light never lowers below Standard" \
  || fail "(c4) judge failure with declared=Light did not floor at Standard: ${out_c4}"
rm -rf "${TMP_C4}"

# ── (c5) judge SUCCEEDS -> the judge's class wins over declared, both ways ──
# up: declared=Light, judge computes Heavy (safety-touching) -> Heavy wins.
TMP_C5="$(mktemp -d)"
JUDGE_C5="$(mkstub_judge "${TMP_C5}" complex 4 safety_publish_payments build)"
out_c5="$(run_classify "${DISPATCH_SH}" "${TMP_C5}" "${JUDGE_C5}" "dispatch-brainC5" "brainC501" "Light" "1" \
  "touch safety/gate.sh")"
printf '%s' "${out_c5}" | grep -q 'CLASS=Heavy \|CLASS=Standard ' \
  && pass "(c5-up) judge success escalates over a lower declared class" \
  || fail "(c5-up) judge success did not escalate: ${out_c5}"
rm -rf "${TMP_C5}"
# down: declared=Heavy, judge computes trivial -> declared floor holds Heavy
# (same invariant as (b), restated here for the judge-succeeds/declared-wins
# down-direction pairing the round-2 brief asks for).
TMP_C6="$(mktemp -d)"
JUDGE_C6="$(mkstub_judge "${TMP_C6}" trivial 1 none build)"
out_c6="$(run_classify "${DISPATCH_SH}" "${TMP_C6}" "${JUDGE_C6}" "dispatch-brainC6" "brainC601" "Heavy" "1" \
  "one-line typo fix")"
printf '%s' "${out_c6}" | grep -q 'CLASS=Heavy ' \
  && pass "(c5-down) declared floor holds Heavy over a lower judge-computed class" \
  || fail "(c5-down) declared floor did not hold: ${out_c6}"
rm -rf "${TMP_C6}"

# ── (d) brain.yaml + brain_decision line name the class the guard enforces ──
TMP_D="$(mktemp -d)"
JUDGE_D="$(mkstub_judge "${TMP_D}" complex 5 safety_publish_payments build)"
out_d="$(run_classify "${DISPATCH_SH}" "${TMP_D}" "${JUDGE_D}" "dispatch-brainD" "brainD01" "Light" "1" \
  "touches five subsystems")"
jf_d="$(journal_file "${TMP_D}" "dispatch-brainD")"
d_all="$(printf '%s\n%s' "${out_d}" "$( [[ -f "${jf_d}" ]] && cat "${jf_d}" )")"
printf '%s' "${d_all}" | grep -q 'brain_decision task=brainD01 class=Heavy class_source=escalated' \
  && pass "(d) brain_decision line names class=Heavy" \
  || fail "(d) brain_decision line missing/wrong: ${d_all}"
[[ -f "${TMP_D}/docs/handoff/dispatch-brainD/brain.yaml" ]] \
  && grep -q '^class: Heavy' "${TMP_D}/docs/handoff/dispatch-brainD/brain.yaml" \
  && pass "(d) brain.yaml class: Heavy" \
  || fail "(d) brain.yaml class mismatch"
# Same-task re-entry (cmd_advance_arm's path): _resolve_class_with_brain_floor
# must read that same brain.yaml as a floor over an independently-derived
# (lower) base class, and journal which record source won.
#
# R3 review fix (fix-round-4, item 1): this MUST assert against the function's
# actual return value (its stdout printf, the one string cmd_advance_arm
# captures as `_adv_class="$(...)"`), not against combined stdout+stderr. The
# decision/log line (`emit decision "phase_class_floor ... class=${brain_cls}"`,
# which lands on stderr via `log`) can say "Heavy" while the function still
# returns the wrong class on stdout -- that split is exactly what R3 found
# uncaught. Capture the two streams separately and assert stdout by itself.
TMP_D2ERR="$(mktemp)"
out_d2="$(blank_project_root_env LEADV2_DISPATCH_SOURCE_ONLY=1 PROJECT_ROOT="${TMP_D}" bash -c '
  source "$1"
  _resolve_class_with_brain_floor "brainD01" "dispatch-brainD" "Light"
' _ "${DISPATCH_SH}" 2>"${TMP_D2ERR}")"
err_d2="$(cat "${TMP_D2ERR}")"
rm -f "${TMP_D2ERR}"
[[ "${out_d2}" == "Heavy" ]] \
  && pass "(d) re-entry guard floor RETURNS class=Heavy (the routed value, on stdout alone) over a lower base class" \
  || fail "(d) re-entry floor did not return Heavy on stdout: stdout='${out_d2}' stderr='${err_d2}'"
rm -rf "${TMP_D}"

# ── mutation negative control: decision line says Heavy, return value lies ──
# Reproduces the exact false-pass the old `*"Heavy"*` substring-on-combined-
# streams assertion above missed: the `emit decision "phase_class_floor ...
# class=${brain_cls}"` line still fires (and still says Heavy on stderr), but
# the function is mutated to forget to reassign `cls` from `brain_cls`, so it
# returns the stale, lower base class on stdout. The stdout-only assertion
# above must go red on this mutant; the old combined-stream assertion would
# have stayed green. Applied to a temp copy of dispatch-code.sh -- never the
# tracked file.
TMP_MUT3="$(mktemp -d)"
MUT3_SH="${TMP_MUT3}/leadv2-dispatch-code.sh"
cp "${DISPATCH_SH}" "${MUT3_SH}"
# leadv2_brain_record/leadv2_brain_read_class live in lib/leadv2-brain-record.sh,
# sourced by SCRIPT_DIR-relative path with a canonical-checkout fallback that is
# NOT guaranteed present on this machine -- copy lib/ alongside the mutant so the
# brain write/read path this control depends on actually runs, same as it does
# for the tracked DISPATCH_SH.
cp -r "${SCRIPT_DIR}/../lib" "${TMP_MUT3}/lib"
python3 - "${MUT3_SH}" <<'PYEOF'
import sys
path = sys.argv[1]
with open(path) as f:
    text = f.read()
needle = '''      emit decision "phase_class_floor task=${sig8} source=brain_record class=${brain_cls}"
      cls="${brain_cls}"'''
assert needle in text, "_resolve_class_with_brain_floor reassignment not found -- mutation target drifted"
mutated = text.replace(
    needle,
    '      emit decision "phase_class_floor task=${sig8} source=brain_record class=${brain_cls}"\n'
    '      : # BRAIN-CLASS-LIVE-01 mutation: decision line still says Heavy, return value stays stale',
    1,
)
with open(path, "w") as f:
    f.write(mutated)
PYEOF
TMP_D3="$(mktemp -d)"
JUDGE_D3="$(mkstub_judge "${TMP_D3}" complex 5 safety_publish_payments build)"
run_classify "${MUT3_SH}" "${TMP_D3}" "${JUDGE_D3}" "dispatch-brainD3" "brainD301" "Light" "1" \
  "touches five subsystems" >/dev/null
TMP_D3ERR="$(mktemp)"
mut_out_d3="$(blank_project_root_env LEADV2_DISPATCH_SOURCE_ONLY=1 PROJECT_ROOT="${TMP_D3}" bash -c '
  source "$1"
  _resolve_class_with_brain_floor "brainD301" "dispatch-brainD3" "Light"
' _ "${MUT3_SH}" 2>"${TMP_D3ERR}")"
mut_err_d3="$(cat "${TMP_D3ERR}")"
rm -f "${TMP_D3ERR}"
if [[ "${mut_out_d3}" == "Heavy" ]]; then
  fail "MUTATION (d-re-entry) survived: stdout still returned Heavy despite the stale-cls mutation"
elif [[ "${mut_out_d3}" != "Heavy" && "${mut_err_d3}" == *"Heavy"* ]]; then
  pass "MUTATION (d-re-entry) killed: decision line still says Heavy (stderr='${mut_err_d3}') but the stdout-only assertion correctly rejects the stale return value ('${mut_out_d3}')"
else
  fail "MUTATION (d-re-entry) inconclusive: expected the decision line to still mention Heavy on stderr even though stdout is stale, got stdout='${mut_out_d3}' stderr='${mut_err_d3}'"
fi
rm -rf "${TMP_MUT3}" "${TMP_D3}"

# ── mutation negative control: skip the judge call unconditionally ─────────
# Applied to a temp copy of dispatch-code.sh -- never the tracked file.
TMP_MUT="$(mktemp -d)"
MUT_SH="${TMP_MUT}/leadv2-dispatch-code.sh"
cp "${DISPATCH_SH}" "${MUT_SH}"
python3 - "${MUT_SH}" <<'PYEOF'
import sys
path = sys.argv[1]
with open(path) as f:
    text = f.read()
needle = '  estimate="$(PROJECT_ROOT="${PROJECT_ROOT}" bash "${TASK_JUDGE_BIN}" \\\n    --mission-file "${mfile}" --task-id "dispatch-${sig8}" 2>/dev/null)"'
assert needle in text, "judge-call anchor not found -- mutation target drifted"
mutated = text.replace(
    needle,
    '  return 0  # BRAIN-CLASS-LIVE-01 mutation: judge call unconditionally skipped\n' + needle,
    1,
)
with open(path, "w") as f:
    f.write(mutated)
PYEOF
TMP_MA="$(mktemp -d)"
JUDGE_MA="$(mkstub_judge "${TMP_MA}" complex 4 safety_publish_payments build)"
out_ma="$(run_classify "${MUT_SH}" "${TMP_MA}" "${JUDGE_MA}" "dispatch-brainMA" "brainMA1" "Light" "1" \
  "touch hooks/ and safety/")"
jf_ma="$(journal_file "${TMP_MA}" "dispatch-brainMA")"
mut_out_a="$(printf '%s\n%s' "${out_ma}" "$( [[ -f "${jf_ma}" ]] && cat "${jf_ma}" )")"
if printf '%s' "${mut_out_a}" | grep -q 'class_escalated'; then
  fail "MUTATION (a) survived: class_escalated still fired with judge skipped"
else
  pass "MUTATION (a) killed: no class_escalated when judge call is skipped"
fi
if [[ -f "${TMP_MA}/docs/handoff/dispatch-brainMA/brain.yaml" ]]; then
  fail "MUTATION (d) survived: brain.yaml still written with judge skipped"
else
  pass "MUTATION (d) killed: no brain.yaml written when judge call is skipped"
fi
rm -rf "${TMP_MUT}" "${TMP_MA}"

# ── mutation negative control: revert _judge_fail_floor to the old ─────────
# hard-coded `ADMISSION_CLASS="Standard"` -- the reviewer's EXACT round-1
# mutation (this is the one case (c) alone failed to catch, since
# explicit=Standard passes identically whether the floor exists or not).
# Applied to a temp copy of dispatch-code.sh -- never the tracked file.
TMP_MUT2="$(mktemp -d)"
MUT2_SH="${TMP_MUT2}/leadv2-dispatch-code.sh"
cp "${DISPATCH_SH}" "${MUT2_SH}"
python3 - "${MUT2_SH}" <<'PYEOF'
import sys
path = sys.argv[1]
with open(path) as f:
    text = f.read()
needle = '''    local _judge_fail_floor
    _judge_fail_floor="$(_lv2_class_canonical "${explicit}")"
    if (( $(_lv2_class_rank "${_judge_fail_floor}") > $(_lv2_class_rank "Standard") )); then
      ADMISSION_CLASS="${_judge_fail_floor}"
    else
      ADMISSION_CLASS="Standard"
    fi'''
assert needle in text, "_judge_fail_floor block not found -- mutation target drifted"
mutated = text.replace(needle, '    ADMISSION_CLASS="Standard"', 1)
with open(path, "w") as f:
    f.write(mutated)
PYEOF
TMP_MB="$(mktemp -d)"
JUDGE_MB="$(mkstub_judge_fail "${TMP_MB}")"
out_mb="$(run_classify "${MUT2_SH}" "${TMP_MB}" "${JUDGE_MB}" "dispatch-brainMB" "brainMB01" "Heavy" "1" \
  "some heavy mission")"
if printf '%s' "${out_mb}" | grep -q 'CLASS=Heavy '; then
  fail "MUTATION (c2) survived: floor held at Heavy even with the hard-coded revert"
else
  pass "MUTATION (c2) killed: reverting to hard-coded Standard loses the Heavy floor"
fi
rm -rf "${TMP_MUT2}" "${TMP_MB}"

printf '\n=== test-brain-class-live.sh: %d PASS, %d FAIL ===\n' "${PASS}" "${FAIL}"
[[ ${FAIL} -eq 0 ]]
