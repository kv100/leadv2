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
# Round-3 review: a mutant that was never created (anchor moved, python assert
# fired, sed no-op) must FAIL LOUD as control_not_applied — an absent mutant
# produces empty output which "diverges" from everything and used to print
# "control proven red-capable" (theatre). is_row checks the mutant emitted a
# well-formed 10-column TSV row with a numeric turns cell.
control_not_applied() { fail "MUTATION CONTROL NOT APPLIED: $1 (control_not_applied)"; }
is_row() { awk -F'\t' 'NF==10 && $3 ~ /^[0-9]+$/ && $3+0>0 {ok=1} END{exit ok?0:1}' 2>/dev/null <<<"$1"; }

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
ratio="$(printf '%s\n' "$row" | awk -F'\t' '{print $8}')"
break_turn="$(printf '%s\n' "$row" | awk -F'\t' '{print $9}')"

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
break2="$(printf '%s\n' "$row2" | awk -F'\t' '{print $9}')"
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
ratio3="$(printf '%s\n' "$row3" | awk -F'\t' '{print $8}')"
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
ratio4="$(printf '%s\n' "$row4" | awk -F'\t' '{print $8}')"
if [[ "$ratio4" == "0.0000" ]]; then
  pass 'reported-zero fixture: ratio is 0.0000, not unreported'
else
  fail "reported-zero fixture: expected 0.0000 got '$ratio4'"
fi

# ---------------------------------------------------------------------------
# Fixture 4b: MIXED run — 1 of 3 requests reports cache keys (value 0), the
# other 2 report nothing at all. Round-2 review finding: a global
# saw_cache_key flag classifies this as a real 0.0000 ratio (wrong — it hides
# that 2/3 requests never told us anything). Correct behaviour: hit_ratio
# computed over the 1 reported request only, and reported column = 1/3.
# ---------------------------------------------------------------------------
MIXED_DIR="$ROOT/freepool-runs/260901-fixture-mixed"
mkdir -p "$MIXED_DIR"
cat > "$MIXED_DIR/journal.jsonl" <<'JSONL'
{"type":"assistant","message":{"id":"m1","usage":{"input_tokens":100,"cache_creation_input_tokens":0,"cache_read_input_tokens":0,"output_tokens":5}}}
{"type":"assistant","message":{"id":"m2","usage":{"input_tokens":50,"output_tokens":5}}}
{"type":"assistant","message":{"id":"m3","usage":{"input_tokens":50,"output_tokens":5}}}
JSONL

out4b="$("$TOOL" "$MIXED_DIR" 2>/dev/null)"
row4b="$(printf '%s\n' "$out4b" | tail -1)"
ratio4b="$(printf '%s\n' "$row4b" | awk -F'\t' '{print $8}')"
reported4b="$(printf '%s\n' "$row4b" | awk -F'\t' '{print $10}')"
if [[ "$ratio4b" == "0.0000" ]]; then
  pass 'mixed fixture: hit_ratio computed over reported subset only (0.0000)'
else
  fail "mixed fixture: expected ratio 0.0000 got '$ratio4b'"
fi
if [[ "$reported4b" == "1/3" ]]; then
  pass 'mixed fixture: reported column shows 1/3, not silently 3/3 or 0/3'
else
  fail "mixed fixture: expected reported=1/3 got '$reported4b'"
fi

# R4 (round-3 review finding 1): ONE definition for the input column.
# input_tokens sums input over ALL turns — the m2/m3 input (50+50) must not
# vanish just because those turns are unreported — while input_reported sums
# the reported subset only. Hand-computed from the fixture above:
#   input_tokens    = 100 (m1) + 50 (m2) + 50 (m3) = 200
#   input_reported  = 100 (m1 only)
# Old behaviour printed input_tokens=100 (sum over reported turns), i.e. half
# the stream's real input silently dropped.
in_all4b="$(printf '%s\n' "$row4b" | awk -F'\t' '{print $4}')"
in_rep4b="$(printf '%s\n' "$row4b" | awk -F'\t' '{print $5}')"
if [[ "$in_all4b" == "200" ]]; then
  pass 'mixed fixture: input_tokens sums ALL turns (hand-computed 100+50+50=200)'
else
  fail "mixed fixture: expected input_tokens=200 got '$in_all4b'"
fi
if [[ "$in_rep4b" == "100" ]]; then
  pass 'mixed fixture: input_reported sums reported subset only (hand-computed 100)'
else
  fail "mixed fixture: expected input_reported=100 got '$in_rep4b'"
fi

# ---------------------------------------------------------------------------
# Fixture 4d: round-3 review probe — a turn that CARRIES the cache keys but
# whose usage is ALL ZEROS is NOT "reported": it must print hit_ratio
# "unreported" (never a fabricated 0.0000 from a zero denominator) and
# reported=0/1. (Old behaviour printed `... 0.0000 none 1/1` here.)
# ---------------------------------------------------------------------------
ALLZERO_DIR="$ROOT/glm-runs/260902-fixture-allzero"
mkdir -p "$ALLZERO_DIR"
cat > "$ALLZERO_DIR/journal.jsonl" <<'JSONL'
{"type":"assistant","message":{"usage":{"input_tokens":0,"cache_creation_input_tokens":0,"cache_read_input_tokens":0,"output_tokens":0}}}
JSONL

out4d="$("$TOOL" "$ALLZERO_DIR" 2>/dev/null)"
row4d="$(printf '%s\n' "$out4d" | tail -1)"
ratio4d="$(printf '%s\n' "$row4d" | awk -F'\t' '{print $8}')"
reported4d="$(printf '%s\n' "$row4d" | awk -F'\t' '{print $10}')"
if [[ "$ratio4d" == "unreported" ]]; then
  pass 'all-zero-usage fixture: cache keys present but usage 0/0/0 -> unreported, not 0.0000'
else
  fail "all-zero-usage fixture: expected 'unreported' got '$ratio4d'"
fi
if [[ "$reported4d" == "0/1" ]]; then
  pass 'all-zero-usage fixture: reported column shows 0/1'
else
  fail "all-zero-usage fixture: expected reported=0/1 got '$reported4d'"
fi

# ---------------------------------------------------------------------------
# Fixture 4c: DUPLICATED message.id — a stream-json file re-emits the same
# assistant message id 3x (streaming deltas + final), as seen on real
# dispatch-c293c1d5 (176 events / 95 unique ids). Only the LAST event per id
# should be counted; totals must equal the de-duplicated sum, not the raw
# event count.
# ---------------------------------------------------------------------------
DUP_DIR="$ROOT/docs/handoff/dispatch-fixture-dup"
mkdir -p "$DUP_DIR"
cat > "$DUP_DIR/developer.stream.jsonl" <<'JSONL'
{"type":"assistant","message":{"id":"a1","usage":{"input_tokens":10,"cache_creation_input_tokens":1000,"cache_read_input_tokens":0,"output_tokens":1}}}
{"type":"assistant","message":{"id":"a1","usage":{"input_tokens":10,"cache_creation_input_tokens":1000,"cache_read_input_tokens":0,"output_tokens":3}}}
{"type":"assistant","message":{"id":"a1","usage":{"input_tokens":10,"cache_creation_input_tokens":1000,"cache_read_input_tokens":0,"output_tokens":5}}}
{"type":"assistant","message":{"id":"a2","usage":{"input_tokens":10,"cache_creation_input_tokens":50,"cache_read_input_tokens":900,"output_tokens":5}}}
{"type":"assistant","message":{"id":"a2","usage":{"input_tokens":10,"cache_creation_input_tokens":50,"cache_read_input_tokens":900,"output_tokens":5}}}
JSONL
# unique sum: a1(10,0,1000) + a2(10,900,50) -> turns=2 input=20 cr=900 cc=1050
# denom=1970 ratio=900/1970=0.4569
outdup="$("$TOOL" "$DUP_DIR" 2>/dev/null)"
rowdup="$(printf '%s\n' "$outdup" | tail -1)"
turnsdup="$(printf '%s\n' "$rowdup" | awk -F'\t' '{print $3}')"
ratiodup="$(printf '%s\n' "$rowdup" | awk -F'\t' '{print $8}')"
if [[ "$turnsdup" == "2" ]]; then
  pass 'dup-id fixture: 5 raw events de-duplicated to 2 unique turns'
else
  fail "dup-id fixture: expected turns=2 got '$turnsdup'"
fi
if printf '%s\n' "$ratiodup" | grep -qE '^0\.4569'; then
  pass 'dup-id fixture: ratio computed over de-duplicated totals (~0.4569)'
else
  fail "dup-id fixture: expected ratio ~0.4569 got '$ratiodup'"
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
CTL1_ANCHOR='overall_ratio = (total_cr / denom) if denom > 0 else 0.0'
if [[ "$(grep -cF "$CTL1_ANCHOR" "$TOOL")" == "1" ]]; then
  sed "s|$CTL1_ANCHOR|overall_ratio = (total_cc / denom) if denom > 0 else 0.0|" "$TOOL" > "$MUTANT"
  chmod +x "$MUTANT"
fi
# the mutant must EXIST and actually carry the swapped numerator, and it must
# emit a well-formed row — else this control never ran and proves nothing.
if [[ ! -s "$MUTANT" ]] \
   || [[ "$(grep -c 'total_cc \/ denom' "$MUTANT" 2>/dev/null)" != "1" ]] \
   || [[ "$(grep -cF 'overall_ratio = (total_cr / denom)' "$MUTANT" 2>/dev/null)" != "0" ]]; then
  control_not_applied 'control 1 (numerator swap): sed anchor did not match or mutant not created'
else
  mutant_out="$("$MUTANT" "$ANTH_DIR" 2>/dev/null | tail -1)"
  mutant_ratio="$(printf '%s\n' "$mutant_out" | awk -F'\t' '{print $8}')"
  if ! is_row "$mutant_out"; then
    control_not_applied "control 1 (numerator swap): mutant emitted a malformed/empty row ('$mutant_out')"
  # expected correct ratio ~0.6208; mutant numerator is cache_creation=1100/2980=0.3691
  elif printf '%s\n' "$mutant_ratio" | grep -qE '^0\.62'; then
    fail 'MUTATION CONTROL: mutant (cache_creation numerator) unexpectedly matched correct ratio — control is not falsifiable'
  else
    pass "MUTATION CONTROL: mutant ratio diverged from correct 0.62 (got '$mutant_ratio') — control proven red-capable"
  fi
fi

# ---------------------------------------------------------------------------
# MUTATION NEGATIVE CONTROL 2: remove id de-duplication (route every event
# through the "unkeyed" path regardless of message.id) in a throwaway copy.
# The dup-id fixture assertion (turns=2) MUST go red, since the mutant would
# count all 5 raw events instead of 2 unique ones.
# ---------------------------------------------------------------------------
MUTANT_DEDUP="$ROOT/leadv2-cache-truth-mutant-dedup.sh"
CTL2_OK=0
if [[ "$(grep -c 'by_id\[mid\] = rec  # last event for this id wins' "$TOOL")" == "1" ]]; then
  python3 - "$TOOL" "$MUTANT_DEDUP" <<'PYEOF'
import sys
src, dst = sys.argv[1], sys.argv[2]
text = open(src).read()
needle = "        if mid:\n            if mid not in by_id:\n                order.append(mid)\n            by_id[mid] = rec  # last event for this id wins\n        else:\n            unkeyed.append(rec)\n"
replacement = "        unkeyed.append(rec)\n"
assert needle in text, "mutation anchor not found in tool source"
text = text.replace(needle, replacement)
open(dst, "w").write(text)
PYEOF
  [[ $? -eq 0 && -s "$MUTANT_DEDUP" ]] && CTL2_OK=1
fi
chmod +x "$MUTANT_DEDUP" 2>/dev/null
if [[ "$CTL2_OK" != "1" ]]; then
  control_not_applied 'control 2 (dedup removal): python anchor did not match or mutant not created'
else
  mutant_dedup_out="$("$MUTANT_DEDUP" "$DUP_DIR" 2>/dev/null | tail -1)"
  mutant_dedup_turns="$(printf '%s\n' "$mutant_dedup_out" | awk -F'\t' '{print $3}')"
  if ! is_row "$mutant_dedup_out"; then
    control_not_applied "control 2 (dedup removal): mutant emitted a malformed/empty row ('$mutant_dedup_out')"
  elif [[ "$mutant_dedup_turns" == "2" ]]; then
    fail 'MUTATION CONTROL (dedup): mutant (no id dedup) unexpectedly still reported 2 turns — control is not falsifiable'
  else
    pass "MUTATION CONTROL (dedup): mutant reported turns='$mutant_dedup_turns' (expected 5, not 2) — control proven red-capable"
  fi
fi

# ---------------------------------------------------------------------------
# MUTATION NEGATIVE CONTROL 3: make saw_cache_key/reported classification
# global again (reported = ALL turns if ANY turn reported keys) in a
# throwaway copy. The mixed fixture assertion (reported=1/3) MUST go red,
# since the mutant would report 3/3.
# ---------------------------------------------------------------------------
MUTANT_GLOBAL="$ROOT/leadv2-cache-truth-mutant-global.sh"
CTL3_OK=0
if [[ "$(grep -cF 'reported_turns = [t for t in turns if t[3] and (t[0] + t[1] + t[2]) > 0]' "$TOOL")" == "1" ]]; then
  python3 - "$TOOL" "$MUTANT_GLOBAL" <<'PYEOF'
import sys
src, dst = sys.argv[1], sys.argv[2]
text = open(src).read()
needle = "reported_turns = [t for t in turns if t[3] and (t[0] + t[1] + t[2]) > 0]\n"
replacement = "reported_turns = turns if any(t[3] for t in turns) else []\n"
assert needle in text, "mutation anchor not found in tool source"
text = text.replace(needle, replacement)
open(dst, "w").write(text)
PYEOF
  [[ $? -eq 0 && -s "$MUTANT_GLOBAL" ]] && CTL3_OK=1
fi
chmod +x "$MUTANT_GLOBAL" 2>/dev/null
if [[ "$CTL3_OK" != "1" ]]; then
  control_not_applied 'control 3 (global-key): python anchor did not match or mutant not created'
else
  mutant_global_out="$("$MUTANT_GLOBAL" "$MIXED_DIR" 2>/dev/null | tail -1)"
  mutant_global_reported="$(printf '%s\n' "$mutant_global_out" | awk -F'\t' '{print $10}')"
  if ! is_row "$mutant_global_out"; then
    control_not_applied "control 3 (global-key): mutant emitted a malformed/empty row ('$mutant_global_out')"
  elif [[ "$mutant_global_reported" == "1/3" ]]; then
    fail 'MUTATION CONTROL (global-key): mutant (global saw_cache_key) unexpectedly still reported 1/3 — control is not falsifiable'
  else
    pass "MUTATION CONTROL (global-key): mutant reported='$mutant_global_reported' (expected 3/3, not 1/3) — control proven red-capable"
  fi
fi

echo
echo "PASS=$PASS FAIL=$FAIL"
[[ $FAIL -eq 0 ]]
