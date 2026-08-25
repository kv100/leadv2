#!/usr/bin/env bash
# LANE-PLACEMENT-NOT-ADDRESSABLE-01 — explicit lane placement (--resume-lane / --worktree).
#
# Eight assertions:
#   P-a  --resume-lane RESUME-ME-01 → worker cwd == that pre-existing lane worktree.
#   P-b  --worktree <abs path> → same cwd.
#   P-c  --worktree /nope/nothing → rc 5, REFUSE placement, no spawn, no ledger row.
#   P-d  --worktree FOREIGN worktree → rc 5, reason foreign_repo, no spawn, no ledger.
#   P-e  --resume-lane with lane live → rc 5, reason lane_is_live, no spawn, no ledger.
#   P-f  --resume-lane + --worktree together → rc 1 (usage), no spawn, no ledger.
#   P-g  no flag (regression) → fresh tree created under .claude/worktrees/, != RESUME-ME.
#   P-h  prompt pin line present when flag used; absent when no flag.
#
# Sandbox: TARGET git repo with linked worktree RESUME-ME-01, FOREIGN repo, stub GLM
# launcher recording --cwd + mission, stub liveness probe, stub journal.

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

SANDBOX="$(mktemp -d /tmp/leadv2-lpp-XXXXXX)"
cleanup() {
  rm -rf "${SANDBOX}"
}
trap cleanup EXIT

# ── Fixture repos ────────────────────────────────────────────────────────────
TARGET="${SANDBOX}/target"
FOREIGN="${SANDBOX}/foreign"

new_repo() {
  local root="$1"
  mkdir -p "${root}"
  ( cd "${root}" && git init -q -b main \
    && git config user.email t@e.com && git config user.name t \
    && printf 'seed\n' > .gitignore && git add .gitignore && git commit -qm seed )
}

new_repo "${TARGET}"
new_repo "${FOREIGN}"

# Linked worktree of TARGET so path-of + --git-common-dir resolve correctly.
RESUME_WT="${TARGET}/.claude/worktrees/RESUME-ME-01"
mkdir -p "$(dirname "${RESUME_WT}")"
( cd "${TARGET}" && git worktree add -q "${RESUME_WT}" -b worktree-RESUME-ME-01 ) 2>/dev/null
# Seed a commit inside the lane worktree so it's not a clean empty tree
( cd "${RESUME_WT}" && printf 'lane work\n' > lane.txt && git add lane.txt && git commit -qm lane-seed )

# Linked worktree of FOREIGN (different repo)
FOREIGN_WT="${FOREIGN}/.claude/worktrees/OTHER-01"
mkdir -p "$(dirname "${FOREIGN_WT}")"
( cd "${FOREIGN}" && git worktree add -q "${FOREIGN_WT}" -b worktree-OTHER-01 ) 2>/dev/null

# ── Sandbox state + cache dirs ───────────────────────────────────────────────
export LEADV2_STATE_BASE="${SANDBOX}/state"
export LEADV2_DISPATCH_CACHE_DIR="${SANDBOX}/cache"

GLM_STUB="${SANDBOX}/glm-stub.sh"
JOURNAL_STUB="${SANDBOX}/journal-stub.sh"
LIVENESS_STUB="${SANDBOX}/liveness-stub.sh"

# ── Stub GLM binary (records --cwd and mission, creates a fake run for status) ─
cat > "${GLM_STUB}" <<'SH'
#!/usr/bin/env bash
RUNS="${LEADV2_STUB_GLM_RUNS:-/tmp/leadv2-stub-glm-runs}"
CWD_OUT="${LEADV2_STUB_CWD_OUT:-}"
MISSION_OUT="${LEADV2_STUB_MISSION_OUT:-}"
case "${1:-}" in
  bg)
    # Extract --cwd <path> from args
    shift  # drop 'bg'
    mission="$1"; shift
    while [[ $# -gt 0 ]]; do
      case "$1" in
        --cwd) CWD="$2"; shift 2 ;;
        *) shift ;;
      esac
    done
    [[ -z "${CWD_OUT}" ]] || printf '%s\n' "${CWD:-}" > "${CWD_OUT}" 2>/dev/null
    [[ -z "${MISSION_OUT}" ]] || printf '%s' "${mission:-}" > "${MISSION_OUT}" 2>/dev/null
    mkdir -p "$RUNS" 2>/dev/null
    handle="stub-run-$(date +%s)-$$"
    printf '%s' "$handle" > "$RUNS/$handle" 2>/dev/null
    printf '%s\n' "$handle"
    exit 0
    ;;
  status)
    [[ -n "${2:-}" && -f "$RUNS/$2" ]] && exit 0
    exit 1
    ;;
  *)
    exit 0
    ;;
esac
SH

# Stub journal (no-op)
cat > "${JOURNAL_STUB}" <<'SH'
#!/usr/bin/env bash
exit 0
SH

# Stub liveness probe — dead by default, alive when force-live sentinel
# exists. LANE-PLACEMENT-01 P-e: leadv2-dispatch-code.sh probes with --json
# and parses via _placement_probe_field (json.loads with a swallowed
# exception on failure), so the stub must emit the real row shape
# (verdict/reason/age_s, as leadv2-lane-liveness.sh --json emits at its
# resolve() call site) — plain text here left json.loads() raising, the
# exception silently swallowed, and P-e never took the refusal path.
cat > "${LIVENESS_STUB}" <<'SH'
#!/usr/bin/env bash
if [[ -f "${LEADV2_STUB_FORCE_LIVE:-}" ]]; then
  printf '{"lane":"%s","verdict":"alive","reason":"process_alive","age_s":5,"pid_alive":true}\n' "${LEADV2_STUB_LANE:-lane}"
else
  printf '{"lane":"%s","verdict":"dead:silent_9999s_no_process","reason":"log_silent_no_process","age_s":9999,"pid_alive":false}\n' "${LEADV2_STUB_LANE:-lane}"
fi
exit 0
SH

# ── Common dispatch env ──────────────────────────────────────────────────────
setup_env() {
  export CLAUDE_PROJECT_DIR="${TARGET}"
  export CLAUDE_PROJECT_ROOT="${TARGET}"
  unset PROJECT_ROOT 2>/dev/null || true
  unset LEADV2_LANE_WORK_ROOT 2>/dev/null || true
  export LEADV2_DISPATCH_GLM_BIN="${GLM_STUB}"
  export LEADV2_STUB_GLM_RUNS="${SANDBOX}/glm-runs"
  export LEADV2_JOURNAL_BIN="${JOURNAL_STUB}"
  export LEADV2_DISPATCH_LEDGER_BIN="${PLUGIN_SCRIPTS}/leadv2-dispatch-ledger.sh"
  export LEADV2_STATE_PATH_BIN="${STATE_PATH}"
  export LEADV2_DISPATCH_LANE_LIVENESS_BIN="${LIVENESS_STUB}"
  # Use v1 router with resolver missing → defaults to arm=glm
  export LEADV2_ROUTER_V2=0
  export GLM_POLICY_RESOLVER=""
  export LEADV2_LANE_SHAPE=off
  export LEADV2_DISPATCH_E2E_GATE=0
  export LEADV2_DISPATCH_REVIEW_GATE=0
  export LEADV2_DISPATCH_PENDING_TTL_S=5
  export LEADV2_DISPATCH_CONFIRMED_TTL_S=10
}

# Resolve the reservation ledger path for a given slug.
reservation_ledger_path() {  # <slug>
  printf '%s/dispatch-ledger/%s.jsonl' "${LEADV2_DISPATCH_CACHE_DIR}" "$1"
}
TARGET_SLUG="target"
TARGET_RESERVATION="$(reservation_ledger_path "${TARGET_SLUG}")"

# ════════════════════════════════════════════════════════════════════════════
# P-a: --resume-lane RESUME-ME-01 → worker cwd == RESUME_WT
# ════════════════════════════════════════════════════════════════════════════
setup_env
export LEADV2_STUB_CWD_OUT="${SANDBOX}/pa-cwd.txt"
export LEADV2_STUB_MISSION_OUT="${SANDBOX}/pa-mission.txt"
dispatch_rc=0
bash "${DC}" --kind tooling --resume-lane RESUME-ME-01 \
  "P-a placement resume test fix the build" >/dev/null 2>&1 || dispatch_rc=$?

if [[ ${dispatch_rc} -eq 0 ]]; then
  ok "P-a: dispatch exited 0"
else
  bad "P-a: dispatch exited ${dispatch_rc} (expected 0)"
fi

CWD_A="$(cat "${SANDBOX}/pa-cwd.txt" 2>/dev/null || printf '')"
CWD_A_PHYS="$(cd "${CWD_A}" 2>/dev/null && pwd -P || printf '')"
RESUME_PHYS="$(cd "${RESUME_WT}" 2>/dev/null && pwd -P)"
if [[ "${CWD_A_PHYS}" == "${RESUME_PHYS}" ]]; then
  ok "P-a: worker cwd == RESUME-ME-01 worktree"
else
  bad "P-a: worker cwd='${CWD_A_PHYS}' != RESUME='${RESUME_PHYS}'"
fi

# P-h (flag path): prompt pin line present
if head -1 "${SANDBOX}/pa-mission.txt" 2>/dev/null | grep -q '^WORKTREE PIN: all edits go in '; then
  ok "P-h(a): prompt pin line present with --resume-lane"
else
  bad "P-h(a): prompt pin line MISSING with --resume-lane"
fi

# ════════════════════════════════════════════════════════════════════════════
# P-b: --worktree <abs path> → same cwd
# ════════════════════════════════════════════════════════════════════════════
setup_env
export LEADV2_STUB_CWD_OUT="${SANDBOX}/pb-cwd.txt"
export LEADV2_STUB_MISSION_OUT="${SANDBOX}/pb-mission.txt"
dispatch_rc=0
bash "${DC}" --kind tooling --worktree "${RESUME_WT}" \
  "P-b placement worktree path test refactor the validator" >/dev/null 2>&1 || dispatch_rc=$?

if [[ ${dispatch_rc} -eq 0 ]]; then
  ok "P-b: dispatch exited 0"
else
  bad "P-b: dispatch exited ${dispatch_rc} (expected 0)"
fi

CWD_B="$(cat "${SANDBOX}/pb-cwd.txt" 2>/dev/null || printf '')"
CWD_B_PHYS="$(cd "${CWD_B}" 2>/dev/null && pwd -P || printf '')"
if [[ "${CWD_B_PHYS}" == "${RESUME_PHYS}" ]]; then
  ok "P-b: worker cwd == RESUME-ME-01 worktree (via --worktree)"
else
  bad "P-b: worker cwd='${CWD_B_PHYS}' != RESUME='${RESUME_PHYS}'"
fi

# P-h (worktree path): prompt pin line present
if head -1 "${SANDBOX}/pb-mission.txt" 2>/dev/null | grep -q '^WORKTREE PIN: all edits go in '; then
  ok "P-h(b): prompt pin line present with --worktree"
else
  bad "P-h(b): prompt pin line MISSING with --worktree"
fi

# ════════════════════════════════════════════════════════════════════════════
# P-c: --worktree /nope/nothing → rc 5, REFUSE, no spawn, no ledger
# ════════════════════════════════════════════════════════════════════════════
setup_env
export LEADV2_STUB_CWD_OUT="${SANDBOX}/pc-cwd.txt"
dispatch_rc=0
bash "${DC}" --kind tooling --worktree "/nope/nothing" \
  "P-c placement nonexistent path test" 2>"${SANDBOX}/pc-stderr.txt" >/dev/null || dispatch_rc=$?

if [[ ${dispatch_rc} -eq 5 ]]; then
  ok "P-c: dispatch exited 5 (placement refused)"
else
  bad "P-c: dispatch exited ${dispatch_rc} (expected 5)"
fi

if grep -q '\[leadv2-dispatch-code\] REFUSE placement:' "${SANDBOX}/pc-stderr.txt" 2>/dev/null; then
  ok "P-c: stderr contains REFUSE placement line"
else
  bad "P-c: stderr missing REFUSE placement line"
fi

# No spawn: cwd file should not exist or be empty
if [[ ! -f "${SANDBOX}/pc-cwd.txt" || -z "$(cat "${SANDBOX}/pc-cwd.txt" 2>/dev/null)" ]]; then
  ok "P-c: no worker spawned (no cwd recorded)"
else
  bad "P-c: worker WAS spawned (cwd file exists)"
fi

# No reservation/ledger row for this sig — use a fresh cache dir to be sure
P_C_CACHE="${SANDBOX}/pc-cache"
LEADV2_DISPATCH_CACHE_DIR="${P_C_CACHE}" TARGET_SLUG="target" bash -c '
  printf "%s\n" "$0"' "$(reservation_ledger_path target)" >/dev/null 2>&1
# Verify the dispatch above wrote no ledger row to the main cache
if [[ ! -f "${TARGET_RESERVATION}" ]] || ! grep -q "P-c" "${TARGET_RESERVATION}" 2>/dev/null; then
  ok "P-c: no reservation ledger row for this dispatch"
else
  bad "P-c: reservation ledger HAS a row for this dispatch"
fi

# ════════════════════════════════════════════════════════════════════════════
# P-d: --worktree FOREIGN worktree → rc 5, foreign_repo
# ════════════════════════════════════════════════════════════════════════════
setup_env
export LEADV2_STUB_CWD_OUT="${SANDBOX}/pd-cwd.txt"
dispatch_rc=0
bash "${DC}" --kind tooling --worktree "${FOREIGN_WT}" \
  "P-d placement foreign repo test fix something" 2>"${SANDBOX}/pd-stderr.txt" >/dev/null || dispatch_rc=$?

if [[ ${dispatch_rc} -eq 5 ]]; then
  ok "P-d: dispatch exited 5 (foreign repo refused)"
else
  bad "P-d: dispatch exited ${dispatch_rc} (expected 5)"
fi

if grep -q 'foreign_repo' "${SANDBOX}/pd-stderr.txt" 2>/dev/null; then
  ok "P-d: stderr contains foreign_repo reason"
else
  bad "P-d: stderr missing foreign_repo reason"
fi

if [[ ! -f "${SANDBOX}/pd-cwd.txt" || -z "$(cat "${SANDBOX}/pd-cwd.txt" 2>/dev/null)" ]]; then
  ok "P-d: no worker spawned"
else
  bad "P-d: worker WAS spawned"
fi

# ════════════════════════════════════════════════════════════════════════════
# P-e: --resume-lane with lane live → rc 5, lane_is_live
# ════════════════════════════════════════════════════════════════════════════
setup_env
export LEADV2_STUB_FORCE_LIVE="${SANDBOX}/force-live"
touch "${LEADV2_STUB_FORCE_LIVE}"
export LEADV2_STUB_CWD_OUT="${SANDBOX}/pe-cwd.txt"
dispatch_rc=0
bash "${DC}" --kind tooling --resume-lane RESUME-ME-01 \
  "P-e placement live lane test refactor handler" 2>"${SANDBOX}/pe-stderr.txt" >/dev/null || dispatch_rc=$?
rm -f "${LEADV2_STUB_FORCE_LIVE}"

if [[ ${dispatch_rc} -eq 5 ]]; then
  ok "P-e: dispatch exited 5 (live lane refused)"
else
  bad "P-e: dispatch exited ${dispatch_rc} (expected 5)"
fi

if grep -q 'lane_is_live' "${SANDBOX}/pe-stderr.txt" 2>/dev/null; then
  ok "P-e: stderr contains lane_is_live reason"
else
  bad "P-e: stderr missing lane_is_live reason"
fi

if [[ ! -f "${SANDBOX}/pe-cwd.txt" || -z "$(cat "${SANDBOX}/pe-cwd.txt" 2>/dev/null)" ]]; then
  ok "P-e: no worker spawned"
else
  bad "P-e: worker WAS spawned"
fi

# ════════════════════════════════════════════════════════════════════════════
# P-f: --resume-lane + --worktree together → rc 1 (usage)
# ════════════════════════════════════════════════════════════════════════════
setup_env
export LEADV2_STUB_CWD_OUT="${SANDBOX}/pf-cwd.txt"
dispatch_rc=0
bash "${DC}" --kind tooling --resume-lane RESUME-ME-01 --worktree "${RESUME_WT}" \
  "P-f placement mutual exclusion test" >/dev/null 2>&1 || dispatch_rc=$?

if [[ ${dispatch_rc} -eq 1 ]]; then
  ok "P-f: dispatch exited 1 (usage error for both flags)"
else
  bad "P-f: dispatch exited ${dispatch_rc} (expected 1)"
fi

if [[ ! -f "${SANDBOX}/pf-cwd.txt" || -z "$(cat "${SANDBOX}/pf-cwd.txt" 2>/dev/null)" ]]; then
  ok "P-f: no worker spawned"
else
  bad "P-f: worker WAS spawned"
fi

# ════════════════════════════════════════════════════════════════════════════
# P-g: no flag (regression) → fresh tree created, != RESUME-ME
# ════════════════════════════════════════════════════════════════════════════
setup_env
export LEADV2_STUB_CWD_OUT="${SANDBOX}/pg-cwd.txt"
export LEADV2_STUB_MISSION_OUT="${SANDBOX}/pg-mission.txt"
dispatch_rc=0
# FOREIGN-PROJECT-ROOT-GUARD-01: cwd must agree with CLAUDE_PROJECT_DIR/ROOT for the
# no-pin ensure path, same convention P-i below uses -- without this cd the guard sees
# cwd's real git root (this worktree checkout) as foreign to TARGET and swaps
# PROJECT_ROOT away from TARGET, so `ensure` operates on the wrong repo entirely and
# the WORK_ROOT != PROJECT_ROOT precondition the pin-line assertions depend on never
# holds for the right reason.
( cd "${TARGET}" && bash "${DC}" --kind tooling \
  "P-g regression no flag fresh tree test fix the linter" >/dev/null 2>&1 ) || dispatch_rc=$?

if [[ ${dispatch_rc} -eq 0 ]]; then
  ok "P-g: dispatch exited 0 (no flag, regression)"
else
  bad "P-g: dispatch exited ${dispatch_rc} (expected 0)"
fi

CWD_G="$(cat "${SANDBOX}/pg-cwd.txt" 2>/dev/null || printf '')"
CWD_G_PHYS="$(cd "${CWD_G}" 2>/dev/null && pwd -P || printf '')"
if [[ -n "${CWD_G_PHYS}" && "${CWD_G_PHYS}" != "${RESUME_PHYS}" ]]; then
  ok "P-g: worker cwd is a fresh tree, != RESUME-ME-01"
else
  bad "P-g: worker cwd='${CWD_G_PHYS}' == RESUME or empty (regression)"
fi

# P-h(g): pin line present on the DEFAULT ensure-created path (PLACEMENT-PIN-DEFAULT-01)
if head -1 "${SANDBOX}/pg-mission.txt" 2>/dev/null | grep -q '^WORKTREE PIN: all edits go in '; then
  ok "P-h(g): prompt pin line present on default ensure-created path"
else
  bad "P-h(g): prompt pin line MISSING on default ensure-created path"
fi

# P-h(g2): pin line names the tree the worker actually ran in
if head -1 "${SANDBOX}/pg-mission.txt" 2>/dev/null | grep -q -- "${CWD_G}"; then
  ok "P-h(g2): pin line names the ensure-created worktree path"
else
  bad "P-h(g2): pin line does NOT name the worktree (expected '${CWD_G}')"
fi

# ════════════════════════════════════════════════════════════════════════════
# P-i: shared-tree dispatch (WORK_ROOT == PROJECT_ROOT) → no pin line (regression)
# ════════════════════════════════════════════════════════════════════════════
setup_env
export LEADV2_STUB_CWD_OUT="${SANDBOX}/pi-cwd.txt"
export LEADV2_STUB_MISSION_OUT="${SANDBOX}/pi-mission.txt"
# Stub the lane-worktree binary to "ensure" by printing $TARGET → fallback to shared tree
LANE_WT_STUB="${SANDBOX}/lane-wt-stub.sh"
cat > "${LANE_WT_STUB}" <<SH
#!/usr/bin/env bash
case "\${1:-}" in
  ensure) printf '%s\n' "${TARGET}" ;;
  path-of) exit 1 ;;
  *) exit 0 ;;
esac
SH
export LEADV2_DISPATCH_LANE_WORKTREE_BIN="${LANE_WT_STUB}"
# FOREIGN-PROJECT-ROOT-GUARD-01: cwd must agree with CLAUDE_PROJECT_DIR/ROOT for the
# shared-tree (no-pin) path, same convention test-foreign-project-root-guard.sh uses --
# without this cd the guard sees cwd's real git root (this worktree checkout) as foreign
# to TARGET and swaps PROJECT_ROOT away from TARGET, breaking the WORK_ROOT==PROJECT_ROOT
# equality this assertion depends on.
dispatch_rc=0
( cd "${TARGET}" && bash "${DC}" --kind tooling \
  "P-i shared tree no pin test fix the validator" >/dev/null 2>&1 ) || dispatch_rc=$?

if [[ ${dispatch_rc} -eq 0 ]]; then
  ok "P-i: dispatch exited 0 (shared-tree fallback)"
else
  bad "P-i: dispatch exited ${dispatch_rc} (expected 0)"
fi

if ! grep -q '^WORKTREE PIN:' "${SANDBOX}/pi-mission.txt" 2>/dev/null; then
  ok "P-i: no pin line on shared-tree dispatch"
else
  bad "P-i: pin line PRESENT on shared-tree dispatch (regression)"
fi

# ════════════════════════════════════════════════════════════════════════════
# Contract: leadv2-lane-liveness.sh --json actually carries the keys
# dispatch-code's _placement_probe_field reads (verdict/reason/age_s). Uses
# the REAL script, not the stub -- if the real --json shape drifts, this
# case fails loudly instead of the placement cases silently passing for the
# wrong reason (the exact hole P-e reopened).
# ════════════════════════════════════════════════════════════════════════════
LANE_LIVENESS_BIN="${PLUGIN_SCRIPTS}/leadv2-lane-liveness.sh"
real_row="$(bash "${LANE_LIVENESS_BIN}" --project-root "${TARGET}" --lane "nonexistent-lane-xyz" --no-codex --json 2>/dev/null || true)"
if python3 -c '
import json, sys
try:
    r = json.loads(sys.argv[1])
except Exception:
    sys.exit(1)
sys.exit(0 if isinstance(r, dict) and "verdict" in r and "reason" in r and "age_s" in r else 1)
' "${real_row}" 2>/dev/null; then
  ok "contract: leadv2-lane-liveness.sh --json emits a JSON object with verdict/reason/age_s"
else
  bad "contract: leadv2-lane-liveness.sh --json shape drifted (got: ${real_row})"
fi

printf '\n[LANE-PLACEMENT-01] passed=%d failed=%d\n' "${PASS}" "${FAIL}"
(( FAIL == 0 ))
