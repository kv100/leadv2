#!/usr/bin/env bash
# tests/test-glm-flash-handle.sh — GLM-ARM-THROUGHPUT-01.
#
# Every glm-flash spawn used to end `spawn(glm-flash) handle= ... has no live
# run record` (journal, 2026-09-01T20:02Z): glm-coder.sh `bg` echoes the bare
# run id ONCE, but leadv2-dispatch-code.sh's handle parser halved the last
# slash-segment of stdout, truncating every real handle to garbage that
# `status` never resolved — so glm-flash never launched a worker through the
# router. Two contracts, both pinned here:
#   1. LAUNCHER: `GLM_MODEL=glm-5.3-flash glm-coder.sh bg` prints a non-empty
#      handle (the run id) and `status <handle>` is TRUE right after bg.
#   2. DISPATCHER: a real spawn through leadv2-dispatch-code.sh with the REAL
#      glm-coder.sh on the glm arm journals `worker_spawned` with a handle
#      that `status` resolves — not `spawn_failed ... not_live/empty_handle`.
#
# Hermetic: GLM_RUNS_DIR at a temp dir, a stub `claude` (fast exit for the
# dispatcher probe, so the whole dispatch terminates), GLM_SKIP_QUOTA_GATE=1,
# quota stub, journal stub. No network.
#
# Negative-control seam: GLM_FLASH_SUITE_SCRIPT overrides the launcher under
# test (default: the real glm-coder.sh) so the broken-handle-echo mutation
# can be proven RED against a scratch copy without touching the working tree.
#
# Run: bash plugins/leadv2/scripts/tests/test-glm-flash-handle.sh

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_SCRIPTS="$(cd "${SCRIPT_DIR}/.." && pwd)"
PLUGIN_ROOT="$(cd "${PLUGIN_SCRIPTS}/.." && pwd)"
GLM_SCRIPT="${GLM_FLASH_SUITE_SCRIPT:-${PLUGIN_SCRIPTS}/glm-coder.sh}"
DISPATCH="${PLUGIN_SCRIPTS}/leadv2-dispatch-code.sh"

export LEADV2_BURN_GOVERNOR=0 LEADV2_ALLOW_FG_DISPATCH=1

PASS=0
FAIL=0
log()  { printf -- '[TEST] %s\n' "$*"; }
pass() { PASS=$((PASS + 1)); log "PASS: $1"; }
fail() { FAIL=$((FAIL + 1)); log "FAIL: $1"; }

FIXTURE="$(mktemp -d "${TMPDIR:-/tmp}/glm-flash-handle.XXXXXX")"
cleanup() {
  local f pid
  for f in "${FIXTURE}"/glm-runs/pgid "${FIXTURE}"/glm-runs/.lock-*/pgid "${FIXTURE}"/glm-runs/.lock-*/pid; do
    [[ -f "${f}" ]] || continue
    pid="$(cat "${f}" 2>/dev/null || true)"
    [[ -n "${pid}" ]] && kill -TERM -"${pid}" 2>/dev/null || true
    [[ -n "${pid}" ]] && kill -TERM "${pid}" 2>/dev/null || true
  done
  sleep 1
  rm -rf "${FIXTURE}"
}
trap cleanup EXIT INT TERM

# ── syntax floor on every file this lane changed ────────────────────────────
for f in "scripts/glm-coder.sh" "scripts/leadv2-dispatch-code.sh"; do
  if bash -n "${PLUGIN_ROOT}/${f}" 2>/dev/null && /bin/bash -n "${PLUGIN_ROOT}/${f}" 2>/dev/null; then
    PASS=$((PASS + 1)); log "PASS: bash -n ${f} (incl. 3.2)"
  else
    FAIL=$((FAIL + 1)); log "FAIL: bash -n ${f}"
  fi
done

# ── dependency floor (round 2): an assertion that cannot run is FAIL, never a
# skip. Every tool the assertions read state through must be present AND
# functional; a missing or sabotaged tool means the suite exits red.
if command -v grep >/dev/null 2>&1 \
   && printf 'leadv2-dep-floor-probe\n' | grep -q 'leadv2-dep-floor-probe' 2>/dev/null; then
  PASS=$((PASS + 1)); log "PASS: dep floor: grep present and functional"
else
  FAIL=$((FAIL + 1)); log "FAIL: dep floor: grep missing or non-functional (cannot match a literal)"
fi
if git --version >/dev/null 2>&1; then
  PASS=$((PASS + 1)); log "PASS: dep floor: git present and functional"
else
  FAIL=$((FAIL + 1)); log "FAIL: dep floor: git missing or non-functional"
fi
if python3 -c 'pass' >/dev/null 2>&1; then
  PASS=$((PASS + 1)); log "PASS: dep floor: python3 present and functional"
else
  FAIL=$((FAIL + 1)); log "FAIL: dep floor: python3 missing or non-functional (quota stub needs it)"
fi
if [[ "${FAIL}" -ne 0 ]]; then
  printf -- '[TEST] %s: %d passed, %d failed\n' "test-glm-flash-handle" "${PASS}" "${FAIL}"
  exit 1
fi

# ── fixture: repo, stub claude (fast exit), stub secrets ────────────────────
REPO="${FIXTURE}/repo"
mkdir -p "${REPO}"
git -C "${REPO}" init -q 2>/dev/null || true
git -C "${REPO}" -c user.email=flash@test -c user.name=flash commit -q --allow-empty -m init 2>/dev/null || true

STUB_BIN="${FIXTURE}/bin"; mkdir -p "${STUB_BIN}"
cat > "${STUB_BIN}/claude" <<'STUBEOF'
#!/usr/bin/env bash
# Emit a stream event the supervisor accepts, then exit 0 immediately so the
# run (and the dispatch probe below) terminates fast.
printf '%s\n' '{"type":"system","subtype":"init","model":"stub"}'
exit 0
STUBEOF
chmod +x "${STUB_BIN}/claude"

SECRETS="${FIXTURE}/zai.env"
printf 'ZAI_AUTH_TOKEN=stub-token-for-test\n' > "${SECRETS}"
chmod 600 "${SECRETS}"

export GLM_CLAUDE_BIN="${STUB_BIN}/claude"
export GLM_SECRETS_FILE="${SECRETS}"
export GLM_RUNS_DIR="${FIXTURE}/glm-runs"
export GLM_SKIP_QUOTA_GATE=1
export TMPDIR="${FIXTURE}"
export CLAUDE_PLUGIN_ROOT="${PLUGIN_ROOT}"

# ── Case 1: launcher — flash bg handle is non-empty and status-true ─────────
handle="$(
  GLM_MODEL=glm-5.3-flash GLM_TIMEOUT=5 \
  bash "${GLM_SCRIPT}" bg "flash handle probe mission" --cwd "${REPO}" 2>/dev/null | tail -1
)" || handle=""
if [[ -n "${handle}" ]]; then
  pass "launcher: glm-5.3-flash bg prints a non-empty handle (${handle})"
else
  fail "launcher: glm-5.3-flash bg printed an empty handle"
fi
if bash "${GLM_SCRIPT}" status "${handle}" >/dev/null 2>&1; then
  pass "launcher: status <handle> true right after bg"
else
  fail "launcher: status [${handle}] not live right after bg"
fi
if bash "${GLM_SCRIPT}" status "${handle}" 2>/dev/null | grep -q '^model: glm-5.3-flash$'; then
  pass "launcher: run record names model glm-5.3-flash"
else
  fail "launcher: meta model line wrong: $(bash "${GLM_SCRIPT}" status "${handle}" 2>/dev/null | grep '^model:' || echo '<none>')"
fi

# Fixture floor: the repo the launchers run in must exist, or every later
# case fails for a fixture reason while looking like a product failure.
if [[ -e "${REPO}/.git" ]]; then
  PASS=$((PASS + 1)); log "PASS: fixture floor: fixture repo exists"
else
  FAIL=$((FAIL + 1)); log "FAIL: fixture floor: fixture repo missing (git setup failed)"
fi

# ── Case 2: dispatcher — real launcher, handle survives the spawn path ──────
# The production bug lived HERE, not in the launcher: the dispatcher's handle
# parser halved glm-coder.sh's stdout, so every spawn was judged not_live.
# Isolation notes (both needed, learned the hard way): LEADV2_STATE_ROOT must
# point at the fixture or leadv2-active-registry.sh reads THIS repo's live
# lane registry and refuses writeset_conflict before the spawn row; the quota
# stub must carry the full three-provider shape or the arbiter sees
# unknown_capped and refuses all arms.
JOURNAL_RECORD="${FIXTURE}/journal-record.txt"
cat > "${FIXTURE}/journal.sh" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$GLM_FLASH_HANDLE_JOURNAL"
EOF
chmod +x "${FIXTURE}/journal.sh"
export GLM_FLASH_HANDLE_JOURNAL="${JOURNAL_RECORD}"

cat > "${FIXTURE}/dispatch-live.sh" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$ROUTE_TEST_QUOTA"
EOF
chmod +x "${FIXTURE}/dispatch-live.sh"

arb_quota() { python3 - "$1" "$2" "$3" <<'PY'
import json,sys
g,c,a=map(int,sys.argv[1:])
print(json.dumps({'glm':{'status':'ok','five_hour':{'pct':g},'weekly':{'pct':g}},'codex':{'status':'ok','binding_window':'primary','windows':[{'kind':'primary','used_percent':c}]},'anthropic':{'status':'ok','accounts':[{'active':True,'five_hour_pct':a,'seven_day_pct':a}]}}))
PY
}

: > "${JOURNAL_RECORD}"
D_CACHE="${FIXTURE}/dispatch-cache"; mkdir -p "${D_CACHE}"
D_OUT="$(
  unset LEADV2_PROJECT_ROOT LEADV2_LANE_WORK_ROOT LEADV2_TASK_ID LEADV2_PARENT_SESSION_ID LEADV2_DISPATCH_LANE_NAME
  CLAUDE_PROJECT_ROOT="${REPO}" \
  LEADV2_PROJECT_ROOT="${REPO}" \
  LEADV2_STATE_ROOT="${FIXTURE}/state" \
  LEADV2_DISPATCH_CACHE_DIR="${D_CACHE}" \
  LEADV2_DISPATCH_E2E_GATE=0 LEADV2_DISPATCH_REVIEW_GATE=0 LEADV2_DISPATCH_ARCHITECT_GATE=0 \
  LEADV2_LANE_SHAPE=off LEADV2_ARM_EARLY_VERDICT_S=0 LEADV2_ROUTER_V2=0 \
  LEADV2_QUOTA_LIVE="${FIXTURE}/dispatch-live.sh" \
  LEADV2_ROUTE_ARBITER_STATE_FILE="${FIXTURE}/dispatch-arb-state" \
  LEADV2_JOURNAL_BIN="${FIXTURE}/journal.sh" JOURNAL_TASK=glm-flash-handle \
  LEADV2_DISPATCH_GLM_BIN="${GLM_SCRIPT}" \
  LEADV2_DISPATCH_KIMI_BIN=/bin/false LEADV2_DISPATCH_CODEX_BIN=/bin/false \
  LEADV2_DISPATCH_SUBSESSION_BIN=/bin/false \
  ROUTE_TEST_QUOTA="$(arb_quota 10 20 20)" \
  bash "${DISPATCH}" 'flash handle dispatch probe: mechanical edit round' --kind code --writes src/x.py 2>&1
)" || true
rm -f "${FIXTURE}/dispatch-arb-state" 2>/dev/null || true

spawned="$(grep -o 'worker_spawned by=router model=glm[a-z-]* .*handle=[^ ]*' "${JOURNAL_RECORD}" | tail -1)"
spawn_handle="${spawned##*handle=}"
if [[ -n "${spawned}" && -n "${spawn_handle}" ]]; then
  pass "dispatcher: glm-family worker_spawned with handle ${spawn_handle}"
else
  fail "dispatcher: no worker_spawned handle — journal tail: $(tail -5 "${JOURNAL_RECORD}" 2>/dev/null | tr '\n' ' ')"
fi
# An ABSENCE check on a journal the dispatch never wrote is vacuous: require
# the journal to be non-empty first, else the dispatch never ran (or the
# journal stub is broken) and that is a FAIL, never a pass.
if [[ ! -s "${JOURNAL_RECORD}" ]]; then
  fail "dispatcher: journal record empty — dispatch produced no journal rows"
elif grep -q 'spawn_failed by=router model=glm[a-z-]* .*reason=not_live\|spawn_failed by=router model=glm[a-z-]* .*reason=empty_handle' "${JOURNAL_RECORD}" 2>/dev/null; then
  fail "dispatcher: spawn_failed not_live/empty_handle present (handle parser broke the run id)"
else
  pass "dispatcher: no spawn_failed not_live/empty_handle rows"
fi
# status on the journaled handle only counts when there IS a handle: status ""
# exits 0 on the launcher, so an empty handle must FAIL here, not resolve.
if [[ -z "${spawn_handle}" ]]; then
  fail "dispatcher: no journaled handle to resolve (status check cannot run — that is a FAIL)"
elif bash "${GLM_SCRIPT}" status "${spawn_handle}" >/dev/null 2>&1; then
  pass "dispatcher: status true on the journaled handle"
else
  fail "dispatcher: status [${spawn_handle}] not live — handle did not survive the spawn path"
fi

printf -- '[TEST] %s: %d passed, %d failed\n' "test-glm-flash-handle" "${PASS}" "${FAIL}"
[[ "${FAIL}" -eq 0 ]]
