#!/usr/bin/env bash
# LANE-REGISTRY-SELF-DEADLOCK-01 — a lane whose worker died could never be
# re-dispatched: active.yaml recorded the LEAD's pid (alive by definition)
# and a fresh architect-prepass stream (written synchronously by the dispatch
# attempt itself) counted as a live signal. Fix under test:
#   (a) pid_role=lead_durable row + live lead pid + stale worker stream ->
#       dead:* (reclaimable) -- the deadlock-breaker.
#   (b) worker_pid alive but birth mismatch (recycled pid) -> dead:* with
#       pid_identity=mismatch.
#   (c) a REFUSED --resume-lane attempt journals but refreshes NO file the
#       liveness probe reads (verdict/reason/source byte-identical before and
#       after, mtime census unchanged).
#   (d) a genuinely-live worker row (worker_pid $$ + real birth + fresh
#       stream) -> alive, and the dispatcher's --resume-lane refusal exits 5
#       with `lane_liveness verdict=live ... signal=stream_fresh` journaled.
#
# Fixtures only -- no real spawns (LEADV2_DISPATCH_SPAWN=0 on every dispatch,
# and every refusal exits at the placement gate before any spawn). bash 3.2.
set -uo pipefail

# BURN-GOVERNOR-01: the burn gate defaults ON and reads the host's real
# ~/.claude/burn/history.db -- a hot host would red this suite on `exit 6`.
export LEADV2_BURN_GOVERNOR=0
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_SCRIPTS="$(cd "${SCRIPT_DIR}/.." && pwd)"
DC="${PLUGIN_SCRIPTS}/leadv2-dispatch-code.sh"
LIVENESS="${PLUGIN_SCRIPTS}/leadv2-lane-liveness.sh"
STATE_PATH="${PLUGIN_SCRIPTS}/leadv2-state-path.sh"
JOURNAL_BIN="${PLUGIN_SCRIPTS}/leadv2-journal.sh"

PASS=0; FAIL=0
ok()  { printf '[TEST] PASS: %s\n' "$1"; PASS=$((PASS+1)); }
bad() { printf '[TEST] FAIL: %s\n' "$1" >&2; FAIL=$((FAIL+1)); }

SANDBOX="$(mktemp -d /tmp/leadv2-lrsd-XXXXXX)"
trap 'rm -rf "${SANDBOX}"' EXIT

# ── Fixture repo + lane worktree (same shape as test-lane-placement-pin.sh) ──
TARGET="${SANDBOX}/target"
mkdir -p "${TARGET}"
( cd "${TARGET}" && git init -q -b main \
  && git config user.email t@e.com && git config user.name t \
  && printf 'seed\n' > .gitignore && git add .gitignore && git commit -qm seed )

LANE_KEY="DEADLANE01"
RESUME_WT="${TARGET}/.claude/worktrees/${LANE_KEY}"
mkdir -p "$(dirname "${RESUME_WT}")"
( cd "${TARGET}" && git worktree add -q "${RESUME_WT}" -b "worktree-${LANE_KEY}" ) 2>/dev/null
( cd "${RESUME_WT}" && printf 'lane work\n' > lane.txt && git add lane.txt && git commit -qm lane-seed )

# Sandbox state root so active.yaml/tombstones resolve inside the sandbox,
# never the real control plane (same isolation as test-lane-liveness-authoritative).
export LEADV2_STATE_ROOT="${SANDBOX}/state"
export LEADV2_STATE_BASE="${SANDBOX}/state"
export LEADV2_DISPATCH_CACHE_DIR="${SANDBOX}/cache"
mkdir -p "${LEADV2_STATE_ROOT}" "${LEADV2_DISPATCH_CACHE_DIR}"
ACTIVE="$(PROJECT_ROOT="${TARGET}" LEADV2_STATE_ROOT="${LEADV2_STATE_ROOT}" bash "${STATE_PATH}" active.yaml)"
mkdir -p "$(dirname "${ACTIVE}")"
printf 'sessions: []\n' > "$ACTIVE"

export CLAUDE_PROJECT_DIR="${TARGET}"
export CLAUDE_PROJECT_ROOT="${TARGET}"
unset PROJECT_ROOT 2>/dev/null || true
unset LEADV2_LANE_WORK_ROOT 2>/dev/null || true
export LEADV2_ROUTER_V2=0
export GLM_POLICY_RESOLVER=""
export LEADV2_LANE_SHAPE=off
export LEADV2_DISPATCH_E2E_GATE=0
export LEADV2_DISPATCH_REVIEW_GATE=0
export LEADV2_DISPATCH_ARCHITECT_GATE=0
export LEADV2_DISPATCH_SPAWN=0
export LEADV2_DISPATCH_PENDING_TTL_S=5
export LEADV2_DISPATCH_CONFIRMED_TTL_S=10
export LEADV2_DISPATCH_LEDGER_BIN="${PLUGIN_SCRIPTS}/leadv2-dispatch-ledger.sh"
export LEADV2_STATE_PATH_BIN="${STATE_PATH}"
# Real liveness probe (the code under test), real journal (a refusal must
# journal -- deliverable #2), stub glm launcher so nothing can really spawn.
GLM_STUB="${SANDBOX}/glm-stub.sh"
cat > "${GLM_STUB}" <<'SH'
#!/usr/bin/env bash
exit 1
SH
export LEADV2_DISPATCH_GLM_BIN="${GLM_STUB}"

probe() {  # <lane-id> [extra env via caller] -> verdict string
  LEADV2_PROJECT_ROOT="${TARGET}" LEADV2_STATE_ROOT="${LEADV2_STATE_ROOT}" \
    CODEX_TASK_SH=/bin/false \
    bash "${LIVENESS}" --project-root "${TARGET}" --lane "$1" --no-codex
}
probe_json() {
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

json_field() {  # <json> <field>
  printf '%s' "$1" | python3 -c '
import sys, json
try:
    print(json.load(sys.stdin).get(sys.argv[1]))
except Exception:
    pass
' "$2" 2>/dev/null || true
}

OLD_TS="2020-01-01T00:00:00Z"

# ════════════════════════════════════════════════════════════════════════════
# (a) lead_durable row + LIVE lead pid ($$) + stale worker stream -> dead:*
#     Pre-fix this lane is silent: forever (lead pid alive by definition).
# ════════════════════════════════════════════════════════════════════════════
TID_A="dispatch-aaaaaaaa"
stale_stream "${TARGET}/docs/handoff/${TID_A}/developer.stream.jsonl" 1800
cat > "$ACTIVE" <<YAML
sessions:
  - task_id: ${TID_A}
    pid: $$
    pid_role: lead_durable
    started_at: "${OLD_TS}"
    log_path: docs/handoff/${TID_A}/developer.stream.jsonl
YAML
v_a="$(probe "${TID_A}")"
j_a="$(probe_json "${TID_A}")"
if [[ "${v_a}" == dead:* ]]; then
  ok "(a) lead_durable row + live lead pid + stale stream -> ${v_a} (reclaimable)"
else
  bad "(a) expected dead:*, got '${v_a}' (json: ${j_a})"
fi
[[ "$(json_field "${j_a}" pid_source)" == "lead_durable" ]] \
  && ok "(a) pid_source=lead_durable recorded" \
  || bad "(a) pid_source='$(json_field "${j_a}" pid_source)' != lead_durable"

# ════════════════════════════════════════════════════════════════════════════
# (b) worker_pid alive but birth mismatch (recycled pid) -> dead:*, mismatch.
#     NOTE (design §5.4 fixture corrected): the design's literal
#     "Jan  1 00:00:00 2000" is NOT a well-formed `ps -o lstart=` value (no
#     weekday token -- ps always emits "Mon Jan  1 ..."), so per §3.1 it must
#     degrade to unverified, never mismatch. A GENUINE mismatch needs a
#     well-formed-but-different birth: "Mon Jan  1 00:00:00 2000".
# ════════════════════════════════════════════════════════════════════════════
TID_B="dispatch-bbbbbbbb"
stale_stream "${TARGET}/docs/handoff/${TID_B}/developer.stream.jsonl" 1800
cat > "$ACTIVE" <<YAML
sessions:
  - task_id: ${TID_B}
    pid: $$
    pid_role: lead_durable
    started_at: "${OLD_TS}"
    log_path: docs/handoff/${TID_B}/developer.stream.jsonl
    worker_pid: $$
    worker_pid_birth: "Mon Jan  1 00:00:00 2000"
YAML
v_b="$(probe "${TID_B}")"
j_b="$(probe_json "${TID_B}")"
if [[ "${v_b}" == dead:* ]]; then
  ok "(b) recycled-pid row (pid alive, birth mismatch) -> ${v_b} (reclaimable)"
else
  bad "(b) expected dead:*, got '${v_b}' (json: ${j_b})"
fi
[[ "$(json_field "${j_b}" pid_identity)" == "mismatch" ]] \
  && ok "(b) pid_identity=mismatch recorded" \
  || bad "(b) pid_identity='$(json_field "${j_b}" pid_identity)' != mismatch"

# (b2) §3.1 malformed-birth boundary: a birth ps can never produce degrades
# to unverified + bare kill -0 -- never to dead. A live worker pid with a
# garbage birth string must keep the lane silent, not reclaim it.
TID_B2="dispatch-b2b2b2b2"
stale_stream "${TARGET}/docs/handoff/${TID_B2}/developer.stream.jsonl" 1800
cat > "$ACTIVE" <<YAML
sessions:
  - task_id: ${TID_B2}
    pid: $$
    pid_role: lead_durable
    started_at: "${OLD_TS}"
    log_path: docs/handoff/${TID_B2}/developer.stream.jsonl
    worker_pid: $$
    worker_pid_birth: "not a lstart at all"
YAML
v_b2="$(probe "${TID_B2}")"
j_b2="$(probe_json "${TID_B2}")"
if [[ "${v_b2}" == silent:* ]]; then
  ok "(b2) malformed birth -> unverified, lane stays ${v_b2} (never dead)"
else
  bad "(b2) malformed birth produced '${v_b2}' (expected silent:*, json: ${j_b2})"
fi
[[ "$(json_field "${j_b2}" pid_identity)" == "unverified" ]] \
  && ok "(b2) pid_identity=unverified recorded" \
  || bad "(b2) pid_identity='$(json_field "${j_b2}" pid_identity)' != unverified"

# ════════════════════════════════════════════════════════════════════════════
# (c) refusal idempotence: a LIVE lane (fresh worker stream + fresh prepass
#     residue) refuses the re-dispatch (rc 5); the refusal journals but must
#     not refresh any file the probe reads. Byte-identical verdict/reason/
#     source before and after, mtime census unchanged.
# ════════════════════════════════════════════════════════════════════════════
# dispatch-<key> is the first id spelling step 5 probes
TID_C="dispatch-$(printf '%s' "${LANE_KEY}" | tr 'A-Z' 'a-z')"
stale_stream "${TARGET}/docs/handoff/${TID_C}/developer.stream.jsonl" 0
# prepass residue, FRESH -- under the old default this alone flipped the lane
# to starting:<age> and every retry loop chasing a self-refreshed probe.
mkdir -p "${TARGET}/docs/handoff/${TID_C}-architect"
printf '{"type":"assistant"}\n' > "${TARGET}/docs/handoff/${TID_C}-architect/architect.stream.jsonl"
cat > "$ACTIVE" <<YAML
sessions:
  - task_id: ${TID_C}
    pid: $$
    pid_role: lead_durable
    started_at: "${OLD_TS}"
    log_path: docs/handoff/${TID_C}/developer.stream.jsonl
YAML
before_c="$(probe_json "${TID_C}")"
census() {  # mtime+size of every file the probe reads for this lane
  find "${TARGET}/docs/handoff/${TID_C}" "${TARGET}/docs/handoff/${TID_C}-architect" \
    -type f 2>/dev/null | sort | while read -r f; do
    stat -f '%m %z %N' "$f" 2>/dev/null || stat -c '%Y %s %n' "$f" 2>/dev/null
  done
  stat -f '%m %z %N' "$ACTIVE" 2>/dev/null || stat -c '%Y %s %n' "$ACTIVE" 2>/dev/null
}
census_before="$(census)"
sleep 2
rc_c=0
bash "${DC}" --kind tooling --resume-lane "${LANE_KEY}" \
  "LRSD c refusal idempotence probe test" >/dev/null 2>"${SANDBOX}/c-stderr.txt" || rc_c=$?
[[ ${rc_c} -eq 5 ]] && ok "(c) live lane refuses the re-dispatch (rc 5)" \
  || bad "(c) expected rc 5, got ${rc_c} (stderr: $(tail -3 "${SANDBOX}/c-stderr.txt" 2>/dev/null))"
after_c="$(probe_json "${TID_C}")"
v_before="$(json_field "${before_c}" verdict)"; r_before="$(json_field "${before_c}" reason)"; s_before="$(json_field "${before_c}" source)"
v_after="$(json_field "${after_c}" verdict)";  r_after="$(json_field "${after_c}" reason)";  s_after="$(json_field "${after_c}" source)"
if [[ "${v_before}" == "${v_after}" && "${r_before}" == "${r_after}" && "${s_before}" == "${s_after}" ]]; then
  ok "(c) verdict/reason/source byte-identical across the refused attempt (${v_before}/${r_before})"
else
  bad "(c) probe drift: before='${v_before}/${r_before}/${s_before}' after='${v_after}/${r_after}/${s_after}'"
fi
census_after="$(census)"
if [[ "${census_before}" == "${census_after}" ]]; then
  ok "(c) no probe-read file changed mtime/size across the refusal"
else
  bad "(c) probe-read file set changed:
before:
${census_before}
after:
${census_after}"
fi
# The refusal MUST have journaled -- that is the deliverable, and it proves the
# census above covers an attempt that actually ran (journal.md itself is NOT a
# liveness input -- design §0.1).
if grep -rqs 'lane_placement_refused' "${TARGET}/docs/leadv2/tasks/"*/journal.md 2>/dev/null; then
  ok "(c) refusal journaled (lane_placement_refused in task journal)"
else
  bad "(c) refusal never journaled -- attempt did not run the refusal path"
fi

# ════════════════════════════════════════════════════════════════════════════
# (d) genuinely live worker: worker_pid $$ + real captured birth + stream
#     touched now -> alive; --resume-lane exits 5 with the lane_liveness
#     verdict=live signal=stream_fresh line journaled.
# ════════════════════════════════════════════════════════════════════════════
BIRTH_NOW="$(ps -o lstart= -p $$ | tr -s ' ' | sed -e 's/^ *//' -e 's/ *$//')"
stale_stream "${TARGET}/docs/handoff/${TID_C}/developer.stream.jsonl" 0
cat > "$ACTIVE" <<YAML
sessions:
  - task_id: ${TID_C}
    pid: $$
    pid_role: lead_durable
    started_at: "${OLD_TS}"
    log_path: docs/handoff/${TID_C}/developer.stream.jsonl
    worker_pid: $$
    worker_pid_birth: "${BIRTH_NOW}"
YAML
v_d="$(probe "${TID_C}")"
j_d="$(probe_json "${TID_C}")"
[[ "${v_d}" == "alive" ]] && ok "(d) live worker row resolves alive" \
  || bad "(d) expected alive, got '${v_d}' (json: ${j_d})"
[[ "$(json_field "${j_d}" pid_source)" == "worker" && "$(json_field "${j_d}" pid_identity)" == "verified" ]] \
  && ok "(d) pid_source=worker pid_identity=verified" \
  || bad "(d) pid_source='$(json_field "${j_d}" pid_source)' pid_identity='$(json_field "${j_d}" pid_identity)'"
rc_d=0
bash "${DC}" --kind tooling --resume-lane "${LANE_KEY}" \
  "LRSD d live lane refusal journal test" >/dev/null 2>"${SANDBOX}/d-stderr.txt" || rc_d=$?
[[ ${rc_d} -eq 5 ]] && ok "(d) live worker lane refuses the re-dispatch (rc 5)" \
  || bad "(d) expected rc 5, got ${rc_d}"
if grep -rqs 'lane_liveness verdict=live.*signal=stream_fresh' "${TARGET}/docs/leadv2/tasks/"*/journal.md 2>/dev/null; then
  ok "(d) journal carries lane_liveness verdict=live signal=stream_fresh"
else
  bad "(d) journal missing the lane_liveness verdict=live line"
fi

# ════════════════════════════════════════════════════════════════════════════
# (R2) argv-unpack lockstep smoke (design §6 R2): the liveness heredoc's
# sys.argv tuple now has 18 slots; editing the invocation and the unpack out
# of lockstep raises ValueError on EVERY call and silently degrades every
# consumer -- bash -n cannot catch it. One live --all --json pass against
# the REAL repo root proves the unpack holds end to end.
# ════════════════════════════════════════════════════════════════════════════
REAL_ROOT="$(cd "${PLUGIN_SCRIPTS}/../.." && pwd)"
smoke="$(LEADV2_PROJECT_ROOT="${REAL_ROOT}" CODEX_TASK_SH=/bin/false \
  bash "${LIVENESS}" --project-root "${REAL_ROOT}" --all --json --no-codex 2>/dev/null)" && rc_s=0 || rc_s=$?
if [[ ${rc_s} -eq 0 && -n "${smoke}" ]] \
   && printf '%s' "${smoke}" | python3 -c '
import json, sys
d = json.load(sys.stdin)
lanes = d.get("lanes", [])
assert isinstance(lanes, list), "lanes not a list"
print("ok")
' 2>/dev/null | grep -q ok; then
  ok "(R2) live --all --json smoke against the real repo root parses (argv unpack in lockstep)"
else
  bad "(R2) --all --json smoke failed rc=${rc_s} (argv unpack out of lockstep?) out=${smoke:0:120}"
fi

printf '\n[LANE-REGISTRY-SELF-DEADLOCK-01] passed=%d failed=%d\n' "${PASS}" "${FAIL}"
(( FAIL == 0 ))
