#!/usr/bin/env bash
# tests/test-glm-deferred-ladder.sh — V3-GLM-LADDER-01
#
# Incident 2026-08-19: GLM-FIRST-01 was silently inverted for a full day —
# every dispatch logged arm_refused reason=glm_refused_quota_gate, codex
# reported credits={"balance":"0","has_credits":false}, 100% of workers ran
# on sonnet, and nobody was told. This suite proves the three levers that
# make that degradation visible and recoverable:
#
#   (a) a quota-refused glm-fitting dispatch writes a park row to
#       docs/leadv2/glm-deferred.jsonl BEFORE the sonnet fallback worker is
#       confirmed live (ordering, not just presence)
#   (b) `leadv2-dispatch-code.sh glm-deferred --list` prints the parked sig8
#   (c) two credit-empty computations inside 24h emit exactly ONE
#       codex_credits_empty journal line; a third after the stamp is
#       back-dated past 24h emits a second
#   (d) the REAL leadv2-broad-status.sh renderer (not a source grep — the
#       CLAIM-EVIDENCE-GATE-01 lesson) writes founder-status.md containing
#       "sonnet-фолбэков сегодня: 1 (glm quota)" after one glm->sonnet
#       fallback
#
# Harness mirrors test-router-v2-retired-arm.sh (poison fence + stubbed GLM/
# router-v2 binaries) for (a)/(b)/(c), and test-broad-status-renderer-truth.sh
# (stubbed collector + claude, real renderer) for (d).
set -uo pipefail

# BURN-GOVERNOR-01: the burn gate defaults ON and reads the host's real
# ~/.claude/burn/history.db -- a hot host would red this suite on `exit 6`.
export LEADV2_BURN_GOVERNOR=0

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DISPATCH_BIN="${SCRIPT_DIR}/../leadv2-dispatch-code.sh"
BROAD_STATUS_SH="${SCRIPT_DIR}/../leadv2-broad-status.sh"
TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "${TMP_ROOT}"' EXIT
FAIL=0

pass() { printf 'PASS: %s\n' "$1"; }
fail() { printf 'FAIL: %s -- %s\n' "$1" "$2"; FAIL=1; }

bash -n "${SCRIPT_DIR}/test-glm-deferred-ladder.sh" 2>/dev/null || { echo "ERROR: self syntax check failed"; exit 1; }

for _sh in "${DISPATCH_BIN}" "${BROAD_STATUS_SH}"; do
  bash -n "${_sh}" || { echo "ERROR: bash -n failed for ${_sh}"; exit 1; }
done

# ── fail-closed spawn fence: codex/kimi must never be invoked in this suite ──
for _arm in kimi codex; do
  _poison="${TMP_ROOT}/poison-${_arm}.sh"
  printf '#!/usr/bin/env bash\nprintf "POISON: real provider spawn attempted\\n" >&2\nexit 99\n' > "${_poison}"
  chmod +x "${_poison}"
done
export LEADV2_DISPATCH_KIMI_BIN="${TMP_ROOT}/poison-kimi.sh"
export LEADV2_DISPATCH_CODEX_BIN="${TMP_ROOT}/poison-codex.sh"

unset LEADV2_PROJECT_ROOT LEADV2_LANE_WORK_ROOT LEADV2_TASK_ID \
      LEADV2_PARENT_SESSION_ID LEADV2_DISPATCH_LANE_NAME LEADV2_EXCLUDED_ARMS
export LEADV2_ARM_EARLY_VERDICT_S=0

make_tenant_root() {  # <root>
  local root="$1"
  mkdir -p "${root}/.claude/ref"
  cat > "${root}/.claude/ref/leadv2-routing.yaml" <<'YAML'
router:
  dispatch_ladder:
    - id: glm
      provider: glm
      model: glm-5.2
      when: [all]
      effort: standard
    - id: codex
      provider: codex
      model: gpt-5.6-terra
      when: [all]
      effort: standard
    - id: sonnet
      provider: anthropic
      model: sonnet
      when: [all]
      effort: standard
YAML
}

make_refusing_glm() {  # <path>
  cat > "$1" <<'SH'
#!/usr/bin/env bash
echo '[glm-quota-gate] LEADV2_DISPATCH_REFUSED: quota_gate' >&2
exit 1
SH
  chmod +x "$1"
}

# <path> <ordered> [<credits-json>] — resolve --chain stub for the reroute site
make_qg_rv2() {
  local path="$1" ordered="$2" credits="${3:-{\}}"
  cat > "${path}" <<SH
#!/usr/bin/env bash
case "\${1:-}" in
  resolve) printf 'eligible=sonnet\nordered=${ordered}\nheadroom={}\nvector=[]\ncredits=${credits}\n' ;;
  *) exit 1 ;;
esac
SH
  chmod +x "${path}"
}

# <path> <deferred-jsonl-path> — sonnet spawn that always lands, and snapshots
# the park file's content the instant it is invoked (proves ordering for leg a).
make_ok_sonnet() {
  local path="$1" deferred="$2" snap="$3"
  # PID: this TEST SCRIPT's own pid ($$, baked in at generation time — NOT
  # $PPID read inside the stub, which would resolve to the command-substitution
  # subshell that invokes it, and that subshell is already gone by the time
  # dispatch-code.sh runs its liveness kill -0 a moment later). The test
  # script's own pid stays alive for the suite's whole synchronous run, so
  # the liveness check is genuinely true, just of a different (still-live)
  # process than the real claude-subsession.sh would have spawned.
  cat > "${path}" <<SH
#!/usr/bin/env bash
cp "${deferred}" "${snap}" 2>/dev/null || : > "${snap}"
printf 'PID=%s LABEL=test SESSION_ID=test\n' "$$"
SH
  chmod +x "${path}"
}

extract_sig8() {  # <dispatch-output>
  printf '%s\n' "$1" | grep -oE 'task=[0-9a-f]{8}' | head -1 | cut -d= -f2
}

# ============================================================================
# (a)+(b)+(d): one glm-quota-refused dispatch that falls to sonnet.
# ============================================================================
ROOT="${TMP_ROOT}/root-ab"
make_tenant_root "${ROOT}"
DEFERRED="${ROOT}/docs/leadv2/glm-deferred.jsonl"
SNAP="${TMP_ROOT}/park-snapshot-at-sonnet-spawn.jsonl"
GLM_BIN="${TMP_ROOT}/refusing-glm.sh"; make_refusing_glm "${GLM_BIN}"
RV2_BIN="${TMP_ROOT}/ab-rv2.sh"; make_qg_rv2 "${RV2_BIN}" "sonnet"
SONNET_BIN="${TMP_ROOT}/ab-sonnet.sh"; make_ok_sonnet "${SONNET_BIN}" "${DEFERRED}" "${SNAP}"

out_ab="$(CLAUDE_PROJECT_ROOT="${ROOT}" \
  LEADV2_DISPATCH_CACHE_DIR="${TMP_ROOT}/ab-cache" \
  LEADV2_DISPATCH_ARCHITECT_GATE=0 \
  LEADV2_ROUTER_V2_BIN="${RV2_BIN}" \
  LEADV2_DISPATCH_GLM_BIN="${GLM_BIN}" \
  LEADV2_DISPATCH_SUBSESSION_BIN="${SONNET_BIN}" \
  LEADV2_DISPATCH_SPAWN=1 \
  bash "${DISPATCH_BIN}" 'plugin-only glm-deferred-ladder ab probe' 2>&1)"
sig8_ab="$(extract_sig8 "${out_ab}")"

if [[ -z "${sig8_ab}" ]]; then
  fail "(a) setup: could not extract sig8 from dispatch output" "output=${out_ab}"
elif [[ ! -f "${DEFERRED}" ]] || ! grep -q "\"sig8\":\"${sig8_ab}\"" "${DEFERRED}"; then
  fail "(a) park row missing for sig8=${sig8_ab}" "deferred_file=$(cat "${DEFERRED}" 2>/dev/null || echo '<missing>')"
elif ! grep -q '"reason":"glm_refused_quota_gate"' "${DEFERRED}"; then
  fail "(a) park row missing reason=glm_refused_quota_gate" "deferred_file=$(cat "${DEFERRED}")"
elif [[ ! -f "${SNAP}" ]] || ! grep -q "\"sig8\":\"${sig8_ab}\"" "${SNAP}"; then
  fail "(a) park row was NOT present before the sonnet worker was spawned (ordering violated)" \
    "snapshot=$(cat "${SNAP}" 2>/dev/null || echo '<missing>')"
else
  pass "(a) park row written before sonnet fallback worker spawn (ordering holds)"
fi

if grep -q 'POISON:' <<<"${out_ab}"; then
  fail "(a) poison fence" "a real codex/kimi bin was invoked: ${out_ab}"
else
  pass "(a) poison fence held"
fi

# (b) glm-deferred --list prints the parked sig8
list_out="$(CLAUDE_PROJECT_ROOT="${ROOT}" bash "${DISPATCH_BIN}" glm-deferred --list 2>&1)"
if [[ -n "${sig8_ab}" ]] && grep -q "^${sig8_ab} " <<<"${list_out}"; then
  pass "(b) glm-deferred --list prints the parked sig8"
else
  fail "(b) glm-deferred --list missing sig8=${sig8_ab}" "list_out=${list_out}"
fi

empty_root="${TMP_ROOT}/root-empty"
make_tenant_root "${empty_root}"
empty_list="$(CLAUDE_PROJECT_ROOT="${empty_root}" bash "${DISPATCH_BIN}" glm-deferred --list 2>&1)"
if [[ "${empty_list}" == "no deferred glm tasks" ]]; then
  pass "(b) glm-deferred --list prints 'no deferred glm tasks' when empty"
else
  fail "(b) empty-state message wrong" "got='${empty_list}'"
fi

# ============================================================================
# (c) codex credit watchdog: two computations within 24h -> ONE journal line;
# a third after the stamp is back-dated past 24h -> a second line.
# ============================================================================
ROOT_C="${TMP_ROOT}/root-c"
make_tenant_root "${ROOT_C}"
JOURNAL_C="${TMP_ROOT}/journal-c.log"
JOURNAL_C_BIN="${TMP_ROOT}/journal-c.sh"
printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$*" >> "%s"\n' "${JOURNAL_C}" > "${JOURNAL_C_BIN}"
chmod +x "${JOURNAL_C_BIN}"
: > "${JOURNAL_C}"

GLM_BIN_C="${TMP_ROOT}/refusing-glm-c.sh"; make_refusing_glm "${GLM_BIN_C}"
CREDITS_EMPTY='{"codex":{"has_credits":false}}'
RV2_C="${TMP_ROOT}/c-rv2.sh"; make_qg_rv2 "${RV2_C}" "sonnet" "${CREDITS_EMPTY}"
DEFERRED_C="${ROOT_C}/docs/leadv2/glm-deferred.jsonl"
SNAP_C="${TMP_ROOT}/snap-c.jsonl"
SONNET_C="${TMP_ROOT}/c-sonnet.sh"; make_ok_sonnet "${SONNET_C}" "${DEFERRED_C}" "${SNAP_C}"

# C1 harness fix: ALL run_c calls share ONE cache dir. The prior per-run cache dir
# hid the ARM-LADDER-HAS-NO-QUOTA-PRECHECK-01 bug — after the FIRST refusal, the
# quota-precheck loop benches glm out of candidate_arms entirely on later runs, so
# leg (c) must keep passing even though glm is no longer attempted on run 2+; it
# asserts journal lines emitted in _codex_credits_watch, which runs independently
# of which arm wins.
CACHE_C="${TMP_ROOT}/c-cache"
run_c() {  # <mission-text>
  CLAUDE_PROJECT_ROOT="${ROOT_C}" \
    LEADV2_DISPATCH_CACHE_DIR="${CACHE_C}" \
    LEADV2_DISPATCH_ARCHITECT_GATE=0 \
    LEADV2_ROUTER_V2_BIN="${RV2_C}" \
    LEADV2_DISPATCH_GLM_BIN="${GLM_BIN_C}" \
    LEADV2_DISPATCH_SUBSESSION_BIN="${SONNET_C}" \
    LEADV2_DISPATCH_SPAWN=1 \
    LEADV2_JOURNAL_BIN="${JOURNAL_C_BIN}" \
    JOURNAL_TASK="glm-deferred-ladder-c" \
    bash "${DISPATCH_BIN}" "$1" >/dev/null 2>&1 || true
}

run_c 'plugin-only glm-deferred-ladder credit watchdog probe 1'
run_c 'plugin-only glm-deferred-ladder credit watchdog probe 2'
n_after_2="$(grep -c 'codex_credits_empty since=' "${JOURNAL_C}" 2>/dev/null || true)"
[[ "${n_after_2}" =~ ^[0-9]+$ ]] || n_after_2=0

if [[ "${n_after_2}" -eq 1 ]]; then
  pass "(c) two credit-empty computations within 24h emit exactly ONE journal line"
else
  fail "(c) expected exactly 1 codex_credits_empty line after 2 runs, got ${n_after_2}" \
    "journal=$(cat "${JOURNAL_C}")"
fi

STAMP_C="${ROOT_C}/docs/leadv2/.codex-credits-empty.stamp"
if [[ -f "${STAMP_C}" ]]; then
  backdated="$(date -u -v-25H +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -d '-25 hours' +%Y-%m-%dT%H:%M:%SZ)"
  printf 'since=%s\n' "${backdated}" > "${STAMP_C}"
else
  fail "(c) setup" "stamp file missing at ${STAMP_C}"
fi

run_c 'plugin-only glm-deferred-ladder credit watchdog probe 3'
n_after_3="$(grep -c 'codex_credits_empty since=' "${JOURNAL_C}" 2>/dev/null || true)"
[[ "${n_after_3}" =~ ^[0-9]+$ ]] || n_after_3=0

if [[ "${n_after_3}" -eq 2 ]]; then
  pass "(c) a third computation after the stamp ages past 24h emits a second journal line"
else
  fail "(c) expected 2 codex_credits_empty lines after the back-dated 3rd run, got ${n_after_3}" \
    "journal=$(cat "${JOURNAL_C}")"
fi

# ============================================================================
# (d) rendered artifact: the REAL leadv2-broad-status.sh renders
# "sonnet-фолбэков сегодня: 1 (glm quota)" after the (a) fallback landed —
# NOT a source grep (CLAIM-EVIDENCE-GATE-01).
# ============================================================================
STUBS_D="${TMP_ROOT}/stubs-d"
mkdir -p "${STUBS_D}"
cat > "${STUBS_D}/collector.sh" <<'EOF'
#!/usr/bin/env bash
out=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --out) out="$2"; shift 2 ;;
    *) shift ;;
  esac
done
[[ -z "$out" ]] && exit 1
cat > "$out" <<'JSON'
{"sections": {
  "lanes": {"ok": true, "data": {"table": [], "questions": [], "degraded": []}},
  "lane_detail": {"ok": true, "data": {"lanes": []}}
}}
JSON
EOF
cat > "${STUBS_D}/claude.sh" <<'EOF'
#!/usr/bin/env bash
printf '{"result":"нет данных за сегодня\nвопросов нет"}'
EOF
chmod +x "${STUBS_D}/collector.sh" "${STUBS_D}/claude.sh"

FOUNDER_STATUS_D="${ROOT}/docs/leadv2/founder-status.md"
# CORE-OFFLINE-WORKTREE-GAP-01 diagnostic finding: the queue section (which
# carries the provider-health/sonnet-fallback line) is ALWAYS compacted out
# of the short founder-status.md into founder-status-full.md whenever the
# queue has any content (leadv2-broad-status.sh "rule 6: nothing cut is
# lost" -- see hidden_bits/hidden_note, broad-status.sh:786-796). The
# compact file only ever gets a "(скрыто: N строк очереди — see
# founder-status-full.md)" pointer, never the line itself -- so this is the
# artifact the assertion must read, not a product bug.
FOUNDER_STATUS_FULL_D="${ROOT}/docs/leadv2/founder-status-full.md"
LEADV2_PROJECT_ROOT="${ROOT}" LEADV2_STATE_ROOT="${TMP_ROOT}/state-d" \
  LEADV2_STATUS_COLLECTOR_BIN="${STUBS_D}/collector.sh" \
  LEADV2_BROAD_STATUS_CLAUDE_BIN="${STUBS_D}/claude.sh" \
  LEADV2_BROAD_STATUS_BEAT_AT="2026-08-20T00:00:00Z" \
  LEADV2_BROAD_STATUS_DISPATCHED="1" \
  bash "${BROAD_STATUS_SH}" >/dev/null 2>&1 || true

if [[ ! -f "${FOUNDER_STATUS_FULL_D}" ]]; then
  fail "(d) founder-status-full.md not written" "renderer produced no artifact"
elif grep -q 'sonnet-фолбэков сегодня: 1 (glm_refused_quota_gate)' "${FOUNDER_STATUS_FULL_D}"; then
  pass "(d) rendered founder-status-full.md contains sonnet-фолбэков сегодня: 1 (glm_refused_quota_gate) -- real reason variant, not hardcoded 'glm quota'"
else
  fail "(d) expected sonnet-fallback line missing from rendered artifact" \
    "content=$(cat "${FOUNDER_STATUS_FULL_D}")"
fi

# ── negative: a day with no fallback renders no such line ──────────────────
ROOT_NEG="${TMP_ROOT}/root-neg"
make_tenant_root "${ROOT_NEG}"
FOUNDER_STATUS_FULL_NEG="${ROOT_NEG}/docs/leadv2/founder-status-full.md"
LEADV2_PROJECT_ROOT="${ROOT_NEG}" LEADV2_STATE_ROOT="${TMP_ROOT}/state-neg" \
  LEADV2_STATUS_COLLECTOR_BIN="${STUBS_D}/collector.sh" \
  LEADV2_BROAD_STATUS_CLAUDE_BIN="${STUBS_D}/claude.sh" \
  LEADV2_BROAD_STATUS_BEAT_AT="2026-08-20T00:00:00Z" \
  LEADV2_BROAD_STATUS_DISPATCHED="1" \
  bash "${BROAD_STATUS_SH}" >/dev/null 2>&1 || true

if [[ -f "${FOUNDER_STATUS_FULL_NEG}" ]] && ! grep -q 'сонн\|sonnet-фолбэков' "${FOUNDER_STATUS_FULL_NEG}"; then
  pass "(d) a day with no fallback renders no sonnet-fallback line"
else
  fail "(d) unexpected sonnet-fallback line with zero fallbacks" \
    "content=$(cat "${FOUNDER_STATUS_FULL_NEG}" 2>/dev/null || echo '<missing>')"
fi

# ============================================================================
# (e) shared-cache double refusal: ONE cache dir, two dispatches, refusing glm.
# Run 1 attempts glm live (refused -> glm_refused_quota_gate). Run 2, same cache,
# is benched by the quota-precheck loop (glm never attempted live this time) ->
# glm_refused_quota_precheck. Proves C1: the counter and park queue both see
# BOTH refusals, not just the first live one.
# ============================================================================
ROOT_E="${TMP_ROOT}/root-e"
make_tenant_root "${ROOT_E}"
DEFERRED_E="${ROOT_E}/docs/leadv2/glm-deferred.jsonl"
GLM_BIN_E="${TMP_ROOT}/refusing-glm-e.sh"; make_refusing_glm "${GLM_BIN_E}"
RV2_E="${TMP_ROOT}/e-rv2.sh"; make_qg_rv2 "${RV2_E}" "sonnet"
CACHE_E="${TMP_ROOT}/e-cache"

run_e() {  # <mission-text> -> stdout: dispatch output
  local snap="${TMP_ROOT}/e-snap-$$-${RANDOM}.jsonl"
  local sonnet_e="${TMP_ROOT}/e-sonnet-${RANDOM}.sh"
  make_ok_sonnet "${sonnet_e}" "${DEFERRED_E}" "${snap}"
  CLAUDE_PROJECT_ROOT="${ROOT_E}" \
    LEADV2_DISPATCH_CACHE_DIR="${CACHE_E}" \
    LEADV2_DISPATCH_ARCHITECT_GATE=0 \
    LEADV2_ROUTER_V2_BIN="${RV2_E}" \
    LEADV2_DISPATCH_GLM_BIN="${GLM_BIN_E}" \
    LEADV2_DISPATCH_SUBSESSION_BIN="${sonnet_e}" \
    LEADV2_DISPATCH_SPAWN=1 \
    bash "${DISPATCH_BIN}" "$1" 2>&1
}

out_e1="$(run_e 'plugin-only glm-deferred-ladder shared-cache probe one')"
sig8_e1="$(extract_sig8 "${out_e1}")"
out_e2="$(run_e 'plugin-only glm-deferred-ladder shared-cache probe two')"
sig8_e2="$(extract_sig8 "${out_e2}")"

_today_e="$(date -u +%Y%m%d)"
EXC_E="${ROOT_E}/docs/leadv2/.arm-exceptions-${_today_e}"

if [[ -z "${sig8_e1}" || -z "${sig8_e2}" || "${sig8_e1}" == "${sig8_e2}" ]]; then
  fail "(e) setup: expected two distinct sig8s" "sig8_e1=${sig8_e1} sig8_e2=${sig8_e2}"
elif [[ ! -f "${EXC_E}" ]] || ! grep -q '^count=2$' "${EXC_E}"; then
  fail "(e) expected count=2 after two distinct-sig8 refusals" "content=$(cat "${EXC_E}" 2>/dev/null || echo '<missing>')"
elif ! grep -qF "sig8=${sig8_e1}" "${EXC_E}" || ! grep -qF "sig8=${sig8_e2}" "${EXC_E}"; then
  fail "(e) expected both sig8s recorded" "content=$(cat "${EXC_E}")"
else
  pass "(e) shared-cache double refusal: count=2, both distinct sig8s recorded"
fi

if [[ ! -f "${DEFERRED_E}" ]] || [[ "$(grep -cF "\"sig8\":\"${sig8_e1}\"" "${DEFERRED_E}" 2>/dev/null)" -lt 1 ]] \
  || [[ "$(grep -cF "\"sig8\":\"${sig8_e2}\"" "${DEFERRED_E}" 2>/dev/null)" -lt 1 ]]; then
  fail "(e) park queue missing a row for one of the two sig8s" "content=$(cat "${DEFERRED_E}" 2>/dev/null || echo '<missing>')"
else
  pass "(e) park queue holds a row for both distinct sig8s"
fi

if grep -qF "\"sig8\":\"${sig8_e2}\"" "${DEFERRED_E}" 2>/dev/null \
  && grep -A0 "\"sig8\":\"${sig8_e2}\"" "${DEFERRED_E}" | grep -q '"reason":"glm_refused_quota_precheck"'; then
  pass "(e) run 2's park row carries reason=glm_refused_quota_precheck (benched, never attempted)"
else
  fail "(e) run 2's park row should carry reason=glm_refused_quota_precheck" "content=$(cat "${DEFERRED_E}" 2>/dev/null)"
fi

# ============================================================================
# (e2) same-sig8 idempotence: a second bump for a sig8 already present leaves
# count unchanged. Exercises _arm_exception_bump directly (extracted from the
# real script, not reimplemented) to avoid the dedup/duplicate-task-signature
# machinery a second live dispatch of the same mission would hit.
# ============================================================================
ROOT_E2="${TMP_ROOT}/root-e2"
mkdir -p "${ROOT_E2}/docs/leadv2"
BUMP_SNIPPET="${TMP_ROOT}/bump-snippet.sh"
{
  printf '#!/usr/bin/env bash\nset -uo pipefail\n'
  printf 'source "%s"\n' "${SCRIPT_DIR}/../leadv2-portable-lock.sh"
  printf 'PROJECT_ROOT="%s"\n' "${ROOT_E2}"
  printf '_leadv2_arm_exceptions_path() { printf "%%s/docs/leadv2/.arm-exceptions-%%s" "${PROJECT_ROOT}" "${1}"; }\n'
  sed -n '/^_arm_exception_bump()/,/^}$/p' "${DISPATCH_BIN}"
  printf '_arm_exception_bump "glm_refused_quota_gate" "aaaaaaaa"\n'
  printf '_arm_exception_bump "glm_refused_quota_gate" "aaaaaaaa"\n'
} > "${BUMP_SNIPPET}"
bash "${BUMP_SNIPPET}" >/dev/null 2>&1
EXC_E2="${ROOT_E2}/docs/leadv2/.arm-exceptions-$(date -u +%Y%m%d)"
if [[ -f "${EXC_E2}" ]] && grep -q '^count=1$' "${EXC_E2}"; then
  pass "(e2) a repeat bump for an already-present sig8 is a no-op (count stays 1)"
else
  fail "(e2) expected count=1 after two bumps of the same sig8" "content=$(cat "${EXC_E2}" 2>/dev/null || echo '<missing>')"
fi

# ============================================================================
# (f)/(g)/(h)/(i): glm-deferred --retry-all, all four D5 outcomes.
# ============================================================================
ROOT_R="${TMP_ROOT}/root-retry"
make_tenant_root "${ROOT_R}"
DEFERRED_R="${ROOT_R}/docs/leadv2/glm-deferred.jsonl"
MDIR_R="${ROOT_R}/docs/leadv2/glm-deferred.d"
mkdir -p "${MDIR_R}"

park_row() {  # <sig8> <mission_path>
  python3 -c '
import json, sys
sig8, mission_path = sys.argv[1], sys.argv[2]
print(json.dumps({
    "sig8": sig8, "mission_path": mission_path, "founder_task_id": "",
    "refused_at": "2026-08-20T00:00:00Z", "reason": "glm_refused_quota_gate",
    "quota_pct": None, "retried_at": None,
}, separators=(",", ":")))
' "$1" "$2" >> "${DEFERRED_R}"
}

RV2_R_GLM="${TMP_ROOT}/r-rv2-glm.sh"
cat > "${RV2_R_GLM}" <<SH
#!/usr/bin/env bash
case "\${1:-}" in
  resolve) printf 'eligible=glm\nordered=glm\nheadroom={}\nvector=[]\ncredits={}\n' ;;
  *) exit 1 ;;
esac
SH
chmod +x "${RV2_R_GLM}"

# (g) reap: parked sig8 already has a terminal row in the ledger.
SIG_G="gggggggg"
park_row "${SIG_G}" ""
LEDGER_G="${TMP_ROOT}/ledger-g.sh"
printf '#!/usr/bin/env bash\n[[ "${1:-}" == "exists" ]] && exit 0\nexit 1\n' > "${LEDGER_G}"
chmod +x "${LEDGER_G}"

out_g="$(CLAUDE_PROJECT_ROOT="${ROOT_R}" LEADV2_DISPATCH_CACHE_DIR="${TMP_ROOT}/cache-g" LEADV2_DISPATCH_LEDGER_BIN="${LEDGER_G}" \
  bash "${DISPATCH_BIN}" glm-deferred --retry-all 2>&1)"
list_after_g="$(CLAUDE_PROJECT_ROOT="${ROOT_R}" LEADV2_DISPATCH_CACHE_DIR="${TMP_ROOT}/cache-g" LEADV2_DISPATCH_LEDGER_BIN="${LEDGER_G}" \
  bash "${DISPATCH_BIN}" glm-deferred --list 2>&1)"
if grep -q "reaped ${SIG_G} fallback_landed" <<<"${out_g}" && ! grep -q "${SIG_G}" <<<"${list_after_g}"; then
  pass "(g) a parked row whose sig8 already landed is reaped, not retried"
else
  fail "(g) expected 'reaped ${SIG_G} fallback_landed' and the row gone from --list" \
    "out=${out_g} list=${list_after_g}"
fi

# (h) no-mission negative: mission_path empty -> skipped, row stays.
SIG_H="hhhhhhhh"
park_row "${SIG_H}" ""
out_h="$(CLAUDE_PROJECT_ROOT="${ROOT_R}" LEADV2_DISPATCH_CACHE_DIR="${TMP_ROOT}/cache-h" LEADV2_ROUTER_V2_BIN="${RV2_R_GLM}" \
  bash "${DISPATCH_BIN}" glm-deferred --retry-all 2>&1)"
list_after_h="$(CLAUDE_PROJECT_ROOT="${ROOT_R}" LEADV2_DISPATCH_CACHE_DIR="${TMP_ROOT}/cache-h" bash "${DISPATCH_BIN}" glm-deferred --list 2>&1)"
if grep -q "skipped_no_mission ${SIG_H}" <<<"${out_h}" && grep -q "${SIG_H}" <<<"${list_after_h}"; then
  pass "(h) a parked row with no usable mission is skipped and stays in the queue (H3)"
else
  fail "(h) expected 'skipped_no_mission ${SIG_H}' and the row still in --list" \
    "out=${out_h} list=${list_after_h}"
fi

# (i) failed dispatch negative: real mission, launcher fixture fails.
ROOT_I="${TMP_ROOT}/root-retry-i"
make_tenant_root "${ROOT_I}"
DEFERRED_I="${ROOT_I}/docs/leadv2/glm-deferred.jsonl"
MDIR_I="${ROOT_I}/docs/leadv2/glm-deferred.d"
mkdir -p "${MDIR_I}"
SIG_I="iiiiiiii"
MPATH_I="${MDIR_I}/${SIG_I}.md"
printf 'plugin-only glm-deferred-ladder retry-all failing-dispatch probe' > "${MPATH_I}"
python3 -c '
import json
row = {"sig8": "'"${SIG_I}"'", "mission_path": "'"${MPATH_I}"'", "founder_task_id": "",
       "refused_at": "2026-08-20T00:00:00Z", "reason": "glm_refused_quota_gate",
       "quota_pct": None, "retried_at": None}
print(json.dumps(row, separators=(",", ":")))
' >> "${DEFERRED_I}"
LEDGER_I="${TMP_ROOT}/ledger-i.sh"
printf '#!/usr/bin/env bash\nexit 1\n' > "${LEDGER_I}"
chmod +x "${LEDGER_I}"
GLM_BIN_I="${TMP_ROOT}/refusing-glm-i.sh"; make_refusing_glm "${GLM_BIN_I}"

out_i="$(CLAUDE_PROJECT_ROOT="${ROOT_I}" LEADV2_DISPATCH_CACHE_DIR="${TMP_ROOT}/cache-i" LEADV2_DISPATCH_LEDGER_BIN="${LEDGER_I}" \
  LEADV2_ROUTER_V2_BIN="${RV2_R_GLM}" LEADV2_DISPATCH_GLM_BIN="${GLM_BIN_I}" \
  LEADV2_DISPATCH_ARCHITECT_GATE=0 LEADV2_DISPATCH_SPAWN=1 \
  bash "${DISPATCH_BIN}" glm-deferred --retry-all 2>&1)"
list_after_i="$(CLAUDE_PROJECT_ROOT="${ROOT_I}" LEADV2_DISPATCH_CACHE_DIR="${TMP_ROOT}/cache-i" bash "${DISPATCH_BIN}" glm-deferred --list 2>&1)"
if grep -q "retry_failed ${SIG_I} rc=" <<<"${out_i}" && grep -q "${SIG_I}" <<<"${list_after_i}"; then
  pass "(i) a failed retry dispatch leaves the row pending"
else
  fail "(i) expected 'retry_failed ${SIG_I} rc=...' and the row still in --list" \
    "out=${out_i} list=${list_after_i}"
fi

# (f) real retry-all: parked mission dispatches as a NEW task on success.
ROOT_F="${TMP_ROOT}/root-retry-f"
make_tenant_root "${ROOT_F}"
DEFERRED_F="${ROOT_F}/docs/leadv2/glm-deferred.jsonl"
MDIR_F="${ROOT_F}/docs/leadv2/glm-deferred.d"
mkdir -p "${MDIR_F}"
SIG_F="ffffffff"
MPATH_F="${MDIR_F}/${SIG_F}.md"
printf 'plugin-only glm-deferred-ladder retry-all success probe' > "${MPATH_F}"
python3 -c '
import json
row = {"sig8": "'"${SIG_F}"'", "mission_path": "'"${MPATH_F}"'", "founder_task_id": "",
       "refused_at": "2026-08-20T00:00:00Z", "reason": "glm_refused_quota_gate",
       "quota_pct": None, "retried_at": None}
print(json.dumps(row, separators=(",", ":")))
' >> "${DEFERRED_F}"
LEDGER_F="${TMP_ROOT}/ledger-f.sh"
printf '#!/usr/bin/env bash\nexit 1\n' > "${LEDGER_F}"
chmod +x "${LEDGER_F}"
MARKER_F="${TMP_ROOT}/marker-f"
GLM_OK_F="${TMP_ROOT}/glm-ok-f.sh"
cat > "${GLM_OK_F}" <<SH
#!/usr/bin/env bash
: > "${MARKER_F}"
printf 'PID=%s LABEL=test SESSION_ID=test\n' "\$\$"
SH
chmod +x "${GLM_OK_F}"

out_f="$(CLAUDE_PROJECT_ROOT="${ROOT_F}" LEADV2_DISPATCH_CACHE_DIR="${TMP_ROOT}/cache-f" LEADV2_DISPATCH_LEDGER_BIN="${LEDGER_F}" \
  LEADV2_ROUTER_V2_BIN="${RV2_R_GLM}" LEADV2_DISPATCH_GLM_BIN="${GLM_OK_F}" \
  LEADV2_DISPATCH_ARCHITECT_GATE=0 LEADV2_DISPATCH_SPAWN=1 \
  bash "${DISPATCH_BIN}" glm-deferred --retry-all 2>&1)"
list_after_f="$(CLAUDE_PROJECT_ROOT="${ROOT_F}" LEADV2_DISPATCH_CACHE_DIR="${TMP_ROOT}/cache-f" bash "${DISPATCH_BIN}" glm-deferred --list 2>&1)"

if [[ ! -f "${MARKER_F}" ]]; then
  fail "(f) retry-all did not spawn a new dispatch for the parked mission" "out=${out_f}"
elif ! grep -q "retried ${SIG_F} as=" <<<"${out_f}"; then
  fail "(f) expected 'retried ${SIG_F} as=<new-sig8>'" "out=${out_f}"
elif grep -q "${SIG_F}" <<<"${list_after_f}"; then
  fail "(f) old sig8 should no longer appear in --list after a successful retry" "list=${list_after_f}"
else
  pass "(f) real retry-all: new dispatch observed (marker file), 'retried as=', old sig8 reaped from --list"
fi

# ── terminal poison-marker assertion across the whole suite ────────────────
if grep -q 'POISON:' <<<"${out_ab}"; then
  fail "poison fence (final)" "a POISON marker appears in captured output"
else
  pass "poison fence held across the suite"
fi

printf '\n================================================\n'
printf '  glm-deferred-ladder suite: FAIL=%s\n' "${FAIL}"
printf '================================================\n'

exit "${FAIL}"
