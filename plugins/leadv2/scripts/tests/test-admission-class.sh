#!/usr/bin/env bash
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
row="$(leadv2_admission_read_receipt "$TMP" "${sig:0:8}")"
[[ "$row" == "$(printf 'Standard\tphases\tjudge\treview\t%s\tT-1' "$sig")" ]] \
  && pass "receipt: read back all six fields" || fail "receipt: read got '$row'"
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
