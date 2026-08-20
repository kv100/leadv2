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

run_c() {  # <mission-text> <cache-suffix>
  # Each call gets its own LEADV2_DISPATCH_CACHE_DIR: the quota-lockout memory
  # written by run N (primary_arm_benched) would otherwise exclude glm from
  # candidate_arms on run N+1, skipping the refusal branch entirely and
  # making this leg fail for the wrong reason (glm never even attempted,
  # not "attempted and deduped"). The credit-watchdog stamp under test lives
  # under ROOT_C/docs/leadv2/, NOT the cache dir, so it is unaffected.
  CLAUDE_PROJECT_ROOT="${ROOT_C}" \
    LEADV2_DISPATCH_CACHE_DIR="${TMP_ROOT}/c-cache-$2" \
    LEADV2_DISPATCH_ARCHITECT_GATE=0 \
    LEADV2_ROUTER_V2_BIN="${RV2_C}" \
    LEADV2_DISPATCH_GLM_BIN="${GLM_BIN_C}" \
    LEADV2_DISPATCH_SUBSESSION_BIN="${SONNET_C}" \
    LEADV2_DISPATCH_SPAWN=1 \
    LEADV2_JOURNAL_BIN="${JOURNAL_C_BIN}" \
    JOURNAL_TASK="glm-deferred-ladder-c" \
    bash "${DISPATCH_BIN}" "$1" >/dev/null 2>&1 || true
}

run_c 'plugin-only glm-deferred-ladder credit watchdog probe 1' 1
run_c 'plugin-only glm-deferred-ladder credit watchdog probe 2' 2
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

run_c 'plugin-only glm-deferred-ladder credit watchdog probe 3' 3
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
LEADV2_PROJECT_ROOT="${ROOT}" LEADV2_STATE_ROOT="${TMP_ROOT}/state-d" \
  LEADV2_STATUS_COLLECTOR_BIN="${STUBS_D}/collector.sh" \
  LEADV2_BROAD_STATUS_CLAUDE_BIN="${STUBS_D}/claude.sh" \
  LEADV2_BROAD_STATUS_BEAT_AT="2026-08-20T00:00:00Z" \
  LEADV2_BROAD_STATUS_DISPATCHED="1" \
  bash "${BROAD_STATUS_SH}" >/dev/null 2>&1 || true

if [[ ! -f "${FOUNDER_STATUS_D}" ]]; then
  fail "(d) founder-status.md not written" "renderer produced no artifact"
elif grep -q 'sonnet-фолбэков сегодня: 1 (glm quota)' "${FOUNDER_STATUS_D}"; then
  pass "(d) rendered founder-status.md contains sonnet-фолбэков сегодня: 1 (glm quota)"
else
  fail "(d) expected sonnet-fallback line missing from rendered artifact" \
    "content=$(cat "${FOUNDER_STATUS_D}")"
fi

# ── negative: a day with no fallback renders no such line ──────────────────
ROOT_NEG="${TMP_ROOT}/root-neg"
make_tenant_root "${ROOT_NEG}"
FOUNDER_STATUS_NEG="${ROOT_NEG}/docs/leadv2/founder-status.md"
LEADV2_PROJECT_ROOT="${ROOT_NEG}" LEADV2_STATE_ROOT="${TMP_ROOT}/state-neg" \
  LEADV2_STATUS_COLLECTOR_BIN="${STUBS_D}/collector.sh" \
  LEADV2_BROAD_STATUS_CLAUDE_BIN="${STUBS_D}/claude.sh" \
  LEADV2_BROAD_STATUS_BEAT_AT="2026-08-20T00:00:00Z" \
  LEADV2_BROAD_STATUS_DISPATCHED="1" \
  bash "${BROAD_STATUS_SH}" >/dev/null 2>&1 || true

if [[ -f "${FOUNDER_STATUS_NEG}" ]] && ! grep -q 'сонн\|sonnet-фолбэков' "${FOUNDER_STATUS_NEG}"; then
  pass "(d) a day with no fallback renders no sonnet-fallback line"
else
  fail "(d) unexpected sonnet-fallback line with zero fallbacks" \
    "content=$(cat "${FOUNDER_STATUS_NEG}" 2>/dev/null || echo '<missing>')"
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
