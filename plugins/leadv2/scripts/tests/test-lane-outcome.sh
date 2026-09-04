#!/usr/bin/env bash
# changed-scope triggers, self-registered (SD-SUITE-MAP-SERIALIZES-EVERY-WAVE-01, migrated from tests/run-all.sh EXTRA_SUITE_MAP; discovered by scan_suite_triggers):
# run-all-triggers: glm-coder.sh
# test-lane-outcome.sh — offline tests for N-3 (TURN-CAP-OUTCOME-01):
# leadv2-lane-outcome.sh, the join of bound-detection + N-2 work-delta into
# one of the three outcome tokens (completed | died-with-work | died-clean).
#
# No network, no real `claude` invocation -- every scenario builds a fixture
# run_dir by hand (meta.yaml, .bound_reason, .workbase, journal.jsonl) and a
# throwaway local git repo where a case needs real git state. Never touches
# prod run dirs.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLASSIFIER="${SCRIPT_DIR}/../leadv2-lane-outcome.sh"
GLM_CODER="${SCRIPT_DIR}/../glm-coder.sh"
KIMI_CODER="${SCRIPT_DIR}/../kimi-coder.sh"
THIS_TEST="${SCRIPT_DIR}/test-lane-outcome.sh"

TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "${TMP_ROOT}"' EXIT

FAILURES=0
PASSES=0
pass() { printf 'PASS: %s\n' "$1"; PASSES=$((PASSES + 1)); }
fail() { printf 'FAIL: %s -- %s\n' "$1" "$2"; FAILURES=$((FAILURES + 1)); }

_hash() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum | cut -d' ' -f1
  elif command -v shasum >/dev/null 2>&1; then
    shasum -a 256 | cut -d' ' -f1
  else
    cksum | cut -d' ' -f1
  fi
}

_new_run_dir() { # -> path
  local d
  d="$(mktemp -d "${TMP_ROOT}/run-XXXXXX")"
  printf 'run_id: %s\n' "$(basename "${d}")" > "${d}/meta.yaml"
  echo "${d}"
}

_assert_outcome_file() { # <run_dir> <case> <expect_outcome> <expect_bound> <expect_next>
  local run_dir="$1" case_name="$2" expect_outcome="$3" expect_bound="$4" expect_next="$5"
  if [[ ! -f "${run_dir}/.outcome" ]]; then
    fail "${case_name}" ".outcome sentinel not written"
    return
  fi
  local got_outcome got_bound got_next
  got_outcome="$(grep '^outcome=' "${run_dir}/.outcome" | head -1 | cut -d= -f2-)"
  got_bound="$(grep '^bound=' "${run_dir}/.outcome" | head -1 | cut -d= -f2-)"
  got_next="$(grep '^next=' "${run_dir}/.outcome" | head -1 | cut -d= -f2-)"
  if [[ "${got_outcome}" != "${expect_outcome}" ]]; then
    fail "${case_name}" "outcome=${got_outcome}, expected ${expect_outcome}"
    return
  fi
  if [[ -n "${expect_bound}" && "${got_bound}" != "${expect_bound}" ]]; then
    fail "${case_name}" "bound=${got_bound}, expected ${expect_bound}"
    return
  fi
  if [[ -n "${expect_next}" && "${got_next}" != "${expect_next}" ]]; then
    fail "${case_name}" "next=${got_next}, expected ${expect_next}"
    return
  fi
  if ! grep -q "LEADV2_LANE_OUTCOME outcome=${expect_outcome}" "${run_dir}/progress.log" 2>/dev/null; then
    fail "${case_name}" "progress.log missing LEADV2_LANE_OUTCOME line"
    return
  fi
  if ! grep -q "^outcome: ${expect_outcome}$" "${run_dir}/meta.yaml" 2>/dev/null; then
    fail "${case_name}" "meta.yaml missing outcome: ${expect_outcome}"
    return
  fi
  pass "${case_name}"
}

# ---------------------------------------------------------------------------
# case_bash_n — syntax-clean on the classifier and both wrapper call sites.
# ---------------------------------------------------------------------------
if bash -n "${CLASSIFIER}" && bash -n "${GLM_CODER}" && bash -n "${KIMI_CODER}" && bash -n "${THIS_TEST}"; then
  pass "case_bash_n"
else
  fail "case_bash_n" "bash -n reported a syntax error"
fi

# ---------------------------------------------------------------------------
# Shared git fixture for the work-delta cases (1, 2, 7).
# ---------------------------------------------------------------------------
REPO_DIR="${TMP_ROOT}/repo"
mkdir -p "${REPO_DIR}"
git -C "${REPO_DIR}" init -q -b main
git -C "${REPO_DIR}" config user.email "test@example.com"
git -C "${REPO_DIR}" config user.name "test"
echo "one" > "${REPO_DIR}/file.txt"
mkdir -p "${REPO_DIR}/docs"
git -C "${REPO_DIR}" add -A
git -C "${REPO_DIR}" commit -q -m "init"

BARE_DIR="${TMP_ROOT}/repo.git"
git clone -q --bare "${REPO_DIR}" "${BARE_DIR}"
git -C "${REPO_DIR}" remote add origin "${BARE_DIR}"
git -C "${REPO_DIR}" push -q -u origin main

# ---------------------------------------------------------------------------
# case_1 — .bound_reason=turn_count, exit 124, tree dirty vs .workbase
#          -> died-with-work, next=continue
# ---------------------------------------------------------------------------
run_dir="$(_new_run_dir)"
printf 'run_id: %s\ncwd: %s\n' "$(basename "${run_dir}")" "${REPO_DIR}" > "${run_dir}/meta.yaml"
base_head="$(git -C "${REPO_DIR}" rev-parse HEAD)"
base_dirty="$(git -C "${REPO_DIR}" status --porcelain -- . ':(exclude)docs/' | _hash)"
{ printf 'head=%s\n' "${base_head}"; printf 'dirty=%s\n' "${base_dirty}"; } > "${run_dir}/.workbase"
echo "turn_count" > "${run_dir}/.bound_reason"
echo "changed" >> "${REPO_DIR}/file.txt"
"${CLASSIFIER}" "${run_dir}" 124 >/dev/null
_assert_outcome_file "${run_dir}" "case_1_bound_dirty_died_with_work" "died-with-work" "turn_count" "continue"
git -C "${REPO_DIR}" checkout -q -- file.txt

# ---------------------------------------------------------------------------
# case_2 — same bound, tree identical to .workbase -> died-clean, next=respawn
# ---------------------------------------------------------------------------
run_dir="$(_new_run_dir)"
printf 'run_id: %s\ncwd: %s\n' "$(basename "${run_dir}")" "${REPO_DIR}" > "${run_dir}/meta.yaml"
base_head="$(git -C "${REPO_DIR}" rev-parse HEAD)"
base_dirty="$(git -C "${REPO_DIR}" status --porcelain -- . ':(exclude)docs/' | _hash)"
{ printf 'head=%s\n' "${base_head}"; printf 'dirty=%s\n' "${base_dirty}"; } > "${run_dir}/.workbase"
echo "turn_count" > "${run_dir}/.bound_reason"
"${CLASSIFIER}" "${run_dir}" 124 >/dev/null
_assert_outcome_file "${run_dir}" "case_2_bound_clean_died_clean" "died-clean" "turn_count" "respawn"

# ---------------------------------------------------------------------------
# case_3 — exit 0, no .no-deliverable -> completed, bound=none
# ---------------------------------------------------------------------------
run_dir="$(_new_run_dir)"
echo "path=some/deliverable.md" > "${run_dir}/.deliverable"
"${CLASSIFIER}" "${run_dir}" 0 >/dev/null
_assert_outcome_file "${run_dir}" "case_3_completed" "completed" "none" "none"

# ---------------------------------------------------------------------------
# case_4 — no .bound_reason, journal tail has subtype=error_max_turns, work
#          passed in as yes -> died-with-work, bound=max_turns
# ---------------------------------------------------------------------------
run_dir="$(_new_run_dir)"
printf '{"type":"assistant","turn":1}\n{"type":"result","subtype":"error_max_turns"}\n' > "${run_dir}/journal.jsonl"
"${CLASSIFIER}" "${run_dir}" 1 yes >/dev/null
_assert_outcome_file "${run_dir}" "case_4_max_turns_json" "died-with-work" "max_turns" "continue"

# ---------------------------------------------------------------------------
# case_5 — malformed journal tail -> bound=none (never guessed)
# ---------------------------------------------------------------------------
run_dir="$(_new_run_dir)"
printf 'this is not json\nneither is this{{{\n' > "${run_dir}/journal.jsonl"
"${CLASSIFIER}" "${run_dir}" 1 no >/dev/null
_assert_outcome_file "${run_dir}" "case_5_malformed_journal_bound_none" "died-clean" "none" "respawn"

# ---------------------------------------------------------------------------
# case_6 — meta.yaml absent / no cwd -> died-clean, classifier itself exits 0
#          and never throws.
# ---------------------------------------------------------------------------
run_dir="$(mktemp -d "${TMP_ROOT}/run-XXXXXX")"
rc=0
"${CLASSIFIER}" "${run_dir}" 1 >/dev/null || rc=$?
if [[ "${rc}" -ne 0 ]]; then
  fail "case_6_no_meta_no_throw" "classifier exited ${rc}, expected 0"
else
  _assert_outcome_file "${run_dir}" "case_6_no_meta_no_throw" "died-clean" "none" "respawn"
fi

# ---------------------------------------------------------------------------
# case_7 — commits ahead of @{u}, clean worktree, no .workbase (delta=skip)
#          -> work=yes via the git-ahead fallback -> died-with-work
# ---------------------------------------------------------------------------
run_dir="$(_new_run_dir)"
printf 'run_id: %s\ncwd: %s\n' "$(basename "${run_dir}")" "${REPO_DIR}" > "${run_dir}/meta.yaml"
echo "two" >> "${REPO_DIR}/file.txt"
git -C "${REPO_DIR}" commit -q -am "ahead commit"
"${CLASSIFIER}" "${run_dir}" 1 >/dev/null
_assert_outcome_file "${run_dir}" "case_7_ahead_commits_died_with_work" "died-with-work" "none" "continue"

# ---------------------------------------------------------------------------
# Summary — the runner's own return-0-regardless defect (fadd0be) is why the
# counters below, not $?, are the source of truth for this suite's verdict.
# ---------------------------------------------------------------------------
printf '\ntest-lane-outcome: %d passed, %d failed\n' "${PASSES}" "${FAILURES}"
(( FAILURES == 0 ))
