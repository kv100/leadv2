#!/usr/bin/env bash
# tests/test-check-decides-per-account.sh — PER-ACCOUNT-BY-DEFAULT (row 3e55153ca645)
#
# Guards the 2026-09-13 default flip + per-account breaker in
# leadv2-quota-status.sh (contract clause PER-ACCOUNT-BY-DEFAULT,
# docs/handoff/DECISION-LAYER-CONTRACT/decision.md):
#   1. DEFAULT output — no per-account env var set at all — is per account:
#      quota-status runs the selector by default, forcing the selector's
#      MEASUREMENT gate open (LEADV2_CLAUDE_MULTIPROFILE=1 on that one
#      invocation, profile-status.sh:59 precedent). Switching stays opt-in.
#   2. --check refuses when ONE account is exhausted while the blended
#      aggregate still looks healthy (the shipped defect: the go/no-go
#      surface read the blend, not the account — 2026-09-12 the report said
#      43% "safe" while work, the dispatching account, was at 80%).
#   3. --check does NOT refuse merely because one account's meter is
#      unreadable (windows pct "-" -> status unknown, never exhausted;
#      bd7f811eb05c doctrine: an unreadable meter is not a verdict about
#      the account). This pin is what stops the fix becoming an outage.
# Plus: the opt-out (LEADV2_QUOTA_STATUS_PER_ACCOUNT=0) restores the legacy
# aggregate line, and the aggregate breaker arm is untouched.
#
# Hermetic: LEADV2_QUOTA_STATUS_PROFILE_SELECT points at a stub selector that
# prints a profile-select-shaped windows= line and REFUSES to emit windows
# unless the caller forced the measurement gate open — so the default-path
# proof also pins the forcing. No registry, no keychain, no network
# (LEADV2_QUOTA_LIVE points at a nonexistent file: the GLM live read is
# skipped entirely). All per-account env vars are explicitly unset per case
# because a dispatched lane inherits LEADV2_CLAUDE_MULTIPROFILE=1 from the
# dispatcher — the suite must prove the DEFAULT, not the inheritance.
#
# Run: bash scripts/tests/test-check-decides-per-account.sh
# run-all-triggers: leadv2-quota-status

set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/leadv2-temp.sh"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
QUOTA_SH="${SCRIPT_DIR}/../leadv2-quota-status.sh"
# QUOTA-PROVIDER-SIGNAL-GOES-STALE-01: quota-status.sh now refreshes the
# rate_limit_anthropic kv row on read by default -- opt out here so this
# suite stays hermetic (no live probe/keychain/network call).
export LEADV2_QUOTA_REFRESH_ON_READ=0

PASS=0; FAIL=0; ERRORS=()
log()  { printf -- '[TEST] %s\n' "$*"; }
pass() { PASS=$((PASS+1)); log "PASS: $1"; }
fail() { FAIL=$((FAIL+1)); ERRORS+=("FAIL: $1"); log "FAIL: $1"; }

TMP="$(lv2_mktemp_dir "check-per-account")"
DB="$TMP/test.db"
CFG="$TMP/ref.yaml"
trap 'rm -rf "$TMP"' EXIT

printf 'max_5h_input_tokens: 8000000\nmax_weekly_input_tokens: 100000000\nmin_cache_hit_rate: 0.30\n' > "$CFG"
# One tiny claude row: aggregate 5h input %=0, weekly %=0, no kv rate-limit
# capture — the blended aggregate is HEALTHY in every case below unless a
# case injects its own kv. That is the whole point: the blend must never be
# able to hide (or fabricate) what a single account's own meter says.
sqlite3 "$DB" "
CREATE TABLE turn_events(id INTEGER PRIMARY KEY AUTOINCREMENT, session_id TEXT, ts TEXT,
  cc INTEGER DEFAULT 0, cr INTEGER DEFAULT 0, input INTEGER DEFAULT 0, output INTEGER DEFAULT 0,
  model TEXT, tools_json TEXT);
CREATE TABLE kv(key TEXT PRIMARY KEY, value TEXT);
CREATE INDEX turn_events_ts ON turn_events(ts);
INSERT INTO turn_events(session_id,ts,input,cr,output,model) VALUES
  ('claude1', datetime('now','-1 hour'), 1000, 100000, 500, 'claude-opus-5');
"
export LEADV2_BURN_DB="$DB" LEADV2_MAIN_MODEL_CFG="$CFG"
export LEADV2_QUOTA_LIVE="$TMP/no-such-live.sh"   # skip the GLM live read

# Hermetic stand-in for leadv2-claude-profile-select.sh. Prints windows ONLY
# when the caller forced the measurement gate open; any other invocation
# prints the gate-closed shape (nothing), exactly like the real selector's
# own opt-in exit at profile-select.sh:221.
STUB="$TMP/stub-select.sh"
cat > "$STUB" <<'EOS'
#!/usr/bin/env bash
if [[ "${LEADV2_CLAUDE_MULTIPROFILE:-}" != "1" ]]; then
  exit 0
fi
printf 'profile=work config_dir=/x rank_by=usable_now_max consumed_pct=90 usable_now=0.1 source=live reason=binding_window candidates=2 cred=file:/x identity=work/na binding=seven_day:consumed_pct=90,usable_now=0.1 windows=%s\n' "${STUB_WINDOWS:-}"
EOS
chmod +x "$STUB"

# run_default: the DEFAULT invocation — every per-account env var explicitly
# UNSET (a lane inherits LEADV2_CLAUDE_MULTIPROFILE=1 from the dispatcher;
# unset here so the case proves the flip, not the inheritance).
run_default() {
  env -u LEADV2_CLAUDE_MULTIPROFILE \
      -u LEADV2_QUOTA_STATUS_IDENTITY_LINE \
      -u LEADV2_QUOTA_STATUS_PER_ACCOUNT \
      LEADV2_QUOTA_STATUS_PROFILE_SELECT="$STUB" "$@"
}
# run_optout: same, but measurement explicitly opted out.
run_optout() {
  env -u LEADV2_CLAUDE_MULTIPROFILE \
      -u LEADV2_QUOTA_STATUS_IDENTITY_LINE \
      LEADV2_QUOTA_STATUS_PER_ACCOUNT=0 \
      LEADV2_QUOTA_STATUS_PROFILE_SELECT="$STUB" "$@"
}

# 1. syntax
if bash -n "$QUOTA_SH"; then pass "1 bash -n syntax"; else fail "1 bash -n syntax"; fi

# 2. DEFAULT (no env var) — per-account report, worst account first line.
rep="$(STUB_WINDOWS='personal:seven_day=5,usable_now=0.9|work:seven_day=90,usable_now=0.1' run_default bash "$QUOTA_SH" --report)"
line1="$(printf '%s\n' "$rep" | head -1)"
if printf '%s' "$line1" | grep -qE 'identity=work seven_day=90% .*status=exhausted'; then
  pass "2a default --report line1 is per-account (identity=work status=exhausted, no env var set)"
else
  fail "2a default line1 not per-account: $line1"
fi
if printf '%s\n' "$rep" | grep -qE 'identity=personal seven_day=5% usable_now=0\.900 status=safe' \
   && printf '%s\n' "$rep" | grep -qE 'identity=work seven_day=90% usable_now=0\.100 status=exhausted'; then
  pass "2b default --report lists BOTH accounts"
else
  fail "2b per-account lines missing: $(printf '%s\n' "$rep" | grep identity=)"
fi

# 3. DEFAULT --json carries identity-backed top-level status.
json="$(STUB_WINDOWS='personal:seven_day=5,usable_now=0.9|work:seven_day=90,usable_now=0.1' run_default bash "$QUOTA_SH" --json)"
py3="$(printf '%s' "$json" | python3 -c '
import json, sys
d = json.load(sys.stdin)
ok = (d.get("status") == "exhausted" and d.get("status_source") == "identity:work"
      and d.get("identities", {}).get("count") == 2
      and d.get("aggregate", {}).get("status") == "safe")
print("OK" if ok else "BAD: status=%s src=%s agg=%s" % (d.get("status"), d.get("status_source"), d.get("aggregate")))
')"
if [[ "$py3" == OK* ]]; then
  pass "3 default --json: top status=exhausted identity:work, aggregate still safe (surfaces disagree -> account wins)"
else
  fail "3 default --json wrong: $py3"
fi

# 4. Opt-out restores the legacy aggregate first line (escape hatch works).
rep_off="$(STUB_WINDOWS='personal:seven_day=5,usable_now=0.9|work:seven_day=90,usable_now=0.1' run_optout bash "$QUOTA_SH" --report)"
line1_off="$(printf '%s\n' "$rep_off" | head -1)"
if printf '%s' "$line1_off" | grep -qE '^Quota: 5h [0-9]+% ' && ! printf '%s' "$line1_off" | grep -q 'identity='; then
  pass "4 opt-out (LEADV2_QUOTA_STATUS_PER_ACCOUNT=0) -> legacy aggregate line"
else
  fail "4 opt-out line wrong: $line1_off"
fi

# 5. PIN 2: --check refuses when ONE account is exhausted, blend healthy.
set +e
STUB_WINDOWS='personal:seven_day=5,usable_now=0.9|work:seven_day=90,usable_now=0.1' run_default bash "$QUOTA_SH" --check >/dev/null 2>"$TMP/check_exh.err"; rc_exh=$?
set -e
if [[ $rc_exh -eq 1 ]] && grep -q 'QUOTA-EXHAUSTED: identity=work seven_day=90%' "$TMP/check_exh.err"; then
  pass "5 --check rc=1 on ONE exhausted account (blend 5h 0%/wk 0% healthy) — refusal names identity=work"
else
  fail "5 --check rc=$rc_exh (want 1); stderr: $(cat "$TMP/check_exh.err")"
fi

# 6. PIN 3: unreadable meter on one account does NOT refuse.
set +e
STUB_WINDOWS='personal:seven_day=-|work:seven_day=10,usable_now=0.9' run_default bash "$QUOTA_SH" --check >/dev/null 2>"$TMP/check_unk.err"; rc_unk=$?
set -e
if [[ $rc_unk -eq 0 ]] && ! grep -q 'QUOTA-EXHAUSTED' "$TMP/check_unk.err"; then
  pass "6 --check rc=0 with one UNREADABLE meter (personal pct \"-\"; unknown != exhausted)"
else
  fail "6 --check rc=$rc_unk (want 0); stderr: $(cat "$TMP/check_unk.err")"
fi

# 7. PIN 3 (representation): the unreadable account is reported as
#    unmeasurable (pct null, status unknown), never folded into a number.
json_unk="$(STUB_WINDOWS='personal:seven_day=-|work:seven_day=10,usable_now=0.9' run_default bash "$QUOTA_SH" --json)"
py7="$(printf '%s' "$json_unk" | python3 -c '
import json, sys
d = json.load(sys.stdin)
lst = d.get("identities", {}).get("list", [])
pers = next((i for i in lst if i.get("label") == "personal"), {})
ok = (pers.get("pct") is None and pers.get("status") == "unknown"
      and d.get("identities", {}).get("worst", {}).get("label") == "work")
print("OK" if ok else "BAD: personal=%s worst=%s" % (pers, d.get("identities", {}).get("worst")))
')"
if [[ "$py7" == OK* ]]; then
  pass "7 unreadable account represented unmeasurable (pct null status unknown), worst stays work"
else
  fail "7 unreadable representation wrong: $py7"
fi

# 8. PIN 3 (all meters unreadable): no fabricated verdict, no refusal.
set +e
STUB_WINDOWS='personal:seven_day=-|work:seven_day=-' run_default bash "$QUOTA_SH" --check >/dev/null 2>&1; rc_none=$?
set -e
json_none="$(STUB_WINDOWS='personal:seven_day=-|work:seven_day=-' run_default bash "$QUOTA_SH" --json)"
py8="$(printf '%s' "$json_none" | python3 -c '
import json, sys
d = json.load(sys.stdin)
ok = (d.get("identities", {}).get("worst") is None and d.get("status_source") == "aggregate")
print("OK" if ok else "BAD: worst=%s source=%s" % (d.get("identities", {}).get("worst"), d.get("status_source")))
')"
if [[ $rc_none -eq 0 ]] && [[ "$py8" == OK* ]]; then
  pass "8 all meters unreadable -> rc=0, worst=null, status_source=aggregate (silence never refuses)"
else
  fail "8 all-unreadable wrong: rc=$rc_none $py8"
fi

# 9. Identity warn does not refuse (parity: only exhausted refuses).
set +e
STUB_WINDOWS='personal:seven_day=5,usable_now=0.9|work:seven_day=80,usable_now=0.2' run_default bash "$QUOTA_SH" --check >/dev/null 2>"$TMP/check_warn.err"; rc_warn=$?
set -e
if [[ $rc_warn -eq 0 ]] && grep -q 'QUOTA-WARN: identity=work seven_day=80%' "$TMP/check_warn.err"; then
  pass "9 warn identity -> rc=0 with QUOTA-WARN naming the account"
else
  fail "9 warn case wrong: rc=$rc_warn stderr: $(cat "$TMP/check_warn.err")"
fi

# 10. Aggregate breaker arm intact (regression guard): fresh unhealthy RL kv
#     capture still refuses with the aggregate line, selector out of play.
rl_json="$(printf '{"status":"cooldown","overageStatus":"normal","resetsAt":1790000000,"captured_epoch":%d}' "$(date +%s)")"
sqlite3 "$DB" "INSERT INTO kv(key,value) VALUES('rate_limit_anthropic','${rl_json}');"
set +e
env -u LEADV2_CLAUDE_MULTIPROFILE -u LEADV2_QUOTA_STATUS_IDENTITY_LINE -u LEADV2_QUOTA_STATUS_PER_ACCOUNT \
  LEADV2_QUOTA_STATUS_PROFILE_SELECT="$TMP/no-such-selector.sh" bash "$QUOTA_SH" --check >/dev/null 2>"$TMP/check_agg.err"; rc_agg=$?
set -e
if [[ $rc_agg -eq 1 ]] && grep -q 'QUOTA-EXHAUSTED: Anthropic 5h' "$TMP/check_agg.err"; then
  pass "10 aggregate arm intact (RL kv unhealthy -> rc=1 via Anthropic 5h line)"
else
  fail "10 aggregate arm broken: rc=$rc_agg stderr: $(cat "$TMP/check_agg.err")"
fi

echo
echo "PASS=$PASS FAIL=$FAIL"
if [[ $FAIL -gt 0 ]]; then printf '%s\n' "${ERRORS[@]}" >&2; exit 1; fi
log "ALL PASS — the breaker decides on the account, the blend never hides it, silence never refuses."
exit 0
