#!/usr/bin/env bash
# tests/test-drift-guard-by-copy-summary.sh —
# DRIFT-GUARD-ADVISES-BACKWARD-SYNC-01 scope (b), round 2.
#
# Negative control: fails if the per-copy SUMMARY-BY-COPY rollup / aggregate
# SUMMARY line ever regresses back to silence (computed-but-never-printed),
# and asserts the --verbose split actually demotes the safe CANONICAL_NEWER
# per-entry firehose while never eliding a VENDORED_NEWER entry, and that
# --json entries[]/by_copy stay complete and --verbose-independent (frozen
# consumer contract — leadv2-drift-only-vendored-check.py parses entries[]).
#
# Portable, sandboxed via LEADV2_CANONICAL_ROOT/LEADV2_HOME_ROOT — never
# touches the real 5 copies.
# Run: bash scripts/tests/test-drift-guard-by-copy-summary.sh

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
DRIFT_GUARD="${SCRIPTS_ROOT}/leadv2-drift-guard.sh"

FAIL=0
pass() { printf -- 'PASS: %s\n' "$*"; }
fail() { printf -- 'FAIL: %s\n' "$*" >&2; FAIL=1; }

TMPROOT="$(mktemp -d)"
trap 'rm -rf "${TMPROOT}"' EXIT

DG_CANON="${TMPROOT}/canon"
mkdir -p "${DG_CANON}/plugins/leadv2/scripts"
printf -- '#!/usr/bin/env bash\necho probe-a\n' > "${DG_CANON}/plugins/leadv2/scripts/probe-a.sh"
printf -- '#!/usr/bin/env bash\necho probe-b\n' > "${DG_CANON}/plugins/leadv2/scripts/probe-b.sh"

DG_HOME="${TMPROOT}/home"
mkdir -p "${DG_HOME}/.claude/plugins/cache/leadv2-local/leadv2/0.1.0/scripts"
mkdir -p "${DG_HOME}/.claude/leadv2-shared/scripts"
mkdir -p "${DG_CANON}/.claude/scripts"
# no cross-repo-paths.yaml under DG_HOME -> only the 3 fixed copies drift.

# leadv2-repo-vendored (a git-tracked path inside DG_CANON): make probe-a a
# CANONICAL_NEWER drift (edit only canonical, commit it, so canonical's
# git-log recency beats the untouched copy's mtime) and probe-b a
# VENDORED_NEWER drift (touch the copy after committing canonical, so the
# copy's mtime is newer).
git -C "${DG_CANON}" init -q
git -C "${DG_CANON}" config user.email "test@test.local"
git -C "${DG_CANON}" config user.name "test"
git -C "${DG_CANON}" add plugins/leadv2/scripts/probe-a.sh plugins/leadv2/scripts/probe-b.sh
git -C "${DG_CANON}" commit -q -m "seed probes"

cp "${DG_CANON}/plugins/leadv2/scripts/probe-a.sh" "${DG_CANON}/.claude/scripts/probe-a.sh"
cp "${DG_CANON}/plugins/leadv2/scripts/probe-b.sh" "${DG_CANON}/.claude/scripts/probe-b.sh"
cp "${DG_CANON}/plugins/leadv2/scripts/probe-a.sh" "${DG_HOME}/.claude/plugins/cache/leadv2-local/leadv2/0.1.0/scripts/probe-a.sh"
cp "${DG_CANON}/plugins/leadv2/scripts/probe-b.sh" "${DG_HOME}/.claude/plugins/cache/leadv2-local/leadv2/0.1.0/scripts/probe-b.sh"
cp "${DG_CANON}/plugins/leadv2/scripts/probe-a.sh" "${DG_HOME}/.claude/leadv2-shared/scripts/probe-a.sh"
cp "${DG_CANON}/plugins/leadv2/scripts/probe-b.sh" "${DG_HOME}/.claude/leadv2-shared/scripts/probe-b.sh"
# decide_direction() absorbs a 2s buffer for filesystem timestamp
# resolution/clock skew — sleep past it decisively so this test's direction
# assignments are never flaky on a slow/fast CI host.
sleep 3

# probe-a: edit + commit in canonical only -> canonical is newer (CANONICAL_NEWER).
printf -- '#!/usr/bin/env bash\necho probe-a-v2\n' > "${DG_CANON}/plugins/leadv2/scripts/probe-a.sh"
git -C "${DG_CANON}" add plugins/leadv2/scripts/probe-a.sh
git -C "${DG_CANON}" commit -q -m "update probe-a"
sleep 3
# probe-b: edit the leadv2-repo-vendored copy only, after canonical's last
# commit -> the copy's mtime is newer (VENDORED_NEWER).
printf -- '#!/usr/bin/env bash\necho probe-b-vendored-fix\n' > "${DG_CANON}/.claude/scripts/probe-b.sh"

DG_JSON="$(LEADV2_CANONICAL_ROOT="${DG_CANON}" LEADV2_HOME_ROOT="${DG_HOME}" \
  bash "${DRIFT_GUARD}" --quiet --json)"
DG_OUT_DEFAULT="$(LEADV2_CANONICAL_ROOT="${DG_CANON}" LEADV2_HOME_ROOT="${DG_HOME}" \
  bash "${DRIFT_GUARD}" 2>&1)"
DG_OUT_VERBOSE="$(LEADV2_CANONICAL_ROOT="${DG_CANON}" LEADV2_HOME_ROOT="${DG_HOME}" \
  bash "${DRIFT_GUARD}" --verbose 2>&1)"
DG_JSON_VERBOSE="$(LEADV2_CANONICAL_ROOT="${DG_CANON}" LEADV2_HOME_ROOT="${DG_HOME}" \
  bash "${DRIFT_GUARD}" --quiet --json --verbose)"

# ── 1. Negative control: the rollup must actually be printed, not just
#      computed. If SUMMARY-BY-COPY / SUMMARY regress to silence, this fails.
if printf -- '%s' "${DG_OUT_DEFAULT}" | grep -q "SUMMARY-BY-COPY: leadv2-repo-vendored:"; then
  pass "default output prints SUMMARY-BY-COPY per drifted copy (rollup not silently dropped)"
else
  fail "SUMMARY-BY-COPY line missing from default output — rollup regressed to silence"
fi
if printf -- '%s' "${DG_OUT_DEFAULT}" | grep -q "^\[drift-guard\] SUMMARY: "; then
  pass "default output prints the aggregate SUMMARY line"
else
  fail "aggregate SUMMARY line missing from default output"
fi

# ── 2. VENDORED_NEWER entries are never elided, default or verbose.
if printf -- '%s' "${DG_OUT_DEFAULT}" | grep -q "content differs for probe-b.sh \[VENDORED_NEWER\]"; then
  pass "default output shows the VENDORED_NEWER entry in full (never elided)"
else
  fail "VENDORED_NEWER entry for probe-b.sh missing from default output"
fi

# ── 3. CANONICAL_NEWER per-entry line is demoted behind --verbose by default.
if printf -- '%s' "${DG_OUT_DEFAULT}" | grep -q "content differs for probe-a.sh \[CANONICAL_NEWER\]"; then
  fail "default output still shows the CANONICAL_NEWER per-entry line — firehose not demoted"
else
  pass "default output demotes the CANONICAL_NEWER per-entry line behind --verbose"
fi
if printf -- '%s' "${DG_OUT_VERBOSE}" | grep -q "content differs for probe-a.sh \[CANONICAL_NEWER\]"; then
  pass "--verbose restores the CANONICAL_NEWER per-entry line"
else
  fail "--verbose should show the CANONICAL_NEWER per-entry line for probe-a.sh"
fi

# ── 4. by_copy JSON key is present and counts the entries correctly.
BYCOPY_VENDORED="$(printf -- '%s' "${DG_JSON}" | python3 -c "
import sys, json
d = json.load(sys.stdin)
bc = d.get('by_copy') or {}
print(bc.get('leadv2-repo-vendored', {}).get('vendored_newer', 'MISSING'))
")"
if [[ "${BYCOPY_VENDORED}" == "1" ]]; then
  pass "--json by_copy.leadv2-repo-vendored.vendored_newer == 1"
else
  fail "--json by_copy key missing/wrong (got vendored_newer=${BYCOPY_VENDORED}; by_copy may be absent entirely)"
fi

# ── 5. entries[]/by_copy are frozen: identical with and without --verbose.
if [[ "${DG_JSON}" == "${DG_JSON_VERBOSE}" ]]; then
  pass "--json output is identical with and without --verbose (frozen consumer contract)"
else
  fail "--json output changed under --verbose — entries[]/by_copy must stay --verbose-independent"
fi

echo "---"
if [[ ${FAIL} -eq 0 ]]; then
  echo "ALL TESTS PASSED"
  exit 0
else
  echo "TESTS FAILED"
  exit 1
fi
