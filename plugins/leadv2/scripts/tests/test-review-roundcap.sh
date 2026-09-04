#!/usr/bin/env bash
# tests/test-review-roundcap.sh — REVIEW-ROUNDCAP-01.
#
# The declared "max 2 rounds then architect escape" policy used to be
# enforced only by the (unreliable) LLM lead's judgement; the engine itself
# never refused a round. This suite exercises the deterministic engine-side
# cap: LEADV2_REVIEW_MAX_ROUNDS (default 2, 0=unlimited) refuses a further
# round via exit 8 once .review-round.state's attempts counter reaches the
# limit, plus the spawns backstop that bounds dedup-frozen lanes. Mirrors the
# stub-resolver/stub-arm harness of test-review-round-exhaustive.sh (zero
# network, mktemp -d + trap cleanup).
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

PASS=0; FAIL=0
log()  { printf '%s\n' "$*"; }
pass() { log "PASS: $*"; PASS=$((PASS + 1)); }
fail() { log "FAIL: $*"; FAIL=$((FAIL + 1)); }

bash -n "${SCRIPT_DIR}/test-review-roundcap.sh" 2>/dev/null || { echo "ERROR: self syntax check failed"; exit 1; }
bash -n "${SCRIPTS_ROOT}/leadv2-review-run.sh" 2>/dev/null || fail "bash -n leadv2-review-run.sh"
/bin/bash -n "${SCRIPTS_ROOT}/leadv2-review-run.sh" 2>/dev/null || fail "/bin/bash -n leadv2-review-run.sh (bash 3.2 syntax)"
if command -v shellcheck >/dev/null 2>&1; then
  # SC2094 excluded: the flock pattern here mirrors atomic_review_check_and_record
  # (leadv2-dispatch-code.sh:2556) -- passing the same lockfile path as both the fd-9
  # redirect target and lv2_lock_wait's argument is the documented, safe use of that
  # primitive (leadv2-portable-lock.sh:11), not an actual read/write race.
  # SC2016/SC2004 excluded: pre-existing on this file (backtick-in-single-quote
  # human-readable gate messages, and array-index style in an unrelated
  # arm-tracking loop) -- predate this lane's change, same exclusion added to
  # test-review-round-exhaustive.sh so both suites gate on the same baseline.
  if shellcheck -x -e SC1091,SC2034,SC2094,SC2016,SC2004 "${SCRIPTS_ROOT}/leadv2-review-run.sh" >/dev/null 2>&1; then
    pass "shellcheck clean: leadv2-review-run.sh"
  else
    fail "shellcheck: leadv2-review-run.sh"
  fi
fi
if shellcheck -x "${SCRIPT_DIR}/test-review-roundcap.sh" >/dev/null 2>&1; then
  pass "shellcheck clean: test-review-roundcap.sh"
else
  fail "shellcheck: test-review-roundcap.sh (or shellcheck unavailable)"
fi

STUB_DIR="$(mktemp -d "${TMPDIR:-/tmp}/leadv2-rrc-stubs.XXXXXX")"
trap 'rm -rf "${STUB_DIR}"' EXIT

cat > "${STUB_DIR}/resolver.py" <<'PY'
#!/usr/bin/env python3
print("reviewer=sonnet")
print("pool=sonnet:ok:,opus:ok:")
print("refusal=")
PY
chmod +x "${STUB_DIR}/resolver.py"

cat > "${STUB_DIR}/resolver-empty.py" <<'PY'
#!/usr/bin/env python3
print("reviewer=")
print("pool=")
print("refusal=test_all_arms_unavailable")
PY
chmod +x "${STUB_DIR}/resolver-empty.py"

# architect-ctrl.sh: always FAIL (never converges), so attempts keeps
# incrementing on each real (non-dedup) round instead of stopping at PASS.
# Also appends one line per invocation to CALL_LOG so tests can assert an
# arm was (or was not) actually launched for a given run.
CALL_LOG="${STUB_DIR}/call-log.txt"
: > "${CALL_LOG}"
cat > "${STUB_DIR}/architect-ctrl.sh" <<SH
#!/usr/bin/env bash
role=""
while [[ \$# -gt 0 ]]; do case "\$1" in --role) role="\$2"; shift 2 ;; *) shift ;; esac; done
[[ "\${role}" == "hack-detect" ]] && exit 0
printf '%s\n' "call" >> "${CALL_LOG}"
printf 'REVIEW_VERDICT: FAIL\nREVIEW_FINDINGS: critical=0 high=1 medium=0 low=0\nFINDING: severity=High file=a.sh line=10 dimension=correctness desc=still broken\n'
SH
chmod +x "${STUB_DIR}/architect-ctrl.sh"

cat > "${STUB_DIR}/codex.sh" <<'SH'
#!/usr/bin/env bash
printf 'REVIEW_VERDICT: FAIL\nREVIEW_FINDINGS: critical=0 high=1 medium=0 low=0\n'
SH
chmod +x "${STUB_DIR}/codex.sh"

# dispatch.sh: record-review always succeeds (rc=0) — real, non-dedup round.
cat > "${STUB_DIR}/dispatch.sh" <<'SH'
#!/usr/bin/env bash
exit 0
SH
chmod +x "${STUB_DIR}/dispatch.sh"

# dispatch-dedup.sh: record-review always reports dedup (rc=2) — simulates a
# lane whose diff/verdict are stable so record-review's diff-hash dedup keeps
# firing regardless of what the engine actually computed.
cat > "${STUB_DIR}/dispatch-dedup.sh" <<'SH'
#!/usr/bin/env bash
exit 2
SH
chmod +x "${STUB_DIR}/dispatch-dedup.sh"

# run_rrc <handoff> <diff_file> <task> <errfile> [dispatch_bin] [resolver] [NAME=VAL ...]
run_rrc() {
  local handoff="$1" diff_file="$2" task="$3" errfile="$4"
  local dispatch_bin="${5:-${STUB_DIR}/dispatch.sh}"
  local resolver_bin="${6:-${STUB_DIR}/resolver.py}"
  shift 6 2>/dev/null || shift $#
  local root="${handoff%/docs/handoff/*}"
  mkdir -p "${root}/.claude/ref"
  env "$@" \
  LEADV2_GLM_POLICY_RESOLVER="${resolver_bin}" \
  LEADV2_DISPATCH_ARCHITECT_BIN="${STUB_DIR}/architect-ctrl.sh" \
  LEADV2_DISPATCH_CODEX_BIN="${STUB_DIR}/codex.sh" \
  LEADV2_DISPATCH_BIN="${dispatch_bin}" \
  LEADV2_JOURNAL_BIN=/bin/true \
  LEADV2_REVIEW_FANOUT=1 \
  bash "${SCRIPTS_ROOT}/leadv2-review-run.sh" --task "${task}" --root "${root}" --handoff "${handoff}" --diff "${diff_file}" --author glm >/dev/null 2>"${errfile}"
  return $?
}

new_handoff() { # <task> -> stdout=handoff dir path
  local task="$1"
  local d
  d="$(mktemp -d "${TMPDIR:-/tmp}/leadv2-rrc.XXXXXX")"
  local h="${d}/repo/docs/handoff/dispatch-${task}"
  mkdir -p "${h}"
  printf '%s' "${h}"
}

state_field() { # <state_file> <field>
  sed -n "s/^${2}=//p" "$1" | head -n1
}

# ── T1: round 1 -> attempts=1 ───────────────────────────────────────────────
case_t1() {
  local h; h="$(new_handoff T1RRC)"
  local diff="${h}/review.diff"
  printf 'diff --git a/x b/x\n+v1\n' > "${diff}"
  run_rrc "${h}" "${diff}" T1RRC "${h}.err"
  [[ "$(state_field "${h}/.review-round.state" attempts)" == "1" ]] || return 1
  return 0
}

# ── T2: round 2 -> attempts=2 ───────────────────────────────────────────────
case_t2() {
  local h; h="$(new_handoff T2RRC)"
  local diff="${h}/review.diff"
  printf 'diff --git a/x b/x\n+v1\n' > "${diff}"
  run_rrc "${h}" "${diff}" T2RRC "${h}.err1"
  printf 'diff --git a/x b/x\n+v2\n' > "${diff}"
  run_rrc "${h}" "${diff}" T2RRC "${h}.err2"
  [[ "$(state_field "${h}/.review-round.state" attempts)" == "2" ]] || return 1
  return 0
}

# ── T3: round 3 -> rc8, blocked, review_roundcap, escalation file, no arm ───
case_t3() {
  local h; h="$(new_handoff T3RRC)"
  local diff="${h}/review.diff"
  local calls_before calls_after
  printf 'diff --git a/x b/x\n+v1\n' > "${diff}"
  run_rrc "${h}" "${diff}" T3RRC "${h}.err1"
  printf 'diff --git a/x b/x\n+v2\n' > "${diff}"
  run_rrc "${h}" "${diff}" T3RRC "${h}.err2"
  calls_before="$(wc -l < "${CALL_LOG}" | tr -d '[:space:]')"
  printf 'diff --git a/x b/x\n+v3\n' > "${diff}"
  run_rrc "${h}" "${diff}" T3RRC "${h}.err3"
  local rc=$?
  [[ "${rc}" -eq 8 ]] || return 1
  grep -q '^reason: review_roundcap$' "${h}/review-gate.md" || return 1
  grep -q '^status: blocked$' "${h}/review-gate.md" || return 1
  [[ -f "${h}/review-roundcap-escalation.md" ]] || return 1
  calls_after="$(wc -l < "${CALL_LOG}" | tr -d '[:space:]')"
  [[ "${calls_after}" -eq "${calls_before}" ]] || return 1
  return 0
}

# ── T4: dedup (record-review rc=2) does not increment attempts ─────────────
case_t4() {
  local h; h="$(new_handoff T4RRC)"
  local diff="${h}/review.diff"
  printf 'diff --git a/x b/x\n+v1\n' > "${diff}"
  run_rrc "${h}" "${diff}" T4RRC "${h}.err1" "${STUB_DIR}/dispatch.sh"
  [[ "$(state_field "${h}/.review-round.state" attempts)" == "1" ]] || return 1
  printf 'diff --git a/x b/x\n+v2\n' > "${diff}"
  run_rrc "${h}" "${diff}" T4RRC "${h}.err2" "${STUB_DIR}/dispatch-dedup.sh"
  [[ "$(state_field "${h}/.review-round.state" attempts)" == "1" ]] || return 1
  return 0
}

# ── T5: LEADV2_REVIEW_MAX_ROUNDS=0 at attempts=9 still runs ─────────────────
case_t5() {
  local h; h="$(new_handoff T5RRC)"
  local diff="${h}/review.diff"
  printf 'diff --git a/x b/x\n+v1\n' > "${diff}"
  printf 'round=9\ndiff=deadbeef00\nattempts=9\nspawns=9\n' > "${h}/.review-round.state"
  run_rrc "${h}" "${diff}" T5RRC "${h}.err" "${STUB_DIR}/dispatch.sh" "${STUB_DIR}/resolver.py" LEADV2_REVIEW_MAX_ROUNDS=0
  local rc=$?
  [[ "${rc}" -eq 8 ]] && return 1
  grep -q 'review_roundcap' "${h}/review-gate.md" 2>/dev/null && return 1
  [[ -f "${h}/review-sonnet.md" ]] || return 1
  return 0
}

# ── T6: corrupt attempts=banana fail-opens ──────────────────────────────────
case_t6() {
  local h; h="$(new_handoff T6RRC)"
  local diff="${h}/review.diff"
  printf 'diff --git a/x b/x\n+v1\n' > "${diff}"
  printf 'round=1\ndiff=deadbeef00\nattempts=banana\nspawns=1\n' > "${h}/.review-round.state"
  run_rrc "${h}" "${diff}" T6RRC "${h}.err"
  local rc=$?
  [[ "${rc}" -eq 8 ]] && return 1
  grep -qi 'unbound variable' "${h}.err" && return 1
  [[ -f "${h}/review-sonnet.md" ]] || return 1
  return 0
}

# ── T7: legacy round=3-only state file caps immediately ────────────────────
case_t7() {
  local h; h="$(new_handoff T7RRC)"
  local diff="${h}/review.diff"
  printf 'diff --git a/x b/x\n+v1\n' > "${diff}"
  printf 'round=3\ndiff=deadbeef00\n' > "${h}/.review-round.state"
  run_rrc "${h}" "${diff}" T7RRC "${h}.err"
  local rc=$?
  [[ "${rc}" -eq 8 ]] || return 1
  grep -q '^reason: review_roundcap$' "${h}/review-gate.md" || return 1
  return 0
}

# ── T8: exit 9 (all arms unavailable) leaves attempts unchanged ────────────
case_t8() {
  local h; h="$(new_handoff T8RRC)"
  local diff="${h}/review.diff"
  printf 'diff --git a/x b/x\n+v1\n' > "${diff}"
  printf 'round=1\ndiff=deadbeef00\nattempts=1\nspawns=1\n' > "${h}/.review-round.state"
  run_rrc "${h}" "${diff}" T8RRC "${h}.err" "${STUB_DIR}/dispatch.sh" "${STUB_DIR}/resolver-empty.py"
  local rc=$?
  [[ "${rc}" -eq 9 ]] || return 1
  [[ "$(state_field "${h}/.review-round.state" attempts)" == "1" ]] || return 1
  return 0
}

# ── T9: re-invoke after cap is idempotent ───────────────────────────────────
case_t9() {
  local h; h="$(new_handoff T9RRC)"
  local diff="${h}/review.diff"
  printf 'diff --git a/x b/x\n+v1\n' > "${diff}"
  printf 'round=2\ndiff=deadbeef00\nattempts=2\nspawns=2\n' > "${h}/.review-round.state"
  run_rrc "${h}" "${diff}" T9RRC "${h}.err1"
  local rc1=$?
  run_rrc "${h}" "${diff}" T9RRC "${h}.err2"
  local rc2=$?
  [[ "${rc1}" -eq 8 && "${rc2}" -eq 8 ]] || return 1
  [[ "$(state_field "${h}/.review-round.state" attempts)" == "2" ]] || return 1
  return 0
}

# ── T10: spawn backstop fires when dedup keeps attempts frozen ─────────────
case_t10() {
  local h; h="$(new_handoff T10RRC)"
  local diff="${h}/review.diff"
  printf 'diff --git a/x b/x\n+v1\n' > "${diff}"
  local i
  for i in 1 2 3 4 5 6; do
    run_rrc "${h}" "${diff}" T10RRC "${h}.err${i}" "${STUB_DIR}/dispatch-dedup.sh"
  done
  [[ "$(state_field "${h}/.review-round.state" attempts)" == "0" ]] || return 1
  [[ "$(state_field "${h}/.review-round.state" spawns)" == "6" ]] || return 1
  run_rrc "${h}" "${diff}" T10RRC "${h}.err7" "${STUB_DIR}/dispatch-dedup.sh"
  local rc=$?
  [[ "${rc}" -eq 8 ]] || return 1
  grep -q '^reason: review_spawncap$' "${h}/review-gate.md" || return 1
  return 0
}

# ── T11: state read+increment is lock-guarded, and fails open under contention ──
case_t11() {
  local h; h="$(new_handoff T11RRC)"
  local diff="${h}/review.diff"
  printf 'diff --git a/x b/x\n+v1\n' > "${diff}"
  run_rrc "${h}" "${diff}" T11RRC "${h}.err1"
  # T11a: the lockfile is created only by the guarded read/write path.
  [[ -f "${h}/.review-round.state.lock" ]] || return 1

  # T11b: hold the lock externally past the 1s test budget; the engine must
  # still fail open and complete (attempts still advances).
  local lockf="${h}/.review-round.state.lock"
  local holder_pid=""
  local mkdir_dir="${lockf}.d"
  if command -v flock >/dev/null 2>&1; then
    ( flock -x 9; sleep 3 ) 9>"${lockf}" &
    holder_pid=$!
    sleep 0.3
  else
    mkdir -p "${mkdir_dir}"
    printf '%s' "$$" > "${mkdir_dir}/pid"
  fi

  printf 'diff --git a/x b/x\n+v2\n' > "${diff}"
  run_rrc "${h}" "${diff}" T11RRC "${h}.err2" "${STUB_DIR}/dispatch.sh" "${STUB_DIR}/resolver.py" LEADV2_REVIEW_STATE_LOCK_WAIT_S=1
  local rc=$?

  if [[ -n "${holder_pid}" ]]; then
    wait "${holder_pid}" 2>/dev/null
  else
    rm -rf "${mkdir_dir}"
  fi

  [[ "${rc}" -eq 0 || "${rc}" -eq 7 ]] || return 1
  [[ -f "${h}/review-sonnet.md" ]] || return 1
  return 0
}

if case_t1; then pass "T1 round1 -> attempts=1"; else fail "T1 round1 -> attempts=1"; fi
if case_t2; then pass "T2 round2 -> attempts=2"; else fail "T2 round2 -> attempts=2"; fi
if case_t3; then pass "T3 round3 -> rc8/blocked/review_roundcap, no arm launched"; else fail "T3 round3 -> rc8/blocked/review_roundcap, no arm launched"; fi
if case_t4; then pass "T4 dedup does not increment attempts"; else fail "T4 dedup does not increment attempts"; fi
if case_t5; then pass "T5 LEADV2_REVIEW_MAX_ROUNDS=0 disables cap"; else fail "T5 LEADV2_REVIEW_MAX_ROUNDS=0 disables cap"; fi
if case_t6; then pass "T6 corrupt attempts fails open"; else fail "T6 corrupt attempts fails open"; fi
if case_t7; then pass "T7 legacy round=3-only state caps immediately"; else fail "T7 legacy round=3-only state caps immediately"; fi
if case_t8; then pass "T8 exit 9 leaves attempts unchanged"; else fail "T8 exit 9 leaves attempts unchanged"; fi
if case_t9; then pass "T9 re-invoke after cap is idempotent"; else fail "T9 re-invoke after cap is idempotent"; fi
if case_t10; then pass "T10 spawn backstop fires when dedup keeps attempts frozen"; else fail "T10 spawn backstop fires when dedup keeps attempts frozen"; fi
if case_t11; then pass "T11 state lock taken during increment, fails open under contention"; else fail "T11 state lock taken during increment, fails open under contention"; fi

# ── red-first baseline: these behaviors must not exist against the pre-fix
# engine (no attempts/spawns fields, no exit 8, no roundcap enforcement).
LEADV2_REPO="$(cd "${SCRIPT_DIR}" && git rev-parse --show-toplevel 2>/dev/null)"
PREFIX_DIR="$(mktemp -d "${TMPDIR:-/tmp}/leadv2-rrc-baseline.XXXXXX")"
LEADV2_TEST_BASELINE_REF="${LEADV2_TEST_BASELINE_REF:-}"
if [[ -z "${LEADV2_TEST_BASELINE_REF}" ]]; then
  LEADV2_TEST_BASELINE_REF="$(git -C "${LEADV2_REPO}" merge-base origin/main HEAD 2>/dev/null || true)"
  if [[ -n "${LEADV2_TEST_BASELINE_REF}" ]] && git -C "${LEADV2_REPO}" grep -q review_roundcap "${LEADV2_TEST_BASELINE_REF}" -- plugins/leadv2/scripts/leadv2-review-run.sh 2>/dev/null; then
    LEADV2_TEST_BASELINE_REF="85ae886"
  fi
fi
[[ -n "${LEADV2_TEST_BASELINE_REF}" ]] || LEADV2_TEST_BASELINE_REF="85ae886"
git -C "${LEADV2_REPO}" archive "${LEADV2_TEST_BASELINE_REF}" plugins/leadv2/scripts 2>/dev/null | tar -x -C "${PREFIX_DIR}" 2>/dev/null
PREFIX_SCRIPTS="${PREFIX_DIR}/plugins/leadv2/scripts"

if [[ ! -f "${PREFIX_SCRIPTS}/leadv2-review-run.sh" ]]; then
  fail "T-red: git archive ${LEADV2_TEST_BASELINE_REF} extraction failed"
else
  h="$(new_handoff T3RRCBASE)"
  diff="${h}/review.diff"
  printf 'diff --git a/x b/x\n+v1\n' > "${diff}"
  printf 'round=3\ndiff=deadbeef00\n' > "${h}/.review-round.state"
  root="${h%/docs/handoff/*}"
  mkdir -p "${root}/.claude/ref"
  env LEADV2_GLM_POLICY_RESOLVER="${STUB_DIR}/resolver.py" \
    LEADV2_DISPATCH_ARCHITECT_BIN="${STUB_DIR}/architect-ctrl.sh" \
    LEADV2_DISPATCH_CODEX_BIN="${STUB_DIR}/codex.sh" \
    LEADV2_DISPATCH_BIN="${STUB_DIR}/dispatch.sh" \
    LEADV2_JOURNAL_BIN=/bin/true \
    LEADV2_REVIEW_FANOUT=1 \
    bash "${PREFIX_SCRIPTS}/leadv2-review-run.sh" --task T3RRCBASE --root "${root}" --handoff "${h}" --diff "${diff}" --author glm >/dev/null 2>"${h}.err"
  rc=$?
  if [[ "${rc}" -eq 8 ]]; then
    fail "T-red: baseline ${LEADV2_TEST_BASELINE_REF} unexpectedly exits 8 on legacy round=3 state"
  else
    pass "T-red: baseline ${LEADV2_TEST_BASELINE_REF} does not enforce round cap (rc=${rc})"
  fi
fi
rm -rf "${PREFIX_DIR}"

log ""
log "================================================"
log "  review-roundcap: PASS=$PASS FAIL=$FAIL"
log "================================================"
[[ "$FAIL" -eq 0 ]]
