#!/usr/bin/env bash
# tests/test-review-pool-never-empty.sh — dispatch-8e2a32be round 2: the review pool
# must never be empty, even when codex+glm are both quota-locked and the author is
# excluded from reviewing itself.
#
# Root cause (see leadv2-glm-policy-resolve.py / leadv2-dispatch-product-close.sh
# headers): the review-pool resolver never found a routing yaml at runtime
# (.claude/ref/leadv2-routing.yaml does not exist in any of the three live repos),
# so it silently fell back to a degraded no-op path that printed NO
# reviewer=/pool=/refusal= lines at all -- all_arms_unavailable was a bash-side
# default, not a real resolver verdict. This suite proves:
#   D1 -- ordered routing-yaml self-heal (tenant -> plugin -> canonical)
#   D2 -- --review-pool output is now unconditional on every return path
#   D3 -- a non-hardcoded review_rank floor guarantees a non-empty pool
#   D4 -- the resolver reads the on-disk quota-lockout store
#   D5 -- both terminal "no reviewer" shapes are loud and always-populated
#
# Hermetic: every test exports its OWN LEADV2_QUOTA_LOCKOUT_DIR / LEADV2_ROUTING_YAML
# (only where a tenant override is deliberately under test) / LEADV2_QUOTA_NOW_EPOCH
# under TMP_ROOT -- the real ~/.claude/cache/dispatch-ledger/quota-lockout-codex.json
# is NEVER touched, and no test relies on a live network quota/kimi read (both are
# stubbed via --quota-live / --kimi-bin / LEADV2_DISPATCH_KIMI_BIN fakes).
#
# T1/T6 drive the REAL leadv2-dispatch-product-close.sh end to end (same harness
# pattern as test-review-silence-gate.sh) so "review actually runs" and the
# tried:/pool: shape in review-gate.md are proven at the bash layer, not just the
# python resolver's stdout. T2-T5 call the real resolver CLI directly -- lighter
# weight, and the natural level to assert reviewer=/pool=/refusal=/codex_quota_blocked=.

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
source "${SCRIPTS_ROOT}/leadv2-temp.sh"

RESOLVER="${SCRIPTS_ROOT}/lib/leadv2-glm-policy-resolve.py"
PRODUCT_CLOSE_SH="${SCRIPTS_ROOT}/leadv2-dispatch-product-close.sh"
CANONICAL_ROUTING_YAML="${SCRIPTS_ROOT}/../config/leadv2-routing.yaml"

FAIL=0
pass() { printf 'PASS: %s\n' "$1"; }
fail() { printf 'FAIL: %s -- %s\n' "$1" "$2"; FAIL=1; }

if bash -n "${PRODUCT_CLOSE_SH}"; then pass "bash -n clean (leadv2-dispatch-product-close.sh)"; else fail "bash -n" "product-close.sh"; fi
if python3 -m py_compile "${RESOLVER}"; then pass "py_compile clean (leadv2-glm-policy-resolve.py)"; else fail "py_compile" "resolver.py"; fi

SUITE_TMP="$(lv2_mktemp_dir "review-pool-never-empty-test")"
trap 'rm -rf "${SUITE_TMP}"' EXIT

NOW_EPOCH=2000000000

# write_lockout <dir> <provider> <relative_seconds_from_now> -- negative = expired.
write_lockout() {
  local dir="$1" provider="$2" rel="$3" until
  mkdir -p "${dir}"
  until=$(( NOW_EPOCH + rel ))
  cat > "${dir}/quota-lockout-${provider}.json" <<JSON
{"provider": "${provider}", "locked_until": "test", "locked_until_epoch": ${until}, "source": "test-seed"}
JSON
}

# fake_quota_live <path> <mode> -- mode=unknown: every provider reads as unmeasured
# (status=error, exactly today's real posture for codex/claude per the yaml's own
# "codex and claude have no ceiling reader at all" comment). mode=anthropic_high:
# anthropic reads as a KNOWN over-threshold 99% (forces opus/sonnet genuinely
# :blocked:, not :unknown: -- the distinction that matters for the last-index
# auto-pick rule in resolve_review_pool).
make_fake_quota_live() {
  local path="$1" mode="$2"
  cat > "${path}" <<SH
#!/usr/bin/env bash
provider="\${1:-}"
if [[ "${mode}" == anthropic_high && "\${provider}" == anthropic ]]; then
  printf '{"status":"ok","accounts":[{"active":true,"five_hour_pct":99,"seven_day_pct":99}]}\n'
else
  printf '{"status":"error"}\n'
fi
exit 0
SH
  chmod +x "${path}"
}

# fake_kimi_probe_fail -- kimi-coder.sh `probe` contract: rc 77 = channel down
# (deterministic, no network). Every test uses this so kimi never resolves True/None
# from a real network probe.
make_fake_kimi_fail() {
  local path="$1"
  cat > "${path}" <<'SH'
#!/usr/bin/env bash
case "${1:-}" in
  probe) exit 77 ;;
  *) exit 2 ;;
esac
SH
  chmod +x "${path}"
}

# make_arch_pass <path> -- claude-subsession.sh stand-in: prints a clean PASS verdict
# so run_reviewer_arm's sonnet/opus/haiku/fable branch actually completes review.
make_arch_pass() {
  local path="$1"
  cat > "${path}" <<'SH'
#!/usr/bin/env bash
printf 'REVIEW_VERDICT: PASS\nREVIEW_FINDINGS: critical=0 high=0 medium=0 low=0\nClean diff, floor reviewer, nothing to flag.\n'
exit 0
SH
  chmod +x "${path}"
}

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

# call_resolver <lockout_dir> <quota_live_mode> <author> [<routing_yaml>]
# -> stdout of the resolver's full output (arm=.../reviewer=.../pool=.../refusal=...).
call_resolver() {
  local lockout_dir="$1" quota_mode="$2" author="$3" routing_yaml="${4:-${CANONICAL_ROUTING_YAML}}"
  local ql kb
  ql="${SUITE_TMP}/shared-quota-live-${quota_mode}.sh"
  [[ -f "${ql}" ]] || make_fake_quota_live "${ql}" "${quota_mode}"
  kb="${SUITE_TMP}/shared-kimi-fail.sh"
  [[ -f "${kb}" ]] || make_fake_kimi_fail "${kb}"
  LEADV2_QUOTA_LOCKOUT_DIR="${lockout_dir}" LEADV2_QUOTA_NOW_EPOCH="${NOW_EPOCH}" \
    python3 "${RESOLVER}" --routing-yaml "${routing_yaml}" --job review --base-arm codex \
      --review-pool --author "${author}" --quota-live "${ql}" --kimi-bin "${kb}" 2>&1
}

extract() { # <field> <resolver_output>
  printf '%s\n' "$2" | sed -n "s/^$1=//p" | head -n1
}

# ── T1: author=sonnet, codex+glm locked out on disk => reviewer=opus, review runs ──
root1="$(make_fixture_root t1 "t1-unique-diff-content")"
lockout1="${SUITE_TMP}/t1/lockout"
write_lockout "${lockout1}" codex 3600
write_lockout "${lockout1}" glm 3600
kimi1="${SUITE_TMP}/t1/kimi-fail.sh"; make_fake_kimi_fail "${kimi1}"
ql1="${SUITE_TMP}/t1/quota-live-unknown.sh"; make_fake_quota_live "${ql1}" unknown
arch1="${SUITE_TMP}/t1/arch-pass.sh"; make_arch_pass "${arch1}"
out1="$(LEADV2_QUOTA_LOCKOUT_DIR="${lockout1}" LEADV2_QUOTA_NOW_EPOCH="${NOW_EPOCH}" \
  GLM_POLICY_QUOTA_LIVE="${ql1}" \
  LEADV2_DISPATCH_KIMI_BIN="${kimi1}" \
  LEADV2_DISPATCH_ARCHITECT_BIN="${arch1}" \
  LEADV2_JOURNAL_BIN=/bin/true LEADV2_E2E_OWNERSHIP=0 \
  LEADV2_DISPATCH_CACHE_DIR="${SUITE_TMP}/t1/cache" \
  bash "${PRODUCT_CLOSE_SH}" "${root1}" t1sig001 sonnet "" 0 1 "" 2>&1)"
rc1=$?
gate1="${root1}/docs/handoff/dispatch-t1sig001/review-gate.md"
t1_reviewer="$(sed -n 's/^reviewer: //p' "${gate1}" 2>/dev/null | head -n1)"
if [[ ${rc1} -eq 0 && "${t1_reviewer}" == "opus" ]] \
  && grep -q '^status: pass$' "${gate1}" 2>/dev/null; then
  pass "T1: author=sonnet, codex+glm locked -> reviewer=opus, review ran to status=pass"
else
  fail "T1: author=sonnet floor-to-opus" "rc=${rc1} reviewer=${t1_reviewer} gate=$(cat "${gate1}" 2>/dev/null || echo MISSING) out=${out1}"
fi

# ── T2: author=opus, codex+glm locked out => reviewer=fable ────────────────────────
lockout2="${SUITE_TMP}/t2/lockout"
write_lockout "${lockout2}" codex 3600
write_lockout "${lockout2}" glm 3600
out2="$(call_resolver "${lockout2}" anthropic_high opus)"
reviewer2="$(extract reviewer "${out2}")"
pool2="$(extract pool "${out2}")"
if [[ "${reviewer2}" == "fable" ]] && [[ "${pool2}" == *"fable:floor:"* ]]; then
  pass "T2: author=opus, codex+glm locked -> reviewer=fable (D3 floor)"
else
  fail "T2: author=opus floor-to-fable" "reviewer=${reviewer2} pool=${pool2} out=${out2}"
fi

# ── T3: codex lockout file present => codex_quota_blocked=1, codex absent from :ok: ──
lockout3="${SUITE_TMP}/t3/lockout"
write_lockout "${lockout3}" codex 3600
out3="$(call_resolver "${lockout3}" unknown sonnet)"
blocked3="$(extract codex_quota_blocked "${out3}")"
pool3="$(extract pool "${out3}")"
if [[ "${blocked3}" == "1" ]] && [[ "${pool3}" == *"codex:blocked:lockout"* ]] && [[ "${pool3}" != *"codex:ok:"* ]]; then
  pass "T3: codex lockout -> codex_quota_blocked=1, codex:blocked:lockout (not :ok:)"
else
  fail "T3: codex lockout gating" "codex_quota_blocked=${blocked3} pool=${pool3} out=${out3}"
fi

# ── T4: routing yaml unreadable/nonexistent + --review-pool => self-heal (D1+D2) ───
lockout4="${SUITE_TMP}/t4/lockout"
out4="$(call_resolver "${lockout4}" unknown sonnet "${SUITE_TMP}/t4/does-not-exist.yaml")"
reviewer4="$(extract reviewer "${out4}")"
pool4="$(extract pool "${out4}")"
if [[ -n "${reviewer4}" ]] && [[ -n "${pool4}" ]]; then
  pass "T4: nonexistent --routing-yaml self-heals to plugin-local -- reviewer/pool non-empty"
else
  fail "T4: routing-yaml self-heal" "reviewer=${reviewer4} pool=${pool4} out=${out4}"
fi

# ── T4b: existing tenant YAML without glm_policy still has a review pool ───────
tenant_no_policy="${SUITE_TMP}/t4b/tenant-routing.yaml"
mkdir -p "${SUITE_TMP}/t4b"
cat > "${tenant_no_policy}" <<'YAML'
phases:
  review:
    standard:
      default: codex
YAML
out4b="$(call_resolver "${SUITE_TMP}/t4b/lockout" unknown sonnet "${tenant_no_policy}")"
reviewer4b="$(extract reviewer "${out4b}")"
pool4b="$(extract pool "${out4b}")"
if [[ -n "${pool4b}" ]] && [[ "${out4b}" != *"Traceback"* ]]; then
  pass "T4b: tenant without glm_policy emits a pool without a resolver crash"
else
  fail "T4b: tenant without glm_policy" "reviewer=${reviewer4b} pool=${pool4b} out=${out4b}"
fi

# ── T5: author not in the rank table => pool non-empty, reviewer != author ─────────
lockout5="${SUITE_TMP}/t5/lockout"
write_lockout "${lockout5}" codex 3600
write_lockout "${lockout5}" glm 3600
out5="$(call_resolver "${lockout5}" anthropic_high "not-a-real-arm")"
reviewer5="$(extract reviewer "${out5}")"
pool5="$(extract pool "${out5}")"
if [[ -n "${reviewer5}" ]] && [[ "${reviewer5}" != "not-a-real-arm" ]] && [[ -n "${pool5}" ]]; then
  pass "T5: unknown author -> non-empty pool, reviewer(${reviewer5}) != author"
else
  fail "T5: unknown-author floor" "reviewer=${reviewer5} pool=${pool5} out=${out5}"
fi
# T5 detail: rank(unknown author) == -infinity, so floor must pick the LOWEST-ranked
# table entry (haiku, rank 1) -- confirms the -infinity rule is real, not incidental.
if [[ "${reviewer5}" == "haiku" ]]; then
  pass "T5 detail: -infinity author rank floors to the lowest-ranked entry (haiku)"
else
  fail "T5 detail: expected floor=haiku for an unranked author" "reviewer=${reviewer5}"
fi

# ── T6: forced all_arms_unavailable (degenerate rank table) -- tried: is populated ──
degenerate_yaml="${SUITE_TMP}/t6/degenerate-routing.yaml"
mkdir -p "${SUITE_TMP}/t6"
cat > "${degenerate_yaml}" <<'YAML'
router:
  dispatch_ladder:
    - id: glm
      provider: glm
    - id: codex
      provider: codex
    - id: sonnet
      provider: anthropic
    - id: opus
      provider: anthropic
  glm_policy:
    protected_path_patterns: []
YAML
root6="$(make_fixture_root t6 "t6-unique-diff-content")"
lockout6="${SUITE_TMP}/t6/lockout"
write_lockout "${lockout6}" codex 3600
write_lockout "${lockout6}" glm 3600
kimi6="${SUITE_TMP}/t6/kimi-fail.sh"; make_fake_kimi_fail "${kimi6}"
ql6="${SUITE_TMP}/t6/quota-live-high.sh"; make_fake_quota_live "${ql6}" anthropic_high
out6="$(LEADV2_ROUTING_YAML="${degenerate_yaml}" \
  LEADV2_QUOTA_LOCKOUT_DIR="${lockout6}" LEADV2_QUOTA_NOW_EPOCH="${NOW_EPOCH}" \
  GLM_POLICY_QUOTA_LIVE="${ql6}" \
  LEADV2_DISPATCH_KIMI_BIN="${kimi6}" \
  LEADV2_JOURNAL_BIN=/bin/true LEADV2_E2E_OWNERSHIP=0 \
  LEADV2_DISPATCH_CACHE_DIR="${SUITE_TMP}/t6/cache" \
  bash "${PRODUCT_CLOSE_SH}" "${root6}" t6sig006 sonnet "" 0 1 "" 2>&1)"
rc6=$?
gate6="${root6}/docs/handoff/dispatch-t6sig006/review-gate.md"
if [[ ${rc6} -eq 9 ]] \
  && grep -q '^status: unreviewed$' "${gate6}" 2>/dev/null \
  && grep -q '^tried: -$' "${gate6}" 2>/dev/null \
  && grep -q '^pool: ' "${gate6}" 2>/dev/null; then
  pass "T6: degenerate rank table -> genuine all_arms_unavailable, tried: - (populated dash)"
else
  fail "T6: forced all_arms_unavailable shape" "rc=${rc6} gate=$(cat "${gate6}" 2>/dev/null || echo MISSING) out=${out6}"
fi

# ── T7 (regression): across T1/T2/T5, reviewer is never equal to author ────────────
t7_ok=1
[[ "${t1_reviewer}" == "sonnet" ]] && t7_ok=0
[[ "${reviewer2}" == "opus" ]] && t7_ok=0
[[ "${reviewer5}" == "not-a-real-arm" ]] && t7_ok=0
if [[ ${t7_ok} -eq 1 ]]; then
  pass "T7: reviewer never equals author across T1(${t1_reviewer})/T2(${reviewer2})/T5(${reviewer5})"
else
  fail "T7: reviewer==author regression" "t1=${t1_reviewer} t2=${reviewer2} t5=${reviewer5}"
fi

# ── Regression: existing round-1 suite (5 cases) must still fully pass ─────────────
POSTSPAWN_SUITE="${SCRIPT_DIR}/test-quota-lockout-postspawn.sh"
if [[ -f "${POSTSPAWN_SUITE}" ]]; then
  out_ps="$(bash "${POSTSPAWN_SUITE}" 2>&1)"; rc_ps=$?
  fail_n_ps="$(grep -c '^FAIL:' <<<"${out_ps}")"
  if [[ ${rc_ps} -eq 0 && ${fail_n_ps} -eq 0 ]]; then
    pass "regression: test-quota-lockout-postspawn.sh still fully passes"
  else
    fail "regression: test-quota-lockout-postspawn.sh" "rc=${rc_ps} fail_n=${fail_n_ps} out=${out_ps}"
  fi
else
  fail "regression suite missing" "expected at ${POSTSPAWN_SUITE}"
fi

[[ ${FAIL} -eq 0 ]]
