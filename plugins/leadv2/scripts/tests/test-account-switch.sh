#!/usr/bin/env bash
# tests/test-account-switch.sh — §3 "account switch as a working operation"
#
# Hermetic coverage for leadv2-account-switch.sh.  No network, no real
# keychain, no real account: the registry, config dirs, credential reader
# (LEADV2_CLAUDE_PROFILE_SECURITY_BIN stub) and the live probe
# (LEADV2_CLAUDE_PROFILE_PROBE stub) are all fixtures under mktemp -d.  The
# probe stub is scenario-driven (per-label pct + reset iso) and can flip a
# label to a confirmed live failure after N probings, which is what makes
# the switch_not_taken case observable.  It can also DROP a label to free
# after N probings (a_drop_after), and the credential stub can model an
# operator re-login mid-switch (SWITCH_TEST_A_RELOGIN: a different blob from
# the moment the steering marker's .cred sidecar exists) -- together they
# make the FIRST of the two switch_not_taken guards (next pick stays on the
# OLD account, detail=next_pick_not_target) observable, case 8.
#
# run-all-triggers: leadv2-account-switch

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
SWITCH_BIN="${LEADV2_TEST_ACCOUNT_SWITCH_BIN:-${SCRIPTS_ROOT}/leadv2-account-switch.sh}"
SELECTOR_BIN="${SCRIPTS_ROOT}/leadv2-claude-profile-select.sh"

PASS=0; FAIL=0
log()  { printf -- '[TEST] %s\n' "$*"; }
pass() { PASS=$((PASS + 1)); log "PASS: $1"; }
fail() { FAIL=$((FAIL + 1)); log "FAIL: $1 -- ${2:-}"; }
check_grep()  { if grep -qE -- "$2" <<<"$1"; then pass "$3"; else fail "$3" "no match for '$2' in: $1"; fi; }
check_rc()    { if [[ "$1" == "$2" ]]; then pass "$3"; else fail "$3" "rc=$1 want=$2"; fi; }
check_file()  { if [[ -e "$1" ]]; then pass "$2"; else fail "$2" "missing: $1"; fi; }
check_nofile(){ if [[ ! -e "$1" ]]; then pass "$2"; else fail "$2" "unexpectedly exists: $1"; fi; }

tmp="$(mktemp -d "${TMPDIR:-/tmp}/account-switch.XXXXXX")"
trap 'rm -rf "$tmp"' EXIT

unset LEADV2_CLAUDE_MULTIPROFILE LEADV2_ANTHROPIC_ACTIVE_SERVICE \
      LEADV2_CLAUDE_PROFILE_REQUESTED LEADV2_CLAUDE_PROFILE_DEMOTE_DIR 2>/dev/null || true

# --- fixtures ---------------------------------------------------------------
# Two registry slots, keychain-sourced, distinct real accounts.
DIR_A="$tmp/slot-a"; DIR_B="$tmp/slot-b"
mkdir -p "$DIR_A" "$DIR_B" "$tmp/cache" "$tmp/default-slot"
printf '{"oauthAccount":{"accountUuid":"uuid-AAAA","organizationUuid":"org-A","emailAddress":"a@test"}}' > "$DIR_A/.claude.json"
printf '{"oauthAccount":{"accountUuid":"uuid-BBBB","organizationUuid":"org-B","emailAddress":"b@test"}}' > "$DIR_B/.claude.json"
REG="$tmp/registry.tsv"
printf 'a\t%s\tkeychain:svc-a\tmax/a@test\nb\t%s\tkeychain:svc-b\tmax/b@test\n' "$DIR_A" "$DIR_B" > "$REG"

# Credential reader stub: fake blobs per service.  b's expiresAt is read
# from the RUNTIME env SWITCH_TEST_B_EXPIRES so the stale-but-alive case can
# flip it without regenerating the stub.
STALE_MS=$(( $(date +%s) * 1000 - 3600000 ))
FRESH_MS=$(( $(date +%s) * 1000 + 86400000 ))
# Both services return STABLE bytes for the whole suite (a real keychain
# entry does not mutate between reads) -- an unstable blob makes the digest
# differ per probe, and the selector's cooldown-invalidation logic then reads
# "credential changed" and deletes the steering marker mid-case.
export SWITCH_TEST_A_EXPIRES="$FRESH_MS"
export SWITCH_TEST_B_EXPIRES="$FRESH_MS"
SECURITY_STUB="$tmp/security-stub.sh"
cat > "$SECURITY_STUB" <<'SH'
#!/usr/bin/env bash
svc=""
while [[ $# -gt 0 ]]; do case "$1" in -s) svc="$2"; shift 2 ;; *) shift ;; esac; done
case "$svc" in
  # SWITCH_TEST_A_RELOGIN (case 8 only): once the switch has armed a's
  # steering marker (its .cred sidecar exists -- written AFTER the digest
  # read, so the marker records the OLD blob), every later read returns a
  # DIFFERENT blob: the operator re-logged into the exhausted account
  # mid-switch, the PROBE-COOLDOWN-OUTLIVES-ITS-CONDITION-01 invalidation
  # shape (sidecar digest != current digest -> steer deleted, account probes).
  svc-a)
    if [[ -n "${SWITCH_TEST_A_RELOGIN:-}" ]] \
       && [[ -e "${SWITCH_TEST_TMP}/cache/identity-max_a_test/probe-cooldown-until.cred" ]]; then
      printf '{"claudeAiOauth":{"accessToken":"sk-ant-fixture-a-relogged","subscriptionType":"max","expiresAt":%s}}' "${SWITCH_TEST_A_EXPIRES:?}"
    else
      printf '{"claudeAiOauth":{"accessToken":"sk-ant-fixture-a","subscriptionType":"max","expiresAt":%s}}' "${SWITCH_TEST_A_EXPIRES:?}"
    fi ;;
  svc-b) printf '{"claudeAiOauth":{"accessToken":"sk-ant-fixture-b","subscriptionType":"max","expiresAt":%s}}' "${SWITCH_TEST_B_EXPIRES:?}" ;;
  *) exit 1 ;;
esac
SH
chmod +x "$SECURITY_STUB"

# Scenario file: per-label window pcts + reset isos; optional
# b_flip_after=N flips label b to EXHAUSTED (still live/ok, pct=100) on its
# Nth probing -- the observable "target stopped being free before the next
# selection" shape the switch must report as a failure.
SCEN="$tmp/scenario.env"
write_scenario() { # <a5h> <b5h> [b_flip_after]
  { printf 'a.five_hour_pct=%s\na.seven_day_pct=40\n' "$1"
    printf 'b.five_hour_pct=%s\nb.seven_day_pct=20\n' "$2"
    printf 'a.reset=2027-01-01T00:00:00Z\nb.reset=2027-01-02T00:00:00Z\n'
    [[ -n "${3:-}" ]] && printf 'b_flip_after=%s\n' "$3"
  } > "$SCEN"
}

# Probe stub: emits the anthropic-shaped payload quota-read.py would.  Keys
# off LEADV2_CLAUDE_PROFILE_LABEL (selector passes it) or the service pin.
PROBE_STUB="$tmp/probe-stub.py"
cat > "$PROBE_STUB" <<'PY'
#!/usr/bin/env python3
import json, os, re
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
fail_after = scen.get("%s_flip_after" % label)
drop_after = scen.get("%s_drop_after" % label)
if fail_after or drop_after:
    cnt_path = os.path.join(os.environ.get("SWITCH_TEST_TMP", "/tmp"),
                            "probe-count-%s" % label)
    n = 0
    try:
        with open(cnt_path) as fh:
            n = int(fh.read().strip() or 0)
    except OSError:
        pass
    n += 1
    with open(cnt_path, "w") as fh:
        fh.write(str(n))
    if fail_after and n >= int(fail_after):
        scen["%s.five_hour_pct" % label] = "100"
        scen["%s.seven_day_pct" % label] = "100"
    # drop = the label turns FREE from its Nth probing (not failed): the
    # re-login-refreshed-account shape that makes the balancer legitimately
    # go BACK to the old label on the observation run (case 8).
    if drop_after and n >= int(drop_after):
        scen["%s.five_hour_pct" % label] = scen.get("%s_drop_five" % label, "10")
        scen["%s.seven_day_pct" % label] = scen.get("%s_drop_seven" % label, "5")
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

# Handoff with a current-account history and artifacts that must SURVIVE.
# Every call gets a FRESH dir -- cases must not read each other's journals.
# The dir name is returned via $MK_HANDOFF_OUT, NOT stdout: a counter bumped
# inside "\$(mk_handoff ...)" dies in the subshell and every case would land
# in the SAME dir (fixture-counter-dies-in-command-substitution).
HANDOFF_SEQ=0
mk_handoff() { # <current-label>
  HANDOFF_SEQ=$((HANDOFF_SEQ + 1))
  MK_HANDOFF_OUT="$tmp/handoff-$1-$HANDOFF_SEQ"
  mkdir -p "$MK_HANDOFF_OUT"
  printf '2026-09-09T00:00:00Z [claude-profile] selected=%s rank_by=consumed_pct_min consumed_pct=99 usable_now=- source=live candidates=2 cred_kind=keychain identity=max/%s@test\n' \
    "$1" "$1" > "$MK_HANDOFF_OUT/claude-profile.log"
  printf '{"events":["lane stream row 1","lane stream row 2"]}\n' > "$MK_HANDOFF_OUT/developer.stream.jsonl"
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
independent_pick() { # the test's OWN selector run: observation, not the script's claim
  env LEADV2_CLAUDE_MULTIPROFILE=1 \
      LEADV2_CLAUDE_PROFILE_DEMOTE_DIR=off \
      LEADV2_CLAUDE_PROFILES_FILE="$REG" \
      LEADV2_CLAUDE_PROFILE_SECURITY_BIN="$SECURITY_STUB" \
      LEADV2_CLAUDE_PROFILE_PROBE="$PROBE_STUB" \
      LEADV2_QUOTA_CACHE_DIR="$tmp/cache" \
      LEADV2_CLAUDE_PROFILE_DEFAULT_DIR="$tmp/default-slot" \
      LEADV2_CLAUDE_ACCOUNT_ALARM_FILE="$tmp/alarm.json" \
      SWITCH_TEST_SCEN="$SCEN" SWITCH_TEST_TMP="$tmp" \
    bash "$SELECTOR_BIN" 2>/dev/null | head -1
}

reset_cache() { rm -rf "$tmp/cache"; mkdir -p "$tmp/cache"; rm -f "$tmp"/probe-count-* "$tmp/alarm.json"; }

# =============================================================================
log "== case 1: MAIN — a exhausted, b free -> switch, and the OBSERVED next pick is b"
write_scenario 100 30
reset_cache
mk_handoff a; H="$MK_HANDOFF_OUT"
LOG_SHA_BEFORE="$(shasum -a 256 "$H/claude-profile.log" | cut -d' ' -f1)"
STREAM_SHA_BEFORE="$(shasum -a 256 "$H/developer.stream.jsonl" | cut -d' ' -f1)"
export_env "$H"
OUT="$(bash "$SWITCH_BIN" --handoff "$H" 2>&1)"; RC=$?
check_rc "$RC" 0 "case1 rc=0 (switched)"
check_grep "$OUT" 'observed_next_pick=b' "case1 stdout names observed_next_pick=b"
check_grep "$OUT" 'staying_children=[0-9]+' "case1 reports staying children count"
# observation by the TEST, not the script's own claim:
NEXT="$(independent_pick)"
check_grep "$NEXT" '^profile=b ' "case1 INDEPENDENT next selector pick is b"
# steering marker: selector-native cooldown armed for a until its reset
# (id_key = identity "max/a@test" mangled the selector's way -> max_a_test)
MARKER="$tmp/cache/identity-max_a_test/probe-cooldown-until"
check_file "$MARKER" "case1 cooldown marker written for exhausted a"
MARKER_VAL="$(cat "$MARKER" 2>/dev/null || echo -)"
WANT_EPOCH="$(python3 -c 'import calendar,time; print(calendar.timegm(time.strptime("2027-01-01T00:00:00","%Y-%m-%dT%H:%M:%S")))')"
[[ "$MARKER_VAL" == "$WANT_EPOCH" ]] && pass "case1 marker until == a's own reset epoch" || fail "case1 marker until" "got '$MARKER_VAL' want '$WANT_EPOCH'"
# survivors: checked by reading bytes back
LOG_SHA_AFTER="$(shasum -a 256 "$H/claude-profile.log" | cut -d' ' -f1)"
STREAM_SHA_AFTER="$(shasum -a 256 "$H/developer.stream.jsonl" | cut -d' ' -f1)"
[[ "$LOG_SHA_BEFORE" == "$LOG_SHA_AFTER" ]] && pass "case1 claude-profile.log byte-identical" || fail "case1 claude-profile.log" "sha changed"
[[ "$STREAM_SHA_BEFORE" == "$STREAM_SHA_AFTER" ]] && pass "case1 lane stream survived" || fail "case1 lane stream" "sha changed"
check_grep "$(cat "$H/account-switch.log" 2>/dev/null)" 'switched from=a to=b' "case1 account-switch.log journals the switch"

# =============================================================================
log "== case 2: PAIRED — a exhausted, NOTHING free -> loud refusal, no switch (only b's pct differs)"
write_scenario 100 100
reset_cache
mk_handoff a; H="$MK_HANDOFF_OUT"
export_env "$H"
OUT="$(bash "$SWITCH_BIN" --handoff "$H" 2>&1)"; RC=$?
check_rc "$RC" 3 "case2 rc=3 (refused)"
check_grep "$OUT" 'REFUSED reason=no_free_alternative' "case2 names the refusal reason"
check_grep "$OUT" 'reset=' "case2 names the nearest reset"
check_nofile "$tmp/cache/identity-max_a_test/probe-cooldown-until" "case2 no steering marker on refusal"
check_grep "$(cat "$H/account-switch.log" 2>/dev/null)" 'REFUSED reason=no_free_alternative' "case2 refusal journalled"
if grep -q 'switched from=' "$H/account-switch.log" 2>/dev/null; then fail "case2 no switch journalled as done" "found 'switched from='"; else pass "case2 no switch journalled as done"; fi
# nothing changed: the balancer still ranks as the scenario says
NEXT="$(independent_pick)"
check_grep "$NEXT" '^profile=a ' "case2 INDEPENDENT next pick unchanged (a)"

# =============================================================================
log "== case 3: only free account IS the current one -> refusal, not a self-switch"
write_scenario 30 100
reset_cache
mk_handoff a; H="$MK_HANDOFF_OUT"
export_env "$H"
OUT="$(bash "$SWITCH_BIN" --handoff "$H" 2>&1)"; RC=$?
check_rc "$RC" 3 "case3 rc=3 (refused)"
check_grep "$OUT" 'REFUSED reason=current_is_best_free' "case3 names current_is_best_free"

# =============================================================================
log "== case 4: expiresAt stale but account alive -> still free, still the target"
write_scenario 100 25
export SWITCH_TEST_B_EXPIRES="$STALE_MS"   # b credential claims to be long dead
reset_cache
mk_handoff a; H="$MK_HANDOFF_OUT"
export_env "$H"
OUT="$(bash "$SWITCH_BIN" --handoff "$H" 2>&1)"; RC=$?
check_rc "$RC" 0 "case4 rc=0 (switched onto stale-expiresAt account)"
check_grep "$OUT" 'observed_next_pick=b' "case4 observed_next_pick=b"
export SWITCH_TEST_B_EXPIRES="$FRESH_MS"

# =============================================================================
log "== case 5: registry collapsed to ONE real account -> guard refusal"
reset_cache
printf '{"oauthAccount":{"accountUuid":"uuid-AAAA","organizationUuid":"org-A","emailAddress":"a@test"}}' > "$DIR_B/.claude.json"
mk_handoff a; H="$MK_HANDOFF_OUT"
export_env "$H"
OUT="$(bash "$SWITCH_BIN" --handoff "$H" 2>&1)"; RC=$?
check_rc "$RC" 4 "case5 rc=4 (guard refusal)"
check_grep "$OUT" 'REFUSED reason=registry_not_two_buckets' "case5 names the guard reason"
printf '{"oauthAccount":{"accountUuid":"uuid-BBBB","organizationUuid":"org-B","emailAddress":"b@test"}}' > "$DIR_B/.claude.json"

# =============================================================================
log "== case 6: switch cannot take (b exhausts after confirmation) -> FAILED, never silent success"
write_scenario 100 30 3   # b's 3rd probing (the verify run) reads exhausted
reset_cache
mk_handoff a; H="$MK_HANDOFF_OUT"
export_env "$H"
OUT="$(bash "$SWITCH_BIN" --handoff "$H" 2>&1)"; RC=$?
check_rc "$RC" 5 "case6 rc=5 (switch_not_taken)"
check_grep "$OUT" 'FAILED reason=switch_not_taken' "case6 names switch_not_taken"
check_grep "$OUT" 'target stopped being free' "case6 says the target stopped being free"
check_grep "$(cat "$H/account-switch.log" 2>/dev/null)" 'reason=switch_not_taken' "case6 journalled as failed"

# =============================================================================
log "== case 7: dry-run decides but writes nothing"
write_scenario 100 30
reset_cache
mk_handoff a; H="$MK_HANDOFF_OUT"
export_env "$H"
OUT="$(bash "$SWITCH_BIN" --handoff "$H" --dry-run 2>&1)"; RC=$?
check_rc "$RC" 0 "case7 rc=0"
check_grep "$OUT" 'DRY-RUN would switch a -> b' "case7 names the would-be switch"
check_nofile "$tmp/cache/identity-max_max_a_test/probe-cooldown-until" "case7 wrote no marker"
NEXT="$(independent_pick)"
check_grep "$NEXT" '^profile=b ' "case7 dry-run left ranking intact (b freer)"

# =============================================================================
log "== case 8: switch armed, but the NEXT pick stays on the OLD account -> FAILED (label guard, not the score guard)"
# Shape: the marker is armed for a, then the operator re-logs into the
# exhausted account (SWITCH_TEST_A_RELOGIN: new blob -> the selector's own
# cooldown invalidation deletes the steer) AND the account reads FREE again
# from its 3rd probing (a_drop_after=3: run A and run C still see 100; the
# marker's own probe and the observation run see 10).  So the observation
# run legitimately lands back on a with a NORMAL score (<100) -- the second
# guard (target stopped being free) is silent, and ONLY the label guard can
# catch it.  This is the fixture that distinguishes guard :357 from guard
# :366; case 6 covers the other one.
write_scenario 100 30
printf 'a_drop_after=3\na_drop_five=10\na_drop_seven=5\n' >> "$SCEN"
reset_cache
mk_handoff a; H="$MK_HANDOFF_OUT"
export_env "$H"
export SWITCH_TEST_A_RELOGIN=1
OUT="$(bash "$SWITCH_BIN" --handoff "$H" 2>&1)"; RC=$?
unset SWITCH_TEST_A_RELOGIN
check_rc "$RC" 5 "case8 rc=5 (switch_not_taken)"
check_grep "$OUT" 'FAILED reason=switch_not_taken' "case8 names switch_not_taken"
check_grep "$OUT" 'observed_next_pick=a' "case8 names the OBSERVED label (a)"
check_grep "$OUT" 'expected=b' "case8 names the EXPECTED label (b)"
if grep -q 'target stopped being free' <<<"$OUT"; then fail "case8 fired the LABEL guard, not the score guard" "stdout carries the guard-2 wording"; else pass "case8 fired the LABEL guard, not the score guard"; fi
J8="$(cat "$H/account-switch.log" 2>/dev/null)"
check_grep "$J8" 'reason=switch_not_taken observed=a expected=b detail=next_pick_not_target' "case8 journal: observed+expected+label-guard discriminator"
if grep -q 'target_no_longer_free' <<<"$J8"; then fail "case8 journal has NO guard-2 marker" "found target_no_longer_free"; else pass "case8 journal has NO guard-2 marker"; fi
check_grep "$J8" 'cooldown invalidated: credential fingerprint changed' "case8 failed via re-login cooldown invalidation (the mechanism itself)"
# observation by the TEST, not the script's own claim: steer gone, a freest
NEXT="$(independent_pick)"
check_grep "$NEXT" '^profile=a ' "case8 INDEPENDENT next selector pick is a (steer gone)"

# =============================================================================
printf -- '[TEST] summary: PASS=%d FAIL=%d\n' "$PASS" "$FAIL"
(( FAIL == 0 )) || exit 1
exit 0
