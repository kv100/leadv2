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

# KIMI-CHANNEL-01b: kimi stub + a kimi-inclusive yaml + a default-order yaml.
# KIMI_STUB mimics kimi-coder.sh `probe` only (the resolver calls nothing else on
# it); rc is driven by $KIMI_RC (0=up, 77=down, 75=secret/lock, 1=other-unknown).
# Default 0 so the non-kimi tests (a..h) are unaffected even if they passed it.
KIMI_STUB="${TMPDIR_BASE}/kimi-coder-stub.sh"
cat > "${KIMI_STUB}" <<'STUB'
#!/usr/bin/env bash
if [[ "${1:-}" == "probe" ]]; then
  exit "${KIMI_RC:-0}"
fi
exit 0
STUB
chmod +x "${KIMI_STUB}"

# yaml that explicitly opts kimi into the review pool.
ROUTING_YAML_KIMI="${TMPDIR_BASE}/routing-kimi.yaml"
cat > "${ROUTING_YAML_KIMI}" <<'YAML'
router:
  glm_policy:
    codex_quota_gate:
      build_threshold_pct: 80
      review_threshold_pct: 95
      build_spill_order: [glm, codex, sonnet]
      review_arm_exclusions: [glm]
      review_arm_order: [codex, glm, kimi, opus, sonnet]
      glm_review_threshold_pct: 90
      anthropic_review_threshold_pct: 95
YAML

# yaml with NO review_arm_order -- proves DEFAULT_REVIEW_ARM_ORDER still carries kimi.
ROUTING_YAML_DEFAULT="${TMPDIR_BASE}/routing-default.yaml"
cat > "${ROUTING_YAML_DEFAULT}" <<'YAML'
router:
  glm_policy:
    codex_quota_gate:
      build_threshold_pct: 80
      review_threshold_pct: 95
      build_spill_order: [glm, codex, sonnet]
      review_arm_exclusions: [glm]
YAML

# KIMI-CHANNEL-01b kimi-aware invocation. Extra args (--signals/--kimi-bin) appended.
run_resolver_kimi() { # <author> <yaml> [extra resolver args...]
  local _author="$1" _yaml="$2"; shift 2
  python3 "${RESOLVER}" --routing-yaml "${_yaml}" --job review --base-arm codex \
    --review-pool --author "${_author}" --quota-live "${QUOTA_STUB}" \
    --kimi-bin "${KIMI_STUB}" "$@"
}

# True iff literal token <a> appears before literal token <b> in <haystack>.
pos_before() { # <haystack> <a-token> <b-token>
  local h="$1" a="$2" b="$3" ia ib
  ia="$(printf '%s' "$h" | grep -bo -- "$a" | head -n1 | cut -d: -f1)"
  ib="$(printf '%s' "$h" | grep -bo -- "$b" | head -n1 | cut -d: -f1)"
  [[ -n "$ia" && -n "$ib" && "$ia" -lt "$ib" ]]
}

run_resolver() { # <author>
  python3 "${RESOLVER}" --routing-yaml "${ROUTING_YAML}" --job review --base-arm codex \
    --review-pool --author "$1" --quota-live "${QUOTA_STUB}" --kimi-bin "${KIMI_STUB}"
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
if grep -qE -- '--model "\$\{arm\}"' "${PRODUCT_CLOSE}"; then
  pass "(e2) product-close launcher passes --model \"\${arm}\" (R1 guard, no hardcoded sonnet; KIMI-CHANNEL-01b renamed inline \${reviewer} to the run_reviewer_arm param \${arm})"
else
  fail "(e2) product-close launcher passes --model \"\${arm}\"" "hardcoded --model sonnet still present or pattern missing"
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

# ---- KIMI-CHANNEL-01b: kimi as a probe-gated reviewer arm ---------------------
# (k1) codex+glm both over threshold, kimi probe up -> reviewer=kimi, kimi:ok:
# positioned after the codex and glm fields.
out1="$(CODEX_PCT=100 GLM_FIVE_PCT=95 GLM_WEEK_PCT=95 ANTHRO_PCT=12 KIMI_RC=0 run_resolver_kimi sonnet "${ROUTING_YAML_KIMI}")"
reviewer1="$(field "${out1}" reviewer)"
pool1="$(field "${out1}" pool)"
if [[ "${reviewer1}" == kimi && "${pool1}" == *"kimi:ok:"* \
  && "$(pos_before "${pool1}" "codex:" "kimi:" && echo yes)" == yes \
  && "$(pos_before "${pool1}" "glm:" "kimi:" && echo yes)" == yes ]]; then
  pass "(k1) codex+glm blocked, kimi up -> reviewer=kimi, kimi:ok: after codex/glm"
else
  fail "(k1) codex+glm blocked, kimi up -> reviewer=kimi" "got reviewer=${reviewer1} pool=${pool1}"
fi

# (k2) author=kimi -> self-review excluded: pool has kimi:author:, reviewer != kimi.
out2="$(CODEX_PCT=100 GLM_FIVE_PCT=95 GLM_WEEK_PCT=95 ANTHRO_PCT=12 KIMI_RC=0 run_resolver_kimi kimi "${ROUTING_YAML_KIMI}")"
reviewer2="$(field "${out2}" reviewer)"
pool2="$(field "${out2}" pool)"
if [[ "${pool2}" == *"kimi:author:"* && "${reviewer2}" != kimi && -n "${reviewer2}" ]]; then
  pass "(k2) author=kimi -> kimi:author:, reviewer != kimi"
else
  fail "(k2) author=kimi -> kimi:author:" "got reviewer=${reviewer2} pool=${pool2}"
fi

# (k3) probe rc 77 (channel down) -> kimi:blocked:probe, reviewer falls through.
out3="$(CODEX_PCT=100 GLM_FIVE_PCT=95 GLM_WEEK_PCT=95 ANTHRO_PCT=12 KIMI_RC=77 run_resolver_kimi sonnet "${ROUTING_YAML_KIMI}")"
reviewer3="$(field "${out3}" reviewer)"
pool3="$(field "${out3}" pool)"
if [[ "${pool3}" == *"kimi:blocked:probe"* && "${reviewer3}" != kimi \
  && ( "${reviewer3}" == opus || "${reviewer3}" == sonnet ) ]]; then
  pass "(k3) KIMI_RC=77 -> kimi:blocked:probe, falls through to opus/sonnet"
else
  fail "(k3) KIMI_RC=77 -> kimi:blocked:probe" "got reviewer=${reviewer3} pool=${pool3}"
fi

# (k4) safety signal -> kimi excluded outright (free arm never reviews a safety diff).
out4="$(CODEX_PCT=100 GLM_FIVE_PCT=95 GLM_WEEK_PCT=95 ANTHRO_PCT=12 KIMI_RC=0 run_resolver_kimi sonnet "${ROUTING_YAML_KIMI}" --signals '{"safety_touched":true}')"
reviewer4="$(field "${out4}" reviewer)"
pool4="$(field "${out4}" pool)"
if [[ "${pool4}" == *"kimi:excluded:safety"* && "${reviewer4}" != kimi ]]; then
  pass "(k4) safety_touched -> kimi:excluded:safety"
else
  fail "(k4) safety_touched -> kimi:excluded:safety" "got reviewer=${reviewer4} pool=${pool4}"
fi

# (k5) review_arm_order key ABSENT -> DEFAULT_REVIEW_ARM_ORDER still places kimi after glm.
out5="$(CODEX_PCT=100 GLM_FIVE_PCT=95 GLM_WEEK_PCT=95 ANTHRO_PCT=12 KIMI_RC=0 run_resolver_kimi sonnet "${ROUTING_YAML_DEFAULT}")"
reviewer5="$(field "${out5}" reviewer)"
pool5="$(field "${out5}" pool)"
if [[ "${reviewer5}" == kimi && "${pool5}" == *"kimi:ok:"* \
  && "$(pos_before "${pool5}" "glm:" "kimi:" && echo yes)" == yes ]]; then
  pass "(k5) review_arm_order absent -> default order still includes kimi after glm"
else
  fail "(k5) review_arm_order absent -> default order includes kimi" "got reviewer=${reviewer5} pool=${pool5}"
fi

# (k6) kimi-bin path nonexistent -> kimi:unknown:, NOT selected (a later arm exists).
out6="$(CODEX_PCT=100 GLM_FIVE_PCT=95 GLM_WEEK_PCT=95 ANTHRO_PCT=12 python3 "${RESOLVER}" \
  --routing-yaml "${ROUTING_YAML_KIMI}" --job review --base-arm codex --review-pool \
  --author sonnet --quota-live "${QUOTA_STUB}" --kimi-bin "${TMPDIR_BASE}/no-such-kimi.sh")"
reviewer6="$(field "${out6}" reviewer)"
pool6="$(field "${out6}" pool)"
if [[ "${pool6}" == *"kimi:unknown:"* && "${reviewer6}" != kimi && -n "${reviewer6}" ]]; then
  pass "(k6) kimi-bin nonexistent -> kimi:unknown:, not selected (later arm exists)"
else
  fail "(k6) kimi-bin nonexistent -> kimi:unknown:" "got reviewer=${reviewer6} pool=${pool6}"
fi

# ---- CODEX-GATE-01 item 6: real safety signals on the product-close review path ---------
# Exercises the LIVE lib/leadv2-review-signals.sh (sourced, not re-implemented -- a re-impl
# would make this tautological) and feeds its JSON to the resolver, asserting the resolver's
# kimi:excluded:safety branch now fires for a protected diff and kimi:ok: for a plain one.
# yaml carries BOTH kimi in review_arm_order (else the assertion passes vacuously) and a
# protected_path_patterns list.
#
# sig_call: wraps the lib so stdout(JSON)+stderr(source/matched) are both captured. The lib
# is invoked under $() (subshell), so it emits signals_source=/signals_matched= on stderr
# rather than via globals -- mirror the close script's temp-file capture.
SIGNALS_LIB="${HERE}/../scripts/lib/leadv2-review-signals.sh"
SIG_SRC="" ; SIG_MATCHED=""
sig_call() {  # <routing_yaml> <writes_csv>  -> SIG_JSON on stdout, sets SIG_SRC/SIG_MATCHED
  local _cap
  _cap="$(mktemp "${TMPDIR_BASE}/sig.XXXXXX")"
  SIG_JSON="$(leadv2_review_signals "$1" "$2" 2>"${_cap}" || true)"
  SIG_SRC="$(sed -n 's/^signals_source=//p' "${_cap}" | head -n1)"
  SIG_MATCHED="$(sed -n 's/^signals_matched=//p' "${_cap}" | head -n1)"
  rm -f "${_cap}"
}
ROUTING_YAML_SIG="${TMPDIR_BASE}/routing-signals.yaml"
cat > "${ROUTING_YAML_SIG}" <<'YAML'
router:
  glm_policy:
    codex_quota_gate:
      build_threshold_pct: 80
      review_threshold_pct: 95
      build_spill_order: [glm, codex, sonnet]
      review_arm_exclusions: [glm]
      review_arm_order: [codex, glm, kimi, opus, sonnet]
      glm_review_threshold_pct: 90
      anthropic_review_threshold_pct: 95
    protected_path_patterns:
      - "*safety*"
      - "*publish*"
      - "*payment*"
YAML

if [[ -f "${SIGNALS_LIB}" ]]; then
  pass "(s0) leadv2-review-signals.sh lib present"
  # shellcheck source=../scripts/lib/leadv2-review-signals.sh
  source "${SIGNALS_LIB}"

  # (s1) protected-path diff -> signals protected=true -> resolver excludes kimi:safety.
  sig_call "${ROUTING_YAML_SIG}" "agent/safety-gate.py"
  sig_json="${SIG_JSON}" ; sig_src="${SIG_SRC}" ; sig_matched="${SIG_MATCHED}"
  outs1="$(CODEX_PCT=100 GLM_FIVE_PCT=95 GLM_WEEK_PCT=95 ANTHRO_PCT=12 KIMI_RC=0 \
    run_resolver_kimi sonnet "${ROUTING_YAML_SIG}" --signals "${sig_json}")"
  pools1="$(field "${outs1}" pool)"
  reviewers1="$(field "${outs1}" reviewer)"
  if printf '%s' "${sig_json}" | grep -q '"protected_path":true' \
    && [[ "${sig_src}" == "lane_writes" && "${sig_matched}" == "agent/safety-gate.py" ]] \
    && [[ "${pools1}" == *"kimi:excluded:safety"* && "${reviewers1}" != kimi ]]; then
    pass "(s1) protected-path diff -> kimi:excluded:safety (source=${sig_src} matched=${sig_matched})"
  else
    fail "(s1) protected-path diff -> kimi:excluded:safety" "json=${sig_json} src=${sig_src} matched=${sig_matched} reviewer=${reviewers1} pool=${pools1}"
  fi

  # (s2) NEGATIVE control: ordinary path -> signals protected=false -> kimi:ok: present
  # (proves s1 is not passing vacuously -- kimi IS reachable when the diff is ordinary).
  sig_call "${ROUTING_YAML_SIG}" "agent/newmod.py"
  sig_json2="${SIG_JSON}" ; sig_src2="${SIG_SRC}"
  outs2="$(CODEX_PCT=100 GLM_FIVE_PCT=95 GLM_WEEK_PCT=95 ANTHRO_PCT=12 KIMI_RC=0 \
    run_resolver_kimi sonnet "${ROUTING_YAML_SIG}" --signals "${sig_json2}")"
  pools2="$(field "${outs2}" pool)"
  if printf '%s' "${sig_json2}" | grep -q '"protected_path":false' \
    && [[ "${sig_src2}" == "lane_writes" ]] \
    && [[ "${pools2}" == *"kimi:ok:"* ]]; then
    pass "(s2) ordinary path -> protected=false, kimi:ok: present (source=${sig_src2})"
  else
    fail "(s2) ordinary path -> kimi:ok:" "json=${sig_json2} src=${sig_src2} pool=${pools2}"
  fi

  # (s3) no patterns in any consulted yaml -> fail-closed protected=true. Canonical default
  # is pointed at a nonexistent path so BOTH lookups miss, exercising no_patterns_failclosed.
  LEADV2_CANONICAL_ROOT="${TMPDIR_BASE}/no-such-canonical" sig_call "${ROUTING_YAML_DEFAULT}" "agent/newmod.py"
  sig_json3="${SIG_JSON}" ; sig_src3="${SIG_SRC}"
  if printf '%s' "${sig_json3}" | grep -q '"protected_path":true' \
    && [[ "${sig_src3}" == "no_patterns_failclosed" ]]; then
    pass "(s3) no patterns anywhere -> fail-closed protected=true (source=${sig_src3})"
  else
    fail "(s3) no patterns -> fail-closed" "json=${sig_json3} src=${sig_src3}"
  fi

  # (s4) empty lane writes (scope unknown) -> fail-closed protected=true.
  sig_call "${ROUTING_YAML_SIG}" ""
  sig_json4="${SIG_JSON}" ; sig_src4="${SIG_SRC}"
  if printf '%s' "${sig_json4}" | grep -q '"protected_path":true' \
    && [[ "${sig_src4}" == "no_lane_writes_failclosed" ]]; then
    pass "(s4) empty lane writes -> fail-closed protected=true (source=${sig_src4})"
  else
    fail "(s4) empty lane writes -> fail-closed" "json=${sig_json4} src=${sig_src4}"
  fi
else
  fail "(s0) leadv2-review-signals.sh lib present" "missing ${SIGNALS_LIB}"
fi

printf -- '\n%d passed, %d failed\n' "${PASS}" "${FAIL}"
exit "${FAIL}"
