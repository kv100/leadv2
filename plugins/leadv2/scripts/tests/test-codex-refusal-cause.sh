#!/usr/bin/env bash
# test-codex-refusal-cause.sh — CODEX-REFUSAL-MARKER-CARRIES-ITS-CAUSE-01
#
# The codex spawn gate used to print LEADV2_DISPATCH_REFUSED: quota_gate for
# THREE distinct refusal classes (cooldown / circuit-open / circuit-unknown),
# so the dispatcher ledgered transport deaths and control-plane fail-closes as
# QUOTA lockouts — live artifact 2026-09-06: quota-lockout-codex.json
# strikes=54 while the arm sat at 9% of quota — and invented a flat 30-minute
# expiry for causes that carried their own.
#
# This suite drives every refusal path of codex_spawn_gate and asserts the
# cause vocabulary, then drives the dispatcher's ledger seam
# (_maybe_record_quota_lockout) and asserts:
#   transport_cooldown / circuit_unknown / gate_broken -> NO quota lockout row,
#     NO quota strike bump (their state lives in the arm-cooldown memory /
#     circuit marker, each with its own expiry; a control-plane read failure
#     has NO knowable expiry, so inventing one is the defect itself);
#   a GENUINE quota refusal (threshold over ceiling; quota-reason cooldown;
#     circuit open) -> quota lockout row WITH its own or cause-stated expiry
#     (negative control: a fix that merely stopped writing lockouts fails here).
#
# Mutation control (named, applied INSIDE codex_spawn_gate's cooldown branch,
# never a top-level insert):
#   sed 's/_refusal_cause="transport_cooldown"/_refusal_cause="quota_gate"/'
# re-conflates the transport cause with the quota word at the exact printf
# source; cases T1/T2 must go red against that mutant and only that mutant.
# Applied via plugins/leadv2/scripts/leadv2-mutation-control.sh; artifact
# under docs/handoff/CODEX-REFUSAL-MARKER-CARRIES-ITS-CAUSE-01/mutation-control/.
#
# Hermetic: LEADV2_QUOTA_LIVE / LEADV2_QUOTA_CACHE_DIR / LEADV2_QUOTA_CEILINGS
# are always exported (check 3 otherwise reads the host's real quota cache),
# cooldown + circuit state and the lockout ledger all live in mktemp dirs.
# run-all-triggers: leadv2-codex-quota-gate leadv2-dispatch-code leadv2-arm-cooldown leadv2-codex-circuit

set -uo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_DIR="$(cd "$TESTS_DIR/.." && pwd)"
PLUGIN_ROOT="$(cd "$SCRIPTS_DIR/.." && pwd)"
GATE_LIB="${SCRIPTS_DIR}/lib/leadv2-codex-quota-gate.sh"
ARM_CD_LIB="${SCRIPTS_DIR}/lib/leadv2-arm-cooldown.sh"
CIRCUIT_LIB="${SCRIPTS_DIR}/lib/leadv2-codex-circuit.sh"
DISPATCH_SH="${SCRIPTS_DIR}/leadv2-dispatch-code.sh"
CEILINGS="${PLUGIN_ROOT}/config/leadv2-quota-ceilings.sh"

PASS=0; FAIL=0
pass() { printf '[TEST] PASS: %s\n' "$1"; PASS=$((PASS + 1)); }
fail() { printf '[TEST] FAIL: %s\n' "$1"; FAIL=$((FAIL + 1)); }

BASE="$(mktemp -d "${TMPDIR:-/tmp}/codex-refusal-cause.XXXXXX")"
trap 'rm -rf "$BASE"' EXIT
mkdir -p "$BASE/proj" "$BASE/ledger" "$BASE/cache"

iso_min() { # <+/-minutes> -> UTC ISO
  date -u -v"$1"M +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -d "$1 minutes" +%Y-%m-%dT%H:%M:%SZ
}

# Scratch tree for the gate_broken case: the gate resolves its check-3 child
# RELATIVE to its own location (../leadv2-provider-quota-gate.sh), so a copy
# with a non-executable child exercises the gate_broken branch hermetically.
SBX="${BASE}/scripts"; mkdir -p "$SBX/lib"
cp "$GATE_LIB" "$ARM_CD_LIB" "$CIRCUIT_LIB" "$SBX/lib/"
cp "${SCRIPTS_DIR}/leadv2-provider-quota-gate.sh" "$SBX/" && chmod 644 "$SBX/leadv2-provider-quota-gate.sh"

GATE_ENV=(LEADV2_ARM_COOLDOWN_DIR="$BASE/cd"
          LEADV2_CODEX_CIRCUIT_FILE="$BASE/circuit.json"
          LEADV2_QUOTA_LIVE="$BASE/live.sh"
          LEADV2_QUOTA_CACHE_DIR="$BASE/cache"
          LEADV2_QUOTA_CEILINGS="$CEILINGS"
          LEADV2_CEIL_CODEX_WORK=50
          HOME="$BASE/home")
mkdir -p "$BASE/home"
cat > "$BASE/live.sh" <<'EOF'
#!/usr/bin/env bash
printf '%s' '{"status":"ok","binding_window":"primary","windows":[{"kind":"primary","used_percent":9}]}'
EOF
chmod +x "$BASE/live.sh"

write_cooldown() { # <reason>
  mkdir -p "$BASE/cd"
  printf '%s ARM_COOLDOWN arm=codex reason=%s reprobe_at=%s cooldown_s=900 advisory_until=na advisory=ignored src=default job=j-1\n' \
    "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$1" "$(iso_min +9)" > "$BASE/cd/codex.state"
}
clear_gate_state() { rm -f "$BASE/cd/codex.state" "$BASE/circuit.json"; }

run_gate() { # <sandbox-lib-dir|""> — runs codex_spawn_gate exec, stderr -> $BASE/gate.err, rc -> GATE_RC
  local libdir="${1:-$SCRIPTS_DIR}"
  GATE_RC=0
  env "${GATE_ENV[@]}" bash -c "source '${libdir}/lib/leadv2-codex-quota-gate.sh'; codex_spawn_gate exec" \
    >"$BASE/gate.out" 2>"$BASE/gate.err" || GATE_RC=$?
}

# ── T1: transport cooldown (worker_died) -> transport_cooldown ──────────────
write_cooldown worker_died
run_gate
if [[ "$GATE_RC" -eq 2 ]] \
   && grep -q 'LEADV2_DISPATCH_REFUSED: transport_cooldown' "$BASE/gate.err" \
   && ! grep -q 'LEADV2_DISPATCH_REFUSED: quota_gate' "$BASE/gate.err" \
   && grep -q 'reason=cooldown' "$BASE/gate.err"; then
  pass "T1 worker_died cooldown -> transport_cooldown marker, rc 2, never the quota word"
else
  fail "T1 worker_died cooldown (rc=$GATE_RC err=$(cat "$BASE/gate.err" 2>/dev/null))"
fi

# ── T2: transport cooldown (queued_stall) -> transport_cooldown ─────────────
write_cooldown queued_stall
run_gate
if [[ "$GATE_RC" -eq 2 ]] && grep -q 'LEADV2_DISPATCH_REFUSED: transport_cooldown' "$BASE/gate.err"; then
  pass "T2 queued_stall cooldown -> transport_cooldown marker"
else
  fail "T2 queued_stall cooldown (rc=$GATE_RC err=$(cat "$BASE/gate.err" 2>/dev/null))"
fi

# ── T3: quota-reason cooldown keeps the legacy quota_gate word ──────────────
write_cooldown quota
run_gate
if [[ "$GATE_RC" -eq 2 ]] \
   && grep -q 'LEADV2_DISPATCH_REFUSED: quota_gate' "$BASE/gate.err" \
   && ! grep -q 'LEADV2_DISPATCH_REFUSED: transport_cooldown' "$BASE/gate.err"; then
  pass "T3 quota cooldown -> legacy quota_gate marker preserved (existing readers keep working)"
else
  fail "T3 quota cooldown (rc=$GATE_RC err=$(cat "$BASE/gate.err" 2>/dev/null))"
fi
clear_gate_state

# ── T4: circuit open -> quota_circuit_open ──────────────────────────────────
printf '{"until":"%s","opened_at":"%s","source":"test","reason":"usage_limit"}' "$(iso_min +12)" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" > "$BASE/circuit.json"
run_gate
if [[ "$GATE_RC" -eq 2 ]] \
   && grep -q 'LEADV2_DISPATCH_REFUSED: quota_circuit_open' "$BASE/gate.err" \
   && grep -q 'reason=circuit' "$BASE/gate.err"; then
  pass "T4 circuit open -> quota_circuit_open marker"
else
  fail "T4 circuit open (rc=$GATE_RC err=$(cat "$BASE/gate.err" 2>/dev/null))"
fi

# ── T5: circuit marker corrupt -> circuit_unknown (fail-closed) ─────────────
printf '{not json' > "$BASE/circuit.json"
run_gate
if [[ "$GATE_RC" -eq 2 ]] && grep -q 'LEADV2_DISPATCH_REFUSED: circuit_unknown' "$BASE/gate.err"; then
  pass "T5 corrupt circuit marker -> circuit_unknown marker"
else
  fail "T5 corrupt circuit marker (rc=$GATE_RC err=$(cat "$BASE/gate.err" 2>/dev/null))"
fi
rm -f "$BASE/circuit.json"

# ── T6: gate dependency non-executable -> gate_broken (sandbox copy) ────────
run_gate "$SBX"
if [[ "$GATE_RC" -eq 2 ]] && grep -q 'LEADV2_DISPATCH_REFUSED: gate_broken' "$BASE/gate.err"; then
  pass "T6 non-executable provider gate -> gate_broken marker"
else
  fail "T6 non-executable provider gate (rc=$GATE_RC err=$(cat "$BASE/gate.err" 2>/dev/null))"
fi

# ── T7 NEGATIVE CONTROL (gate side): over-ceiling threshold -> quota_gate ───
cat > "$BASE/live.sh" <<'EOF'
#!/usr/bin/env bash
printf '%s' '{"status":"ok","binding_window":"primary","windows":[{"kind":"primary","used_percent":99}]}'
EOF
chmod +x "$BASE/live.sh"
run_gate
if [[ "$GATE_RC" -eq 2 ]] \
   && grep -q 'LEADV2_DISPATCH_REFUSED: quota_gate' "$BASE/gate.err" \
   && grep -q 'reason=threshold' "$BASE/gate.err"; then
  pass "T7 live ceiling over threshold -> quota_gate marker (the real quota refusal is untouched)"
else
  fail "T7 live ceiling over threshold (rc=$GATE_RC err=$(cat "$BASE/gate.err" 2>/dev/null))"
fi

# ── R1: refusal_reason() extracts every new token (single-word grammar) ─────
# Rows are tok|<raw stderr>, with literal \n standing in for newlines (in
# production the diagnostic line and the marker are separate stderr lines);
# printf %b decodes them before the call.
{
  printf 'transport_cooldown|[codex-task] CODEX_REFUSED_QUOTA reason=cooldown used=na threshold=na until=%s\\nLEADV2_DISPATCH_REFUSED: transport_cooldown\n' "$(iso_min +9)"
  printf 'quota_circuit_open|[codex-task] CODEX_REFUSED_QUOTA reason=circuit used=na threshold=na until=2099-01-01T00:00:00Z\\nLEADV2_DISPATCH_REFUSED: quota_circuit_open\n'
  printf 'circuit_unknown|[codex-task] CODEX_REFUSED_QUOTA reason=circuit-unknown (control-plane unreachable) used=na threshold=na until=na\\nLEADV2_DISPATCH_REFUSED: circuit_unknown\n'
  printf 'gate_broken|[codex-task] CODEX_REFUSED_QUOTA reason=gate_broken dependency=x rc=126\\nLEADV2_DISPATCH_REFUSED: gate_broken\n'
  printf 'quota_gate|[codex-task] CODEX_REFUSED_QUOTA reason=threshold used=live threshold=ceiling until=na\\nLEADV2_DISPATCH_REFUSED: quota_gate\n'
} > "$BASE/r1.txt"
R1_OUT="$(LEADV2_DISPATCH_SOURCE_ONLY=1 PROJECT_ROOT="$BASE/proj" LEADV2_QUOTA_LOCKOUT_DIR="$BASE/ledger" \
  bash -c '
    source "$1"
    while IFS="|" read -r tok text; do
      [[ -z "$tok" ]] && continue
      text="$(printf "%b" "$text")"
      got="$(refusal_reason codex 2 "" "$text" || true)"
      if [[ "$got" == "$tok" ]]; then printf "ok %s\n" "$tok"; else printf "BAD %s->%s\n" "$tok" "$got"; fi
    done < "$2"
  ' _ "$DISPATCH_SH" "$BASE/r1.txt" 2>"$BASE/r1.err")" || R1_OUT=""
if [[ "$(printf '%s\n' "$R1_OUT" | grep -c '^ok ')" -eq 5 ]] && ! grep -q '^BAD' <<<"$R1_OUT"; then
  pass "R1 refusal_reason extracts all five cause tokens"
else
  fail "R1 refusal_reason token extraction (out=$R1_OUT err=$(head -2 "$BASE/r1.err" 2>/dev/null | tr '\n' ' '))"
fi

# ── consumer seam driver ─────────────────────────────────────────────────────
# <ledger-dir> <reason> <raw-text> -> one bash -c: before-strikes, call
# _maybe_record_quota_lockout, after-strikes, then locked_until|source|strikes
# of the row (or "absent").
ledger_call() { # <ledger-dir> <reason> <raw-text>
  LEADV2_DISPATCH_SOURCE_ONLY=1 PROJECT_ROOT="$BASE/proj" LEADV2_QUOTA_LOCKOUT_DIR="$1" \
    bash -c '
      source "$1"
      before=$(_lockout_prior_strikes codex)
      _maybe_record_quota_lockout codex "$2" "$3" 2>/dev/null
      after=$(_lockout_prior_strikes codex)
      row="$(python3 - "$LEADV2_QUOTA_LOCKOUT_DIR/quota-lockout-codex.json" <<"PY"
import json, sys
try:
    d = json.load(open(sys.argv[1]))
    print("%s|%s|%s" % (d.get("locked_until"), d.get("source"), d.get("strikes")))
except Exception:
    print("absent")
PY
)"
      printf "%s->%s %s\n" "$before" "$after" "$row"
    ' _ "$DISPATCH_SH" "$2" "$3" 2>/dev/null
}

# ── C1: transport / circuit-unknown / gate_broken refusals -> NO row, NO bump
C1_RAW_T="[codex-task] CODEX_REFUSED_QUOTA reason=cooldown used=na threshold=na until=$(iso_min +9)
LEADV2_DISPATCH_REFUSED: transport_cooldown"
C1_RAW_U="[codex-task] CODEX_REFUSED_QUOTA reason=circuit-unknown (control-plane unreachable) used=na threshold=na until=na
LEADV2_DISPATCH_REFUSED: circuit_unknown"
C1_RAW_B="[codex-task] CODEX_REFUSED_QUOTA reason=gate_broken dependency=x rc=126
LEADV2_DISPATCH_REFUSED: gate_broken"
C1_T="$(ledger_call "$BASE/ledger-t" transport_cooldown "$C1_RAW_T")"
C1_U="$(ledger_call "$BASE/ledger-u" circuit_unknown "$C1_RAW_U")"
C1_B="$(ledger_call "$BASE/ledger-b" gate_broken "$C1_RAW_B")"
if [[ "$C1_T" == "0->0 absent" && "$C1_U" == "0->0 absent" && "$C1_B" == "0->0 absent" ]]; then
  pass "C1 transport/circuit-unknown/gate_broken refusals write NO quota lockout and bump NO strike"
else
  fail "C1 non-quota ledger behavior (t=$C1_T u=$C1_U b=$C1_B)"
fi

# ── C2: quota cooldown lockout INHERITS the cause's stated until ────────────
C2_T="$(iso_min +9)"
C2_RAW="[codex-task] CODEX_REFUSED_QUOTA reason=cooldown used=na threshold=na until=${C2_T}
LEADV2_DISPATCH_REFUSED: quota_gate"
C2_OUT="$(ledger_call "$BASE/ledger-q" quota_gate "$C2_RAW")"
if [[ "$C2_OUT" == "0->1 ${C2_T}|launcher_refusal:quota_gate|1" ]]; then
  pass "C2 quota cooldown -> lockout inherits the cooldown's reprobe_at exactly (strikes 0->1)"
else
  fail "C2 expiry inheritance (got: $C2_OUT, want 0->1 ${C2_T}|launcher_refusal:quota_gate|1)"
fi

# ── C3 NEGATIVE CONTROL (ledger side): expiry-less quota refusal -> row with
#     the flat default expiry (a fix that stopped writing lockouts fails here)
C3_RAW="[codex-task] CODEX_REFUSED_QUOTA reason=threshold used=live threshold=ceiling until=na
LEADV2_DISPATCH_REFUSED: quota_gate"
C3_OUT="$(ledger_call "$BASE/ledger-d" quota_gate "$C3_RAW")"
C3_MIN="$(date -u +%s)"
C3_ISO="${C3_OUT#* }"; C3_ISO="${C3_ISO%%|*}"
C3_UNTIL_EPOCH="$(python3 - "$C3_ISO" <<'PY'
import sys
from datetime import datetime
try:
    print(int(datetime.fromisoformat(sys.argv[1].replace("Z", "+00:00")).timestamp()))
except Exception:
    print(0)
PY
)"
C3_DELTA=$(( (C3_UNTIL_EPOCH - C3_MIN) / 60 ))
if [[ "$C3_OUT" == *"|launcher_refusal:quota_gate|"* ]] && [[ "$C3_DELTA" -ge 28 && "$C3_DELTA" -le 31 ]]; then
  pass "C3 expiry-less quota refusal -> lockout row with the ~30min default expiry (negative control)"
else
  fail "C3 negative control (got: $C3_OUT delta=${C3_DELTA}min)"
fi

# ── C4: circuit-open (quota-shaped) lockout inherits the circuit's until ────
C4_T="$(iso_min +12)"
C4_RAW="[codex-task] CODEX_REFUSED_QUOTA reason=circuit used=na threshold=na until=${C4_T}
LEADV2_DISPATCH_REFUSED: quota_circuit_open"
C4_OUT="$(ledger_call "$BASE/ledger-c" quota_circuit_open "$C4_RAW")"
if [[ "$C4_OUT" == "0->1 ${C4_T}|launcher_refusal:quota_circuit_open|1" ]]; then
  pass "C4 circuit open -> quota-family lockout inherits the circuit's until exactly"
else
  fail "C4 circuit-open ledger (got: $C4_OUT, want 0->1 ${C4_T}|launcher_refusal:quota_circuit_open|1)"
fi

echo "---"
echo "$PASS passed, $FAIL failed"
[[ "$FAIL" -eq 0 ]]
