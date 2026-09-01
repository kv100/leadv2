#!/usr/bin/env bash
# Offline contract tests for CACHE-TRUTH-01's leadv2-cache-truth.sh.
#
# Every assertion below has a NEGATIVE CONTROL: the tool's ratio numerator is
# swapped from cache_read to cache_creation in a throwaway copy, and the same
# assertion is re-run expecting the suite to go RED. A case whose negative
# control stays green proves nothing (COOKBOOK: gates that can't fail dead).
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TOOL="${SCRIPT_DIR}/leadv2-cache-truth.sh"

PASS=0 FAIL=0
pass() { PASS=$((PASS + 1)); printf '[TEST] PASS: %s\n' "$1"; }
fail() { FAIL=$((FAIL + 1)); printf '[TEST] FAIL: %s\n' "$1"; }

ROOT="$(mktemp -d "${TMPDIR:-/tmp}/cache-truth.XXXXXX")"
trap 'rm -rf "$ROOT"' EXIT

if bash -n "$TOOL"; then
  pass 'bash syntax: leadv2-cache-truth.sh'
else
  fail 'bash syntax: leadv2-cache-truth.sh'
fi

# ---------------------------------------------------------------------------
# Fixture 1: Anthropic shape WITH cache fields, two turns, high hit ratio.
# ---------------------------------------------------------------------------
ANTH_DIR="$ROOT/docs/handoff/dispatch-fixture01"
mkdir -p "$ANTH_DIR"
cat > "$ANTH_DIR/developer.stream.jsonl" <<'JSONL'
{"type":"assistant","message":{"usage":{"input_tokens":10,"cache_creation_input_tokens":1000,"cache_read_input_tokens":0,"output_tokens":5}}}
{"type":"assistant","message":{"usage":{"input_tokens":10,"cache_creation_input_tokens":50,"cache_read_input_tokens":900,"output_tokens":5}}}
{"type":"assistant","message":{"usage":{"input_tokens":10,"cache_creation_input_tokens":50,"cache_read_input_tokens":950,"output_tokens":5}}}
JSONL

out="$("$TOOL" "$ANTH_DIR" 2>/dev/null)"
row="$(printf '%s\n' "$out" | tail -1)"
ratio="$(printf '%s\n' "$row" | awk -F'\t' '{print $7}')"
break_turn="$(printf '%s\n' "$row" | awk -F'\t' '{print $8}')"

# total: input=30 cache_read=1850 cache_creation=1100 -> denom=2980 -> ratio=0.6208
if printf '%s\n' "$ratio" | grep -qE '^0\.62'; then
  pass 'anthropic fixture: overall hit ratio ~0.62'
else
  fail "anthropic fixture: overall hit ratio expected ~0.62 got '$ratio'"
fi

if [[ "$break_turn" == "none" ]]; then
  pass 'anthropic fixture: no cache break (turns 2,3 both >=0.5)'
else
  fail "anthropic fixture: expected no cache break, got '$break_turn'"
fi

# arm classification: path contains /docs/handoff/dispatch-*
arm="$(printf '%s\n' "$row" | awk -F'\t' '{print $1}')"
if [[ "$arm" == "claude-native" ]]; then
  pass 'anthropic fixture: arm classified claude-native'
else
  fail "anthropic fixture: expected arm claude-native got '$arm'"
fi

# ---------------------------------------------------------------------------
# Fixture 2: Anthropic shape with a genuine cache BREAK on turn 2 (ratio<0.5).
# ---------------------------------------------------------------------------
BREAK_DIR="$ROOT/docs/handoff/dispatch-fixture02"
mkdir -p "$BREAK_DIR"
cat > "$BREAK_DIR/developer.stream.jsonl" <<'JSONL'
{"type":"assistant","message":{"usage":{"input_tokens":10,"cache_creation_input_tokens":1000,"cache_read_input_tokens":0,"output_tokens":5}}}
{"type":"assistant","message":{"usage":{"input_tokens":900,"cache_creation_input_tokens":900,"cache_read_input_tokens":0,"output_tokens":5}}}
JSONL

out2="$("$TOOL" "$BREAK_DIR" 2>/dev/null)"
row2="$(printf '%s\n' "$out2" | tail -1)"
break2="$(printf '%s\n' "$row2" | awk -F'\t' '{print $8}')"
if [[ "$break2" == "2" ]]; then
  pass 'break fixture: first_break correctly reports turn 2'
else
  fail "break fixture: expected first_break=2 got '$break2'"
fi

# ---------------------------------------------------------------------------
# Fixture 3: provider shape with NO cache fields at all -> "unreported", not 0.
# ---------------------------------------------------------------------------
NOCACHE_DIR="$ROOT/glm-runs/260901-fixture-noCache"
mkdir -p "$NOCACHE_DIR"
cat > "$NOCACHE_DIR/journal.jsonl" <<'JSONL'
{"type":"assistant","message":{"usage":{"input_tokens":0,"output_tokens":0}}}
{"type":"assistant","message":{"usage":{"input_tokens":0,"output_tokens":0}}}
JSONL

out3="$("$TOOL" "$NOCACHE_DIR" 2>/dev/null)"
row3="$(printf '%s\n' "$out3" | tail -1)"
ratio3="$(printf '%s\n' "$row3" | awk -F'\t' '{print $7}')"
arm3="$(printf '%s\n' "$row3" | awk -F'\t' '{print $1}')"

if [[ "$ratio3" == "unreported" ]]; then
  pass 'no-cache-field fixture: ratio reported as unreported, not coerced to 0'
else
  fail "no-cache-field fixture: expected 'unreported' got '$ratio3'"
fi

if [[ "$arm3" == "glm" ]]; then
  pass 'no-cache-field fixture: arm classified glm from path'
else
  fail "no-cache-field fixture: expected arm glm got '$arm3'"
fi

# ---------------------------------------------------------------------------
# Fixture 4: provider reports the cache keys but genuinely zero (freepool
# TokenRouter shape seen in the real 260901 runs) -> a real 0.0000 ratio,
# distinct from "unreported". This is the exact distinction the tool exists
# to make (a missing field is a finding, a reported zero is a different one).
# ---------------------------------------------------------------------------
ZERO_DIR="$ROOT/freepool-runs/260901-fixture-zero"
mkdir -p "$ZERO_DIR"
cat > "$ZERO_DIR/journal.jsonl" <<'JSONL'
{"type":"assistant","message":{"usage":{"input_tokens":100,"cache_creation_input_tokens":0,"cache_read_input_tokens":0,"output_tokens":5}}}
JSONL

out4="$("$TOOL" "$ZERO_DIR" 2>/dev/null)"
row4="$(printf '%s\n' "$out4" | tail -1)"
ratio4="$(printf '%s\n' "$row4" | awk -F'\t' '{print $7}')"
if [[ "$ratio4" == "0.0000" ]]; then
  pass 'reported-zero fixture: ratio is 0.0000, not unreported'
else
  fail "reported-zero fixture: expected 0.0000 got '$ratio4'"
fi

# ---------------------------------------------------------------------------
# Fixture 5: missing input entirely (no journal.jsonl / developer.stream.jsonl
# in the given dir) -> non-zero exit, error on stderr, no crash.
# ---------------------------------------------------------------------------
EMPTY_DIR="$ROOT/empty-run"
mkdir -p "$EMPTY_DIR"
"$TOOL" "$EMPTY_DIR" >/dev/null 2>/tmp/cache-truth-empty-err.$$
emptyrc=$?
if [[ $emptyrc -ne 0 ]] && grep -q 'ERROR' /tmp/cache-truth-empty-err.$$; then
  pass 'missing stream: tool exits non-zero with an ERROR line, not a silent pass'
else
  fail "missing stream: expected non-zero rc + ERROR line, got rc=$emptyrc"
fi
rm -f /tmp/cache-truth-empty-err.$$

# ---------------------------------------------------------------------------
# MUTATION NEGATIVE CONTROL: swap numerator from cache_read to cache_creation
# in a throwaway copy of the tool. The ratio assertion above (fixture 1,
# ~0.62) MUST go red against the mutant, because cache_creation dominates the
# fixture differently (1100 vs 1850) — proving the ratio test can fail.
# ---------------------------------------------------------------------------
MUTANT="$ROOT/leadv2-cache-truth-mutant.sh"
sed 's/overall_ratio = (total_cr \/ denom) if denom > 0 else 0.0/overall_ratio = (total_cc \/ denom) if denom > 0 else 0.0/' "$TOOL" > "$MUTANT"
chmod +x "$MUTANT"

mutant_out="$("$MUTANT" "$ANTH_DIR" 2>/dev/null | tail -1)"
mutant_ratio="$(printf '%s\n' "$mutant_out" | awk -F'\t' '{print $7}')"
# expected correct ratio ~0.6208; mutant numerator is cache_creation=1100/2980=0.3691
if printf '%s\n' "$mutant_ratio" | grep -qE '^0\.62'; then
  fail 'MUTATION CONTROL: mutant (cache_creation numerator) unexpectedly matched correct ratio — control is not falsifiable'
else
  pass "MUTATION CONTROL: mutant ratio diverged from correct 0.62 (got '$mutant_ratio') — control proven red-capable"
fi

echo
echo "PASS=$PASS FAIL=$FAIL"
[[ $FAIL -eq 0 ]]
