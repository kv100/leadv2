#!/usr/bin/env bash
# tests/test-empty-writes-autocommit-loud-skip.sh — LANE-WRITES-IS-EMPTY-98-PERCENT-01
# items 2+3
#
# pc_precheck_writes and pc_stop_gate_autocommit (leadv2-dispatch-product-close.sh)
# both bailed on an empty write-set with a bare `|| return 0` -- no journal line,
# no trace. ~70% of real dispatches declare no LANE_WRITES (this row's own
# premise recheck), so for the majority of lanes the autocommit checkpoint
# silently never ran, indistinguishable from "nothing needed checkpointing".
#
# Fix: both functions now emit a named `stop_gate_autocommit_skipped
# reason=<writes_csv_empty|empty_scope_writes_csv>` line before returning. This
# is the brief's "loud refusal" branch, not "unbounded check" -- the gate's own
# containment design makes staging undeclared paths on an empty write-set
# actively unsafe (that IS the scope violation this gate exists to prevent), so
# the conservative behaviour (nothing gets auto-committed) is unchanged; only
# the silence is fixed.
# run-all-triggers: leadv2-dispatch-product-close

set -uo pipefail

export LEADV2_BURN_GOVERNOR=0

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LANE_WT_BIN="${SCRIPT_DIR}/leadv2-lane-worktree.sh"
PC="${SCRIPT_DIR}/leadv2-dispatch-product-close.sh"
FAIL=0

bash -n "${PC}" || { echo "ERROR: bash -n failed for ${PC}"; exit 1; }

pass() { printf 'PASS: %s\n' "$1"; }
fail() { printf 'FAIL: %s -- %s\n' "$1" "$2"; FAIL=1; }

new_repo() {
  local d
  d="$(mktemp -d "${TMPDIR:-/tmp}/leadv2-ewac.XXXXXX")"
  ( cd "${d}" && git init -q -b main && git config user.email test@example.com \
    && git config user.name test && mkdir -p agent \
    && printf 'seed\n' > agent/seed.py && git add agent/seed.py && git commit -qm seed ) >/dev/null 2>&1
  printf '%s' "${d}"
}
worktree_path() { printf '%s/.claude/worktrees/%s' "$1" "$2"; }
ensure_worktree() {
  LEADV2_PROJECT_ROOT="$1" bash "${LANE_WT_BIN}" ensure "$2" standard >/dev/null 2>&1
  worktree_path "$1" "$2"
}

run_close_gate() { # <pc_binary> <root> <wt> <tid> -> stderr on stdout
  CLAUDE_PROJECT_ROOT="${2}" LEADV2_DISPATCH_LANE_WRITES="" LEADV2_LANE_WORK_ROOT="${3}" \
  LEADV2_BUILDER_SELFCHECK=0 LEADV2_REVIEW_ENGINE=0 \
  bash "${1}" "${2}" "${4}sig001" sonnet "" 0 0 "${4}" 2>&1 >/dev/null
}

ROOT="$(new_repo)"
TID="ewac-$$"
WT="$(ensure_worktree "${ROOT}" "${TID}")"
cleanup() { rm -rf "${ROOT}"; }
trap cleanup EXIT

if [[ ! -d "${WT}" ]]; then
  fail "fixture setup" "worktree not created at ${WT}"
else
  # Real uncommitted worker output, in a lane whose write-set was never
  # declared -- exactly the ~70% shape this row's premise recheck measured.
  printf 'worker output\n' > "${WT}/agent/undeclared.py"

  ERR="$(run_close_gate "${PC}" "${ROOT}" "${WT}" "${TID}")"

  # --- test 1: pc_precheck_writes' loud skip fires ---
  if [[ "${ERR}" == *"stop_gate_autocommit_skipped"*"reason=writes_csv_empty"* ]]; then
    pass "pc_precheck_writes journals a named reason instead of a silent return on empty WRITES_CSV"
  else
    fail "precheck loud skip" "stderr did not contain 'stop_gate_autocommit_skipped ... reason=writes_csv_empty': ${ERR}"
  fi

  # --- test 2: pc_stop_gate_autocommit's own loud skip also fires (same
  # empty-writes shape reaches its own guard too) ---
  if [[ "${ERR}" == *"reason=empty_scope_writes_csv"* ]]; then
    pass "pc_stop_gate_autocommit journals its own named reason instead of a silent return"
  else
    fail "autocommit loud skip" "stderr did not contain 'reason=empty_scope_writes_csv': ${ERR}"
  fi

  # --- test 3: the conservative behaviour is UNCHANGED -- nothing with an
  # undeclared write-set gets auto-committed. This is the "loud refusal", not
  # "unbounded check" branch; staging undeclared paths would itself be the
  # scope violation this gate exists to prevent.
  status="$(git -C "${WT}" status --porcelain -- agent/undeclared.py 2>/dev/null || true)"
  if [[ "${status}" == '??'* ]]; then
    pass "undeclared work is still never auto-committed on an empty write-set (conservative behaviour unchanged)"
  else
    fail "conservative behaviour" "expected agent/undeclared.py to remain untracked, git status='${status}'"
  fi
fi

# --- test 4: MUTATION CONTROL -- restore the bare silent `return 0` INSIDE
# the function body (never a top-level/line-number insert), removing the
# journal line this suite exists to prove. Confirms the suite actually
# exercises the fix.
TMP_MUT="$(mktemp -d "${TMPDIR:-/tmp}/leadv2-ewac-mut.XXXXXX")"
MUT_PC="${TMP_MUT}/leadv2-dispatch-product-close.sh"
python3 - "${PC}" "${MUT_PC}" <<'PY'
import re, sys
src_path, dst_path = sys.argv[1], sys.argv[2]
text = open(src_path).read()
text = text.replace(
    'if [[ -z "${WRITES_CSV:-}" ]]; then\n'
    '    emit decision "stop_gate_autocommit_skipped task=${TASK} reason=writes_csv_empty"\n'
    '    return 0\n'
    '  fi',
    '[[ -n "${WRITES_CSV:-}" ]] || return 0',
    1,
)
text = text.replace(
    'if [[ -z "${_PC_SCOPE_WRITES_CSV:-}" ]]; then\n'
    '    emit decision "stop_gate_autocommit_skipped task=${TASK} reason=empty_scope_writes_csv"\n'
    '    return 0\n'
    '  fi',
    '[[ -n "${_PC_SCOPE_WRITES_CSV:-}" ]] || return 0',
    1,
)
open(dst_path, 'w').write(text)
PY
chmod +x "${MUT_PC}" 2>/dev/null || true

if diff -q "${PC}" "${MUT_PC}" >/dev/null 2>&1; then
  fail "mutation control" "mutated file byte-identical to production -- the mutation never applied, this control proves nothing"
else
  ROOT2="$(new_repo)"
  TID2="ewacmut-$$"
  WT2="$(ensure_worktree "${ROOT2}" "${TID2}")"
  printf 'worker output\n' > "${WT2}/agent/undeclared.py"
  MUT_ERR="$(run_close_gate "${MUT_PC}" "${ROOT2}" "${WT2}" "${TID2}")"
  rm -rf "${ROOT2}"
  if [[ "${MUT_ERR}" != *"stop_gate_autocommit_skipped"* ]]; then
    pass "MUTATION CONTROL: restoring the bare silent return removes the journal line entirely (suite would go red)"
  else
    fail "mutation control" "mutated stderr still contained 'stop_gate_autocommit_skipped': ${MUT_ERR}"
  fi
fi
rm -rf "${TMP_MUT}"

if [[ "${FAIL}" -eq 0 ]]; then
  echo "ALL PASS: test-empty-writes-autocommit-loud-skip.sh"
  exit 0
else
  echo "SOME FAILED: test-empty-writes-autocommit-loud-skip.sh"
  exit 1
fi
