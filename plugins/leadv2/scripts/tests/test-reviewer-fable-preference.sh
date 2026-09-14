#!/usr/bin/env bash
# tests/test-reviewer-fable-preference.sh
# REVIEWER-CHOICE-MUST-EXPLAIN-ITSELF-AND-FABLE-IS-NOT-THE-DEFAULT-01
# (founder ruling, 2026-09-14): fable must not be the default reviewer for
# ordinary work; it is legitimate for genuinely hard/important work, or when
# reviewing a strong-arm author (opus/sol/astra). This proves the T17 block
# in resolve_review_pool_call() (leadv2-dispatch-product-close.sh) applies
# that preference, that a hard/important task still gets fable, and that the
# rollback flag LEADV2_REVIEWER_PREFER_NON_FABLE=0 reproduces the pre-fix
# (always-cheapest, fable included) pick as a real negative control.
#
# Isolation strategy: resolve_review_pool_call() and _pc_review_entry_eligible()
# are extracted verbatim (brace-matched, not line-numbered, so this survives
# unrelated edits above/below them) from the real script and sourced into this
# test's own shell. Only route_arbiter, emit, and JOURNAL_BIN are stubbed; the
# real leadv2-glm-policy-resolve.py resolver runs for real against a stub
# --quota-live, exactly as tests/test-review-arm-pool.sh does, so the pool=
# entries the T17 walk checks eligibility against are genuine resolver output,
# not hand-authored fixtures.
#
# run-all-triggers: leadv2-dispatch-product-close leadv2-route-arbiter

set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_ROOT="${HERE}/.."
PRODUCT_CLOSE="${SCRIPTS_ROOT}/leadv2-dispatch-product-close.sh"
RESOLVER="${SCRIPTS_ROOT}/lib/leadv2-glm-policy-resolve.py"
TMPDIR_BASE="$(mktemp -d)"
trap 'rm -rf "${TMPDIR_BASE}"' EXIT

PASS=0
FAIL=0
pass() { printf 'PASS: %s\n' "$1"; PASS=$(( PASS + 1 )); }
fail() { printf 'FAIL: %s (%s)\n' "$1" "$2"; FAIL=$(( FAIL + 1 )); }

# ---- extract the two functions under test, brace-matched -------------------
FRAGMENT="${TMPDIR_BASE}/fragment.sh"
awk '
  /^_pc_review_entry_eligible\(\) \{/ { grab=1 }
  grab { print; if ($0 == "}") { n++; if (n == 2) exit } }
' "${PRODUCT_CLOSE}" > "${FRAGMENT}"
if [[ ! -s "${FRAGMENT}" ]]; then
  echo "FATAL: could not extract resolve_review_pool_call()/_pc_review_entry_eligible() from ${PRODUCT_CLOSE} — brace-match failed, refusing to run against a stale fixture" >&2
  exit 2
fi
# shellcheck source=/dev/null
source "${FRAGMENT}"

# ---- stubs shared by every case ---------------------------------------------
JOURNAL_BIN="${TMPDIR_BASE}/journal-stub.sh"
cat > "${JOURNAL_BIN}" <<'STUB'
#!/usr/bin/env bash
[[ -n "${TASK_CLASS_STUB:-}" ]] && printf 'task_class=%s\n' "${TASK_CLASS_STUB}"
STUB
chmod +x "${JOURNAL_BIN}"

_arb_fault_detail() { printf 'reason=stub_fault'; }

DECISION_LOG="${TMPDIR_BASE}/decisions.log"
emit() { # <kind> <message...>
  shift
  printf '%s\n' "$*" >> "${DECISION_LOG}"
}

QUOTA_STUB="${TMPDIR_BASE}/quota-live-stub.sh"
cat > "${QUOTA_STUB}" <<'STUB'
#!/usr/bin/env bash
bucket="$1"
case "$bucket" in
  codex)
    if [[ "${CODEX_PCT:-unknown}" == "unknown" ]]; then
      echo '{"status":"error"}'
    else
      printf '{"status":"ok","windows":[{"kind":"primary","used_percent":%s}],"binding_window":"primary"}\n' "${CODEX_PCT}"
    fi
    ;;
  glm)
    if [[ "${GLM_FIVE_PCT:-unknown}" == "unknown" && "${GLM_WEEK_PCT:-unknown}" == "unknown" ]]; then
      echo '{"status":"error"}'
    else
      printf '{"status":"ok","five_hour":{"pct":%s},"weekly":{"pct":%s}}\n' \
        "${GLM_FIVE_PCT:-0}" "${GLM_WEEK_PCT:-0}"
    fi
    ;;
  anthropic)
    if [[ "${ANTHRO_PCT:-unknown}" == "unknown" ]]; then
      echo '{"status":"error"}'
    else
      printf '{"status":"ok","active_account":"acct1","accounts":[{"account_label":"acct1","active":true,"five_hour_pct":%s,"seven_day_pct":%s}]}\n' \
        "${ANTHRO_PCT}" "${ANTHRO_PCT}"
    fi
    ;;
  *) echo '{"status":"error"}' ;;
esac
STUB
chmod +x "${QUOTA_STUB}"

ROUTING_YAML="${TMPDIR_BASE}/routing.yaml"
cat > "${ROUTING_YAML}" <<'YAML'
router:
  glm_policy:
    codex_quota_gate:
      build_threshold_pct: 80
      review_threshold_pct: 95
      build_spill_order: [glm, codex, sonnet]
      review_arm_exclusions: [glm]
      review_arm_order: [codex, glm, fable, opus, sonnet]
      glm_review_threshold_pct: 90
      anthropic_review_threshold_pct: 95
YAML

WRITES_CSV="${TMPDIR_BASE}/writes.csv"
: > "${WRITES_CSV}"
HANDOFF="${TMPDIR_BASE}/handoff"
mkdir -p "${HANDOFF}"
SCRIPT_DIR="${SCRIPTS_ROOT}"
ROOT="${TMPDIR_BASE}/root"
mkdir -p "${ROOT}"
LEADV2_ROUTING_YAML=""
GLM_POLICY_QUOTA_LIVE="${QUOTA_STUB}"
LEADV2_GLM_POLICY_RESOLVER="${RESOLVER}"

# Cost-cheapest-is-fable chain: without the preference, fable wins outright
# in every scenario below (all three candidates are otherwise available).
route_arbiter() { # <role> <desc-json>
  printf 'by=arbiter role=%s arm=fable kind=review reason=cheapest_capable chain=fable,codex,glm util_glm=50.0 util_codex=20.0 util_claude=10.0\n' "$1"
}

field() { # <output> <field>
  printf '%s\n' "$1" | sed -n "s/^$2=//p" | head -n1
}
decision_line() { # <field=value substring>
  grep -F -- "$1" "${DECISION_LOG}" | tail -n1
}

run_case() { # <author> <task_class-or-empty> <prefer_non_fable>
  local _author="$1" _task_class="$2" _prefer="$3"
  : > "${DECISION_LOG}"
  TASK="case-${_author}-${_task_class:-none}-${_prefer}"
  AUTHOR="${_author}"
  export TASK_CLASS_STUB="${_task_class}"
  LEADV2_REVIEWER_PREFER_NON_FABLE="${_prefer}"
  resolve_review_pool_call
}

# All three review-pool candidates (codex/glm/fable-via-anthropic) available,
# none blocked — isolates the preference logic, not quota exclusion.
export CODEX_PCT=50 GLM_FIVE_PCT=50 GLM_WEEK_PCT=50 ANTHRO_PCT=50

# ---- (1) author=sonnet, ordinary task -> non-fable reviewer ----------------
out1="$(run_case sonnet "" 1)"
reviewer1="$(field "${out1}" reviewer)"
line1="$(decision_line 'route_resolved by=arbiter role=reviewer')"
if [[ "${reviewer1}" != "fable" && -n "${reviewer1}" ]]; then
  pass "(1) author=sonnet, ordinary task -> non-fable reviewer (got reviewer=${reviewer1})"
else
  fail "(1) author=sonnet, ordinary task -> non-fable reviewer" "got reviewer='${reviewer1}' decision='${line1}'"
fi
if [[ "${line1}" == *"reason=cheapest_capable_non_fable_preferred"* && "${line1}" == *"reviewer_fable_gate=deferred_pass1:fable"* ]]; then
  pass "(1) decision line names the deferral: reason=cheapest_capable_non_fable_preferred, reviewer_fable_gate=deferred_pass1:fable"
else
  fail "(1) decision line names the deferral" "got: ${line1}"
fi

# ---- (2) author=opus (strong arm) -> fable IS picked, and says why ---------
out2="$(run_case opus "" 1)"
reviewer2="$(field "${out2}" reviewer)"
line2="$(decision_line 'route_resolved by=arbiter role=reviewer')"
if [[ "${reviewer2}" == "fable" ]]; then
  pass "(2) author=opus (strong-arm author) -> fable picked"
else
  fail "(2) author=opus (strong-arm author) -> fable picked" "got reviewer='${reviewer2}' decision='${line2}'"
fi
if [[ "${line2}" == *"reason=cheapest_capable_hard_important"* && "${line2}" == *"reviewer_hard_signal=author_strong_arm:opus"* ]]; then
  pass "(2) decision line names why: reason=cheapest_capable_hard_important, reviewer_hard_signal=author_strong_arm:opus"
else
  fail "(2) decision line names why" "got: ${line2}"
fi

# ---- (2b) author=sonnet but task_class=Heavy -> fable picked via the OTHER
# hard/important signal (task class, not author identity) ------------------
out2b="$(run_case sonnet Heavy 1)"
reviewer2b="$(field "${out2b}" reviewer)"
line2b="$(decision_line 'route_resolved by=arbiter role=reviewer')"
if [[ "${reviewer2b}" == "fable" && "${line2b}" == *"reviewer_hard_signal=task_class:Heavy"* ]]; then
  pass "(2b) author=sonnet, task_class=Heavy -> fable picked, reviewer_hard_signal=task_class:Heavy"
else
  fail "(2b) author=sonnet, task_class=Heavy -> fable picked" "got reviewer='${reviewer2b}' decision='${line2b}'"
fi

# ---- (3) NEGATIVE CONTROL: same as (1), but with the rollback flag off ----
# Must reproduce the pre-fix pick: fable wins on raw cost, no preference
# applied, and the decision line names the flag as the reason (not a false
# "hard_important" label — the exact audit gap this suite was written to
# catch: see leadv2-dispatch-product-close.sh's reason= taxonomy comment).
out3="$(run_case sonnet "" 0)"
reviewer3="$(field "${out3}" reviewer)"
line3="$(decision_line 'route_resolved by=arbiter role=reviewer')"
if [[ "${reviewer3}" == "fable" ]]; then
  pass "(3) NEGATIVE CONTROL: LEADV2_REVIEWER_PREFER_NON_FABLE=0, author=sonnet -> fable picked (pre-fix behavior reproduced)"
else
  fail "(3) NEGATIVE CONTROL: LEADV2_REVIEWER_PREFER_NON_FABLE=0, author=sonnet -> fable picked" "got reviewer='${reviewer3}' decision='${line3}'"
fi
if [[ "${line3}" == *"reason=cheapest_capable_policy_disabled"* && "${line3}" == *"reviewer_prefer_non_fable=0"* && "${line3}" == *"reviewer_hard_important=0"* ]]; then
  pass "(3) decision line does not mislabel the flag-disabled pick as hard_important: reason=cheapest_capable_policy_disabled"
else
  fail "(3) decision line does not mislabel the flag-disabled pick as hard_important" "got: ${line3}"
fi

echo "----"
echo "pass=${PASS} fail=${FAIL}"
if [[ "${FAIL}" -eq 0 ]]; then
  echo "SUITE GREEN"
  exit 0
else
  echo "SUITE RED"
  exit 1
fi
