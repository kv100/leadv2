#!/usr/bin/env bash
# tests/test-quota-daemon.sh — W1-QUOTA-DAEMON-01 part B
#
# The always-live quota daemon (founder proposal 2026-09-09, PRE-WAVES-PLAN
# §1 item 1.5) must: start as an idempotent singleton; answer ONE command with
# every source's remaining_pct + hours_to_reset for BOTH windows (codex: the
# single weekly one) with freshness not older than 60 s; add ZERO logins per
# request (the acceptance's "no interactive login" -- queries between polls
# must not touch the reader at all); and feed the existing scorer path by
# making leadv2-quota-read.py consult its snapshot instead of doing a live
# call (that consult is the daemon's feed into leadv2-claude-profile-select.sh
# probes -> lib/leadv2-claude-profile-pick.py scoring, neither of which is
# modified by this lane).
#
# Hermetic: LEADV2_QUOTA_READ points at a fake reader that counts invocations;
# the registry is a fixture TSV; no network, no real keychain, no real
# ~/.claude state. Named tests:
#   T1 daemon-start-idempotent
#   T2 query-serves-both-windows-fresh      (acceptance #1)
#   T3 no-login-per-request                 (acceptance #1)
#   T4 quota-read-consults-daemon           (feeds the existing scorer)
#   T5 scorer-profile-keys-served           (per-service / per-file consults)
#   T6 stale-refuses-freshness-lie          (fail-open, never fabricated)
#   T7 stop-clean
#
# run-all-triggers: leadv2-quota-daemon leadv2-quota-read

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
DAEMON_BIN="${SCRIPTS_ROOT}/leadv2-quota-daemon.py"
READER="${SCRIPTS_ROOT}/leadv2-quota-read.py"

if [[ ! -f "${DAEMON_BIN}" ]]; then
  echo "FAIL: daemon not found at ${DAEMON_BIN}" >&2
  exit 1
fi

TMPD="$(mktemp -d)"
cleanup() {
  "${DAEMON_BIN}" stop >/dev/null 2>&1 || true
  rm -rf "${TMPD}"
}
trap cleanup EXIT

FAKE_READER="${TMPD}/fake-reader.py"
CALLS="${TMPD}/calls.log"
cat > "${FAKE_READER}" <<'FAKE'
import json, os, sys
args = sys.argv[1:]
p = args[0] if args else ""
calls = os.environ["FAKE_CALLS_LOG"]
key = p
if p == "anthropic":
    svc = os.environ.get("LEADV2_ANTHROPIC_ACTIVE_SERVICE", "")
    cf = args[args.index("--credential-file") + 1] if "--credential-file" in args else ""
    key = "anthropic:service:" + svc if svc else ("anthropic:file:" + cf if cf else "anthropic")
with open(calls, "a") as f:
    f.write(key + "\n")
# The reader's stdout contract (main() prints normalize_payload output):
# every window carries remaining_pct/hours_to_reset/usable_now already.
if p == "glm":
    doc = {"provider": "glm", "status": "ok", "level": "max",
           "five_hour": {"pct": 24, "reset_iso": "2099-01-01T00:00:00Z",
                         "remaining_pct": 76.0, "hours_to_reset": 5.0, "usable_now": 15.2},
           "weekly": {"pct": 16, "reset_iso": "2099-01-02T00:00:00Z",
                      "remaining_pct": 84.0, "hours_to_reset": 168.0, "usable_now": 0.5}}
elif p == "codex":
    doc = {"provider": "codex", "status": "ok", "plan_type": "prolite",
           "windows": [{"kind": "primary", "used_percent": 38,
                        "limit_window_seconds": 604800, "reset_at": 4102444800,
                        "remaining_pct": 62.0, "hours_to_reset": 130.0, "usable_now": 0.48}]}
elif p == "anthropic":
    doc = {"provider": "anthropic", "status": "ok",
           "accounts": [{"account_label": "fake-profile", "active": True,
                         "five_hour": {"pct": 10, "reset_iso": "2099-01-01T00:00:00Z",
                                       "remaining_pct": 90.0, "hours_to_reset": 3.0, "usable_now": 30.0},
                         "seven_day": {"pct": 40, "reset_iso": "2099-01-02T00:00:00Z",
                                       "remaining_pct": 60.0, "hours_to_reset": 100.0, "usable_now": 0.6}}]}
else:
    doc = {"provider": p, "status": "unknown", "error": "fake: unknown provider"}
print(json.dumps(doc))
FAKE

cat > "${TMPD}/profiles.tsv" <<TSV
# label	config_dir	credential_source	expect
personal	${TMPD}/cfgA	keychain:Claude Code-credentials-abc123	max
work	${TMPD}/cfgB	file:${TMPD}/credB.json	max
TSV
: > "${TMPD}/credB.json"

export LEADV2_QUOTA_READ="${FAKE_READER}"
export FAKE_CALLS_LOG="${CALLS}"
export LEADV2_QUOTA_DAEMON_DIR="${TMPD}/daemon-state"
export LEADV2_CLAUDE_PROFILES_FILE="${TMPD}/profiles.tsv"
export LEADV2_QUOTA_DAEMON_INTERVAL_GLM=2
export LEADV2_QUOTA_DAEMON_INTERVAL_CODEX=2
export LEADV2_QUOTA_DAEMON_INTERVAL_ANTHROPIC=2
# Hermeticity: any fallback LIVE read must deterministically fail open, never
# touch the real keychain / shared quota cache / real credentials. A `security`
# stub on PATH makes _keychain_services fail; the scratch cache dir and empty
# tokens make glm/codex unknown. Only the daemon's snapshot can answer ok.
mkdir -p "${TMPD}/pathstub"
printf '#!/bin/sh\nexit 1\n' > "${TMPD}/pathstub/security"
chmod +x "${TMPD}/pathstub/security"
export PATH="${TMPD}/pathstub:${PATH}"
export LEADV2_QUOTA_CACHE_DIR="${TMPD}/no-cache"
export ZAI_AUTH_TOKEN=""
export LEADV2_ZAI_ENV="${TMPD}/no-zai-env"
export CODEX_HOME="${TMPD}/no-codex-home"

PASS=0; FAIL=0; ERRORS=()
log()  { printf -- '[TEST] %s\n' "$*"; }
pass() { PASS=$((PASS + 1)); log "PASS: $1"; }
fail() { FAIL=$((FAIL + 1)); ERRORS+=("FAIL: $1"); log "FAIL: $1 -- ${2:-}"; }

count_calls() { [[ -f "${CALLS}" ]] && wc -l < "${CALLS}" | tr -d ' ' || echo 0; }
calls_for() { grep -c "^$1$" "${CALLS}" 2>/dev/null || true; }

# T1: idempotent singleton start.
"${DAEMON_BIN}" start; rc=$?
[[ ${rc} -eq 0 ]] && pass "T1 daemon-start-idempotent (first start rc=0)" \
  || fail "T1 daemon-start-idempotent" "first start rc=${rc}"
out2="$("${DAEMON_BIN}" start)"; rc2=$?
[[ ${rc2} -eq 0 && "${out2}" == *"already running"* ]] \
  && pass "T1 daemon-start-idempotent (second start is a no-op)" \
  || fail "T1 daemon-start-idempotent" "second start rc=${rc2} out=${out2}"

# Let the first poll cycle land (intervals are 2 s).
sleep 4

# T2: one command, every source, both windows, fresh ages.
qjson="$("${DAEMON_BIN}" query --json --max-age 60 2>/dev/null)"
echo "${qjson}" | python3 -c '
import json, sys
d = json.load(sys.stdin)
src = d["sources"]
glm = src.get("glm", {})
fh = glm.get("five_hour") or {}
wk = glm.get("weekly") or {}
cx = (src.get("codex", {}).get("windows") or [{}])[0]
an = ((src.get("anthropic", {}).get("accounts") or [{}])[0])
ok = (glm.get("status") == "ok" and fh.get("remaining_pct") == 76.0
      and isinstance(fh.get("hours_to_reset"), (int, float)) and fh["hours_to_reset"] > 0
      and wk.get("remaining_pct") == 84.0 and wk["hours_to_reset"] > 0
      and cx.get("remaining_pct") == 62.0 and cx.get("hours_to_reset") > 0
      and cx.get("limit_window_seconds") == 604800
      and not any(w.get("limit_window_seconds") == 18000
                  for w in src.get("codex", {}).get("windows", []))
      and an.get("five_hour", {}).get("remaining_pct") == 90.0
      and an.get("seven_day", {}).get("remaining_pct") == 60.0)
print("[TEST] %s T2 query-serves-both-windows-fresh" % ("PASS:" if ok else "FAIL:"))
sys.exit(0 if ok else 1)
' && pass "T2 query-serves-both-windows-fresh (acceptance #1: both windows, real periods)" \
  || fail "T2 query-serves-both-windows-fresh" "query json: ${qjson:0:600}"

ages="$("${DAEMON_BIN}" status | grep -c 'age *[0-9]')"
[[ ${ages} -ge 3 ]] && pass "T2 status-reports-per-source-ages (${ages} sources)" \
  || fail "T2 status-reports-per-source-ages" "status shows ${ages} sources"

# T3: queries between polls add ZERO reader invocations (no login per request).
before="$(count_calls)"
for _ in 1 2 3 4 5; do "${DAEMON_BIN}" query --max-age 60 >/dev/null 2>&1; done
after="$(count_calls)"
[[ "${after}" == "${before}" ]] \
  && pass "T3 no-login-per-request (5 queries, 0 new reader calls)" \
  || fail "T3 no-login-per-request" "calls ${before} -> ${after}"

# T4: the real reader serves the daemon's snapshot (consult) with no live call.
# ZAI_AUTH_TOKEN is empty here, so a live read would fail to unknown -- a
# status=ok answer proves the snapshot served it.
consult="$(LEADV2_QUOTA_READ="${READER}" python3 "${READER}" glm 2>/dev/null)"
echo "${consult}" | python3 -c '
import json, sys
d = json.load(sys.stdin)
fh = (d.get("models", {}).get("glm-5.3", {}).get("five_hour") or {}) \
     if d.get("status") == "ok" else {}
ok = d.get("status") == "ok" and d.get("level") == "max" and "five_hour" in d
print("[TEST] %s T4 quota-read-consults-daemon" % ("PASS:" if ok else "FAIL:"))
sys.exit(0 if ok else 1)
' && pass "T4 quota-read-consults-daemon (feeds the existing scorer probe path)" \
  || fail "T4 quota-read-consults-daemon" "consult=${consult:0:300}"

# T5: the scorer's per-profile probe keys are served too.
svc_consult="$(LEADV2_QUOTA_READ="${READER}" \
  LEADV2_ANTHROPIC_ACTIVE_SERVICE="Claude Code-credentials-abc123" \
  python3 "${READER}" anthropic 2>/dev/null)"
file_consult="$(LEADV2_QUOTA_READ="${READER}" python3 "${READER}" anthropic \
  --credential-file "${TMPD}/credB.json" 2>/dev/null)"
python3 -c '
import json, sys
docs = [json.loads(a) for a in sys.argv[1:3]]
ok = all(d.get("status") == "ok"
         and (d.get("accounts") or [{}])[0].get("account_label") == "fake-profile"
         for d in docs)
print("[TEST] %s T5 scorer-profile-keys-served" % ("PASS:" if ok else "FAIL:"))
sys.exit(0 if ok else 1)
' "${svc_consult}" "${file_consult}" && pass "T5 scorer-profile-keys-served (keychain: and file: consults hit daemon keys)" \
  || fail "T5 scorer-profile-keys-served" "svc=${svc_consult:0:200} file=${file_consult:0:200}"
[[ "$(calls_for 'anthropic:service:Claude Code-credentials-abc123')" -ge 1 ]] \
  && [[ "$(calls_for 'anthropic:file:'"${TMPD}"'/credB.json')" -ge 1 ]] \
  && pass "T5 daemon-polled-the-registry-keys" \
  || fail "T5 daemon-polled-the-registry-keys" \
    "service=$(calls_for 'anthropic:service:Claude Code-credentials-abc123') file=$(grep -c '^anthropic:file:' "${CALLS}" 2>/dev/null || echo 0)"

# T6: staleness is refused loudly, numbers are kept but never refreshed.
"${DAEMON_BIN}" stop >/dev/null 2>&1
sleep 3
qout="$("${DAEMON_BIN}" query --max-age 2 2>&1)"; qrc=$?
[[ ${qrc} -eq 3 && "${qout}" == *"STALE"* && "${qout}" == *"remaining="* ]] \
  && pass "T6 stale-refuses-freshness-lie (rc=3, STALE named, last-known kept)" \
  || fail "T6 stale-refuses-freshness-lie" "rc=${qrc} out=${qout:0:300}"

# T7: stop is clean and idempotent; socket removed.
"${DAEMON_BIN}" stop >/dev/null 2>&1
sleep 1
[[ ! -S "${LEADV2_QUOTA_DAEMON_DIR}/daemon.sock" && ! -f "${LEADV2_QUOTA_DAEMON_DIR}/daemon.pid" ]] \
  && pass "T7 stop-clean (socket+pidfile gone)" \
  || fail "T7 stop-clean" "socket/pidfile still present"
"${DAEMON_BIN}" stop >/dev/null 2>&1 && pass "T7 stop-idempotent" \
  || fail "T7 stop-idempotent" "second stop rc nonzero"

echo
echo "passed=${PASS} failed=${FAIL}"
if [[ ${FAIL} -gt 0 ]]; then
  printf '%s\n' "${ERRORS[@]}"
  echo "SUITE FAIL: quota daemon"
  exit 1
fi
echo "SUITE OK: quota daemon"
exit 0
