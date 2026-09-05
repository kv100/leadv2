#!/usr/bin/env bash
# N1-EMPTY-LANE-IS-NOT-A-PASS — falsifying harness for Design B.
# Asserts (1) the resolver rule glm_lock_busy_no_second_channel FIRES when the
# lock-busy signal is set (it was reachable only at classification time before);
# (2) a fake glm launcher exiting 75 + the LEADV2_DISPATCH_REFUSED: lock_busy
# marker is typed as an admission refusal; (3) end-to-end through dispatch-code,
# a glm lock-busy spawn re-resolves to sonnet with route_resolved naming the rule
# -- NOT the old "rule=none model=kimi"; (4) re-resolve happens at most once.
# New file (R5): the six named suites keep their exact counts.
# run-all-triggers: leadv2-dispatch-code
#
# SUITE-SELECTION-COVERS-140-OF-390-01: this suite carried no trigger
# marker and matched no name convention, so `run-all.sh --scope changed`
# never selected it — it could only ever run under `--scope all`. The
# triggers are the production files the suite's own body references most,
# with shared helpers excluded so a helper edit does not select everything.

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

SIG_BUSY='{"mission_kind":"","protected_path":false,"safety_touched":false,"subsystem_count":0,"needs_midflight_interaction":false,"ui_design_judgment":false,"glm_failure_count":0,"glm_lock_busy":true}'
SIG_IDLE='{"mission_kind":"","protected_path":false,"safety_touched":false,"subsystem_count":0,"needs_midflight_interaction":false,"ui_design_judgment":false,"glm_failure_count":0,"glm_lock_busy":false}'

write_routing() { # <path>  -- includes the prod-configured rule id
  local p="$1"
  mkdir -p "$(dirname "$p")"
  cat > "$p" <<'YAML'
router:
  glm_policy:
    sonnet_exceptions:
      - id: glm_lock_busy_no_second_channel
    opus_only_mission_kinds: []
    codex_fitting_mission_kinds: []
YAML
}

# ---- Case 1: resolver fires the rule with the signal set --------------------
case_resolver_fires() {
  local d rt
  d="$(mktemp -d)"; rt="${d}/repo"; mkdir -p "${rt}"
  write_routing "${rt}/.claude/ref/leadv2-routing.yaml"
  local idle busy
  idle="$(python3 "${RESOLVER}" --routing-yaml "${rt}/.claude/ref/leadv2-routing.yaml" --job build --base-arm glm --signals "${SIG_IDLE}" 2>/dev/null || true)"
  busy="$(python3 "${RESOLVER}" --routing-yaml "${rt}/.claude/ref/leadv2-routing.yaml" --job build --base-arm glm --signals "${SIG_BUSY}" 2>/dev/null || true)"
  if printf '%s\n' "${idle}" | grep -q '^arm=glm$'; then ok "idle: resolver picks glm (primary)"; else bad "idle: expected arm=glm (got: ${idle})"; fi
  if printf '%s\n' "${busy}" | grep -q '^arm=sonnet$' && printf '%s\n' "${busy}" | grep -q '^rule=glm_lock_busy_no_second_channel$'; then
    ok "busy: resolver fires glm_lock_busy_no_second_channel -> sonnet"
  else bad "busy: expected arm=sonnet rule=glm_lock_busy_no_second_channel (got: ${busy})"; fi
  rm -rf "${d}"
}

# ---- Case 2+3+4: end-to-end through dispatch-code ---------------------------
case_dispatch_reresolve() {
  local d root glm_bin sub journal
  d="$(mktemp -d)"; root="${d}/repo"; mkdir -p "${root}"
  write_routing "${root}/.claude/ref/leadv2-routing.yaml"
  # fake glm launcher: always refuses lock-busy (rc 75 + marker). Exits BEFORE
  # printing any run-id, so spawn_worker treats it as an admission refusal.
  glm_bin="${d}/glm-fake.sh"
  cat > "${glm_bin}" <<'SH'
#!/usr/bin/env bash
echo "another GLM run is active for this repo (lock: .lock-x, pid: 1)" >&2
echo "LEADV2_DISPATCH_REFUSED: lock_busy" >&2
exit 75
SH
  chmod +x "${glm_bin}"
  # sonnet subsession stub: pretends to spawn a worker and succeed.
  sub="${d}/subsession.sh"
  cat > "${sub}" <<'SH'
#!/usr/bin/env bash
nohup sleep 30 >/dev/null 2>&1 &
printf 'PID=%s LABEL=test SESSION_ID=test\n' "$!"
SH
  chmod +x "${sub}"
  journal="${d}/journal.log"
  printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$*" >> "%s"\n' "${journal}" > "${d}/journal.sh"
  chmod +x "${d}/journal.sh"
  local out rc
  out="$(CLAUDE_PROJECT_ROOT="${root}" LEADV2_PROJECT_ROOT="${root}" \
    LEADV2_DISPATCH_CACHE_DIR="${d}/cache" \
    LEADV2_DISPATCH_GLM_BIN="${glm_bin}" LEADV2_DISPATCH_SUBSESSION_BIN="${sub}" \
    LEADV2_DISPATCH_ARCHITECT_GATE=0 LEADV2_DISPATCH_E2E_GATE=0 LEADV2_DISPATCH_REVIEW_GATE=0 \
    LEADV2_REQUIRE_LANE_WRITES=0 LEADV2_ROUTER_V2=0 LEADV2_LANE_SHAPE=off \
    LEADV2_JOURNAL_BIN="${d}/journal.sh" \
    bash "${DC}" "lockbusy mission" --kind product 2>&1)"; rc=$?
  if printf '%s' "${out}" | grep -q 'route_resolved by=router.*model=sonnet.*rule=glm_lock_busy_no_second_channel'; then
    ok "route_resolved names sonnet + glm_lock_busy_no_second_channel"
  else bad "expected route_resolved model=sonnet rule=glm_lock_busy_no_second_channel (rc=${rc}, out: $(printf '%s' "${out}" | grep -E 'route_resolved|arm_reresolved|arm_refused|spawn_failed' | tail -3))"; fi
  # re-resolve happens at most once
  local n
  n="$(grep -c 'arm_reresolved by=router trigger=glm_lock_busy' "${journal}" 2>/dev/null || true)"
  [[ "${n}" =~ ^[0-9]+$ ]] || n=0
  if [[ "${n}" -le 1 ]]; then ok "re-resolve fires at most once (n=${n})"; else bad "re-resolve fired ${n} times (must be <=1)"; fi
  # the old blind-spill must NOT have produced a kimi route_resolved
  if printf '%s' "${out}" | grep -q 'route_resolved by=router.*model=kimi'; then
    bad "blind-spill to kimi still happens (model=kimi)"
  else ok "no blind-spill to kimi"; fi
  rm -rf "${d}"
}


# ---- Case 5: ARBITER-PICK-OVERRIDDEN-BY-ROUTER-01 ---------------------------
# The filed claim was "the router silently overrides the arbiter". A census over
# 345 dispatch logs carrying both lines refuted the "silently": 33 differing pairs,
# every one preceded by a named arm_refused/spawn_failed line, 0 silent. What
# survived is narrower: the TERMINAL line said nothing -- all 33 printed rule=none
# and 6 kept the arbiter's own reason=cheapest_capable for an arm that then LOST,
# so read alone that line is indistinguishable from a route nobody overrode. That
# is how the defect came to be filed in the first place.
# This case asserts the terminal line is self-sufficient: it names the pick that
# was displaced, that a ladder ran, how deep, and after what.
# The control is the point: a dispatch whose arm never moved must carry NO
# arm_source= token, or the assertion would pass on a line that always prints it.
case_terminal_line_names_the_fallback() {
  local d root glm_bin sub ok_bin out_fb out_ctl
  d="$(mktemp -d)"; root="${d}/repo"; mkdir -p "${root}"
  write_routing "${root}/.claude/ref/leadv2-routing.yaml"
  glm_bin="${d}/glm-fake.sh"
  cat > "${glm_bin}" <<'SH'
#!/usr/bin/env bash
echo "another GLM run is active for this repo (lock: .lock-x, pid: 1)" >&2
echo "LEADV2_DISPATCH_REFUSED: lock_busy" >&2
exit 75
SH
  # the control's glm launcher SUCCEEDS, so the arbiter's pick is what lands and
  # no rung of the ladder is burned.
  ok_bin="${d}/glm-ok.sh"
  cat > "${ok_bin}" <<'SH'
#!/usr/bin/env bash
nohup sleep 30 >/dev/null 2>&1 &
printf 'PID=%s LABEL=test SESSION_ID=test\n' "$!"
SH
  sub="${d}/subsession.sh"; cp "${ok_bin}" "${sub}"
  chmod +x "${glm_bin}" "${ok_bin}" "${sub}"
  printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$*" >> "%s"\n' "${d}/journal.log" > "${d}/journal.sh"
  chmod +x "${d}/journal.sh"
  _dc_run() { # <glm-bin>
    CLAUDE_PROJECT_ROOT="${root}" LEADV2_PROJECT_ROOT="${root}" \
      LEADV2_DISPATCH_CACHE_DIR="${d}/cache-$(basename "$1")" \
      LEADV2_DISPATCH_GLM_BIN="$1" LEADV2_DISPATCH_SUBSESSION_BIN="${sub}" \
      LEADV2_DISPATCH_ARCHITECT_GATE=0 LEADV2_DISPATCH_E2E_GATE=0 LEADV2_DISPATCH_REVIEW_GATE=0 \
      LEADV2_REQUIRE_LANE_WRITES=0 LEADV2_ROUTER_V2=0 LEADV2_LANE_SHAPE=off \
      LEADV2_JOURNAL_BIN="${d}/journal.sh" \
      bash "${DC}" "lockbusy mission" --kind product 2>&1
  }
  out_fb="$(_dc_run "${glm_bin}")"
  out_ctl="$(_dc_run "${ok_bin}")"
  if printf '%s' "${out_fb}" | grep -qE 'route_resolved by=router.*arbiter_pick=glm arm_source=ladder_fallback depth=[0-9]+ after=glm_refused_lock_busy'; then
    ok "terminal route line names the displaced pick, the ladder and what it followed"
  else bad "expected arm_source=ladder_fallback on the terminal line (got: $(printf '%s' "${out_fb}" | grep -E 'route_resolved by=router' | tail -1))"; fi
  if printf '%s' "${out_ctl}" | grep -q 'route_resolved by=router' \
     && ! printf '%s' "${out_ctl}" | grep -q 'arm_source='; then
    ok "a route nobody overrode carries no arm_source token (control)"
  else bad "control: unmoved route must NOT carry arm_source= (got: $(printf '%s' "${out_ctl}" | grep -E 'route_resolved by=router' | tail -1))"; fi
  rm -rf "${d}"
}

case_resolver_fires
case_dispatch_reresolve
case_terminal_line_names_the_fallback

printf '\n=== %d passed, %d failed ===\n' "${PASS}" "${FAIL}"
[[ "${FAIL}" == 0 ]]
