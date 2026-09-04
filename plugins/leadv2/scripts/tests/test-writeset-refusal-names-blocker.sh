#!/usr/bin/env bash
# test-writeset-refusal-names-blocker.sh — WRITESET-REFUSAL-NEVER-NAMES-THE-BLOCKER-01.
#
# exit 5 from leadv2_active_register covers TWO situations that both used to
# surface as the same bare `dispatch_refused reason=writeset_conflict`:
#   1. pending_resolution — an incumbent with NO write set still inside
#      LEADV2_WRITESET_PENDING_WINDOW_SEC (refused before any path
#      comparison; narrowing one's writes is useless here), and
#   2. overlap — a genuine path collision.
# The registry already names the blocker on stderr
# ("[registry] writeset conflict: other=<task_id> reason=pending_resolution"
# / "... other=<task_id> paths=<a>,<b>"); cmd_resolve used to discard that
# stderr, so the answer the code had already computed never reached the
# blocked lead. This suite proves _emit_writeset_refusal (leadv2-dispatch-
# code.sh) parses the REAL registry stderr (never a hand-written fixture
# line) and emits two distinguishable reasons that both carry blocked_by=,
# plus the mandatory negative control: with the stderr swallowed again
# (exactly what the old 2>/dev/null call sites passed on), the blocker's
# name disappears and the legacy writeset_conflict fallback fires.
#
# Technique: same as test-dispatch-checkpoint-commit-cutoff.sh — source the
# REAL leadv2-dispatch-code.sh function bodies by truncating just before its
# trailing dispatch-case block (nothing dispatches/spawns), sourcing the
# truncation from within scripts/ so sibling `source` lines resolve, and
# driving the REAL registry (leadv2-active-registry.sh) against a scratch
# LEADV2_STATE_ROOT so the refusal parses the wire format the registry
# actually emits today.
#
# Run: bash plugins/leadv2/scripts/tests/test-writeset-refusal-names-blocker.sh
# run-all-triggers: leadv2-dispatch-code.sh

set -uo pipefail

# BURN-GOVERNOR-01: the burn gate defaults ON and reads the host's real
# ~/.claude/burn/history.db -- a hot host would red this suite on `exit 6`.
# LEADV2_WRITESET_PENDING_WINDOW_SEC is pinned per-case below, NOT here: the
# ambient harness environment can carry a hostile value (measured 2026-09-04:
# =1 leaked from a hook, which silently turned every pending_resolution into
# writeset_unknown and red the suite for a reason unrelated to the diff).
export LEADV2_BURN_GOVERNOR=0
# The ambient session may export LEADV2_WRITESET_PENDING_WINDOW_SEC=1 (set by
# the harness so this lane's OWN dispatch isn't blocked by a stale registry
# row) -- inherited by the subshells below, it would expire the incumbent's
# pending window before the candidate even registers. Pin a window generous
# enough that register-then-register within this suite can never race it.
export LEADV2_WRITESET_PENDING_WINDOW_SEC=900
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
DISPATCH_SH="${SCRIPTS_DIR}/leadv2-dispatch-code.sh"
REGISTRY_SH="${SCRIPTS_DIR}/leadv2-active-registry.sh"
source "${SCRIPTS_DIR}/leadv2-temp.sh"

PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); printf '[TEST] PASS: %s\n' "$1"; }
bad() { FAIL=$((FAIL + 1)); printf '[TEST] FAIL: %s\n' "$1"; }

RUN_ID="wr-refusal-$$-$(date +%s 2>/dev/null || echo 0)"
TMPDIR_ROOT="$(lv2_mktemp_dir "${RUN_ID}")"

# Truncation lives beside its siblings in SCRIPTS_DIR (SCRIPT_DIR-relative
# `source` lines inside leadv2-dispatch-code.sh require this) — a private
# dotfile, removed on exit alongside the rest of the fixture.
FUNCS_SH="${SCRIPTS_DIR}/.test-wr-refusal-funcs.$$.sh"
cleanup() { rm -rf "${TMPDIR_ROOT}"; rm -f "${FUNCS_SH}"; }
trap cleanup EXIT

CUT_LINE="$(grep -n '^# .. dispatch ..*$' "${DISPATCH_SH}" | tail -1 | cut -d: -f1)"
[[ -z "${CUT_LINE}" ]] && CUT_LINE="$(grep -n 'dispatch ─' "${DISPATCH_SH}" | tail -1 | cut -d: -f1)"
if [[ -z "${CUT_LINE}" ]]; then
  echo "[TEST] SETUP FAILED: could not locate trailing dispatch-case marker in ${DISPATCH_SH}" >&2
  exit 1
fi
head -n "$((CUT_LINE - 1))" "${DISPATCH_SH}" > "${FUNCS_SH}"

# _refusal_case <label> <incumbent_id> <incumbent_writes> <candidate_writes>
# Registers a REAL incumbent in the scratch registry, then runs a REAL second
# register (capturing its stderr exactly the way the FIXED call sites do —
# stderr kept, stdout dropped), then runs the real _emit_writeset_refusal on
# that stderr inside the sourced-function shell. Prints the refusal's stderr
# (emit decision line) and stdout (LEADV2_DISPATCH_REFUSED token) merged, plus
# a `reg_rc=` line so the case can assert the register itself was refused.
_refusal_case() {
  local label="$1" incumbent="$2" inc_writes="$3" cand_writes="$4"
  # Fresh scratch registry per case: rows accumulate inside one suite run, and
  # a prior case's no-writes incumbent (still inside its 900 s pending window)
  # would make THIS case's own incumbent register exit 5 -- which the sourced
  # registry's `set -e` then turns into a dead subshell (measured: case 2
  # produced no output at all until this isolation).
  local root="${TMPDIR_ROOT}/c-${label}"
  mkdir -p "${root}"
  ( cd "${root}" && git init -q && git config user.email t@e.com && git config user.name t \
    && : > seed && git add seed && git commit -qm seed ) >/dev/null 2>&1
  ( cd "${root}" || exit 9
    LEADV2_PROJECT_ROOT="${root}" LEADV2_STATE_ROOT="${root}" CLAUDE_PROJECT_DIR="${root}" \
    LEADV2_BURN_GOVERNOR=0 LEADV2_JOURNAL_BIN=/bin/true LEADV2_EVENT_BIN=/bin/true TERMINAL_LEDGER=0 \
    LEADV2_WRITESET_PENDING_WINDOW_SEC=900 \
    bash -s "${REGISTRY_SH}" "${FUNCS_SH}" "${incumbent}" "${inc_writes}" "${cand_writes}" <<'EOF'
set -uo pipefail
source "$1"
FUNCS="$2"; INC="$3"; INC_W="$4"; CAND_W="$5"
root="$(pwd)"
# Real incumbent row. Empty writes -> the pending window path; a declared
# write intersecting the candidate -> the overlap path. Same liveness either
# way: a just-registered row with no stale flag.
leadv2_active_register "${INC}" Standard "${root}" "wt-${INC}" false "" "" "${INC_W}" >/dev/null 2>&1
# Real candidate register, stderr captured (the fixed call-site shape: the
# old code did `2>/dev/null` / `>/dev/null 2>&1` here and lost the answer).
reg_err=""
set +e
reg_err="$(LEADV2_PROJECT_ROOT="${root}" LEADV2_STATE_ROOT="${root}" \
  leadv2_active_register "CANDIDATE" Standard "${root}" "wt-cand" false "" "" "${CAND_W}" 2>&1 >/dev/null)"
reg_rc=$?

printf 'reg_rc=%s\n' "${reg_rc}"
printf 'reg_stderr=[%s]\n' "${reg_err}"
source "${FUNCS}"
set +e
_emit_writeset_refusal "WRTEST01" "${CAND_W}" "${reg_err}" "FOUNDER-TASK" 2>&1
refusal_rc=$?

printf 'refusal_rc=%s\n' "${refusal_rc}"
EOF
  )
}

# ── 1. pending_resolution: incumbent with no writes inside the window ──────
out1="$(_refusal_case pending "WSR-INC-PEND" "" "plugins/leadv2/scripts/leadv2-dispatch-code.sh")"
line1="$(printf '%s\n' "${out1}" | grep -m1 'dispatch_refused')"
if printf '%s' "${out1}" | grep -q 'reg_rc=5' \
  && printf '%s' "${line1}" | grep -q 'reason=writeset_pending task=WRTEST01 blocked_by=WSR-INC-PEND' \
  && printf '%s' "${line1}" | grep -Eq 'age_s=([0-9]{1,4}|unknown) window_s=[0-9]+' \
  && ! printf '%s' "${line1}" | grep -q 'paths=' \
  && printf '%s' "${out1}" | grep -q 'LEADV2_DISPATCH_REFUSED: writeset_pending'; then
  ok "1: pending incumbent (no writes, inside window) refuses as writeset_pending naming blocked_by=WSR-INC-PEND, no paths=, age_s=/window_s present"
else
  bad "1: refusal line was: ${line1:-<none>}; full case: ${out1}"
fi

# ── 2. overlap: genuine path collision with a declared write set ───────────
out2="$(_refusal_case overlap "WSR-INC-OVR" "contested/b.txt" "contested/b.txt")"
line2="$(printf '%s\n' "${out2}" | grep -m1 'dispatch_refused')"
if printf '%s' "${out2}" | grep -q 'reg_rc=5' \
  && printf '%s' "${line2}" | grep -q 'reason=writeset_overlap task=WRTEST01 blocked_by=WSR-INC-OVR' \
  && printf '%s' "${line2}" | grep -q 'paths=contested/b.txt' \
  && printf '%s' "${out2}" | grep -q 'LEADV2_DISPATCH_REFUSED: writeset_overlap'; then
  ok "2: real path overlap refuses as writeset_overlap naming blocked_by=WSR-INC-OVR with the colliding paths="
else
  bad "2: refusal line was: ${line2:-<none>}; full case: ${out2}"
fi

# ── 3. distinguishability from the refusal text alone ──────────────────────
# The two lines must differ in reason AND carry exactly one discriminator
# each: pending has window_s= (paths never compared), overlap has paths=
# (and no window_s, which would be meaningless there).
if [[ -n "${line1}" && -n "${line2}" \
  && "${line1}" != "${line2}" ]] \
  && printf '%s' "${line1}" | grep -q 'window_s=' && ! printf '%s' "${line1}" | grep -q 'paths=' \
  && printf '%s' "${line2}" | grep -q 'paths=' && ! printf '%s' "${line2}" | grep -q 'window_s='; then
  ok "3: the two cases are distinguishable from the refusal text alone (reason + window_s= vs paths=)"
else
  bad "3: lines not distinguishable: [${line1}] vs [${line2}]"
fi

# ── 4. negative control (mandatory): swallow the stderr, name disappears ───
# Re-run the pending case's register the OLD way (2>/dev/null) and feed the
# resulting empty stderr to _emit_writeset_refusal — exactly what the
# pre-fix call sites passed. Without this, "the name is there" cannot be
# distinguished from "the name was always there and we never looked".
NEG_ROOT="${TMPDIR_ROOT}/c-neg"
mkdir -p "${NEG_ROOT}"
( cd "${NEG_ROOT}" && git init -q && git config user.email t@e.com && git config user.name t \
  && : > seed && git add seed && git commit -qm seed ) >/dev/null 2>&1
out4="$( cd "${NEG_ROOT}" || exit 9
  LEADV2_PROJECT_ROOT="${NEG_ROOT}" LEADV2_STATE_ROOT="${NEG_ROOT}" CLAUDE_PROJECT_DIR="${NEG_ROOT}" \
  LEADV2_BURN_GOVERNOR=0 LEADV2_JOURNAL_BIN=/bin/true LEADV2_EVENT_BIN=/bin/true TERMINAL_LEDGER=0 \
  LEADV2_WRITESET_PENDING_WINDOW_SEC=900 \
  bash -s "${REGISTRY_SH}" "${FUNCS_SH}" <<'EOF'
set -uo pipefail
source "$1"; FUNCS="$2"; root="$(pwd)"
# WSR-INC-NEG: another fresh no-writes incumbent, same shape as case 1.
leadv2_active_register "WSR-INC-NEG" Standard "${root}" "wt-neg" false >/dev/null 2>&1
reg_err=""
set +e
# OLD call-site shape at the second site: >/dev/null 2>&1 — stderr dropped.
LEADV2_PROJECT_ROOT="${root}" LEADV2_STATE_ROOT="${root}" \
  leadv2_active_register "CAND-NEG" Standard "${root}" "wt-cand-neg" false "" "" \
  "plugins/leadv2/scripts/leadv2-dispatch-code.sh" >/dev/null 2>&1

source "${FUNCS}"
set +e
_emit_writeset_refusal "WRNEG01" "plugins/leadv2/scripts/leadv2-dispatch-code.sh" "${reg_err}" "FOUNDER-TASK" 2>&1

EOF
)"
line4="$(printf '%s\n' "${out4}" | grep -m1 'dispatch_refused')"
if printf '%s' "${line4}" | grep -q 'reason=writeset_conflict' \
  && ! printf '%s' "${line4}" | grep -q 'blocked_by='; then
  ok "4: negative control — with stderr re-swallowed (old 2>/dev/null), blocked_by disappears and the legacy writeset_conflict fallback fires"
else
  bad "4: expected bare writeset_conflict with no blocked_by, got: ${line4:-<none>}"
fi

echo "----"
echo "PASS=${PASS} FAIL=${FAIL}"
[[ ${FAIL} -eq 0 ]]
