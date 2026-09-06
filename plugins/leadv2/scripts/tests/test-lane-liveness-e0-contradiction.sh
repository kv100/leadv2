#!/usr/bin/env bash
# run-all-triggers: leadv2-lane-liveness.sh
# test-lane-liveness-e0-contradiction.sh — D2-M5 (D2-SINGLE-LIVENESS-VERDICT
# §3 E0, §6 M5, #14/#15).
#
# E0 is evaluated before every other rung in resolve(): a structural fact
# about the registry that no evidence can rescue. Three independent
# triggers, all decisive -> "unknown:contradictory_rows", never alive,
# never dead:
#   C1: more than one active.yaml row for the same task_id.
#   C2: a row whose worktree == PROJECT_ROOT (the second #14 corruption).
#   C3: one WORKER pid recorded as the owner of two different lanes -- both
#       lanes must resolve contradictory (at most one alive is satisfied
#       trivially: zero).
#   C4 (regression sanity): a normal single-row, single-owner, genuinely
#       live worker lane is UNAFFECTED by the guard and still resolves
#       alive -- E0 must not over-fire on the common case.
#
# Ordering dependency (brief §6 M5): lands only after D1 M1
# (D1-SINGLE-WRITER-FOR-LANE-STATE), which makes duplicate active.yaml rows
# for one task_id impossible to CREATE going forward -- already merged to
# main (commit 1b02faf9) before this suite was written.
set -uo pipefail

export LEADV2_BURN_GOVERNOR=0
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_SCRIPTS="$(cd "${SCRIPT_DIR}/.." && pwd)"
LIVENESS="${PLUGIN_SCRIPTS}/leadv2-lane-liveness.sh"
STATE_PATH="${PLUGIN_SCRIPTS}/leadv2-state-path.sh"

PASS=0; FAIL=0
ok()  { printf '[TEST] PASS: %s\n' "$1"; PASS=$((PASS+1)); }
bad() { printf '[TEST] FAIL: %s\n' "$1" >&2; FAIL=$((FAIL+1)); }

SANDBOX="$(mktemp -d "${TMPDIR:-/tmp}/leadv2-e0-XXXXXX")"
trap 'rm -rf "${SANDBOX}"' EXIT

TARGET="${SANDBOX}/target"
mkdir -p "${TARGET}"
( cd "${TARGET}" && git init -q -b main \
  && git config user.email t@e.com && git config user.name t \
  && printf 'seed\n' > .gitignore && git add .gitignore && git commit -qm seed )

export LEADV2_STATE_ROOT="${SANDBOX}/state"
export LEADV2_STATE_BASE="${SANDBOX}/state"
mkdir -p "${LEADV2_STATE_ROOT}"
ACTIVE="$(PROJECT_ROOT="${TARGET}" LEADV2_STATE_ROOT="${LEADV2_STATE_ROOT}" bash "${STATE_PATH}" active.yaml)"
mkdir -p "$(dirname "${ACTIVE}")"

json_field() {  # <json> <field>
  printf '%s' "$1" | python3 -c '
import sys, json
try:
    print(json.load(sys.stdin).get(sys.argv[1]))
except Exception:
    pass
' "$2" 2>/dev/null || true
}

probe_json() {  # <lane-id> -> json
  LEADV2_PROJECT_ROOT="${TARGET}" LEADV2_STATE_ROOT="${LEADV2_STATE_ROOT}" \
    CODEX_TASK_SH=/bin/false \
    bash "${LIVENESS}" --project-root "${TARGET}" --lane "$1" --no-codex --json
}

stale_stream() {  # <path> <age-s>
  mkdir -p "$(dirname "$1")"
  printf '{"type":"assistant","text":"stale"}\n' > "$1"
  python3 - "$1" "$2" <<'PY'
import os, sys, time
os.utime(sys.argv[1], (time.time() - float(sys.argv[2]),) * 2)
PY
}

# ── C1: two rows for the same task_id ───────────────────────────────────────
TID_C1="E0-C1-DUP-ROWS"
cat > "${ACTIVE}" <<YAML
sessions:
  - task_id: ${TID_C1}
    pid: 1
    started_at: "2020-01-01T00:00:00Z"
  - task_id: ${TID_C1}
    pid: 2
    started_at: "2020-01-01T00:00:01Z"
YAML
j1="$(probe_json "${TID_C1}")"
v1="$(json_field "${j1}" verdict)"
[[ "${v1}" == "unknown:contradictory_rows" ]] \
  && ok "C1: two rows for one task_id -> unknown:contradictory_rows" \
  || bad "C1: expected unknown:contradictory_rows, got '${v1}' (json: ${j1})"

# ── C2: worktree == PROJECT_ROOT ────────────────────────────────────────────
TID_C2="E0-C2-WT-IS-ROOT"
cat > "${ACTIVE}" <<YAML
sessions:
  - task_id: ${TID_C2}
    pid: 1
    started_at: "2020-01-01T00:00:00Z"
    worktree: "${TARGET}"
YAML
j2="$(probe_json "${TID_C2}")"
v2="$(json_field "${j2}" verdict)"
[[ "${v2}" == "unknown:contradictory_rows" ]] \
  && ok "C2: worktree == PROJECT_ROOT -> unknown:contradictory_rows" \
  || bad "C2: expected unknown:contradictory_rows, got '${v2}' (json: ${j2})"

# ── C3: one worker pid owns two lanes ───────────────────────────────────────
TID_C3A="E0-C3-SHARED-PID-A"
TID_C3B="E0-C3-SHARED-PID-B"
BIRTH_NOW="$(ps -o lstart= -p $$ | tr -s ' ' | sed -e 's/^ *//' -e 's/ *$//')"
stale_stream "${TARGET}/docs/handoff/${TID_C3A}/developer.stream.jsonl" 0
stale_stream "${TARGET}/docs/handoff/${TID_C3B}/developer.stream.jsonl" 0
cat > "${ACTIVE}" <<YAML
sessions:
  - task_id: ${TID_C3A}
    pid: $$
    pid_role: lead_durable
    started_at: "2020-01-01T00:00:00Z"
    log_path: docs/handoff/${TID_C3A}/developer.stream.jsonl
    worker_pid: $$
    worker_pid_birth: "${BIRTH_NOW}"
  - task_id: ${TID_C3B}
    pid: $$
    pid_role: lead_durable
    started_at: "2020-01-01T00:00:00Z"
    log_path: docs/handoff/${TID_C3B}/developer.stream.jsonl
    worker_pid: $$
    worker_pid_birth: "${BIRTH_NOW}"
YAML
j3a="$(probe_json "${TID_C3A}")"
j3b="$(probe_json "${TID_C3B}")"
v3a="$(json_field "${j3a}" verdict)"
v3b="$(json_field "${j3b}" verdict)"
[[ "${v3a}" == "unknown:contradictory_rows" ]] \
  && ok "C3a: pid shared by two lanes -> lane A unknown:contradictory_rows" \
  || bad "C3a: expected unknown:contradictory_rows, got '${v3a}' (json: ${j3a})"
[[ "${v3b}" == "unknown:contradictory_rows" ]] \
  && ok "C3b: pid shared by two lanes -> lane B unknown:contradictory_rows" \
  || bad "C3b: expected unknown:contradictory_rows, got '${v3b}' (json: ${j3b})"
if [[ "${v3a}" != "alive" || "${v3b}" != "alive" ]]; then
  ok "C3c: at most one (here: zero) of the two shares-a-pid lanes reads alive"
else
  bad "C3c: both lanes sharing one pid read alive -- violates 'at most one alive'"
fi

# ── C4 (regression sanity): a normal single, distinct-pid lane is unaffected ─
TID_C4="E0-C4-NORMAL-LIVE"
BIRTH_NOW_C4="$(ps -o lstart= -p $$ | tr -s ' ' | sed -e 's/^ *//' -e 's/ *$//')"
stale_stream "${TARGET}/docs/handoff/${TID_C4}/developer.stream.jsonl" 0
cat > "${ACTIVE}" <<YAML
sessions:
  - task_id: ${TID_C4}
    pid: $$
    pid_role: lead_durable
    started_at: "2020-01-01T00:00:00Z"
    log_path: docs/handoff/${TID_C4}/developer.stream.jsonl
    worker_pid: $$
    worker_pid_birth: "${BIRTH_NOW_C4}"
YAML
j4="$(probe_json "${TID_C4}")"
v4="$(json_field "${j4}" verdict)"
[[ "${v4}" == "alive" ]] \
  && ok "C4: a normal single-row live lane still resolves alive (E0 does not over-fire)" \
  || bad "C4: expected alive, got '${v4}' (json: ${j4})"

printf -- '\n=== test-lane-liveness-e0-contradiction.sh: %s passed, %s failed ===\n' "$PASS" "$FAIL"
[[ $FAIL -eq 0 ]]
