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
#
# Round 2 (reviewer High): marker reads/writes are serialized through
# leadv2-portable-lock.sh and a ranked pick clears only a marker older than
# its own sub-second start, so a degraded write that lands while a healthy
# selection is probing SURVIVES it (T9).  T10 pins the serialization, T11
# pins its fail-open degradation (selector copy without the sibling lock
# helper writes unlocked -- that is what "lock removed" looks like, and it is
# the red side of T10).  T12-T17 cover the six reason codes round 1 shipped
# untested.
set -uo pipefail

SEL="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/leadv2-claude-profile-select.sh"
tmp="$(mktemp -d /tmp/degraded-select-01.XXXXXX)" || exit 2
trap 'rm -rf "$tmp"' EXIT
REG="$tmp/reg.tsv"
CACHE="$tmp/cache"
MARKER="$CACHE/degraded-select.json"
mkdir -p "$CACHE" "$tmp/dir-a" "$tmp/dir-b"
# Hermetic default-slot credential (round 2): a future expiresAt keeps the
# inherited-slot health check off the REAL keychain.  Round 1 silently
# depended on the host's `security` answering for Claude Code-credentials;
# on a host where that entry is absent or stale every rc-0 expectation here
# would flip to a default_token_* exit 4.
printf '{"claudeAiOauth":{"subscriptionType":"pro","expiresAt":4102444800000}}' > "$tmp/dir-a/.credentials.json"

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
# T9's healthy side: succeeds but takes ~1.2s per probe, so its ranked pick
# (and therefore its marker clear) lands well AFTER the fast degraded side
# has already written the marker -- the reviewer's High race, made
# deterministic by construction rather than by timing luck.
cat > "$tmp/slowprobe.py" <<'PY'
import os, time
time.sleep(1.2)
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
# Round-2 tests reset the registry through this helper so T4's single-row
# registry cannot leak into them by ordering.
two_row_registry() {
  printf 'a\t%s\tfile:%s/cred.json\n' "$tmp/dir-a" "$tmp/dir-a" > "$REG"
  printf 'b\t%s\tfile:%s/cred.json\n' "$tmp/dir-b" "$tmp/dir-b" >> "$REG"
}

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

echo "=== T9: concurrent healthy pick must NOT destroy the degraded marker (round 2, reviewer High) ==="
# Degraded side fails fast (~0.5s) and writes the marker; healthy side probes
# for ~2.4s (slowprobe x2) and clears the marker at its ranked pick.  Round 1
# (blind rm) destroyed the marker here every time -- this choreography was
# seen RED against it before the round-2 fix (report.md).
two_row_registry
rm -f "$MARKER"
env LEADV2_CLAUDE_MULTIPROFILE=1 \
    LEADV2_CLAUDE_PROFILES_FILE="$REG" LEADV2_QUOTA_CACHE_DIR="$CACHE" \
    LEADV2_CLAUDE_PROFILE_DEFAULT_DIR="$tmp/dir-a" LEADV2_CLAUDE_PROFILE_DEMOTE_DIR=off \
    LEADV2_CLAUDE_PROFILE_PROBE="$tmp/badprobe.py" \
    bash "$SEL" > "$tmp/t9-degraded.out" 2>/dev/null &
T9D=$!
env LEADV2_CLAUDE_MULTIPROFILE=1 \
    LEADV2_CLAUDE_PROFILES_FILE="$REG" LEADV2_QUOTA_CACHE_DIR="$CACHE" \
    LEADV2_CLAUDE_PROFILE_DEFAULT_DIR="$tmp/dir-a" LEADV2_CLAUDE_PROFILE_DEMOTE_DIR=off \
    LEADV2_CLAUDE_PROFILE_PROBE="$tmp/slowprobe.py" \
    bash "$SEL" > "$tmp/t9-healthy.out" 2>/dev/null &
T9H=$!
wait "$T9D"; T9D_RC=$?
wait "$T9H"; T9H_RC=$?
[[ "$T9D_RC" -eq 0 && "$(cat "$tmp/t9-degraded.out")" == "profile=- reason=single_profile" ]] \
  && pass "T9: degraded side contract bytes intact" || fail "T9 degraded" "rc=$T9D_RC out='$(cat "$tmp/t9-degraded.out")'"
grep -q '^profile=a ' "$tmp/t9-healthy.out" \
  && pass "T9: healthy side made a ranked pick" || fail "T9 healthy pick" "$(cat "$tmp/t9-healthy.out")"
[[ -s "$MARKER" ]] \
  && pass "T9: degraded marker SURVIVED the concurrent healthy pick" \
  || fail "T9 marker survival" "concurrent ranked pick destroyed the degraded signal"
[[ "$(marker_reason)" == "no_probe_completed" ]] \
  && pass "T9: survivor is the degraded signal (reason=no_probe_completed)" \
  || fail "T9 reason" "$(marker_reason)"

echo "=== T10: marker writes are serialized through \${MARKER}.lock ==="
PORTABLE_LOCK="$(cd "$(dirname "$SEL")" && pwd)/leadv2-portable-lock.sh"
# shellcheck disable=SC1091
. "$PORTABLE_LOCK"
two_row_registry
rm -f "$MARKER" "$tmp/t10.leak"
(
  lv2_lock_wait "${MARKER}.lock" 10 >/dev/null 2>&1 || exit 3
  env LEADV2_CLAUDE_MULTIPROFILE=1 \
      LEADV2_CLAUDE_PROFILES_FILE="$REG" LEADV2_QUOTA_CACHE_DIR="$CACHE" \
      LEADV2_CLAUDE_PROFILE_DEFAULT_DIR="$tmp/dir-a" LEADV2_CLAUDE_PROFILE_DEMOTE_DIR=off \
      LEADV2_CLAUDE_PROFILE_PROBE="$tmp/does-not-exist.py" \
      bash "$SEL" >/dev/null 2>&1 &
  sleep 1
  [[ -e "$MARKER" ]] && : > "$tmp/t10.leak"
  exit 0
) 9>"${MARKER}.lock"
T10_APPEARED=0
for _ in $(seq 50); do [[ -e "$MARKER" ]] && { T10_APPEARED=1; break; }; sleep 0.1; done
[[ ! -e "$tmp/t10.leak" ]] \
  && pass "T10: no marker while the lock is held (write serialized)" \
  || fail "T10 serialization" "marker appeared while ${MARKER}.lock was held"
(( T10_APPEARED )) \
  && pass "T10: blocked write lands after release" || fail "T10 post-release" "marker never appeared"

echo "=== T11: lock removed (selector copy without the sibling helper) -> write NOT serialized ==="
# Same bytes, no leadv2-portable-lock.sh next to them: the guarded source
# no-ops and the write lands during the hold.  This is the deterministic RED
# side of T10 (seen RED against the helper-less copy, report.md) and pins the
# fail-open degradation arm-cooldown documents for a missing helper.
mkdir -p "$tmp/nolock"
cp "$SEL" "$tmp/nolock/leadv2-claude-profile-select.sh"
two_row_registry
rm -f "$MARKER" "$tmp/t11.during"
(
  lv2_lock_wait "${MARKER}.lock" 10 >/dev/null 2>&1 || exit 3
  env LEADV2_CLAUDE_MULTIPROFILE=1 \
      LEADV2_CLAUDE_PROFILES_FILE="$REG" LEADV2_QUOTA_CACHE_DIR="$CACHE" \
      LEADV2_CLAUDE_PROFILE_DEFAULT_DIR="$tmp/dir-a" LEADV2_CLAUDE_PROFILE_DEMOTE_DIR=off \
      LEADV2_CLAUDE_PROFILE_PROBE="$tmp/does-not-exist.py" \
      bash "$tmp/nolock/leadv2-claude-profile-select.sh" >/dev/null 2>&1 &
  sleep 1
  [[ -e "$MARKER" ]] && : > "$tmp/t11.during"
  exit 0
) 9>"${MARKER}.lock"
[[ -e "$tmp/t11.during" ]] \
  && pass "T11: helper-less copy writes during the hold (unlocked by design -- the red side)" \
  || fail "T11" "helper-less copy did not write during the hold"

echo "=== T12: reason_code=dependency_missing_probe ==="
two_row_registry
rm -f "$MARKER"
run_select LEADV2_CLAUDE_PROFILE_PROBE="$tmp/does-not-exist.py"
[[ "$RC" -eq 0 && "$OUT" == "profile=- reason=single_profile" && -s "$MARKER" && "$(marker_reason)" == "dependency_missing_probe" ]] \
  && pass "T12: dependency_missing_probe marked, contract bytes intact" \
  || fail "T12" "rc=$RC out='$OUT' reason=$(marker_reason)"

echo "=== T13: reason_code=dependency_missing_picker (selector copy without lib/) ==="
mkdir -p "$tmp/nolib"
cp "$SEL" "$tmp/nolib/leadv2-claude-profile-select.sh"
cp "$(dirname "$SEL")/leadv2-portable-lock.sh" "$tmp/nolib/"
two_row_registry
rm -f "$MARKER"
OUT="$(env LEADV2_CLAUDE_MULTIPROFILE=1 \
      LEADV2_CLAUDE_PROFILES_FILE="$REG" LEADV2_QUOTA_CACHE_DIR="$CACHE" \
      LEADV2_CLAUDE_PROFILE_DEFAULT_DIR="$tmp/dir-a" LEADV2_CLAUDE_PROFILE_DEMOTE_DIR=off \
      LEADV2_CLAUDE_PROFILE_PROBE="$tmp/goodprobe.py" \
      bash "$tmp/nolib/leadv2-claude-profile-select.sh" 2>/dev/null)"; RC=$?
[[ "$RC" -eq 0 && "$OUT" == "profile=- reason=single_profile" && -s "$MARKER" && "$(marker_reason)" == "dependency_missing_picker" ]] \
  && pass "T13: dependency_missing_picker marked, contract bytes intact" \
  || fail "T13" "rc=$RC out='$OUT' reason=$(marker_reason)"

echo "=== T14: reason_code=records_temp_unavailable (mktemp shim fails on the recs template) ==="
REAL_MKTEMP="$(command -v mktemp)"
mkdir -p "$tmp/bin-norecs"
cat > "$tmp/bin-norecs/mktemp" <<SH
#!/usr/bin/env bash
for a in "\$@"; do
  case "\$a" in *claude-profile-recs*) exit 1 ;; esac
done
exec "$REAL_MKTEMP" "\$@"
SH
chmod +x "$tmp/bin-norecs/mktemp"
two_row_registry
rm -f "$MARKER"
OUT="$(env PATH="$tmp/bin-norecs:$PATH" LEADV2_CLAUDE_MULTIPROFILE=1 \
      LEADV2_CLAUDE_PROFILES_FILE="$REG" LEADV2_QUOTA_CACHE_DIR="$CACHE" \
      LEADV2_CLAUDE_PROFILE_DEFAULT_DIR="$tmp/dir-a" LEADV2_CLAUDE_PROFILE_DEMOTE_DIR=off \
      LEADV2_CLAUDE_PROFILE_PROBE="$tmp/goodprobe.py" \
      bash "$SEL" 2>/dev/null)"; RC=$?
[[ "$RC" -eq 0 && "$OUT" == "profile=- reason=single_profile" && -s "$MARKER" && "$(marker_reason)" == "records_temp_unavailable" ]] \
  && pass "T14: records_temp_unavailable marked, contract bytes intact" \
  || fail "T14" "rc=$RC out='$OUT' reason=$(marker_reason)"

echo "=== T15: reason_code=exhausted_filter_failed (mktemp shim fails on the eligible template) ==="
mkdir -p "$tmp/bin-noeligible"
cat > "$tmp/bin-noeligible/mktemp" <<SH
#!/usr/bin/env bash
for a in "\$@"; do
  case "\$a" in *claude-profile-eligible*) exit 1 ;; esac
done
exec "$REAL_MKTEMP" "\$@"
SH
chmod +x "$tmp/bin-noeligible/mktemp"
two_row_registry
rm -f "$MARKER"
OUT="$(env PATH="$tmp/bin-noeligible:$PATH" LEADV2_CLAUDE_MULTIPROFILE=1 \
      LEADV2_CLAUDE_PROFILES_FILE="$REG" LEADV2_QUOTA_CACHE_DIR="$CACHE" \
      LEADV2_CLAUDE_PROFILE_DEFAULT_DIR="$tmp/dir-a" LEADV2_CLAUDE_PROFILE_DEMOTE_DIR=off \
      LEADV2_CLAUDE_PROFILE_PROBE="$tmp/goodprobe.py" \
      bash "$SEL" 2>/dev/null)"; RC=$?
[[ "$RC" -eq 0 && "$OUT" == "profile=- reason=single_profile" && -s "$MARKER" && "$(marker_reason)" == "exhausted_filter_failed" ]] \
  && pass "T15: exhausted_filter_failed marked, contract bytes intact" \
  || fail "T15" "rc=$RC out='$OUT' reason=$(marker_reason)"

echo "=== T16: reason_code=picker_no_result (selector copy, picker exits 1) ==="
mkdir -p "$tmp/badpick/lib"
cp "$SEL" "$tmp/badpick/leadv2-claude-profile-select.sh"
cp "$(dirname "$SEL")/leadv2-portable-lock.sh" "$tmp/badpick/"
printf 'import sys\nsys.exit(1)\n' > "$tmp/badpick/lib/leadv2-claude-profile-pick.py"
two_row_registry
rm -f "$MARKER"
OUT="$(env LEADV2_CLAUDE_MULTIPROFILE=1 \
      LEADV2_CLAUDE_PROFILES_FILE="$REG" LEADV2_QUOTA_CACHE_DIR="$CACHE" \
      LEADV2_CLAUDE_PROFILE_DEFAULT_DIR="$tmp/dir-a" LEADV2_CLAUDE_PROFILE_DEMOTE_DIR=off \
      LEADV2_CLAUDE_PROFILE_PROBE="$tmp/goodprobe.py" \
      bash "$tmp/badpick/leadv2-claude-profile-select.sh" 2>/dev/null)"; RC=$?
[[ "$RC" -eq 0 && "$OUT" == "profile=- reason=single_profile" && -s "$MARKER" && "$(marker_reason)" == "picker_no_result" ]] \
  && pass "T16: picker_no_result marked, contract bytes intact" \
  || fail "T16" "rc=$RC out='$OUT' reason=$(marker_reason)"

echo "=== T17: reason_code=no_rankable_records (selector copy, picker prints profile=-) ==="
mkdir -p "$tmp/emptypick/lib"
cp "$SEL" "$tmp/emptypick/leadv2-claude-profile-select.sh"
cp "$(dirname "$SEL")/leadv2-portable-lock.sh" "$tmp/emptypick/"
printf 'print("profile=- reason=single_profile")\n' > "$tmp/emptypick/lib/leadv2-claude-profile-pick.py"
two_row_registry
rm -f "$MARKER"
OUT="$(env LEADV2_CLAUDE_MULTIPROFILE=1 \
      LEADV2_CLAUDE_PROFILES_FILE="$REG" LEADV2_QUOTA_CACHE_DIR="$CACHE" \
      LEADV2_CLAUDE_PROFILE_DEFAULT_DIR="$tmp/dir-a" LEADV2_CLAUDE_PROFILE_DEMOTE_DIR=off \
      LEADV2_CLAUDE_PROFILE_PROBE="$tmp/goodprobe.py" \
      bash "$tmp/emptypick/leadv2-claude-profile-select.sh" 2>/dev/null)"; RC=$?
[[ "$RC" -eq 0 && "$OUT" == "profile=- reason=single_profile" && -s "$MARKER" && "$(marker_reason)" == "no_rankable_records" ]] \
  && pass "T17: no_rankable_records marked, contract bytes intact" \
  || fail "T17" "rc=$RC out='$OUT' reason=$(marker_reason)"

if [[ "$FAIL" == "1" ]]; then echo "[degraded-select-01] FAILED"; exit 1; fi
echo "[degraded-select-01] All checks passed"
