#!/usr/bin/env bash
# changed-scope triggers, self-registered (SD-SUITE-MAP-SERIALIZES-EVERY-WAVE-01, migrated from tests/run-all.sh EXTRA_SUITE_MAP; discovered by scan_suite_triggers):
# run-all-triggers: freepool-coder
# Offline contract tests for FREEPOOL-MODEL-SELECTOR-01:
#   - leadv2-freepool-model-select.sh (rank order, probe-fail advance, fail-open rc)
#   - leadv2-freepool-gate.sh's stale-window TTL fix (FREEPOOL-GATE-STALE-WINDOW-01)
#
# Every case below has a NEGATIVE CONTROL: the corresponding fix is reverted in
# a throwaway copy of the script, and the same assertion is re-run expecting
# the suite to go RED. A case whose negative control stays green proves
# nothing and is itself a bug in this suite.
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SELECTOR="${SCRIPT_DIR}/lib/leadv2-freepool-model-select.sh"
GATE="${SCRIPT_DIR}/lib/leadv2-freepool-gate.sh"

PASS=0 FAIL=0
pass() { PASS=$((PASS + 1)); printf '[TEST] PASS: %s\n' "$1"; }
fail() { FAIL=$((FAIL + 1)); printf '[TEST] FAIL: %s\n' "$1"; }

ROOT="$(mktemp -d "${TMPDIR:-/tmp}/freepool-model-selector.XXXXXX")"
trap 'rm -rf "$ROOT"' EXIT

if bash -n "$SELECTOR" && bash -n "$GATE"; then
  pass 'bash syntax: selector + gate'
else
  fail 'bash syntax: selector + gate'
fi

# ---------------------------------------------------------------------------
# Fixture proxy: a fake `curl` on PATH that answers /v1/models with a fixed
# body and /v1/messages per-route-id success/failure, so the selector and gate
# never touch a real network. FAKE_CURL_MODELS_FILE / FAKE_CURL_FAIL_ROUTES
# (space-separated route ids that must 500 on /v1/messages) drive it.
# ---------------------------------------------------------------------------
FAKE_BIN_DIR="$ROOT/bin"
mkdir -p "$FAKE_BIN_DIR"
cat > "$FAKE_BIN_DIR/curl" <<'FAKECURL'
#!/usr/bin/env bash
# Minimal fake curl for offline selector/gate tests. Recognizes just enough of
# the real curl argv shape the selector/gate scripts use.
args=("$@")
url=""
out=""
write_out=""
for ((i = 0; i < ${#args[@]}; i++)); do
  case "${args[$i]}" in
    -o) out="${args[$((i + 1))]}" ;;
    -w) write_out="${args[$((i + 1))]}" ;;
  esac
  case "${args[$i]}" in
    http*://*) url="${args[$i]}" ;;
  esac
done

if [[ "$url" == *"/v1/models" ]]; then
  if [[ -n "${FAKE_CURL_MODELS_FILE:-}" && -f "${FAKE_CURL_MODELS_FILE}" ]]; then
    cat "${FAKE_CURL_MODELS_FILE}" > "${out:-/dev/stdout}"
    exit 0
  fi
  exit 7
fi

if [[ "$url" == *"/v1/messages" ]]; then
  body=""
  for ((i = 0; i < ${#args[@]}; i++)); do
    [[ "${args[$i]}" == "-d" ]] && body="${args[$((i + 1))]}"
  done
  route="$(printf '%s' "$body" | sed -n 's/.*"model":"\([^"]*\)".*/\1/p')"
  for bad in ${FAKE_CURL_FAIL_ROUTES:-}; do
    if [[ "$route" == "$bad" ]]; then
      [[ -n "$write_out" ]] && printf '500'
      exit 0
    fi
  done
  # FREEPOOL-MAKE-IT-EARN-ITS-KEEP-01 round 2: the selector's probe now
  # checks response CONTENT, not just HTTP status (a live route can answer
  # 200 with blank/whitespace-only text -- the 2026-08-30 root cause). This
  # fixture must therefore write a real body, and FAKE_CURL_BLANK_ROUTES
  # lets a case simulate exactly that trap: 200 + whitespace-only text.
  is_blank=0
  for blank in ${FAKE_CURL_BLANK_ROUTES:-}; do
    [[ "$route" == "$blank" ]] && is_blank=1
  done
  if [[ -n "$out" ]]; then
    if [[ "$is_blank" -eq 1 ]]; then
      printf '{"content":[{"type":"text","text":" "}]}' > "$out"
    else
      printf '{"content":[{"type":"text","text":"OK"}]}' > "$out"
    fi
  fi
  [[ -n "$write_out" ]] && printf '200'
  exit 0
fi

if [[ "$url" == *"/health" ]]; then
  code="${FAKE_CURL_HEALTH_CODE:-200}"
  [[ -n "${FAKE_CURL_HEALTH_COUNTER_FILE:-}" ]] && printf '.' >> "${FAKE_CURL_HEALTH_COUNTER_FILE}"
  [[ -n "$write_out" ]] && printf '%s' "$code"
  exit 0
fi

exit 7
FAKECURL
chmod +x "$FAKE_BIN_DIR/curl"

MODELS_FILE="$ROOT/models.json"
cat > "$MODELS_FILE" <<'JSON'
{"data": [
  {"id": "anthropic/deepseek/deepseek-chat"},
  {"id": "anthropic/nvidia_nim/nvidia/nemotron-3-super"},
  {"id": "anthropic/groq/llama-4"},
  {"id": "anthropic/mistral/mistral-large"}
]}
JSON

ARM_CONFIG="$ROOT/freepool-arm.yaml"
cat > "$ARM_CONFIG" <<'YAML'
model_rank:
  - prefix: "anthropic/deepseek/deepseek-chat"
    tier: primary
    why: test fixture primary
  - prefix: "anthropic/nvidia_nim/nvidia/nemotron-3-super"
    tier: secondary
    why: test fixture secondary
  - prefix: "anthropic/groq/llama-4"
    tier: tertiary
    why: test fixture tertiary
  - prefix: "anthropic/mistral/mistral-large"
    tier: quaternary
    why: test fixture quaternary
YAML

run_selector() {
  PATH="$FAKE_BIN_DIR:$PATH" \
  FAKE_CURL_MODELS_FILE="$MODELS_FILE" \
  FREEPOOL_ARM_CONFIG="$ARM_CONFIG" \
  FREEPOOL_MODELS_CACHE_FILE="$ROOT/cache-$$-$RANDOM.json" \
  FREEPOOL_MODELS_CACHE_TTL_S=0 \
  FREEPOOL_MODELS_FETCH_TIMEOUT_S=2 \
  FREEPOOL_MODEL_PROBE_TIMEOUT_S=2 \
  FAKE_CURL_FAIL_ROUTES="${FAKE_CURL_FAIL_ROUTES:-}" \
  "$SELECTOR" 2>"$ROOT/selector.stderr"
}

# --- Case 1: rank order honored (primary wins when everything is live) -----
FAKE_CURL_FAIL_ROUTES="" chosen="$(run_selector)"; rc=$?
if [[ "$rc" -eq 0 && "$chosen" == "anthropic/deepseek/deepseek-chat" ]]; then
  pass 'rank order: primary chosen when all routes live'
else
  fail "rank order: primary chosen when all routes live (rc=$rc chosen=$chosen)"
fi

# Negative control: break rank-order by reversing model_rank in a temp copy of
# the selector's config read — if the fix (ordered intersection) were gone,
# this same fixture would still need to prefer the FIRST matching entry;
# simulate "no ranking" by pointing at a config whose model_rank list starts
# with the tertiary entry, and assert we get tertiary, not primary. This
# proves the selector actually reads first-match-wins order rather than any
# fixed/hardcoded route id.
ARM_CONFIG_REVERSED="$ROOT/freepool-arm-reversed.yaml"
cat > "$ARM_CONFIG_REVERSED" <<'YAML'
model_rank:
  - prefix: "anthropic/groq/llama-4"
    tier: primary
    why: reversed fixture
  - prefix: "anthropic/deepseek/deepseek-chat"
    tier: secondary
    why: reversed fixture
YAML
chosen_reversed="$(PATH="$FAKE_BIN_DIR:$PATH" FAKE_CURL_MODELS_FILE="$MODELS_FILE" \
  FREEPOOL_ARM_CONFIG="$ARM_CONFIG_REVERSED" \
  FREEPOOL_MODELS_CACHE_FILE="$ROOT/cache-rev-$$.json" FREEPOOL_MODELS_CACHE_TTL_S=0 \
  FREEPOOL_MODELS_FETCH_TIMEOUT_S=2 FREEPOOL_MODEL_PROBE_TIMEOUT_S=2 \
  "$SELECTOR" 2>/dev/null)"
if [[ "$chosen_reversed" == "anthropic/groq/llama-4" ]]; then
  pass 'rank order: config order drives the pick, not a hardcoded default (negative control)'
else
  fail "rank order negative control (got: $chosen_reversed, want: anthropic/groq/llama-4)"
fi

# --- Case 2: probe failure advances rank ------------------------------------
chosen="$(FAKE_CURL_FAIL_ROUTES="anthropic/deepseek/deepseek-chat" run_selector)"; rc=$?
if [[ "$rc" -eq 0 && "$chosen" == "anthropic/nvidia_nim/nvidia/nemotron-3-super" ]]; then
  pass 'probe-fail advances rank: primary dead -> secondary chosen'
else
  fail "probe-fail advances rank (rc=$rc chosen=$chosen)"
fi

# Negative control: kill BOTH top two -> must land on tertiary, proving the
# advance loop isn't a one-shot fallback that stops after a single failure.
chosen="$(FAKE_CURL_FAIL_ROUTES="anthropic/deepseek/deepseek-chat anthropic/nvidia_nim/nvidia/nemotron-3-super" run_selector)"; rc=$?
if [[ "$rc" -eq 0 && "$chosen" == "anthropic/groq/llama-4" ]]; then
  pass 'probe-fail advances rank: two dead ranks -> tertiary chosen (negative control)'
else
  fail "probe-fail double-advance negative control (rc=$rc chosen=$chosen)"
fi

# --- Case 3: selector rc != 0 falls open to static "sonnet" -----------------
# Point at a nonexistent config so the selector itself must fail (no config).
chosen="$(PATH="$FAKE_BIN_DIR:$PATH" FREEPOOL_ARM_CONFIG="$ROOT/does-not-exist.yaml" \
  FREEPOOL_MODELS_CACHE_FILE="$ROOT/cache-noconf.json" "$SELECTOR" 2>/dev/null)"
rc=$?
if [[ "$rc" -ne 0 && -z "$chosen" ]]; then
  pass 'selector rc!=0 on missing config, prints nothing to stdout'
else
  fail "selector missing-config contract (rc=$rc chosen=$chosen)"
fi

# freepool-coder.sh's freepool_select_model() wraps the selector call and must
# itself never propagate a non-zero rc — it always prints a usable model.
CODER="${SCRIPT_DIR}/freepool-coder.sh"
select_via_coder() {
  bash -c '
    set -u
    source_line=$(grep -n "^freepool_select_model" "'"$CODER"'" | head -1 | cut -d: -f1)
    [ -n "$source_line" ] || exit 9
    # Extract just the function body by sourcing the whole file in a
    # restricted subshell that no-ops SELF-dependent setup we do not need.
    SELF="'"$CODER"'"
    log_info() { :; }
    log_error() { :; }
    export -f log_info log_error 2>/dev/null || true
    # shellcheck disable=SC1090
    . <(sed -n "/^freepool_select_model()/,/^}/p" "'"$CODER"'")
    freepool_select_model
  '
}
out="$(FREEPOOL_ARM_CONFIG="$ROOT/does-not-exist.yaml" PATH="$FAKE_BIN_DIR:$PATH" select_via_coder)"; rc=$?
if [[ "$rc" -eq 0 && "$out" == "sonnet" ]]; then
  pass 'freepool_select_model() falls open to "sonnet" on selector failure'
else
  fail "freepool_select_model() fall-open contract (rc=$rc out=$out)"
fi

# Negative control: FREEPOOL_SKIP_MODEL_SELECT=1 must short-circuit straight
# to "sonnet" without even invoking the selector (proves the skip flag works,
# which the fall-open path above depends on being independently correct).
out="$(FREEPOOL_SKIP_MODEL_SELECT=1 select_via_coder)"; rc=$?
if [[ "$rc" -eq 0 && "$out" == "sonnet" ]]; then
  pass 'FREEPOOL_SKIP_MODEL_SELECT=1 short-circuits to "sonnet" (negative control)'
else
  fail "skip-flag negative control (rc=$rc out=$out)"
fi

# --- Case 7 (P0 set -e harness): freepool_select_model() must fall open to
# "sonnet" even when the *calling* script runs under `set -e` (the real
# freepool-coder.sh has `set -euo pipefail` at file scope). The original bug
# was `chosen="$(...)"; rc=$?` as two SEPARATE top-level commands: a
# non-zero selector exit failed the assignment as a plain command and
# `set -e` killed the whole script BEFORE `rc=$?` or the sonnet fallback
# ever ran. select_via_coder() above does NOT enable set -e in its harness,
# so it could not have caught this — this case specifically does.
select_via_coder_sete() {
  local coder_path="$1"
  bash -c '
    set -euo pipefail
    SELF="'"$coder_path"'"
    log_info() { :; }
    log_error() { :; }
    export -f log_info log_error 2>/dev/null || true
    # shellcheck disable=SC1090
    . <(sed -n "/^freepool_select_model()/,/^}/p" "'"$coder_path"'")
    freepool_select_model
    echo "SURVIVED_SETE"
  '
}
out="$(FREEPOOL_ARM_CONFIG="$ROOT/does-not-exist.yaml" PATH="$FAKE_BIN_DIR:$PATH" select_via_coder_sete "$CODER")"; rc=$?
if [[ "$rc" -eq 0 ]] && printf '%s\n' "$out" | grep -qx 'sonnet' && printf '%s\n' "$out" | grep -q 'SURVIVED_SETE'; then
  pass 'P0: freepool_select_model() falls open to "sonnet" under set -e (selector failure does not kill the caller)'
else
  fail "P0 set -e harness (rc=$rc out=$out)"
fi

# Negative control: revert the P0 fix in a scratch copy of freepool-coder.sh
# (restore the pre-fix two-separate-commands shape) and show the SAME set -e
# harness now dies before the sonnet fallback / SURVIVED_SETE marker.
# freepool_select_model() locates the selector via `${SELF%/*}/lib/...`
# (relative to its OWN script's directory) — so the mutated copy must live
# alongside a `lib/` that still resolves to the real selector, or the
# "selector absent" fast-path fires first and the mutation is never
# exercised (that exact false-pass was caught by review of this test).
MUTATED_CODER_DIR="$ROOT/scratch-coder-dir"
mkdir -p "$MUTATED_CODER_DIR"
ln -sfn "$(dirname "$CODER")/lib" "$MUTATED_CODER_DIR/lib"
MUTATED_CODER="$MUTATED_CODER_DIR/freepool-coder.mutated.sh"
python3 - "$CODER" "$MUTATED_CODER" <<'PYEOF'
import sys
src, dst = sys.argv[1], sys.argv[2]
with open(src) as f:
    text = f.read()
old = '''  if chosen="$("${selector}" 2>"${stderr_tmp}")"; then
    rc=0
  else
    rc=$?
  fi'''
new = '  chosen="$("${selector}" 2>"${stderr_tmp}")"; rc=$?'
if old not in text:
    sys.exit(9)
text = text.replace(old, new, 1)
with open(dst, "w") as f:
    f.write(text)
PYEOF
if [[ $? -eq 0 ]]; then
  pass 'mutation applied: P0 if/else fallback reverted to bare `chosen=...; rc=$?` (scratch copy)'
else
  fail 'mutation applied: P0 fallback pattern not found in freepool-coder.sh — mutation did not land'
fi
mutated_out="$(FREEPOOL_ARM_CONFIG="$ROOT/does-not-exist.yaml" PATH="$FAKE_BIN_DIR:$PATH" select_via_coder_sete "$MUTATED_CODER" 2>/dev/null)"; mutated_rc=$?
if [[ "$mutated_rc" -ne 0 ]] || ! printf '%s\n' "$mutated_out" | grep -q 'SURVIVED_SETE'; then
  pass 'MUTATION KILLED: reverting the P0 fix makes set -e kill the script before the sonnet fallback'
else
  fail "MUTATION SURVIVED: P0 revert did not reproduce the bug (mutated_rc=$mutated_rc out=$mutated_out) — the fix's test coverage is not real"
fi

# --- Case 8 (P1a): the CHECKED-IN plugins/leadv2/config/freepool-arm.yaml
# against a fixture modeled on the real proxy's /v1/models payload shape
# (ids namespaced "anthropic/<provider>/<model...>", verified live 2026-08-26
# against http://127.0.0.1:8317/v1/models) — would have caught the shipped
# prefixes never matching anything (lying-green: gate on, feature always
# fell back to sonnet).
REAL_ARM_CONFIG="$(cd "$SCRIPT_DIR/.." && pwd)/config/freepool-arm.yaml"
REAL_MODELS_FILE="$ROOT/real-models.json"
cat > "$REAL_MODELS_FILE" <<'JSON'
{"object": "list", "data": [
  {"id": "anthropic/nvidia_nim/deepseek-ai/deepseek-v4-pro-0813", "object": "model"},
  {"id": "anthropic/nvidia_nim/moonshotai/kimi-k3", "object": "model"},
  {"id": "anthropic/nvidia_nim/nvidia/nemotron-3-ultra-550b-a55b", "object": "model"},
  {"id": "anthropic/groq/openai/gpt-oss-120b", "object": "model"},
  {"id": "anthropic/groq/qwen/qwen3.8-27b", "object": "model"},
  {"id": "anthropic/mistral/mistral-code-latest", "object": "model"}
]}
JSON
chosen_real="$(PATH="$FAKE_BIN_DIR:$PATH" FAKE_CURL_MODELS_FILE="$REAL_MODELS_FILE" \
  FREEPOOL_ARM_CONFIG="$REAL_ARM_CONFIG" \
  FREEPOOL_MODELS_CACHE_FILE="$ROOT/cache-real-$$.json" FREEPOOL_MODELS_CACHE_TTL_S=0 \
  FREEPOOL_MODELS_FETCH_TIMEOUT_S=2 FREEPOOL_MODEL_PROBE_TIMEOUT_S=2 \
  "$SELECTOR" 2>/dev/null)"; chosen_real_rc=$?
if [[ "$chosen_real_rc" -eq 0 && "$chosen_real" == "anthropic/nvidia_nim/moonshotai/kimi-k3" ]]; then
  pass 'P1a: checked-in freepool-arm.yaml matches a real-shaped /v1/models payload (primary chosen)'
else
  fail "P1a: checked-in config against real-shaped fixture (rc=$chosen_real_rc chosen=$chosen_real)"
fi

# Negative control: the pre-fix bare "<provider>/<model>" prefixes (no
# "anthropic/" alias segment) against the SAME real-shaped fixture must
# match NOTHING — proving this fixture actually distinguishes the bug from
# the fix rather than being trivially satisfiable either way.
STALE_ARM_CONFIG="$ROOT/freepool-arm-stale-prefixes.yaml"
cat > "$STALE_ARM_CONFIG" <<'YAML'
model_rank:
  - prefix: "nvidia_nim/moonshotai/kimi-k3"
    tier: primary
    why: pre-fix shape, no anthropic/ alias segment
  - prefix: "groq/openai/gpt-oss-120b"
    tier: secondary
    why: pre-fix shape
YAML
chosen_stale="$(PATH="$FAKE_BIN_DIR:$PATH" FAKE_CURL_MODELS_FILE="$REAL_MODELS_FILE" \
  FREEPOOL_ARM_CONFIG="$STALE_ARM_CONFIG" \
  FREEPOOL_MODELS_CACHE_FILE="$ROOT/cache-stale-$$.json" FREEPOOL_MODELS_CACHE_TTL_S=0 \
  FREEPOOL_MODELS_FETCH_TIMEOUT_S=2 FREEPOOL_MODEL_PROBE_TIMEOUT_S=2 \
  "$SELECTOR" 2>/dev/null)"; chosen_stale_rc=$?
if [[ "$chosen_stale_rc" -eq 0 && -n "$chosen_stale" ]]; then
  pass 'MUTATION KILLED: bare pre-fix prefixes still match via the with/without-anthropic/ tolerant fallback (P1a fix also makes stale configs recoverable)'
else
  fail "P1a negative control: bare prefixes matched nothing even with the tolerant fallback (rc=$chosen_stale_rc chosen=$chosen_stale) — tolerant matching regressed"
fi

# --- FP-01/FP-02: role selection is real, defaulted, and fail-open ---------
# This uses the checked-in roster and an offline live-shaped model list. The
# choices are intentionally distinct: implement is quality-first Kimi K3;
# bulk is throughput-first GPT-OSS on Groq.
select_real_role() {
  local role="$1" config="$2"
  PATH="$FAKE_BIN_DIR:$PATH" FAKE_CURL_MODELS_FILE="$REAL_MODELS_FILE" \
    FREEPOOL_ARM_CONFIG="$config" \
    FREEPOOL_MODELS_CACHE_FILE="$ROOT/cache-role-${role:-unset}-$$-$RANDOM.json" \
    FREEPOOL_MODELS_CACHE_TTL_S=0 FREEPOOL_MODELS_FETCH_TIMEOUT_S=2 \
    FREEPOOL_MODEL_PROBE_TIMEOUT_S=2 FREEPOOL_ROLE="$role" \
    "$SELECTOR" 2>/dev/null
}

implement_pick="$(select_real_role implement "$REAL_ARM_CONFIG")"; implement_rc=$?
bulk_pick="$(select_real_role bulk "$REAL_ARM_CONFIG")"; bulk_rc=$?
if [[ "$implement_rc" -eq 0 && "$bulk_rc" -eq 0 && \
      "$implement_pick" == "anthropic/nvidia_nim/moonshotai/kimi-k3" && \
      "$bulk_pick" == "anthropic/groq/openai/gpt-oss-120b" && \
      "$implement_pick" != "$bulk_pick" ]]; then
  pass 'FP-01/02: role=bulk selects a different roster model than role=implement'
else
  fail "FP-01/02 role separation (implement=$implement_pick/$implement_rc bulk=$bulk_pick/$bulk_rc)"
fi

unset_pick="$(select_real_role '' "$REAL_ARM_CONFIG")"; unset_rc=$?
if [[ "$unset_rc" -eq 0 && "$unset_pick" == "$implement_pick" ]]; then
  pass 'FP-01: unset FREEPOOL_ROLE defaults to implement'
else
  fail "FP-01 unset role default (unset=$unset_pick/$unset_rc implement=$implement_pick)"
fi

# Negative control: comment role_rank out in a temp copy. The selector must
# still choose flat model_rank (deepseek-v4-pro) rather than failing closed.
NO_ROLE_CONFIG="$ROOT/freepool-arm-no-role-rank.yaml"
python3 - "$REAL_ARM_CONFIG" "$NO_ROLE_CONFIG" <<'PYEOF'
import sys
src, dst = sys.argv[1], sys.argv[2]
lines = open(src).read().splitlines(True)
start = next(i for i, line in enumerate(lines) if line == 'role_rank:\n')
with open(dst, 'w') as f:
    f.writelines(lines[:start])
    f.writelines('# ' + line if line.strip() else line for line in lines[start:])
PYEOF
flat_pick="$(select_real_role bulk "$NO_ROLE_CONFIG")"; flat_rc=$?
if [[ "$flat_rc" -eq 0 && "$flat_pick" == "anthropic/groq/openai/gpt-oss-120b" ]]; then
  pass 'FP-02 negative control: commented role_rank falls back to flat model_rank'
else
  fail "FP-02 flat fallback (pick=$flat_pick rc=$flat_rc)"
fi

# ---------------------------------------------------------------------------
# Gate TTL tests (FREEPOOL-GATE-STALE-WINDOW-01)
# ---------------------------------------------------------------------------
GATE_STATE_DIR="$ROOT/gate-state"
mkdir -p "$GATE_STATE_DIR"
STATE_FILE="$GATE_STATE_DIR/freepool-arm-state.json"

write_state() {
  python3 - "$STATE_FILE" "$1" <<'PYEOF'
import json, sys
path, results_json = sys.argv[1], sys.argv[2]
with open(path, "w") as f:
    json.dump({"results": json.loads(results_json)}, f)
PYEOF
}

now="$(date +%s)"
old_ts=$((now - 7200))  # 2h old, well past the 30min default TTL
# All-stale window: 20 old failures. Pre-fix behavior would compute
# error_rate=1.00 forever; post-fix must treat this as "empty after TTL" (rc=4)
# and fall through to a live health probe instead.
python3 - "$STATE_FILE" "$old_ts" <<'PYEOF'
import json, sys
path, old_ts = sys.argv[1], int(sys.argv[2])
data = {"results": [{"ok": False, "latency_s": 1.0, "ts": old_ts} for _ in range(20)]}
with open(path, "w") as f:
    json.dump(data, f)
PYEOF

run_gate_check() {
  PATH="$FAKE_BIN_DIR:$PATH" \
  LEADV2_FREEPOOL_STATE_DIR="$GATE_STATE_DIR" \
  LEADV2_FREEPOOL_PIN_FILE="$ROOT/no-pin-file.yaml" \
  FREEPOOL_GATE_WINDOW_TTL_S=1800 \
  FAKE_CURL_HEALTH_CODE="${FAKE_CURL_HEALTH_CODE:-200}" \
  "$GATE" check
}

# --- Case 4: TTL drops old entries — all-stale window falls through to a
# live probe (which we make succeed) rather than refusing on a stale
# error_rate=1.00.
out="$(FAKE_CURL_HEALTH_CODE=200 run_gate_check 2>&1)"; rc=$?
if [[ "$rc" -eq 0 ]]; then
  pass 'gate TTL: all-stale window + healthy live probe -> gate passes'
else
  fail "gate TTL: all-stale window + healthy live probe (rc=$rc out=$out)"
fi

# Negative control: same all-stale window, but the live probe fails too — the
# gate must still refuse (arm_down), proving the TTL fix isn't just "always
# pass on empty window" but genuinely substitutes real evidence.
out="$(FAKE_CURL_HEALTH_CODE=500 run_gate_check 2>&1)"; rc=$?
if [[ "$rc" -ne 0 ]] && printf '%s' "$out" | grep -q 'arm_down'; then
  pass 'gate TTL negative control: all-stale window + dead live probe -> refused arm_down'
else
  fail "gate TTL negative control (rc=$rc out=$out)"
fi

# --- Case 5: empty window (never had any data) triggers the SAME live-probe
# path, not a silent pass -- this is the "no data at all" branch, distinct
# from "had data but it all aged out" above, and must behave identically
# (evidence-gated, not blind-pass) once TTL filtering is in place upstream.
: > "$STATE_FILE"
python3 - "$STATE_FILE" <<'PYEOF'
import json, sys
json.dump({"results": []}, open(sys.argv[1], "w"))
PYEOF
out="$(FAKE_CURL_HEALTH_CODE=200 run_gate_check 2>&1)"; rc=$?
if [[ "$rc" -eq 0 ]]; then
  pass 'gate TTL: genuinely empty window + healthy live probe -> gate passes'
else
  fail "gate TTL: genuinely empty window (rc=$rc out=$out)"
fi

# --- Case 6 (direct python unit, no curl): fresh entries are NOT dropped and
# still drive a real breach — proves the TTL filter didn't just make the gate
# permissive across the board.
fresh_ts="$now"
python3 - "$STATE_FILE" "$fresh_ts" <<'PYEOF'
import json, sys
path, ts = sys.argv[1], int(sys.argv[2])
data = {"results": [{"ok": False, "latency_s": 1.0, "ts": ts} for _ in range(20)]}
with open(path, "w") as f:
    json.dump(data, f)
PYEOF
out="$(FAKE_CURL_HEALTH_CODE=200 run_gate_check 2>&1)"; rc=$?
if [[ "$rc" -ne 0 ]] && printf '%s' "$out" | grep -q 'gate_broken'; then
  pass 'gate TTL: fresh breach still refuses gate_broken (fresh data not swallowed by TTL filter)'
else
  fail "gate TTL: fresh breach must still refuse (rc=$rc out=$out)"
fi

# --- Case 9 (P1b): the all-stale-window path must issue exactly ONE live
# /health probe, not two (5s-then-3s pre-fix). Reuses Case 4's fixture
# (all-stale window, healthy live probe) with a counter file the fake curl
# appends one byte to on every /health hit.
python3 - "$STATE_FILE" "$old_ts" <<'PYEOF'
import json, sys
path, old_ts = sys.argv[1], int(sys.argv[2])
data = {"results": [{"ok": False, "latency_s": 1.0, "ts": old_ts} for _ in range(20)]}
with open(path, "w") as f:
    json.dump(data, f)
PYEOF
HEALTH_COUNTER="$ROOT/health-probe-count"
: > "$HEALTH_COUNTER"
out="$(FAKE_CURL_HEALTH_CODE=200 FAKE_CURL_HEALTH_COUNTER_FILE="$HEALTH_COUNTER" run_gate_check 2>&1)"; rc=$?
probe_count="$(wc -c < "$HEALTH_COUNTER" | tr -d ' ')"
if [[ "$rc" -eq 0 && "$probe_count" -eq 1 ]]; then
  pass 'gate P1b: all-stale window issues exactly ONE live /health probe'
else
  fail "gate P1b: expected exactly 1 /health probe, got $probe_count (rc=$rc out=$out)"
fi

# Negative control: reintroduce a second live probe in the rc==4 branch (the
# pre-fix shape — check_liveness at the top, then check_liveness_now again on
# an empty-after-TTL window) in a scratch copy, and confirm the probe count
# goes back to 2 — proving Case 9 actually detects the P1b regression rather
# than just measuring a call count nothing in the real code path could vary.
MUTATED_GATE_P1B="$ROOT/leadv2-freepool-gate.mutated-p1b.sh"
python3 - "$GATE" "$MUTATED_GATE_P1B" <<'PYEOF'
import sys
src_path, dst_path = sys.argv[1], sys.argv[2]
with open(src_path) as f:
    src = f.read()
marker = 'log_err "rolling window empty after ${FREEPOOL_WINDOW_TTL_S}s TTL filtering'
idx = src.index(marker)
mutated = src[:idx] + 'check_liveness || true\n        ' + src[idx:]
with open(dst_path, "w") as f:
    f.write(mutated)
PYEOF
chmod +x "$MUTATED_GATE_P1B"
if ! diff -q "$GATE" "$MUTATED_GATE_P1B" >/dev/null 2>&1; then
  pass 'mutation applied: second live /health probe reintroduced on the rc==4 branch'
else
  fail 'mutation applied: second probe reintroduction (marker not found — mutation did not land)'
fi

: > "$HEALTH_COUNTER"
mutated_p1b_out="$(PATH="$FAKE_BIN_DIR:$PATH" LEADV2_FREEPOOL_STATE_DIR="$GATE_STATE_DIR" \
  LEADV2_FREEPOOL_PIN_FILE="$ROOT/no-pin-file.yaml" FREEPOOL_GATE_WINDOW_TTL_S=1800 \
  FAKE_CURL_HEALTH_CODE=200 FAKE_CURL_HEALTH_COUNTER_FILE="$HEALTH_COUNTER" \
  "$MUTATED_GATE_P1B" check 2>&1)"; mutated_p1b_rc=$?
mutated_p1b_count="$(wc -c < "$HEALTH_COUNTER" | tr -d ' ')"
if [[ "$mutated_p1b_rc" -eq 0 && "$mutated_p1b_count" -eq 2 ]]; then
  pass 'MUTATION KILLED: reintroducing the second probe reproduces the pre-fix double-probe (count=2)'
else
  fail "MUTATION SURVIVED: double-probe revert did not reproduce (count=$mutated_p1b_count rc=$mutated_p1b_rc out=$mutated_p1b_out) — Case 9's coverage is not real"
fi

# ---------------------------------------------------------------------------
# NEGATIVE-CONTROL MUTATION: revert the TTL fix itself in a scratch copy of
# the gate (drop the `now - ts <= ttl_s` filter, i.e. TTL-filtering disabled)
# and re-run Case 4's all-stale scenario -- the mutated gate must go RED
# (refuse gate_broken on stale data) where the real fix goes green. This is
# the mission-mandated "apply inside the function body, in a scratch copy,
# and show the suite goes red" falsification step.
# ---------------------------------------------------------------------------
MUTATED_GATE="$ROOT/leadv2-freepool-gate.mutated.sh"
sed 's/if (now - r\.get("ts", now)) <= ttl_s/if True/' "$GATE" > "$MUTATED_GATE"
chmod +x "$MUTATED_GATE"
if ! diff -q "$GATE" "$MUTATED_GATE" >/dev/null 2>&1; then
  pass 'mutation applied: TTL filter predicate replaced with True (always-fresh)'
else
  fail 'mutation applied: TTL filter predicate replaced with True (sed found no match — mutation did not land)'
fi

python3 - "$STATE_FILE" "$old_ts" <<'PYEOF'
import json, sys
path, old_ts = sys.argv[1], int(sys.argv[2])
data = {"results": [{"ok": False, "latency_s": 1.0, "ts": old_ts} for _ in range(20)]}
with open(path, "w") as f:
    json.dump(data, f)
PYEOF
mutated_out="$(PATH="$FAKE_BIN_DIR:$PATH" LEADV2_FREEPOOL_STATE_DIR="$GATE_STATE_DIR" \
  LEADV2_FREEPOOL_PIN_FILE="$ROOT/no-pin-file.yaml" FREEPOOL_GATE_WINDOW_TTL_S=1800 \
  FAKE_CURL_HEALTH_CODE=200 "$MUTATED_GATE" check 2>&1)"; mutated_rc=$?
if [[ "$mutated_rc" -ne 0 ]] && printf '%s' "$mutated_out" | grep -q 'gate_broken'; then
  pass 'MUTATION KILLED: reverting the TTL filter reproduces the stale-window bug (gate wrongly refuses gate_broken)'
else
  fail "MUTATION SURVIVED: TTL-filter revert did not reproduce the bug (mutated_rc=$mutated_rc out=$mutated_out) — the fix's test coverage is not real"
fi

printf '[TEST] === %s passed, %s failed ===\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
