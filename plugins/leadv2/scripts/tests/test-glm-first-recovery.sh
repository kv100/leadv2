#!/usr/bin/env bash
# test-glm-first-recovery.sh — GLM-FIRST-RECOVERY-01
#
# The codex_fitting_mission_kind precedence row is a PREFERENCE, not an
# exclusion: when the codex_quota_gate spill walk fires, glm stays in the
# candidate chain. Before the fix the walk skipped base_arm unconditionally,
# so [glm, codex, sonnet] + codex-blocked left sonnet as the ONLY arm -- with
# codex's probe stuck on a 401 (reading unknown), every codex_fitting lane
# resolved sonnet forever (90 journal rows, 2026-08-15).
#
# Cases (design §5):
#   1  codex_fitting + codex unknown + glm ok/2%  -> arm=glm, readings carries
#      codex=unknown and glm=2%
#   2  codex_fitting + codex 91% + glm ok         -> arm=glm (recovery at peak)
#   3  codex_fitting + codex unknown + glm 95%    -> arm=sonnet (R2 guard)
#   4  codex_fitting + codex 44%                  -> arm=codex, gate silent
#   5  safety_gate + codex unknown                -> arm=sonnet (exclusion row
#      still excludes glm)
#   6  job=review, base codex, codex blocked      -> arm=sonnet, never glm (R8)
#   7  no codex_quota_gate in yaml                -> byte-identical v1 output
#   8  happy path (no rule fired)                 -> arm=glm rule=none, NO
#      readings line, no glm/anthropic subprocess (R3)
#   9  dispatch-code.sh emit: journal line carries readings= when present,
#      byte-identical arm_resolved line when absent
#
# Harness shape mirrors test-codex-quota-gate.sh (stubbed quota reader,
# deterministic readings) and test-lock-busy-reresolve.sh (real dispatch-code.sh
# run with stub journal, gates off, --no-spawn).
set -uo pipefail

# BURN-GOVERNOR-01: the burn gate defaults ON and reads the host's real
# ~/.claude/burn/history.db -- a hot host would red this suite on `exit 6`.
export LEADV2_BURN_GOVERNOR=0
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RESOLVER="${SCRIPT_DIR}/lib/leadv2-glm-policy-resolve.py"
DC="${SCRIPT_DIR}/leadv2-dispatch-code.sh"

PASS=0; FAIL=0
ok()  { printf '[TEST] PASS: %s\n' "$1"; PASS=$((PASS+1)); }
bad() { printf '[TEST] FAIL: %s\n' "$1"; FAIL=$((FAIL+1)); }

BASE="$(mktemp -d)"
trap 'rm -rf "$BASE"' EXIT

# ── stub quota-live: per-provider canned JSON + a call log (for R3) ─────────
STUB="${BASE}/quota-live.sh"
STUB_LOG="${BASE}/calls.log"
mkdir -p "${BASE}/readings"
cat > "${STUB}" <<SH
#!/usr/bin/env bash
printf '%s\n' "\$1" >> "${STUB_LOG}"
cat "${BASE}/readings/\$1.json" 2>/dev/null || printf '{"status":"unknown"}'
SH
chmod +x "${STUB}"

reading() { # <provider> <json>
  printf '%s' "$2" > "${BASE}/readings/$1.json"
}
GLM_OK='{"status":"ok","five_hour":{"pct":2},"weekly":{"pct":2}}'
GLM_HOT='{"status":"ok","five_hour":{"pct":95},"weekly":{"pct":40}}'
CODEX_UNKNOWN='{"provider":"codex","status":"unknown","error":"refresh http 401","needs_login":true}'
CODEX_91='{"status":"ok","windows":[{"kind":"primary","used_percent":91}],"binding_window":"primary"}'
CODEX_96='{"status":"ok","windows":[{"kind":"primary","used_percent":96}],"binding_window":"primary"}'
CODEX_44='{"status":"ok","windows":[{"kind":"primary","used_percent":44}],"binding_window":"primary"}'
ANTHROPIC_44='{"status":"ok","accounts":[{"account_label":"max","active":true,"five_hour_pct":44,"seven_day_pct":12}]}'

# ── routing fixtures ─────────────────────────────────────────────────────────
RT_GATE="${BASE}/routing-gate.yaml"
cat > "${RT_GATE}" <<'YAML'
router:
  glm_policy:
    sonnet_exceptions:
      - id: safety_gate_publish_payments
      - id: glm_lock_busy_no_second_channel
    opus_only_mission_kinds: []
    codex_fitting_mission_kinds: [doc_fix]
    codex_quota_gate:
      build_threshold_pct: 80.0
      review_threshold_pct: 95.0
      build_spill_order: [glm, codex, sonnet]
      review_arm_exclusions: [glm]
YAML
RT_NOGATE="${BASE}/routing-nogate.yaml"
cat > "${RT_NOGATE}" <<'YAML'
router:
  glm_policy:
    sonnet_exceptions:
      - id: safety_gate_publish_payments
    opus_only_mission_kinds: []
    codex_fitting_mission_kinds: [doc_fix]
YAML

SIG_DOC_FIX='{"mission_kind":"doc_fix","protected_path":false,"safety_touched":false,"subsystem_count":0,"needs_midflight_interaction":false,"ui_design_judgment":false,"glm_failure_count":0,"glm_lock_busy":false}'
SIG_SAFETY='{"mission_kind":"doc_fix","protected_path":false,"safety_touched":true,"subsystem_count":0,"needs_midflight_interaction":false,"ui_design_judgment":false,"glm_failure_count":0,"glm_lock_busy":false}'
SIG_IDLE='{"mission_kind":"cleanup","protected_path":false,"safety_touched":false,"subsystem_count":0,"needs_midflight_interaction":false,"ui_design_judgment":false,"glm_failure_count":0,"glm_lock_busy":false}'

resolve() { # <yaml> <signals> <job> <base-arm>
  : > "${STUB_LOG}"
  python3 "${RESOLVER}" --routing-yaml "$1" --job "$3" --base-arm "$4" \
    --signals "$2" --quota-live "${STUB}" 2>/dev/null
}

# ---- Case 1: the headline fix -- stuck 401 recovers to glm ------------------
case1() {
  reading glm "${GLM_OK}"; reading codex "${CODEX_UNKNOWN}"; reading anthropic "${ANTHROPIC_44}"
  local out
  out="$(resolve "${RT_GATE}" "${SIG_DOC_FIX}" build glm)"
  if printf '%s\n' "${out}" | grep -q '^arm=glm$' \
     && printf '%s\n' "${out}" | grep -q '^rule=codex_quota_gate_80pct$'; then
    ok "1: codex unknown + glm ok -> arm=glm, rule=codex_quota_gate_80pct"
  else bad "1: expected arm=glm rule=codex_quota_gate_80pct (got: ${out})"; fi
  local rd
  rd="$(printf '%s\n' "${out}" | sed -n 's/^readings=//p')"
  if [[ "${rd}" == "glm=2% codex=unknown anthropic=44%" ]]; then
    ok "1: readings names codex=unknown alongside glm=2% ('${rd}')"
  else bad "1: readings mismatch (got: '${rd}')"; fi
}

# ---- Case 2: real peak (codex 91%) still recovers to glm --------------------
case2() {
  reading glm "${GLM_OK}"; reading codex "${CODEX_91}"; reading anthropic "${ANTHROPIC_44}"
  local out
  out="$(resolve "${RT_GATE}" "${SIG_DOC_FIX}" build glm)"
  if printf '%s\n' "${out}" | grep -q '^arm=glm$' \
     && printf '%s\n' "${out}" | grep -q '^rule=codex_quota_gate_80pct$' \
     && printf '%s\n' "${out}" | grep -q '^readings=.*codex=91%'; then
    ok "2: codex 91% + glm ok -> arm=glm (recovery case at peak)"
  else bad "2: expected arm=glm with codex=91% readings (got: ${out})"; fi
}

# ---- Case 3: a known-hot glm steps aside (R2) --------------------------------
case3() {
  reading glm "${GLM_HOT}"; reading codex "${CODEX_UNKNOWN}"; reading anthropic "${ANTHROPIC_44}"
  local out
  out="$(resolve "${RT_GATE}" "${SIG_DOC_FIX}" build glm)"
  if printf '%s\n' "${out}" | grep -q '^arm=sonnet$'; then
    ok "3: glm 95% known-hot -> arm=sonnet (R2 guard holds)"
  else bad "3: expected arm=sonnet (got: ${out})"; fi
}

# ---- Case 4: gate silent below threshold -------------------------------------
case4() {
  reading glm "${GLM_OK}"; reading codex "${CODEX_44}"; reading anthropic "${ANTHROPIC_44}"
  local out
  out="$(resolve "${RT_GATE}" "${SIG_DOC_FIX}" build glm)"
  if printf '%s\n' "${out}" | grep -q '^arm=codex$' \
     && printf '%s\n' "${out}" | grep -q '^rule=codex_fitting_kind$' \
     && ! printf '%s\n' "${out}" | grep -q '^readings='; then
    ok "4: codex 44% -> arm=codex, gate does not fire, no readings line"
  else bad "4: expected arm=codex rule=codex_fitting_kind, no readings (got: ${out})"; fi
}

# ---- Case 5: exclusion rows still exclude glm --------------------------------
case5() {
  reading glm "${GLM_OK}"; reading codex "${CODEX_UNKNOWN}"; reading anthropic "${ANTHROPIC_44}"
  local out
  out="$(resolve "${RT_GATE}" "${SIG_SAFETY}" build glm)"
  if printf '%s\n' "${out}" | grep -q '^arm=sonnet$' \
     && printf '%s\n' "${out}" | grep -q '^rule=safety_gate_publish_payments$'; then
    ok "5: safety row + codex unknown -> arm=sonnet (glm still excluded)"
  else bad "5: expected arm=sonnet rule=safety_gate_publish_payments (got: ${out})"; fi
}

# ---- Case 6: review never resolves glm (R8) ----------------------------------
case6() {
  reading glm "${GLM_OK}"; reading codex "${CODEX_96}"; reading anthropic "${ANTHROPIC_44}"
  local out
  out="$(resolve "${RT_GATE}" "${SIG_IDLE}" review codex)"
  if printf '%s\n' "${out}" | grep -q '^arm=sonnet$' \
     && ! printf '%s\n' "${out}" | grep -q '^arm=glm$'; then
    ok "6: job=review base=codex blocked -> arm=sonnet, never glm"
  else bad "6: expected arm=sonnet (got: ${out})"; fi
}

# ---- Case 7: gate absent -> byte-identical v1 output -------------------------
case7() {
  reading glm "${GLM_OK}"; reading codex "${CODEX_UNKNOWN}"; reading anthropic "${ANTHROPIC_44}"
  local out expected
  out="$(resolve "${RT_NOGATE}" "${SIG_DOC_FIX}" build glm)"
  expected='arm=codex
rule=codex_fitting_kind
reason=codex_fitting_mission_kind
tier=standard
codex_quota_blocked=0'
  if [[ "${out}" == "${expected}" ]]; then
    ok "7: no codex_quota_gate block -> output byte-identical to v1"
  else bad "7: v1 output drifted (got: $(printf '%q' "${out}"))"; fi
}

# ---- Case 8: happy path pays nothing (R3) ------------------------------------
case8() {
  reading glm "${GLM_OK}"; reading codex "${CODEX_44}"; reading anthropic "${ANTHROPIC_44}"
  local out n_glm n_ant
  out="$(resolve "${RT_GATE}" "${SIG_IDLE}" build glm)"
  n_glm="$(grep -c '^glm$' "${STUB_LOG}" 2>/dev/null || true)"; [[ "${n_glm}" =~ ^[0-9]+$ ]] || n_glm=0
  n_ant="$(grep -c '^anthropic$' "${STUB_LOG}" 2>/dev/null || true)"; [[ "${n_ant}" =~ ^[0-9]+$ ]] || n_ant=0
  if printf '%s\n' "${out}" | grep -q '^arm=glm$' \
     && printf '%s\n' "${out}" | grep -q '^rule=none$' \
     && ! printf '%s\n' "${out}" | grep -q '^readings=' \
     && [[ "${n_glm}" == 0 && "${n_ant}" == 0 ]]; then
    ok "8: happy path -> arm=glm rule=none, no readings line, no glm/anthropic subprocess"
  else bad "8: happy path leaked cost or readings (out: ${out}; glm=${n_glm} anthropic=${n_ant})"; fi
}

# ---- Case 9: dispatch-code.sh journal emit carries readings= ------------------
# End-to-end through the real leadv2-dispatch-code.sh: --no-spawn so no worker
# launches, stub journal captures every `emit decision` line verbatim, gates off
# (same envelope as test-lock-busy-reresolve.sh).
run_dispatch() { # <repo-root> <mission>
  CLAUDE_PROJECT_ROOT="$1" LEADV2_PROJECT_ROOT="$1" \
    LEADV2_DISPATCH_CACHE_DIR="${BASE}/cache" \
    LEADV2_DISPATCH_ARCHITECT_GATE=0 LEADV2_DISPATCH_E2E_GATE=0 LEADV2_DISPATCH_REVIEW_GATE=0 \
    LEADV2_REQUIRE_LANE_WRITES=0 LEADV2_ROUTER_V2=0 LEADV2_LANE_SHAPE=off \
    LEADV2_JOURNAL_BIN="${BASE}/journal.sh" \
    GLM_POLICY_QUOTA_LIVE="${STUB}" \
    bash "${DC}" "$2" --kind doc_fix --no-spawn 2>&1
}

case9() {
  local root journal
  root="${BASE}/repo"; mkdir -p "${root}/.claude/ref"
  cp "${RT_GATE}" "${root}/.claude/ref/leadv2-routing.yaml"
  journal="${BASE}/journal.log"
  printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$*" >> "%s"\n' "${journal}" > "${BASE}/journal.sh"
  chmod +x "${BASE}/journal.sh"

  # present: degraded path -> arm=glm + readings in the journal line
  reading glm "${GLM_OK}"; reading codex "${CODEX_UNKNOWN}"; reading anthropic "${ANTHROPIC_44}"
  : > "${journal}"
  run_dispatch "${root}" "glm-first recovery journal probe alpha" >/dev/null 2>&1 || true
  if grep -q 'arm_resolved job=build arm=glm reason=codex_quota_gate_80pct readings=glm=2% codex=unknown anthropic=44%' "${journal}"; then
    ok "9: journal line carries arm=glm + readings (codex=unknown visible)"
  else bad "9: expected readings-carrying arm_resolved line (journal: $(grep arm_resolved "${journal}" 2>/dev/null | tail -1))"; fi

  # absent: gate not fired -> byte-identical arm_resolved line
  reading codex "${CODEX_44}"
  : > "${journal}"
  run_dispatch "${root}" "glm-first recovery journal probe beta" >/dev/null 2>&1 || true
  if grep -q 'decision arm_resolved job=build arm=codex reason=codex_fitting_kind$' "${journal}" \
     && ! grep -q 'arm_resolved.*readings=' "${journal}"; then
    ok "9: absent readings -> arm_resolved line byte-identical to today"
  else bad "9: unexpected emit for the non-degraded path (journal: $(grep arm_resolved "${journal}" 2>/dev/null | tail -1))"; fi
}

case1; case2; case3; case4; case5; case6; case7; case8; case9

printf '\n=== %d passed, %d failed ===\n' "${PASS}" "${FAIL}"
[[ "${FAIL}" == 0 ]]
