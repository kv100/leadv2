#!/usr/bin/env bash
# test-selfcheck-sql-comment-header.sh — SELFCHECK-SQL-COMMENT-HEADER-01.
#
# WHY THIS TEST EXISTS: the builder selfcheck extracts changed paths from a diff by
# matching any line beginning with "--- " or "+++ ". A REMOVED SQL comment line
# `-- some text` renders in a unified diff as `--- some text` — byte-identical in
# shape to a real file header `--- a/path`. So every round that deletes a SQL comment
# donates its prose to the write-set, and the scope check then reports English
# sentences as off-write-set paths and fails the round.
#
# This is not hypothetical. It blocked lane 14bd0c10 TWICE in one night:
#   dispatch-4181a3e2 -> failed: scope:off_write_set:"`set local` (fix round 1, M4): a
#     bare session-scoped `set lock_timeout`,leaks into whatever the migration runner…"
#   dispatch-2cbfe96d -> failed: scope:off_write_set:"This file may be applied wrapped
#     in a transaction or unwrapped, depending,on which applier runs it,…"
# Both rounds' LANE_WRITES lines were correct and both diffs were fine. The artifact
# `docs/handoff/dispatch-2cbfe96d/review.diff` shows it plainly: real headers at lines
# 220 and 284, six phantom "--- " lines at 226-231 in between.
#
# SQL is the language whose comment marker is `--`, which is why migrations are where
# this bites — but the bug is in the parser, not in SQL.
#
# The fix keeps the original intent (SCOPE-DISCIPLINE-01 fix-round-2: collect BOTH
# sides so deletions and rename sources are not missed) and only tightens what counts
# as a header: a real one is inside a `diff --git` block, or carries the a/ or b/
# prefix, or is /dev/null. A SQL comment has none of those.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB="${SCRIPT_DIR}/../lib/leadv2-builder-selfcheck.sh"

PASS=0; FAIL=0; GREEN_PRE_FIX=0; COULD_NOT_RUN=0
declare -a ERRORS=()
log() { printf '[TEST] %s\n' "$*"; }

WORK="$(mktemp -d "${TMPDIR:-/tmp}/sc-sqlhdr.XXXXXX")"
trap 'rm -rf "${WORK}"' EXIT

REPO="$(cd "${SCRIPT_DIR}" && git rev-parse --show-toplevel 2>/dev/null)"
PRE_LIB="${WORK}/pre-lib.sh"
if [[ -n "${REPO}" ]]; then
  git -C "${REPO}" show "HEAD:plugins/leadv2/scripts/lib/leadv2-builder-selfcheck.sh" \
    > "${PRE_LIB}" 2>/dev/null || : > "${PRE_LIB}"
fi
[[ -s "${PRE_LIB}" ]] || PRE_LIB=""

# A diff that removes a SQL comment block from a migration, exactly as git renders it:
# the removed `-- text` lines become `--- text` and sit between two real file headers.
_write_diff() { # <path>
  cat > "$1" <<'DIFF'
diff --git a/supabase/migrations/20260818170000_guard.sql b/supabase/migrations/20260818170000_guard.sql
index 1111111..2222222 100644
--- a/supabase/migrations/20260818170000_guard.sql
+++ b/supabase/migrations/20260818170000_guard.sql
@@ -1,8 +1,3 @@
--- This file may be applied wrapped in a transaction or unwrapped, depending
--- on which applier runs it, so the session-scoped form is used here — a
--- `set local` outside a transaction is a silent no-op. No explicit
--- begin/commit wrapper here — a migration file may contain its own commit.
 set lock_timeout = '5s';
 alter table feed_posts add column if not exists topic_gate_reason text;
diff --git a/tests/unit/test-migration-lock-timeout.sh b/tests/unit/test-migration-lock-timeout.sh
index 3333333..4444444 100644
--- a/tests/unit/test-migration-lock-timeout.sh
+++ b/tests/unit/test-migration-lock-timeout.sh
@@ -1,2 +1,3 @@
 #!/usr/bin/env bash
+echo ok
DIFF
}

# Run the lib against the diff with a write-set that legitimately covers BOTH real
# files. A correct parser finds exactly those two paths and the scope check passes.
# The buggy parser also harvests the four removed SQL comment lines, none of which
# are in the write-set, and fails with prose reported as paths.
_scope_verdict() { # <lib> -> prints "CLEAN" or "OFFSET:<first offending target>"
  local lib="$1"
  [[ -f "$lib" ]] || return 2
  local diff="${WORK}/d.diff" md="${WORK}/out.md"
  _write_diff "${diff}"
  : > "${md}"
  (
    set +e
    # shellcheck disable=SC1090
    source "${lib}" >/dev/null 2>&1 || exit 2
    command -v lv2_selfcheck_run >/dev/null 2>&1 || exit 2
    LEADV2_E2E_GATE=0 lv2_selfcheck_run "${diff}" "${WORK}" "${WORK}" "${md}" \
      "supabase/migrations/20260818170000_guard.sql,tests/unit/test-migration-lock-timeout.sh" \
      >/dev/null 2>&1
  ) || true
  [[ -s "${md}" ]] || return 2
  if grep -q 'off_write_set' "${md}"; then
    printf 'OFFSET'
  else
    printf 'CLEAN'
  fi
}

_expect_clean() { # <lib>
  local got; got="$(_scope_verdict "$1")" || return 2
  [[ -z "${got}" ]] && return 2
  [[ "${got}" == "CLEAN" ]] && return 0
  return 1
}

# A removed SQL comment must not be mistaken for a file header. This is the whole bug.
case_sql_comment_not_a_path() { _expect_clean "$1"; }

run_case() { # <name> <fn>
  local name="$1" fn="$2" pre_rc post_rc
  if [[ -n "${PRE_LIB}" ]]; then "${fn}" "${PRE_LIB}" >/dev/null 2>&1; pre_rc=$?; else pre_rc=2; fi
  "${fn}" "${LIB}" >/dev/null 2>&1; post_rc=$?
  if [[ ${post_rc} -eq 2 ]]; then
    COULD_NOT_RUN=$((COULD_NOT_RUN + 1)); log "COULD-NOT-RUN: ${name}"; return
  fi
  if [[ ${post_rc} -ne 0 ]]; then
    FAIL=$((FAIL + 1)); ERRORS+=("${name}: post-fix rc=${post_rc}")
    log "FAIL: ${name} -- post-fix rc=${post_rc}, expected 0"; return
  fi
  if [[ ${pre_rc} -eq 0 ]]; then
    GREEN_PRE_FIX=$((GREEN_PRE_FIX + 1))
    log "GREEN-PRE-FIX: ${name} -- passed against the pre-fix lib too (pre_rc=0)"; return
  fi
  PASS=$((PASS + 1)); log "RED-then-GREEN: ${name} (pre_rc=${pre_rc} -> post_rc=0)"
}

log "PASS: bash -n leadv2-builder-selfcheck.sh"
bash -n "${LIB}" || { log "FAIL: bash -n"; exit 1; }

run_case "sql-comment-is-not-a-file-header" case_sql_comment_not_a_path

echo ""
echo "Results: ${PASS} passed(red->green), ${FAIL} failed, ${GREEN_PRE_FIX} green-pre-fix, ${COULD_NOT_RUN} could-not-run"
if [[ ${FAIL} -gt 0 ]]; then printf -- 'FAIL: %s\n' "${ERRORS[@]}"; exit 1; fi
exit 0
