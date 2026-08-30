#!/usr/bin/env bash
# test-freepool-model-liveness.sh — FREEPOOL-MAKE-IT-EARN-ITS-KEEP-01 round 2.
#
# Measured 2026-08-30 against the real proxy: an HTTP 200 with
# content[].text == " " (whitespace only) is a live trap, not a live model.
# leadv2-freepool-model-select.sh's old probe accepted any 2xx status code,
# so it happily chose a route that answers nothing. This suite proves the
# content-based probe rejects that shape and advances rank, with a
# mutation-proven negative control: revert the content check to a bare
# status-code check in a scratch copy of the PRODUCTION file and prove the
# exact bug (blank-body route chosen) reproduces.
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SELECTOR="${SCRIPT_DIR}/lib/leadv2-freepool-model-select.sh"

PASS=0 FAIL=0
pass() { PASS=$((PASS + 1)); printf '[TEST] PASS: %s\n' "$1"; }
fail() { FAIL=$((FAIL + 1)); printf '[TEST] FAIL: %s\n' "$1"; }

ROOT="$(mktemp -d "${TMPDIR:-/tmp}/freepool-model-liveness.XXXXXX")"
trap 'rm -rf "$ROOT"' EXIT

if bash -n "$SELECTOR"; then
  pass 'bash syntax: selector'
else
  fail 'bash syntax: selector'
fi

# The data-only freepool roster is itself dispatch behaviour. Keep the
# changed-scope mapping honest by proving every role exists and the round-3
# implementation/review primaries are the route this lane is meant to run.
if python3 - "${SCRIPT_DIR}/../config/freepool-arm.yaml" <<'PYEOF'
import sys, yaml
cfg = yaml.safe_load(open(sys.argv[1])) or {}
roles = cfg.get("role_rank") or {}
want = {
    "implement": "groq/openai/gpt-oss-120b",
    "review": "groq/openai/gpt-oss-120b",
}
assert all(isinstance(roles.get(role), list) and roles[role] for role in ("implement", "bulk", "review", "read"))
assert all(roles[role][0].get("prefix") == prefix for role, prefix in want.items())
PYEOF
then
  pass 'yaml roster: all roles exist; implement and review primary are gpt-oss-120b'
else
  fail 'yaml roster: role blocks or round-3 primaries drifted'
fi

# ---------------------------------------------------------------------------
# Fixture proxy: fake curl. /v1/models returns a fixed catalog. /v1/messages
# answers per-route: FAKE_CURL_BLANK_ROUTES get 200 + whitespace-only text
# (the live trap), FAKE_CURL_FAIL_ROUTES get a non-2xx, everything else gets
# 200 + real text.
# ---------------------------------------------------------------------------
FAKE_BIN_DIR="$ROOT/bin"
mkdir -p "$FAKE_BIN_DIR"
cat > "$FAKE_BIN_DIR/curl" <<'FAKECURL'
#!/usr/bin/env bash
args=("$@")
url="" out="" write_out=""
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
      [[ -n "$out" ]] && printf '' > "$out"
      [[ -n "$write_out" ]] && printf '500'
      exit 0
    fi
  done

  for blank in ${FAKE_CURL_BLANK_ROUTES:-}; do
    if [[ "$route" == "$blank" ]]; then
      [[ -n "$out" ]] && printf '{"content":[{"type":"text","text":" "}]}' > "$out"
      [[ -n "$write_out" ]] && printf '200'
      exit 0
    fi
  done

  [[ -n "$out" ]] && printf '{"content":[{"type":"text","text":"OK"}]}' > "$out"
  [[ -n "$write_out" ]] && printf '200'
  exit 0
fi

exit 7
FAKECURL
chmod +x "$FAKE_BIN_DIR/curl"

MODELS_FILE="$ROOT/models.json"
cat > "$MODELS_FILE" <<'JSON'
{"data": [
  {"id": "anthropic/nvidia_nim/deepseek-ai/deepseek-v4-pro-0813"},
  {"id": "anthropic/mistral/mistral-code-latest"}
]}
JSON

ARM_CONFIG="$ROOT/freepool-arm.yaml"
cat > "$ARM_CONFIG" <<'YAML'
model_rank:
  - prefix: "anthropic/nvidia_nim/deepseek-ai/deepseek-v4-pro-0813"
    tier: primary
    why: test fixture primary -- answers 200 but blank
  - prefix: "anthropic/mistral/mistral-code-latest"
    tier: secondary
    why: test fixture secondary -- answers 200 with real text
YAML

run_selector() {
  local selector_bin="$1"
  PATH="$FAKE_BIN_DIR:$PATH" \
  FAKE_CURL_MODELS_FILE="$MODELS_FILE" \
  FREEPOOL_ARM_CONFIG="$ARM_CONFIG" \
  FREEPOOL_MODELS_CACHE_FILE="$ROOT/cache-$$-$RANDOM.json" \
  FREEPOOL_MODELS_CACHE_TTL_S=0 \
  FREEPOOL_MODELS_FETCH_TIMEOUT_S=2 \
  FREEPOOL_MODEL_PROBE_TIMEOUT_S=2 \
  FAKE_CURL_FAIL_ROUTES="" \
  FAKE_CURL_BLANK_ROUTES="anthropic/nvidia_nim/deepseek-ai/deepseek-v4-pro-0813" \
  "$selector_bin" 2>"$ROOT/selector.stderr"
}

# --- Case 1 (GREEN, production file): a 200-but-blank primary is rejected,
# the selector advances to the secondary which answers real text.
chosen="$(run_selector "$SELECTOR")"; rc=$?
if [[ "$rc" -eq 0 && "$chosen" == "anthropic/mistral/mistral-code-latest" ]]; then
  pass 'content probe: 200+blank primary rejected, secondary (real text) chosen'
else
  fail "content probe: 200+blank primary rejected, secondary (real text) chosen (rc=$rc chosen=$chosen)"
fi
grep -q 'probe failed for.*deepseek-v4-pro-0813' "$ROOT/selector.stderr" \
  && pass 'content probe: blank route logged as probe failure, not silently skipped' \
  || fail 'content probe: blank route logged as probe failure, not silently skipped'

# --- Case 2 (RED, mutated scratch copy): revert the content check to a bare
# status-code check -- the same fixture must now WRONGLY pick the blank
# primary, reproducing the exact 2026-08-30 live incident shape.
MUTATED="$ROOT/leadv2-freepool-model-select.mutated.sh"
cp "$SELECTOR" "$MUTATED"

# Anchor on the exact status-only probe body this fix replaced. A zero-match
# anchor is a hard failure, not a skip -- it means the fix drifted and this
# control no longer proves anything.
python3 - "$MUTATED" <<'PYEOF'
import re, sys
path = sys.argv[1]
with open(path) as f:
    src = f.read()

start = src.index("_probe() {")
end = src.index("\nmain() {")
old_block = src[start:end]

anchor = 'if [[ ! "${code}" =~ ^2[0-9][0-9]$ ]]; then'
if anchor not in old_block:
    print("ANCHOR_NOT_FOUND", file=sys.stderr)
    sys.exit(1)

new_block = '''_probe() {
  local route_id="$1"
  local probe_max_tokens="${FREEPOOL_MODEL_PROBE_MAX_TOKENS:-64}"
  local code
  code="$(curl -s -o /dev/null -w '%{http_code}' --max-time "${PROBE_TIMEOUT_S}" \\
    -X POST "${FREEPOOL_BASE_URL}/v1/messages" \\
    -H "Content-Type: application/json" \\
    -d "$(printf '{"model":"%s","max_tokens":%s,"messages":[{"role":"user","content":"hi"}]}' "${route_id}" "${probe_max_tokens}")" \\
    2>/dev/null || echo "000")"
  [[ "${code}" =~ ^2[0-9][0-9]$ ]]
}
'''

src2 = src[:start] + new_block + src[end:]
with open(path, "w") as f:
    f.write(src2)
PYEOF
mutate_rc=$?
if [[ "$mutate_rc" -ne 0 ]]; then
  fail 'mutation anchor: _probe status-only reversion (anchor not found -- production shape drifted, control is void)'
else
  pass 'mutation applied: _probe reverted to status-code-only check (scratch copy)'
fi

bash -n "$MUTATED" || fail 'mutated selector fails bash -n (control setup broken)'

mutated_chosen="$(run_selector "$MUTATED")"; mutated_rc=$?
if [[ "$mutated_rc" -eq 0 && "$mutated_chosen" == "anthropic/nvidia_nim/deepseek-ai/deepseek-v4-pro-0813" ]]; then
  pass 'MUTATION KILLED: status-only probe wrongly picks the blank-body route (reproduces the 2026-08-30 incident)'
else
  fail "MUTATION KILLED: status-only probe wrongly picks the blank-body route (rc=$mutated_rc chosen=$mutated_chosen)"
fi

echo "=== ${PASS} passed, ${FAIL} failed ==="
[[ "$FAIL" -eq 0 ]]
