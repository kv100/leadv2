#!/usr/bin/env bash
# test-degraded-select-is-distinguishable-01.sh
#
# A-DEGRADED-PROFILE-SELECT-EXITS-ZERO-01 (founder 2026-09-16): a degraded
# selection (every probe failed / registry unusable / dependencies missing)
# must be distinguishable by the caller from a ranked one, WITHOUT breaking
# the pinned fail-open contract -- exit code 0 and the exact stdout line
# `profile=- reason=single_profile` stay byte-identical (test-claude-
# profile-select.sh T2/T3/T8 and test-claude-profile-requested.sh case 4 pin
# them).  The distinguishability is the machine-readable sidecar
# ${LEADV2_QUOTA_CACHE_DIR}/degraded-select.json: written (best-effort) by
# every degraded entrance, cleared by the next healthy ranked pick.
# The --requested-profile hard-refusal paths (exit 3/5) are already loud and
# must remain marker-free -- a refusal is not a degraded selection.
set -uo pipefail

SEL="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/leadv2-claude-profile-select.sh"
tmp="$(mktemp -d /tmp/degraded-select-01.XXXXXX)" || exit 2
trap 'rm -rf "$tmp"' EXIT
REG="$tmp/reg.tsv"
CACHE="$tmp/cache"
MARKER="$CACHE/degraded-select.json"
mkdir -p "$CACHE" "$tmp/dir-a" "$tmp/dir-b"

FAIL=0
pass() { echo "[degraded-select-01] PASS: $1"; }
fail() { echo "[degraded-select-01] FAIL: $1 -- $2"; FAIL=1; }
check_grep() { grep -qE "$2" <<<"$1" && pass "$3" || fail "$3" "no match for '$2' in: $1"; }

# python3 probe stubs (the selector invokes $PROBE with python3)
cat > "$tmp/badprobe.py" <<'PY'
import sys
sys.exit(1)
PY
cat > "$tmp/goodprobe.py" <<'PY'
import os
if os.environ.get("LEADV2_CLAUDE_PROFILE_LABEL") == "a":
    print('{"status":"ok","accounts":[{"active":true,"status":"ok","binding_window":"seven_day","seven_day":{"usable_now":80.0}}]}')
else:
    print('{"status":"ok","accounts":[{"active":true,"status":"ok","binding_window":"seven_day","seven_day":{"usable_now":20.0}}]}')
PY

base_env() {
  echo "LEADV2_CLAUDE_MULTIPROFILE=1" \
    "LEADV2_CLAUDE_PROFILES_FILE=$REG" \
    "LEADV2_QUOTA_CACHE_DIR=$CACHE" \
    "LEADV2_CLAUDE_PROFILE_DEFAULT_DIR=$tmp/dir-a" \
    "LEADV2_CLAUDE_PROFILE_DEMOTE_DIR=off"
}
run_select() {
  # env operand ordering: LAST operand wins, so caller overrides come after
  # the defaults (env-operand-override-ordering).
  OUT="$(env LEADV2_CLAUDE_MULTIPROFILE=1 \
        LEADV2_CLAUDE_PROFILES_FILE="$REG" \
        LEADV2_QUOTA_CACHE_DIR="$CACHE" \
        LEADV2_CLAUDE_PROFILE_DEFAULT_DIR="$tmp/dir-a" \
        LEADV2_CLAUDE_PROFILE_DEMOTE_DIR=off \
        "$@" \
        bash "$SEL" 2>"$tmp/err")"
  RC=$?
}

printf 'a\t%s\tfile:%s/cred.json\n' "$tmp/dir-a" "$tmp/dir-a" > "$REG"
printf 'b\t%s\tfile:%s/cred.json\n' "$tmp/dir-b" "$tmp/dir-b" >> "$REG"

echo "=== T1: every probe fails -> degraded marker written, contract bytes intact ==="
run_select LEADV2_CLAUDE_PROFILE_PROBE="$tmp/badprobe.py"
[[ "$RC" -eq 0 ]] && pass "T1: exit 0 (fail-open preserved)" || fail "T1 rc" "rc=$RC"
[[ "$OUT" == "profile=- reason=single_profile" ]] \
  && pass "T1: stdout byte-identical" || fail "T1 stdout" "out='$OUT'"
[[ -s "$MARKER" ]] && pass "T1: marker written" || fail "T1 marker" "missing $MARKER"
marker_reason() { python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["reason_code"])' "$MARKER" 2>/dev/null; }
[[ "$(marker_reason)" == "no_probe_completed" ]] \
  && pass "T1: reason_code=no_probe_completed" || fail "T1 reason" "$(marker_reason)"

echo "=== T2: healthy ranked pick clears the marker ==="
run_select LEADV2_CLAUDE_PROFILE_PROBE="$tmp/goodprobe.py"
[[ "$RC" -eq 0 && "$OUT" == profile=a* ]] && pass "T2: ranked pick" || fail "T2 pick" "rc=$RC out='$OUT'"
[[ ! -e "$MARKER" ]] && pass "T2: marker cleared by ranked selection" || fail "T2 marker" "still present"

echo "=== T3: registry missing -> degraded marker registry_unreadable ==="
run_select LEADV2_CLAUDE_PROFILE_PROBE="$tmp/goodprobe.py" LEADV2_CLAUDE_PROFILES_FILE="$tmp/nope.tsv"
[[ "$RC" -eq 0 && -s "$MARKER" && "$(marker_reason)" == "registry_unreadable" ]] \
  && pass "T3: marker registry_unreadable, exit 0" || fail "T3" "rc=$RC reason=$(marker_reason)"

echo "=== T4: single valid entry -> fewer_than_two_candidates ==="
printf 'a\t%s\tfile:%s/cred.json\n' "$tmp/dir-a" "$tmp/dir-a" > "$REG"
run_select LEADV2_CLAUDE_PROFILE_PROBE="$tmp/goodprobe.py"
[[ "$RC" -eq 0 && -s "$MARKER" && "$(marker_reason)" == "fewer_than_two_candidates" ]] \
  && pass "T4: marker fewer_than_two_candidates, exit 0" || fail "T4" "rc=$RC reason=$(marker_reason)"

echo "=== T5: opt-in unset -> inert, NO marker (deliberate opt-out is not degradation) ==="
rm -f "$MARKER"
# MULTIPROFILE=0 (not 1) pins the opt-out even if the harnessing session
# exports LEADV2_CLAUDE_MULTIPROFILE=1 into this suite's environment.
OUT="$(env LEADV2_CLAUDE_MULTIPROFILE=0 \
      LEADV2_CLAUDE_PROFILE_REQUESTED= \
      LEADV2_CLAUDE_PROFILES_FILE="$REG" LEADV2_QUOTA_CACHE_DIR="$CACHE" \
      LEADV2_CLAUDE_PROFILE_PROBE="$tmp/goodprobe.py" \
      bash "$SEL" 2>/dev/null)"; RC=$?
[[ "$RC" -eq 0 && -z "$OUT" && ! -e "$MARKER" ]] \
  && pass "T5: inert opt-out untouched, no marker" || fail "T5" "rc=$RC out='$OUT' marker=$(ls "$MARKER" 2>/dev/null)"

echo "=== T6: --requested-profile unknown label -> exit 3, no marker (already loud) ==="
printf 'a\t%s\tfile:%s/cred.json\n' "$tmp/dir-a" "$tmp/dir-a" > "$REG"
printf 'b\t%s\tfile:%s/cred.json\n' "$tmp/dir-b" "$tmp/dir-b" >> "$REG"
rm -f "$MARKER"
OUT="$(env LEADV2_CLAUDE_MULTIPROFILE=1 LEADV2_CLAUDE_PROFILE_REQUESTED=ghost \
      LEADV2_CLAUDE_PROFILES_FILE="$REG" LEADV2_QUOTA_CACHE_DIR="$CACHE" \
      LEADV2_CLAUDE_PROFILE_PROBE="$tmp/goodprobe.py" \
      LEADV2_CLAUDE_PROFILE_DEFAULT_DIR="$tmp/dir-a" \
      bash "$SEL" 2>/dev/null)"; RC=$?
[[ "$RC" -eq 3 && "$OUT" == "profile=- reason=requested_profile_unknown requested=ghost" && ! -e "$MARKER" ]] \
  && pass "T6: hard refusal unchanged, marker-free" || fail "T6" "rc=$RC out='$OUT'"

echo "=== T7: requested profile + failing probe -> exit 3 requested_profile_unavailable, no marker ==="
OUT="$(env LEADV2_CLAUDE_MULTIPROFILE=1 LEADV2_CLAUDE_PROFILE_REQUESTED=a \
      LEADV2_CLAUDE_PROFILES_FILE="$REG" LEADV2_QUOTA_CACHE_DIR="$CACHE" \
      LEADV2_CLAUDE_PROFILE_PROBE="$tmp/badprobe.py" \
      LEADV2_CLAUDE_PROFILE_DEFAULT_DIR="$tmp/dir-a" \
      bash "$SEL" 2>/dev/null)"; RC=$?
[[ "$RC" -eq 3 && "$OUT" == "profile=- reason=requested_profile_unavailable requested=a" && ! -e "$MARKER" ]] \
  && pass "T7: requested-unavailable refusal, marker-free" || fail "T7" "rc=$RC out='$OUT'"

echo "=== T8: marker JSON shape is machine-readable (kind/exit/detected_at) ==="
run_select LEADV2_CLAUDE_PROFILE_PROBE="$tmp/badprobe.py"
python3 -c '
import json, sys
d = json.load(open(sys.argv[1]))
assert d["kind"] == "degraded_select", d
assert d["exit"] == 0, d
assert d["stdout"] == "profile=- reason=single_profile", d
assert d["reason_code"] == "no_probe_completed", d
assert d["detected_at"].endswith("Z"), d
' "$MARKER" && pass "T8: marker JSON shape" || fail "T8" "shape invalid"

if [[ "$FAIL" == "1" ]]; then echo "[degraded-select-01] FAILED"; exit 1; fi
echo "[degraded-select-01] All checks passed"
