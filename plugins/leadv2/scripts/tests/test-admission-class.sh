#!/usr/bin/env bash
# changed-scope triggers, self-registered (SD-SUITE-MAP-SERIALIZES-EVERY-WAVE-01, migrated from tests/run-all.sh EXTRA_SUITE_MAP; discovered by scan_suite_triggers):
# run-all-triggers: leadv2-admission-class
# test-admission-class.sh — PHASE-DISCIPLINE-01 D1/D2 unit coverage for
# lib/leadv2-admission-class.sh (the shared TaskEstimate->class map,
# escalate-only explicit flag, and the admission receipt).
#
# Negative control (C3b): named mutation this suite must kill — in
# leadv2_admission_class's escalate-only guard, the non-escalating branch
# (`printf '%s\t%s\n' "$explicit" "flag"`) flipped to instead print
# "$mapped"/"$src". That silently DE-ESCALATES a flagged Heavy/Standard task
# to whatever a re-estimate maps to (e.g. Heavy -> Light on a trivial
# estimate) — the exact regression the "never de-escalated" assertions above
# exist to catch. The suite applies this mutation to a temp copy of the lib
# and asserts it goes red.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB="${SCRIPT_DIR}/../lib/leadv2-admission-class.sh"
# shellcheck disable=SC1091
source "$LIB"

PASS=0; FAIL=0
pass(){ printf 'PASS: %s\n' "$1"; PASS=$((PASS+1)); }
fail(){ printf 'FAIL: %s\n' "$1" >&2; FAIL=$((FAIL+1)); }

est() { # complexity subsystems risk [work_kind] -> estimate json
  printf '{"complexity":"%s","subsystems_touched":%s,"risk_class":"%s","work_kind":"%s","estimate_source":"judge"}' "$1" "$2" "$3" "${4:-build}"
}

# ── D1: deterministic map ────────────────────────────────────────────────────
[[ "$(leadv2_admission_map_class "$(est trivial 1 none)")" == "Light" ]] \
  && pass "map: trivial -> Light" || fail "map: trivial"
[[ "$(leadv2_admission_map_class "$(est simple 2 none)")" == "Light" ]] \
  && pass "map: simple -> Light" || fail "map: simple"
[[ "$(leadv2_admission_map_class "$(est standard 3 none)")" == "Standard" ]] \
  && pass "map: standard -> Standard" || fail "map: standard"
[[ "$(leadv2_admission_map_class "$(est complex 3 none)")" == "Heavy" ]] \
  && pass "map: complex -> Heavy" || fail "map: complex"
[[ "$(leadv2_admission_map_class "$(est simple 1 safety_publish_payments)")" == "Heavy" ]] \
  && pass "map: risk safety_publish_payments -> Heavy" || fail "map: safety risk"
[[ "$(leadv2_admission_map_class "$(est simple 4 none)")" == "Heavy" ]] \
  && pass "map: subsystems>=4 -> Heavy" || fail "map: subsystems 4"
[[ -z "$(leadv2_admission_map_class 'not-json' 2>/dev/null)" ]] \
  && pass "map: unparseable estimate -> empty (caller takes classifier_error)" || fail "map: garbage"

# ── D1: escalate-only explicit flag ──────────────────────────────────────────
IFS=$'\t' read -r c s <<<"$(leadv2_admission_class Light 1 "$(est complex 3 none)")"
[[ "$c" == "Heavy" && "$s" == "judge" ]] \
  && pass "flag Light escalated to Heavy by risk signals" || fail "escalate: got $c/$s"
IFS=$'\t' read -r c s <<<"$(leadv2_admission_class Heavy 1 "$(est trivial 1 none)")"
[[ "$c" == "Heavy" && "$s" == "flag" ]] \
  && pass "flag Heavy never de-escalated to Light" || fail "de-escalate guard: got $c/$s"
IFS=$'\t' read -r c s <<<"$(leadv2_admission_class Standard 1 "$(est trivial 1 none)")"
[[ "$c" == "Standard" && "$s" == "flag" ]] \
  && pass "flag Standard never de-escalated" || fail "flag standard: got $c/$s"
IFS=$'\t' read -r c s <<<"$(leadv2_admission_class standard 1 "$(est trivial 1 none)")"
[[ "$c" == "Standard" && "$s" == "flag" ]] \
  && pass "lowercase CLI --task-class standard binds Standard on first dispatch" || fail "lowercase flag: got $c/$s"
IFS=$'\t' read -r c s <<<"$(leadv2_admission_class "" 0 "$(est standard 2 none)")"
[[ "$c" == "Standard" && "$s" == "judge" ]] \
  && pass "no flag: estimate wins" || fail "no-flag: got $c/$s"

# ── D6: work_kind -> FREEPOOL_ROLE projection ───────────────────────────────
[[ "$(leadv2_admission_freepool_role review)" == "review" ]] \
  && pass "role: review -> review" || fail "role: review"
[[ "$(leadv2_admission_freepool_role build)" == "implement" ]] \
  && pass "role: build -> implement" || fail "role: build"
[[ "$(leadv2_admission_freepool_role diagnose)" == "implement" ]] \
  && pass "role: diagnose -> implement" || fail "role: diagnose"
[[ "$(leadv2_admission_freepool_role docs)" == "bulk" ]] \
  && pass "role: docs -> bulk" || fail "role: docs"
[[ -z "$(leadv2_admission_freepool_role '')" ]] \
  && pass "role: empty -> empty (no export)" || fail "role: empty"

# ── D2: receipt write/read/once ─────────────────────────────────────────────
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP"
sig="aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
leadv2_admission_write_receipt "$TMP" "${sig:0:8}" "T-1" "$sig" Standard phases judge review
rc=$?
[[ $rc -eq 0 ]] && pass "receipt: written rc=0" || fail "receipt: write rc=$rc"
# SAFETY-PIN-SECOND-DOOR-01: read_receipt now always appends a 7th
# tab-delimited risk_class field (empty when the writer didn't pass one, as
# here) so the dispatch-code.sh call site can positionally parse both old and
# new receipts the same way.
row="$(leadv2_admission_read_receipt "$TMP" "${sig:0:8}")"
[[ "$row" == "$(printf 'Standard\tphases\tjudge\treview\t%s\tT-1\t' "$sig")" ]] \
  && pass "receipt: read back all seven fields (risk_class empty)" || fail "receipt: read got '$row'"
[[ "$(leadv2_admission_read_task_receipt "$TMP" "T-1")" == "Standard" ]] \
  && pass "receipt: task-keyed class record written" || fail "receipt: task record missing"
# digest binding is what the re-entry guard keys on
printf '%s' "$row" | grep -q "$sig" && pass "receipt: mission digest bound" || fail "receipt: digest missing"
# write-once: a second intake for the same sig8 must NOT overwrite
leadv2_admission_write_receipt "$TMP" "${sig:0:8}" "T-2" "ffffffff" Light dispatch flag ""
row2="$(leadv2_admission_read_receipt "$TMP" "${sig:0:8}")"
printf '%s' "$row2" | grep -q "T-1" && ! printf '%s' "$row2" | grep -q "T-2" \
  && pass "receipt: never overwritten on second write" || fail "receipt: overwrite happened ($row2)"
[[ -z "$(leadv2_admission_read_receipt "$TMP" "deadbeef")" ]] \
  && pass "receipt: absent sig8 reads empty" || fail "receipt: phantom read"

# SAFETY-PIN-SECOND-DOOR-01: risk_class round-trips through the receipt so a
# cache-hit resume can still recover the judge's safety signal without
# re-judging (leadv2-dispatch-code.sh's cmd_resolve reads this field to
# decide whether to fold the safety pin in on a same-digest re-entry).
sig2="bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
leadv2_admission_write_receipt "$TMP" "${sig2:0:8}" "T-3" "$sig2" Heavy phases judge build safety_publish_payments
row3="$(leadv2_admission_read_receipt "$TMP" "${sig2:0:8}")"
[[ "$row3" == "$(printf 'Heavy\tphases\tjudge\tbuild\t%s\tT-3\tsafety_publish_payments' "$sig2")" ]] \
  && pass "receipt: risk_class round-trips through write/read" || fail "receipt: risk_class got '$row3'"

# ── ADMISSION-CLASS-FALLS-BACK-TO-LIGHT-01: derivation + strict fallback ─────
# The fallback estimate is line-count-only; before it may decide the phase
# mode, leadv2_admission_class derives a floor from observables (touched
# paths, prior cost classification, mission size). A fallback with NO
# observable is STRICT: Standard, never Light. Mutation controls for this
# section run OUT of suite via leadv2-mutation-control.sh (see
# docs/handoff/ADMISSION-CLASS-FALLS-BACK-TO-LIGHT-01/mutation-control/):
#   M1 core-path matcher neutered      -> the lib/-dispatcher cases below go red
#   M2 strict-default flip reverted    -> the knows-nothing case goes red
#   M3 cost-classification floor cut   -> the cost floor case goes red
#   M4 escalate-only `>` flipped `>=`  -> flag-beats-derivation goes red
#   M5 door stops passing the mission  -> both door wiring cases go red
fbest() { # complexity -> fallback-sourced estimate json
  printf '{"complexity":"%s","subsystems_touched":1,"risk_class":"none","work_kind":"build","estimate_source":"fallback"}' "$1"
}
mkdir -p "$TMP/missions"
printf 'Fix the guard\n\nПравь lib/leadv2-lane-guard.sh и тесты.\n'      > "$TMP/missions/core.txt"
printf 'Fix dispatcher\n\nОбнови leadv2-dispatch-code.sh.\n'             > "$TMP/missions/disp.txt"
printf 'Tidy\n\nUpdate the README wording in docs.\n'                    > "$TMP/missions/small.txt"
printf 'Cleanup\n\nНе трогать: main, docs/leadv2/, lib/ и leadv2-dispatch-code.sh.\n' > "$TMP/missions/excl.txt"
{ printf 'Big mission header\n\n'; i=0; while (( i < 120 )); do printf 'line %d of padding\n' "$i"; i=$((i+1)); done; } > "$TMP/missions/big.txt"
printf 'estimate:\n  task_id: T-COST\n  classification: Heavy\n' > "$TMP/cost-heavy.yaml"
printf 'estimate:\n  task_id: T-LIGHT\n  classification: Light\n' > "$TMP/cost-light.yaml"

# lib/-touching task with a fallback (knows-nothing) estimate is never Light
IFS=$'\t' read -r c s <<<"$(leadv2_admission_class "" 0 "$(fbest trivial)" "$TMP/missions/core.txt" "")"
[[ "$c" == "Standard" && "$s" == "derived" ]] \
  && pass "derive: lib/-touching mission + fallback -> Standard/derived (never Light)" || fail "derive: lib mission got $c/$s"
# dispatcher-named mission alone is enough for the core floor
IFS=$'\t' read -r c s <<<"$(leadv2_admission_class "" 0 "$(fbest trivial)" "$TMP/missions/disp.txt" "")"
[[ "$c" == "Standard" && "$s" == "derived" ]] \
  && pass "derive: dispatcher-touching mission -> Standard/derived" || fail "derive: dispatcher got $c/$s"
# small clean mission: size alone justifies Light, but as DERIVED, not blind
IFS=$'\t' read -r c s <<<"$(leadv2_admission_class "" 0 "$(fbest trivial)" "$TMP/missions/small.txt" "")"
[[ "$c" == "Light" && "$s" == "derived" ]] \
  && pass "derive: small clean mission -> Light/derived (size justifies)" || fail "derive: small got $c/$s"
# a path named only on an exclusion line ("Не трогать: ...") is not a touch
IFS=$'\t' read -r c s <<<"$(leadv2_admission_class "" 0 "$(fbest trivial)" "$TMP/missions/excl.txt" "")"
[[ "$c" == "Light" && "$s" == "derived" ]] \
  && pass "derive: exclusion-line path mention is not a touch" || fail "derive: excl got $c/$s"
# >100-line mission floors at Standard even if the estimate said trivial
IFS=$'\t' read -r c s <<<"$(leadv2_admission_class "" 0 "$(fbest trivial)" "$TMP/missions/big.txt" "")"
[[ "$c" == "Standard" && "$s" == "derived" ]] \
  && pass "derive: >100-line mission -> Standard/derived" || fail "derive: big got $c/$s"
# no observable at all (no mission file, no cost record): STRICT, never Light
IFS=$'\t' read -r c s <<<"$(leadv2_admission_class "" 0 "$(fbest trivial)" "" "")"
[[ "$c" == "Standard" && "$s" == "fallback" ]] \
  && pass "strict: knows-nothing fallback -> Standard/fallback (default flip)" || fail "strict: got $c/$s"
# prior cycle's cost-estimate.yaml classification is a floor (re-entry case)
IFS=$'\t' read -r c s <<<"$(leadv2_admission_class "" 0 "$(fbest trivial)" "$TMP/missions/small.txt" "$TMP/cost-heavy.yaml")"
[[ "$c" == "Heavy" && "$s" == "derived" ]] \
  && pass "derive: cost-estimate.yaml classification Heavy -> Heavy/derived" || fail "derive: cost got $c/$s"
# a Light cost classification does not raise anything
IFS=$'\t' read -r c s <<<"$(leadv2_admission_class "" 0 "$(fbest trivial)" "$TMP/missions/small.txt" "$TMP/cost-light.yaml")"
[[ "$c" == "Light" && "$s" == "derived" ]] \
  && pass "derive: cost classification Light stays Light" || fail "derive: cost-light got $c/$s"
# a judge estimate is never re-derived (judge already read the task)
IFS=$'\t' read -r c s <<<"$(leadv2_admission_class "" 0 "$(est trivial 1 none)" "$TMP/missions/core.txt" "")"
[[ "$c" == "Light" && "$s" == "judge" ]] \
  && pass "derive: judge estimate untouched -> Light/judge" || fail "derive: judge got $c/$s"

# explicit flag beats derivation at equal rank (human decision, not overridden)
IFS=$'\t' read -r c s <<<"$(leadv2_admission_class Standard 1 "$(fbest trivial)" "$TMP/missions/core.txt" "")"
[[ "$c" == "Standard" && "$s" == "flag" ]] \
  && pass "flag: explicit Standard beats a Standard derivation -> source flag" || fail "flag-beats-derive: got $c/$s"
# flag never de-escalated by derivation
IFS=$'\t' read -r c s <<<"$(leadv2_admission_class Heavy 1 "$(fbest trivial)" "$TMP/missions/core.txt" "")"
[[ "$c" == "Heavy" && "$s" == "flag" ]] \
  && pass "flag: explicit Heavy not de-escalated by derivation" || fail "flag-heavy: got $c/$s"
# derivation may still ESCALATE a flag (same escalate-only doctrine as judge)
IFS=$'\t' read -r c s <<<"$(leadv2_admission_class Light 1 "$(fbest trivial)" "$TMP/missions/core.txt" "")"
[[ "$c" == "Standard" && "$s" == "derived" ]] \
  && pass "flag: flagged Light escalated to Standard by core-path derivation" || fail "flag-escalate: got $c/$s"

# door: lock the WIRING, not just the lib — _admission_classify must hand
# the mission text (+ cost-yaml path) to leadv2_admission_class, or a
# fallback estimate silently loses derivation again at the dispatch door.
DISPATCH_SH="${SCRIPT_DIR}/../leadv2-dispatch-code.sh"
# Each call gets its own hermetic root + task id + sig: a shared root would
# make the second call a same-task re-entry whose task-record floor (D1/D2,
# correct behaviour) masks the derivation under test here.
_door() { # <judge-stub> <mission> <id> -> last stdout line "CLASS=<c> SOURCE=<s>"
  env CLAUDE_PROJECT_ROOT= CLAUDE_PROJECT_DIR= LEADV2_PROJECT_ROOT= \
    LEADV2_DISPATCH_SOURCE_ONLY=1 PROJECT_ROOT="$TMP/door-root-$3" \
    LEADV2_TASK_JUDGE_BIN="$1" founder_task_id="T-DOOR-$3" JOURNAL_TASK="T-DOOR-$3" \
    bash -c '
      source "$1"
      _admission_classify "$2" "$3" "${3:0:8}sig0" "" 0
      echo "CLASS=${ADMISSION_CLASS} SOURCE=${ADMISSION_SOURCE}"
    ' _ "${DISPATCH_SH}" "$2" "$3" 2>/dev/null | tail -1
}
cat > "$TMP/judge-fb.sh" <<'JEOF'
#!/usr/bin/env bash
printf '%s' '{"complexity":"trivial","subsystems_touched":1,"risk_class":"none","work_kind":"build","estimate_source":"fallback"}'
JEOF
chmod +x "$TMP/judge-fb.sh"
out="$(_door "$TMP/judge-fb.sh" "Правь lib/leadv2-lane-guard.sh и диспетчер leadv2-dispatch-code.sh." doorcore)"
[[ "$out" == "CLASS=Standard SOURCE=derived" ]] \
  && pass "door: fallback estimate + core-path mission -> Standard/derived" || fail "door: core got '$out'"
out="$(_door "$TMP/judge-fb.sh" "Update the README wording." doorsmall)"
[[ "$out" == "CLASS=Light SOURCE=derived" ]] \
  && pass "door: fallback estimate + small clean mission -> Light/derived" || fail "door: small got '$out'"
# task-record floor still rules a same-task re-entry (D1 semantics unchanged)
mkdir -p "$TMP/door-root-reentry/docs/handoff/T-DOOR-reentry"
printf 'task_id: T-DOOR-reentry\ntask_class: Standard\nsource: flag\n' \
  > "$TMP/door-root-reentry/docs/handoff/T-DOOR-reentry/task-class.yaml"
out="$(_door "$TMP/judge-fb.sh" "Update the README wording." reentry)"
[[ "$out" == "CLASS=Standard SOURCE=task_record" ]] \
  && pass "door: task-record floor Standard beats a derived Light on re-entry" || fail "door: reentry got '$out'"

# requirement 3: the class FILE keeps the source — a derived admission must
# be distinguishable from a hand-flagged one on disk
sig3="cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc"
leadv2_admission_write_receipt "$TMP" "${sig3:0:8}" "T-4" "$sig3" Standard phases derived build
grep -q '^source: derived$' "$TMP/docs/handoff/dispatch-${sig3:0:8}/admission-receipt.yaml" \
  && pass "receipt: source=derived persisted in the class file" || fail "receipt: derived source not in class file"
grep -q '^source: derived$' "$TMP/docs/handoff/T-4/task-class.yaml" \
  && pass "receipt: task-keyed class file carries source=derived" || fail "receipt: task class file missing derived source"

# ── C3b negative control: apply the named mutation to a temp copy, assert red ─
MUT_LIB="$TMP/leadv2-admission-class.mut.sh"
cp "${SCRIPT_DIR}/../lib/leadv2-lane-guard.sh" "$TMP/leadv2-lane-guard.sh"
python3 - "$LIB" "$MUT_LIB" <<'PYEOF'
import sys
src, dst = sys.argv[1], sys.argv[2]
text = open(src, encoding="utf-8").read()
old = '      printf \'%s\\t%s\\n\' "$explicit" "flag"\n'
new = '      printf \'%s\\t%s\\n\' "$mapped" "$src"\n'
if old not in text:
    sys.exit(2)
open(dst, "w", encoding="utf-8").write(text.replace(old, new, 1))
PYEOF
mut_status=$?
if [[ $mut_status -ne 0 ]]; then
  fail "control: mutation source pattern not found (lib drifted, update mutation)"
else
  (
    # shellcheck disable=SC1090
    source "$MUT_LIB"
    IFS=$'\t' read -r mc ms <<<"$(leadv2_admission_class Heavy 1 "$(est trivial 1 none)")"
    [[ "$mc" == "Heavy" ]] && exit 0 || exit 1
  )
  mut_rc=$?
  [[ $mut_rc -ne 0 ]] && pass "control: mutated lib de-escalates flagged Heavy -> caught (would be red)" \
    || fail "control: mutation NOT caught — de-escalate guard is not actually tested"
fi

printf 'SUMMARY: pass=%s fail=%s\n' "$PASS" "$FAIL"
(( FAIL == 0 ))
