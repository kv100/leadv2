#!/usr/bin/env bash
# Offline RED→GREEN suite for PROVIDER-LOCKOUT-FALSE-BLOCK-01.
#
# Root cause (2026-08-17 05:49Z): a killed GLM worker whose 60-line tail still
# carried one earlier, SURVIVED `429 rate limit` retry line was classified
# quota-shaped by _quota_shaped, and whatever reset time quota-error-parse.py
# scraped out of that tail became the lockout duration — 24h to the second,
# clamped only by --max-minutes (4320). One dead spawn benched the primary
# code writer for a working day, silently.
#
# This suite proves the fix:
#   T1  killed worker + an earlier 429 line  -> class=worker_killed, <=60m
#   T2  fresh quota refusal at the LAUNCHER-refusal site still blocks, hours-scale
#       preserved (site-dependent cap: 4320 there, 60 at postspawn)
#   T3  post-spawn quota refusal stating "resets in 24 hours" -> clamped to 60m
#   T4  expired record does not block — BOTH read paths (_provider_available via a
#       full dispatch, and the python resolver --review-pool) [regression lock F4/F5]
#   T5  malformed record does not block — both read paths [regression lock]
#   T6  ordinary non-quota build failure -> NO record + arm_failure_classified lockout=none
#   T7  a live lockout on the ladder's first dispatchable provider renders the
#       "PRIMARY ARM BENCHED" stderr banner BEFORE any route line
#   T8  strikes escalation: re-lock doubles minutes (capped at the class cap)
#
# Hermeticity follows test-quota-lockout-postspawn.sh: fake launchers, per-scenario
# LEADV2_QUOTA_LOCKOUT_DIR / LEADV2_DISPATCH_CACHE_DIR under TMP_ROOT — the real
# ~/.claude/cache/dispatch-ledger/ is NEVER touched.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DISPATCH_BIN="${SCRIPT_DIR}/../leadv2-dispatch-code.sh"
RESOLVER="${SCRIPT_DIR}/../lib/leadv2-glm-policy-resolve.py"
CANONICAL_ROUTING_YAML="${SCRIPT_DIR}/../../config/leadv2-routing.yaml"
TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "${TMP_ROOT}"' EXIT
FAIL=0

pass() { printf 'PASS: %s\n' "$1"; }
fail() { printf 'FAIL: %s -- %s\n' "$1" "$2"; FAIL=1; }

if bash -n "${DISPATCH_BIN}"; then pass "bash -n clean (leadv2-dispatch-code.sh)"; else fail "bash -n" "dispatch-code.sh"; fi
if python3 -m py_compile "${RESOLVER}" "${SCRIPT_DIR}/../lib/leadv2-lockout-classify.py"; then
  pass "py_compile clean (resolver + lockout-classify)"
else
  fail "py_compile" "resolver/lockout-classify"
fi

# Poison fence: any provider bin defaults to a loud failure; tests override.
for _arm in glm kimi codex sonnet; do
  _poison="${TMP_ROOT}/poison-${_arm}.sh"
  printf '#!/usr/bin/env bash\nprintf "POISON: real provider spawn attempted\\n" >&2\nexit 99\n' > "${_poison}"
  chmod +x "${_poison}"
done
export LEADV2_DISPATCH_GLM_BIN="${TMP_ROOT}/poison-glm.sh"
export LEADV2_DISPATCH_KIMI_BIN="${TMP_ROOT}/poison-kimi.sh"
export LEADV2_DISPATCH_CODEX_BIN="${TMP_ROOT}/poison-codex.sh"
export LEADV2_DISPATCH_SUBSESSION_BIN="${TMP_ROOT}/poison-sonnet.sh"
export LEADV2_ARM_EARLY_VERDICT_S=3
export LEADV2_ARM_EARLY_VERDICT_POLL_S=0.2

make_root() {
  local root="$1"
  mkdir -p "${root}/.claude/ref" "${root}/docs/leadv2/.bus-offsets" "${root}/docs/leadv2/tasks"
  cat > "${root}/.claude/ref/leadv2-routing.yaml" <<'YAML'
  glm_policy:
    sonnet_exceptions:
      - id: safety_gate_publish_payments
YAML
}

# glm launcher that REFUSES pre-spawn with a quota reason + a provider-stated
# relative reset ("resets in 20 hours") — the launcher_refusal site.
make_refusing_glm() {
  local path="$1"
  cat > "${path}" <<'SH'
#!/usr/bin/env bash
echo '[glm-quota-gate] LEADV2_DISPATCH_REFUSED: quota_gate' >&2
echo '[glm-quota-gate] usage limit reached; resets in 20 hours.' >&2
exit 1
SH
  chmod +x "${path}"
}

# codex-task.sh stand-in: enqueue rc0, status=failed, log prints the chosen tail.
make_dying_codex() {  # <path> <final_output_text>
  local path="$1" text="$2"
  cat > "${path}" <<EOF
#!/usr/bin/env bash
case "\${1:-}" in
  task)
    echo 'task-fake-lockout01 started in the background as task-fake-lockout01.'
    ;;
  status)
    echo 'status: failed'
    ;;
  log)
    cat <<'TXT'
${text}
TXT
    ;;
  *) exit 2 ;;
esac
EOF
  chmod +x "${path}"
}

make_live_sonnet() {
  local path="$1"
  cat > "${path}" <<'SH'
#!/usr/bin/env bash
set -uo pipefail
nohup sleep 0.3 >/dev/null 2>&1 &
pid=$!
disown
printf 'PID=%s LABEL=fake-lane SESSION_ID=fake-session\n' "${pid}"
exit 0
SH
  chmod +x "${path}"
}

# Fake quota-live whose codex bucket reads a KNOWN-low 5% (so the codex gate
# cannot fire quota_read_unknown and muddy the lockout assertions).
make_low_quota_live() {
  local path="$1"
  cat > "${path}" <<'SH'
#!/usr/bin/env bash
printf '{"status":"ok","windows":[{"kind":"weekly","used_percent":5}]}\n'
exit 0
SH
  chmod +x "${path}"
}

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

# ── T1: killed worker + an earlier survived 429 line -> worker_killed, <=60m ────────
# RED today: _quota_shaped matches the 429 line first, provider time (~24h past-
# guarded or default) becomes the duration. GREEN: transient classes outrank quota.
make_root "${TMP_ROOT}/t1-root"
make_refusing_glm "${TMP_ROOT}/t1-glm.sh"
make_dying_codex "${TMP_ROOT}/t1-codex.sh" "HTTP 429 too many requests, retry 1 of 3 succeeded
worker ran for 4 minutes
Killed
signal 9"
t1_out="$(CLAUDE_PROJECT_ROOT="${TMP_ROOT}/t1-root" \
  LEADV2_DISPATCH_CACHE_DIR="${TMP_ROOT}/t1-cache" \
  LEADV2_QUOTA_LOCKOUT_DIR="${TMP_ROOT}/t1-lockout" \
  LEADV2_DISPATCH_GLM_BIN="${TMP_ROOT}/t1-glm.sh" \
  LEADV2_DISPATCH_CODEX_BIN="${TMP_ROOT}/t1-codex.sh" \
  LEADV2_DISPATCH_SUBSESSION_BIN="${TMP_ROOT}/poison-sonnet.sh" \
  LEADV2_DISPATCH_ARCHITECT_GATE=0 \
  bash "${DISPATCH_BIN}" 'plugin-only killed worker with earlier 429 t1' 2>&1)"
t1_lockfile="${TMP_ROOT}/t1-lockout/quota-lockout-codex.json"
t1_ok=0
if [[ -f "${t1_lockfile}" ]]; then
  t1_ok="$(python3 - "${t1_lockfile}" <<'PY'
import json, sys, time
try:
    d = json.load(open(sys.argv[1]))
    epoch = int(d.get("locked_until_epoch") or 0)
    cls = d.get("class", "")
except Exception:
    print(0); sys.exit(0)
delta_min = (epoch - time.time()) / 60.0
print(1 if (cls == "worker_killed" and 0 < delta_min <= 60) else 0)
PY
)"
fi
if [[ "${t1_ok}" == "1" ]] \
  && grep -q 'quota_lockout_recorded provider=codex arm=codex reason=postspawn_worker_killed class=worker_killed' <<<"${t1_out}"; then
  pass 'T1: killed worker (tail carries an earlier 429) -> class=worker_killed, <=60m'
else
  fail 'T1: killed-worker class + duration' "lockfile=$(cat "${t1_lockfile}" 2>/dev/null || echo MISSING) output=${t1_out}"
fi

# ── T2: fresh launcher-refusal quota -> still blocks, hours-scale preserved ─────────
make_root "${TMP_ROOT}/t2-root"
make_refusing_glm "${TMP_ROOT}/t2-glm.sh"
make_live_sonnet "${TMP_ROOT}/t2-sonnet.sh"
t2_out="$(CLAUDE_PROJECT_ROOT="${TMP_ROOT}/t2-root" \
  LEADV2_DISPATCH_CACHE_DIR="${TMP_ROOT}/t2-cache" \
  LEADV2_QUOTA_LOCKOUT_DIR="${TMP_ROOT}/t2-lockout" \
  LEADV2_DISPATCH_GLM_BIN="${TMP_ROOT}/t2-glm.sh" \
  LEADV2_DISPATCH_CODEX_BIN="${TMP_ROOT}/poison-codex.sh" \
  LEADV2_DISPATCH_SUBSESSION_BIN="${TMP_ROOT}/t2-sonnet.sh" \
  LEADV2_DISPATCH_ARCHITECT_GATE=0 \
  bash "${DISPATCH_BIN}" 'plugin-only launcher refusal hours-scale t2' 2>&1)"
t2_lockfile="${TMP_ROOT}/t2-lockout/quota-lockout-glm.json"
t2_ok=0
if [[ -f "${t2_lockfile}" ]]; then
  t2_ok="$(python3 - "${t2_lockfile}" <<'PY'
import json, sys, time
try:
    d = json.load(open(sys.argv[1]))
    epoch = int(d.get("locked_until_epoch") or 0)
    cls = d.get("class", "")
except Exception:
    print(0); sys.exit(0)
delta_min = (epoch - time.time()) / 60.0
# provider said "resets in 20 hours"; launcher_refusal cap stays 4320 -> NOT clamped
print(1 if (cls == "provider_refusal" and 19 * 60 <= delta_min <= 21 * 60) else 0)
PY
)"
fi
if [[ "${t2_ok}" == "1" ]]; then
  pass 'T2: launcher-refusal quota still blocks, provider hours-scale preserved (~20h, not clamped to 60m)'
else
  fail 'T2: launcher-refusal hours-scale' "lockfile=$(cat "${t2_lockfile}" 2>/dev/null || echo MISSING) output=${t2_out}"
fi

# ── T3: post-spawn quota refusal stating "resets in 24 hours" -> clamped to 60m ────
make_root "${TMP_ROOT}/t3-root"
make_refusing_glm "${TMP_ROOT}/t3-glm.sh"
make_dying_codex "${TMP_ROOT}/t3-codex.sh" "You've hit your usage limit; resets in 24 hours."
t3_out="$(CLAUDE_PROJECT_ROOT="${TMP_ROOT}/t3-root" \
  LEADV2_DISPATCH_CACHE_DIR="${TMP_ROOT}/t3-cache" \
  LEADV2_QUOTA_LOCKOUT_DIR="${TMP_ROOT}/t3-lockout" \
  LEADV2_DISPATCH_GLM_BIN="${TMP_ROOT}/t3-glm.sh" \
  LEADV2_DISPATCH_CODEX_BIN="${TMP_ROOT}/t3-codex.sh" \
  LEADV2_DISPATCH_SUBSESSION_BIN="${TMP_ROOT}/poison-sonnet.sh" \
  LEADV2_DISPATCH_ARCHITECT_GATE=0 \
  bash "${DISPATCH_BIN}" 'plugin-only postspawn 24h refusal clamped t3' 2>&1)"
t3_lockfile="${TMP_ROOT}/t3-lockout/quota-lockout-codex.json"
t3_ok=0
if [[ -f "${t3_lockfile}" ]]; then
  t3_ok="$(python3 - "${t3_lockfile}" <<'PY'
import json, sys, time
try:
    d = json.load(open(sys.argv[1]))
    epoch = int(d.get("locked_until_epoch") or 0)
    cls = d.get("class", "")
except Exception:
    print(0); sys.exit(0)
delta_min = (epoch - time.time()) / 60.0
print(1 if (cls == "provider_refusal" and 58 <= delta_min <= 62) else 0)
PY
)"
fi
if [[ "${t3_ok}" == "1" ]] && grep -q 'class=provider_refusal' <<<"${t3_out}" \
  && grep -q 'source=provider_time_clamped_postspawn' <<<"${t3_out}"; then
  pass 'T3: post-spawn "resets in 24 hours" clamped to the 60m post-spawn cap'
else
  fail 'T3: post-spawn cap clamp' "lockfile=$(cat "${t3_lockfile}" 2>/dev/null || echo MISSING) output=${t3_out}"
fi

# ── T4: EXPIRED record does not block — BOTH read paths [regression lock] ──────────
# Bash path: an expired glm lockout must NOT precheck-skip glm (glm then refuses
# on its own launcher text, spilling to sonnet — proving glm survived the filter).
make_root "${TMP_ROOT}/t4-root"
make_refusing_glm "${TMP_ROOT}/t4-glm.sh"
make_live_sonnet "${TMP_ROOT}/t4-sonnet.sh"
mkdir -p "${TMP_ROOT}/t4-lockout"
_exp_epoch=$(( $(date +%s) - 3600 ))
cat > "${TMP_ROOT}/t4-lockout/quota-lockout-glm.json" <<JSON
{"provider": "glm", "locked_until": "past", "locked_until_epoch": ${_exp_epoch}, "source": "test-seed", "class": "worker_killed", "strikes": 1}
JSON
t4_out="$(CLAUDE_PROJECT_ROOT="${TMP_ROOT}/t4-root" \
  LEADV2_DISPATCH_CACHE_DIR="${TMP_ROOT}/t4-cache" \
  LEADV2_QUOTA_LOCKOUT_DIR="${TMP_ROOT}/t4-lockout" \
  LEADV2_DISPATCH_GLM_BIN="${TMP_ROOT}/t4-glm.sh" \
  LEADV2_DISPATCH_CODEX_BIN="${TMP_ROOT}/poison-codex.sh" \
  LEADV2_DISPATCH_SUBSESSION_BIN="${TMP_ROOT}/t4-sonnet.sh" \
  LEADV2_DISPATCH_ARCHITECT_GATE=0 \
  bash "${DISPATCH_BIN}" 'plugin-only expired lockout glm survives t4' 2>&1)"
t4_rc=$?
if [[ ${t4_rc} -eq 0 ]] \
  && ! grep -q 'quota_precheck_skip model=glm' <<<"${t4_out}" \
  && grep -q 'worker_spawned by=router model=sonnet' <<<"${t4_out}"; then
  pass 'T4a: expired glm record — glm survives the bash precheck (_provider_available)'
else
  fail 'T4a: expired record, bash path' "rc=${t4_rc} output=${t4_out}"
fi
# Python path: resolver --review-pool with a frozen now — expired codex record,
# KNOWN-low codex pct -> codex not lockout-blocked, codex_quota_blocked=0.
NOW_EPOCH=2000000000
mkdir -p "${TMP_ROOT}/t4-lockout-py"
_exp2=$(( NOW_EPOCH - 3600 ))
cat > "${TMP_ROOT}/t4-lockout-py/quota-lockout-codex.json" <<JSON
{"provider": "codex", "locked_until": "past", "locked_until_epoch": ${_exp2}, "source": "test-seed"}
JSON
make_low_quota_live "${TMP_ROOT}/t4-quota-live.sh"
make_fake_kimi_fail "${TMP_ROOT}/t4-kimi.sh"
t4_py_out="$(LEADV2_QUOTA_LOCKOUT_DIR="${TMP_ROOT}/t4-lockout-py" \
  LEADV2_QUOTA_NOW_EPOCH="${NOW_EPOCH}" \
  python3 "${RESOLVER}" --routing-yaml "${CANONICAL_ROUTING_YAML}" --job review \
    --base-arm codex --review-pool --author sonnet \
    --quota-live "${TMP_ROOT}/t4-quota-live.sh" --kimi-bin "${TMP_ROOT}/t4-kimi.sh" 2>&1)"
t4_blocked="$(sed -n 's/^codex_quota_blocked=//p' <<<"${t4_py_out}" | head -1)"
t4_pool="$(sed -n 's/^pool=//p' <<<"${t4_py_out}" | head -1)"
if [[ "${t4_blocked}" == "0" ]] && [[ "${t4_pool}" != *"codex:blocked:lockout"* ]]; then
  pass 'T4b: expired codex record — resolver (_lockout_blocked) does not block codex'
else
  fail 'T4b: expired record, python path' "blocked=${t4_blocked} pool=${t4_pool} out=${t4_py_out}"
fi

# ── T5: MALFORMED record does not block — both paths [regression lock] ─────────────
make_root "${TMP_ROOT}/t5-root"
make_refusing_glm "${TMP_ROOT}/t5-glm.sh"
make_live_sonnet "${TMP_ROOT}/t5-sonnet.sh"
mkdir -p "${TMP_ROOT}/t5-lockout"
printf '{"locked_until_epoch": "banana"' > "${TMP_ROOT}/t5-lockout/quota-lockout-glm.json"
t5_out="$(CLAUDE_PROJECT_ROOT="${TMP_ROOT}/t5-root" \
  LEADV2_DISPATCH_CACHE_DIR="${TMP_ROOT}/t5-cache" \
  LEADV2_QUOTA_LOCKOUT_DIR="${TMP_ROOT}/t5-lockout" \
  LEADV2_DISPATCH_GLM_BIN="${TMP_ROOT}/t5-glm.sh" \
  LEADV2_DISPATCH_CODEX_BIN="${TMP_ROOT}/poison-codex.sh" \
  LEADV2_DISPATCH_SUBSESSION_BIN="${TMP_ROOT}/t5-sonnet.sh" \
  LEADV2_DISPATCH_ARCHITECT_GATE=0 \
  bash "${DISPATCH_BIN}" 'plugin-only malformed lockout glm survives t5' 2>&1)"
t5_rc=$?
if [[ ${t5_rc} -eq 0 ]] \
  && ! grep -q 'quota_precheck_skip model=glm' <<<"${t5_out}" \
  && grep -q 'worker_spawned by=router model=sonnet' <<<"${t5_out}"; then
  pass 'T5a: malformed glm record — glm survives the bash precheck, no crash'
else
  fail 'T5a: malformed record, bash path' "rc=${t5_rc} output=${t5_out}"
fi
mkdir -p "${TMP_ROOT}/t5-lockout-py"
printf '{"locked_until_epoch": "banana"' > "${TMP_ROOT}/t5-lockout-py/quota-lockout-codex.json"
t5_py_out="$(LEADV2_QUOTA_LOCKOUT_DIR="${TMP_ROOT}/t5-lockout-py" \
  LEADV2_QUOTA_NOW_EPOCH="${NOW_EPOCH}" \
  python3 "${RESOLVER}" --routing-yaml "${CANONICAL_ROUTING_YAML}" --job review \
    --base-arm codex --review-pool --author sonnet \
    --quota-live "${TMP_ROOT}/t4-quota-live.sh" --kimi-bin "${TMP_ROOT}/t4-kimi.sh" 2>&1)"
t5_rc_py=$?
t5_pool="$(sed -n 's/^pool=//p' <<<"${t5_py_out}" | head -1)"
if [[ ${t5_rc_py} -eq 0 ]] && [[ -n "${t5_pool}" ]] && [[ "${t5_pool}" != *"codex:blocked:lockout"* ]]; then
  pass 'T5b: malformed codex record — resolver exits 0, codex not lockout-blocked'
else
  fail 'T5b: malformed record, python path' "rc=${t5_rc_py} pool=${t5_pool} out=${t5_py_out}"
fi

# ── T6: ordinary non-quota failure -> NO record + arm_failure_classified lockout=none ──
make_root "${TMP_ROOT}/t6-root"
make_refusing_glm "${TMP_ROOT}/t6-glm.sh"
make_dying_codex "${TMP_ROOT}/t6-codex.sh" "FAILED tests/test_foo.py::test_bar — AssertionError"
t6_out="$(CLAUDE_PROJECT_ROOT="${TMP_ROOT}/t6-root" \
  LEADV2_DISPATCH_CACHE_DIR="${TMP_ROOT}/t6-cache" \
  LEADV2_QUOTA_LOCKOUT_DIR="${TMP_ROOT}/t6-lockout" \
  LEADV2_DISPATCH_GLM_BIN="${TMP_ROOT}/t6-glm.sh" \
  LEADV2_DISPATCH_CODEX_BIN="${TMP_ROOT}/t6-codex.sh" \
  LEADV2_DISPATCH_SUBSESSION_BIN="${TMP_ROOT}/poison-sonnet.sh" \
  LEADV2_DISPATCH_ARCHITECT_GATE=0 \
  bash "${DISPATCH_BIN}" 'plugin-only ordinary build failure no lockout t6' 2>&1)"
t6_lockfile="${TMP_ROOT}/t6-lockout/quota-lockout-codex.json"
if [[ ! -f "${t6_lockfile}" ]] \
  && grep -q 'arm_failure_classified arm=codex site=postspawn class=unclassified evidence=none lockout=none' <<<"${t6_out}"; then
  pass 'T6: ordinary build failure — no lockout record, arm_failure_classified lockout=none journaled'
else
  fail 'T6: ordinary failure must not lock out' "lockfile_exists=$([[ -f ${t6_lockfile} ]] && echo yes || echo no) output=${t6_out}"
fi

# ── T7: bench banner on stderr BEFORE any route line ───────────────────────────────
make_root "${TMP_ROOT}/t7-root"
make_live_sonnet "${TMP_ROOT}/t7-sonnet.sh"
mkdir -p "${TMP_ROOT}/t7-lockout"
_fut_epoch=$(( $(date +%s) + 45 * 60 ))
_fut_iso="$(date -u -r "${_fut_epoch}" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -d "@${_fut_epoch}" +%Y-%m-%dT%H:%M:%SZ)"
cat > "${TMP_ROOT}/t7-lockout/quota-lockout-glm.json" <<JSON
{"provider": "glm", "locked_until": "${_fut_iso}", "locked_until_epoch": ${_fut_epoch}, "source": "postspawn_failure:glm", "class": "worker_killed", "strikes": 1}
JSON
t7_out="$(CLAUDE_PROJECT_ROOT="${TMP_ROOT}/t7-root" \
  LEADV2_DISPATCH_CACHE_DIR="${TMP_ROOT}/t7-cache" \
  LEADV2_QUOTA_LOCKOUT_DIR="${TMP_ROOT}/t7-lockout" \
  LEADV2_DISPATCH_GLM_BIN="${TMP_ROOT}/poison-glm.sh" \
  LEADV2_DISPATCH_CODEX_BIN="${TMP_ROOT}/poison-codex.sh" \
  LEADV2_DISPATCH_SUBSESSION_BIN="${TMP_ROOT}/t7-sonnet.sh" \
  LEADV2_DISPATCH_ARCHITECT_GATE=0 \
  bash "${DISPATCH_BIN}" 'plugin-only bench banner visible t7' 2>&1)"
t7_banner_line="$(grep -n 'PRIMARY ARM BENCHED: glm' <<<"${t7_out}" | head -1 | cut -d: -f1)"
t7_route_line="$(grep -nE 'route_resolved|arm_resolved' <<<"${t7_out}" | head -1 | cut -d: -f1)"
if [[ -n "${t7_banner_line}" && -n "${t7_route_line}" && "${t7_banner_line}" -lt "${t7_route_line}" ]] \
  && grep -q 'class=worker_killed' <<<"${t7_out}" && grep -q 'quota_precheck_skip model=glm provider=glm' <<<"${t7_out}"; then
  pass 'T7: "PRIMARY ARM BENCHED: glm … class=worker_killed" banner on stderr before the first route line'
else
  fail 'T7: bench banner' "banner_line=${t7_banner_line:-none} route_line=${t7_route_line:-none} output=${t7_out}"
fi

# ── T8: strikes escalation — re-lock doubles minutes, capped at the class cap ──────
# Drives the close-gate CLI (record-quota-lockout) twice against the SAME
# fixture dir with a killed-worker tail: strike 1 -> 10m, strike 2 -> 20m.
make_dying_codex "${TMP_ROOT}/t8-codex.sh" "Killed"
t8_env=(LEADV2_QUOTA_LOCKOUT_DIR="${TMP_ROOT}/t8-lockout" \
  LEADV2_DISPATCH_CODEX_BIN="${TMP_ROOT}/t8-codex.sh")
t8_1="$(env "${t8_env[@]}" bash "${DISPATCH_BIN}" record-quota-lockout --arm codex --handle fake-h1 2>&1)"
t8_2="$(env "${t8_env[@]}" bash "${DISPATCH_BIN}" record-quota-lockout --arm codex --handle fake-h2 2>&1)"
t8_lockfile="${TMP_ROOT}/t8-lockout/quota-lockout-codex.json"
t8_ok=0
if [[ -f "${t8_lockfile}" ]]; then
  t8_ok="$(python3 - "${t8_lockfile}" <<'PY'
import json, sys, time
try:
    d = json.load(open(sys.argv[1]))
    epoch = int(d.get("locked_until_epoch") or 0)
    strikes = int(d.get("strikes") or 0)
except Exception:
    print(0); sys.exit(0)
delta_min = (epoch - time.time()) / 60.0
print(1 if (strikes == 2 and 19 <= delta_min <= 21) else 0)
PY
)"
fi
if [[ "${t8_ok}" == "1" ]] \
  && grep -q 'strikes=1 ' <<<"${t8_1}" && grep -q 'strikes=2 ' <<<"${t8_2}"; then
  pass 'T8: strikes escalation — second lock doubles to 20m (base 10, cap 60)'
else
  fail 'T8: strikes escalation' "lockfile=$(cat "${t8_lockfile}" 2>/dev/null || echo MISSING) run1=${t8_1} run2=${t8_2}"
fi

[[ ${FAIL} -eq 0 ]]
