#!/usr/bin/env bash
# run-all-triggers: leadv2-claude-profile-select.sh
# SELECTOR-SKIPS-EXHAUSTED-01 acceptance suite.
# Negative control (run by leadv2-mutation-control.sh): inside
# filter_exhausted_candidates, return the exhausted record to the picker.  The
# all-exhausted case below must then go red.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SELECTOR="${SCRIPT_DIR}/../leadv2-claude-profile-select.sh"
tmp="$(mktemp -d "${TMPDIR:-/tmp}/selector-skips-exhausted.XXXXXX")"
trap 'rm -rf "$tmp"' EXIT

mkdir -p "$tmp/default" "$tmp/default-profile" "$tmp/exhausted" "$tmp/good"
printf '{"claudeAiOauth":{"subscriptionType":"max","expiresAt":9999999999999}}\n' > "$tmp/default/.credentials.json"
printf '{"oauthAccount":{"emailAddress":"inherited@fixture.test"}}\n' > "$tmp/default/.claude.json"
for slot in default-profile exhausted good; do
  printf '{"claudeAiOauth":{"subscriptionType":"max","expiresAt":9999999999999}}\n' > "$tmp/${slot}/.credentials.json"
  printf '{"oauthAccount":{"emailAddress":"%s@fixture.test"}}\n' "$slot" > "$tmp/${slot}/.claude.json"
done

registry="$tmp/registry.tsv"
printf 'default\t%s\tfile:%s/.credentials.json\n' "$tmp/default-profile" "$tmp/default-profile" > "$registry"
printf '5a3c2328\t%s\tfile:%s/.credentials.json\n' "$tmp/exhausted" "$tmp/exhausted" >> "$registry"
printf 'eb6c5b97\t%s\tfile:%s/.credentials.json\n' "$tmp/good" "$tmp/good" >> "$registry"

probe="$tmp/probe.sh"
printf '%s\n' \
  '#!/usr/bin/env python3' \
  'import json, os' \
  'label = os.environ.get("LEADV2_CLAUDE_PROFILE_LABEL", "")' \
  'payloads = {' \
  '  "default": {"provider":"anthropic","status":"ok","accounts":[{"active":True,"status":"unknown","error":"http 401"}]},' \
  '  "5a3c2328": {"provider":"anthropic","status":"ok","accounts":[{"active":True,"status":"ok","binding_window":"five_hour","five_hour_pct":100.0,"five_hour":{"pct":100.0,"usable_now":0.0,"reset_iso":"2026-09-10T20:00:00Z"},"seven_day":{"pct":65.0,"usable_now":0.0,"reset_iso":"2026-09-11T20:00:00Z"}}]},' \
  '  "eb6c5b97": {"provider":"anthropic","status":"ok","accounts":[{"active":True,"status":"ok","binding_window":"five_hour","five_hour_pct":5.0,"five_hour":{"pct":5.0,"usable_now":95.0,"reset_iso":"2026-09-10T20:00:00Z"},"seven_day":{"pct":54.0,"usable_now":46.0,"reset_iso":"2026-09-11T20:00:00Z"}}]}' \
  '}' \
  'if os.environ.get("LEADV2_TEST_EXHAUST_ALL") == "1" and label == "eb6c5b97": label = "5a3c2328"' \
  'print(json.dumps(payloads[label]))' > "$probe"
chmod +x "$probe"

run_selector() {
  local exhaust_all="${1:-0}"
  env LEADV2_CLAUDE_MULTIPROFILE=1 \
    LEADV2_CLAUDE_PROFILES_FILE="$registry" \
    LEADV2_CLAUDE_PROFILE_PROBE="$probe" \
    LEADV2_CLAUDE_PROFILE_DEFAULT_DIR="$tmp/default" \
    LEADV2_CLAUDE_PROFILE_DEMOTE_DIR=off \
    LEADV2_TEST_EXHAUST_ALL="$exhaust_all" \
    LEADV2_QUOTA_CACHE_DIR="$tmp/cache" \
    bash "$SELECTOR" 2>"$tmp/err"
}

out="$(run_selector 0)"; rc=$?
[[ "$rc" -eq 0 ]] || { printf 'FAIL: mixed fixture rc=%s out=%s\n' "$rc" "$out"; exit 1; }
[[ "$out" == profile=eb6c5b97\ config_dir=* ]] || { printf 'FAIL: expected eb6c5b97, got %s\n' "$out"; exit 1; }
[[ "$out" == *'source=live'* && "$out" != *'profile=5a3c2328'* ]] || { printf 'FAIL: exhausted profile selected: %s\n' "$out"; exit 1; }
[[ "$out" != *'reason=all_unknown'* ]] || { printf 'FAIL: readable-window outcome called all_unknown: %s\n' "$out"; exit 1; }
printf 'PASS: 401 default + exhausted 5a3c2328 + usable eb6c5b97 selects eb6c5b97\n'

printf '5a3c2328\t%s\tfile:%s/.credentials.json\n' "$tmp/exhausted" "$tmp/exhausted" > "$registry"
printf 'eb6c5b97\t%s\tfile:%s/.credentials.json\n' "$tmp/good" "$tmp/good" >> "$registry"
out="$(run_selector 1)"; rc=$?
[[ "$rc" -eq 4 ]] || { printf 'FAIL: all-exhausted rc=%s out=%s\n' "$rc" "$out"; exit 1; }
[[ "$out" == profile=-\ reason=all_exhausted\ candidates=2\ resets=* ]] || { printf 'FAIL: expected all_exhausted with resets, got %s\n' "$out"; exit 1; }
[[ "$out" == *'2026-09-10T20:00:00Z'* ]] || { printf 'FAIL: reset list is empty or wrong: %s\n' "$out"; exit 1; }
printf 'PASS: both exhausted candidates refuse with all_exhausted and reset timestamps\n'
