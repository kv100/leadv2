#!/usr/bin/env bash
# tests/test-claude-profile-select.sh — CLAUDE-MULTIPROFILE-QUOTA-02
#
# Hermetic unit + integration coverage for leadv2-claude-profile-select.sh,
# lib/leadv2-claude-profile-pick.py, and the claude-subsession.sh integration.
# No network, no keychain: the probe is stubbed via LEADV2_CLAUDE_PROFILE_PROBE
# (a fixture python script echoing canned JSON keyed by the per-profile cache
# dir the selector exports), and the registry lives under mktemp -d.
#
# T1..T10 mirror the design table; the last block exercises the acceptance
# observable end-to-end with a fake `claude` binary on PATH.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
# Overridable for the negative control: point LEADV2_TEST_SELECT_BIN at a
# mutated copy of the selector and the whole suite must go red.
SELECT_BIN="${LEADV2_TEST_SELECT_BIN:-${SCRIPTS_ROOT}/leadv2-claude-profile-select.sh}"
PICK_BIN="${SCRIPTS_ROOT}/lib/leadv2-claude-profile-pick.py"
SUBSESSION_SH="${SCRIPTS_ROOT}/claude-subsession.sh"

PASS=0; FAIL=0
log()  { printf -- '[TEST] %s\n' "$*"; }
pass() { PASS=$((PASS + 1)); log "PASS: $1"; }
fail() { FAIL=$((FAIL + 1)); log "FAIL: $1 -- ${2:-}"; }
check_grep() { # <haystack> <pattern> <label>
  if grep -qE -- "$2" <<<"$1"; then pass "$3"; else fail "$3" "no match for '$2' in: $1"; fi
}
check_nogrep() { # <haystack> <pattern> <label>
  if grep -qE -- "$2" <<<"$1"; then fail "$3" "unexpected match for '$2' in: $1"; else pass "$3"; fi
}

unset LEADV2_CLAUDE_MULTIPROFILE LEADV2_CLAUDE_PROFILES_FILE \
      LEADV2_CLAUDE_PROFILE_PROBE LEADV2_CLAUDE_PROFILE_TIMEOUT \
      LEADV2_QUOTA_CACHE_DIR LEADV2_ANTHROPIC_ACTIVE_SERVICE CLAUDE_CONFIG_DIR

tmp="$(mktemp -d "${TMPDIR:-/tmp}/claude-profile-select.XXXXXX")"
trap 'rm -rf "$tmp"' EXIT
FIX="${tmp}/fixtures"; CACHE="${tmp}/cache"; REG="${tmp}/registry.tsv"
mkdir -p "$FIX" "$CACHE" "$tmp/dir-alpha" "$tmp/dir-beta"

# T12/LEAD-FINAL-FIXES-01: the selector health-checks the inherited default
# slot too; pin it to a healthy fixture so the suite never touches the real
# ~/.claude or Keychain (T9b caught exactly that leak before this pin).
mkdir -p "$tmp/dir-default"
printf '{"claudeAiOauth":{"accessToken":"sk-ant-fixture","subscriptionType":"max","expiresAt":%s}}' \
  "$(( $(date +%s) * 1000 + 3600000 ))" > "$tmp/dir-default/.credentials.json"
printf '{"oauthAccount":{"emailAddress":"default@fixture.test"}}' > "$tmp/dir-default/.claude.json"
export LEADV2_CLAUDE_PROFILE_DEFAULT_DIR="$tmp/dir-default"

# Probe stub: canned JSON keyed by the per-profile cache dir the selector
# exports (…/profile-<label>).  A label starting with "hang" sleeps forever.
# STUB_SEEN (optional): appends each probe's LEADV2_QUOTA_CACHE_DIR so tests
# can assert how usage buckets were keyed (T14: same identity -> one bucket).
STUB="${tmp}/stub-probe.py"
cat > "$STUB" <<'PY'
#!/usr/bin/env python3
import json, os, sys, time
# T12: the selector now keys LEADV2_QUOTA_CACHE_DIR by derived identity, not
# by registry label (that's the fix under test), so the fixture stub keys off
# LEADV2_CLAUDE_PROFILE_LABEL directly instead of parsing it out of the cache
# dir path.
label = os.environ.get("LEADV2_CLAUDE_PROFILE_LABEL", "")
if label.startswith("hang"):
    time.sleep(300)
seen = os.environ.get("STUB_SEEN")
if seen:
    with open(seen, "a") as f:
        f.write(os.environ.get("LEADV2_QUOTA_CACHE_DIR", "") + "\n")
path = os.path.join(os.environ["STUB_FIXDIR"], label + ".json")
if os.path.exists(path):
    print(open(path).read())
else:
    print(json.dumps({"provider": "anthropic", "status": "unknown", "accounts": []}))
PY

# Canned live account payload with the given worst-window percentages.
acct_json() { # <five_hour_pct> <seven_day_pct>
  printf '{"provider":"anthropic","status":"ok","accounts":[{"entry_suffix":"file","service":"file:stub","status":"ok","five_hour_pct":%s,"seven_day_pct":%s,"active":true,"account_label":"stub"}],"active_account":"stub","fetched_at":"2026-08-25T00:00:00Z"}' "$1" "$2"
}
acct_json 20 10 > "$FIX/alpha.json"
acct_json 80 70 > "$FIX/beta.json"
acct_json 50 40 > "$FIX/tie-a.json"
acct_json 50 40 > "$FIX/tie-b.json"
printf '{"provider":"anthropic","status":"unknown","accounts":[]}' > "$FIX/dead.json"

run_select() { # -> sets OUT / ERR / RC
  OUT="$(env STUB_FIXDIR="$FIX" "$@" bash "$SELECT_BIN" 2>"$tmp/select.err")"; RC=$?
  ERR="$(cat "$tmp/select.err")"
}

base_env() {
  printf '%s\n' "LEADV2_CLAUDE_MULTIPROFILE=1" \
    "LEADV2_CLAUDE_PROFILES_FILE=$REG" \
    "LEADV2_CLAUDE_PROFILE_PROBE=$STUB" \
    "LEADV2_QUOTA_CACHE_DIR=$CACHE"
}

# ============================================================================
echo "=== T1: opt-in unset -> inert ==="
printf 'alpha\t%s\tfile:%s/cred.json\n' "$tmp/dir-alpha" "$tmp/dir-alpha" > "$REG"
printf 'beta\t%s\tfile:%s/cred.json\n' "$tmp/dir-beta" "$tmp/dir-beta" >> "$REG"
run_select LEADV2_CLAUDE_PROFILES_FILE="$REG" LEADV2_CLAUDE_PROFILE_PROBE="$STUB" STUB_FIXDIR="$FIX"
[[ -z "$OUT" && "$RC" -eq 0 ]] && pass "T1: no stdout, exit 0" || fail "T1" "out='$OUT' rc=$RC"

# ============================================================================
echo "=== T2: registry missing -> single_profile ==="
run_select LEADV2_CLAUDE_MULTIPROFILE=1 "LEADV2_CLAUDE_PROFILES_FILE=$tmp/nope.tsv" \
  "LEADV2_CLAUDE_PROFILE_PROBE=$STUB" STUB_FIXDIR="$FIX"
check_grep "$OUT" '^profile=- reason=single_profile$' 'T2: reason=single_profile'
[[ "$RC" -eq 0 ]] && pass "T2: exit 0" || fail "T2 exit" "rc=$RC"

# ============================================================================
echo "=== T3: 1 valid entry -> single_profile (fallback preserved) ==="
printf 'alpha\t%s\tfile:%s/cred.json\n' "$tmp/dir-alpha" "$tmp/dir-alpha" > "$REG"
run_select $(base_env)
check_grep "$OUT" '^profile=- reason=single_profile$' 'T3: reason=single_profile'
[[ "$RC" -eq 0 ]] && pass "T3: exit 0" || fail "T3 exit" "rc=$RC"

# ============================================================================
echo "=== T4: 20% vs 80% -> picks the 20% label ==="
printf 'alpha\t%s\tfile:%s/cred.json\n' "$tmp/dir-alpha" "$tmp/dir-alpha" > "$REG"
printf 'beta\t%s\tfile:%s/cred.json\n' "$tmp/dir-beta" "$tmp/dir-beta" >> "$REG"
run_select $(base_env)
check_grep "$OUT" '^profile=alpha config_dir=.*/dir-alpha score=20 source=live reason=worst_window candidates=2 cred=file:[^ ]+ identity=unknown/na$' 'T4: picks alpha score=20 live'
[[ "$RC" -eq 0 ]] && pass "T4: exit 0" || fail "T4 exit" "rc=$RC"

# ============================================================================
echo "=== T5: one unknown, one ok -> picks ok, source=live ==="
printf 'dead\t%s\tfile:%s/cred.json\n' "$tmp/dir-alpha" "$tmp/dir-alpha" > "$REG"
printf 'beta\t%s\tfile:%s/cred.json\n' "$tmp/dir-beta" "$tmp/dir-beta" >> "$REG"
run_select $(base_env)
check_grep "$OUT" '^profile=beta .*score=80 source=live reason=worst_window candidates=2 cred=file:[^ ]+ identity=unknown/na$' 'T5: picks the ok profile'

# ============================================================================
echo "=== T6: both unknown -> first registry entry, all_unknown ==="
printf 'dead\t%s\tfile:%s/cred.json\n' "$tmp/dir-alpha" "$tmp/dir-alpha" > "$REG"
printf 'dead2\t%s\tfile:%s/cred.json\n' "$tmp/dir-beta" "$tmp/dir-beta" >> "$REG"
cp "$FIX/dead.json" "$FIX/dead2.json"
run_select $(base_env)
check_grep "$OUT" '^profile=dead .*score=101 source=unknown reason=all_unknown candidates=2 cred=file:[^ ]+ identity=unknown/na$' 'T6: first entry, all_unknown'

# ============================================================================
echo "=== T7: malformed line + email-shaped label -> skipped, one warning each ==="
{
  printf 'alpha\t%s\tfile:%s/cred.json\n' "$tmp/dir-alpha" "$tmp/dir-alpha"
  printf 'founder@anthropic.com\t%s\n' "$tmp/dir-beta"
  printf 'just-a-label-no-dir\n'
  printf 'beta\t%s\tfile:%s/cred.json\n' "$tmp/dir-beta" "$tmp/dir-beta"
} > "$REG"
run_select $(base_env)
check_grep "$OUT" '^profile=alpha .*candidates=2 cred=file:[^ ]+ identity=unknown/na$' 'T7: bad lines skipped, both good ones used'
w_count="$(grep -c 'WARN: registry line .* skipped' <<<"$ERR")"
[[ "$w_count" -eq 2 ]] && pass "T7: exactly two skip warnings" || fail "T7 warnings" "count=$w_count err=$ERR"

# ============================================================================
echo "=== T8: probe hangs -> timeout, single_profile, exit 0 under 15s ==="
mkdir -p "$tmp/dir-hang1" "$tmp/dir-hang2"
printf 'hang1\t%s\tfile:%s/cred.json\n' "$tmp/dir-hang1" "$tmp/dir-hang1" > "$REG"
printf 'hang2\t%s\tfile:%s/cred.json\n' "$tmp/dir-hang2" "$tmp/dir-hang2" >> "$REG"
start=$(date +%s)
run_select $(base_env) LEADV2_CLAUDE_PROFILE_TIMEOUT=2
elapsed=$(( $(date +%s) - start ))
check_grep "$OUT" '^profile=- reason=single_profile$' 'T8: single_profile on total probe timeout'
[[ "$RC" -eq 0 ]] && pass "T8: exit 0" || fail "T8 exit" "rc=$RC"
if (( elapsed < 15 )); then pass "T8: completed in ${elapsed}s (<15s)"; else fail "T8 duration" "${elapsed}s"; fi

# ============================================================================
echo "=== T9: leak scan — no token, email, or path on label-only surfaces ==="
printf 'alpha\t%s\tfile:%s/cred.json\n' "$tmp/dir-alpha" "$tmp/dir-alpha" > "$REG"
printf 'beta\t%s\tfile:%s/cred.json\n' "$tmp/dir-beta" "$tmp/dir-beta" >> "$REG"
run_select $(base_env)
# stdout legitimately carries config_dir (consumed by the caller, never journalled)
check_grep "$OUT" 'config_dir=.*/dir-' 'T9a: config_dir present on selector stdout'
check_nogrep "$ERR" 'sk-ant|@' 'T9b: selector stderr has no token or email'
# identity=<subscriptionType>/<email-or-na> legitimately carries ONE slash (T12);
# a real leaked path (config_dir, cred file) has at least two segments/slashes.
check_nogrep "$ERR" '/[^[:space:]]+/' 'T9c: selector stderr has no path'

# ============================================================================
echo "=== T10: determinism — identical scores, same pick over 5 runs ==="
printf 'tie-a\t%s\tfile:%s/cred.json\n' "$tmp/dir-alpha" "$tmp/dir-alpha" > "$REG"
printf 'tie-b\t%s\tfile:%s/cred.json\n' "$tmp/dir-beta" "$tmp/dir-beta" >> "$REG"
det_ok=1
for _r in 1 2 3 4 5; do
  run_select $(base_env)
  grep -q '^profile=tie-a ' <<<"$OUT" || det_ok=0
done
(( det_ok )) && pass "T10: registry-order tie-break stable over 5 runs" || fail "T10 determinism" "unstable"

# ============================================================================
echo "=== Integration: acceptance observable via claude-subsession.sh ==="
repo="$tmp/repo"; mkdir -p "$repo/.claude/agents" "$repo/docs/handoff" "$repo/docs/leadv2" "$repo/bin"
printf 'sessions: []\n' > "$repo/docs/leadv2/active.yaml"
printf 'Test role body.\n' > "$repo/.claude/agents/developer.md"
printf 'Test mission.\n' > "$repo/mission.md"
printf 'alpha\t%s\tfile:%s/cred.json\n' "$tmp/dir-alpha" "$tmp/dir-alpha" > "$REG"
printf 'beta\t%s\tfile:%s/cred.json\n' "$tmp/dir-beta" "$tmp/dir-beta" >> "$REG"
cat > "$repo/bin/claude" <<SH
#!/usr/bin/env bash
printf 'CLAUDE_CONFIG_DIR=%s\n' "\${CLAUDE_CONFIG_DIR:-<unset>}" > "\$I9_CAPTURE"
printf 'LEADV2_ANTHROPIC_ACTIVE_SERVICE=%s\n' "\${LEADV2_ANTHROPIC_ACTIVE_SERVICE:-<unset>}" >> "\$I9_CAPTURE"
printf '{"type":"assistant","message":{"usage":{"input_tokens":10,"output_tokens":5}}}\n'
exit 0
SH
chmod +x "$repo/bin/claude"
cap="$tmp/captured-config-dir"
int_err="$tmp/int.err"
I9_CAPTURE="$cap" STUB_FIXDIR="$FIX" \
  PROJECT_ROOT="$repo" PATH="$repo/bin:$PATH" LEADV2_ROUTE_BANDIT=0 \
  LEADV2_CLAUDE_MULTIPROFILE=1 LEADV2_CLAUDE_PROFILES_FILE="$REG" \
  LEADV2_CLAUDE_PROFILE_PROBE="$STUB" LEADV2_QUOTA_CACHE_DIR="$CACHE" \
  bash "$SUBSESSION_SH" --role developer --model sonnet --task-id PROFILE-CL \
    --mission-file "$repo/mission.md" --wait >/dev/null 2>"$int_err" || true
cap_val="$(cat "$cap" 2>/dev/null)"
check_grep "$cap_val" "^CLAUDE_CONFIG_DIR=$tmp/dir-alpha$" 'I1: child sees only the selected config_dir'
n_prof_lines="$(grep -c '^\[claude-profile\]' "$int_err")"
if [[ "$n_prof_lines" -eq 1 ]]; then pass "I2: exactly one [claude-profile] stderr line"; else fail "I2" "count=$n_prof_lines"; fi
check_grep "$(cat "$int_err")" '^\[claude-profile\] selected=alpha score=20 source=live candidates=2 cred_kind=file identity=unknown/na$' 'I2b: label-only stderr line shape'
hlog="$repo/docs/handoff/PROFILE-CL/claude-profile.log"
[[ -f "$hlog" ]] && pass "I3: handoff claude-profile.log exists" || fail "I3" "missing $hlog"
if [[ -f "$hlog" ]]; then
  check_grep "$(cat "$hlog")" '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z \[claude-profile\] selected=alpha score=20 source=live candidates=2 cred_kind=file identity=unknown/na$' 'I4: ISO-prefixed label-only handoff line'
  check_nogrep "$(cat "$hlog")" 'sk-ant' 'I5a: handoff log has no token'
  check_nogrep "$(cat "$hlog")" '/[^[:space:]]+/' 'I5b: handoff log has no path'
fi
check_nogrep "$(grep '^\[claude-profile\]' "$int_err")" 'sk-ant' 'I6a: profile stderr line has no token'
check_nogrep "$(grep '^\[claude-profile\]' "$int_err")" '/[^[:space:]]+/' 'I6b: profile stderr line has no path'

# ============================================================================
echo "=== Integration: flag unset -> no profile line, lane unchanged ==="
rm -f "$cap"; : > "$cap"
int_err2="$tmp/int2.err"; : > "$int_err2"
I9_CAPTURE="$cap" STUB_FIXDIR="$FIX" \
  PROJECT_ROOT="$repo" PATH="$repo/bin:$PATH" LEADV2_ROUTE_BANDIT=0 \
  LEADV2_CLAUDE_PROFILES_FILE="$REG" LEADV2_CLAUDE_PROFILE_PROBE="$STUB" \
  LEADV2_QUOTA_CACHE_DIR="$CACHE" \
  bash "$SUBSESSION_SH" --role developer --model sonnet --task-id PROFILE-CL2 \
    --mission-file "$repo/mission.md" --wait >/dev/null 2>"$int_err2" || true
cap_val="$(cat "$cap" 2>/dev/null)"
check_grep "$cap_val" '^CLAUDE_CONFIG_DIR=<unset>$' 'I7: no CLAUDE_CONFIG_DIR forced when flag unset'
if grep -q '^\[claude-profile\]' "$int_err2"; then
  fail "I8: no [claude-profile] line when flag unset" "line present"
else
  pass "I8: no [claude-profile] line when flag unset"
fi
[[ ! -f "$repo/docs/handoff/PROFILE-CL2/claude-profile.log" ]] \
  && pass "I9: no handoff claude-profile.log when flag unset" \
  || fail "I9" "unexpected log"

# ============================================================================
# T12 (CLAUDE-PROFILE-SELECT-FINISH-01 follow-up): identity derived from the
# credential itself, expired-token exclusion, all-expired refusal. Fixture
# keychain-shaped JSONs are plain temp files (never the real keychain); the
# hard-coded `security` binary is swapped for a stub via
# LEADV2_CLAUDE_PROFILE_SECURITY_BIN so the keychain: path is exercised too.
now_ms=$(( $(date +%s) * 1000 ))
future_ms=$(( now_ms + 3600000 ))
past_ms=$(( now_ms - 3600000 ))
cred_json() { # <subscription_type> <expires_at_ms>
  printf '{"claudeAiOauth":{"accessToken":"sk-ant-should-never-be-read","refreshToken":"sk-ant-r","subscriptionType":"%s","expiresAt":%s}}' "$1" "$2"
}
mkdir -p "$tmp/dir-team" "$tmp/dir-stale" "$tmp/dir-allexp-a" "$tmp/dir-allexp-b"
cred_json team "$future_ms" > "$tmp/dir-team/cred.json"
cred_json max  "$past_ms"   > "$tmp/dir-stale/cred.json"
cred_json max  "$past_ms"   > "$tmp/dir-allexp-a/cred.json"
cred_json pro  "$past_ms"   > "$tmp/dir-allexp-b/cred.json"
acct_json 30 25 > "$FIX/personal.json"

# --- keychain-path fixture: a "security" stub that maps -s <service> to a
# fixture file under KEYFIX, keyed by service name -- never touches the real
# Keychain, and never prints the fixture's accessToken/refreshToken to
# anything the selector itself echoes.
KEYFIX="$tmp/keyfix"; mkdir -p "$KEYFIX"
cred_json team "$future_ms" > "$KEYFIX/svc-team.json"
SECURITY_STUB="$tmp/security-stub.sh"
cat > "$SECURITY_STUB" <<SH
#!/usr/bin/env bash
# args: find-generic-password -s <service> -w
svc=""
prev=""
for a in "\$@"; do
  if [[ "\$prev" == "-s" ]]; then svc="\$a"; fi
  prev="\$a"
done
f="$KEYFIX/\${svc}.json"
[[ -f "\$f" ]] && cat "\$f" || exit 44
SH
chmod +x "$SECURITY_STUB"

echo "=== T11 (NC-a): label='personal' but credential subscriptionType=team -> identity=team/na ==="
printf 'personal\t%s\tfile:%s/cred.json\n' "$tmp/dir-team" "$tmp/dir-team" > "$REG"
printf 'beta\t%s\tfile:%s/cred.json\n' "$tmp/dir-beta" "$tmp/dir-beta" >> "$REG"
run_select $(base_env)
check_grep "$OUT" '^profile=personal .*identity=team/na$' 'T11a: identity derived from credential (team), not label (personal)'
check_grep "$OUT" 'score=30 source=live' 'T11b: personal/team profile scored and picked'
[[ "$RC" -eq 0 ]] && pass "T11: exit 0" || fail "T11 exit" "rc=$RC"

echo "=== T11k (NC-a, keychain path): same mismatch via keychain: credential_source ==="
printf 'personal\t%s\tkeychain:svc-team\n' "$tmp/dir-team" > "$REG"
printf 'beta\t%s\tfile:%s/cred.json\n' "$tmp/dir-beta" "$tmp/dir-beta" >> "$REG"
run_select $(base_env) LEADV2_CLAUDE_PROFILE_SECURITY_BIN="$SECURITY_STUB"
check_grep "$OUT" '^profile=personal .*identity=team/na$' 'T11k: identity derived via keychain: credential_source too'
check_nogrep "$OUT" 'sk-ant' 'T11k-leak: selected-profile stdout carries no access/refresh token'
check_nogrep "$ERR" 'sk-ant' 'T11k-leak2: selector stderr carries no access/refresh token'

echo "=== T12 (NC-b): expired credential -> WARN token_expired + excluded from scoring ==="
printf 'stale\t%s\tfile:%s/cred.json\n' "$tmp/dir-stale" "$tmp/dir-stale" > "$REG"
printf 'alpha\t%s\tfile:%s/cred.json\n' "$tmp/dir-alpha" "$tmp/dir-alpha" >> "$REG"
printf 'beta\t%s\tfile:%s/cred.json\n' "$tmp/dir-beta" "$tmp/dir-beta" >> "$REG"
run_select $(base_env)
check_grep "$ERR" 'WARN: registry line 1 skipped: token_expired label=stale identity=max/na' 'T12a: WARN token_expired names label+identity'
check_grep "$OUT" '^profile=alpha .*candidates=2 ' 'T12b: expired entry excluded -- candidates=2, not 3'
check_nogrep "$OUT" '^profile=stale ' 'T12c: expired profile never wins'
[[ "$RC" -eq 0 ]] && pass "T12: exit 0" || fail "T12 exit" "rc=$RC"

echo "=== T13 (NC-c): all candidates expired -> named refusal, not a silent pick ==="
printf 'exp-a\t%s\tfile:%s/cred.json\n' "$tmp/dir-allexp-a" "$tmp/dir-allexp-a" > "$REG"
printf 'exp-b\t%s\tfile:%s/cred.json\n' "$tmp/dir-allexp-b" "$tmp/dir-allexp-b" >> "$REG"
run_select $(base_env)
check_grep "$OUT" '^profile=- reason=all_expired$' 'T13a: named refusal, not single_profile or a stale pick'
w_count="$(grep -c 'WARN: registry line .* skipped: token_expired' <<<"$ERR")"
[[ "$w_count" -eq 2 ]] && pass "T13b: both expired entries warned" || fail "T13b" "count=$w_count err=$ERR"
[[ "$RC" -eq 0 ]] && pass "T13: exit 0" || fail "T13 exit" "rc=$RC"

# ============================================================================
# T12 final fixes (LEAD-FINAL-FIXES-01): honest profile registry -- the label
# is display-only; identity comes from the slot's own JSON (.claude.json for
# the email, credential for sub/expiry), bucketing keys on that identity, and
# every lie the registry can tell is warned loudly, fail-open.
mk_slot() { # <dir> <sub> <email|-> <expiry_ms> [account_uuid]
  mkdir -p "$1"
  printf '{"claudeAiOauth":{"accessToken":"sk-ant-fixture","refreshToken":"sk-ant-r","subscriptionType":"%s","expiresAt":%s}}' \
    "$2" "$4" > "$1/.credentials.json"
  if [[ "$3" == "-" ]]; then
    rm -f "$1/.claude.json"
  elif [[ -n "${5:-}" ]]; then
    printf '{"oauthAccount":{"emailAddress":"%s","accountUuid":"%s"}}' "$3" "$5" > "$1/.claude.json"
  else
    printf '{"oauthAccount":{"emailAddress":"%s"}}' "$3" > "$1/.claude.json"
  fi
}

echo "=== T14: both slots = SAME account -> refuse the round (reason=same_account), email-free WARN ==="
mkdir -p "$tmp/dir-same1" "$tmp/dir-same2"
mk_slot "$tmp/dir-same1" team  "shared@fixture.test" "$future_ms"
mk_slot "$tmp/dir-same2" team  "shared@fixture.test" "$future_ms"
acct_json 40 30 > "$FIX/same1.json"; acct_json 40 30 > "$FIX/same2.json"
printf 'same1\t%s\tfile:%s/.credentials.json\n' "$tmp/dir-same1" "$tmp/dir-same1" > "$REG"
printf 'same2\t%s\tfile:%s/.credentials.json\n' "$tmp/dir-same2" "$tmp/dir-same2" >> "$REG"
: > "$tmp/seen"
alarm="$tmp/alarm.json"; rm -f "$alarm"
run_select $(base_env) "STUB_SEEN=$tmp/seen" "LEADV2_CLAUDE_PROFILE_SECURITY_BIN=$SECURITY_STUB" \
  "LEADV2_CLAUDE_ACCOUNT_ALARM_FILE=$alarm"
check_grep "$ERR" 'WARN: same_account label=same1 label=same2 sub=team account=unresolved' 'T14a: same_account warn is email-free (no accountUuid in fixture -> unresolved)'
check_nogrep "$ERR" 'shared@fixture\.test' 'T14a2: same_account warn never carries the email half'
check_grep "$OUT" '^profile=- reason=same_account$' 'T14b: selector refuses the round instead of pinning a dir'
[[ ! -s "$tmp/seen" ]] && pass "T14c: no probe ran (refused before probing)" || fail "T14c" "seen=$(cat "$tmp/seen")"
[[ -f "$alarm" ]] && grep -q '"kind":"same_account"' "$alarm" \
  && pass "T14d: alarm file written on detect" || fail "T14d" "alarm=$([[ -f "$alarm" ]] && cat "$alarm" || echo MISSING)"
check_nogrep "$(cat "$alarm" 2>/dev/null)" '@' 'T14e: alarm file carries no email'
[[ "$RC" -eq 0 ]] && pass "T14: exit 0 (fail-open availability -- caller falls back to single-profile)" || fail "T14 exit" "rc=$RC"

echo "=== T21: same accountUuid, DIFFERING email case -> still caught (uuid beats string identity) ==="
mkdir -p "$tmp/dir-uuid1" "$tmp/dir-uuid2"
mk_slot "$tmp/dir-uuid1" team "Shared@Fixture.test" "$future_ms" "acct-fixture-000111222333"
mk_slot "$tmp/dir-uuid2" team "shared@fixture.test" "$future_ms" "acct-fixture-000111222333"
printf 'uuid1\t%s\tfile:%s/.credentials.json\n' "$tmp/dir-uuid1" "$tmp/dir-uuid1" > "$REG"
printf 'uuid2\t%s\tfile:%s/.credentials.json\n' "$tmp/dir-uuid2" "$tmp/dir-uuid2" >> "$REG"
: > "$tmp/seen"
run_select $(base_env) "STUB_SEEN=$tmp/seen" "LEADV2_CLAUDE_PROFILE_SECURITY_BIN=$SECURITY_STUB"
check_grep "$ERR" 'WARN: same_account label=uuid1 label=uuid2 sub=team account=\.\.222333' 'T21a: uuid-keyed match reports the account-uuid tail'
check_grep "$OUT" '^profile=- reason=same_account$' 'T21b: refused even though the two derived identities differ as strings'
[[ ! -s "$tmp/seen" ]] && pass "T21c: no probe ran" || fail "T21c" "seen=$(cat "$tmp/seen")"
[[ "$RC" -eq 0 ]] && pass "T21: exit 0" || fail "T21 exit" "rc=$RC"

echo "=== T15: label/expect vs derived identity -> WARN label_mismatch, bucket by identity ==="
mkdir -p "$tmp/dir-mism"
mk_slot "$tmp/dir-mism" max_20x "vkk@fixture.test" "$future_ms"
acct_json 25 20 > "$FIX/mism-team.json"
printf 'mism-team\t%s\tfile:%s/.credentials.json\tteam\n' "$tmp/dir-mism" "$tmp/dir-mism" > "$REG"
printf 'beta\t%s\tfile:%s/cred.json\n' "$tmp/dir-beta" "$tmp/dir-beta" >> "$REG"
run_select $(base_env) "LEADV2_CLAUDE_PROFILE_SECURITY_BIN=$SECURITY_STUB"
check_grep "$ERR" 'WARN: label_mismatch label=mism-team expected=team identity=max_20x/vkk@fixture\.test' 'T15a: label_mismatch warn carries expected + derived'
check_grep "$OUT" '^profile=mism-team .*identity=max_20x/vkk@fixture\.test' 'T15b: reported/bucketed identity is the DERIVED one, not the label claim'
[[ "$RC" -eq 0 ]] && pass "T15: exit 0 (fail-open)" || fail "T15 exit" "rc=$RC"

echo "=== T16: missing .claude.json -> WARN identity_email_unresolved, fail-open ==="
mkdir -p "$tmp/dir-nojson"
mk_slot "$tmp/dir-nojson" pro "-" "$future_ms"
acct_json 10 5 > "$FIX/nojson.json"
printf 'nojson\t%s\tfile:%s/.credentials.json\n' "$tmp/dir-nojson" "$tmp/dir-nojson" > "$REG"
printf 'beta\t%s\tfile:%s/cred.json\n' "$tmp/dir-beta" "$tmp/dir-beta" >> "$REG"
run_select $(base_env) "LEADV2_CLAUDE_PROFILE_SECURITY_BIN=$SECURITY_STUB"
check_grep "$ERR" 'WARN: registry line 1: identity_email_unresolved \(no readable \.claude\.json\) label=nojson identity=pro/na -- fail-open' 'T16a: identity_email_unresolved warn'
check_grep "$OUT" '^profile=nojson .*identity=pro/na$' 'T16b: entry still selectable (fail-open)'
[[ "$RC" -eq 0 ]] && pass "T16: exit 0" || fail "T16 exit" "rc=$RC"

echo "=== T17: default token expired -> WARN default_token_expired, selection unchanged ==="
mkdir -p "$tmp/dir-def-exp"
mk_slot "$tmp/dir-def-exp" max "defexp@fixture.test" "$past_ms"
printf 'alpha\t%s\tfile:%s/cred.json\n' "$tmp/dir-alpha" "$tmp/dir-alpha" > "$REG"
printf 'beta\t%s\tfile:%s/cred.json\n' "$tmp/dir-beta" "$tmp/dir-beta" >> "$REG"
run_select $(base_env) "LEADV2_CLAUDE_PROFILE_DEFAULT_DIR=$tmp/dir-def-exp" \
  "LEADV2_CLAUDE_PROFILE_SECURITY_BIN=$SECURITY_STUB"
check_grep "$ERR" 'WARN: default_token_expired identity=max/defexp@fixture\.test -- fail-open' 'T17a: default_token_expired warn'
check_grep "$OUT" '^profile=alpha .*score=20 source=live' 'T17b: selection itself unchanged'
[[ "$RC" -eq 0 ]] && pass "T17: exit 0" || fail "T17 exit" "rc=$RC"

echo "=== T18: default credential absent -> WARN default_token_absent, fail-open ==="
mkdir -p "$tmp/dir-def-empty"
run_select $(base_env) "LEADV2_CLAUDE_PROFILE_DEFAULT_DIR=$tmp/dir-def-empty" \
  "LEADV2_CLAUDE_PROFILE_SECURITY_BIN=$SECURITY_STUB"
check_grep "$ERR" 'WARN: default_token_absent \(inherited slot has no readable credential\) -- fail-open' 'T18a: default_token_absent warn'
check_grep "$OUT" '^profile=alpha ' 'T18b: selection proceeds'
[[ "$RC" -eq 0 ]] && pass "T18: exit 0" || fail "T18 exit" "rc=$RC"

echo "=== T19: WARN lines reach the journal (ISO-prefixed) ==="
jr="$tmp/journal.log"; : > "$jr"
printf 'same1\t%s\tfile:%s/.credentials.json\n' "$tmp/dir-same1" "$tmp/dir-same1" > "$REG"
printf 'same2\t%s\tfile:%s/.credentials.json\n' "$tmp/dir-same2" "$tmp/dir-same2" >> "$REG"
run_select $(base_env) "LEADV2_CLAUDE_PROFILE_JOURNAL=$jr" "LEADV2_CLAUDE_PROFILE_SECURITY_BIN=$SECURITY_STUB"
check_grep "$(cat "$jr")" '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z \[claude-profile-select\] WARN: same_account label=same1' 'T19a: journal carries ISO-prefixed same_account WARN'
check_nogrep "$(cat "$jr")" 'sk-ant' 'T19b: journal has no token'

# ============================================================================
# Fix-round C2 (2026-08-27): the incident class the dir-fallback exists for.
# Two slots, both with a VALID credential and resolvable subscriptionType but
# NO readable .claude.json -> both derive "<sub>/na".  They must still land in
# DISTINCT quota buckets (config-dir-keyed), and the same_account warn must
# NOT fire (the email half is unresolved, so "same account" is unprovable).
echo "=== T20 (C2): two no-.claude.json slots, same sub -> distinct buckets, no same_account ==="
mkdir -p "$tmp/dir-nojson-a" "$tmp/dir-nojson-b"
mk_slot "$tmp/dir-nojson-a" pro "-" "$future_ms"
mk_slot "$tmp/dir-nojson-b" pro "-" "$future_ms"
acct_json 15 10 > "$FIX/nojson-a.json"
acct_json 60 50 > "$FIX/nojson-b.json"
printf 'nojson-a\t%s\tfile:%s/.credentials.json\n' "$tmp/dir-nojson-a" "$tmp/dir-nojson-a" > "$REG"
printf 'nojson-b\t%s\tfile:%s/.credentials.json\n' "$tmp/dir-nojson-b" "$tmp/dir-nojson-b" >> "$REG"
: > "$tmp/seen"
run_select $(base_env) "STUB_SEEN=$tmp/seen" "LEADV2_CLAUDE_PROFILE_SECURITY_BIN=$SECURITY_STUB"
buckets="$(sort -u "$tmp/seen" | wc -l | tr -d ' ')"
[[ "$buckets" -eq 2 ]] && pass "T20a: distinct quota buckets for two pro/na slots (config-dir key)" \
                      || fail "T20a" "buckets=$buckets seen=$(cat "$tmp/seen")"
check_nogrep "$ERR" 'same_account' 'T20b: no same_account warn when the email half is unresolved'
w_count="$(grep -c 'identity_email_unresolved' <<<"$ERR")"
[[ "$w_count" -eq 2 ]] && pass "T20c: both slots warned identity_email_unresolved" || fail "T20c" "count=$w_count err=$ERR"
check_grep "$OUT" '^profile=nojson-a .*score=15 source=live.*identity=pro/na' 'T20d: selection still works (fail-open, lowest window wins)'
[[ "$RC" -eq 0 ]] && pass "T20: exit 0" || fail "T20 exit" "rc=$RC"

printf '[TEST] Results: PASS=%d FAIL=%d\n' "$PASS" "$FAIL"
(( FAIL == 0 ))
