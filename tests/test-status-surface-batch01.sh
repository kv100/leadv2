#!/usr/bin/env bash
# tests/test-status-surface-batch01.sh — STATUS-SURFACE-BATCH-01
#
# Covers the two rows that needed code changes:
#   - STATUSLINE-FLICKER-PARTIAL-CACHE-01: a failed user command preserves the
#     previous BASE from cache instead of replacing it with FALLBACK_BASE.
#   - SD-STATUSLINE-BURN-FIRSTCLASS-01: the burn segment is NOT dropped by
#     default (DROP_BURN defaults to 0 now), and survives BASE compression.
#
# The tail script is driven directly in a hermetic sandbox (mktemp).  No real
# lane state, no real user settings.json, no real active.yaml.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "${HERE}/.." && pwd)"
TAIL="${ROOT}/plugins/leadv2/scripts/leadv2-lane-status-line-tail.sh"
LINE_MAIN="${ROOT}/plugins/leadv2/scripts/leadv2-lane-status-line.sh"

PASS=0
FAIL=0
ok()  { printf '  ok   - %s\n' "$1"; PASS=$((PASS + 1)); }
bad() { printf '  FAIL - %s\n' "$1"; FAIL=$((FAIL + 1)); }

FIX="$(mktemp -d -t leadv2-batch01)"
trap 'rm -rf "$FIX"' EXIT

# ── shared fixtures ──────────────────────────────────────────────────────────
# A minimal settings.json that points to a stub user command.
SETTINGS="$FIX/settings.json"

# Standard stdin payload the statusLine receives.
make_input() {
  printf '{"model":{"display_name":"TestModel"},"workspace":{"current_dir":"%s"},"context_window":{"remaining_percentage":75}}' "$FIX"
}

write_settings() {
  # $1 = the command to run as the user statusLine
  cat > "$SETTINGS" <<EOF
{"statusLine":{"command":$(printf '%s' "$1" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))')}}
EOF
}

# ════════════════════════════════════════════════════════════════════════════
# T1: FLICKER — user command succeeds, then fails; BASE is preserved
# ════════════════════════════════════════════════════════════════════════════
echo "== T1: FLICKER — failed user command preserves previous BASE =="

CACHE="$FIX/cache"
mkdir -p "$CACHE"

# Stub user command that SUCCEEDS (prints a distinctive base).
STUB_OK="$FIX/stub-ok.sh"
printf '#!/usr/bin/env bash\nprintf "GOOD-BASE model in dir"\n' > "$STUB_OK"
chmod +x "$STUB_OK"

# Stub user command that FAILS (exits 1, no output).
STUB_FAIL="$FIX/stub-fail.sh"
printf '#!/usr/bin/env bash\nexit 1\n' > "$STUB_FAIL"
chmod +x "$STUB_FAIL"

INPUT="$(make_input)"
OUT_FILE="$CACHE/last-known"

# Run 1: user command succeeds → cache has "GOOD-BASE"
write_settings "$STUB_OK"
bash "$TAIL" "$INPUT" "$SETTINGS" "${ROOT}/plugins/leadv2/scripts" "3" "$OUT_FILE" >/dev/null 2>&1
RUN1="$(cat "$OUT_FILE" 2>/dev/null)"

case "$RUN1" in
  *GOOD-BASE*) ok "run 1 (success): BASE has GOOD-BASE" ;;
  *) bad "run 1 (success): expected GOOD-BASE, got: $(printf '%s' "$RUN1" | sed 's/\x1b\[[0-9;]*m//g')" ;;
esac

# Run 2: user command fails → BASE should be preserved from cache (still GOOD-BASE)
write_settings "$STUB_FAIL"
bash "$TAIL" "$INPUT" "$SETTINGS" "${ROOT}/plugins/leadv2/scripts" "3" "$OUT_FILE" >/dev/null 2>&1
RUN2="$(cat "$OUT_FILE" 2>/dev/null)"

case "$RUN2" in
  *GOOD-BASE*) ok "run 2 (fail): BASE preserved as GOOD-BASE from cache" ;;
  *)
    # Check it's not the fallback (which would lack GOOD-BASE)
    _visible="$(printf '%s' "$RUN2" | sed 's/\x1b\[[0-9;]*m//g')"
    case "$_visible" in
      *TestModel*GOOD-BASE*) ok "run 2 (fail): BASE preserved (with codes)" ;;
      *) bad "run 2 (fail): expected GOOD-BASE preserved, got: $_visible" ;;
    esac
    ;;
esac

# ════════════════════════════════════════════════════════════════════════════
# T2: FLICKER — no previous cache + failing command → FALLBACK_BASE used
# ════════════════════════════════════════════════════════════════════════════
echo "== T2: FLICKER — no cache + failing cmd → fallback =="

OUT_FILE_FRESH="$CACHE/last-known-fresh"
rm -f "$OUT_FILE_FRESH"

write_settings "$STUB_FAIL"
bash "$TAIL" "$INPUT" "$SETTINGS" "${ROOT}/plugins/leadv2/scripts" "3" "$OUT_FILE_FRESH" >/dev/null 2>&1
RUN_FRESH="$(cat "$OUT_FILE_FRESH" 2>/dev/null)"

_visible="$(printf '%s' "$RUN_FRESH" | sed 's/\x1b\[[0-9;]*m//g')"
case "$_visible" in
  *TestModel*) ok "no-cache + fail: fallback has TestModel" ;;
  *) bad "no-cache + fail: expected TestModel in fallback, got: $_visible" ;;
esac

# ════════════════════════════════════════════════════════════════════════════
# T3: BURN-FIRSTCLASS — burn segment survives by default (DROP_BURN=0)
# ════════════════════════════════════════════════════════════════════════════
echo "== T3: BURN-FIRSTCLASS — burn preserved by default =="

STUB_BURN="$FIX/stub-burn.sh"
printf '#!/usr/bin/env bash\nprintf "model in dir 75%% ctx | 42t 1h 23m"\n' > "$STUB_BURN"
chmod +x "$STUB_BURN"

OUT_BURN="$CACHE/last-known-burn"
write_settings "$STUB_BURN"

# Run with default env (DROP_BURN should default to 0 now).
bash "$TAIL" "$INPUT" "$SETTINGS" "${ROOT}/plugins/leadv2/scripts" "3" "$OUT_BURN" >/dev/null 2>&1
BURN_OUT="$(cat "$OUT_BURN" 2>/dev/null)"
_burn_visible="$(printf '%s' "$BURN_OUT" | sed 's/\x1b\[[0-9;]*m//g')"

case "$_burn_visible" in
  *42t*) ok "burn preserved by default (42t visible)" ;;
  *) bad "burn dropped by default, expected 42t in: $_burn_visible" ;;
esac

# ════════════════════════════════════════════════════════════════════════════
# T4: BURN-FIRSTCLASS — explicit DROP_BURN=1 still drops it (escape hatch)
# ════════════════════════════════════════════════════════════════════════════
echo "== T4: BURN-FIRSTCLASS — DROP_BURN=1 still works =="

OUT_BURN_DROP="$CACHE/last-known-burn-drop"
LEADV2_STATUSLINE_DROP_BURN=1 \
  bash "$TAIL" "$INPUT" "$SETTINGS" "${ROOT}/plugins/leadv2/scripts" "3" "$OUT_BURN_DROP" >/dev/null 2>&1
BURN_DROP_OUT="$(cat "$OUT_BURN_DROP" 2>/dev/null)"
_burn_drop_visible="$(printf '%s' "$BURN_DROP_OUT" | sed 's/\x1b\[[0-9;]*m//g')"

case "$_burn_drop_visible" in
  *42t*) bad "DROP_BURN=1 should have stripped burn, but 42t visible: $_burn_drop_visible" ;;
  *) ok "DROP_BURN=1 strips burn (42t absent)" ;;
esac

# ════════════════════════════════════════════════════════════════════════════
# T5: FLICKER — consecutive successful renders produce stable BASE
# ════════════════════════════════════════════════════════════════════════════
echo "== T5: FLICKER — stable BASE across consecutive successes =="

OUT_STABLE="$CACHE/last-known-stable"
write_settings "$STUB_OK"

bash "$TAIL" "$INPUT" "$SETTINGS" "${ROOT}/plugins/leadv2/scripts" "3" "$OUT_STABLE" >/dev/null 2>&1
STABLE1="$(cat "$OUT_STABLE" 2>/dev/null)"
bash "$TAIL" "$INPUT" "$SETTINGS" "${ROOT}/plugins/leadv2/scripts" "3" "$OUT_STABLE" >/dev/null 2>&1
STABLE2="$(cat "$OUT_STABLE" 2>/dev/null)"

if [[ "$STABLE1" == "$STABLE2" ]]; then
  ok "consecutive successful renders are byte-identical"
else
  bad "consecutive renders differ (flicker on success path)"
fi

# ── summary ──────────────────────────────────────────────────────────────────
echo ""
echo "Results: $PASS passed, $FAIL failed"
if [[ "$FAIL" -gt 0 ]]; then exit 1; fi
exit 0
