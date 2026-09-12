#!/usr/bin/env bash
# 429-METER-VERDICT-01 — reproduction of the measured chain, steps 1-4, on
# fixtures (the live 429 had cleared by the time this lane ran: both identity
# caches read status=ok / http 200 at 2026-09-12T20:12Z).
#
# BEFORE = selector/picker from b7469eff^ (git archive), AFTER = HEAD.
# Hermetic: stub probe, fixture registry, no network, no keychain.
set -uo pipefail

R="$(cd "$(dirname "$0")" && pwd)"
PREFIX="${PREFIX:-/tmp/hd-prefix}"     # git archive of b7469eff^ (pre-fix)
HEADD="${HEADD:-/tmp/hd-audit}"        # git archive of HEAD (fixed)
PRE_SEL="$PREFIX/plugins/leadv2/scripts/leadv2-claude-profile-select.sh"
HEAD_SEL="$HEADD/plugins/leadv2/scripts/leadv2-claude-profile-select.sh"
HEAD_STATUS="$HEADD/plugins/leadv2/scripts/leadv2-claude-profile-status.sh"

FIX="$R/fixtures"; CACHE="$R/cache"; REG="$R/registry.tsv"
rm -rf "$FIX" "$CACHE"; mkdir -p "$FIX" "$CACHE"

for p in personal work; do
  mkdir -p "$R/dir-$p"
  printf '{"oauthAccount":{"emailAddress":"%s@fixture.test"}}' "$p" > "$R/dir-$p/.claude.json"
  printf '{"claudeAiOauth":{"accessToken":"sk-ant-fixture-%s","subscriptionType":"%s","expiresAt":%s}}' \
    "$p" "$([[ $p == personal ]] && echo max || echo team)" "$(( $(date +%s) * 1000 + 3600000 ))" \
    > "$R/dir-$p/cred.json"
done
mkdir -p "$R/dir-default"
printf '{"claudeAiOauth":{"accessToken":"sk-ant-fixture","subscriptionType":"max","expiresAt":%s}}' \
  "$(( $(date +%s) * 1000 + 3600000 ))" > "$R/dir-default/.credentials.json"
printf '{"oauthAccount":{"emailAddress":"default@fixture.test"}}' > "$R/dir-default/.claude.json"
printf 'personal\t%s\tfile:%s/cred.json\n' "$R/dir-personal" "$R/dir-personal" > "$REG"
printf 'work\t%s\tfile:%s/cred.json\n' "$R/dir-work" "$R/dir-work" >> "$REG"

STUB="$R/stub-probe.py"
cat > "$STUB" <<'PY'
#!/usr/bin/env python3
import json, os, sys
label = os.environ.get("LEADV2_CLAUDE_PROFILE_LABEL", "")
path = os.path.join(os.environ["STUB_FIXDIR"], label + ".json")
if os.path.exists(path):
    print(open(path).read())
else:
    print(json.dumps({"provider": "anthropic", "status": "unknown", "accounts": []}))
PY

# Healthy payloads mirroring the founder-panel numbers from the incident:
# personal max_20x seven_day ~4% (usable 0.63), work Team/5x seven_day ~81% (usable 0.13).
win_json() { # <label> <7d_pct> <7d_usable> <sub>
  printf '{"provider":"anthropic","status":"ok","accounts":[{"entry_suffix":"file","service":"file:stub","subscription_type":"%s","http":200,"account_label":"%s","active":true,"status":"ok","account_state":"ok","five_hour_pct":6,"seven_day_pct":%s,"five_hour":{"pct":6,"reset_iso":"2026-09-13T00:00:00Z","remaining_pct":94,"hours_to_reset":3.4,"usable_now":24.2},"seven_day":{"pct":%s,"reset_iso":"2026-09-18T22:00:00Z","remaining_pct":%s,"hours_to_reset":145.8,"usable_now":%s},"binding_window":"seven_day"}],"active_account":"%s","binding_window":"seven_day","fetched_at":"%s"}' \
    "$4" "$4" "$2" "$2" "$(( 100 - $2 ))" "$3" "$4" "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
win_json personal 4 0.63 max_20x > "$FIX/personal-ok.json"
win_json work 81 0.13 max_5x   > "$FIX/work-ok.json"
# The exact payload shape the quota layer writes when the usage meter 429s
# (measured live 2026-09-12 on both identities).
cat > "$FIX/personal-429.json" <<'EOF'
{"provider":"anthropic","status":"unknown","accounts":[{"entry_suffix":"eb6c5b97","service":"Claude Code-credentials-eb6c5b97","subscription_type":"max","tier":"default_claude_max_20x","http":429,"account_label":"max_20x","active":true,"status":"unknown","account_state":"unknown","error":"429 rate_limited (reported as unknown, NEVER 0)","five_hour":null,"seven_day":null,"binding_window":null}],"active_account":"max_20x","usable_now":null,"binding_window":null,"five_hour":null,"seven_day":null,"fetched_at":"2026-09-12T12:07:42Z"}
EOF
sed 's/eb6c5b97/5a3c2328/g; s/max_20x/max_5x/g; s/default_claude_max_20x/default_claude_max_5x/g; s/"max"/"team"/' \
  "$FIX/personal-429.json" > "$FIX/work-429.json"

pay() { cp "$FIX/personal-$1.json" "$FIX/personal.json"; cp "$FIX/work-$1.json" "$FIX/work.json"; }

run_sel() { # <bin> [extra env...] -> OUT/ERR/RC
  local bin="$1"; shift
  OUT="$(env STUB_FIXDIR="$FIX" \
    LEADV2_CLAUDE_MULTIPROFILE=1 \
    LEADV2_CLAUDE_PROFILES_FILE="$REG" \
    LEADV2_CLAUDE_PROFILE_PROBE="$STUB" \
    LEADV2_QUOTA_CACHE_DIR="$CACHE" \
    LEADV2_CLAUDE_PROFILE_DEFAULT_DIR="$R/dir-default" \
    LEADV2_CLAUDE_PROFILE_COOLDOWN_S=900 \
    "$@" bash "$bin" 2>"$R/sel.err")"; RC=$?
  ERR="$(cat "$R/sel.err")"
}
cds() { find "$CACHE" -name probe-cooldown-until -exec sh -c 'echo "$1=$(cat "$1")"' _ {} \; | sort; }

echo "############ STEP 0 (seed, AFTER binary): healthy meters ############"
pay ok
run_sel "$HEAD_SEL"
echo "stdout: $OUT"
echo

echo "############ STEP 1: the usage meter returns HTTP 429 for BOTH identities ############"
pay 429
echo "-- payload now on disk for both identities (identity-*/anthropic.json would carry this):"
head -c 400 "$FIX/personal.json"; echo " ..."
echo

echo "############ STEP 2 (BEFORE, b7469eff^): a 429 is treated as a confirmed live failure ############"
run_sel "$PRE_SEL"
echo "-- stderr (WARN lines):"; printf '%s\n' "$ERR" | grep "WARN" || echo "(no warns)"
echo "-- cooldown markers written:"; cds
echo

echo "############ STEP 3 (BEFORE): both cooled in the same second -> selector refuses ############"
run_sel "$PRE_SEL"
echo "stdout: $OUT (rc=$RC)"
echo "-- status.sh sees the same state:"
env STUB_FIXDIR="$FIX" LEADV2_CLAUDE_MULTIPROFILE=1 \
  LEADV2_CLAUDE_PROFILES_FILE="$REG" LEADV2_CLAUDE_PROFILE_PROBE="$STUB" \
  LEADV2_QUOTA_CACHE_DIR="$CACHE" LEADV2_CLAUDE_PROFILE_DEFAULT_DIR="$R/dir-default" \
  LEADV2_CLAUDE_PROFILE_COOLDOWN_S=900 \
  LEADV2_CLAUDE_PROFILE_STATUS_SELECT_BIN="$PRE_SEL" \
  LEADV2_CLAUDE_PROFILE_STATUS_HANDOFF_DIR="$R/no-handoff" \
  bash "$HEAD_STATUS" 2>/dev/null | sed -n '2,3p'
echo

echo "############ STEP 4 (BEFORE): cooldowns cleared by hand -> 429 recurs -> rank_by=none, demotion picks backwards ############"
find "$CACHE" -name 'probe-cooldown-until*' -delete
run_sel "$PRE_SEL" LEADV2_CLAUDE_PROFILE_DEMOTE_DIR="$R/dir-personal"
echo "stdout: $OUT"
echo "-- and the cooldowns are right back:"
cds
echo

echo "############ AFTER (HEAD): same 429 fixtures, sidecars from step 0, personal demoted ############"
find "$CACHE" -name 'probe-cooldown-until*' -delete
run_sel "$HEAD_SEL" LEADV2_CLAUDE_PROFILE_DEMOTE_DIR="$R/dir-personal"
echo "stdout: $OUT"
echo "-- stderr (degradation journal lines):"; printf '%s\n' "$ERR" | grep -E "unmeasurable|cooling down" || echo "(none)"
echo "-- cooldown markers after the 429 round (must be none):"; cds; echo "(end)"
echo "-- status.sh surfaces the stale ranking:"
env STUB_FIXDIR="$FIX" LEADV2_CLAUDE_MULTIPROFILE=1 \
  LEADV2_CLAUDE_PROFILES_FILE="$REG" LEADV2_CLAUDE_PROFILE_PROBE="$STUB" \
  LEADV2_QUOTA_CACHE_DIR="$CACHE" LEADV2_CLAUDE_PROFILE_DEFAULT_DIR="$R/dir-default" \
  LEADV2_CLAUDE_PROFILE_COOLDOWN_S=900 \
  LEADV2_CLAUDE_PROFILE_STATUS_SELECT_BIN="$HEAD_SEL" \
  LEADV2_CLAUDE_PROFILE_STATUS_HANDOFF_DIR="$R/no-handoff" \
  bash "$HEAD_STATUS" 2>/dev/null | sed -n '2,4p'
