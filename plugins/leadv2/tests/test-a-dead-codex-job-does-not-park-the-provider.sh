#!/usr/bin/env bash
# run-all-triggers: leadv2-dispatch-code
# test-a-dead-codex-job-does-not-park-the-provider.sh — CODEX-ALWAYS-UP
# (founder order 2026-09-08: «кодекс доступен всегда»).
#
# Before this lane, every job-death verdict — no_first_byte,
# instant_complete, worker_liveness(vanished_job), worker_liveness
# (turn_aborted) — called `record-quota-lockout --provider codex --hours 1`,
# removing codex from EVERY future selection for an hour. The live store
# read 55 strikes (source standdown:arm_dead_worker_liveness) while the
# quota gate answered `codex 27% < 95%`. None of those verdicts is a
# provider refusal: there is no launcher output to classify, only a dead
# job. A provider lockout is the instrument for "the provider refused us"
# (429 / usage limit), which these are not.
#
# Coverage, all against the REAL dispatcher loaded as a library
# (definitions above the `# ── dispatch ` CLI footer, symlink-populated
# scratch dir so sibling libs resolve to the real files):
#   §1 guard     — a genuine provider refusal (quota_circuit_open with a
#                  stated until=, and a 429/rate_limit shape) STILL parks
#                  codex: lockout record written, read back as a VALUE
#                  (_lockout_state / _provider_available / json fields),
#                  never as a log string.
#   §2 symptom   — worker_liveness vanished_job: rc=7 (job-level spill
#                  contract kept) AND codex selectable afterwards
#                  (_provider_available=0, record absent as a value).
#   §3 symptom   — worker_liveness turn_aborted: same.
#   §4 siblings  — first-byte and instant-complete dead shapes: rc=7 AND
#                  no provider park (the whole arm_dead family, not just
#                  the two named paths).
#   §5 attribution — a sibling lane's NEWEST aborted rollout (different
#                  session_meta.cwd) must not kill this lane's healthy
#                  worker: check proceeds, _codex_newest_rollout_since
#                  returns the OWN rollout.
#   §6 instrument — the stand-down CLI handler itself is NOT disarmed:
#                  cmd_record_quota_lockout --hours still writes a lockout
#                  (the operator's manual instrument for a genuinely down
#                  runtime).
#
# LEADV2_DISPATCH_UNDER_TEST overrides the dispatcher under test (used for
# the red-first proof against the pristine pre-fix file).
# Fixture-only: stubbed codex bin, sandboxed CODEX_HOME and lockout dir.
# Never a live provider, never a real spawn.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "${HERE}/.." && pwd)"
SCRIPTS_DIR="${PLUGIN_ROOT}/scripts"
DISPATCH="${LEADV2_DISPATCH_UNDER_TEST:-${SCRIPTS_DIR}/leadv2-dispatch-code.sh}"

PASS=0; FAIL=0
pass(){ printf 'PASS: %s\n' "$1"; PASS=$((PASS+1)); }
fail(){ printf 'FAIL: %s\n' "$1" >&2; FAIL=$((FAIL+1)); }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/leadv2-codex-always-up.XXXXXX")"
cleanup(){ rm -rf "${TMP}"; }
trap cleanup EXIT

# ── scratch dir: symlink every real sibling, materialise only the awked ──────
# dispatcher body as dispatch-lib.sh (definitions only, no CLI footer).
LIB_DIR="${TMP}/scripts"
mkdir -p "${LIB_DIR}"
for _entry in "${SCRIPTS_DIR}"/*; do
  _base="$(basename "${_entry}")"
  [[ "${_base}" == "leadv2-dispatch-code.sh" ]] && continue
  ln -s "${_entry}" "${LIB_DIR}/${_base}"
done
# The dispatcher under test itself IS symlinked into the scratch dir (unlike
# A4's harness, which skipped it): the pre-fix dead-verdict lockout write is a
# SUBPROCESS `bash ${DISPATCH_SELF_BIN:-${SCRIPT_DIR}/leadv2-dispatch-code.sh}
# record-quota-lockout ...` — without this symlink the fallback path resolves
# to nothing, the write fails silently, and a pristine-code red-first run
# stays vacuously green.
ln -s "${DISPATCH}" "${LIB_DIR}/leadv2-dispatch-code.sh"
awk '/^# ── dispatch / { exit } { print }' "$DISPATCH" > "${LIB_DIR}/dispatch-lib.sh"
LIB_SH="${LIB_DIR}/dispatch-lib.sh"

# run_lib <env-assignments...> -- <body>: source the real dispatcher body,
# neutralise journalling, run the body. Lockout dir is ALWAYS a fresh
# sandbox so a verdict's write (or absence) is observed in isolation.
run_lib() {
  local envs=() body=""
  while [[ $# -gt 0 ]]; do
    [[ "$1" == "--" ]] && { shift; body="$*"; break; }
    envs+=("$1"); shift
  done
  env "${envs[@]}" CLAUDE_PROJECT_ROOT="${TMP}/own-lane" LIB_SH="${LIB_SH}" bash -c '
    set -uo pipefail
    source "${LIB_SH}"
    emit() { :; }
    log() { :; }
    log_err() { :; }
    '"${body}"'
  '
}

# ── stub codex bin: status <handle> shapes only; log stays empty ─────────────
cat > "${TMP}/codex-vanished.sh" <<'EOF'
#!/usr/bin/env bash
if [[ "${1:-}" == "status" ]]; then echo "No job found for ${2:-}" >&2; exit 1; fi
exit 0
EOF
cat > "${TMP}/codex-alive.sh" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
cat > "${TMP}/codex-silent.sh" <<'EOF'
#!/usr/bin/env bash
# first-byte probe: `log <handle>` prints nothing -> probe never succeeds
exit 0
EOF
chmod +x "${TMP}"/codex-*.sh

NOW="$(date +%s)"
SINCE=$(( NOW - 10 ))
OWN_CWD="${TMP}/own-lane"
SIB_CWD="${TMP}/sibling-lane"
mkdir -p "${OWN_CWD}" "${SIB_CWD}"

write_rollout() {  # <path> <mtime_epoch> <lines...>
  local path="$1" mtime="$2"; shift 2
  printf '%s\n' "$@" > "${path}"
  python3 -c "import os,sys; os.utime(sys.argv[1], (int(sys.argv[2]), int(sys.argv[2])))" "${path}" "${mtime}"
}

make_sessions() {  # <codex_home>
  mkdir -p "$1/sessions/2026/09/08"
}

# ── §1 GUARD: a genuine provider refusal still parks codex ──────────────────
fresh_dir() { mktemp -d "${TMP}/lockout.XXXXXX"; }

G1_DIR="$(fresh_dir)"
G1_ISO="$(date -u -v+10M +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -d '+10 minutes' +%Y-%m-%dT%H:%M:%SZ)"
g1_out="$(run_lib "LEADV2_QUOTA_LOCKOUT_DIR=${G1_DIR}" -- '
  _maybe_record_quota_lockout codex quota_circuit_open "CODEX_REFUSED_QUOTA usage_limit until='"${G1_ISO}"'"
  printf "%s|%s\n" "$(_lockout_state codex)" "$(_provider_available codex && echo avail || echo locked)"
  python3 -c "import json;d=json.load(open(\"${QUOTA_LOCKOUT_DIR}/quota-lockout-codex.json\"));print(d[\"class\"],int(d[\"locked_until_epoch\"]))"
')"
g1_state="$(printf '%s\n' "${g1_out}" | grep -m1 -E '^locked [0-9]+\|locked$')"
g1_class="$(printf '%s\n' "${g1_out}" | grep -m1 -E '^provider_refusal [0-9]+$' | awk '{print $1}')"
g1_epoch="$(printf '%s\n' "${g1_out}" | grep -m1 -E '^provider_refusal [0-9]+$' | awk '{print $2}')"
if [[ "${g1_state}" == "locked "*"|locked" && "${g1_class}" == "provider_refusal" && -n "${g1_epoch}" && "${g1_epoch}" -gt "${NOW}" ]]; then
  pass "S1 usage-limit refusal (quota_circuit_open) parks codex: state=[${g1_state}] class=${g1_class} until_epoch=${g1_epoch}>now"
else
  fail "S1 usage-limit refusal must park codex, got state=[${g1_state}] class=${g1_class} epoch=${g1_epoch}"
fi

G2_DIR="$(fresh_dir)"
g2_out="$(run_lib "LEADV2_QUOTA_LOCKOUT_DIR=${G2_DIR}" -- '
  _maybe_record_quota_lockout codex rate_limit "Error: 429 Too Many Requests. Try again at 2026-09-08T23:00:00Z."
  printf "%s\n" "$(_lockout_state codex)"
')"
if [[ "${g2_out}" == "locked "* ]]; then
  pass "S2 429/rate_limit refusal parks codex: state=[${g2_out}]"
else
  fail "S2 429/rate_limit refusal must park codex, got [${g2_out}]"
fi

# ── §2 SYMPTOM: worker_liveness vanished_job — spill, no provider park ───────
V_DIR="$(fresh_dir)"
v_rc="$(run_lib "LEADV2_QUOTA_LOCKOUT_DIR=${V_DIR}" "LEADV2_DISPATCH_CODEX_BIN=${TMP}/codex-vanished.sh" "CODEX_HOME=${TMP}/empty-home" -- '
  mkdir -p "${CODEX_HOME}/sessions"
  _codex_worker_liveness_deadline_check job-vanish01 testsig8 '"${SINCE}"' "'"${OWN_CWD}"'"
  echo "rc=$?"
  printf "%s|%s\n" "$(_lockout_state codex)" "$(_provider_available codex >/dev/null 2>&1 && echo avail || echo locked)"
  [[ -f "${QUOTA_LOCKOUT_DIR}/quota-lockout-codex.json" ]] && echo file=present || echo file=absent
')"
v_rcode="$(printf '%s\n' "${v_rc}" | sed -n 's/^rc=//p')"
v_state="$(printf '%s\n' "${v_rc}" | grep -m1 -E '^[a-z]+( [0-9]+)?\|(avail|locked)$')"
v_file="$(printf '%s\n' "${v_rc}" | grep -m1 '^file=')"
if [[ "${v_rcode}" == "7" && "${v_state}" == "absent|avail" && "${v_file}" == "file=absent" ]]; then
  pass "S2 vanished_job: rc=7 spill kept, codex selectable (${v_state}, record ${v_file})"
else
  fail "S2 vanished_job: want rc=7 + absent|avail + file=absent, got rc=${v_rcode} [${v_state}] ${v_file}"
fi

# ── §3 SYMPTOM: worker_liveness turn_aborted — spill, no provider park ───────
T_HOME="${TMP}/turn-aborted-home"; make_sessions "${T_HOME}"
write_rollout "${T_HOME}/sessions/2026/09/08/rollout-2026-09-08T10-00-00-own.jsonl" "$(( NOW - 5 ))" \
  '{"type":"session_meta","payload":{"cwd":"'"${OWN_CWD}"'","originator":"codex-cli"}}' \
  '{"type":"event_msg","payload":{"type":"task_started"}}' \
  '{"type":"event_msg","payload":{"type":"turn_aborted","reason":"interrupted"}}'
T_DIR="$(fresh_dir)"
t_rc="$(run_lib "LEADV2_QUOTA_LOCKOUT_DIR=${T_DIR}" "LEADV2_DISPATCH_CODEX_BIN=${TMP}/codex-alive.sh" "CODEX_HOME=${T_HOME}" -- '
  _codex_worker_liveness_deadline_check job-abort01 testsig8 '"${SINCE}"' "'"${OWN_CWD}"'"
  echo "rc=$?"
  printf "%s|%s\n" "$(_lockout_state codex)" "$(_provider_available codex >/dev/null 2>&1 && echo avail || echo locked)"
  [[ -f "${QUOTA_LOCKOUT_DIR}/quota-lockout-codex.json" ]] && echo file=present || echo file=absent
')"
t_rcode="$(printf '%s\n' "${t_rc}" | sed -n 's/^rc=//p')"
t_state="$(printf '%s\n' "${t_rc}" | grep -m1 -E '^[a-z]+( [0-9]+)?\|(avail|locked)$')"
t_file="$(printf '%s\n' "${t_rc}" | grep -m1 '^file=')"
if [[ "${t_rcode}" == "7" && "${t_state}" == "absent|avail" && "${t_file}" == "file=absent" ]]; then
  pass "S3 turn_aborted: rc=7 spill kept, codex selectable (${t_state}, record ${t_file})"
else
  fail "S3 turn_aborted: want rc=7 + absent|avail + file=absent, got rc=${t_rcode} [${t_state}] ${t_file}"
fi

# ── §4 SIBLINGS: first-byte and instant-complete dead shapes park nothing ────
F_DIR="$(fresh_dir)"
f_rc="$(run_lib "LEADV2_QUOTA_LOCKOUT_DIR=${F_DIR}" "LEADV2_DISPATCH_CODEX_BIN=${TMP}/codex-silent.sh" "CODEX_HOME=${TMP}/empty-home" "LEADV2_CODEX_FIRST_BYTE_SECS=1" "LEADV2_ARM_EARLY_VERDICT_POLL_S=0.1" -- '
  mkdir -p "${CODEX_HOME}/sessions"
  _codex_first_byte_deadline_check job-fb01 testsig8
  echo "rc=$?"
  printf "%s|%s\n" "$(_lockout_state codex)" "$(_provider_available codex >/dev/null 2>&1 && echo avail || echo locked)"
')"
f_rcode="$(printf '%s\n' "${f_rc}" | sed -n 's/^rc=//p')"
f_state="$(printf '%s\n' "${f_rc}" | grep -m1 -E '^[a-z]+( [0-9]+)?\|(avail|locked)$')"
if [[ "${f_rcode}" == "7" && "${f_state}" == "absent|avail" ]]; then
  pass "S4a no_first_byte: rc=7 spill kept, codex selectable (${f_state})"
else
  fail "S4a no_first_byte: want rc=7 + absent|avail, got rc=${f_rcode} [${f_state}]"
fi

I_HOME="${TMP}/instant-home"; make_sessions "${I_HOME}"
write_rollout "${I_HOME}/sessions/2026/09/08/rollout-2026-09-08T10-05-00-null.jsonl" "$(( NOW - 5 ))" \
  '{"type":"session_meta","payload":{"cwd":"'"${OWN_CWD}"'","originator":"codex-cli"}}' \
  '{"type":"event_msg","payload":{"type":"task_started"}}' \
  '{"type":"event_msg","payload":{"type":"task_complete","last_agent_message":null,"duration_ms":946}}'
I_DIR="$(fresh_dir)"
i_rc="$(run_lib "LEADV2_QUOTA_LOCKOUT_DIR=${I_DIR}" "LEADV2_DISPATCH_CODEX_BIN=${TMP}/codex-alive.sh" "CODEX_HOME=${I_HOME}" "LEADV2_CODEX_INSTANT_COMPLETE_SECS=5" "LEADV2_ARM_EARLY_VERDICT_POLL_S=0.1" -- '
  _codex_instant_complete_deadline_check testsig8 '"${SINCE}"' "'"${OWN_CWD}"'"
  echo "rc=$?"
  printf "%s|%s\n" "$(_lockout_state codex)" "$(_provider_available codex >/dev/null 2>&1 && echo avail || echo locked)"
')"
i_rcode="$(printf '%s\n' "${i_rc}" | sed -n 's/^rc=//p')"
i_state="$(printf '%s\n' "${i_rc}" | grep -m1 -E '^[a-z]+( [0-9]+)?\|(avail|locked)$')"
if [[ "${i_rcode}" == "7" && "${i_state}" == "absent|avail" ]]; then
  pass "S4b instant_complete: rc=7 spill kept, codex selectable (${i_state})"
else
  fail "S4b instant_complete: want rc=7 + absent|avail, got rc=${i_rcode} [${i_state}]"
fi

# ── §5 ATTRIBUTION: a sibling lane's aborted rollout must not kill ours ─────
A_HOME="${TMP}/attribution-home"; make_sessions "${A_HOME}"
# the SIBLING rollout is NEWER (mtime now-2 > own now-5) and carries the dead
# shape — a bare newest-of-window scan would pick it and spill our healthy
# worker (the B4 `candidates=2` shape, up to 8 concurrent lanes).
write_rollout "${A_HOME}/sessions/2026/09/08/rollout-2026-09-08T10-10-00-sibling.jsonl" "$(( NOW - 2 ))" \
  '{"type":"session_meta","payload":{"cwd":"'"${SIB_CWD}"'","originator":"codex-cli"}}' \
  '{"type":"event_msg","payload":{"type":"task_started"}}' \
  '{"type":"event_msg","payload":{"type":"turn_aborted","reason":"interrupted"}}'
write_rollout "${A_HOME}/sessions/2026/09/08/rollout-2026-09-08T10-09-00-own.jsonl" "$(( NOW - 5 ))" \
  '{"type":"session_meta","payload":{"cwd":"'"${OWN_CWD}"'","originator":"codex-cli"}}' \
  '{"type":"event_msg","payload":{"type":"task_started"}}' \
  '{"type":"event_msg","payload":{"type":"agent_message","payload":"working on it"}}'
A_DIR="$(fresh_dir)"
a_rc="$(run_lib "LEADV2_QUOTA_LOCKOUT_DIR=${A_DIR}" "LEADV2_DISPATCH_CODEX_BIN=${TMP}/codex-alive.sh" "CODEX_HOME=${A_HOME}" -- '
  scan="$(_codex_newest_rollout_since '"${SINCE}"' "'"${OWN_CWD}"'")"
  printf "picked=%s\n" "$(printf "%s\n" "${scan}" | sed -n 1p)"
  _codex_worker_liveness_deadline_check job-attr01 testsig8 '"${SINCE}"' "'"${OWN_CWD}"'"
  echo "rc=$?"
  printf "%s|%s\n" "$(_lockout_state codex)" "$(_provider_available codex >/dev/null 2>&1 && echo avail || echo locked)"
')"
a_picked="$(printf '%s\n' "${a_rc}" | sed -n 's/^picked=//p')"
a_rcode="$(printf '%s\n' "${a_rc}" | sed -n 's/^rc=//p')"
a_state="$(printf '%s\n' "${a_rc}" | grep -m1 -E '^[a-z]+( [0-9]+)?\|(avail|locked)$')"
if [[ "${a_picked}" == *"-own.jsonl" && "${a_rcode}" == "0" && "${a_state}" == "absent|avail" ]]; then
  pass "S5 attribution: cwd filter picked own rollout, sibling's aborted turn did not spill (rc=0, ${a_state})"
else
  fail "S5 attribution: want own rollout + rc=0 + absent|avail, got picked=${a_picked##*/} rc=${a_rcode} [${a_state}]"
fi

# ── §6 INSTRUMENT: the stand-down writer itself is not disarmed ──────────────
M_DIR="$(fresh_dir)"
m_rc="$(run_lib "LEADV2_QUOTA_LOCKOUT_DIR=${M_DIR}" -- '
  ( cmd_record_quota_lockout --provider codex --hours 1 --reason manual_operator_standdown ) >/dev/null 2>&1
  printf "%s\n" "$(_lockout_state codex)"
')"
if [[ "${m_rc}" == "locked "* ]]; then
  pass "S6 stand-down instrument still arms on an explicit operator assertion: [${m_rc}]"
else
  fail "S6 stand-down CLI handler must still write a lockout, got [${m_rc}]"
fi

printf 'suite=codex-always-up pass=%d fail=%d\n' "${PASS}" "${FAIL}"
[[ "${FAIL}" -eq 0 ]]
