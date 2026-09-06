#!/usr/bin/env bash
# changed-scope triggers, self-registered (discovered by scan_suite_triggers):
# run-all-triggers: leadv2-review-run.sh
# (BASENAMES only — a token containing "/" is FATAL for the whole run.)
#
# tests/test-review-gate-terminal-fallback.sh — REVIEW-GATE-SILENCE-READS-AS-PASS-01.
#
# leadv2-review-run.sh writes review-gate.md inline at each of its twelve decision
# points. An engine that died BETWEEN those points — an unset-variable exit under
# `set -u` in the parent scope, a TERM from the lane watcher, an early `wait` path —
# left no gate artifact and no review_gate line at all, and a missing gate reads
# downstream as "nothing blocked it". The defect is silence in the PERMISSIVE
# direction: an unreviewed lane looked reviewed. Measured 2026-09-06 before the fix:
# `git grep -E 'gate_engine_aborted|trap .*EXIT' main -- plugins/leadv2` was empty.
#
# What is REAL and what is faked (E2E-KILLRATE-01 rule 1): the production code under
# claim — `_review_gate_terminal_fallback` AND the trap lines that arm it — is LIFTED
# BYTE-EXACT out of the shipped leadv2-review-run.sh at run time and executed in a
# real bash process that is really killed by a real signal. Nothing here restates the
# rule. Faked one level lower only: the journal sink (`emit`) and the engine body
# around the traps.
#
# DECLARED MUTATIONS — a pair, one per direction, and BOTH were run (2026-09-06).
# Each is applied INSIDE the body of _review_gate_terminal_fallback, never at top
# level: a top-level insert reddens every suite for the wrong reason and reads as a
# pass. The anchor line is confirmed unique with `grep -cF` before either is trusted.
#
#   A. "never write" — invert the guard to `if [[ -f "${HANDOFF}/review-gate.md" ]]`.
#      Measured: 15/0 -> 7/8. Kills (a)(b)(c)(d)(e)(f)(f2)(g). Stays green: the four
#      exit-code cases (a2)(b2)(c2)(d2) plus (h)(i)(j) — so the suite is not merely
#      "everything red".
#   B. "write always" — replace the same guard with `if true; then`.
#      Measured: 15/0 -> 13/2. Kills exactly (f)(f2) and NOTHING else.
#
# B is the half that matters most: without it a fallback that clobbers a real PASS
# decision would sail through, because every death-mode case would still be green.
# An earlier draft of this header claimed (f) survives A. It does not — under A the
# inverted guard writes only when a gate already exists, so (f) fails too. The claim
# was corrected against the measurement rather than the measurement against the claim.
set -uo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_DIR="$(cd "${TESTS_DIR}/.." && pwd)"
RR_FILE="${SCRIPTS_DIR}/leadv2-review-run.sh"

PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); printf -- '[TEST] PASS %s\n' "$*"; }
bad() { FAIL=$((FAIL+1)); printf -- '[TEST] FAIL %s\n' "$*"; }

WORK="$(mktemp -d "${TMPDIR:-/tmp}/lv2-rgtf.XXXXXX")"
cleanup() { rm -rf "${WORK}"; }
trap cleanup EXIT

[[ -f "${RR_FILE}" ]] || { printf 'no review-run script at %s\n' "${RR_FILE}" >&2; exit 2; }

# ── lift the production block out of the shipped file ─────────────────────────
# Byte-exact slice: the function plus the four trap lines that arm it. Arming is
# part of what is under claim — a fallback that exists and is never installed is
# the same silence with extra code — so the extraction takes both or fails loudly.
LIFTED="${WORK}/lifted.sh"
python3 - "${RR_FILE}" "${LIFTED}" <<'PY' || { printf 'extraction failed\n' >&2; exit 2; }
import io, sys
src = io.open(sys.argv[1], encoding="utf-8").read()
i = src.index("_review_gate_terminal_fallback() {")
end = "trap 'exit 129' HUP\n"
j = src.index(end, i) + len(end)
io.open(sys.argv[2], "w", encoding="utf-8").write(src[i:j])
PY

grep -q 'gate_engine_aborted' "${LIFTED}" || { printf 'lifted block carries no gate_engine_aborted\n' >&2; exit 2; }
grep -q "trap '_REVIEW_GATE_ST=\$?" "${LIFTED}" || { printf 'lifted block installs no EXIT trap\n' >&2; exit 2; }

# ── a real child process that arms the real traps and then really dies ────────
# $1 = case dir, $2 = shell fragment that ends the child.
run_child() { # <dir> <death-fragment>
  local d="$1" death="$2"
  mkdir -p "${d}/handoff"
  {
    printf 'set -uo pipefail\n'
    printf 'HANDOFF="%s/handoff"\n' "${d}"
    printf 'TASK="rgtf"\n'
    printf 'emit() { printf "%%s %%s\\n" "${1:-}" "${2:-}" >> "%s/emitted.log"; }\n' "${d}"
    printf 'source "%s"\n' "${LIFTED}"
    printf '%s\n' "${death}"
  } > "${d}/child.sh"
  bash "${d}/child.sh" >/dev/null 2>&1
  printf '%s' "$?"
}

gate_of() { cat "$1/handoff/review-gate.md" 2>/dev/null; }

# (a) TERM — the lane watcher's kill. An EXIT trap alone never runs on an
#     untrapped signal, so the signal traps are load-bearing, not decoration.
D="${WORK}/a"; RC="$(run_child "${D}" 'kill -TERM $$; sleep 5')"
G="$(gate_of "${D}")"
case "${G}" in
  *"reason: gate_engine_aborted"*) ok "(a) TERM leaves a blocked gate" ;;
  *) bad "(a) TERM left no gate_engine_aborted gate (got: ${G:-<nothing>})" ;;
esac
[[ "${RC}" == "143" ]] && ok "(a2) TERM preserves the conventional exit code 143" \
  || bad "(a2) expected rc 143, got ${RC}"

# (b) INT
D="${WORK}/b"; RC="$(run_child "${D}" 'kill -INT $$; sleep 5')"
case "$(gate_of "${D}")" in
  *"reason: gate_engine_aborted"*) ok "(b) INT leaves a blocked gate" ;;
  *) bad "(b) INT left no gate" ;;
esac
[[ "${RC}" == "130" ]] && ok "(b2) INT preserves exit code 130" || bad "(b2) expected 130, got ${RC}"

# (c) HUP
D="${WORK}/c"; RC="$(run_child "${D}" 'kill -HUP $$; sleep 5')"
case "$(gate_of "${D}")" in
  *"reason: gate_engine_aborted"*) ok "(c) HUP leaves a blocked gate" ;;
  *) bad "(c) HUP left no gate" ;;
esac
[[ "${RC}" == "129" ]] && ok "(c2) HUP preserves exit code 129" || bad "(c2) expected 129, got ${RC}"

# (d) the NON-signal death: an unset variable under `set -u` in the parent scope.
#     This is the shape the original incident had — no signal, no crash message,
#     just an engine that stopped between two decision points.
D="${WORK}/d"; RC="$(run_child "${D}" 'printf "%s" "${DEFINITELY_UNSET_VAR}"')"
case "$(gate_of "${D}")" in
  *"reason: gate_engine_aborted"*) ok "(d) a set -u abort leaves a blocked gate" ;;
  *) bad "(d) set -u abort left no gate — the original incident shape" ;;
esac
[[ "${RC}" == "1" ]] && ok "(d2) the trap does not change the abort's exit code" \
  || bad "(d2) expected rc 1, got ${RC}"

# (e) the gate names the status that actually killed the engine, not a constant.
grep -q '^rc: 143$' "${WORK}/a/handoff/review-gate.md" 2>/dev/null \
  && ok "(e) the gate carries the real terminating status" \
  || bad "(e) gate does not carry rc: 143"

# (f) CONTROL — fallback-only. A decision the engine already persisted is never
#     overwritten. This is the case that must stay GREEN under the declared
#     mutation; without it, a fallback that writes unconditionally would pass.
D="${WORK}/f"; mkdir -p "${D}/handoff"
printf 'status: pass\nreviewer: codex\n' > "${D}/handoff/review-gate.md"
RC="$(run_child "${D}" 'kill -TERM $$; sleep 5')"
if [[ "$(gate_of "${D}")" == "status: pass"* ]]; then
  ok "(f) CONTROL: an already-persisted decision is not overwritten"
else
  bad "(f) CONTROL: the fallback clobbered a real decision"
fi
[[ -s "${D}/emitted.log" ]] && bad "(f2) fallback emitted a decision over an existing gate" \
  || ok "(f2) no decision line emitted when a gate already exists"

# (g) arm subshells must never fire it. bash 3.2 resets caught traps in ( ),
#     $( ) and background subshells — verified here rather than assumed, because
#     if it were false every arm would write a blocked gate over a live review.
D="${WORK}/g"; RC="$(run_child "${D}" '( exit 3 ); x=$( exit 4 ); ( exit 5 ) & wait; exit 0')"
N="$(grep -c . "${D}/emitted.log" 2>/dev/null || printf 0)"
[[ "${N}" == "1" ]] && ok "(g) subshell exits do not fire the trap (fired once, in the parent)" \
  || bad "(g) trap fired ${N} times — subshells are firing it"

# (h) HANDOFF absent -> silent no-op, never a crash and never a stray write.
D="${WORK}/h"; mkdir -p "${D}"
{
  printf 'set -uo pipefail\nHANDOFF="%s/nonexistent"\nTASK="rgtf"\n' "${D}"
  printf 'emit() { :; }\nsource "%s"\nexit 0\n' "${LIFTED}"
} > "${D}/child.sh"
bash "${D}/child.sh" >/dev/null 2>&1; RC=$?
[[ "${RC}" == "0" && ! -e "${D}/nonexistent" ]] \
  && ok "(h) an absent HANDOFF is a no-op, not a crash" \
  || bad "(h) absent HANDOFF: rc=${RC}, stray dir=$([[ -e "${D}/nonexistent" ]] && echo yes || echo no)"

# (i) ANTI-ROT — the shipped file must arm the trap at TOP LEVEL. A fallback
#     defined inside a function, or defined and never armed, is the same silence.
if grep -qE "^trap '_REVIEW_GATE_ST=\\\$\?" "${RR_FILE}"; then
  ok "(i) the shipped engine arms the EXIT trap at top level"
else
  bad "(i) the shipped engine does not arm the EXIT trap at top level"
fi

# (j) ANTI-ROT — REVIEW-ARM-FAILCLOSED-02 is a DIFFERENT half (per-arm rc
#     classification) and must survive this change untouched.
grep -q 'REVIEW-ARM-FAILCLOSED-02' "${RR_FILE}" \
  && ok "(j) FAILCLOSED-02 still present — the other half was not disturbed" \
  || bad "(j) FAILCLOSED-02 markers are gone from the engine"

printf -- '[TEST] %s passed, %s failed\n' "${PASS}" "${FAIL}"
[[ "${FAIL}" -eq 0 ]]
