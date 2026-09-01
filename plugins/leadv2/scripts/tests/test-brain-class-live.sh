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

# ── (a) light mission touching hooks/+safety -> escalated to Standard|Heavy ──
TMP_A="$(mktemp -d)"
JUDGE_A="$(mkstub_judge "${TMP_A}" complex 4 safety_publish_payments build)"
out_a="$(run_classify "${DISPATCH_SH}" "${TMP_A}" "${JUDGE_A}" "dispatch-brainA" "brainA01" "Light" "1" \
  "touch hooks/pre-commit.sh and safety/gate.sh")"
jf_a="$(journal_file "${TMP_A}" "dispatch-brainA")"
if printf '%s' "${out_a}" "$( [[ -f "${jf_a}" ]] && cat "${jf_a}" )" | grep -q 'class_escalated task=brainA01 from=Light to=\(Standard\|Heavy\)'; then
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
jf_b="$(journal_file "${TMP_B}" "dispatch-brainB")"
if printf '%s' "${out_b}" "$( [[ -f "${jf_b}" ]] && cat "${jf_b}" )" | grep -q 'class_floor_held task=brainB01 declared=Heavy'; then
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
out_d2="$(LEADV2_DISPATCH_SOURCE_ONLY=1 PROJECT_ROOT="${TMP_D}" bash -c '
  source "$1"
  _resolve_class_with_brain_floor "brainD01" "dispatch-brainD" "Light"
' _ "${DISPATCH_SH}" 2>&1)"
[[ "${out_d2}" == *"Heavy"* ]] \
  && pass "(d) re-entry guard floor reads brain.yaml class=Heavy over a lower base class" \
  || fail "(d) re-entry floor did not enforce Heavy: ${out_d2}"
rm -rf "${TMP_D}"

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

printf '\n=== test-brain-class-live.sh: %d PASS, %d FAIL ===\n' "${PASS}" "${FAIL}"
[[ ${FAIL} -eq 0 ]]
