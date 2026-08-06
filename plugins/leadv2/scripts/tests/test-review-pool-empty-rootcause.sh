#!/usr/bin/env bash
# tests/test-review-pool-empty-rootcause.sh — dispatch-59a0e749 (CODEX-QUOTA-GATE r2,
# Layer A): a resolver crash must be LOUD, never the silent empty
# `pool:`/`tried:` shape that made the live dispatch-83c44855 review-gate.md
# undiagnosable (status: unreviewed / reason: all_arms_unavailable / pool: / tried:,
# with NO refusal:/resolver_rc: line at all).
#
# Root cause established for THIS lane's live incident (see leadv2-dispatch-
# product-close.sh:resolve_review_pool_call header + the D1 self-heal): the
# resolver never found a routing yaml at runtime and its ONLY visible symptom was
# `2>/dev/null` swallowing everything. This suite proves the two Layer-A fixes that
# make the NEXT such failure self-diagnosing instead of a second guessing round:
#   A2 -- resolver stderr lands in a per-lane file + rc is captured, never
#         thrown away, and both are printed as resolver_rc=/resolver_stderr=
#   A3 -- both terminal "no reviewer" branches converge on the ONE writer
#         (_pc_write_unreviewed), so refusal:/resolver_rc:/resolver_stderr:/
#         merge_blocked: can never again be silently absent from review-gate.md
#
# Hermetic: LEADV2_GLM_POLICY_RESOLVER swaps in a fake resolver script so no live
# quota/network read ever happens; every test uses its own LEADV2_QUOTA_LOCKOUT_DIR
# under TMP_ROOT.

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
source "${SCRIPTS_ROOT}/leadv2-temp.sh"

PRODUCT_CLOSE_SH="${SCRIPTS_ROOT}/leadv2-dispatch-product-close.sh"
CANONICAL_ROUTING_YAML="${SCRIPTS_ROOT}/../config/leadv2-routing.yaml"

FAIL=0
pass() { printf 'PASS: %s\n' "$1"; }
fail() { printf 'FAIL: %s -- %s\n' "$1" "$2"; FAIL=1; }

if bash -n "${PRODUCT_CLOSE_SH}"; then pass "bash -n clean (leadv2-dispatch-product-close.sh)"; else fail "bash -n" "product-close.sh"; fi

SUITE_TMP="$(lv2_mktemp_dir "review-pool-rootcause-test")"
trap 'rm -rf "${SUITE_TMP}"' EXIT

make_fixture_root() {
  local name="$1" content="$2"
  local repo="${SUITE_TMP}/${name}/root"
  mkdir -p "${repo}"
  git -C "${repo}" init -q
  git -C "${repo}" config user.email "test@test.local"
  git -C "${repo}" config user.name "test"
  printf 'baseline\n' > "${repo}/file.txt"
  git -C "${repo}" add file.txt
  git -C "${repo}" commit -q -m init
  lv2_assert_scratch_repo "${repo}"
  printf '%s\n' "${content}" >> "${repo}/file.txt"
  printf '%s' "${repo}"
}

# ── T1: resolver crashes (rc=1, stderr="boom", no stdout) -- must be loud, not empty ──
crash_resolver="${SUITE_TMP}/crash-resolver.py"
cat > "${crash_resolver}" <<'PY'
import sys
sys.stderr.write("boom: simulated resolver crash\n")
sys.exit(1)
PY
root1="$(make_fixture_root t1 "t1-unique-diff-content")"
out1="$(LEADV2_GLM_POLICY_RESOLVER="${crash_resolver}" \
  LEADV2_QUOTA_LOCKOUT_DIR="${SUITE_TMP}/t1/lockout" \
  LEADV2_JOURNAL_BIN=/bin/true LEADV2_E2E_OWNERSHIP=0 \
  LEADV2_DISPATCH_CACHE_DIR="${SUITE_TMP}/t1/cache" \
  bash "${PRODUCT_CLOSE_SH}" "${root1}" t1sigrc01 sonnet "" 0 1 "" 2>&1)"
rc1=$?
gate1="${root1}/docs/handoff/dispatch-t1sigrc01/review-gate.md"
gate1_body="$(cat "${gate1}" 2>/dev/null || echo MISSING)"
if [[ ${rc1} -eq 9 ]] \
  && grep -q '^status: unreviewed$' "${gate1}" 2>/dev/null \
  && grep -q '^refusal: ' "${gate1}" 2>/dev/null \
  && ! grep -q '^refusal: $' "${gate1}" 2>/dev/null \
  && grep -qE '^resolver_rc: [0-9]+$' "${gate1}" 2>/dev/null \
  && ! grep -q '^resolver_rc: -$' "${gate1}" 2>/dev/null \
  && grep -qE '^resolver_stderr: .+$' "${gate1}" 2>/dev/null \
  && ! grep -q '^resolver_stderr: -$' "${gate1}" 2>/dev/null \
  && grep -q '^merge_blocked: true$' "${gate1}" 2>/dev/null \
  && grep -q '^pool: -$' "${gate1}" 2>/dev/null \
  && grep -q '^tried: -$' "${gate1}" 2>/dev/null; then
  pass "T1: resolver crash -> review-gate.md is loud (refusal/resolver_rc/resolver_stderr/merge_blocked all populated)"
else
  fail "T1: resolver crash loud-failure shape" "rc=${rc1} gate=${gate1_body} out=${out1}"
fi

# T1 detail: the resolver's own stderr text actually landed in the referenced file.
stderr_path="$(sed -n 's/^resolver_stderr: //p' "${gate1}" 2>/dev/null | head -n1)"
if [[ -n "${stderr_path}" && -f "${stderr_path}" ]] && grep -q 'boom: simulated resolver crash' "${stderr_path}" 2>/dev/null; then
  pass "T1 detail: resolver_stderr: path contains the resolver's actual stderr text"
else
  fail "T1 detail: resolver stderr capture" "path=${stderr_path} contents=$(cat "${stderr_path}" 2>/dev/null || echo MISSING)"
fi

# ── T2: resolver_rc line is emitted on the SUCCESS path too, not only on failure ──
root2="$(make_fixture_root t2 "t2-unique-diff-content")"
arch2="${SUITE_TMP}/t2/arch-pass.sh"
cat > "${arch2}" <<'SH'
#!/usr/bin/env bash
printf 'REVIEW_VERDICT: PASS\nREVIEW_FINDINGS: critical=0 high=0 medium=0 low=0\nClean diff.\n'
exit 0
SH
chmod +x "${arch2}"
kimi2="${SUITE_TMP}/t2/kimi-fail.sh"
cat > "${kimi2}" <<'SH'
#!/usr/bin/env bash
case "${1:-}" in probe) exit 77 ;; *) exit 2 ;; esac
SH
chmod +x "${kimi2}"
out2="$(LEADV2_QUOTA_LOCKOUT_DIR="${SUITE_TMP}/t2/lockout" \
  LEADV2_DISPATCH_KIMI_BIN="${kimi2}" \
  LEADV2_DISPATCH_ARCHITECT_BIN="${arch2}" \
  LEADV2_JOURNAL_BIN=/bin/true LEADV2_E2E_OWNERSHIP=0 \
  LEADV2_DISPATCH_CACHE_DIR="${SUITE_TMP}/t2/cache" \
  bash "${PRODUCT_CLOSE_SH}" "${root2}" t2sigrc02 sonnet "" 0 1 "" 2>&1)"
if grep -qE 'review_pool_resolve task=t2sigrc02 rc=[0-9]+ reviewer=[a-z]+ pool_n=[0-9]+' <<<"${out2}"; then
  pass "T2: review_pool_resolve ledger line present on the successful path too"
else
  fail "T2: review_pool_resolve ledger line missing on success" "out=${out2}"
fi

# T3 (regression) intentionally NOT re-run here: test-review-pool-never-empty.sh
# already nests test-quota-lockout-postspawn.sh (which itself nests
# test-routing-enforcement-p1.sh) as its own regression tail -- stacking a THIRD
# layer on top here only multiplies wall-clock (each layer re-runs everything below
# it) without adding coverage. Run that suite directly for the same evidence.

[[ ${FAIL} -eq 0 ]]
