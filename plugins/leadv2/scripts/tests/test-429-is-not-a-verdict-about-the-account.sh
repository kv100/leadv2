#!/usr/bin/env bash
# changed-scope triggers, self-registered (discovered by scan_suite_triggers):
# run-all-triggers: leadv2-claude-profile-select leadv2-claude-profile-pick
#
# test-429-is-not-a-verdict-about-the-account.sh — 429-METER-VERDICT-01.
#
# The production selector and picker are always real. The sole fake is
# LEADV2_CLAUDE_PROFILE_PROBE, the HTTP-transport seam immediately below the
# selector. This pins meter 429, stale ranking, credential-surface 429, and
# stale self-slot-demote yielding in a direct acceptance probe.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
SELECT_BIN="${LEADV2_TEST_SELECT_BIN:-${SCRIPTS_ROOT}/leadv2-claude-profile-select.sh}"

PASS=0
FAIL=0
pass() { PASS=$((PASS + 1)); printf '[TEST] PASS: %s\n' "$1"; }
fail() { FAIL=$((FAIL + 1)); printf '[TEST] FAIL: %s\n' "$1"; }
has() { grep -qE -- "$2" <<<"$1"; }
missing() { ! grep -qE -- "$2" <<<"$1"; }

tmp="$(mktemp -d "${TMPDIR:-/tmp}/429-verdict-account.XXXXXX")"
trap 'rm -rf "$tmp"' EXIT
fix="$tmp/fixtures"
cache="$tmp/cache"
registry="$tmp/registry.tsv"
seen="$tmp/probe-seen"
mkdir -p "$fix" "$cache" "$tmp/default" "$tmp/meter" "$tmp/live" \
         "$tmp/personal" "$tmp/work" "$tmp/revoked"

# Prevent every fixture call from touching the user's inherited Claude slot.
printf '{"claudeAiOauth":{"accessToken":"fixture","subscriptionType":"max","expiresAt":9999999999999}}' > "$tmp/default/.credentials.json"
printf '{"oauthAccount":{"emailAddress":"default@fixture.test"}}' > "$tmp/default/.claude.json"

# Transport fake: the selector selects an account and the fake HTTP layer
# returns that account's canned response. The selector/picker are never stubbed.
probe="$tmp/probe.py"
cat > "$probe" <<'PY'
#!/usr/bin/env python3
import os
label = os.environ.get("LEADV2_CLAUDE_PROFILE_LABEL", "")
seen = os.environ.get("PROBE_SEEN")
if seen:
    with open(seen, "a") as f:
        f.write(label + "\n")
path = os.path.join(os.environ["PROBE_FIXTURES"], label + ".json")
with open(path) as f:
    print(f.read())
PY
chmod +x "$probe"

meter_429() {
  printf '{"provider":"anthropic","status":"ok","accounts":[{"active":true,"status":"unknown","account_state":"unknown","http":429,"error":"429 rate_limited","five_hour":null,"seven_day":null,"binding_window":null}],"active_account":"fixture"}'
}
healthy() { # <seven-day consumed pct> <usable now>
  printf '{"provider":"anthropic","status":"ok","accounts":[{"active":true,"status":"ok","account_state":"ok","http":200,"five_hour_pct":5,"seven_day_pct":%s,"five_hour":{"pct":5,"usable_now":30},"seven_day":{"pct":%s,"usable_now":%s},"binding_window":"seven_day"}],"active_account":"fixture","fetched_at":"%s"}' \
    "$1" "$1" "$2" "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
credential_429() {
  # Paired control: HTTP 429 is present, but a credential-specific error is too.
  printf '{"provider":"anthropic","status":"ok","accounts":[{"active":true,"status":"unknown","account_state":"unknown","http":429,"error":"credential revoked after HTTP 429","binding_window":null}],"active_account":"fixture"}'
}
write_registry() { # alternating label and directory
  : > "$registry"
  while [[ $# -gt 0 ]]; do
    printf '%s\t%s\tfile:%s/cred.json\n' "$1" "$2" "$2" >> "$registry"
    shift 2
  done
}
run_select() {
  OUT="$(env PROBE_FIXTURES="$fix" PROBE_SEEN="$seen" \
    LEADV2_CLAUDE_MULTIPROFILE=1 \
    LEADV2_CLAUDE_PROFILES_FILE="$registry" \
    LEADV2_CLAUDE_PROFILE_PROBE="$probe" \
    LEADV2_QUOTA_CACHE_DIR="$cache" \
    LEADV2_CLAUDE_PROFILE_DEFAULT_DIR="$tmp/default" \
    LEADV2_CLAUDE_PROFILE_COOLDOWN_S=900 \
    "$@" bash "$SELECT_BIN" 2>"$tmp/selector.err")"
  RC=$?
  ERR="$(cat "$tmp/selector.err")"
}

echo '=== meter 429: no credential verdict and no cooldown ==='
meter_429 > "$fix/meter.json"
healthy 80 0.13 > "$fix/live.json"
write_registry meter "$tmp/meter" live "$tmp/live"
run_select
if [[ "$RC" -eq 0 ]] && has "$OUT" '^profile=live ' && missing "$ERR" 'reason=confirmed_live_failure'; then
  pass 'usage-meter 429 is not reason=confirmed_live_failure'
else
  fail "meter 429 first selector output was rc=${RC}: ${OUT}; ${ERR}"
fi
if ! find "$cache" -name probe-cooldown-until -type f | grep -q .; then
  pass 'usage-meter 429 writes no probe cooldown'
else
  fail 'usage-meter 429 wrote a probe cooldown'
fi
run_select
meter_calls="$(grep -c '^meter$' "$seen" 2>/dev/null || true)"
if [[ "$meter_calls" -eq 2 ]] && missing "$ERR" 'cooling down after a recent live probe failure'; then
  pass 'second meter-429 round probes again instead of skipping cooldown'
else
  fail "meter 429 was not probed twice or was cooled (calls=${meter_calls}; ${ERR})"
fi

echo '=== both meters unreadable: selector ranks last-known sidecars ==='
healthy 3 0.63 > "$fix/personal.json"
healthy 80 0.13 > "$fix/work.json"
write_registry personal "$tmp/personal" work "$tmp/work"
run_select
if [[ "$RC" -eq 0 ]] && has "$OUT" '^profile=personal .*source=live'; then
  pass 'healthy seed round writes selector-owned last-known inputs'
else
  fail "healthy seed round failed: rc=${RC}; ${OUT}; ${ERR}"
fi
meter_429 > "$fix/personal.json"
meter_429 > "$fix/work.json"
run_select "LEADV2_CLAUDE_PROFILE_DEMOTE_DIR=$tmp/personal"
if [[ "$RC" -eq 0 ]] \
   && has "$OUT" '^profile=personal .*rank_by=usable_now_max .*source=stale reason=last_known' \
   && missing "$OUT" 'profile=- reason=single_profile' \
   && missing "$OUT" 'rank_by=none'; then
  pass 'both meter 429s rank selector output from last-known sidecars'
else
  fail "stale ranking collapsed instead of selecting personal: rc=${RC}; ${OUT}; ${ERR}"
fi
if has "$OUT" 'demote_yielded=personal margin=0\.15' && ! find "$cache" -name probe-cooldown-until -type f | grep -q .; then
  pass 'stale known capacity gap still yields self-slot demotion without cooldown'
else
  fail "stale gap did not compose with demote yield or wrote cooldown: ${OUT}; ${ERR}"
fi

echo '=== credential-surface 429: still a credential verdict ==='
credential_429 > "$fix/revoked.json"
healthy 80 0.13 > "$fix/live.json"
write_registry revoked "$tmp/revoked" live "$tmp/live"
run_select
if [[ "$RC" -eq 0 ]] && has "$OUT" '^profile=live ' \
   && has "$ERR" 'profile label=revoked live probe failed; cooling down 900s \(reason=confirmed_live_failure'; then
  pass '429 carrying revoked-credential evidence remains a credential verdict'
else
  fail "credential-surface 429 was ignored: rc=${RC}; ${OUT}; ${ERR}"
fi
if find "$cache" -name probe-cooldown-until -type f | grep -q .; then
  pass 'credential-surface verdict writes its cooldown marker'
else
  fail 'credential-surface verdict did not write cooldown marker'
fi

printf '[TEST] Results: PASS=%d FAIL=%d\n' "$PASS" "$FAIL"
(( FAIL == 0 ))
