#!/usr/bin/env bash
# tests/test-state-layer-silent-write.sh
#
# STATE-LAYER-CANNOT-SAY-IT-FAILED-01: census + detector for functions that
# take a write, don't perform it, and still return 0 (caller can't tell
# success from silence). This suite validates a small behavioural-shape
# scanner, then uses it to (a) re-detect the known real instances by the
# scanner's own mechanism -- not a hardcoded name lookup -- and (b) prove via
# mutation that the scanner reacts to the shape appearing/disappearing, not
# to a fixed list.
#
# run-all-triggers: self-select -- this file lives at
# plugins/leadv2/scripts/tests/test-*.sh, which tests/run-all.sh's own
# "a changed test suite selects itself" rule (see tests/run-all.sh:452-460)
# and leadv2-dod-gate.sh::_dod_check_c's self-selecting-conventional-dirs
# list both already recognize. No EXTRA_SUITE_MAP row, no run-all.sh edit.
#
# Bash 3.2 safe: indexed arrays only, no associative arrays, no `readarray`,
# no `${x^^}`. Portable `sed -i.bak` (works under both GNU and BSD sed).
set -uo pipefail

# STATE-LAYER-CANNOT-SAY-IT-FAILED-01 / lead fix: under zsh BASH_SOURCE does not
# exist, so HERE resolved to the caller's cwd and every known-instance lookup came
# back MISSING -- the detector reported "no such functions exist" because it was
# looking in the wrong directory. That is the exact false zero this lane counts,
# occurring inside the lane's own instrument. Resolution order as in the merged
# lib/leadv2-lane-state.sh: this file's path when bash names it, then $0.
# The classifier reads function bodies from `declare -f`, whose output shape is
# bash-specific: under zsh every lookup came back CLEAN — a detector for silent
# failures failing silently. A skip would be no better (a suite that does not run
# must not look like one that found nothing), so re-exec under bash instead, and
# refuse loudly if bash is absent.
if [ -z "${BASH_VERSION:-}" ]; then
  if command -v bash >/dev/null 2>&1; then
    exec bash "$0" "$@"
  fi
  printf 'FAIL: this suite classifies `declare -f` output and needs bash; no bash found.\n' >&2
  printf '      Refusing to run under another shell: every lookup would report CLEAN,\n' >&2
  printf '      which is the false zero this suite exists to detect.\n' >&2
  exit 2
fi

_ssw_src="${BASH_SOURCE[0]:-}"
if [[ -z "$_ssw_src" && -f "${0:-}" ]]; then _ssw_src="$0"; fi
HERE="$(cd "$(dirname "$_ssw_src")" && pwd)"
SCRIPTS_DIR="$(cd "${HERE}/.." && pwd)"
LIB_DIR="${SCRIPTS_DIR}/lib"

PASS=0
FAIL=0
FAILED_NAMES=()

ok() { printf 'PASS: %s\n' "$1"; PASS=$((PASS + 1)); }
bad() { printf 'FAIL: %s -- %s\n' "$1" "$2"; FAIL=$((FAIL + 1)); FAILED_NAMES+=("$1"); }

# ---------------------------------------------------------------------------
# The scanner. Classifies one function body (as printed by `declare -f`) as
# FLAGGED if there is an early `... || return 0` guard that is NOT the last
# effective statement in the function (i.e. real work was skippable behind
# a silent-success exit), OR a statement whose own failure is swallowed via
# `|| true` / `|| :`. This is a behavioural-shape rule, not a literal-text
# match against any known finding -- it has no list of function names baked
# in. False positives are possible (e.g. a legitimate idempotency fast-path);
# that is an accepted cost for a census/detector, not a correctness proof.
# ---------------------------------------------------------------------------
_ssw_classify_body() { # <body-text> -> prints FLAGGED or CLEAN
  local body="$1" line trimmed guard_seen=0 verdict="CLEAN"
  while IFS= read -r line; do
    trimmed="$(printf '%s' "$line" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
    case "$trimmed" in
      ""|"{"|"}"|"#"*) continue ;;
    esac
    # skip the `declare -f` function-header line itself, e.g. `foo ()`
    if [[ "$trimmed" =~ ^[A-Za-z_][A-Za-z0-9_]*[[:space:]]*\(\)[[:space:]]*$ ]]; then
      continue
    fi
    if [[ ${guard_seen} -eq 1 ]]; then
      case "$trimmed" in
        local\ *) : ;;  # a bare local decl right after the guard isn't "skipped work"
        *) verdict="FLAGGED" ;;
      esac
    fi
    if [[ "$trimmed" =~ \|\|[[:space:]]*return[[:space:]]+0([[:space:]]|\;|$) ]]; then
      guard_seen=1
      continue
    fi
    if [[ "$trimmed" =~ \|\|[[:space:]]*(true|:)([[:space:]]|\;|$) ]]; then
      verdict="FLAGGED"
    fi
  done <<< "${body}"
  printf '%s' "${verdict}"
}

_ssw_source_and_dump() { # <file> <funcname> [dummy-args...] -> body on stdout
  local file="$1" fn="$2" work body
  shift 2
  work="$(mktemp -d "${TMPDIR:-/tmp}/ssw-src.XXXXXX")" || return 1
  body="$(
    cd "${work}" 2>/dev/null || exit 1
    git init -q . >/dev/null 2>&1 || true
    export PROJECT_ROOT="${work}" LEADV2_PROJECT_ROOT="${work}"
    set +e +u
    # shellcheck disable=SC1090
    source "${file}" "$@" >/dev/null 2>&1
    declare -f "${fn}" 2>/dev/null
  )"
  rm -rf "${work}" 2>/dev/null
  printf '%s' "${body}"
}

_ssw_get_body() { # <file> <funcname> -> body on stdout; rc1 if function absent
  local file="$1" fn="$2" body
  # Plain source first (works for library-style files with no top-level
  # arg dispatch, e.g. leadv2-active-registry.sh, lib/*.sh).
  body="$(_ssw_source_and_dump "${file}" "${fn}")"
  if [[ -z "${body}" ]]; then
    # Some state-layer files (leadv2-phase-record.sh) are CLI scripts with
    # an unconditional `main` dispatch at file scope: `source`-ing them with
    # zero args hits their own `usage; exit 4` before we ever get to
    # `declare -f`, which kills the subshell before it dumps anything. Retry
    # with a harmless, argument-complete subcommand so the dispatch falls
    # through cleanly and function definitions (already parsed earlier in
    # the file) survive to the `declare -f` call.
    body="$(_ssw_source_and_dump "${file}" "${fn}" is-bootstrap deadbeef00)"
  fi
  [[ -n "${body}" ]] || return 1
  printf '%s' "${body}"
}

_ssw_classify_real() { # <file> <funcname> -> FLAGGED|CLEAN|MISSING
  local body
  body="$(_ssw_get_body "$1" "$2")" || { printf 'MISSING'; return; }
  _ssw_classify_body "${body}"
}

assert_eq() { # <name> <expected> <actual>
  if [[ "$2" == "$3" ]]; then ok "$1"; else bad "$1" "expected=$2 actual=$3"; fi
}

# ===========================================================================
# Part 1 -- re-detect known real instances, by the scanner's own mechanism.
# Acceptance bar: a census that reports "no such functions exist" must
# rediscover at least one of the three documented instances. Two of the
# three (registration-guard family, deregistration) are directly detectable
# by this bash-level shape rule; the third (phase-record's wrong-repo root
# trust) is a missing-validation defect, not a guard-shape defect, and is
# out of reach of this scanner by design -- it is recorded in census.md by
# direct measurement instead.
# ===========================================================================
REG="${SCRIPTS_DIR}/leadv2-active-registry.sh"
PHR="${SCRIPTS_DIR}/leadv2-phase-record.sh"
ARM="${LIB_DIR}/leadv2-arm-cooldown.sh"
BRN="${LIB_DIR}/leadv2-brain-record.sh"

assert_eq "known instance: leadv2_active_unregister (deregistration) flagged" \
  "FLAGGED" "$(_ssw_classify_real "${REG}" "leadv2_active_unregister")"

assert_eq "known instance: phase-record _emit (journal fire-and-forget) flagged" \
  "FLAGGED" "$(_ssw_classify_real "${PHR}" "_emit")"

# Two additional real instances from census.md rows 17/14, to demonstrate the
# scanner generalizes past the two functions singled out above.
assert_eq "census row 17: arm_cooldown_record flagged" \
  "FLAGGED" "$(_ssw_classify_real "${ARM}" "arm_cooldown_record")"

assert_eq "census row 14: leadv2_brain_write_yaml flagged" \
  "FLAGGED" "$(_ssw_classify_real "${BRN}" "leadv2_brain_write_yaml")"

# ===========================================================================
# Part 2 -- negative control: a clean function (proper nonzero returns, no
# swallowed failures) must NOT be flagged.
# ===========================================================================
_ssw_safe_write() {
  local dir="${1:?dir required}"
  [[ -n "${dir}" ]] || return 1
  mkdir -p "${dir}" || return 1
  printf 'x' > "${dir}/f" || return 1
  return 0
}
SAFE_BODY_ORIG="$(declare -f _ssw_safe_write)"

assert_eq "negative control: clean function not flagged" \
  "CLEAN" "$(_ssw_classify_body "${SAFE_BODY_ORIG}")"

# ===========================================================================
# Part 3 -- mutation triple A (synthetic): prove the scanner reacts to the
# shape appearing, not to the function's identity. Assert the mutant differs
# byte-for-byte from the original before classifying it.
# ===========================================================================
baseline_rc_A="$(_ssw_classify_body "${SAFE_BODY_ORIG}")"

# Mutate via a line-numbered sed pass on a temp file -- safer than bash
# parameter substitution here, since the target text itself contains `${...}`
# sequences that bash's `${var/pat/repl}` glob-pattern parser misreads as
# nested parameter expansions.
WORK_A="$(mktemp -d "${TMPDIR:-/tmp}/ssw-mut-a.XXXXXX")"
BODY_FILE_A="${WORK_A}/body.txt"
printf '%s\n' "${SAFE_BODY_ORIG}" > "${BODY_FILE_A}"
MKDIR_LINE_A="$(grep -n 'mkdir -p' "${BODY_FILE_A}" | head -1 | cut -d: -f1)"
sed -i.bak "${MKDIR_LINE_A}s#|| return 1#2>/dev/null || true#" "${BODY_FILE_A}"
SAFE_BODY_MUTATED="$(cat "${BODY_FILE_A}")"
rm -rf "${WORK_A}" 2>/dev/null

if [[ "${SAFE_BODY_MUTATED}" == "${SAFE_BODY_ORIG}" ]]; then
  bad "mutation A: mutant differs from original" "sed/substitution produced no change"
else
  ok "mutation A: mutant differs from original"
fi

mutated_rc_A="$(_ssw_classify_body "${SAFE_BODY_MUTATED}")"
restored_rc_A="$(_ssw_classify_body "${SAFE_BODY_ORIG}")"

printf 'mutation A (synthetic safe_write): baseline=%s mutated=%s restored=%s\n' \
  "${baseline_rc_A}" "${mutated_rc_A}" "${restored_rc_A}"

assert_eq "mutation A: baseline is CLEAN" "CLEAN" "${baseline_rc_A}"
assert_eq "mutation A: injecting a swallowed-write turns it FLAGGED" "FLAGGED" "${mutated_rc_A}"
assert_eq "mutation A: restoring the original text returns it to CLEAN" "CLEAN" "${restored_rc_A}"

# ===========================================================================
# Part 4 -- mutation triple B (real function, copied file): take the known
# real defect (leadv2_active_unregister), mutate away its guard's silent
# return-0 on a COPY, and prove the scanner flips from FLAGGED to CLEAN --
# then restore and reconfirm FLAGGED. This never touches the real file.
# ===========================================================================
WORK_B="$(mktemp -d "${TMPDIR:-/tmp}/ssw-mut-b.XXXXXX")"
COPY_B="${WORK_B}/leadv2-active-registry.sh"
cp "${REG}" "${COPY_B}"

GUARD_LINE_B="$(awk '
  /^leadv2_active_unregister\(\)/ { infn = 1 }
  infn && /\|\| return 0/ { print NR; exit }
  infn && /^}/ { exit }
' "${COPY_B}")"

if [[ -z "${GUARD_LINE_B}" ]]; then
  bad "mutation B: located the guard line in leadv2_active_unregister" "no matching line found (function shape changed?)"
else
  ok "mutation B: located the guard line in leadv2_active_unregister (line ${GUARD_LINE_B})"

  ORIG_TEXT_B="$(sed -n "${GUARD_LINE_B}p" "${COPY_B}")"
  baseline_rc_B="$(_ssw_classify_real "${COPY_B}" "leadv2_active_unregister")"

  sed -i.bak "${GUARD_LINE_B}s/return 0/return 1/" "${COPY_B}"
  MUT_TEXT_B="$(sed -n "${GUARD_LINE_B}p" "${COPY_B}")"

  if [[ "${MUT_TEXT_B}" == "${ORIG_TEXT_B}" ]]; then
    bad "mutation B: mutant line differs from original" "sed produced no change"
  else
    ok "mutation B: mutant line differs from original"
  fi

  bash -n "${COPY_B}" 2>/tmp/ssw-mut-b-parse.$$.log
  parse_rc_B=$?
  if [[ ${parse_rc_B} -ne 0 ]]; then
    bad "mutation B: mutated copy still parses (bash -n)" "$(cat /tmp/ssw-mut-b-parse.$$.log)"
  else
    ok "mutation B: mutated copy still parses (bash -n)"
  fi
  rm -f "/tmp/ssw-mut-b-parse.$$.log"

  mutated_rc_B="$(_ssw_classify_real "${COPY_B}" "leadv2_active_unregister")"

  # restore
  mv -f "${COPY_B}.bak" "${COPY_B}"
  RESTORED_TEXT_B="$(sed -n "${GUARD_LINE_B}p" "${COPY_B}")"
  restored_rc_B="$(_ssw_classify_real "${COPY_B}" "leadv2_active_unregister")"

  printf 'mutation B (leadv2_active_unregister, copied file): baseline=%s mutated=%s restored=%s\n' \
    "${baseline_rc_B:-}" "${mutated_rc_B:-}" "${restored_rc_B:-}"

  assert_eq "mutation B: restored line matches original byte-for-byte" \
    "${ORIG_TEXT_B}" "${RESTORED_TEXT_B}"
  assert_eq "mutation B: baseline (real defect) is FLAGGED" "FLAGGED" "${baseline_rc_B:-}"
  assert_eq "mutation B: fixing the guard (return 0 -> return 1) turns it CLEAN" \
    "CLEAN" "${mutated_rc_B:-}"
  assert_eq "mutation B: restoring the original guard returns it to FLAGGED" \
    "FLAGGED" "${restored_rc_B:-}"
fi

rm -rf "${WORK_B}" 2>/dev/null

# ===========================================================================
# Summary
# ===========================================================================
printf -- '---\n%d passed, %d failed\n' "${PASS}" "${FAIL}"
if [[ ${FAIL} -gt 0 ]]; then
  printf 'Failed assertions:\n'
  for n in "${FAILED_NAMES[@]}"; do printf '  - %s\n' "$n"; done
  exit 1
fi
exit 0
