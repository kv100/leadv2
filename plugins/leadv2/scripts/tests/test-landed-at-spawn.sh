#!/usr/bin/env bash
# LANDED-AT-SPAWN-01 — spawn must never write terminal=landed; ledger keyed to target repo.
#
# Four assertions:
#   T-a  non-product async spawn → zero lines matching "terminal":"landed" in EITHER
#        repo's terminal ledger; reservation ledger DOES carry a confirmed row.
#   T-b  a genuine pre-spawn refusal → terminal row lands under the TARGET slug's
#        state dir; decoy's state dir has no such row.
#   T-c  regression: pre-spawn refused still writes at all (non-empty terminal file,
#        correct terminal/cause).
#   T-d  decoy state dir holds NO dispatch-ledger.jsonl line for this sig at all —
#        proves the leak is closed, not merely duplicated.
#
# Sandbox: two git fixture repos (target/ with a linked lane worktree, decoy/),
# sandbox LEADV2_STATE_BASE + LEADV2_DISPATCH_CACHE_DIR, stub GLM binary,
# decoy wired in as the caller session via CLAUDE_PROJECT_DIR.

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
bad() { printf '[TEST] FAIL: %s\n' "$1"; FAIL=$((FAIL+1)); }

SANDBOX="$(mktemp -d /tmp/leadv2-las-XXXXXX)"
cleanup() {
  rm -rf "${SANDBOX}"
}
trap cleanup EXIT

# ── Fixture repos ────────────────────────────────────────────────────────────
TARGET="${SANDBOX}/target"
DECOY="${SANDBOX}/decoy"
TARGET_WT="${SANDBOX}/target-wt"

new_repo() {
  local root="$1"
  mkdir -p "${root}"
  ( cd "${root}" && git init -q -b main \
    && git config user.email t@e.com && git config user.name t \
    && printf 'seed\n' > .gitignore && git add .gitignore && git commit -qm seed )
}

new_repo "${TARGET}"
new_repo "${DECOY}"
# Linked worktree of target so --git-common-dir resolves to target/.git
( cd "${TARGET}" && git worktree add -q "${TARGET_WT}" ) 2>/dev/null

# ── Sandbox state + cache dirs ───────────────────────────────────────────────
export LEADV2_STATE_BASE="${SANDBOX}/state"
export LEADV2_DISPATCH_CACHE_DIR="${SANDBOX}/cache"
STUB_RUNS="${SANDBOX}/glm-runs"
GLM_STUB="${SANDBOX}/glm-stub.sh"
JOURNAL_STUB="${SANDBOX}/journal-stub.sh"

# ── Stub GLM binary (bg creates a fake run record, status checks it) ─────────
cat > "${GLM_STUB}" <<'SH'
#!/usr/bin/env bash
RUNS="${LEADV2_STUB_GLM_RUNS:-/tmp/leadv2-stub-glm-runs}"
case "${1:-}" in
  bg)
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

# Stub journal (no-op — dispatch-code.sh calls it via bash, never exec)
cat > "${JOURNAL_STUB}" <<'SH'
#!/usr/bin/env bash
exit 0
SH

# ── Common dispatch env ──────────────────────────────────────────────────────
# Decoy is the CALLER SESSION (simulates persona-engine session dispatching
# into a leadv2 lane). Target worktree is the DISPATCH TARGET.
setup_env() {
  export CLAUDE_PROJECT_DIR="${DECOY}"
  export CLAUDE_PROJECT_ROOT="${DECOY}"
  unset PROJECT_ROOT 2>/dev/null || true
  export LEADV2_LANE_WORK_ROOT="${TARGET_WT}"
  export LEADV2_DISPATCH_GLM_BIN="${GLM_STUB}"
  export LEADV2_STUB_GLM_RUNS="${STUB_RUNS}"
  export LEADV2_JOURNAL_BIN="${JOURNAL_STUB}"
  export LEADV2_DISPATCH_LEDGER_BIN="${PLUGIN_SCRIPTS}/leadv2-dispatch-ledger.sh"
  export LEADV2_STATE_PATH_BIN="${STATE_PATH}"
  # Use v1 router with resolver missing → defaults to arm=glm
  export LEADV2_ROUTER_V2=0
  export GLM_POLICY_RESOLVER=""
  # Lane-shape gate off (default) — skip shape classification
  export LEADV2_LANE_SHAPE=off
  # No e2e/review gates — non-product dispatch
  export LEADV2_DISPATCH_E2E_GATE=0
  export LEADV2_DISPATCH_REVIEW_GATE=0
  # Short TTLs so stale rows from a prior case don't block
  export LEADV2_DISPATCH_PENDING_TTL_S=5
  export LEADV2_DISPATCH_CONFIRMED_TTL_S=10
}

# Resolve the terminal ledger path for a given repo root.
terminal_ledger_path() { # <repo_root>
  local repo="$1"
  PROJECT_ROOT="${repo}" LEADV2_STATE_BASE="${LEADV2_STATE_BASE}" \
    bash "${STATE_PATH}" --no-link dispatch-ledger.jsonl 2>/dev/null
}

# Resolve the reservation ledger path for a given slug.
reservation_ledger_path() { # <slug>
  printf '%s/dispatch-ledger/%s.jsonl' "${LEADV2_DISPATCH_CACHE_DIR}" "$1"
}

TARGET_SLUG="target"
DECOY_SLUG="decoy"
TARGET_TERMINAL="$(terminal_ledger_path "${TARGET}")"
DECOY_TERMINAL="$(terminal_ledger_path "${DECOY}")"
TARGET_RESERVATION="$(reservation_ledger_path "${TARGET_SLUG}")"
DECOY_RESERVATION="$(reservation_ledger_path "${DECOY_SLUG}")"

# ════════════════════════════════════════════════════════════════════════════
# T-a: non-product async spawn → no terminal=landed in EITHER ledger
# ════════════════════════════════════════════════════════════════════════════
setup_env
MISSION_A="LAS01-T-a: fix the flaky integration test in scripts/build.sh"
SIG_A="$(printf '%s' "${MISSION_A}" | tr -d '\r' | tr -s '[:space:]' ' ' | sed -e 's/^ //' -e 's/ $//' | shasum -a 256 | awk '{print $1}')"
SIG8_A="${SIG_A:0:8}"

dispatch_rc=0
bash "${DC}" --kind tooling "${MISSION_A}" >/dev/null 2>&1 || dispatch_rc=$?

if [[ ${dispatch_rc} -eq 0 ]]; then
  ok "T-a: dispatch exited 0 (spawn succeeded)"
else
  bad "T-a: dispatch exited ${dispatch_rc} (expected 0)"
fi

# T-a assertion 1: no landed row in target terminal ledger
target_landed=""
[[ -f "${TARGET_TERMINAL}" ]] && target_landed="$(grep -c '"terminal":"landed"' "${TARGET_TERMINAL}" 2>/dev/null || printf 0)"
if [[ "${target_landed}" == "0" || -z "${target_landed}" ]]; then
  ok "T-a: no terminal=landed in TARGET terminal ledger"
else
  bad "T-a: TARGET terminal ledger has ${target_landed} landed row(s)"
fi

# T-a assertion 2: no landed row in decoy terminal ledger
decoy_landed=""
[[ -f "${DECOY_TERMINAL}" ]] && decoy_landed="$(grep -c '"terminal":"landed"' "${DECOY_TERMINAL}" 2>/dev/null || printf 0)"
if [[ "${decoy_landed}" == "0" || -z "${decoy_landed}" ]]; then
  ok "T-a: no terminal=landed in DECOY terminal ledger"
else
  bad "T-a: DECOY terminal ledger has ${decoy_landed} landed row(s)"
fi

# T-a assertion 3: reservation ledger DOES carry a confirmed row for this sig
target_confirmed=""
[[ -f "${TARGET_RESERVATION}" ]] && target_confirmed="$(grep -c "\"task_sig\":\"${SIG_A}\"" "${TARGET_RESERVATION}" 2>/dev/null | head -1 || printf 0)"
if [[ "${target_confirmed}" != "0" && -n "${target_confirmed}" ]]; then
  ok "T-a: reservation ledger has a row for this sig"
else
  bad "T-a: reservation ledger has no row for sig ${SIG8_A}"
fi

# T-a assertion 4: confirmed state exists
if [[ -f "${TARGET_RESERVATION}" ]] && grep -q "\"state\":\"confirmed\"" "${TARGET_RESERVATION}" 2>/dev/null; then
  ok "T-a: reservation row is confirmed"
else
  bad "T-a: reservation row is NOT confirmed (or missing)"
fi

# ════════════════════════════════════════════════════════════════════════════
# T-b: pre-spawn refusal → terminal lands under TARGET slug, NOT decoy
# T-d: decoy has no row for this sig at all
# ════════════════════════════════════════════════════════════════════════════
setup_env
# Exclude ALL arms → pre-spawn refusal (all_arms_excluded)
# GLM-53-FLASH-ARM-01: glm-flash joined the dispatchable set — excluding the
# old four leaves it as the last arm standing and the refusal never happens.
export LEADV2_EXCLUDED_ARMS="glm glm-flash kimi codex sonnet"

MISSION_B="LAS01-T-b: refactor the plugin cache validator scripts/sync.sh"
SIG_B="$(printf '%s' "${MISSION_B}" | tr -d '\r' | tr -s '[:space:]' ' ' | sed -e 's/^ //' -e 's/ $//' | shasum -a 256 | awk '{print $1}')"
SIG8_B="${SIG_B:0:8}"

dispatch_rc_b=0
bash "${DC}" --kind tooling "${MISSION_B}" >/dev/null 2>&1 || dispatch_rc_b=$?

if [[ ${dispatch_rc_b} -eq 4 ]]; then
  ok "T-b: dispatch exited 4 (pre-spawn refusal)"
else
  bad "T-b: dispatch exited ${dispatch_rc_b} (expected 4)"
fi

# T-b: terminal row exists in TARGET terminal ledger for this sig
if [[ -f "${TARGET_TERMINAL}" ]] && grep -q "\"task_sig\":\"${SIG8_B}\"" "${TARGET_TERMINAL}" 2>/dev/null; then
  ok "T-b: terminal row landed in TARGET state dir for sig ${SIG8_B}"
else
  bad "T-b: NO terminal row in TARGET state dir for sig ${SIG8_B}"
fi

# T-d: NO terminal row in DECOY terminal ledger for this sig
decoy_has_sig=""
[[ -f "${DECOY_TERMINAL}" ]] && decoy_has_sig="$(grep -c "\"task_sig\":\"${SIG8_B}\"" "${DECOY_TERMINAL}" 2>/dev/null || printf 0)"
if [[ "${decoy_has_sig}" == "0" || -z "${decoy_has_sig}" ]]; then
  ok "T-d: NO terminal row in DECOY state dir for sig ${SIG8_B}"
else
  bad "T-d: DECOY state dir HAS a terminal row for sig ${SIG8_B} (leak not closed)"
fi

# ════════════════════════════════════════════════════════════════════════════
# T-c: regression — pre-spawn refused still writes a terminal row (non-empty,
#      correct terminal=refused, cause=all_arms_excluded)
# ════════════════════════════════════════════════════════════════════════════
if [[ -f "${TARGET_TERMINAL}" ]] && [[ -s "${TARGET_TERMINAL}" ]]; then
  ok "T-c: terminal ledger is non-empty (pre-spawn refusal still writes)"
else
  bad "T-c: terminal ledger is empty or missing (regression: refusal writes nothing)"
fi

if [[ -f "${TARGET_TERMINAL}" ]] && grep -q '"terminal":"refused"' "${TARGET_TERMINAL}" 2>/dev/null; then
  ok "T-c: terminal row has terminal=refused"
else
  bad "T-c: terminal row missing terminal=refused"
fi

if [[ -f "${TARGET_TERMINAL}" ]] && grep -q '"cause":"all_arms_excluded"' "${TARGET_TERMINAL}" 2>/dev/null; then
  ok "T-c: terminal row has cause=all_arms_excluded"
else
  bad "T-c: terminal row missing cause=all_arms_excluded"
fi

# ── Static guard: no _dl_note ... landed on the spawn path ───────────────────
if ! grep -q '_dl_note.*landed.*spawned_' "${DC}" 2>/dev/null; then
  ok "T-static: no _dl_note landed/spawned_ call in dispatch-code.sh"
else
  bad "T-static: _dl_note landed/spawned_ STILL PRESENT in dispatch-code.sh"
fi

printf '\n[LANDED-AT-SPAWN-01] passed=%d failed=%d\n' "${PASS}" "${FAIL}"
(( FAIL == 0 ))
