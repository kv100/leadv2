#!/usr/bin/env bash
# tests/test-drift-guard-direction.sh — DRIFT-GUARD-ADVISES-BACKWARD-SYNC-01
# scope (a)/(b)/(d) coverage: the direction machinery in leadv2-drift-guard.sh
# (decide_direction + REMEDY + SUMMARY-BY-COPY/by_copy aggregation) previously
# had ZERO test coverage — tests/test-drift-guard-safety-fixes.sh only covers
# MISSING_DIR handling and the vendored-only classifier. The DoD behavior ("on
# a repo whose vendored copy is ahead, drift-guard names it as ahead") was
# enforced only by code-reading.
#
# Covers:
#   1. VENDORED_NEWER   — copy mtime > canonical evidence + 2s → direction tag
#                         + "promote vendored -> canonical" remedy (scope a/d).
#   2. CANONICAL_NEWER  — copy mtime older → tag + "sync from canonical" remedy.
#   3. UNKNOWN          — mtimes within the 2s noise buffer → tag + "diff
#                         manually" remedy.
#   4. SUMMARY-BY-COPY  — two drifted files in one copy + one in another →
#                         exactly one group line per drifted copy with correct
#                         per-direction counts (scope b).
#   5. --json           — by_copy object carries the same counts; entries[]
#                         strings still end with the direction suffix (shape
#                         frozen for leadv2-drift-only-vendored-check.py).
#   6. MISSING file     — entry suffixed :MISSING:CANONICAL_NEWER.
#   7. git-evidence     — canonical is a real git repo: commit-time evidence
#                         wins over filesystem mtimes (both directions probed
#                         with mtimes that would make the mtime-fallback say
#                         UNKNOWN, so a pass proves the git branch decided).
#
# Determinism: every fixture mtime is set explicitly via `touch -t` — never
# write-order, never sleep — so nothing races the 2s direction buffer.
#
# Portable: no GNU-only date/sed -i/timeout/flock. Everything runs under a
# mktemp sandbox via the LEADV2_CANONICAL_ROOT / LEADV2_HOME_ROOT test hooks;
# nothing under ~/Projects/leadv2, ~/.claude, or any real vendored repo is
# ever read or written.
# Run: bash scripts/tests/test-drift-guard-direction.sh
# Exit 0 = all pass; non-zero = failures found.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
DRIFT_GUARD="${SCRIPTS_ROOT}/leadv2-drift-guard.sh"

FAIL=0
pass() { printf -- 'PASS: %s\n' "$*"; }
fail() { printf -- 'FAIL: %s\n' "$*" >&2; FAIL=1; }

check() { # check <haystack> <needle> <label>
  local got="$1" needle="$2" label="$3"
  if [[ "${got}" == *"${needle}"* ]]; then
    pass "${label}"
  else
    fail "${label} — wanted substring '${needle}', got: ${got}"
  fi
}

TMPROOT="$(mktemp -d)"
# Codex review finding 4: a failed mktemp must abort, never leave TMPROOT empty
# (fixture paths would collapse to /dir1/... outside the sandbox).
if [[ -z "${TMPROOT}" || ! -d "${TMPROOT}" ]]; then
  printf -- 'FAIL: mktemp -d did not produce a sandbox dir\n' >&2
  exit 1
fi
trap 'rm -rf "${TMPROOT}"' EXIT

# Fixture builder: canonical tree with 3 probe scripts + the 3 fixed copies
# (leadv2-repo-vendored under the canonical root, plugin-cache + leadv2-shared
# under the sandboxed HOME root), all byte-identical to canonical. Each case
# mutates its own copy of this base; no cross-case state.
VENDORED=""
CACHE=""
SHARED=""
make_fixture() { # make_fixture <name>
  local base="${TMPROOT}/$1"
  VENDORED_CANON="${base}/canon"
  DG_HOME="${base}/home"
  VENDORED="${VENDORED_CANON}/.claude/scripts"
  CACHE="${DG_HOME}/.claude/plugins/cache/leadv2-local/leadv2/0.1.0/scripts"
  SHARED="${DG_HOME}/.claude/leadv2-shared/scripts"
  mkdir -p "${VENDORED_CANON}/plugins/leadv2/scripts" "${VENDORED}" "${CACHE}" "${SHARED}"
  local f
  for f in probe-a.sh probe-b.sh probe-c.sh; do
    printf -- '#!/usr/bin/env bash\necho %s\n' "${f}" > "${VENDORED_CANON}/plugins/leadv2/scripts/${f}"
    cp "${VENDORED_CANON}/plugins/leadv2/scripts/${f}" "${VENDORED}/${f}"
    cp "${VENDORED_CANON}/plugins/leadv2/scripts/${f}" "${CACHE}/${f}"
    cp "${VENDORED_CANON}/plugins/leadv2/scripts/${f}" "${SHARED}/${f}"
  done
  # No cross-repo-paths.yaml under DG_HOME -> per-repo vendored copies skipped
  # (WARN only) — same as test-drift-guard-safety-fixes.sh §2.
}

# Human-readable run (DRIFT/SUMMARY lines are log() -> stderr); merge so one
# capture holds everything. Codex review finding 3: the guard's EXIT STATUS is
# asserted too (drift => 1, clean => 0) — never masked with `|| true`, so a
# regression that prints the right text but exits 0 cannot pass vacuously.
GUARD_OUT=""
GUARD_RC=0
run_guard() { # run_guard <fixture-name> [extra args...] -> GUARD_OUT / GUARD_RC
  local fixture="$1"; shift
  GUARD_OUT="$(LEADV2_CANONICAL_ROOT="${TMPROOT}/${fixture}/canon" \
    LEADV2_HOME_ROOT="${TMPROOT}/${fixture}/home" \
    bash "${DRIFT_GUARD}" "$@" 2>&1)"
  GUARD_RC=$?
}

expect_rc() { # expect_rc <wanted> <label>
  if [[ "${GUARD_RC}" -eq "$1" ]]; then
    pass "$2 (guard exit=${GUARD_RC})"
  else
    fail "$2 — wanted guard exit $1, got ${GUARD_RC}: ${GUARD_OUT}"
  fi
}

# ─────────────────────────────────────────────────────────────────────────
# 0. baseline: untouched fixture -> exit 0, OK line (exit-status half of the
#    contract; without this, direction cases could pass on text alone)
# ─────────────────────────────────────────────────────────────────────────
make_fixture dir0
run_guard dir0
expect_rc 0 "0: identical copies -> guard exits 0"
check "${GUARD_OUT}" "OK: all 3 copies match canonical" "0: identical copies -> OK summary line"

# ─────────────────────────────────────────────────────────────────────────
# 1-3. direction tags + per-entry remedies (non-git canonical -> mtime
#      evidence fallback, code path leadv2-drift-guard.sh:217-219)
# ─────────────────────────────────────────────────────────────────────────
make_fixture dir1
# canonical evidence = canonical file mtime (no git repo): 2024-01-01
touch -t 202401010000 "${TMPROOT}/dir1/canon/plugins/leadv2/scripts/"probe-*.sh

# 1. vendored copy newer by a year -> VENDORED_NEWER + promote remedy
printf -- '#!/usr/bin/env bash\necho hellO\n' > "${TMPROOT}/dir1/canon/.claude/scripts/probe-a.sh"
touch -t 202501010000 "${TMPROOT}/dir1/canon/.claude/scripts/probe-a.sh"
run_guard dir1
expect_rc 1 "1: drift detected -> guard exits 1"
OUT1="${GUARD_OUT}"
check "${OUT1}" "content differs for probe-a.sh [VENDORED_NEWER]" "1: vendored-newer entry carries [VENDORED_NEWER] tag"
check "${OUT1}" "promote vendored -> canonical (this copy is newer; copy it INTO ~/Projects/leadv2, do not overwrite it)" "1: vendored-newer entry carries the promote remedy"

# 2. canonical newer (copy mtime 2 years older) -> CANONICAL_NEWER + sync remedy
printf -- '#!/usr/bin/env bash\necho hell0\n' > "${TMPROOT}/dir1/canon/.claude/scripts/probe-b.sh"
touch -t 202201010000 "${TMPROOT}/dir1/canon/.claude/scripts/probe-b.sh"
run_guard dir1
OUT2="${GUARD_OUT}"
check "${OUT2}" "content differs for probe-b.sh [CANONICAL_NEWER]" "2: canonical-newer entry carries [CANONICAL_NEWER] tag"
check "${OUT2}" "sync from canonical (canonical is newer; leadv2-plugin-sync.sh is safe here)" "2: canonical-newer entry carries the sync-from-canonical remedy"

# 3. mtimes equal (inside the 2s buffer) -> UNKNOWN + diff-manually remedy
printf -- '#!/usr/bin/env bash\necho noproblem\n' > "${TMPROOT}/dir1/canon/.claude/scripts/probe-c.sh"
touch -t 202401010000 "${TMPROOT}/dir1/canon/.claude/scripts/probe-c.sh"
run_guard dir1
OUT3="${GUARD_OUT}"
check "${OUT3}" "content differs for probe-c.sh [UNKNOWN]" "3: equal-mtime entry carries [UNKNOWN] tag"
check "${OUT3}" "inconclusive evidence — diff manually before syncing either direction" "3: unknown entry carries the diff-manually remedy"

# ─────────────────────────────────────────────────────────────────────────
# 4. per-copy grouping (scope b): 2 drifted files in leadv2-shared, 1 in
#    leadv2-repo-vendored -> one SUMMARY-BY-COPY line per drifted copy
# ─────────────────────────────────────────────────────────────────────────
make_fixture dir4
touch -t 202401010000 "${TMPROOT}/dir4/canon/plugins/leadv2/scripts/"probe-*.sh
printf -- '#!/usr/bin/env bash\necho shared1\n' > "${TMPROOT}/dir4/home/.claude/leadv2-shared/scripts/probe-a.sh"
printf -- '#!/usr/bin/env bash\necho shared2\n' > "${TMPROOT}/dir4/home/.claude/leadv2-shared/scripts/probe-b.sh"
touch -t 202501010000 "${TMPROOT}/dir4/home/.claude/leadv2-shared/scripts/probe-a.sh" "${TMPROOT}/dir4/home/.claude/leadv2-shared/scripts/probe-b.sh"
printf -- '#!/usr/bin/env bash\necho old-vendored\n' > "${TMPROOT}/dir4/canon/.claude/scripts/probe-a.sh"
touch -t 202201010000 "${TMPROOT}/dir4/canon/.claude/scripts/probe-a.sh"
run_guard dir4
OUT4="${GUARD_OUT}"
expect_rc 1 "4: drifted fixture -> guard exits 1"
check "${OUT4}" "SUMMARY-BY-COPY: leadv2-shared: 2 entries (VENDORED_NEWER=2 CANONICAL_NEWER=0 UNKNOWN=0 MISSING=0)" "4: leadv2-shared group line counts 2 VENDORED_NEWER entries"
check "${OUT4}" "SUMMARY-BY-COPY: leadv2-repo-vendored: 1 entry (VENDORED_NEWER=0 CANONICAL_NEWER=1 UNKNOWN=0 MISSING=0)" "4: leadv2-repo-vendored group line counts 1 CANONICAL_NEWER entry"
N_GROUP_LINES="$(printf -- '%s\n' "${OUT4}" | grep -c 'SUMMARY-BY-COPY: ' || true)"
if [[ "${N_GROUP_LINES}" -eq 2 ]]; then
  pass "4: exactly one SUMMARY-BY-COPY line per drifted copy (plugin-cache not drifted -> no line)"
else
  fail "4: expected exactly 2 SUMMARY-BY-COPY lines, got ${N_GROUP_LINES}: ${OUT4}"
fi
# scope (d): the summary must refuse the old blanket advice
check "${OUT4}" "Do NOT blanket re-run leadv2-plugin-sync.sh" "4: SUMMARY line forbids the blanket plugin-sync advice"

# ─────────────────────────────────────────────────────────────────────────
# 5. --json mirror: by_copy counts + frozen entries[] suffix shape
# ─────────────────────────────────────────────────────────────────────────
run_guard dir4 --quiet --json
JSON5="${GUARD_OUT}"
expect_rc 1 "5: --json drift run exits 1"
PY5="$(printf -- '%s' "${JSON5}" | python3 -c '
import json, sys
d = json.load(sys.stdin)
bc = d.get("by_copy") or {}
shared = bc.get("leadv2-shared")
vend = bc.get("leadv2-repo-vendored")
ok = (
    shared == {"total": 2, "vendored_newer": 2, "canonical_newer": 0, "unknown": 0, "missing": 0}
    and vend == {"total": 1, "vendored_newer": 0, "canonical_newer": 1, "unknown": 0, "missing": 0}
    and isinstance(d.get("entries"), list)
    and "leadv2-shared:probe-a.sh:CONTENT_DIFFERS:VENDORED_NEWER" in d["entries"]
    and "leadv2-shared:probe-b.sh:CONTENT_DIFFERS:VENDORED_NEWER" in d["entries"]
    and "leadv2-repo-vendored:probe-a.sh:CONTENT_DIFFERS:CANONICAL_NEWER" in d["entries"]
)
print("OK" if ok else "BAD: " + json.dumps(d))
')"
if [[ "${PY5}" == "OK" ]]; then
  pass "5: --json by_copy counts match SUMMARY-BY-COPY and entries[] keep the direction-suffix shape"
else
  fail "5: --json shape/counts wrong: ${PY5}"
fi

# ─────────────────────────────────────────────────────────────────────────
# 6. file missing from a copy -> :MISSING:CANONICAL_NEWER (unambiguous)
# ─────────────────────────────────────────────────────────────────────────
make_fixture dir6
rm "${TMPROOT}/dir6/home/.claude/plugins/cache/leadv2-local/leadv2/0.1.0/scripts/probe-a.sh"
run_guard dir6
OUT6="${GUARD_OUT}"
expect_rc 1 "6: missing file in copy -> guard exits 1"
run_guard dir6 --quiet --json
JSON6="${GUARD_OUT}"
check "${OUT6}" "missing file probe-a.sh (sync from canonical" "6: human output names the missing file with the canonical remedy"
check "${JSON6}" "plugin-cache:probe-a.sh:MISSING:CANONICAL_NEWER" "6: entry suffixed :MISSING:CANONICAL_NEWER"
check "${OUT6}" "SUMMARY-BY-COPY: plugin-cache: 1 entry (VENDORED_NEWER=0 CANONICAL_NEWER=0 UNKNOWN=0 MISSING=1)" "6: MISSING counts into the missing bucket only"

# ─────────────────────────────────────────────────────────────────────────
# 7. git-evidence branch: canonical IS a git repo — commit time decides even
#    when filesystem mtimes alone would say UNKNOWN (equal on both sides)
# ─────────────────────────────────────────────────────────────────────────
make_fixture dir7
(
  cd "${TMPROOT}/dir7/canon" || exit 1
  git init -q
  git config user.email test@example.invalid
  git config user.name drift-direction-test
  git add -A
  git commit -q -m "init probes"
)
# Both canonical + copy mtimes pinned to the SAME instant (2024) so the mtime
# fallback would classify UNKNOWN; only commit-time evidence (now) can decide.
printf -- '#!/usr/bin/env bash\necho future-local-work\n' > "${SHARED}/probe-a.sh"
printf -- '#!/usr/bin/env bash\necho stale-vendored\n' > "${VENDORED}/probe-a.sh"
touch -t 202401010000 "${TMPROOT}/dir7/canon/plugins/leadv2/scripts/probe-a.sh" "${SHARED}/probe-a.sh" "${VENDORED}/probe-a.sh"
# probe-a in the shared copy: content never committed, mtime equal -> only the
# git-vs-mtime mix can tag it. Equal mtimes would say UNKNOWN; assert the git
# evidence path tagged by leaving mtime equal and checking the tag is NOT
# UNKNOWN but matches git evidence: copy 2024 < commit-now -> CANONICAL_NEWER.
run_guard dir7
OUT7="${GUARD_OUT}"
check "${OUT7}" "content differs for probe-a.sh [CANONICAL_NEWER]" "7: git commit-time evidence decides over equal mtimes (CANONICAL_NEWER, not UNKNOWN)"

# Same repo, far-future copy mtime (2099 > commit time + 2) -> VENDORED_NEWER
# even though canonical's own file mtime is ALSO 2099 (mtime alone: UNKNOWN).
touch -t 209901010000 "${SHARED}/probe-a.sh" "${TMPROOT}/dir7/canon/plugins/leadv2/scripts/probe-a.sh"
run_guard dir7
OUT7B="${GUARD_OUT}"
check "${OUT7B}" "content differs for probe-a.sh [VENDORED_NEWER]" "7b: future copy mtime beats commit time -> VENDORED_NEWER via evidence, remedy follows"
check "${OUT7B}" "promote vendored -> canonical" "7b: vendored-newer remedy present"

echo "---"
if [[ ${FAIL} -eq 0 ]]; then
  echo "ALL TESTS PASSED"
  exit 0
else
  echo "TESTS FAILED"
  exit 1
fi
