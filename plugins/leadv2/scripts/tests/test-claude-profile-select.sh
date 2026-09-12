#!/usr/bin/env bash
# run-all-triggers: leadv2-claude-profile-select.sh
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
mkdir -p "$FIX" "$CACHE" "$tmp/dir-alpha" "$tmp/dir-beta" "$tmp/dir-dead" "$tmp/dir-dead2"

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
check_grep "$OUT" '^profile=alpha config_dir=.*/dir-alpha rank_by=consumed_pct_min consumed_pct=20 usable_now=- source=live reason=worst_window candidates=2 cred=file:[^ ]+ identity=unknown/na binding=worst_of_both:consumed_pct=20 windows=alpha:worst_of_both=20\|beta:worst_of_both=80$' 'T4: picks alpha (consumed_pct=20, legacy pct-only fixture) live, binding/windows logged'
[[ "$RC" -eq 0 ]] && pass "T4: exit 0" || fail "T4 exit" "rc=$RC"

# ============================================================================
echo "=== T5: one unknown, one ok -> picks ok, source=live ==="
# 429-METER-VERDICT-01: dead keeps its OWN config dir -- a label parked on a
# dir whose earlier occupant probed ok would inherit that bucket's
# anthropic-last-ok.json sidecar and rank from it (the sidecar is keyed by
# bucket=slot, not label), which is the correct live behaviour but not what
# T5/T6 exist to pin: their dead candidates must be NEVER-known.
printf 'dead\t%s\tfile:%s/cred.json\n' "$tmp/dir-dead" "$tmp/dir-dead" > "$REG"
printf 'beta\t%s\tfile:%s/cred.json\n' "$tmp/dir-beta" "$tmp/dir-beta" >> "$REG"
run_select $(base_env)
check_grep "$OUT" '^profile=beta .*rank_by=consumed_pct_min consumed_pct=80 usable_now=- source=live reason=worst_window candidates=2 cred=file:[^ ]+ identity=unknown/na binding=worst_of_both:consumed_pct=80 windows=dead:-=-\|beta:worst_of_both=80$' 'T5: picks the ok profile, binding/windows logged'

# ============================================================================
echo "=== T6: both unknown -> first registry entry, all_unknown ==="
printf 'dead\t%s\tfile:%s/cred.json\n' "$tmp/dir-dead" "$tmp/dir-dead" > "$REG"
printf 'dead2\t%s\tfile:%s/cred.json\n' "$tmp/dir-dead2" "$tmp/dir-dead2" >> "$REG"
cp "$FIX/dead.json" "$FIX/dead2.json"
run_select $(base_env)
# TEAM-ACCOUNT-QUOTA-WINDOW-UNPARSED-01: UNKNOWN_TRIABLE still orders the
# pick (it competes fairly -- never successfully probed is not a confirmed-
# failure cooldown), but since BALANCER-...-01 the line prints NO number
# for it (rank_by=none consumed_pct=-), never a sentinel dressed as a pct.
check_grep "$OUT" '^profile=dead .*rank_by=none consumed_pct=- usable_now=- source=unknown reason=all_unknown candidates=2 cred=file:[^ ]+ identity=unknown/na binding=-:- windows=dead:-=-\|dead2:-=-$' 'T6: first entry, all_unknown, binding/windows logged'

# ============================================================================
echo "=== T7: malformed line + email-shaped label -> skipped, one warning each ==="
{
  printf 'alpha\t%s\tfile:%s/cred.json\n' "$tmp/dir-alpha" "$tmp/dir-alpha"
  printf 'founder@anthropic.com\t%s\n' "$tmp/dir-beta"
  printf 'just-a-label-no-dir\n'
  printf 'beta\t%s\tfile:%s/cred.json\n' "$tmp/dir-beta" "$tmp/dir-beta"
} > "$REG"
run_select $(base_env)
check_grep "$OUT" '^profile=alpha .*candidates=2 cred=file:[^ ]+ identity=unknown/na' 'T7: bad lines skipped, both good ones used'
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
check_grep "$(cat "$int_err")" '^\[claude-profile\] selected=alpha rank_by=consumed_pct_min consumed_pct=20 usable_now=- source=live candidates=2 cred_kind=file identity=unknown/na$' 'I2b: label-only stderr line shape'
hlog="$repo/docs/handoff/PROFILE-CL/claude-profile.log"
[[ -f "$hlog" ]] && pass "I3: handoff claude-profile.log exists" || fail "I3" "missing $hlog"
if [[ -f "$hlog" ]]; then
  check_grep "$(cat "$hlog")" '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z \[claude-profile\] selected=alpha rank_by=consumed_pct_min consumed_pct=20 usable_now=- source=live candidates=2 cred_kind=file identity=unknown/na$' 'I4: ISO-prefixed label-only handoff line'
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
# Caller refusal propagation: exercise claude-subsession.sh with a fixture
# selector in a sibling script directory.  The fixture changes only selector
# stdout/rc; the fake `claude` above records whether the caller actually
# reached a launch.  Keeping this separate from the real selector makes the
# rc=4 versus rc=124 distinction deterministic and hermetic.
echo "=== Integration: caller propagates selector refusal, but preserves timeout fallback ==="
SUB_FIX="$tmp/subsession-fixture"; mkdir -p "$SUB_FIX"
ln -s "$SUBSESSION_SH" "$SUB_FIX/claude-subsession.sh"
ln -s "$SCRIPTS_ROOT/leadv2-temp.sh" "$SUB_FIX/leadv2-temp.sh"
ln -s "$SCRIPTS_ROOT/leadv2-helpers.sh" "$SUB_FIX/leadv2-helpers.sh"
ln -s "$SCRIPTS_ROOT/lib" "$SUB_FIX/lib"
cat > "$SUB_FIX/leadv2-claude-profile-select.sh" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "${LEADV2_TEST_SELECTOR_LINE-profile=- reason=single_profile}"
exit "${LEADV2_TEST_SELECTOR_RC:-0}"
SH
chmod +x "$SUB_FIX/leadv2-claude-profile-select.sh"
SUB_FIX_BIN="$SUB_FIX/claude-subsession.sh"

run_subsession_fixture() { # <task-id> <selector-stdout> <selector-rc> [requested-profile]
  local task="$1" selector_line="$2" selector_rc="$3" requested="${4:-}"
  local fixture_err="$tmp/${task}.err"
  local -a requested_arg=()
  [[ -n "$requested" ]] && requested_arg=(--requested-profile "$requested")
  rm -f "$cap"; : > "$fixture_err"
  I9_CAPTURE="$cap" PROJECT_ROOT="$repo" PATH="$repo/bin:$PATH" LEADV2_ROUTE_BANDIT=0 \
    LEADV2_CLAUDE_MULTIPROFILE=1 LEADV2_TEST_SELECTOR_LINE="$selector_line" \
    LEADV2_TEST_SELECTOR_RC="$selector_rc" \
    bash "$SUB_FIX_BIN" --role developer --model sonnet --task-id "$task" \
      --mission-file "$repo/mission.md" --wait "${requested_arg[@]}" \
      >/dev/null 2>"$fixture_err"
  SUB_RC=$?
  SUB_ERR="$(cat "$fixture_err")"
  SUB_LOG="$repo/docs/handoff/$task/claude-profile.log"
  SUB_CAP="$(cat "$cap" 2>/dev/null)"
}

run_subsession_fixture PROFILE-REFUSAL 'profile=- reason=same_account' 4
[[ "$SUB_RC" -ne 0 ]] && pass "I10a: rc=4 refusal stops the launch" || fail "I10a" "rc=$SUB_RC"
[[ -z "$SUB_CAP" ]] && pass "I10b: rc=4 refusal never invokes claude" || fail "I10b" "capture=$SUB_CAP"
check_grep "$SUB_ERR" '^\[claude-subsession\] FATAL:.*reason=same_account' 'I10c: refusal reason reaches FATAL stderr'
check_grep "$(cat "$SUB_LOG" 2>/dev/null)" '\[claude-profile\] FATAL reason=same_account' 'I10d: refusal reason reaches handoff log'

run_subsession_fixture PROFILE-TIMEOUT 'profile=- reason=same_account' 124
[[ -n "$SUB_CAP" ]] && pass "I11a: rc=124 remains a soft fallback that reaches launch" || fail "I11a" "rc=$SUB_RC capture=$SUB_CAP"
check_grep "$SUB_CAP" '^CLAUDE_CONFIG_DIR=<unset>$' 'I11b: rc=124 still launches on inherited config'
check_grep "$(cat "$SUB_LOG" 2>/dev/null)" '\[claude-profile\] single-profile fallback' 'I11c: rc=124 keeps the legacy fallback journal'

success_line="profile=alpha config_dir=$tmp/dir-alpha rank_by=consumed_pct_min consumed_pct=20 usable_now=- source=live candidates=2 cred=file:$tmp/dir-alpha/cred.json identity=unknown/na"
run_subsession_fixture PROFILE-SUCCESS "$success_line" 0
[[ -n "$SUB_CAP" ]] && pass "I12a: successful selection still launches" || fail "I12a" "rc=$SUB_RC capture=$SUB_CAP"
check_grep "$SUB_CAP" "^CLAUDE_CONFIG_DIR=$tmp/dir-alpha$" 'I12b: successful selection still sets selected config_dir'
check_grep "$(cat "$SUB_LOG" 2>/dev/null)" '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z \[claude-profile\] selected=alpha rank_by=consumed_pct_min consumed_pct=20 usable_now=- source=live candidates=2 cred_kind=file identity=unknown/na$' 'I12c: successful selection journal carries rank_by/consumed_pct/usable_now'

run_subsession_fixture PROFILE-REFUSAL-EMPTY '' 4
[[ "$SUB_RC" -ne 0 && -z "$SUB_CAP" ]] && pass "I13a: empty rc=4 refusal still stops before launch" || fail "I13a" "rc=$SUB_RC capture=$SUB_CAP"
check_grep "$SUB_ERR" 'reason=unparsed_refusal' 'I13b: empty rc=4 refusal gets an explicit reason'
check_grep "$(cat "$SUB_LOG" 2>/dev/null)" 'reason=unparsed_refusal' 'I13c: empty rc=4 reason reaches handoff log'

run_subsession_fixture PROFILE-REQUESTED-REFUSAL 'profile=- reason=same_account' 4 alpha
[[ "$SUB_RC" -eq 5 ]] && pass "I14a: requested-profile refusal keeps exit 5 priority" || fail "I14a" "rc=$SUB_RC"
check_grep "$SUB_ERR" "requested profile 'alpha' could not be confirmed" 'I14b: requested-profile path remains authoritative'
check_nogrep "$SUB_ERR" '^\[claude-subsession\] FATAL: profile selector refused launch' 'I14c: requested-profile path does not emit a second refusal FATAL'

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
check_grep "$OUT" '^profile=personal .*identity=team/na' 'T11a: identity derived from credential (team), not label (personal)'
check_grep "$OUT" 'rank_by=consumed_pct_min consumed_pct=30 usable_now=- source=live' 'T11b: personal/team profile scored and picked'
[[ "$RC" -eq 0 ]] && pass "T11: exit 0" || fail "T11 exit" "rc=$RC"

echo "=== T11k (NC-a, keychain path): same mismatch via keychain: credential_source ==="
printf 'personal\t%s\tkeychain:svc-team\n' "$tmp/dir-team" > "$REG"
printf 'beta\t%s\tfile:%s/cred.json\n' "$tmp/dir-beta" "$tmp/dir-beta" >> "$REG"
run_select $(base_env) LEADV2_CLAUDE_PROFILE_SECURITY_BIN="$SECURITY_STUB"
check_grep "$OUT" '^profile=personal .*identity=team/na' 'T11k: identity derived via keychain: credential_source too'
check_nogrep "$OUT" 'sk-ant' 'T11k-leak: selected-profile stdout carries no access/refresh token'
check_nogrep "$ERR" 'sk-ant' 'T11k-leak2: selector stderr carries no access/refresh token'

echo "=== T12 (NC-b, D3): stale expiresAt -> WARN expiresAt_stale, probed live anyway ==="
printf 'stale\t%s\tfile:%s/cred.json\n' "$tmp/dir-stale" "$tmp/dir-stale" > "$REG"
printf 'alpha\t%s\tfile:%s/cred.json\n' "$tmp/dir-alpha" "$tmp/dir-alpha" >> "$REG"
printf 'beta\t%s\tfile:%s/cred.json\n' "$tmp/dir-beta" "$tmp/dir-beta" >> "$REG"
run_select $(base_env)
check_grep "$ERR" 'WARN: registry line 1: expiresAt_stale label=stale identity=max/na -- probing live anyway' 'T12a: WARN expiresAt_stale names label+identity, does not exclude'
check_grep "$OUT" '^profile=alpha .*candidates=3 ' 'T12b: stale entry still reaches the probe -- candidates=3, not 2'
check_nogrep "$OUT" '^profile=stale ' 'T12c: stale-and-actually-dead-per-probe profile still never wins'
[[ "$RC" -eq 0 ]] && pass "T12: exit 0" || fail "T12 exit" "rc=$RC"

echo "=== T13 (NC-c, D3): all candidates stale + probe can't resolve them -> all_unknown, not a silent pick ==="
printf 'exp-a\t%s\tfile:%s/cred.json\n' "$tmp/dir-allexp-a" "$tmp/dir-allexp-a" > "$REG"
printf 'exp-b\t%s\tfile:%s/cred.json\n' "$tmp/dir-allexp-b" "$tmp/dir-allexp-b" >> "$REG"
run_select $(base_env)
# TEAM-ACCOUNT-QUOTA-WINDOW-UNPARSED-01: unknown pick (rank_by=none) -- see T6.
check_grep "$OUT" '^profile=exp-a .*rank_by=none consumed_pct=- usable_now=- source=unknown reason=all_unknown candidates=2 cred=file:[^ ]+ identity=max/na binding=-:- windows=exp-a:-=-\|exp-b:-=-$' 'T13a: named all_unknown outcome (probed, not statically refused), not a silent pick'
w_count="$(grep -c 'WARN: registry line .* expiresAt_stale' <<<"$ERR")"
[[ "$w_count" -eq 2 ]] && pass "T13b: both stale entries warned but still probed" || fail "T13b" "count=$w_count err=$ERR"
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
[[ "$RC" -eq 4 ]] && pass "T14: exit 4 (hard refusal; never a single-profile fallback)" || fail "T14 exit" "rc=$RC"

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
[[ "$RC" -eq 4 ]] && pass "T21: exit 4 (uuid collapse is a hard refusal)" || fail "T21 exit" "rc=$RC"

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
check_grep "$OUT" '^profile=nojson .*identity=pro/na' 'T16b: entry still selectable (fail-open)'
[[ "$RC" -eq 0 ]] && pass "T16: exit 0" || fail "T16 exit" "rc=$RC"

echo "=== T17: default token expired -> visible alternate selection, never inherited fallback ==="
mkdir -p "$tmp/dir-def-exp"
mk_slot "$tmp/dir-def-exp" max "defexp@fixture.test" "$past_ms"
printf 'alpha\t%s\tfile:%s/cred.json\n' "$tmp/dir-alpha" "$tmp/dir-alpha" > "$REG"
printf 'beta\t%s\tfile:%s/cred.json\n' "$tmp/dir-beta" "$tmp/dir-beta" >> "$REG"
run_select $(base_env) "LEADV2_CLAUDE_PROFILE_DEFAULT_DIR=$tmp/dir-def-exp" \
  "LEADV2_CLAUDE_PROFILE_SECURITY_BIN=$SECURITY_STUB"
check_grep "$ERR" 'WARN: default_token_expired identity=max/defexp@fixture\.test -- inherited fallback will refuse; probe-qualified profile required' 'T17a: default_token_expired makes fallback policy explicit'
check_grep "$OUT" '^profile=alpha .*rank_by=consumed_pct_min consumed_pct=20 usable_now=- source=live' 'T17b: selection itself unchanged'
[[ "$RC" -eq 0 ]] && pass "T17: exit 0 (explicit probe-qualified alternative selected)" || fail "T17 exit" "rc=$RC"

printf 'alpha\t%s\tfile:%s/cred.json\n' "$tmp/dir-alpha" "$tmp/dir-alpha" > "$REG"
run_select $(base_env) "LEADV2_CLAUDE_PROFILE_DEFAULT_DIR=$tmp/dir-def-exp" \
  "LEADV2_CLAUDE_PROFILE_SECURITY_BIN=$SECURITY_STUB"
check_grep "$OUT" '^profile=- reason=default_token_expired$' 'T17c: expired inherited credential refuses single-profile fallback'
check_grep "$ERR" 'FATAL: default_token_expired -- refusing inherited single-profile fallback' 'T17d: refusal is explicit, not a quiet fallback'
[[ "$RC" -eq 4 ]] && pass "T17: fallback exit 4" || fail "T17 fallback exit" "rc=$RC"

echo "=== T18: default credential absent -> visible alternate selection, never inherited fallback ==="
mkdir -p "$tmp/dir-def-empty"
printf 'alpha\t%s\tfile:%s/cred.json\n' "$tmp/dir-alpha" "$tmp/dir-alpha" > "$REG"
printf 'beta\t%s\tfile:%s/cred.json\n' "$tmp/dir-beta" "$tmp/dir-beta" >> "$REG"
run_select $(base_env) "LEADV2_CLAUDE_PROFILE_DEFAULT_DIR=$tmp/dir-def-empty" \
  "LEADV2_CLAUDE_PROFILE_SECURITY_BIN=$SECURITY_STUB"
check_grep "$ERR" 'WARN: default_token_absent \(inherited slot has no readable credential\) -- inherited fallback will refuse' 'T18a: default_token_absent makes fallback policy explicit'
check_grep "$OUT" '^profile=alpha ' 'T18b: selection proceeds'
[[ "$RC" -eq 0 ]] && pass "T18: exit 0 (explicit probe-qualified alternative selected)" || fail "T18 exit" "rc=$RC"

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
check_grep "$OUT" '^profile=nojson-a .*rank_by=consumed_pct_min consumed_pct=15 usable_now=- source=live.*identity=pro/na' 'T20d: selection still works (fail-open, lowest window wins)'
[[ "$RC" -eq 0 ]] && pass "T20: exit 0" || fail "T20 exit" "rc=$RC"

# ============================================================================
# T21 (TWO-ACCOUNTS-EVERYWHERE-AND-QUOTA-AWARE-01 D2): binding_window scoring.
# case1: five_hour=90% (NOT binding -- resets soon) / seven_day=20% (binding).
# case2: five_hour=20% (NOT binding) / seven_day=90% (binding -- resets soon).
# A blind max(five_hour_pct, seven_day_pct) would score BOTH 90 and could not
# tell them apart. Scoring on the account's own binding_window must pick
# case1 (score 20, healthy) over case2 (score 90, genuinely tight) even
# though the raw five_hour numbers alone would suggest the opposite.
echo "=== T21: binding_window (reset-aware) beats blind worst-of-both ==="
acct_json_binding() { # <five_hour_pct> <seven_day_pct> <binding_window>
  printf '{"provider":"anthropic","status":"ok","accounts":[{"entry_suffix":"file","service":"file:stub","status":"ok","five_hour_pct":%s,"seven_day_pct":%s,"binding_window":"%s","active":true,"account_label":"stub"}],"active_account":"stub","fetched_at":"2026-08-25T00:00:00Z"}' "$1" "$2" "$3"
}
acct_json_binding 90 20 seven_day > "$FIX/case1.json"
acct_json_binding 20 90 seven_day > "$FIX/case2.json"
printf 'case1\t%s\tfile:%s/cred.json\n' "$tmp/dir-alpha" "$tmp/dir-alpha" > "$REG"
printf 'case2\t%s\tfile:%s/cred.json\n' "$tmp/dir-beta" "$tmp/dir-beta" >> "$REG"
run_select $(base_env)
check_grep "$OUT" '^profile=case1 config_dir=.*/dir-alpha rank_by=consumed_pct_min consumed_pct=20 usable_now=- source=live reason=binding_window candidates=2 cred=file:[^ ]+ identity=unknown/na binding=seven_day:consumed_pct=20 windows=case1:seven_day=20\|case2:seven_day=90$' \
  'T21: picks case1 (binding window 20%) over case2 (binding window 90%), reason=binding_window'
[[ "$RC" -eq 0 ]] && pass "T21: exit 0" || fail "T21 exit" "rc=$RC"

# ============================================================================
echo "=== T22 (D3, TWO-ACCOUNTS-EVERYWHERE-AND-QUOTA-AWARE-01): stale expiresAt does not stop a genuinely live account from winning ==="
mkdir -p "$tmp/dir-stale-live"
cred_json max "$past_ms" > "$tmp/dir-stale-live/cred.json"
acct_json 15 10 > "$FIX/stale-live.json"
printf 'stale-live\t%s\tfile:%s/cred.json\n' "$tmp/dir-stale-live" "$tmp/dir-stale-live" > "$REG"
printf 'beta\t%s\tfile:%s/cred.json\n' "$tmp/dir-beta" "$tmp/dir-beta" >> "$REG"
run_select $(base_env)
check_grep "$ERR" 'WARN: registry line 1: expiresAt_stale label=stale-live identity=max/na -- probing live anyway' 'T22a: WARN fires but does not exclude'
check_grep "$OUT" '^profile=stale-live .*rank_by=consumed_pct_min consumed_pct=15 usable_now=- source=live' 'T22b: the stale-per-field, live-per-probe account still wins -- the field is not the liveness test'
[[ "$RC" -eq 0 ]] && pass "T22: exit 0" || fail "T22 exit" "rc=$RC"

# ============================================================================
echo "=== T23 (D3): same_account still fires when one sibling's expiresAt looks stale ==="
# Before D3, a stale-looking sibling was dropped in the registry loop BEFORE
# ever reaching the same-account comparison below -- a real same-account pair
# could silently present as a single, unwarned candidate whenever one slot's
# expiresAt looked expired (measured: true of every registered slot in this
# environment). This is the exact incident risk the founder flagged for the
# Sept 15 plan: two registry rows that resolve to ONE live account must never
# go undetected just because a stale field happened to hide one of them.
mkdir -p "$tmp/dir-same-fresh" "$tmp/dir-same-stale"
mk_slot "$tmp/dir-same-fresh" team "shared2@fixture.test" "$future_ms"
mk_slot "$tmp/dir-same-stale" team "shared2@fixture.test" "$past_ms"
acct_json 40 30 > "$FIX/same-fresh.json"; acct_json 40 30 > "$FIX/same-stale.json"
printf 'same-fresh\t%s\tfile:%s/.credentials.json\n' "$tmp/dir-same-fresh" "$tmp/dir-same-fresh" > "$REG"
printf 'same-stale\t%s\tfile:%s/.credentials.json\n' "$tmp/dir-same-stale" "$tmp/dir-same-stale" >> "$REG"
run_select $(base_env) "LEADV2_CLAUDE_PROFILE_SECURITY_BIN=$SECURITY_STUB"
# Both assertions below were written against a shape the production script
# never had. T23 and the D3 rescue landed the SAME day (2026-09-03) in two
# commits that both say so in their own subjects -- "rescue uncommitted lane
# work after worker death" and "checkpoint of a worker that died mid-write --
# NOT finished work" -- and the two halves disagree because neither was
# finished, not because the product regressed:
#
#   * the warn carries `sub=` and `account=`, not `identity=`. The
#     `identity=` form is from f6c580d8 (2026-08-27) and was replaced in the
#     same rescue commit that added this case.
#   * `profile=same-fresh ... candidates=2` is unreachable BY DESIGN. Two
#     slots resolving to one real account is "the incident" in this script's
#     own header table, and its documented response is to select nothing --
#     `profile=- reason=same_account`, exit 0 -- so the caller keeps the
#     profile it inherited rather than silently collapsing two slots onto one
#     account. There is no code path that reaches a candidate count after a
#     same_account hit. "fail-open, as with T14" was carried over from T14,
#     whose case has no same_account hit at all.
#
# The INTENT of T23 is untouched and is what the assertions now check: a
# sibling whose expiresAt looks stale must still reach the same-account
# comparison. That is asserted on both sides -- the stale row is warned about
# and kept (D3), and the pair is then detected -- so the coverage hole this
# case exists for stays closed, and the incident response is pinned with it.
check_grep "$ERR" 'WARN: registry line 2: expiresAt_stale label=same-stale identity=team/shared2@fixture\.test -- probing live anyway' 'T23a: the stale-looking sibling is warned about and KEPT, not dropped in the registry loop (D3)'
check_grep "$ERR" 'WARN: same_account label=same-fresh label=same-stale sub=team account=' 'T23b: both slots reached the comparison and the pair is named -- the coverage hole stays closed'
check_grep "$OUT" '^profile=- reason=same_account$' 'T23c: the documented incident response -- select nothing, so the caller keeps its inherited profile'
[[ "$RC" -eq 4 ]] && pass "T23: exit 4 (same-account is never a fallback)" || fail "T23 exit" "rc=$RC"

# ============================================================================
# T24 (TEAM-ACCOUNT-QUOTA-WINDOW-UNPARSED-01): mandatory pair control, both
# halves. Half 1 -- an unknown-scored profile (never successfully probed) is
# now SELECTABLE: it wins a tie against a live profile that is itself fully
# exhausted (pct=100), instead of automatically losing to every live score
# the way the old flat UNKNOWN=101 sentinel did. Half 2 (regression sanity)
# -- unknown still LOSES to a live profile with genuine free quota, so the
# fix does not over-correct into "unknown always wins".
echo "=== T24a: unknown ties-and-wins (input order) against a fully exhausted (100%) live profile ==="
acct_json 100 100 > "$FIX/maxed.json"
printf 'idle\t%s\tfile:%s/cred.json\n' "$tmp/dir-alpha" "$tmp/dir-alpha" > "$REG"
printf 'maxed\t%s\tfile:%s/cred.json\n' "$tmp/dir-beta" "$tmp/dir-beta" >> "$REG"
run_select $(base_env)
check_grep "$OUT" '^profile=idle .*rank_by=none consumed_pct=- usable_now=- source=unknown' 'T24a: never-probed idle profile (unknown triable) beats a 100%-exhausted live profile, not automatically loses'
[[ "$RC" -eq 0 ]] && pass "T24a: exit 0" || fail "T24a exit" "rc=$RC"

echo "=== T24b (regression): unknown still loses to a live profile with real free quota ==="
printf 'idle\t%s\tfile:%s/cred.json\n' "$tmp/dir-alpha" "$tmp/dir-alpha" > "$REG"
printf 'alpha\t%s\tfile:%s/cred.json\n' "$tmp/dir-beta" "$tmp/dir-beta" >> "$REG"
run_select $(base_env)
check_grep "$OUT" '^profile=alpha .*rank_by=consumed_pct_min consumed_pct=20 usable_now=- source=live' 'T24b: a live profile with free quota (20%) still beats an unknown-scored one'
[[ "$RC" -eq 0 ]] && pass "T24b: exit 0" || fail "T24b exit" "rc=$RC"

# ============================================================================
# T25 (TEAM-ACCOUNT-QUOTA-WINDOW-UNPARSED-01): a CONFIRMED live failure (the
# active account's own status!=ok plus a non-empty error, e.g. an expired
# credential returning http 401) starts a cooldown; the very next round must
# skip probing that identity and score it strictly worse than a live
# profile, even one with worse-than-average quota -- so a broken credential
# never eats every dispatch, but is never retried within the cooldown either.
echo "=== T25: a confirmed live failure starts a cooldown that survives to the next round ==="
printf '{"provider":"anthropic","status":"ok","accounts":[{"entry_suffix":"file","service":"file:stub","status":"error","error":"http 401","active":true,"account_label":"stub"}],"active_account":"stub","fetched_at":"2026-08-25T00:00:00Z"}' > "$FIX/flaky.json"
acct_json 90 80 > "$FIX/steady.json"
printf 'flaky\t%s\tfile:%s/cred.json\n' "$tmp/dir-alpha" "$tmp/dir-alpha" > "$REG"
printf 'steady\t%s\tfile:%s/cred.json\n' "$tmp/dir-beta" "$tmp/dir-beta" >> "$REG"
LEADV2_CLAUDE_PROFILE_COOLDOWN_S=900 run_select $(base_env) LEADV2_CLAUDE_PROFILE_COOLDOWN_S=900
check_grep "$ERR" 'WARN: profile label=flaky live probe failed; cooling down' 'T25a: the confirmed 401 starts a cooldown (WARN fires)'
check_grep "$OUT" '^profile=steady .*rank_by=consumed_pct_min consumed_pct=90 usable_now=- source=live' 'T25b: round 1 sanity -- steady (90%/80% worst-of-both) wins over flaky (scores fairly at 100 on its FIRST failure, not yet cooling)'
# Round 2, same CACHE dir (identity/config_dir key persists): rewrite
# flaky's fixture to a WOULD-BE great score (5%). If cooldown is honored,
# flaky must not even be re-probed this round -- it stays excluded and
# steady (worse quota, 90%) still must not lose to a phantom "5%" that was
# never actually re-verified live during the cooldown window.
acct_json 5 5 > "$FIX/flaky.json"
run_select $(base_env)
check_grep "$ERR" 'WARN: profile label=flaky cooling down after a recent live probe failure; skipping this round' 'T25c: round 2 -- flaky is skipped (cooling), not re-probed'
check_grep "$OUT" '^profile=steady .*rank_by=consumed_pct_min consumed_pct=90 usable_now=- source=live' 'T25d: round 2 -- steady wins despite worse quota, because the cooling profile is excluded, not silently re-trusted'
[[ "$RC" -eq 0 ]] && pass "T25: exit 0" || fail "T25 exit" "rc=$RC"

# ============================================================================
# T26/T27 (PROBE-COOLDOWN-OUTLIVES-ITS-CONDITION-01): the cooldown is a cached
# negative result keyed on the credential that just failed. A re-login changes
# the credential bytes underneath the same registry slot; the cooldown must
# not survive that change (T26, positive), but MUST still survive an ordinary
# next round where the credential did not change (T27, the mandatory paired
# negative control -- without it this "fix" would just be a 401-storm
# re-enabler in disguise).  Real credential-file bytes are required here (T25
# above never exercises this path: its `cred.json` files do not exist on
# disk, so their digest resolves to "-" and the fix's own missing-sidecar
# fallback intentionally treats that as "unknown", not "changed").
mkdir -p "$tmp/dir-gamma" "$tmp/dir-delta"

echo "=== T26: credential fingerprint change invalidates an in-window cooldown ==="
printf '{"claudeAiOauth":{"subscriptionType":"max","expiresAt":9999999999999}}' > "$tmp/dir-gamma/cred-v1.json"
printf '{"provider":"anthropic","status":"ok","accounts":[{"entry_suffix":"file","service":"file:stub","status":"error","error":"http 401","active":true,"account_label":"stub"}],"active_account":"stub","fetched_at":"2026-08-25T00:00:00Z"}' > "$FIX/relogina.json"
acct_json 90 80 > "$FIX/steadyb.json"
printf 'relogina\t%s\tfile:%s/cred-v1.json\n' "$tmp/dir-gamma" "$tmp/dir-gamma" > "$REG"
printf 'steadyb\t%s\tfile:%s/cred.json\n' "$tmp/dir-beta" "$tmp/dir-beta" >> "$REG"
LEADV2_CLAUDE_PROFILE_COOLDOWN_S=900 run_select $(base_env) LEADV2_CLAUDE_PROFILE_COOLDOWN_S=900
check_grep "$ERR" 'WARN: profile label=relogina live probe failed; cooling down' 'T26a: round 1 -- confirmed 401 starts a cooldown for relogina'
# Simulate a re-login: the SAME registry slot, DIFFERENT credential bytes.
printf '{"claudeAiOauth":{"subscriptionType":"max","expiresAt":9999999999999,"nonce":"post-relogin"}}' > "$tmp/dir-gamma/cred-v1.json"
acct_json 5 5 > "$FIX/relogina.json"
run_select $(base_env)
check_grep "$ERR" 'WARN: profile label=relogina cooldown invalidated: credential fingerprint changed' 'T26b: round 2 -- changed credential invalidates the cooldown (WARN fires)'
check_nogrep "$ERR" 'WARN: profile label=relogina cooling down after a recent live probe failure; skipping this round' 'T26c: round 2 -- relogina is NOT silently skipped this time'
check_grep "$OUT" '^profile=relogina .*rank_by=consumed_pct_min consumed_pct=5 usable_now=- source=live' 'T26d: round 2 -- relogina was actually re-probed live and won on its real (good) quota, not defaulted'
[[ "$RC" -eq 0 ]] && pass "T26: exit 0" || fail "T26 exit" "rc=$RC"

echo "=== T27 (mandatory paired negative control): unchanged credential -- cooldown still applies ==="
printf '{"claudeAiOauth":{"subscriptionType":"max","expiresAt":9999999999999}}' > "$tmp/dir-delta/cred-v1.json"
printf '{"provider":"anthropic","status":"ok","accounts":[{"entry_suffix":"file","service":"file:stub","status":"error","error":"http 401","active":true,"account_label":"stub"}],"active_account":"stub","fetched_at":"2026-08-25T00:00:00Z"}' > "$FIX/reloginc.json"
acct_json 90 80 > "$FIX/steadyd.json"
printf 'reloginc\t%s\tfile:%s/cred-v1.json\n' "$tmp/dir-delta" "$tmp/dir-delta" > "$REG"
printf 'steadyd\t%s\tfile:%s/cred.json\n' "$tmp/dir-beta" "$tmp/dir-beta" >> "$REG"
LEADV2_CLAUDE_PROFILE_COOLDOWN_S=900 run_select $(base_env) LEADV2_CLAUDE_PROFILE_COOLDOWN_S=900
check_grep "$ERR" 'WARN: profile label=reloginc live probe failed; cooling down' 'T27a: round 1 -- confirmed 401 starts a cooldown for reloginc'
# NO credential change this time -- same bytes, same file, untouched.
acct_json 5 5 > "$FIX/reloginc.json"
run_select $(base_env)
check_nogrep "$ERR" 'WARN: profile label=reloginc cooldown invalidated' 'T27b: round 2 -- unchanged credential does NOT invalidate the cooldown'
check_grep "$ERR" 'WARN: profile label=reloginc cooling down after a recent live probe failure; skipping this round' 'T27c: round 2 -- reloginc is still skipped (cooling), exactly like T25 -- the protection is not disabled by this fix'
check_grep "$OUT" '^profile=steadyd .*rank_by=consumed_pct_min consumed_pct=90 usable_now=- source=live' 'T27d: round 2 -- steadyd still wins; the phantom 5%% never actually re-verified'
[[ "$RC" -eq 0 ]] && pass "T27: exit 0" || fail "T27 exit" "rc=$RC"

# T28: mutation control -- if the fingerprint comparison in the fix is
# dropped (cooldown always honored regardless of credential change), T26b/c/d
# must fail. Run the exact T26 scenario fresh against a copy of the selector
# with that one comparison neutralized, and require the suite to go red.
echo "=== T28: mutation control -- neutralizing the fingerprint check must break T26 ==="
# The mutant must live NEXT TO the real script, not under $tmp: SCRIPT_DIR is
# derived from its own location and used to resolve PICK="$SCRIPT_DIR/lib/
# leadv2-claude-profile-pick.py" (no env override exists for PICK), so a
# copy anywhere else silently fails PICK's readability check and every run
# degrades to single_profile before ever reaching the mutated line.
MUT="${SCRIPTS_ROOT}/.mut-profile-select-$$.sh"
trap 'rm -f "$MUT"; rm -rf "$tmp"' EXIT
# NOTE: `[[ false ]]` is NOT bash false -- it tests the non-empty STRING
# "false", which is truthy, and would silently make this mutation a no-op
# that still passes the diff-differs check below (caught by running this
# exact idiom against its target before trusting red/green, per today's
# s3 finding). `[[ 1 -eq 0 ]]` is a genuine false.
sed -E 's/(\[\[ -n "\$cooldown_cred" && -n "\$digest" && "\$digest" != "-" && "\$cooldown_cred" != "\$digest" \]\])/[[ 1 -eq 0 ]]/' \
  "$SELECT_BIN" > "$MUT"
chmod +x "$MUT"
if diff -q "$SELECT_BIN" "$MUT" >/dev/null 2>&1; then
  fail "T28: mutation applied" "sed did not change the file -- pattern did not match, mutation is a no-op"
else
  pass "T28: mutation applied (file differs from original)"
fi
mkdir -p "$tmp/dir-mut"
printf '{"claudeAiOauth":{"subscriptionType":"max","expiresAt":9999999999999}}' > "$tmp/dir-mut/cred-v1.json"
printf '{"provider":"anthropic","status":"ok","accounts":[{"entry_suffix":"file","service":"file:stub","status":"error","error":"http 401","active":true,"account_label":"stub"}],"active_account":"stub","fetched_at":"2026-08-25T00:00:00Z"}' > "$FIX/reloginm.json"
acct_json 90 80 > "$FIX/steadym.json"
printf 'reloginm\t%s\tfile:%s/cred-v1.json\n' "$tmp/dir-mut" "$tmp/dir-mut" > "$REG"
printf 'steadym\t%s\tfile:%s/cred.json\n' "$tmp/dir-beta" "$tmp/dir-beta" >> "$REG"
# run_select's $SELECT_BIN is resolved once at script startup from
# LEADV2_TEST_SELECT_BIN, so a prefix assignment on the call below would be a
# no-op -- both rounds must invoke $MUT directly, matching what run_select
# does internally.
OUT="$(env STUB_FIXDIR="$FIX" $(base_env) LEADV2_CLAUDE_PROFILE_COOLDOWN_S=900 bash "$MUT" 2>"$tmp/select.err")"; RC=$?
ERR="$(cat "$tmp/select.err")"
printf '{"claudeAiOauth":{"subscriptionType":"max","expiresAt":9999999999999,"nonce":"post-relogin"}}' > "$tmp/dir-mut/cred-v1.json"
acct_json 5 5 > "$FIX/reloginm.json"
OUT="$(env STUB_FIXDIR="$FIX" $(base_env) bash "$MUT" 2>"$tmp/select.err")"; RC=$?
ERR="$(cat "$tmp/select.err")"
check_grep "$ERR" 'WARN: profile label=reloginm cooling down after a recent live probe failure; skipping this round' 'T28 (RED under mutation): reloginm wrongly still skipped despite the credential change -- mutation confirmed to break the exact behaviour T26 proves'

# ============================================================================
# T29..T36 (429-METER-VERDICT-01): a 429 from the usage meter is a verdict
# about the METER, never about the account. Half one: only a positive list
# of credential-verdict causes (http 401/403, expired/revoked/malformed/
# invalid/unauthorized/forbidden) may start a cooldown -- an unmeasurable
# read leaves the profile a live candidate. Half two: an unmeasurable read
# ranks from the identity's last-known-good sidecar (source=stale, labeled
# with its age) instead of falling through to demotion order.
# Fixture payload: the exact shape leadv2-quota-read.py emits on a throttled
# meter (measured live 2026-09-12 on both identities).
err429_json() { # <account_state>
  printf '{"provider":"anthropic","status":"ok","accounts":[{"entry_suffix":"file","service":"file:stub","subscription_type":"team","http":429,"account_label":"max_5x","active":true,"status":"unknown","account_state":"%s","error":"429 rate_limited (reported as unknown, NEVER 0)","five_hour":{"pct":null,"reset_iso":null,"remaining_pct":null,"hours_to_reset":null,"usable_now":null},"seven_day":{"pct":null,"reset_iso":null,"remaining_pct":null,"hours_to_reset":null,"usable_now":null},"binding_window":null}],"active_account":"max_5x","binding_window":null,"fetched_at":"2026-09-12T12:07:42Z"}' "$1"
}
# Windowed healthy payload (binding seven_day) for seeding last-known sidecars.
win_json() { # <7d_pct> <7d_usable> -> seven_day-bound healthy account
  printf '{"provider":"anthropic","status":"ok","accounts":[{"entry_suffix":"file","service":"file:stub","subscription_type":"max","http":200,"account_label":"max_20x","active":true,"status":"ok","account_state":"ok","five_hour_pct":6,"seven_day_pct":%s,"five_hour":{"pct":6,"reset_iso":"2026-09-12T15:30:00Z","remaining_pct":94,"hours_to_reset":3.3,"usable_now":28.2},"seven_day":{"pct":%s,"reset_iso":"2026-09-18T22:00:00Z","remaining_pct":%s,"hours_to_reset":153.8,"usable_now":%s},"binding_window":"seven_day"}],"active_account":"max_20x","binding_window":"seven_day","fetched_at":"%s"}' \
    "$1" "$1" "$(( 100 - $1 ))" "$2" "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
mkdir -p "$tmp/dir-t29" "$tmp/dir-t30" "$tmp/dir-t31" "$tmp/dir-t32p" "$tmp/dir-t32w" \
         "$tmp/dir-t33p" "$tmp/dir-t33w" "$tmp/dir-t34p" "$tmp/dir-t34w" "$tmp/dir-t35p" "$tmp/dir-t35w"

echo "=== T29: a 429 meter read starts NO cooldown and never skips a round ==="
err429_json unknown > "$FIX/err429.json"
acct_json 90 80 > "$FIX/steady29.json"
printf 'err429\t%s\tfile:%s/cred.json\n' "$tmp/dir-t29" "$tmp/dir-t29" > "$REG"
printf 'steady29\t%s\tfile:%s/cred.json\n' "$tmp/dir-beta" "$tmp/dir-beta" >> "$REG"
run_select $(base_env) LEADV2_CLAUDE_PROFILE_COOLDOWN_S=900
check_grep "$OUT" '^profile=steady29 ' 'T29a: the 429 profile did not win, the live one did'
check_nogrep "$ERR" 'WARN: profile label=err429 live probe failed; cooling down' 'T29b: NO cooldown WARN for a 429 meter read'
check_nogrep "$ERR" 'WARN: profile label=err429 cooling down after a recent live probe failure' 'T29c: 429 never reads as a confirmed live failure'
run_select $(base_env) LEADV2_CLAUDE_PROFILE_COOLDOWN_S=900
check_nogrep "$ERR" 'WARN: profile label=err429 cooling down after a recent live probe failure; skipping this round' 'T29d: round 2 -- 429 profile is still probed (a throttled meter is not a dead credential)'
[[ -z "$(find "$CACHE" -name probe-cooldown-until -path '*t29*')" ]] && pass "T29e: no cooldown marker file written for the 429 bucket" || fail "T29e" "cooldown marker exists for the 429 bucket"
[[ "$RC" -eq 0 ]] && pass "T29: exit 0" || fail "T29 exit" "rc=$RC"

echo "=== T30: 401 with account_state=unmetered is a meter verdict, not a credential one ==="
printf '{"provider":"anthropic","status":"ok","accounts":[{"entry_suffix":"file","service":"file:stub","subscription_type":"team","http":401,"account_label":"max_5x","active":true,"status":"unknown","account_state":"unmetered","error":"http 401","binding_window":null}],"active_account":"max_5x","binding_window":null,"fetched_at":"2026-09-12T12:07:42Z"}' > "$FIX/unmet401.json"
acct_json 90 80 > "$FIX/steady30.json"
printf 'unmet401\t%s\tfile:%s/cred.json\n' "$tmp/dir-t30" "$tmp/dir-t30" > "$REG"
printf 'steady30\t%s\tfile:%s/cred.json\n' "$tmp/dir-beta" "$tmp/dir-beta" >> "$REG"
run_select $(base_env) LEADV2_CLAUDE_PROFILE_COOLDOWN_S=900
check_grep "$OUT" '^profile=steady30 ' 'T30a: unmetered profile loses to the live one, fair unknown rank'
check_nogrep "$ERR" 'WARN: profile label=unmet401 live probe failed; cooling down' 'T30b: measured-unmetered 401 starts NO cooldown (the token resolves; only the usage endpoint refuses)'
[[ -z "$(find "$CACHE" -name probe-cooldown-until -path '*t30*')" ]] && pass "T30c: no cooldown marker for the unmetered bucket" || fail "T30c" "cooldown marker exists for the unmetered bucket"
[[ "$RC" -eq 0 ]] && pass "T30: exit 0" || fail "T30 exit" "rc=$RC"

echo "=== T31: an unknown failure shape (transport) defaults to unmeasurable, never to cooldown ==="
printf '{"provider":"anthropic","status":"ok","accounts":[{"entry_suffix":"file","service":"file:stub","active":true,"status":"unknown","error":"timed out","binding_window":null}],"active_account":"stub","binding_window":null,"fetched_at":"2026-09-12T12:07:42Z"}' > "$FIX/tmo.json"
acct_json 90 80 > "$FIX/steady31.json"
printf 'tmo\t%s\tfile:%s/cred.json\n' "$tmp/dir-t31" "$tmp/dir-t31" > "$REG"
printf 'steady31\t%s\tfile:%s/cred.json\n' "$tmp/dir-beta" "$tmp/dir-beta" >> "$REG"
run_select $(base_env) LEADV2_CLAUDE_PROFILE_COOLDOWN_S=900
check_nogrep "$ERR" 'WARN: profile label=tmo live probe failed; cooling down' 'T31a: transport error starts NO cooldown (positive list, not a blocklist of one)'
[[ -z "$(find "$CACHE" -name probe-cooldown-until -path '*t31*')" ]] && pass "T31b: no cooldown marker for the transport bucket" || fail "T31b" "cooldown marker exists for the transport bucket"
[[ "$RC" -eq 0 ]] && pass "T31: exit 0" || fail "T31 exit" "rc=$RC"

echo "=== T32: a healthy read is kept as the identity's last-known-good sidecar ==="
win_json 3 0.63 > "$FIX/healthyp.json"
win_json 80 0.13 > "$FIX/healthyw.json"
printf 'healthyp\t%s\tfile:%s/cred.json\n' "$tmp/dir-t32p" "$tmp/dir-t32p" > "$REG"
printf 'healthyw\t%s\tfile:%s/cred.json\n' "$tmp/dir-t32w" "$tmp/dir-t32w" >> "$REG"
run_select $(base_env)
sc_p="$(find "$CACHE" -name anthropic-last-ok.json -path '*t32p*' | head -1)"
sc_w="$(find "$CACHE" -name anthropic-last-ok.json -path '*t32w*' | head -1)"
[[ -n "$sc_p" && -n "$sc_w" ]] && pass "T32a: sidecar written for both healthy buckets" || fail "T32a" "missing sidecar(s): p=${sc_p:-none} w=${sc_w:-none}"
grep -q '"status": *"ok"' "$sc_p" 2>/dev/null && pass "T32b: sidecar holds the ok payload" || fail "T32b" "sidecar content not an ok payload: $(cat "$sc_p" 2>/dev/null)"
check_grep "$OUT" '^profile=healthyp .*source=live' 'T32c: healthy round still picks live'
[[ "$RC" -eq 0 ]] && pass "T32: exit 0" || fail "T32 exit" "rc=$RC"

echo "=== T33: the incident -- both meters 429, sidecars known, personal demoted: rank from last known ==="
err429_json unknown > "$FIX/healthyp.json"
err429_json unknown > "$FIX/healthyw.json"
run_select $(base_env) LEADV2_CLAUDE_PROFILE_DEMOTE_DIR="$tmp/dir-t32p"
check_grep "$OUT" '^profile=healthyp .*rank_by=usable_now_max consumed_pct=3 usable_now=0\.630 source=stale reason=last_known candidates=2 .*binding=seven_day:consumed_pct=3,usable_now=0\.630 windows=healthyp:seven_day=3,usable_now=0\.630,stale\|healthyw:seven_day=80,usable_now=0\.130,stale demoted=healthyp demote_yielded=healthyp margin=0\.15 stale_age_s=[0-9]+' 'T33a: picks the last-known-3%% profile (source=stale, age labeled), NOT demotion order'
check_grep "$ERR" 'WARN: profile label=healthyp live quota read unmeasurable; ranking from last-known payload \(degradation=stale_last_known age_s=[0-9]+\)' 'T33b: journal line carries the age and the degradation word'
[[ -z "$(find "$CACHE" -name probe-cooldown-until -path '*t32*')" ]] && pass "T33c: 429 round wrote no cooldown markers" || fail "T33c" "cooldown marker written on a 429 round"
[[ "$RC" -eq 0 ]] && pass "T33: exit 0" || fail "T33 exit" "rc=$RC"

echo "=== T34: a stale gap BELOW the yield margin does not yield -- 154b2cbe margin still rules ==="
win_json 3 0.63 > "$FIX/margp.json"
win_json 42 0.55 > "$FIX/margw.json"
printf 'margp\t%s\tfile:%s/cred.json\n' "$tmp/dir-t34p" "$tmp/dir-t34p" > "$REG"
printf 'margw\t%s\tfile:%s/cred.json\n' "$tmp/dir-t34w" "$tmp/dir-t34w" >> "$REG"
run_select $(base_env)   # seed sidecars (healthy)
err429_json unknown > "$FIX/margp.json"
err429_json unknown > "$FIX/margw.json"
run_select $(base_env) LEADV2_CLAUDE_PROFILE_DEMOTE_DIR="$tmp/dir-t34p"
check_grep "$OUT" '^profile=margw .*source=stale reason=last_known ' 'T34a: gap 0\.63-0.55=0.08 < 0.15 -> demotion holds, the non-demoted stale wins'
check_nogrep "$OUT" 'demote_yielded' 'T34b: no yield below the margin'
[[ "$RC" -eq 0 ]] && pass "T34: exit 0" || fail "T34 exit" "rc=$RC"

echo "=== T35: stale-but-known (demoted) vs a fresh nothing -> yield, not demotion order ==="
printf 'stalep\t%s\tfile:%s/cred.json\n' "$tmp/dir-t35p" "$tmp/dir-t35p" > "$REG"
printf 'freshw\t%s\tfile:%s/cred.json\n' "$tmp/dir-t35w" "$tmp/dir-t35w" >> "$REG"
win_json 3 0.63 > "$FIX/stalep.json"
err429_json unknown > "$FIX/freshw.json"
run_select $(base_env)   # stalep seeds its sidecar; freshw never succeeds
err429_json unknown > "$FIX/stalep.json"
run_select $(base_env) LEADV2_CLAUDE_PROFILE_DEMOTE_DIR="$tmp/dir-t35p"
check_grep "$OUT" '^profile=stalep .*source=stale reason=last_known .*demote_yielded=stalep margin=- yield_reason=no_known_normal' 'T35a: the stale-known demoted slot beats the fresh nothing, yield named'
[[ "$RC" -eq 0 ]] && pass "T35: exit 0" || fail "T35 exit" "rc=$RC"

echo "=== T36: a live reading anywhere keeps the decision on live numbers only ==="
win_json 3 0.63 > "$FIX/livep.json"
win_json 80 0.13 > "$FIX/livew.json"
printf 'livep\t%s\tfile:%s/cred.json\n' "$tmp/dir-t33p" "$tmp/dir-t33p" > "$REG"
printf 'livew\t%s\tfile:%s/cred.json\n' "$tmp/dir-t33w" "$tmp/dir-t33w" >> "$REG"
run_select $(base_env)   # seed sidecars on both buckets
err429_json unknown > "$FIX/livep.json"   # livep's meter now 429 (sidecar stays)
# Demote the 429 slot, NOT the live one: §1.3 says an unknown-triable beats a
# DEMOTED live record (founder line, unchanged by this task); what T36 pins is
# that stale data does not engage while any live record exists.
run_select $(base_env) LEADV2_CLAUDE_PROFILE_DEMOTE_DIR="$tmp/dir-t33p"
check_grep "$OUT" '^profile=livew .*consumed_pct=80 usable_now=0\.130 source=live reason=binding_window' 'T36a: live 80%% beats stale 3%% -- stale never competes with a live reading'
check_nogrep "$OUT" 'source=stale' 'T36b: no stale source in the line while a live record exists'
check_grep "$OUT" 'windows=livep:-=-\|' 'T36c: the unmeasurable livep shows no window, stale not displayed as live'
[[ "$RC" -eq 0 ]] && pass "T36: exit 0" || fail "T36 exit" "rc=$RC"

printf '[TEST] Results: PASS=%d FAIL=%d\n' "$PASS" "$FAIL"
(( FAIL == 0 ))
