#!/usr/bin/env bash
# test-m3-market-is-not-a-repo.sh — M3-MARKET-IS-NOT-A-GIT-REPO-01 (row 614ee2ce74f5)
# run-all-triggers: leadv2-helpers.sh leadv2-dispatch-code.sh leadv2-state-path.sh leadv2-temp.sh
#
# Doctrine (plugins/leadv2/ref/m3-control-directory.md, founder decision
# 2026-09-13 "подтверждаю"): ~/MythicalGames/m3-market is a leadv2 CONTROL
# DIRECTORY, not a git repo. Code repo: ~/MythicalGames/m3-market/m3. Second
# separate clone: ~/MythicalGames/m3. This suite goes RED if:
#   (1) ~/MythicalGames/m3-market/.git ever appears (someone took the other
#       branch of the decision and git-init'd the control directory),
#   (2) a live surface again calls m3-market a repo (user-level ~/.claude/
#       CLAUDE.md "Live repos" line, persona-engine .claude/CLAUDE.md "Live:"
#       line) — asserted from the LIVE files, never a hand-kept copy,
#   (3) the dispatch-path guard stops refusing git queries aimed at the
#       control directory (helpers fn + inline dispatch block).
#
# Declared negative controls (suite header, per E2E-KILLRATE-01):
#   M3M-01 (tool-backed, leadv2-mutation-control.sh --live, artifact in the
#     lane's mutation-control/): inside leadv2_control_dir_git_guard() the
#     refusal `return 1` is replaced by `return 0` — check 5 must go RED.
#   M3M-02 (manual scratch, shown in the lane report): the corrected sentence
#     in a scratch COPY of ~/.claude/CLAUDE.md is reverted to the old
#     repo-calling wording (anchored: new-string count asserted == 1 before
#     replacing) — run with M3_MARKET_TEST_USER_CLAUDE_MD=<scratch>, check 3
#     must go RED. Never a top-level insert: the replacement is in-place.
#
# Env overrides (scratch/negative-control runs ONLY; defaults are the LIVE
# surfaces — do not point production at hand-kept copies, they drift):
#   M3_MARKET_TEST_CONTROL_DIR   default $HOME/MythicalGames/m3-market
#   M3_MARKET_TEST_PLUGIN_ROOT   default = this script's plugins/leadv2
#   M3_MARKET_TEST_USER_CLAUDE_MD  default $HOME/.claude/CLAUDE.md
#   M3_MARKET_TEST_PE_CLAUDE_MD    default $HOME/Projects/persona-engine/.claude/CLAUDE.md
#   M3_MARKET_TEST_DISPATCH       default <plugin>/scripts/leadv2-dispatch-code.sh
set -uo pipefail

FAIL=0
pass() { printf 'PASS: %s\n' "$1"; }
fail() { printf 'FAIL: %s\n' "$1"; FAIL=1; }

TESTS_DIR="$(cd "$(dirname "$0")" && pwd)"
CONTROL_DIR="${M3_MARKET_TEST_CONTROL_DIR:-$HOME/MythicalGames/m3-market}"
PLUGIN_ROOT="${M3_MARKET_TEST_PLUGIN_ROOT:-$(cd "${TESTS_DIR}/../.." && pwd)}"
USER_CLAUDE_MD="${M3_MARKET_TEST_USER_CLAUDE_MD:-$HOME/.claude/CLAUDE.md}"
PE_CLAUDE_MD="${M3_MARKET_TEST_PE_CLAUDE_MD:-$HOME/Projects/persona-engine/.claude/CLAUDE.md}"
DISPATCH_SH="${M3_MARKET_TEST_DISPATCH:-${PLUGIN_ROOT}/scripts/leadv2-dispatch-code.sh}"
HELPERS_SH="${PLUGIN_ROOT}/scripts/leadv2-helpers.sh"

# ── 1. The control directory must NOT be a git repo ────────────────────────
if [ -e "${CONTROL_DIR}/.git" ]; then
  fail "${CONTROL_DIR}/.git EXISTS — the control directory was git-init'd; founder decision 2026-09-13 says it must never be a repo (see ref/m3-control-directory.md)"
else
  pass "control directory ${CONTROL_DIR} has no .git"
fi

# ── 2. The code repo is where the doctrine says it is ──────────────────────
if [ -d "${CONTROL_DIR}/m3/.git" ]; then
  pass "m3 code repo present at ${CONTROL_DIR}/m3/.git"
else
  fail "m3 code repo MISSING at ${CONTROL_DIR}/m3/.git — doctrine path is stale"
fi

# check_line <label> <file> <grep-for-the-line>  — the line that enumerates
# live repos must name the code repo (m3-market/m3) and must carry no
# m3-market token outside the two allowed path forms (m3-market/m3 and
# MythicalGames/m3-market). A bare "m3-market" among repo names is the
# regression this suite exists to catch.
check_line() { # <label> <file> <line-pattern>
  local label="$1" file="$2" pattern="$3" line stripped
  line="$(grep -m1 "${pattern}" "${file}" 2>/dev/null || true)"
  if [ -z "${line}" ]; then
    fail "${label}: no '${pattern}' line found in ${file}"
    return
  fi
  case "${line}" in
    *m3-market/m3*) ;;
    *) fail "${label}: '${pattern}' line does not name the m3 code repo m3-market/m3 — got: ${line}"; return ;;
  esac
  stripped="${line//m3-market\/m3/}"
  stripped="${stripped//MythicalGames\/m3-market/}"
  case "${stripped}" in
    *m3-market*) fail "${label}: '${pattern}' line still calls bare m3-market a repo: ${line}" ;;
    *) pass "${label}: live line names m3-market/m3, no bare m3-market" ;;
  esac
}

# ── 3. User-level live surface ──────────────────────────────────────────────
check_line "user CLAUDE.md Live repos" "${USER_CLAUDE_MD}" "Live repos:"

# ── 4. persona-engine live surface ─────────────────────────────────────────
# NOTE: reads the MAIN checkout. Until lane 614ee2ce74f5 (this row) merges to
# persona-engine main this check is RED by design — the live surface is still
# in the bad state the suite exists to catch.
check_line "persona-engine CLAUDE.md Live" "${PE_CLAUDE_MD}" "^Live:"

# ── 5. Guard behavior: helpers fn refuses the control dir ─────────────────
if [ -f "${HELPERS_SH}" ]; then
  guard_err="$( bash -c '
    source "${1}" >/dev/null 2>&1
    leadv2_control_dir_git_guard "${2}"' _ "${HELPERS_SH}" "${CONTROL_DIR}" 2>&1 )"
  guard_rc=$?
  if [ "${guard_rc}" -ne 0 ] && printf '%s' "${guard_err}" | grep -q "m3-market/m3"; then
    pass "leadv2_control_dir_git_guard refuses the control dir, message names m3-market/m3"
  else
    fail "leadv2_control_dir_git_guard did NOT refuse ${CONTROL_DIR} naming m3-market/m3 (rc=${guard_rc}, err=${guard_err:-<none>})"
  fi
  bash -c 'source "${1}" >/dev/null 2>&1; leadv2_control_dir_git_guard "${2}"' _ "${HELPERS_SH}" "${CONTROL_DIR}/m3" >/dev/null 2>&1 \
    && pass "guard passes the m3 code repo …/m3" \
    || fail "guard must NOT refuse the code repo ${CONTROL_DIR}/m3"
  bash -c 'source "${1}" >/dev/null 2>&1; leadv2_control_dir_git_guard "${2}"' _ "${HELPERS_SH}" "${TESTS_DIR}" >/dev/null 2>&1 \
    && pass "guard passes an unrelated dir" \
    || fail "guard must not refuse unrelated dirs (got refusal for ${TESTS_DIR})"
else
  fail "helpers not found at ${HELPERS_SH}"
fi

# ── 6. Dispatch path carries the inline refusal ────────────────────────────
if grep -q "M3-MARKET-IS-NOT-A-GIT-REPO-01" "${DISPATCH_SH}" 2>/dev/null \
   && grep -q "CONTROL DIRECTORY, not a git repo" "${DISPATCH_SH}" 2>/dev/null; then
  pass "leadv2-dispatch-code.sh carries the control-directory refusal block"
else
  fail "leadv2-dispatch-code.sh lost its M3-MARKET-IS-NOT-A-GIT-REPO-01 refusal block (${DISPATCH_SH})"
fi

# ── 7. Doctrine file exists and names the backup worked example ────────────
if [ -f "${PLUGIN_ROOT}/ref/m3-control-directory.md" ] \
   && grep -q "e4cece06" "${PLUGIN_ROOT}/ref/m3-control-directory.md"; then
  pass "doctrine ref/m3-control-directory.md present, names backup example e4cece06"
else
  fail "doctrine ref/m3-control-directory.md missing or lost its e4cece06 backup rule (${PLUGIN_ROOT}/ref/)"
fi

if [ "${FAIL}" -eq 1 ]; then
  printf 'SUITE test-m3-market-is-not-a-repo: RED\n'
  exit 1
fi
printf 'SUITE test-m3-market-is-not-a-repo: GREEN (%s checks)\n' 7
exit 0
