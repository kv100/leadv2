#!/usr/bin/env bash
# test-quota-unknown-surfaces.sh — A-DEAD-INSTRUMENT-MUST-ANNOUNCE-ITSELF-01
#
# The founder-facing incident: a codex quota probe returned status="unknown"
# (HTTP 401 on OAuth token refresh) for ~12h, but the human-facing surface
# rendered it as a plausible measured percentage ("cx ~90%·wk/5d15h 12h15m
# old") instead of visibly flagging it as unmeasured/stale. True value: 17%.
#
# Asserts, end to end, against the REAL scripts (never a hand-copied
# reimplementation, so this cannot silently drift from the shipped code):
#   T1/T2  codex unknown(401, needs_login) -> kv state=unknown, detail names
#          the remedy ("codex login"); status-surface renders it with the ⚠
#          marker, never a bare percentage.
#   T3/T4  glm unknown (no remedy flag in the reader's contract) -> detail is
#          the bare error, no invented remedy; still gets the ⚠ marker.
#   T5     healthy control: codex ok -> plain value, no ⚠ (run AFTER the
#          forced-unknown case, on the same cache dir, to also prove the
#          render flips back cleanly on recovery).
#   T6     exhausted/lockout (state=ok, a KNOWN answer) renders distinctly
#          from unknown (a NOT-known answer) -- no ⚠, different text.
#   T7/T8  active-signal requirement: transition INTO unknown appends exactly
#          ONE [SUPERVISE-URGENT] QUOTA_UNKNOWN line per provider to the
#          pulse log (the existing seam leadv2-writes-overlap.sh already
#          uses); a second refresh while still unknown must NOT re-fire.
#   T9/T10 leadv2-codex-status.sh (Codex-lead's statusline substitute) names
#          the remedy per-field ("?(codex login)" / "?(reauth)") on the exact
#          shipped python block (extracted, not retyped) and renders plainly
#          when healthy.
#
# Isolation: LEADV2_LIMITS_CACHE_DIR / LEADV2_STATE_PATH_SH / LEADV2_QUOTA_READ
# all point into a per-run mktemp dir. Nothing here ever touches the real
# ~/.claude/cache/leadv2-limits.d or the real supervise-loop.log.
#
# run-all-triggers: leadv2-limits-refresh leadv2-status-surface leadv2-codex-status leadv2-quota-read leadv2-quota-live

set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LIMITS_REFRESH_SH="${HERE}/leadv2-limits-refresh.sh"
STATUS_SURFACE_SH="${HERE}/leadv2-status-surface.sh"
CODEX_STATUS_SH="${HERE}/../codex-lead/leadv2-codex-status.sh"

PASS=0
FAIL=0
pass() { printf '[TEST] PASS: %s\n' "$1"; PASS=$((PASS + 1)); }
fail() { printf '[TEST] FAIL: %s\n' "$1"; FAIL=$((FAIL + 1)); }

BASE="$(mktemp -d)"
trap 'rm -rf "$BASE"' EXIT

CACHE="$BASE/cache"
mkdir -p "$CACHE"
PULSE_LOG="$BASE/pulse.log"

# A stable, isolated state-path stub: every provider .kv write in this suite
# stays under $CACHE, and every pulse-log append stays at $PULSE_LOG -- never
# the real ~/.claude/leadv2-state/leadv2/supervise-loop.log.
STATE_PATH_STUB="$BASE/state-path-stub.sh"
cat > "$STATE_PATH_STUB" <<EOF
#!/usr/bin/env bash
printf '%s\n' "$PULSE_LOG"
EOF
chmod +x "$STATE_PATH_STUB"

# Fake leadv2-quota-live.sh substitute (the --provider refresh path calls
# this directly): $2 selects the bucket; JSON comes from an env var per case.
QUOTA_LIVE_STUB="$BASE/quota-live-stub.sh"
cat > "$QUOTA_LIVE_STUB" <<'EOF'
#!/usr/bin/env bash
bucket="${*: -1}"
case "$bucket" in
  codex) printf '%s' "${FAKE_CODEX_JSON:-}" ;;
  glm)   printf '%s' "${FAKE_GLM_JSON:-}" ;;
esac
EOF
chmod +x "$QUOTA_LIVE_STUB"

refresh() { # $1=provider
  LEADV2_QUOTA_LIVE_SH="$QUOTA_LIVE_STUB" \
  LEADV2_STATE_PATH_SH="$STATE_PATH_STUB" \
  LEADV2_LIMITS_CACHE_DIR="$CACHE" \
  LEADV2_CODEX_LOCKOUT_SH="${LOCKOUT_STUB:-/bin/false}" \
  PROJECT_ROOT="$BASE" \
  bash "$LIMITS_REFRESH_SH" --provider "$1" --force
}

render_limits() {
  LEADV2_LIMITS_CACHE_DIR="$CACHE" LEADV2_LIMITS_REFRESH_SH=/bin/false \
    bash "$STATUS_SURFACE_SH" --limits
}

kv_field() { # $1=provider $2=field
  sed -n "s/^${2}=//p" "$CACHE/${1}.kv" 2>/dev/null | head -1
}

pulse_count() { # $1=grep-pattern
  [[ -f "$PULSE_LOG" ]] || { echo 0; return; }
  grep -c "$1" "$PULSE_LOG" 2>/dev/null || true
}

# ── T1/T2: codex unknown(401, needs_login) ──────────────────────────────────
export FAKE_CODEX_JSON='{"status":"unknown","error":"refresh http 401","needs_login":true}'
refresh codex >/dev/null 2>&1

if [[ "$(kv_field codex state)" == "unknown" ]]; then
  pass "T1 codex.kv state=unknown on 401-on-refresh"
else
  fail "T1 codex.kv state=$(kv_field codex state), expected unknown"
fi
if [[ "$(kv_field codex detail)" == *"codex login"* ]]; then
  pass "T1 codex.kv detail names the remedy (codex login)"
else
  fail "T1 codex.kv detail did not name the remedy: $(kv_field codex detail)"
fi

LINE1="$(render_limits | grep '^  codex:')"
echo "[NEGATIVE-CONTROL raw] $LINE1"
if [[ "$LINE1" == *"⚠"* && "$LINE1" == *"codex login"* ]]; then
  pass "T2 status-surface renders codex unknown with ⚠ + remedy"
else
  fail "T2 status-surface codex line missing ⚠/remedy: $LINE1"
fi
if [[ ! "$LINE1" =~ [0-9]+% ]]; then
  pass "T2 unknown codex line carries no plausible percentage"
else
  fail "T2 unknown codex line looks like a measured percentage: $LINE1"
fi

# ── T3/T4: glm unknown, no remedy flag in the reader's contract ────────────
export FAKE_GLM_JSON='{"status":"unknown","error":"ZAI_AUTH_TOKEN not set"}'
refresh glm >/dev/null 2>&1

if [[ "$(kv_field glm state)" == "unknown" ]]; then
  pass "T3 glm.kv state=unknown"
else
  fail "T3 glm.kv state=$(kv_field glm state), expected unknown"
fi
GLM_DETAIL="$(kv_field glm detail)"
if [[ "$GLM_DETAIL" == *"run:"* ]]; then
  fail "T3 glm.kv detail invented a remedy the reader never named: $GLM_DETAIL"
else
  pass "T3 glm.kv detail names no invented remedy: $GLM_DETAIL"
fi

LINE_GLM="$(render_limits | grep '^  glm:')"
if [[ "$LINE_GLM" == *"⚠"* ]]; then
  pass "T4 status-surface renders glm unknown with ⚠"
else
  fail "T4 status-surface glm line missing ⚠: $LINE_GLM"
fi

# ── T5: healthy control (recovery on the SAME cache dir) ───────────────────
export FAKE_CODEX_JSON='{"status":"ok","windows":[{"used_percent":17,"limit_reached":false,"hours_to_reset":36,"reset_iso":"2026-09-15T12:00:00Z"}]}'
refresh codex >/dev/null 2>&1
if [[ "$(kv_field codex state)" == "ok" ]]; then
  pass "T5 codex.kv state=ok once the probe recovers"
else
  fail "T5 codex.kv state=$(kv_field codex state) after recovery, expected ok"
fi
LINE5="$(render_limits | grep '^  codex:')"
echo "[POSITIVE-CONTROL raw] $LINE5"
if [[ "$LINE5" != *"⚠"* ]]; then
  pass "T5 healthy codex line carries no ⚠"
else
  fail "T5 healthy codex line still carries ⚠: $LINE5"
fi

# ── T6: exhausted/lockout stays visually distinct from unknown ─────────────
LOCKOUT_STUB="$BASE/lockout-stub.sh"
cat > "$LOCKOUT_STUB" <<'EOF'
#!/usr/bin/env bash
printf 'locked 18:00\n'
EOF
chmod +x "$LOCKOUT_STUB"
refresh codex >/dev/null 2>&1
LOCKOUT_LINE="$(render_limits | grep '^  codex:')"
echo "[EXHAUSTED-CONTROL raw] $LOCKOUT_LINE"
if [[ "$(kv_field codex state)" == "ok" && "$(kv_field codex value)" == *"lockout"* ]]; then
  pass "T6 lockout is a KNOWN answer (state=ok), not folded into unknown"
else
  fail "T6 lockout state/value wrong: state=$(kv_field codex state) value=$(kv_field codex value)"
fi
if [[ "$LOCKOUT_LINE" != *"⚠"* && "$LOCKOUT_LINE" != "$LINE1" ]]; then
  pass "T6 lockout line has no ⚠ and reads differently from the unknown line"
else
  fail "T6 lockout line not distinguishable from unknown: $LOCKOUT_LINE vs $LINE1"
fi
unset LOCKOUT_STUB

# ── T7/T8: active signal — edge-triggered, not spammed ─────────────────────
: > "$PULSE_LOG"
export FAKE_CODEX_JSON='{"status":"unknown","error":"refresh http 401","needs_login":true}'
refresh codex >/dev/null 2>&1   # transition ok(lockout) -> unknown: must fire
refresh codex >/dev/null 2>&1   # still unknown: must NOT re-fire
N_CODEX="$(pulse_count 'QUOTA_UNKNOWN provider=codex')"
if [[ "$N_CODEX" -eq 1 ]]; then
  pass "T7 codex QUOTA_UNKNOWN pulse fires exactly once across 2 refreshes (edge-triggered)"
else
  fail "T7 codex QUOTA_UNKNOWN pulse fired $N_CODEX times, expected 1"
fi

# glm.kv was already left at state=unknown by T3 -- establish a KNOWN prior
# state first (same pattern as T6 for codex) so this exercises a real
# ok -> unknown transition, not a no-op re-read of an already-unknown state.
export FAKE_GLM_JSON='{"status":"ok","weekly":{"pct":10,"reset_iso":"2026-09-20T00:00:00Z"}}'
refresh glm >/dev/null 2>&1
export FAKE_GLM_JSON='{"status":"unknown","error":"connect timeout"}'
refresh glm >/dev/null 2>&1
N_GLM="$(pulse_count 'QUOTA_UNKNOWN provider=glm')"
if [[ "$N_GLM" -eq 1 ]]; then
  pass "T8 glm QUOTA_UNKNOWN pulse fires independently of codex's counter"
else
  fail "T8 glm QUOTA_UNKNOWN pulse count=$N_GLM, expected 1"
fi
echo "[PULSE-LOG raw]"; cat "$PULSE_LOG"

# ── T9/T10: leadv2-codex-status.sh, driven against its OWN shipped python
#            block (extracted verbatim, never hand-retyped) ────────────────
CODEX_STATUS_PY="$BASE/codex-status-block.py"
sed -n '/^QUOTA_LINE=.*<<.PYEOF.$/,/^PYEOF$/p' "$CODEX_STATUS_SH" | sed '1d;$d' > "$CODEX_STATUS_PY"
if [[ ! -s "$CODEX_STATUS_PY" ]]; then
  fail "T9/T10 setup: could not extract the python block from $CODEX_STATUS_SH (heredoc marker drifted)"
else
  QJSON_UNKNOWN='{"anthropic":{"status":"unknown","needs_session":true},"codex":{"status":"unknown","error":"refresh http 401","needs_login":true},"glm":{"status":"ok","weekly":{"pct":42,"hours_to_reset":30},"binding_window":"weekly"}}'
  OUT9="$(python3 "$CODEX_STATUS_PY" "$QJSON_UNKNOWN")"
  echo "[CODEX-STATUS NEGATIVE-CONTROL raw] $OUT9"
  if [[ "$OUT9" == *'cx ?(codex login)'* && "$OUT9" == *'cc ?(reauth)'* ]]; then
    pass "T9 leadv2-codex-status.sh names the remedy for both cc and cx"
  else
    fail "T9 leadv2-codex-status.sh did not name the remedy: $OUT9"
  fi

  QJSON_OK='{"anthropic":{"status":"ok","accounts":[{"five_day":{"pct":12,"hours_to_reset":24}}],"binding_window":"five_day"},"codex":{"status":"ok","windows":[{"used_percent":17,"hours_to_reset":36}]},"glm":{"status":"ok","weekly":{"pct":42,"hours_to_reset":30},"binding_window":"weekly"}}'
  OUT10="$(python3 "$CODEX_STATUS_PY" "$QJSON_OK")"
  echo "[CODEX-STATUS POSITIVE-CONTROL raw] $OUT10"
  if [[ "$OUT10" != *'?'* ]]; then
    pass "T10 leadv2-codex-status.sh renders plainly when healthy (no '?')"
  else
    fail "T10 leadv2-codex-status.sh still shows '?' when healthy: $OUT10"
  fi
fi

echo "SUMMARY: PASS=$PASS FAIL=$FAIL"
[[ "$FAIL" -eq 0 ]]
