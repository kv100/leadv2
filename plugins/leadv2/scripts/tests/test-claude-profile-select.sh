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
SELECT_BIN="${SCRIPTS_ROOT}/leadv2-claude-profile-select.sh"
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
      LEADV2_QUOTA_CACHE_DIR CLAUDE_CONFIG_DIR

tmp="$(mktemp -d "${TMPDIR:-/tmp}/claude-profile-select.XXXXXX")"
trap 'rm -rf "$tmp"' EXIT
FIX="${tmp}/fixtures"; CACHE="${tmp}/cache"; REG="${tmp}/registry.tsv"
mkdir -p "$FIX" "$CACHE" "$tmp/dir-alpha" "$tmp/dir-beta"

# Probe stub: canned JSON keyed by the per-profile cache dir the selector
# exports (…/profile-<label>).  A label starting with "hang" sleeps forever.
STUB="${tmp}/stub-probe.py"
cat > "$STUB" <<'PY'
#!/usr/bin/env python3
import json, os, sys, time
cache_dir = os.environ.get("LEADV2_QUOTA_CACHE_DIR", "")
label = cache_dir.rsplit("/profile-", 1)[-1] if "/profile-" in cache_dir else ""
if label.startswith("hang"):
    time.sleep(300)
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
check_grep "$OUT" '^profile=alpha config_dir=.*/dir-alpha score=20 source=live reason=worst_window candidates=2$' 'T4: picks alpha score=20 live'
[[ "$RC" -eq 0 ]] && pass "T4: exit 0" || fail "T4 exit" "rc=$RC"

# ============================================================================
echo "=== T5: one unknown, one ok -> picks ok, source=live ==="
printf 'dead\t%s\tfile:%s/cred.json\n' "$tmp/dir-alpha" "$tmp/dir-alpha" > "$REG"
printf 'beta\t%s\tfile:%s/cred.json\n' "$tmp/dir-beta" "$tmp/dir-beta" >> "$REG"
run_select $(base_env)
check_grep "$OUT" '^profile=beta .*score=80 source=live reason=worst_window candidates=2$' 'T5: picks the ok profile'

# ============================================================================
echo "=== T6: both unknown -> first registry entry, all_unknown ==="
printf 'dead\t%s\tfile:%s/cred.json\n' "$tmp/dir-alpha" "$tmp/dir-alpha" > "$REG"
printf 'dead2\t%s\tfile:%s/cred.json\n' "$tmp/dir-beta" "$tmp/dir-beta" >> "$REG"
cp "$FIX/dead.json" "$FIX/dead2.json"
run_select $(base_env)
check_grep "$OUT" '^profile=dead .*score=101 source=unknown reason=all_unknown candidates=2$' 'T6: first entry, all_unknown'

# ============================================================================
echo "=== T7: malformed line + email-shaped label -> skipped, one warning each ==="
{
  printf 'alpha\t%s\tfile:%s/cred.json\n' "$tmp/dir-alpha" "$tmp/dir-alpha"
  printf 'founder@anthropic.com\t%s\n' "$tmp/dir-beta"
  printf 'just-a-label-no-dir\n'
  printf 'beta\t%s\tfile:%s/cred.json\n' "$tmp/dir-beta" "$tmp/dir-beta"
} > "$REG"
run_select $(base_env)
check_grep "$OUT" '^profile=alpha .*candidates=2$' 'T7: bad lines skipped, both good ones used'
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
check_nogrep "$ERR" '/' 'T9c: selector stderr has no path'

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
check_grep "$(cat "$int_err")" '^\[claude-profile\] selected=alpha score=20 source=live candidates=2$' 'I2b: label-only stderr line shape'
hlog="$repo/docs/handoff/PROFILE-CL/claude-profile.log"
[[ -f "$hlog" ]] && pass "I3: handoff claude-profile.log exists" || fail "I3" "missing $hlog"
if [[ -f "$hlog" ]]; then
  check_grep "$(cat "$hlog")" '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z \[claude-profile\] selected=alpha score=20 source=live candidates=2$' 'I4: ISO-prefixed label-only handoff line'
  check_nogrep "$(cat "$hlog")" 'sk-ant|@|/' 'I5: handoff log has no token, email, or path'
fi
check_nogrep "$(grep '^\[claude-profile\]' "$int_err")" 'sk-ant|@|/' 'I6: profile stderr line has no token, email, or path'

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

printf '[TEST] Results: PASS=%d FAIL=%d\n' "$PASS" "$FAIL"
(( FAIL == 0 ))
