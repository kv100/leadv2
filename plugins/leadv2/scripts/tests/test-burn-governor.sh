#!/usr/bin/env bash
# tests/test-burn-governor.sh — BURN-GOVERNOR-01: 24h local token-burn gate.
#
# Covers the governor script standalone (fixture sqlite db, the REAL '-'
# hour_key separator -- not the mission's original 'T' spelling, see
# architect prepass §0.1), the dispatcher's pre-arm gate, and one caller's
# rc=6 handling. Conventions mirror test-dispatch-silent-arm.sh /
# test-glm-deferred-ladder.sh: set -uo pipefail, ambient LEADV2_*/CLAUDE_*
# scrub via unset, sandboxed CLAUDE_PROJECT_ROOT/LEADV2_DISPATCH_CACHE_DIR/
# LEADV2_DISPATCH_ARCHITECT_GATE=0 so no real repo state is ever touched, no
# GNU-only date/sed/timeout.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
source "${SCRIPTS_ROOT}/leadv2-temp.sh"

GOVERNOR_BIN="${SCRIPTS_ROOT}/leadv2-burn-governor.sh"
DISPATCH_BIN="${SCRIPTS_ROOT}/leadv2-dispatch-code.sh"
LANE_LAUNCHER_BIN="${SCRIPTS_ROOT}/leadv2-fanout-lane-launcher.sh"

PASS=0; FAIL=0; ERRORS=()
log()  { printf -- '[TEST] %s\n' "$*"; }
pass() { PASS=$((PASS + 1)); log "PASS: $1"; }
fail() { FAIL=$((FAIL + 1)); ERRORS+=("FAIL: $1"); log "FAIL: $1 -- ${2:-}"; }

unset LEADV2_PROJECT_ROOT LEADV2_LANE_WORK_ROOT LEADV2_TASK_ID \
      LEADV2_PARENT_SESSION_ID LEADV2_DISPATCH_LANE_NAME LEADV2_EXCLUDED_ARMS \
      LEADV2_BURN_GOVERNOR LEADV2_BURN_SOFT_24H LEADV2_BURN_HARD_24H \
      LEADV2_BURN_OVERRIDE LEADV2_CLAUDE_BURN_DIR

tmp="$(lv2_mktemp_dir "burn-governor-test")"; trap 'rm -rf "$tmp"' EXIT

if bash -n "${GOVERNOR_BIN}"; then
  pass "bash -n clean (leadv2-burn-governor.sh)"
else
  fail "bash -n failed on leadv2-burn-governor.sh"
fi
if bash -n "${DISPATCH_BIN}"; then
  pass "bash -n clean (leadv2-dispatch-code.sh)"
else
  fail "bash -n failed on leadv2-dispatch-code.sh"
fi

# ── governor fixture db builder — REAL '-' hour_key separator, rows stamped
# via sqlite3's own strftime('now','-N hours') so no shell date -v/-d split.
make_fixture_db() {  # <db-path>
  local db="$1"
  mkdir -p "$(dirname "${db}")"
  sqlite3 "${db}" "
CREATE TABLE hourly (
  hour_key TEXT PRIMARY KEY,
  hour_of_day INTEGER,
  day_of_week INTEGER,
  cc_sum INTEGER DEFAULT 0,
  cr_sum INTEGER DEFAULT 0,
  input_sum INTEGER DEFAULT 0,
  output_sum INTEGER DEFAULT 0,
  turn_count INTEGER DEFAULT 0
);"
}

insert_hours_ago() {  # <db> <hours-ago> <cc> <cr> <input> <output>
  local db="$1" hago="$2" cc="$3" cr="$4" inp="$5" out="$6"
  sqlite3 "${db}" "INSERT INTO hourly (hour_key,cc_sum,cr_sum,input_sum,output_sum)
    SELECT strftime('%Y-%m-%d-%H','now','-${hago} hours'), ${cc}, ${cr}, ${inp}, ${out};"
}

gv_field() {  # <line> <field>
  printf '%s\n' "$1" | sed -n "s/.*$2=\\([^ ]*\\).*/\\1/p"
}

# 1: bash -n already covered above.

# 2: sum just under soft -> ok
DB2="${tmp}/g2/history.db"; make_fixture_db "${DB2}"
insert_hours_ago "${DB2}" 1 100 0 0 0
line="$(LEADV2_CLAUDE_BURN_DIR="${tmp}/g2" LEADV2_BURN_SOFT_24H=200 LEADV2_BURN_HARD_24H=300 bash "${GOVERNOR_BIN}" verdict)"
[[ "$(gv_field "${line}" verdict)" == "ok" ]] && pass "2: under-soft -> verdict=ok" || fail "2: under-soft" "${line}"

# 3: sum == soft exactly -> soft (boundary is >=)
DB3="${tmp}/g3/history.db"; make_fixture_db "${DB3}"
insert_hours_ago "${DB3}" 1 200 0 0 0
line="$(LEADV2_CLAUDE_BURN_DIR="${tmp}/g3" LEADV2_BURN_SOFT_24H=200 LEADV2_BURN_HARD_24H=300 bash "${GOVERNOR_BIN}" verdict)"
[[ "$(gv_field "${line}" verdict)" == "soft" ]] && pass "3: burn==soft -> verdict=soft" || fail "3: burn==soft" "${line}"

# 4: sum == hard exactly -> hard
DB4="${tmp}/g4/history.db"; make_fixture_db "${DB4}"
insert_hours_ago "${DB4}" 1 300 0 0 0
line="$(LEADV2_CLAUDE_BURN_DIR="${tmp}/g4" LEADV2_BURN_SOFT_24H=200 LEADV2_BURN_HARD_24H=300 bash "${GOVERNOR_BIN}" verdict)"
[[ "$(gv_field "${line}" verdict)" == "hard" ]] && pass "4: burn==hard -> verdict=hard" || fail "4: burn==hard" "${line}"

# 5: sum above hard -> hard
DB5="${tmp}/g5/history.db"; make_fixture_db "${DB5}"
insert_hours_ago "${DB5}" 1 500 0 0 0
line="$(LEADV2_CLAUDE_BURN_DIR="${tmp}/g5" LEADV2_BURN_SOFT_24H=200 LEADV2_BURN_HARD_24H=300 bash "${GOVERNOR_BIN}" verdict)"
[[ "$(gv_field "${line}" verdict)" == "hard" ]] && pass "5: burn>hard -> verdict=hard" || fail "5: burn>hard" "${line}"

# 6: -25h row excluded, -23h row included (the case that fails against 'T' format)
DB6="${tmp}/g6/history.db"; make_fixture_db "${DB6}"
insert_hours_ago "${DB6}" 25 1000000 0 0 0
insert_hours_ago "${DB6}" 23 5 0 0 0
line="$(LEADV2_CLAUDE_BURN_DIR="${tmp}/g6" LEADV2_BURN_SOFT_24H=200 LEADV2_BURN_HARD_24H=300 bash "${GOVERNOR_BIN}" verdict)"
if [[ "$(gv_field "${line}" burn24h)" == "5" ]]; then
  pass "6: -25h row excluded, -23h row included (D1 hour_key format)"
else
  fail "6: 24h window boundary" "${line}"
fi

# 7: governor disabled -> ok reason=disabled even over-hard db
line="$(LEADV2_CLAUDE_BURN_DIR="${tmp}/g5" LEADV2_BURN_SOFT_24H=200 LEADV2_BURN_HARD_24H=300 LEADV2_BURN_GOVERNOR=0 bash "${GOVERNOR_BIN}" verdict)"
if [[ "$(gv_field "${line}" verdict)" == "ok" && "$(gv_field "${line}" reason)" == "disabled" ]]; then
  pass "7: LEADV2_BURN_GOVERNOR=0 -> ok/disabled"
else
  fail "7: governor disabled" "${line}"
fi

# 8: no db file -> no_telemetry
line="$(LEADV2_CLAUDE_BURN_DIR="${tmp}/no-such-dir" bash "${GOVERNOR_BIN}" verdict)"
[[ "$(gv_field "${line}" reason)" == "no_telemetry" ]] && pass "8: missing db -> no_telemetry" || fail "8: missing db" "${line}"

# 9: hourly table dropped -> no_telemetry
DB9="${tmp}/g9/history.db"
mkdir -p "${tmp}/g9"; sqlite3 "${DB9}" "CREATE TABLE other (x INTEGER);"
line="$(LEADV2_CLAUDE_BURN_DIR="${tmp}/g9" bash "${GOVERNOR_BIN}" verdict)"
[[ "$(gv_field "${line}" reason)" == "no_telemetry" ]] && pass "9: hourly table missing -> no_telemetry" || fail "9: hourly missing" "${line}"

# 10: sqlite3 absent from PATH -> no_telemetry, exit 0
STUBPATH="${tmp}/no-sqlite-path"; mkdir -p "${STUBPATH}"
for _b in bash sh sed grep cat mkdir printf date python3 basename dirname; do
  _real="$(command -v "${_b}" 2>/dev/null || true)"
  [[ -n "${_real}" ]] && ln -sf "${_real}" "${STUBPATH}/${_b}"
done
line="$(PATH="${STUBPATH}" LEADV2_CLAUDE_BURN_DIR="${tmp}/g2" bash "${GOVERNOR_BIN}" verdict)"; rc=$?
if [[ "$(gv_field "${line}" reason)" == no_telemetry* && "${rc}" == "0" ]]; then
  pass "10: sqlite3 absent from PATH -> no_telemetry, exit 0"
else
  fail "10: sqlite3 absent" "line=${line} rc=${rc}"
fi

# 11: hard<=soft (misconfigured) -> defaults used, reason contains bad_config
line="$(LEADV2_CLAUDE_BURN_DIR="${tmp}/g2" LEADV2_BURN_HARD_24H=1 LEADV2_BURN_SOFT_24H=100 bash "${GOVERNOR_BIN}" verdict)"
if [[ "$(gv_field "${line}" soft)" == "800000000" && "$(gv_field "${line}" hard)" == "1300000000" \
      && "$(gv_field "${line}" reason)" == *bad_config* ]]; then
  pass "11: hard<=soft -> defaults + bad_config"
else
  fail "11: hard<=soft misconfig" "${line}"
fi

# 12: non-numeric threshold -> defaults + bad_config
line="$(LEADV2_CLAUDE_BURN_DIR="${tmp}/g2" LEADV2_BURN_SOFT_24H=abc bash "${GOVERNOR_BIN}" verdict)"
if [[ "$(gv_field "${line}" soft)" == "800000000" && "$(gv_field "${line}" reason)" == *bad_config* ]]; then
  pass "12: non-numeric threshold -> defaults + bad_config"
else
  fail "12: non-numeric threshold" "${line}"
fi

# 13: NULL in one column of one row still contributes its other columns (D7)
DB13="${tmp}/g13/history.db"; make_fixture_db "${DB13}"
sqlite3 "${DB13}" "INSERT INTO hourly (hour_key,cc_sum,cr_sum,input_sum,output_sum)
  SELECT strftime('%Y-%m-%d-%H','now','-1 hours'), NULL, 100, 200, 300;"
line="$(LEADV2_CLAUDE_BURN_DIR="${tmp}/g13" LEADV2_BURN_SOFT_24H=200 LEADV2_BURN_HARD_24H=300 bash "${GOVERNOR_BIN}" verdict)"
[[ "$(gv_field "${line}" burn24h)" == "600" ]] && pass "13: NULL column doesn't zero the row (D7)" || fail "13: NULL column" "${line}"

# D6: a valid 21-digit hard threshold (hard > soft, both numeric — a legitimate
# operator config, not a misconfiguration) must classify correctly and never crash
# or silently wrap into a refusal via bash `(( ))` overflow.
DBoverflow="${tmp}/goverflow/history.db"; make_fixture_db "${DBoverflow}"
insert_hours_ago "${DBoverflow}" 1 100 0 0 0
line="$(LEADV2_CLAUDE_BURN_DIR="${tmp}/goverflow" LEADV2_BURN_HARD_24H=999999999999999999999 LEADV2_BURN_SOFT_24H=1 bash "${GOVERNOR_BIN}" verdict)"; rc=$?
if [[ "${rc}" == "0" && "$(gv_field "${line}" verdict)" == "soft" && "$(gv_field "${line}" reason)" != *bad_config* ]]; then
  pass "D6: 21-digit hard threshold classifies correctly, no crash/overflow"
else
  fail "D6: overflow guard" "rc=${rc} ${line}"
fi
# D6 companion: a genuinely misconfigured 21-digit pair (hard<=soft) still resolves
# to defaults + bad_config, not a bash-arithmetic-overflow crash or hang.
line="$(LEADV2_CLAUDE_BURN_DIR="${tmp}/goverflow" LEADV2_BURN_HARD_24H=1 LEADV2_BURN_SOFT_24H=999999999999999999999 bash "${GOVERNOR_BIN}" verdict)"; rc=$?
if [[ "${rc}" == "0" && "$(gv_field "${line}" reason)" == *bad_config* ]]; then
  pass "D6: 21-digit misconfigured pair -> defaults + bad_config, no crash"
else
  fail "D6: overflow guard misconfigured" "rc=${rc} ${line}"
fi

# ============================================================================
# Dispatcher gate — sandboxed tenant root, LEADV2_DISPATCH_ARCHITECT_GATE=0,
# LEADV2_DISPATCH_SPAWN=0, poison fence for codex/kimi so a bug in the gate
# can never reach a real provider spawn.
# ============================================================================
make_stub_governor() {  # <path> <verdict-line>
  local path="$1" line="$2"
  printf '#!/usr/bin/env bash\nprintf %s\n' "'${line}\n'" > "${path}"
  chmod +x "${path}"
}

for _arm in kimi codex glm sonnet; do
  _poison="${tmp}/poison-${_arm}.sh"
  printf '#!/usr/bin/env bash\nprintf "POISON: real provider spawn attempted\\n" >&2\nexit 99\n' > "${_poison}"
  chmod +x "${_poison}"
done

dispatch_env() {  # <root> <cache> <governor-bin>
  echo CLAUDE_PROJECT_ROOT="$1" LEADV2_DISPATCH_CACHE_DIR="$2" LEADV2_DISPATCH_ARCHITECT_GATE=0 \
    LEADV2_DISPATCH_SPAWN=0 LEADV2_BURN_GOVERNOR_BIN="$3" \
    LEADV2_DISPATCH_KIMI_BIN="${tmp}/poison-kimi.sh" LEADV2_DISPATCH_CODEX_BIN="${tmp}/poison-codex.sh" \
    LEADV2_DISPATCH_GLM_BIN="${tmp}/poison-glm.sh" LEADV2_DISPATCH_SUBSESSION_BIN="${tmp}/poison-sonnet.sh"
}

# 14: stub says hard -> exit 6, stderr BURN GATE, burn-deferred.jsonl gains one row
ROOT14="${tmp}/root14"; mkdir -p "${ROOT14}"
GOV14="${tmp}/gov14.sh"; make_stub_governor "${GOV14}" "verdict=hard burn24h=2000000000 soft=800000000 hard=1300000000 reason=over_hard"
out14="$(CLAUDE_PROJECT_ROOT="${ROOT14}" LEADV2_DISPATCH_CACHE_DIR="${tmp}/cache14" LEADV2_DISPATCH_ARCHITECT_GATE=0 \
  LEADV2_DISPATCH_SPAWN=0 LEADV2_BURN_GOVERNOR_BIN="${GOV14}" \
  LEADV2_DISPATCH_KIMI_BIN="${tmp}/poison-kimi.sh" LEADV2_DISPATCH_CODEX_BIN="${tmp}/poison-codex.sh" \
  bash "${DISPATCH_BIN}" 'plugin-only burn governor test 14' --no-spawn 2>&1)"; rc14=$?
DEFERRED14="${ROOT14}/docs/leadv2/burn-deferred.jsonl"
sig14="$(printf '%s\n' "${out14}" | grep -oE 'task=[0-9a-f]{8}' | head -1 | cut -d= -f2)"
if [[ "${rc14}" == "6" ]] && grep -q 'BURN GATE' <<<"${out14}" && [[ -f "${DEFERRED14}" ]] \
    && grep -q "\"sig8\":\"${sig14}\"" "${DEFERRED14}" && grep -q '"reason":"burn_hard_24h"' "${DEFERRED14}"; then
  pass "14: hard -> exit 6, BURN GATE stderr, burn-deferred row written"
else
  fail "14: hard refusal" "rc=${rc14} out=${out14} deferred=$(cat "${DEFERRED14}" 2>/dev/null)"
fi

# 15: --force does not bypass a hard verdict
out15="$(CLAUDE_PROJECT_ROOT="${ROOT14}" LEADV2_DISPATCH_CACHE_DIR="${tmp}/cache15" LEADV2_DISPATCH_ARCHITECT_GATE=0 \
  LEADV2_DISPATCH_SPAWN=0 LEADV2_BURN_GOVERNOR_BIN="${GOV14}" \
  LEADV2_DISPATCH_KIMI_BIN="${tmp}/poison-kimi.sh" LEADV2_DISPATCH_CODEX_BIN="${tmp}/poison-codex.sh" \
  bash "${DISPATCH_BIN}" 'plugin-only burn governor test 15' --no-spawn --force 2>&1)"; rc15=$?
[[ "${rc15}" == "6" ]] && pass "15: --force does not bypass hard verdict" || fail "15: --force bypass" "rc=${rc15} out=${out15}"

# 16: LEADV2_BURN_OVERRIDE=1 bypasses; no burn-deferred row for this task
ROOT16="${tmp}/root16"; mkdir -p "${ROOT16}"
out16="$(CLAUDE_PROJECT_ROOT="${ROOT16}" LEADV2_DISPATCH_CACHE_DIR="${tmp}/cache16" LEADV2_DISPATCH_ARCHITECT_GATE=0 \
  LEADV2_DISPATCH_SPAWN=0 LEADV2_BURN_GOVERNOR_BIN="${GOV14}" LEADV2_BURN_OVERRIDE=1 \
  LEADV2_DISPATCH_KIMI_BIN="${tmp}/poison-kimi.sh" LEADV2_DISPATCH_CODEX_BIN="${tmp}/poison-codex.sh" \
  bash "${DISPATCH_BIN}" 'plugin-only burn governor test 16' --no-spawn 2>&1)"; rc16=$?
DEFERRED16="${ROOT16}/docs/leadv2/burn-deferred.jsonl"
if [[ "${rc16}" == "0" ]] && grep -q 'OVERRIDDEN' <<<"${out16}" && [[ ! -f "${DEFERRED16}" ]]; then
  pass "16: LEADV2_BURN_OVERRIDE=1 bypasses hard verdict, no park row"
else
  fail "16: override" "rc=${rc16} out=${out16}"
fi

# 17: stub says soft -> exit 0, stderr BURN GATE warning, resolve proceeds
ROOT17="${tmp}/root17"; mkdir -p "${ROOT17}"
GOV17="${tmp}/gov17.sh"; make_stub_governor "${GOV17}" "verdict=soft burn24h=900000000 soft=800000000 hard=1300000000 reason=over_soft"
out17="$(CLAUDE_PROJECT_ROOT="${ROOT17}" LEADV2_DISPATCH_CACHE_DIR="${tmp}/cache17" LEADV2_DISPATCH_ARCHITECT_GATE=0 \
  LEADV2_DISPATCH_SPAWN=0 LEADV2_BURN_GOVERNOR_BIN="${GOV17}" \
  LEADV2_DISPATCH_KIMI_BIN="${tmp}/poison-kimi.sh" LEADV2_DISPATCH_CODEX_BIN="${tmp}/poison-codex.sh" \
  bash "${DISPATCH_BIN}" 'plugin-only burn governor test 17' --no-spawn 2>&1)"; rc17=$?
if [[ "${rc17}" == "0" ]] && grep -q 'BURN GATE' <<<"${out17}"; then
  pass "17: soft -> exit 0, advisory BURN GATE line, resolve proceeds"
else
  fail "17: soft path" "rc=${rc17} out=${out17}"
fi

# 18: stub says ok -> zero burn_gate journal lines (no journal noise)
ROOT18="${tmp}/root18"; mkdir -p "${ROOT18}"
GOV18="${tmp}/gov18.sh"; make_stub_governor "${GOV18}" "verdict=ok burn24h=100 soft=800000000 hard=1300000000 reason=under_soft"
out18="$(CLAUDE_PROJECT_ROOT="${ROOT18}" LEADV2_DISPATCH_CACHE_DIR="${tmp}/cache18" LEADV2_DISPATCH_ARCHITECT_GATE=0 \
  LEADV2_DISPATCH_SPAWN=0 LEADV2_BURN_GOVERNOR_BIN="${GOV18}" \
  LEADV2_DISPATCH_KIMI_BIN="${tmp}/poison-kimi.sh" LEADV2_DISPATCH_CODEX_BIN="${tmp}/poison-codex.sh" \
  bash "${DISPATCH_BIN}" 'plugin-only burn governor test 18' --no-spawn 2>&1)"; rc18=$?
sig18="$(printf '%s\n' "${out18}" | grep -oE 'task=[0-9a-f]{8}' | head -1 | cut -d= -f2)"
journal18="${ROOT18}/docs/handoff/dispatch-${sig18}"
if [[ "${rc18}" == "0" ]] && ! grep -q 'burn_gate' <<<"${out18}" \
    && { [[ ! -d "${journal18}" ]] || ! grep -rq 'burn_gate' "${journal18}" 2>/dev/null; }; then
  pass "18: ok verdict -> zero burn_gate journal noise"
else
  fail "18: ok verdict noise" "rc=${rc18} out=${out18}"
fi

# 19: hard refusal leaves no worktree and no ledger row (placement guarantee, §1.2)
if [[ ! -d "${ROOT14}/.claude/worktrees" ]] || [[ -z "$(ls -A "${ROOT14}/.claude/worktrees" 2>/dev/null)" ]]; then
  pass "19: hard refusal created no worktree"
else
  fail "19: hard refusal worktree leak" "$(ls -A "${ROOT14}/.claude/worktrees" 2>/dev/null)"
fi
if ! LEADV2_DISPATCH_CACHE_DIR="${tmp}/cache14" \
    bash "${SCRIPTS_ROOT}/leadv2-dispatch-ledger.sh" exists "${sig14:-nonexistent}" >/dev/null 2>&1; then
  pass "19: hard refusal left no ledger row"
else
  fail "19: hard refusal ledger row leak" "sig=${sig14}"
fi

# ============================================================================
# 20: caller A (leadv2-fanout-lane-launcher.sh) treats rc=6 as parked, not dead
# ============================================================================
if bash -n "${LANE_LAUNCHER_BIN}"; then
  pass "20: bash -n clean (leadv2-fanout-lane-launcher.sh)"
else
  fail "20: bash -n failed on leadv2-fanout-lane-launcher.sh"
fi
if grep -q '6)' "${LANE_LAUNCHER_BIN}" && grep -q 'burn_hard_24h' "${LANE_LAUNCHER_BIN}"; then
  pass "20: leadv2-fanout-lane-launcher.sh has an explicit 6) arm for burn_hard_24h"
else
  fail "20: leadv2-fanout-lane-launcher.sh missing rc=6 handling"
fi

# ============================================================================
# 21-26: QUOTA-GATE-PARITY-01 -- `--provider <glm|codex|claude>` mode. The
# default (no-flag) cases above are the backward-compat oracle and are left
# untouched; --provider is additive and never reads LEADV2_BURN_SOFT_24H/
# LEADV2_BURN_HARD_24H (asserted at 26).
# ============================================================================
CEILINGS_BIN="${SCRIPTS_ROOT}/../config/leadv2-quota-ceilings.sh"
FAKE_LIVE_PROV="${tmp}/fake-live-provider.sh"
cat > "${FAKE_LIVE_PROV}" <<'EOF'
#!/usr/bin/env bash
case "${1:-}" in
  glm) printf '{"status":"ok","five_hour":{"pct":'"${FAKE_GLM_PCT:-10}"'},"weekly":{"pct":5}}' ;;
  codex) printf '{"status":"ok","binding_window":"weekly","windows":[{"kind":"weekly","used_percent":'"${FAKE_CODEX_PCT:-10}"'}]}' ;;
  anthropic) printf '{"status":"ok","accounts":[{"active":true,"seven_day_pct":'"${FAKE_CLAUDE_PCT:-10}"',"five_hour_pct":5}]}' ;;
  *) printf '{"status":"unknown"}' ;;
esac
EOF
chmod +x "${FAKE_LIVE_PROV}"

# 21: glm under soft -> verdict=ok, ceiling-derived soft/hard (80 -> soft=70 hard=80)
out21="$(FAKE_GLM_PCT=10 LEADV2_QUOTA_LIVE="${FAKE_LIVE_PROV}" bash "${GOVERNOR_BIN}" --provider glm 2>&1)"
if grep -q '^verdict=ok ' <<<"${out21}" && grep -q 'soft=70' <<<"${out21}" && grep -q 'hard=80' <<<"${out21}" && grep -q 'unit=pct' <<<"${out21}"; then
  pass "21: --provider glm under soft -> ok, soft/hard from ceiling"
else
  fail "21: --provider glm under soft" "${out21}"
fi

# 22: codex over hard (ceiling 90) -> verdict=hard reason=over_hard
out22="$(FAKE_CODEX_PCT=95 LEADV2_QUOTA_LIVE="${FAKE_LIVE_PROV}" bash "${GOVERNOR_BIN}" --provider codex 2>&1)"
if grep -q '^verdict=hard ' <<<"${out22}" && grep -q 'reason=over_hard' <<<"${out22}" && grep -q 'hard=90' <<<"${out22}"; then
  pass "22: --provider codex over hard -> verdict=hard"
else
  fail "22: --provider codex over hard" "${out22}"
fi

# 23: claude over soft, under hard (ceiling 95, soft 85) -> verdict=soft
out23="$(FAKE_CLAUDE_PCT=90 LEADV2_QUOTA_LIVE="${FAKE_LIVE_PROV}" bash "${GOVERNOR_BIN}" --provider claude 2>&1)"
if grep -q '^verdict=soft ' <<<"${out23}" && grep -q 'reason=over_soft' <<<"${out23}"; then
  pass "23: --provider claude over soft, under hard -> verdict=soft"
else
  fail "23: --provider claude over soft" "${out23}"
fi

# 24: unknown provider -> verdict=ok reason=bad_provider (fail-open, never a crash)
out24="$(bash "${GOVERNOR_BIN}" --provider bogus 2>&1)"
if grep -q 'reason=bad_provider' <<<"${out24}" && grep -q '^verdict=ok ' <<<"${out24}"; then
  pass "24: --provider bogus -> fail-open bad_provider"
else
  fail "24: --provider bogus" "${out24}"
fi

# 25: quota-live telemetry unavailable -> verdict=ok reason=no_telemetry (fail-open)
out25="$(LEADV2_QUOTA_LIVE="${tmp}/does-not-exist.sh" bash "${GOVERNOR_BIN}" --provider glm 2>&1)"
if grep -q 'reason=no_telemetry' <<<"${out25}" && grep -q '^verdict=ok ' <<<"${out25}"; then
  pass "25: --provider glm with no telemetry -> fail-open no_telemetry"
else
  fail "25: --provider glm no telemetry" "${out25}"
fi

# 26: --provider ignores LEADV2_BURN_SOFT_24H/HARD_24H (ceiling-derived only)
out26="$(FAKE_GLM_PCT=10 LEADV2_QUOTA_LIVE="${FAKE_LIVE_PROV}" LEADV2_BURN_SOFT_24H=1 LEADV2_BURN_HARD_24H=2 \
  bash "${GOVERNOR_BIN}" --provider glm 2>&1)"
if grep -q 'soft=70' <<<"${out26}" && grep -q 'hard=80' <<<"${out26}"; then
  pass "26: --provider ignores LEADV2_BURN_SOFT_24H/HARD_24H env"
else
  fail "26: --provider env-ignore" "${out26}"
fi

# default (no-flag) path is untouched by --provider's addition
out_default="$(bash "${GOVERNOR_BIN}" 2>&1)"
if grep -q '^verdict=' <<<"${out_default}"; then
  pass "backward-compat: default (no-flag) invocation still emits a verdict line"
else
  fail "backward-compat default invocation" "${out_default}"
fi

echo
echo "=== ${PASS} passed, ${FAIL} failed ==="
if [[ ${FAIL} -gt 0 ]]; then
  printf '%s\n' "${ERRORS[@]}"
  exit 1
fi
exit 0
