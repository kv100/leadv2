#!/usr/bin/env bash
# tests/test-plan-run-acceptance-real.sh — design §5 tests 1-3.
#
# Asserts the REAL leadv2-acceptance-shape.sh validator (not the old heuristic
# _acceptance_guard) refuses malformed acceptance blocks. These are the same
# invariants the old plan.js tests asserted — now re-pointed at the engine's
# real validator surface.
#
# Cases:
#   1. empty observable → refused
#   2. observable with internal-contract phrasing ("the function returns 0") → refused
#   3. acceptance inside a fenced markdown block only → refused (top-level key missing)
#
# Run: bash plugins/leadv2/scripts/tests/test-plan-run-acceptance-real.sh
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SCRIPTS_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
ACCEPT="${SCRIPTS_ROOT}/leadv2-acceptance-shape.sh"

PASS=0; FAIL=0; ERRORS=()
log()  { printf -- '[TEST] %s\n' "$*"; }
pass() { PASS=$((PASS + 1)); log "PASS: $1"; }
fail() { FAIL=$((FAIL + 1)); ERRORS+=("$1"); log "FAIL: $1"; }

bash -n "$0" 2>/dev/null || { echo "ERROR: self syntax check failed"; exit 1; }

TMP="$(mktemp -d)"; trap 'rm -rf "${TMP}"' EXIT

# ---------------------------------------------------------------------------
# Case 1: empty observable → refused (acceptance_invalid)
# ---------------------------------------------------------------------------
log "Case 1: empty observable → refused"
cat > "${TMP}/ctx-bad1.yaml" <<'YAML'
id: dispatch-test0001
mission: |
  Bad mission with empty observable.
acceptance:
  surface: file_artifact
  observable: ""
  authored_at: 2026-08-12T00:00:00Z
YAML
if ! bash "${ACCEPT}" validate "${TMP}/ctx-bad1.yaml" >/dev/null 2>&1; then
  pass "empty observable refused by real validator"
else
  fail "empty observable NOT refused (should have been)"
fi

# ---------------------------------------------------------------------------
# Case 2: observable with internal-contract phrasing → refused
# ("the function returns 0" — banned phrase " returns ")
# ---------------------------------------------------------------------------
log "Case 2: internal-contract phrasing → refused"
cat > "${TMP}/ctx-bad2.yaml" <<'YAML'
id: dispatch-test0002
mission: |
  Bad mission with internal-contract phrasing.
acceptance:
  surface: file_artifact
  observable: >
    The function returns 0 and the variable is set to true.
  authored_at: 2026-08-12T00:00:00Z
YAML
if ! bash "${ACCEPT}" validate "${TMP}/ctx-bad2.yaml" >/dev/null 2>&1; then
  pass "internal-contract observable refused"
else
  fail "internal-contract observable NOT refused"
fi

# ---------------------------------------------------------------------------
# Case 3: acceptance only inside a fenced markdown block → refused
# (top-level acceptance: key is absent from YAML parsing)
# ---------------------------------------------------------------------------
log "Case 3: acceptance inside fenced block only → refused"
cat > "${TMP}/ctx-bad3.yaml" <<'YAML'
id: dispatch-test0003
mission: |
  Mission with acceptance hidden in a code block.
```
acceptance:
  surface: file_artifact
  observable: A reader sees the output file.
  authored_at: 2026-08-12T00:00:00Z
```
YAML
if ! bash "${ACCEPT}" validate "${TMP}/ctx-bad3.yaml" >/dev/null 2>&1; then
  pass "fenced-only acceptance refused"
else
  fail "fenced-only acceptance NOT refused"
fi

# ---------------------------------------------------------------------------
# Positive control: a well-formed acceptance block must pass.
# ---------------------------------------------------------------------------
log "Positive control: well-formed acceptance passes"
cat > "${TMP}/ctx-good.yaml" <<'YAML'
id: dispatch-test-good
mission: |
  A valid mission.
acceptance:
  surface: file_artifact
  observable: >
    A reader opening the file sees a valid YAML document with non-empty fields
    describing the deliverable.
  authored_at: 2026-08-12T00:00:00Z
decisions:
  - Use engine-owned skeleton
off_limits:
  - leadv2-review-run.sh
plan:
  steps:
    - Step one
writes: [plugins/leadv2/scripts/leadv2-plan-run.sh]
lane_writes: plugins/leadv2/scripts/leadv2-plan-run.sh
reads: []
YAML
if bash "${ACCEPT}" validate "${TMP}/ctx-good.yaml" >/dev/null 2>&1; then
  pass "well-formed acceptance passes real validator"
else
  fail "well-formed acceptance UNEXPECTEDLY refused"
fi

# ---------------------------------------------------------------------------
printf -- '\n'
for e in "${ERRORS[@]}"; do printf -- '  FAIL: %s\n' "${e}"; done
printf -- 'Results: %d pass, %d fail\n' "${PASS}" "${FAIL}"
[[ "${FAIL}" == "0" ]] || exit 1
exit 0
