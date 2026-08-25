#!/usr/bin/env bash
# LANE-OBSERVABILITY-02 change 2 — resume invalidates a refuted / stale prepass.
#
# The live defect (dispatch-16fbe872, 2026-08-25): architect-prepass.md persisted
# in the handoff dir and was re-fed from cache on every resume; after the worker
# refused with census-falsified (or after the lane base moved via merge/ff in the
# worktree), the SAME prepass poisoned rounds 2-3. This suite locks the four
# behaviours of the invalidation gate (leadv2-dispatch-code.sh architect_prepass,
# the block guarded by PLACEMENT_PINNED=1 + LEADV2_PREPASS_INVALIDATE=1):
#
#   R1  first pinned run generates: .head sidecar stamped with the worktree HEAD,
#       artifact line 1 carries the human `<!-- leadv2-prepass base_head=... -->`
#       header.
#   R2  resume at the SAME head with byte-identical mission: cache HIT
#       (status=cached), NO invalidation.
#   R3  resume after the worktree HEAD moved: status=invalidated reason=head_moved,
#       old artifact archived as architect-prepass.<epoch>.md, fresh artifact's
#       .head + header name the NEW head.
#   R4  resume at the same head whose terminal-ledger last cause names a
#       census/prepass refusal: status=invalidated reason=prepass_refuted.
#   R5  LEADV2_PREPASS_INVALIDATE=0 restores today: head moved, NO invalidation,
#       cache still served.
#
# Hermetic: scratch repo + linked lane worktree, stubbed glm/journal/liveness/
# architect, no network, no real dispatch arms.
# Run: bash scripts/tests/test-prepass-resume-invalidate.sh

set -uo pipefail

# BURN-GOVERNOR-01: the burn gate defaults ON and reads the host's real
# ~/.claude/burn/history.db -- a hot host would red this suite on `exit 6`.
export LEADV2_BURN_GOVERNOR=0

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_SCRIPTS="$(cd "${SCRIPT_DIR}/.." && pwd)"
DC="${PLUGIN_SCRIPTS}/leadv2-dispatch-code.sh"
STATE_PATH="${PLUGIN_SCRIPTS}/leadv2-state-path.sh"

PASS=0; FAIL=0
ok()  { printf '[TEST] PASS: %s\n' "$1"; PASS=$((PASS+1)); }
bad() { printf '[TEST] FAIL: %s\n' "$1" >&2; FAIL=$((FAIL+1)); }

SANDBOX="$(mktemp -d /tmp/leadv2-ppinv-XXXXXX)"
cleanup() { rm -rf "${SANDBOX}"; }
trap cleanup EXIT

# ── Fixture repo + linked lane worktree ──────────────────────────────────────
TARGET="${SANDBOX}/target"
mkdir -p "${TARGET}"
( cd "${TARGET}" && git init -q -b main \
  && git config user.email t@e.com && git config user.name t \
  && printf 'seed\n' > .gitignore && git add .gitignore && git commit -qm seed )

LANE_REF="PPINV001"
RESUME_WT="${TARGET}/.claude/worktrees/${LANE_REF}"
mkdir -p "$(dirname "${RESUME_WT}")"
( cd "${TARGET}" && git worktree add -q "${RESUME_WT}" -b "worktree-${LANE_REF}" ) 2>/dev/null
( cd "${RESUME_WT}" && printf 'lane work\n' > lane.txt && git add lane.txt && git commit -qm lane-seed )

# ── Stubs ────────────────────────────────────────────────────────────────────
GLM_STUB="${SANDBOX}/glm-stub.sh"
JOURNAL_STUB="${SANDBOX}/journal-stub.sh"
LIVENESS_STUB="${SANDBOX}/liveness-stub.sh"
ARCH_STUB="${SANDBOX}/arch-stub.sh"
WORKER_STUB="${SANDBOX}/worker-stub.sh"

cat > "${GLM_STUB}" <<'SH'
#!/usr/bin/env bash
case "${1:-}" in
  bg) shift; printf 'PID=%s LABEL=fake SESSION_ID=fake\n' "$$"; exit 0 ;;
  *) exit 0 ;;
esac
SH
cat > "${JOURNAL_STUB}" <<'SH'
#!/usr/bin/env bash
exit 0
SH
cat > "${LIVENESS_STUB}" <<'SH'
#!/usr/bin/env bash
printf '{"lane":"%s","verdict":"dead:silent_9999s_no_process","reason":"log_silent_no_process","age_s":9999,"pid_alive":false}\n' "${LEADV2_STUB_LANE:-lane}"
exit 0
SH
# Architect stub: writes the design artifact synchronously, exits 0 (the
# well-behaved twin of the late-artifact fixture's exit-1 stub).
cat > "${ARCH_STUB}" <<'SH'
#!/usr/bin/env bash
task_id=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --task-id) task_id="$2"; shift 2;;
    *) shift;;
  esac
done
adir="${PROJECT_ROOT}/docs/handoff/${task_id}"
mkdir -p "$adir"
printf '# Design\nchanges: a.txt, b.txt\nacceptance:\n  surface: file_artifact\n  observable: file exists\n  authored_at: 2026-08-25T00:00:00Z\nLANE_WRITES: a.txt,b.txt\nDELIVERABLE_COMPLETE\n' > "${adir}/architect.full.md"
exit 0
SH
cat > "${WORKER_STUB}" <<'SH'
#!/usr/bin/env bash
nohup sleep 60 >/dev/null 2>&1 &
printf 'PID=%s LABEL=test SESSION_ID=test\n' "$!"
exit 0
SH
chmod +x "${GLM_STUB}" "${JOURNAL_STUB}" "${LIVENESS_STUB}" "${ARCH_STUB}" "${WORKER_STUB}"

# ── Common dispatch env ──────────────────────────────────────────────────────
export CLAUDE_PROJECT_DIR="${TARGET}"
export CLAUDE_PROJECT_ROOT="${TARGET}"
unset PROJECT_ROOT 2>/dev/null || true
unset LEADV2_LANE_WORK_ROOT 2>/dev/null || true
export LEADV2_DISPATCH_GLM_BIN="${GLM_STUB}"
export LEADV2_JOURNAL_BIN="${JOURNAL_STUB}"
export LEADV2_DISPATCH_LEDGER_BIN="${PLUGIN_SCRIPTS}/leadv2-dispatch-ledger.sh"
export LEADV2_STATE_PATH_BIN="${STATE_PATH}"
export LEADV2_DISPATCH_LANE_LIVENESS_BIN="${LIVENESS_STUB}"
export LEADV2_ROUTER_V2=0
export GLM_POLICY_RESOLVER=""
export LEADV2_LANE_SHAPE=off
export LEADV2_DISPATCH_E2E_GATE=0
export LEADV2_DISPATCH_REVIEW_GATE=0
export LEADV2_DISPATCH_CACHE_DIR="${SANDBOX}/cache"
export LEADV2_STATE_BASE="${SANDBOX}/state"
export LEADV2_DISPATCH_PENDING_TTL_S=5
export LEADV2_DISPATCH_CONFIRMED_TTL_S=10
export LEADV2_EXCLUDED_ARMS="__none__"
export LEADV2_DISPATCH_ARCHITECT_GATE=1
export LEADV2_DISPATCH_SUBSESSION_BIN="${WORKER_STUB}"
export LEADV2_DISPATCH_ARCHITECT_BIN="${ARCH_STUB}"
export LEADV2_DISPATCH_ARCHITECT_TIMEOUT_SEC=10
export LEADV2_DISPATCH_TERMINAL_LEDGER_FILE="${SANDBOX}/terminal-ledger.jsonl"

MISSION='PPINV resume invalidation fixture mission fix the watcher layer completely'
LOG="${SANDBOX}/out.log"

run_dispatch() {  # extra args pass through
  ( cd "${TARGET}" && \
    LEADV2_BURN_GOVERNOR=0 \
    bash "${DC}" --kind product --protected --worktree "${RESUME_WT}" \
      --writes "a.txt,b.txt" "${MISSION}" "$@" ) >"${LOG}" 2>&1
  return $?
}

prepass_file() {  # <sig8>
  printf '%s/docs/handoff/dispatch-%s/architect-prepass.md' "${TARGET}" "$1"
}

# sig8 is a hash of the mission text -> identical mission = identical sig8
# (compute_sig = normalise whitespace + sha256; verified below by falling back
# to the sig8 the log itself reports if this ever drifts).
SIG8="$(printf '%s' "${MISSION}" | tr -d '\r' | tr -s '[:space:]' ' ' | sed -e 's/^ //' -e 's/ $//' | shasum -a 256 | awk '{print substr($1,1,8)}')"
PP="$(prepass_file "${SIG8}")"

# ── R1: first pinned run generates + stamps ─────────────────────────────────
run_dispatch || true
if grep -q "architect_prepass task=${SIG8} status=ran" "${LOG}"; then
  ok "R1a: first pinned run generated the prepass (sig8=${SIG8})"
else
  # fall back: discover the sig8 dispatch actually used from the log itself
  SIG8="$(sed -n 's/.*architect_prepass task=\([0-9a-f]\{8\}\) status=ran.*/\1/p' "${LOG}" | head -1)"
  PP="$(prepass_file "${SIG8}")"
  if [[ -n "${SIG8}" ]]; then
    ok "R1a: first pinned run generated the prepass (discovered sig8=${SIG8})"
  else
    bad "R1a: no architect_prepass status=ran in log:"; tail -20 "${LOG}" >&2; exit 1
  fi
fi

HEAD1="$(cd "${RESUME_WT}" && git rev-parse HEAD)"
if [[ "$(cat "${PP}.head" 2>/dev/null)" == "${HEAD1}" ]]; then
  ok "R1b: .head sidecar stamped with the worktree HEAD"
else
  bad "R1b: .head sidecar is '$(cat "${PP}.head" 2>/dev/null)' want '${HEAD1}'"
fi
if head -n 1 "${PP}" | grep -q "base_head=${HEAD1}"; then
  ok "R1c: artifact line 1 carries the base_head header"
else
  bad "R1c: artifact line 1 is '$(head -n 1 "${PP}")'"
fi

# ── R2: same head, same mission -> cache hit, NO invalidation ────────────────
rm -f "${LOG}"; run_dispatch || true
if grep -q "architect_prepass task=${SIG8} status=cached" "${LOG}"; then
  ok "R2a: same-head resume served from cache"
else
  bad "R2a: no status=cached in log:"; grep architect_prepass "${LOG}" >&2
fi
if ! grep -q "status=invalidated" "${LOG}"; then
  ok "R2b: same-head resume did NOT invalidate"
else
  bad "R2b: same-head resume invalidated (must not): $(grep status=invalidated "${LOG}")"
fi

# ── R3: head moved -> invalidate + archive + regenerate ──────────────────────
( cd "${RESUME_WT}" && printf 'base moved\n' >> lane.txt && git add lane.txt && git commit -qm base-move ) >/dev/null 2>&1
HEAD2="$(cd "${RESUME_WT}" && git rev-parse HEAD)"
rm -f "${LOG}"; run_dispatch || true
if grep -q "architect_prepass task=${SIG8} status=invalidated reason=head_moved old_head=${HEAD1} new_head=${HEAD2}" "${LOG}"; then
  ok "R3a: head-move resume journaled invalidation old->new"
else
  bad "R3a: invalidation line wrong/missing: $(grep -E 'architect_prepass' "${LOG}" | head -3)"
fi
ARCHIVED="$(ls "${TARGET}/docs/handoff/dispatch-${SIG8}"/architect-prepass.*.md 2>/dev/null | head -1)"
if [[ -n "${ARCHIVED}" && -s "${ARCHIVED}" ]]; then
  ok "R3b: old prepass archived as $(basename "${ARCHIVED}")"
else
  bad "R3b: no archived architect-prepass.<epoch>.md"
fi
if [[ "$(cat "${PP}.head" 2>/dev/null)" == "${HEAD2}" ]]; then
  ok "R3c: regenerated .head names the NEW head"
else
  bad "R3c: .head is '$(cat "${PP}.head" 2>/dev/null)' want '${HEAD2}'"
fi
if head -n 1 "${PP}" | grep -q "base_head=${HEAD2}"; then
  ok "R3d: regenerated artifact header names the NEW head"
else
  bad "R3d: regenerated artifact line 1 is '$(head -n 1 "${PP}")'"
fi
# and the NEXT resume at this head is a cache hit again (no invalidation loop)
rm -f "${LOG}"; run_dispatch || true
if grep -q "architect_prepass task=${SIG8} status=cached" "${LOG}" && ! grep -q "status=invalidated" "${LOG}"; then
  ok "R3e: second resume at the same new head hits cache (no invalidation loop)"
else
  bad "R3e: regeneration did not stabilise: $(grep -E 'architect_prepass' "${LOG}" | head -3)"
fi

# ── R4: census-refusal terminal at same head -> prepass_refuted ──────────────
printf '{"ts":"2026-08-25T00:00:00Z","task_sig":"%s","founder_task_id":"f","task_id":"dispatch-%s","terminal":"no_work","cause":"census_falsified_by_probe","evidence":"e","commit":"none","deliverable":"unknown","attempt":"1","worker_reason":""}\n' \
  "${SIG8}" "${SIG8}" >> "${SANDBOX}/terminal-ledger.jsonl"
rm -f "${LOG}"; run_dispatch || true
if grep -q "architect_prepass task=${SIG8} status=invalidated reason=prepass_refuted" "${LOG}"; then
  ok "R4: census-refused terminal invalidates the cached prepass"
else
  bad "R4: no prepass_refuted invalidation: $(grep -E 'architect_prepass' "${LOG}" | head -3)"
fi

# ── R5: LEADV2_PREPASS_INVALIDATE=0 restores today ───────────────────────────
rm -f "${LOG}"
( cd "${TARGET}" && \
  LEADV2_BURN_GOVERNOR=0 LEADV2_PREPASS_INVALIDATE=0 \
  bash "${DC}" --kind product --protected --worktree "${RESUME_WT}" \
    --writes "a.txt,b.txt" "${MISSION}" ) >"${LOG}" 2>&1 || true
if ! grep -q "status=invalidated" "${LOG}" && grep -q "architect_prepass task=${SIG8} status=cached" "${LOG}"; then
  ok "R5: kill switch restores today (no invalidation, cache served)"
else
  bad "R5: kill switch did not restore today: $(grep -E 'architect_prepass' "${LOG}" | head -3)"
fi

printf '\n[prepass-resume-invalidate] PASS=%d FAIL=%d\n' "$PASS" "$FAIL"
[[ "${FAIL}" -eq 0 ]]
