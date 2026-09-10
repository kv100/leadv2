#!/usr/bin/env bash
# changed-scope triggers, self-registered (scan_suite_triggers convention):
# run-all-triggers: leadv2-dispatch-code
# W1-ARBITER-BYPASSED-ON-DISPATCH-01 (part B) -- the ladder-fallback telemetry
# died exactly when it was owed. Live 2026-09-10:
#   leadv2-dispatch-code.sh: line 2026: attempted: unbound variable
# inside _route_arm_source_suffix(), whose whole job is to print
#   arbiter_pick=<...> arm_source=ladder_fallback depth=<n> after=<last>
# -- the only line explaining an arm that landed off the arbiter's pick.
#
# Measured mechanism (NOT the briefed one -- bash 3.2 survives every state):
#   state                          bash 3.2.57        bash 5.3.9 (PATH bash)
#   local -a attempted             survives (n=0)     CRASH "attempted: unbound variable"
#   attempted=()                   survives           survives
#   attempted=(x y)                works              works
# `#!/usr/bin/env bash` resolves to the PATH bash (5.x here), and
# leadv2-dispatch-code.sh declares `local -a candidate_arms attempted` -- the
# declared-NEVER-ASSIGNED state -- so the old `declare -p attempted` guard
# passed and ${#attempted[@]} killed the function under set -u before its
# printf. The fix proves element zero EXISTS (declare -p's own rendering names
# [0]=) before ANY array expansion, which is safe on every bash in every
# state. This suite pins that contract on /bin/bash (3.2, per the mission) AND
# on the PATH bash, and proves red-capability by reverting the guard on a
# throwaway copy: the reverted guard must crash the live state on bash >= 4.4
# (declared-unassigned + set -u). On a box whose PATH bash IS 3.2 the crash arm
# cannot run; the suite says so loudly instead of pretending it proved it.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
DISPATCH_BIN="${SCRIPTS_ROOT}/leadv2-dispatch-code.sh"

PASS=0; FAIL=0
pass() { printf 'PASS: %s\n' "$1"; PASS=$((PASS + 1)); }
fail() { printf 'FAIL: %s -- %s\n' "$1" "${2:-}"; FAIL=$((FAIL + 1)); }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/sfx-unbound.XXXXXX")"
trap '[[ "${SFXU_KEEP_LOGS:-0}" == "1" ]] || rm -rf "$TMP"' EXIT

bash -n "$DISPATCH_BIN" || { fail "bash syntax: dispatch"; exit 1; }
pass "bash syntax: dispatch"

# Extract the LIVE function from the REAL file: sed-range on the function
# header to its closing brace. A mutation-control run mutates the real file;
# this extraction then carries the mutation, which is what makes the control
# able to redden THIS suite.
sed -n '/^_route_arm_source_suffix()/,/^}/p' "$DISPATCH_BIN" > "$TMP/func.sh"
if grep -q 'arm_source=ladder_fallback' "$TMP/func.sh" && [[ $(wc -l < "$TMP/func.sh") -ge 8 ]]; then
  pass "extracted _route_arm_source_suffix from the live dispatch script"
else
  fail "function extraction failed -- anchor gone" "re-anchor the sed range, do not silence it"
  echo "---"; echo "PASS=$PASS FAIL=$FAIL"; exit 1
fi

BIN_BASH32="/bin/bash"
V32="$($BIN_BASH32 -c 'echo ${BASH_VERSINFO[0]}.${BASH_VERSINFO[1]}')"
if [[ "${V32}" != "3.2" ]]; then
  fail "/bin/bash is not 3.2 (got ${V32})" "this suite owes a bash-3.2 arm per the mission"
fi

PATH_BASH="$(command -v bash)"
BASHES="$BIN_BASH32"
[[ "${PATH_BASH}" != "${BIN_BASH32}" ]] && BASHES="$BASHES $PATH_BASH"

# run_case <bash> <state-setup> <want_n> <want_last>
run_case() {
  local B="$1" state="$2" want_n="$3" want_last="$4" tag="$5" out rc
  out="$($B -uc "source '$TMP/func.sh'; g() { $state; _route_arm_source_suffix glm glm2; }; g" 2>&1)"; rc=$?
  printf '%s\n' "$out" > "$TMP/case-${tag}.log"
  if [[ $rc -ne 0 ]]; then
    fail "($tag) ${B} died rc=$rc under set -u -- telemetry line lost" "$(printf '%s' "$out" | tail -1)"
    return
  fi
  if printf '%s' "$out" | grep -q " arbiter_pick=glm2 arm_source=ladder_fallback depth=${want_n} after=${want_last}\$"; then
    pass "($tag) ${B} prints the ladder_fallback line (depth=${want_n} after=${want_last})"
  else
    fail "($tag) ${B} output mismatch" "want depth=${want_n} after=${want_last}, got: $(printf '%s' "$out" | tail -1)"
  fi
}

tagid=0
for B in $BASHES; do
  tagid=$((tagid + 1))
  # the LIVE state at leadv2-dispatch-code.sh:8849 -- declared, never assigned
  run_case "$B" 'local -a candidate_arms attempted' 0 unexplained "s${tagid}-declared-unassigned"
  run_case "$B" 'attempted=()' 0 unexplained "s${tagid}-assigned-empty"
  run_case "$B" 'attempted=(glm codex)' 2 codex "s${tagid}-nonempty"
  run_case "$B" 'true' 0 unexplained "s${tagid}-unset"
done
[[ "${V32}" == "3.2" ]] && pass "bash 3.2 arm ran on /bin/bash ${V32}"

# Contract guards: no pick or landed==pick -> no output at all (early return)
out_er="$(PATH_BASH="$PATH_BASH"; for B in $BASHES; do $B -uc "source '$TMP/func.sh'; _route_arm_source_suffix glm glm; _route_arm_source_suffix glm \"\"; echo EARLY_OK"; done 2>&1)"
if printf '%s' "$out_er" | grep -q EARLY_OK && ! printf '%s' "$out_er" | grep -q 'arm_source=ladder_fallback'; then
  pass "early-return contract intact (no line when pick empty or pick==landed)"
else
  fail "early-return contract broken" "got: $(printf '%s' "$out_er" | tail -2)"
fi

# ── RED-capable: revert the guard to `declare -p attempted` (the exact
# mutation the lead re-runs on the real file via leadv2-mutation-control.sh)
# and prove the live state crashes it on a bash >= 4.4. ─────────────────────
cp "$TMP/func.sh" "$TMP/func-mutated.sh"
python3 - "$TMP/func-mutated.sh" <<'PY' || { fail "(red) mutation anchor not found in extracted function -- control not falsifiable" "zero-match"; }
import sys
path = sys.argv[1]
src = open(path).read()
anchor = """if _dp="$(declare -p attempted 2>/dev/null)" && [[ "${_dp}" == *'([0]='* ]]; then"""
repl = """if declare -p attempted >/dev/null 2>&1; then"""
n = src.count(anchor)
if n != 1:
    sys.exit('mutation anchor found %d times (expected exactly 1) in %s -- '
             'the non-empty guard lives in _route_arm_source_suffix '
             '(W1-ARBITER-BYPASSED-ON-DISPATCH-01 part B); re-anchor, do not silence.'
             % (n, path))
src = src.replace(anchor, repl)
# revert the second half of the old body: drop the provably-non-empty early
# assignment of last= so the mutated shape matches the pre-fix bytes
src = src.replace('    n=${#attempted[@]}\n    last="${attempted[n-1]}"',
                  '    n=${#attempted[@]}\n    (( n > 0 )) && last="${attempted[n-1]}"')
open(path, 'w').write(src)
PY
for B in $BASHES; do
  vmaj="$($B -c 'echo ${BASH_VERSINFO[0]}')"
  if [[ "${vmaj}" -lt 4 ]]; then
    printf 'NOTE: %s is %s.x -- the declared-unassigned crash arm needs bash >= 4.4; mutation red proven on the other bash\n' "$B" "$vmaj"
    continue
  fi
  out_mut="$($B -uc "source '$TMP/func-mutated.sh'; g() { local -a candidate_arms attempted; _route_arm_source_suffix glm glm2; }; g" 2>&1)"; rc_mut=$?
  printf '%s\n' "$out_mut" > "$TMP/mutated-$(basename "$B").log"
  if [[ $rc_mut -ne 0 ]] && printf '%s' "$out_mut" | grep -q 'attempted: unbound variable'; then
    pass "(red) reverted guard crashes the live declared-unassigned state on $B -- suite red under this mutation"
  else
    fail "(red) reverted guard did not reproduce the unbound-variable crash on $B" "rc=$rc_mut log: $TMP/mutated-$(basename "$B").log"
  fi
done

echo "---"
echo "PASS=$PASS FAIL=$FAIL"
[[ $FAIL -eq 0 ]]
