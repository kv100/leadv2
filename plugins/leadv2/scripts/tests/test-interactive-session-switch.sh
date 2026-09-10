#!/usr/bin/env bash
# tests/test-interactive-session-switch.sh — interactive session leaves an
# exhausted account (lane 467462db0de5)
#
# Hermetic coverage for leadv2-interactive-session-switch.sh +
# leadv2-interactive-limit-detect.sh.  No network, no real keychain, no real
# account: registry, config dirs, credential reader
# (LEADV2_CLAUDE_PROFILE_SECURITY_BIN stub) and live probe
# (LEADV2_CLAUDE_PROFILE_PROBE stub) are all fixtures under mktemp -d, in the
# exact shape tests/test-account-switch.sh established.
#
# ONE CASE PER GUARD (the §3 round-2 lesson, now standing policy): every
# refusal path below has its own case AND its own journal word, and the
# mutation matrix in docs/handoff/w-interactive-session-switch/report.md kills
# exactly one guard per run — a mutation that reds two cases means two guards
# share a fixture and the suite is wrong, not the mutation.
#
#   case 1  screen banner "Session limit reached · Retrying in 50m · attempt
#           1/300" (the REAL string from the 2026-09-10 m3-market case) ->
#           switch + transplant + resume command          [screen matcher]
#   case 2  live probe says the account is at 100 -> same happy path
#                                                       [probe threshold]
#   case 3  limit, but NOTHING is free -> loud propagated refusal, no
#           transplant                            [refusal propagation]
#   case 4  ordinary network error on screen -> detector says no_limit,
#           account never touched                  [screen non-limit]
#   case 5  probe transport failure -> limit_unknown, account never touched
#                                               [unknown is never a limit]
#   case 6  transcript missing -> refused before anything runs
#                                                  [transcript guard]
#
# run-all-triggers: leadv2-interactive-session-switch leadv2-interactive-limit-detect

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
ORCH_BIN="${LEADV2_TEST_INTERACTIVE_SWITCH_BIN:-${SCRIPTS_ROOT}/leadv2-interactive-session-switch.sh}"
DETECT_BIN="${LEADV2_TEST_LIMIT_DETECT_BIN:-${SCRIPTS_ROOT}/leadv2-interactive-limit-detect.sh}"

PASS=0; FAIL=0
log()  { printf -- '[TEST] %s\n' "$*"; }
pass() { PASS=$((PASS + 1)); log "PASS: $1"; }
fail() { FAIL=$((FAIL + 1)); log "FAIL: $1 -- ${2:-}"; }
check_grep()  { if grep -qE -- "$2" <<<"$1"; then pass "$3"; else fail "$3" "no match for '$2' in: $1"; fi; }
check_fixed() { if grep -qF -- "$2" <<<"$1"; then pass "$3"; else fail "$3" "no fixed match for '$2' in: $1"; fi; }
check_rc()    { if [[ "$1" == "$2" ]]; then pass "$3"; else fail "$3" "rc=$1 want=$2"; fi; }
check_file()  { if [[ -e "$1" ]]; then pass "$2"; else fail "$2" "missing: $1"; fi; }
check_nofile(){ if [[ ! -e "$1" ]]; then pass "$2"; else fail "$2" "unexpectedly exists: $1"; fi; }

tmp="$(mktemp -d "${TMPDIR:-/tmp}/interactive-switch.XXXXXX")"
trap 'rm -rf "$tmp"' EXIT

unset LEADV2_CLAUDE_MULTIPROFILE LEADV2_ANTHROPIC_ACTIVE_SERVICE \
      LEADV2_CLAUDE_PROFILE_REQUESTED LEADV2_CLAUDE_PROFILE_DEMOTE_DIR 2>/dev/null || true

# --- fixtures: two registry slots, distinct real accounts (as in §3's suite)
DIR_A="$tmp/slot-a"; DIR_B="$tmp/slot-b"
mkdir -p "$DIR_A" "$DIR_B" "$tmp/cache" "$tmp/default-slot"
printf '{"oauthAccount":{"accountUuid":"uuid-AAAA","organizationUuid":"org-A","emailAddress":"a@test"}}' > "$DIR_A/.claude.json"
printf '{"oauthAccount":{"accountUuid":"uuid-BBBB","organizationUuid":"org-B","emailAddress":"b@test"}}' > "$DIR_B/.claude.json"
REG="$tmp/registry.tsv"
printf 'a\t%s\tkeychain:svc-a\tmax/a@test\nb\t%s\tkeychain:svc-b\tmax/b@test\n' "$DIR_A" "$DIR_B" > "$REG"

# The stuck interactive session's transcript, living in slot a's projects
# tree (its config dir) -- the only thing the restart must not lose.
SID="11111111-2222-3333-4444-555555555555"
PROJ_SEG="-tmp-proj"
TRANSCRIPT="$DIR_A/projects/$PROJ_SEG/$SID.jsonl"
mkdir -p "$DIR_A/projects/$PROJ_SEG"
printf '{"cwd":"/tmp/proj","type":"user","message":{"role":"user","content":"stuck mid-task"}}\n' > "$TRANSCRIPT"
TRANSPLANT_DEST="$DIR_B/projects/$PROJ_SEG/$SID.jsonl"
TRANS_SHA="$(shasum -a 256 "$TRANSCRIPT" | cut -d' ' -f1)"

# Credential reader stub: stable bytes per service (a real keychain entry
# does not mutate between reads).
FRESH_MS=$(( $(date +%s) * 1000 + 86400000 ))
export SWITCH_TEST_A_EXPIRES="$FRESH_MS" SWITCH_TEST_B_EXPIRES="$FRESH_MS"
SECURITY_STUB="$tmp/security-stub.sh"
cat > "$SECURITY_STUB" <<'SH'
#!/usr/bin/env bash
svc=""
while [[ $# -gt 0 ]]; do case "$1" in -s) svc="$2"; shift 2 ;; *) shift ;; esac; done
case "$svc" in
  svc-a) printf '{"claudeAiOauth":{"accessToken":"sk-ant-fixture-a","subscriptionType":"max","expiresAt":%s}}' "${SWITCH_TEST_A_EXPIRES:?}" ;;
  svc-b) printf '{"claudeAiOauth":{"accessToken":"sk-ant-fixture-b","subscriptionType":"max","expiresAt":%s}}' "${SWITCH_TEST_B_EXPIRES:?}" ;;
  *) exit 1 ;;
esac
SH
chmod +x "$SECURITY_STUB"

# Scenario file + probe stub: the §3 shapes, plus a.probe_fail=1 (detector
# transport failure -- case 5 only; the switch is never reached there).
SCEN="$tmp/scenario.env"
write_scenario() { # <a5h> <b5h>
  { printf 'a.five_hour_pct=%s\na.seven_day_pct=40\n' "$1"
    printf 'b.five_hour_pct=%s\nb.seven_day_pct=20\n' "$2"
    printf 'a.reset=2027-01-01T00:00:00Z\nb.reset=2027-01-02T00:00:00Z\n'
  } > "$SCEN"
}
PROBE_STUB="$tmp/probe-stub.py"
cat > "$PROBE_STUB" <<'PY'
#!/usr/bin/env python3
import json, os, sys
scen = {}
with open(os.environ.get("SWITCH_TEST_SCEN", "/dev/null"), "r") as fh:
    for line in fh:
        line = line.strip()
        if not line or "=" not in line:
            continue
        k, v = line.split("=", 1)
        scen[k] = v
label = os.environ.get("LEADV2_CLAUDE_PROFILE_LABEL", "")
svc = os.environ.get("LEADV2_ANTHROPIC_ACTIVE_SERVICE", "")
if not label:
    label = {"svc-a": "a", "svc-b": "b"}.get(svc, "")
if scen.get("%s.probe_fail" % label) == "1":
    sys.exit(1)
def win(pct, reset):
    rem = max(0.0, 100.0 - float(pct))
    return {"pct": float(pct), "reset_iso": reset, "remaining_pct": rem,
            "hours_to_reset": 5.0, "usable_now": rem / 5.0}
five_hour_pct = float(scen.get("%s.five_hour_pct" % label, 50))
seven_day_pct = float(scen.get("%s.seven_day_pct" % label, 50))
reset = scen.get("%s.reset" % label, "2027-01-01T00:00:00Z")
binding = "five_hour" if five_hour_pct >= seven_day_pct else "seven_day"
acct = {"service": svc or label, "active": True, "status": "ok",
        "five_hour_pct": five_hour_pct, "seven_day_pct": seven_day_pct,
        "five_hour_reset_iso": reset, "seven_day_reset_iso": "2027-01-08T00:00:00Z",
        "five_hour": win(five_hour_pct, reset),
        "seven_day": win(seven_day_pct, "2027-01-08T00:00:00Z"),
        "binding_window": binding}
print(json.dumps({"provider": "anthropic", "status": "ok",
                  "accounts": [acct], "binding_window": binding}))
PY

# Stub detector for case 3 ONLY: pins the limit verdict so that case's guard
# (refusal propagation) stands on NO detector guard — a mutation of either
# detector input must leave case 3 green (one mutation, exactly one red case).
STUB_DET="$tmp/stub-detector.sh"
printf '#!/usr/bin/env bash\nprintf "verdict=limit source=stub label=a pct=100\\n"\nexit 0\n' > "$STUB_DET"
chmod +x "$STUB_DET"

# Fresh handoff per case (cases must not read each other's journals); the
# counter is bumped OUTSIDE command substitution (fixture-counter trap).
HANDOFF_SEQ=0
mk_handoff() { # <tag>
  HANDOFF_SEQ=$((HANDOFF_SEQ + 1))
  MK_HANDOFF_OUT="$tmp/handoff-$1-$HANDOFF_SEQ"
  mkdir -p "$MK_HANDOFF_OUT"
}
export_env() { # <handoff-dir>
  export LEADV2_CLAUDE_PROFILES_FILE="$REG"
  export LEADV2_CLAUDE_PROFILE_SECURITY_BIN="$SECURITY_STUB"
  export LEADV2_CLAUDE_PROFILE_PROBE="$PROBE_STUB"
  export LEADV2_QUOTA_CACHE_DIR="$tmp/cache"
  export LEADV2_CLAUDE_ACCOUNT_ALARM_FILE="$tmp/alarm.json"
  export LEADV2_CLAUDE_PROFILE_DEFAULT_DIR="$tmp/default-slot"
  export LEADV2_CLAUDE_PROFILE_TIMEOUT=10
  export SWITCH_TEST_SCEN="$SCEN"
  export SWITCH_TEST_TMP="$tmp"
  export LEADV2_HANDOFF_DIR="$1"
}
reset_case() { rm -rf "$tmp/cache"; mkdir -p "$tmp/cache"; rm -f "$tmp"/probe-count-* "$tmp/alarm.json"; rm -rf "$DIR_B/projects"; }

MARKER_A="$tmp/cache/identity-max_a_test/probe-cooldown-until"
BANNER="Session limit reached · Retrying in 50m · attempt 1/300"

# =============================================================================
log "== case 1: the REAL banner string -> switch + transplant + resume (screen matcher)"
write_scenario 100 30
reset_case
mk_handoff c1; H="$MK_HANDOFF_OUT"
export_env "$H"
OUT="$(bash "$ORCH_BIN" --transcript "$TRANSCRIPT" --config-dir "$DIR_A" --screen-text "$BANNER" --handoff "$H" 2>&1)"; RC=$?
check_rc "$RC" 0 "case1 rc=0 (switched + transplanted)"
check_grep "$OUT" 'OK switched from=a to=b' "case1 names the switch a -> b"
check_grep "$OUT" 'detector: verdict=limit source=screen label=a' "case1 detector matched the banner (screen source)"
check_grep "$OUT" "attempt=1/300" "case1 detector reports the banner's attempt counter"
check_fixed "$OUT" "resume: cd \"/tmp/proj\" && CLAUDE_CONFIG_DIR=\"$DIR_B\" claude --resume $SID" "case1 emits the exact resume command pinned to slot b"
check_file "$TRANSPLANT_DEST" "case1 transcript transplanted into slot b"
DEST_SHA="$(shasum -a 256 "$TRANSPLANT_DEST" 2>/dev/null | cut -d' ' -f1)"
[[ "$DEST_SHA" == "$TRANS_SHA" ]] && pass "case1 transplant byte-identical" || fail "case1 transplant byte-identical" "sha $DEST_SHA != $TRANS_SHA"
check_file "$MARKER_A" "case1 cooldown marker armed for exhausted a (the switch happened)"
check_grep "$(cat "$H/interactive-switch.log" 2>/dev/null)" 'switched from=a to=b.*session=' "case1 journal: switch + session named"
check_file "$H/account-switch.log" "case1 account-switch ran and journalled"

# =============================================================================
log "== case 2: live probe at 100 -> same happy path (probe threshold)"
write_scenario 100 30
reset_case
mk_handoff c2; H="$MK_HANDOFF_OUT"
export_env "$H"
OUT="$(bash "$ORCH_BIN" --transcript "$TRANSCRIPT" --config-dir "$DIR_A" --handoff "$H" 2>&1)"; RC=$?
check_rc "$RC" 0 "case2 rc=0 (live-detected limit switched)"
check_grep "$OUT" 'detector: verdict=limit source=live label=a pct=100' "case2 detector decided from the LIVE probe (not screen)"
check_file "$TRANSPLANT_DEST" "case2 transcript transplanted"
check_fixed "$OUT" "CLAUDE_CONFIG_DIR=\"$DIR_B\" claude --resume $SID" "case2 resume command pinned to slot b"

# =============================================================================
log "== case 3: limit, NOTHING free -> loud propagated refusal, no transplant (refusal propagation)"
# Limit verdict pinned via the stub detector: this case's guard is the refusal
# propagation alone — mutations of either detector input must leave it green.
write_scenario 100 100
reset_case
mk_handoff c3; H="$MK_HANDOFF_OUT"
export_env "$H"
OUT="$(LEADV2_TEST_LIMIT_DETECT_BIN="$STUB_DET" bash "$ORCH_BIN" --transcript "$TRANSCRIPT" --config-dir "$DIR_A" --handoff "$H" 2>&1)"; RC=$?
check_rc "$RC" 3 "case3 rc=3 (refused)"
check_grep "$OUT" 'REFUSED reason=switch_refused detail=no_free_alternative' "case3 propagates the account-switch refusal word"
check_nofile "$TRANSPLANT_DEST" "case3 nothing transplanted on refusal"
check_nofile "$MARKER_A" "case3 no steering marker (the switch itself refused)"
J3="$(cat "$H/interactive-switch.log" 2>/dev/null)"
check_grep "$J3" 'REFUSED reason=switch_refused detail=no_free_alternative' "case3 journal names WHICH guard (switch_refused + no_free_alternative)"

# =============================================================================
log "== case 4: ordinary network error on screen -> no_limit, account never touched (screen non-limit)"
write_scenario 100 30
reset_case
mk_handoff c4; H="$MK_HANDOFF_OUT"
export_env "$H"
NETERR="API Error: Connection error. Please check your internet connection and try again."
OUT="$(bash "$ORCH_BIN" --transcript "$TRANSCRIPT" --config-dir "$DIR_A" --screen-text "$NETERR" --handoff "$H" 2>&1)"; RC=$?
check_rc "$RC" 3 "case4 rc=3 (refused)"
check_grep "$OUT" 'REFUSED reason=not_limit' "case4 refuses: a network error is not a limit"
check_nofile "$H/account-switch.log" "case4 account-switch NEVER invoked"
check_nofile "$MARKER_A" "case4 account untouched (no marker)"
check_nofile "$TRANSPLANT_DEST" "case4 nothing transplanted"
check_grep "$(cat "$H/interactive-switch.log" 2>/dev/null)" 'REFUSED reason=not_limit detail=detector_no_limit' "case4 journal names the not_limit guard"
# detector unit, same guard: "Approaching" is not "reached", and a file input works
printf 'Approaching your usage limit. You still have capacity left.' > "$tmp/screen.txt"
DOUT="$(bash "$DETECT_BIN" --screen-text "@$tmp/screen.txt" --config-dir "$DIR_A" 2>&1)"; DRC=$?
check_rc "$DRC" 1 "case4-unit approaching-usage-limit is no_limit"
check_grep "$DOUT" 'verdict=no_limit' "case4-unit names no_limit"

# =============================================================================
log "== case 5: probe transport failure -> limit_unknown, account never touched (unknown is never a limit)"
write_scenario 100 30
printf 'a.probe_fail=1\n' >> "$SCEN"
reset_case
mk_handoff c5; H="$MK_HANDOFF_OUT"
export_env "$H"
OUT="$(bash "$ORCH_BIN" --transcript "$TRANSCRIPT" --config-dir "$DIR_A" --handoff "$H" 2>&1)"; RC=$?
check_rc "$RC" 3 "case5 rc=3 (refused)"
check_grep "$OUT" 'REFUSED reason=limit_unknown detail=probe_transport' "case5 refuses on unknown: a network failure must never trigger a switch"
check_nofile "$H/account-switch.log" "case5 account-switch NEVER invoked"
check_nofile "$MARKER_A" "case5 account untouched (no marker)"
check_nofile "$TRANSPLANT_DEST" "case5 nothing transplanted"
check_grep "$(cat "$H/interactive-switch.log" 2>/dev/null)" 'REFUSED reason=limit_unknown detail=probe_transport' "case5 journal names the limit_unknown guard"
sed -i '' '/^a.probe_fail=1$/d' "$SCEN"

# =============================================================================
log "== case 6: transcript missing -> refused before anything runs (transcript guard)"
write_scenario 100 30
reset_case
mk_handoff c6; H="$MK_HANDOFF_OUT"
export_env "$H"
OUT="$(bash "$ORCH_BIN" --transcript "$tmp/does-not-exist.jsonl" --config-dir "$DIR_A" --screen-text "$BANNER" --handoff "$H" 2>&1)"; RC=$?
check_rc "$RC" 5 "case6 rc=5 (refused)"
check_grep "$OUT" 'REFUSED reason=transcript_missing' "case6 names transcript_missing"
check_nofile "$H/account-switch.log" "case6 nothing ran downstream of the guard"
check_nofile "$MARKER_A" "case6 no marker (the guard fires FIRST)"
check_grep "$(cat "$H/interactive-switch.log" 2>/dev/null)" 'REFUSED reason=transcript_missing' "case6 journal names the transcript guard"

# =============================================================================
printf -- '[TEST] summary: PASS=%d FAIL=%d\n' "$PASS" "$FAIL"
(( FAIL == 0 )) || exit 1
exit 0
