#!/usr/bin/env bash
# test-e2e-gate-ignores-pre-existing-red.sh
# HARNESS-COSTS-MORE-THAN-IT-CATCHES-01 / GATE-CHARGES-A-LANE-FOR-A-RED-IT-DID-NOT-CAUSE
#
# Subject: the REAL leadv2-e2e-ownership.sh. Nothing in it is stubbed. What is
# faked is one level lower: a throwaway git repo standing in for a lane's
# checkout, and two-line shell scripts standing in for suites.
#
# The claim under test is a subtraction: a suite that was ALREADY red at the
# lane's own merge-base must leave `own` and land in `pre_existing`, so the
# gate stops charging a lane for a red it did not cause -- while a suite the
# lane genuinely broke must still land in `own` and still kill the lane.
#
# DECLARED NEGATIVE CONTROLS (apply INSIDE the baseline loop body of
# leadv2-e2e-ownership.sh; each must turn this suite RED):
#   M1  still_own+=("${suite}")   -> pre_existing+=("${suite}")   in the
#       "green before the lane" branch          => case (b) fails
#   M2  still_own+=("${suite}")   -> pre_existing+=("${suite}")   in the
#       "suite absent at merge-base" branch     => case (e) fails
#   M3  still_own+=("${suite}")   -> pre_existing+=("${suite}")   in the
#       "budget spent" branch                   => case (f) fails
#   M4  pre_existing+=("${suite}") -> still_own+=("${suite}")     in the
#       "red before the lane" branch            => case (a) fails
# Cases (c) and (d) survive M1/M2/M3/M4 by construction: they never reach the
# per-suite baseline re-run at all.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OWNERSHIP="${LEADV2_OWNERSHIP_SH:-${SCRIPT_DIR}/../leadv2-e2e-ownership.sh}"
[[ -f "${OWNERSHIP}" ]] || { echo "FATAL: ownership script not found: ${OWNERSHIP}" >&2; exit 2; }

PASS=0; FAIL=0
ok()   { PASS=$((PASS+1)); echo "  ok   — $1"; }
bad()  { FAIL=$((FAIL+1)); echo "  FAIL — $1"; }
check() { # <label> <expected> <actual>
  if [[ "$2" == "$3" ]]; then ok "$1"; else bad "$1 (expected='$2' actual='$3')"; fi
}

WORK="$(mktemp -d "${TMPDIR:-/tmp}/e2e-preexisting.XXXXXX")" || exit 2
trap 'rm -rf "${WORK}"' EXIT

# ── fixture ────────────────────────────────────────────────────────────────
# main:  prod.sh VALUE=ok · test-solid (green iff VALUE=ok) · test-flaky (always red)
# lane:  commits a NEW always-red suite; working tree breaks prod.sh (its only
#        declared write), which is what turns test-solid red.
mk_repo() { # <dir> <initial_branch>
  local d="$1" br="$2"
  mkdir -p "${d}/tests/unit" || return 1
  git init -q -b "${br}" "${d}" >/dev/null 2>&1 || return 1
  git -C "${d}" config user.email t@t.local; git -C "${d}" config user.name t
  printf 'VALUE=ok\n' > "${d}/prod.sh"
  printf '#!/usr/bin/env bash\n. "$(dirname "$0")/../../prod.sh"\n[[ "${VALUE:-}" == "ok" ]]\n' \
    > "${d}/tests/unit/test-solid.sh"
  printf '#!/usr/bin/env bash\nexit 1\n' > "${d}/tests/unit/test-flaky.sh"
  chmod +x "${d}"/tests/unit/*.sh
  git -C "${d}" add prod.sh tests/unit/test-solid.sh tests/unit/test-flaky.sh >/dev/null 2>&1
  git -C "${d}" commit -qm "base" >/dev/null 2>&1 || return 1
}

mk_log() { # <path> <suite>...
  local p="$1"; shift
  { echo "  Failures (blocking):"; for s in "$@"; do echo "    - ${s}"; done; } > "${p}"
}

run_own() { # <root> <log> -> stdout of the real ownership script
  bash "${OWNERSHIP}" "$1" "lane0000" "prod.sh" "$2" 2>/dev/null
}
field() { sed -n "s/^$2=//p" <<< "$1"; }

# ── fixture A: a lane branched off main ────────────────────────────────────
A="${WORK}/a"
mk_repo "${A}" main || { echo "FATAL: fixture A"; exit 2; }
git -C "${A}" checkout -q -b lane
printf '#!/usr/bin/env bash\nexit 1\n' > "${A}/tests/unit/test-lane-new.sh"
chmod +x "${A}/tests/unit/test-lane-new.sh"
git -C "${A}" add tests/unit/test-lane-new.sh >/dev/null 2>&1
git -C "${A}" commit -qm "lane adds a suite" >/dev/null 2>&1
printf 'VALUE=broken\n' > "${A}/prod.sh"     # the lane's declared write, uncommitted
LOG_A="${WORK}/a.log"
mk_log "${LOG_A}" tests/unit/test-flaky.sh tests/unit/test-solid.sh tests/unit/test-lane-new.sh

echo "== A: lane off main, three blocking reds"
OUT="$(run_own "${A}" "${LOG_A}")"
OWN="$(field "${OUT}" own)"; PRE="$(field "${OUT}" pre_existing)"; FOR="$(field "${OUT}" foreign)"

# (a) red before the lane existed -> pre_existing, and OUT of own
check "(a) already-red suite is named pre_existing" "tests/unit/test-flaky.sh" "${PRE}"

# (b) NEGATIVE CONTROL. The lane really did break test-solid: it must still be
#     own, and the lane must still die. A change that merely stops failing
#     lanes would show up right here.
case ",${OWN}," in
  *,tests/unit/test-solid.sh,*) ok "(b) NEG-CTL: suite the lane genuinely broke stays own" ;;
  *) bad "(b) NEG-CTL: lane-caused red vanished from own (own='${OWN}')" ;;
esac

# (e) a suite the lane ADDED cannot have been red before it existed -> own
case ",${OWN}," in
  *,tests/unit/test-lane-new.sh,*) ok "(e) suite absent at merge-base stays own" ;;
  *) bad "(e) lane-added suite was laundered as pre-existing (own='${OWN}')" ;;
esac
check "(a2) nothing was misfiled as foreign" "" "${FOR}"

# ── fixture B: no resolvable merge-base at all ─────────────────────────────
B="${WORK}/b"
mk_repo "${B}" lane || { echo "FATAL: fixture B"; exit 2; }
printf 'VALUE=broken\n' > "${B}/prod.sh"
LOG_B="${WORK}/b.log"
mk_log "${LOG_B}" tests/unit/test-flaky.sh tests/unit/test-solid.sh

echo "== B/C/D: fail-closed paths"
OUT_B="$(run_own "${B}" "${LOG_B}")"
check "(c) no merge-base -> pre_existing empty (fail closed)" "" "$(field "${OUT_B}" pre_existing)"
case ",$(field "${OUT_B}" own)," in
  *,tests/unit/test-flaky.sh,*) ok "(c) no merge-base -> the red still kills" ;;
  *) bad "(c) unresolvable baseline let a red through" ;;
esac

# (d) kill switch: LEADV2_E2E_BASELINE=0 restores the pre-fix behaviour
OUT_D="$(LEADV2_E2E_BASELINE=0 run_own "${A}" "${LOG_A}")"
check "(d) LEADV2_E2E_BASELINE=0 -> subtraction off" "" "$(field "${OUT_D}" pre_existing)"

# (f) a spent time budget is not a licence to launder reds
OUT_F="$(LEADV2_E2E_BASELINE_BUDGET_S=0 run_own "${A}" "${LOG_A}")"
check "(f) budget spent -> pre_existing empty (fail closed)" "" "$(field "${OUT_F}" pre_existing)"

echo
echo "passed=${PASS} failed=${FAIL}"
[[ ${FAIL} -eq 0 ]]
