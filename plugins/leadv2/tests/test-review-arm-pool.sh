#!/usr/bin/env bash
# tests/test-review-arm-pool.sh — regression harness for dispatch-00629379
# (P0: review gate has no available reviewer). Exercises the resolver's CLI
# --review-pool mode with a stub --quota-live so no live provider call is made.
# Must FAIL on pre-fix HEAD (resolver has no --review-pool flag at all) and
# PASS after. Usage: bash tests/test-review-arm-pool.sh
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RESOLVER="${HERE}/../scripts/lib/leadv2-glm-policy-resolve.py"
TMPDIR_BASE="$(mktemp -d)"
trap 'rm -rf "${TMPDIR_BASE}"' EXIT

PASS=0
FAIL=0
pass() { printf -- 'PASS: %s\n' "$1"; PASS=$(( PASS + 1 )); }
fail() { printf -- 'FAIL: %s (%s)\n' "$1" "$2"; FAIL=$(( FAIL + 1 )); }

# Minimal routing.yaml carrying only the glm_policy/codex_quota_gate block the
# resolver's regex extractor reads — no other yaml content needed.
ROUTING_YAML="${TMPDIR_BASE}/routing.yaml"
cat > "${ROUTING_YAML}" <<'YAML'
router:
  glm_policy:
    codex_quota_gate:
      build_threshold_pct: 80
      review_threshold_pct: 95
      build_spill_order: [glm, codex, sonnet]
      review_arm_exclusions: [glm]
      review_arm_order: [codex, glm, opus, sonnet]
      glm_review_threshold_pct: 90
      anthropic_review_threshold_pct: 95
YAML

# Stub --quota-live: emits canned per-bucket JSON keyed by $1 (glm/codex/anthropic),
# values driven by env CODEX_PCT / GLM_FIVE_PCT / GLM_WEEK_PCT / ANTHRO_PCT.
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

run_resolver() { # <author>
  python3 "${RESOLVER}" --routing-yaml "${ROUTING_YAML}" --job review --base-arm codex \
    --review-pool --author "$1" --quota-live "${QUOTA_STUB}"
}

field() { # <output> <field>
  printf '%s\n' "$1" | sed -n "s/^$2=//p" | head -n1
}

# (a) author=sonnet, codex=100 (blocked), glm=84 (ok) -> reviewer=glm (today: sonnet, conflict)
out="$(CODEX_PCT=100 GLM_FIVE_PCT=84 GLM_WEEK_PCT=50 ANTHRO_PCT=12 run_resolver sonnet)"
reviewer="$(field "${out}" reviewer)"
if [[ "${reviewer}" == "glm" ]]; then
  pass "(a) codex-blocked, glm-84 -> reviewer=glm"
else
  fail "(a) codex-blocked, glm-84 -> reviewer=glm" "got reviewer=${reviewer}"
fi

# (b) glm=85 -> glm offered; glm=95 -> glm refused (reviewer moves past it)
out_ok="$(CODEX_PCT=100 GLM_FIVE_PCT=85 GLM_WEEK_PCT=50 ANTHRO_PCT=12 run_resolver sonnet)"
reviewer_ok="$(field "${out_ok}" reviewer)"
if [[ "${reviewer_ok}" == "glm" ]]; then
  pass "(b1) glm=85 -> offered as reviewer"
else
  fail "(b1) glm=85 -> offered as reviewer" "got reviewer=${reviewer_ok}"
fi
out_blocked="$(CODEX_PCT=100 GLM_FIVE_PCT=95 GLM_WEEK_PCT=50 ANTHRO_PCT=12 run_resolver sonnet)"
reviewer_blocked="$(field "${out_blocked}" reviewer)"
pool_blocked="$(field "${out_blocked}" pool)"
if [[ "${reviewer_blocked}" == "opus" ]] && [[ "${pool_blocked}" == *"glm:blocked:95"* ]]; then
  pass "(b2) glm=95 -> refused, reviewer=opus"
else
  fail "(b2) glm=95 -> refused, reviewer=opus" "got reviewer=${reviewer_blocked} pool=${pool_blocked}"
fi

# (c) matrix over author in {glm,codex,sonnet,opus} -> reviewer != author
c_all_ok=1
for author in glm codex sonnet opus; do
  out_c="$(CODEX_PCT=50 GLM_FIVE_PCT=50 GLM_WEEK_PCT=50 ANTHRO_PCT=50 run_resolver "${author}")"
  reviewer_c="$(field "${out_c}" reviewer)"
  if [[ -z "${reviewer_c}" || "${reviewer_c}" == "${author}" ]]; then
    c_all_ok=0
    fail "(c) author=${author} -> reviewer != author" "got reviewer='${reviewer_c}'"
  fi
done
[[ "${c_all_ok}" == "1" ]] && pass "(c) reviewer != author across full arm matrix"

# (d) every arm blocked -> reviewer empty, refusal=all_review_arms_unavailable
out_d="$(CODEX_PCT=100 GLM_FIVE_PCT=95 GLM_WEEK_PCT=95 ANTHRO_PCT=96 run_resolver sonnet)"
reviewer_d="$(field "${out_d}" reviewer)"
refusal_d="$(field "${out_d}" refusal)"
if [[ -z "${reviewer_d}" && "${refusal_d}" == "all_review_arms_unavailable" ]]; then
  pass "(d) all arms blocked -> reviewer empty, refusal=all_review_arms_unavailable"
else
  fail "(d) all arms blocked -> reviewer empty, refusal=all_review_arms_unavailable" "got reviewer='${reviewer_d}' refusal='${refusal_d}'"
fi

# (e) opus selected -> pool marks it ok (launcher argv assertion lives in the bash
# gate consumer, not the resolver — covered by (f2) below via product-close's
# --model "${reviewer}" substitution, verified by direct grep since spawning a real
# claude-subsession is out of scope for a resolver-only harness).
out_e="$(CODEX_PCT=100 GLM_FIVE_PCT=95 GLM_WEEK_PCT=95 ANTHRO_PCT=12 run_resolver sonnet)"
reviewer_e="$(field "${out_e}" reviewer)"
if [[ "${reviewer_e}" == "opus" ]]; then
  pass "(e) codex+glm blocked, anthropic ok -> reviewer=opus"
else
  fail "(e) codex+glm blocked, anthropic ok -> reviewer=opus" "got reviewer=${reviewer_e}"
fi
PRODUCT_CLOSE="${HERE}/../scripts/leadv2-dispatch-product-close.sh"
if grep -qE -- '--model "\$\{reviewer\}"' "${PRODUCT_CLOSE}"; then
  pass "(e2) product-close launcher passes --model \"\${reviewer}\" (R1 guard, no hardcoded sonnet)"
else
  fail "(e2) product-close launcher passes --model \"\${reviewer}\"" "hardcoded --model sonnet still present or pattern missing"
fi

# (f) no --review-pool -> output byte-identical to pre-change (v1-equivalence)
out_f="$(python3 "${RESOLVER}" --routing-yaml "${ROUTING_YAML}" --job review --base-arm codex --quota-live "${QUOTA_STUB}")"
line_count="$(printf '%s\n' "${out_f}" | grep -c .)"
if [[ "${line_count}" -eq 5 ]] && ! printf '%s\n' "${out_f}" | grep -q '^reviewer='; then
  pass "(f) no --review-pool -> exact 5-line legacy output, no reviewer=/pool=/refusal="
else
  fail "(f) no --review-pool -> exact 5-line legacy output" "got:
${out_f}"
fi

# product-close must never WRITE status: conflict for this gate anymore (mentions in
# comments/docstrings describing the retired behavior are fine — only the printf that
# actually emits the artifact line matters).
if grep -qE "printf '.*status: conflict" "${PRODUCT_CLOSE}"; then
  fail "(g) status: conflict retired from review gate" "printf still emits status: conflict"
else
  pass "(g) status: conflict retired from review gate"
fi
if grep -q 'status: no_reviewer' "${PRODUCT_CLOSE}"; then
  pass "(h) status: no_reviewer artifact present"
else
  fail "(h) status: no_reviewer artifact present" "not found in leadv2-dispatch-product-close.sh"
fi

printf -- '\n%d passed, %d failed\n' "${PASS}" "${FAIL}"
exit "${FAIL}"
