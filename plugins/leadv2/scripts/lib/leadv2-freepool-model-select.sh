#!/usr/bin/env bash
# leadv2-freepool-model-select.sh — FREEPOOL-MODEL-SELECTOR-01.
#
# Picks the best live model for one freepool worker spawn instead of pinning
# a single static route id. Reads plugins/leadv2/config/freepool-arm.yaml's
# `model_rank` (ordered list of route-id PREFIXES, most-preferred first),
# fetches the proxy's live GET /v1/models, and for the first rank whose
# prefix has a live route, runs a content-based liveness probe (a short deterministic prompt must come back with non-whitespace text, not just HTTP 200). First
# candidate whose probe succeeds wins; a probe failure advances to the next
# rank.
#
# Contract: prints the chosen route id on stdout and exits 0. On ANY
# failure (no config, no models reachable, all ranked candidates dead) exits
# non-zero and prints NOTHING to stdout — callers must fail open to their
# existing static default, never block the spawn on this script.
#
# Env knobs (all optional, defaults match prod):
#   FREEPOOL_PROXY_URL              proxy base url (default http://127.0.0.1:8317)
#   FREEPOOL_ARM_CONFIG              path to freepool-arm.yaml (default sibling ../../config/freepool-arm.yaml)
#   FREEPOOL_MODELS_CACHE_FILE       cache file for /v1/models (default ~/.claude/leadv2-state/freepool-models.json)
#   FREEPOOL_MODELS_CACHE_TTL_S      cache TTL seconds (default 60)
#   FREEPOOL_MODELS_FETCH_TIMEOUT_S  timeout for GET /v1/models (default 5; a cold proxy
#                                    process can be slow to answer its first request)
#   FREEPOOL_MODEL_PROBE_TIMEOUT_S   timeout for the liveness probe (default 30;
#                                    measured 2026-08-27 -- gemini routes answered in
#                                    18-26s and some NIM/mistral routes in 50-117s, so
#                                    the old 8s default silently excluded working models.
#                                    Latency-sensitive callers can still lower it.)
#   FREEPOOL_AUTH_TOKEN              bearer token for the probe (required for a real probe;
#                                    if unset, the probe call is still attempted with no
#                                    auth header — a proxy that requires auth will simply
#                                    fail the probe and the rank advances, same as any
#                                    other probe failure)
#   FREEPOOL_ROLE                    optional role id (e.g. implement/bulk/review/read).
#                                    When set and config/freepool-arm.yaml has a matching
#                                    non-empty `role_rank.<role>` list, that list is used
#                                    instead of the flat `model_rank`. Unset defaults to
#                                    `implement`; a role with no matching/empty list falls
#                                    back silently to `model_rank` -- never an error.
set -euo pipefail

_SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

readonly FREEPOOL_BASE_URL="${FREEPOOL_PROXY_URL:-http://127.0.0.1:8317}"
readonly ARM_CONFIG="${FREEPOOL_ARM_CONFIG:-$(cd "${_SELF_DIR}/../.." && pwd)/config/freepool-arm.yaml}"
readonly CACHE_DIR_DEFAULT="${HOME}/.claude/leadv2-state"
readonly MODELS_CACHE_FILE="${FREEPOOL_MODELS_CACHE_FILE:-${CACHE_DIR_DEFAULT}/freepool-models.json}"
readonly MODELS_CACHE_TTL_S="${FREEPOOL_MODELS_CACHE_TTL_S:-60}"
readonly FETCH_TIMEOUT_S="${FREEPOOL_MODELS_FETCH_TIMEOUT_S:-5}"
readonly PROBE_TIMEOUT_S="${FREEPOOL_MODEL_PROBE_TIMEOUT_S:-30}"

log_err() { echo "[freepool-model-select] $*" >&2; }

# _fetch_models -> writes a fresh /v1/models JSON body to MODELS_CACHE_FILE
# when the cache is missing or stale; leaves it untouched otherwise. Never
# throws: a fetch failure just leaves the cache as-is (possibly absent),
# and the caller treats "no cache file" as "no live models".
_fetch_models() {
  mkdir -p "$(dirname "${MODELS_CACHE_FILE}")"
  if [[ -f "${MODELS_CACHE_FILE}" ]]; then
    local mtime now
    mtime="$(stat -f '%m' "${MODELS_CACHE_FILE}" 2>/dev/null || stat -c '%Y' "${MODELS_CACHE_FILE}" 2>/dev/null || echo 0)"
    now="$(date +%s)"
    if [[ "${mtime}" =~ ^[0-9]+$ ]] && (( now - mtime < MODELS_CACHE_TTL_S )); then
      return 0
    fi
  fi
  local tmp
  tmp="$(mktemp "${MODELS_CACHE_FILE}.XXXXXX" 2>/dev/null || echo "${MODELS_CACHE_FILE}.tmp")"
  if curl -s --max-time "${FETCH_TIMEOUT_S}" "${FREEPOOL_BASE_URL}/v1/models" -o "${tmp}" 2>/dev/null \
     && [[ -s "${tmp}" ]]; then
    mv -f "${tmp}" "${MODELS_CACHE_FILE}"
  else
    rm -f "${tmp}" 2>/dev/null || true
  fi
}

# _rank_candidates -> one route id per line, in rank order, for every rank
# whose prefix matches at least one live route id. Empty output (not an
# error) when the config or the models cache is missing/unparseable.
#
# Role-aware (FREEPOOL_ROLE): the unset role defaults to `implement`. If the
# resulting `role_rank.<role>` exists in the yaml and is a non-empty list,
# that list is used instead of the flat `model_rank`. An unknown role or empty
# role list falls back silently to `model_rank` -- resolution never errors on
# a role miss.
_rank_candidates() {
  python3 - "${ARM_CONFIG}" "${MODELS_CACHE_FILE}" "${FREEPOOL_ROLE:-}" <<'PYEOF' 2>/dev/null || true
import json, sys
try:
    import yaml
except ImportError:
    sys.exit(0)

config_path, models_path, role = sys.argv[1], sys.argv[2], sys.argv[3]
role = role or "implement"

try:
    with open(config_path) as f:
        cfg = yaml.safe_load(f) or {}
except Exception:
    sys.exit(0)

ranks = None
role_ranks = cfg.get("role_rank") or {}
if isinstance(role_ranks, dict):
    candidate = role_ranks.get(role)
    if isinstance(candidate, list) and candidate:
        ranks = candidate
if ranks is None:
    ranks = cfg.get("model_rank") or []
prefixes = [r.get("prefix", "") for r in ranks if isinstance(r, dict) and r.get("prefix")]
if not prefixes:
    sys.exit(0)

try:
    with open(models_path) as f:
        models = json.load(f)
except Exception:
    sys.exit(0)

# OpenAI-style {"data": [{"id": "..."}]} or a bare list of ids/objects.
if isinstance(models, dict):
    entries = models.get("data") or []
elif isinstance(models, list):
    entries = models
else:
    entries = []

ids = []
for e in entries:
    if isinstance(e, str):
        ids.append(e)
    elif isinstance(e, dict) and isinstance(e.get("id"), str):
        ids.append(e["id"])

# FREEPOOL-MODEL-SELECTOR-01 fix-round (P1a): freepool-arm.yaml's prefixes
# have drifted between the bare "<provider>/<model>" shape and the proxy's
# actual "anthropic/<provider>/<model>" route-id namespace before (a mismatch
# means every rank silently never matches -- lying-green). Try each prefix
# both as given and with the "anthropic/" alias segment added/stripped, so a
# config edit that gets the alias wrong in either direction still matches.
ANTHROPIC_ALIAS = "anthropic/"

def _prefix_variants(prefix):
    variants = [prefix]
    if prefix.startswith(ANTHROPIC_ALIAS):
        variants.append(prefix[len(ANTHROPIC_ALIAS):])
    else:
        variants.append(ANTHROPIC_ALIAS + prefix)
    return variants

for prefix in prefixes:
    variants = _prefix_variants(prefix)
    for route_id in ids:
        if any(route_id.startswith(v) for v in variants):
            print(route_id)
            break
PYEOF
}

# _route_id_is_safe <route_id> -> 0 if the id is printable ASCII with no
# leading/trailing whitespace, 1 otherwise. A live-fetched /v1/models
# response is data from an external proxy: a route id smuggling a newline
# or other control char could forge extra journal.jsonl/progress.log lines
# once interpolated into log_err below or freepool-coder.sh's log_info
# (P2a, FREEPOOL-MODEL-SELECTOR-01 fix-round). python3 is already a hard
# dependency of this script (see _rank_candidates).
_route_id_is_safe() {
  python3 -c '
import sys
s = sys.argv[1]
sys.exit(0 if s and s == s.strip() and all(32 <= ord(c) < 127 for c in s) else 1)
' "$1" 2>/dev/null
}

# _json_str <value> -> the value as a JSON-quoted string, for safely
# embedding untrusted text (a route id) inside a log line without it being
# able to inject literal newlines/quotes into the surrounding log format.
_json_str() {
  python3 -c 'import json, sys; print(json.dumps(sys.argv[1]))' "$1" 2>/dev/null || printf '"%s"' "$1"
}

# _probe <route_id> -> 0 if the liveness POST succeeds AND the response body
# carries non-whitespace text content, 1 otherwise.
#
# 2026-08-30 (FREEPOOL-MAKE-IT-EARN-ITS-KEEP-01 round 2): an HTTP 200 with a
# blank/whitespace-only content[].text is a live trap, not a live model --
# measured against the real proxy on 2026-08-30, ranks 1-3 of the previous
# default list (deepseek-v4-pro, kimi-k3, gemini-3.7-flash) AND groq's
# gpt-oss-120b all returned exactly this shape at max_tokens:1. Root cause is
# NOT dead credentials (every one of those routes answers 200, never
# 401/403) -- it is that the proxy leaves reasoning computation to the
# provider default (free_claude_code core/reasoning.py
# ReasoningPolicy.provider_default()), so a reasoning-capable model spends
# its entire tiny max_tokens budget on invisible reasoning tokens before any
# visible text is emitted, and the response comes back well-formed but
# empty. A status-code-only probe cannot see this. Bumping the probe budget
# to 64 tokens (measured minimum for gpt-oss-120b to clear its reasoning
# preamble and answer "OK" in 2.2s; 16/32 both still came back blank) fixes
# it for fast non-blocked routes while a genuinely dead/hung route still
# times out or returns blank at 64 either way, so it still gets rejected.
_probe() {
  local route_id="$1"
  local auth_header=()
  if [[ -n "${FREEPOOL_AUTH_TOKEN:-}" ]]; then
    auth_header=(-H "Authorization: Bearer ${FREEPOOL_AUTH_TOKEN}")
  fi
  local probe_max_tokens="${FREEPOOL_MODEL_PROBE_MAX_TOKENS:-64}"
  local tmp_body
  tmp_body="$(mktemp 2>/dev/null || echo "/tmp/freepool-probe-body.$$")"
  local code
  code="$(curl -s -o "${tmp_body}" -w '%{http_code}' --max-time "${PROBE_TIMEOUT_S}" \
    -X POST "${FREEPOOL_BASE_URL}/v1/messages" \
    -H "Content-Type: application/json" \
    "${auth_header[@]}" \
    -d "$(printf '{"model":"%s","max_tokens":%s,"messages":[{"role":"user","content":"Reply with exactly the word OK and nothing else."}]}' "${route_id}" "${probe_max_tokens}")" \
    2>/dev/null || echo "000")"

  if [[ ! "${code}" =~ ^2[0-9][0-9]$ ]]; then
    rm -f "${tmp_body}" 2>/dev/null || true
    return 1
  fi

  local has_content
  has_content="$(python3 -c '
import json, sys
try:
    with open(sys.argv[1]) as f:
        body = json.load(f)
    parts = [b.get("text", "") for b in (body.get("content") or []) if isinstance(b, dict) and b.get("type") == "text"]
    text = "".join(parts)
    print("1" if text.strip() else "0")
except Exception:
    print("0")
' "${tmp_body}" 2>/dev/null || echo "0")"
  rm -f "${tmp_body}" 2>/dev/null || true
  [[ "${has_content}" == "1" ]]
}

main() {
  [[ -f "${ARM_CONFIG}" ]] || { log_err "no config at ${ARM_CONFIG}"; exit 1; }

  _fetch_models
  [[ -f "${MODELS_CACHE_FILE}" ]] || { log_err "no live models (fetch failed, no cache)"; exit 1; }

  local candidates
  candidates="$(_rank_candidates)"
  if [[ -z "${candidates}" ]]; then
    log_err "no ranked candidate matched a live route"
    exit 1
  fi

  local alt_count
  alt_count="$(printf '%s\n' "${candidates}" | grep -c . || true)"

  local route_id start_ms probe_ms
  while IFS= read -r route_id; do
    [[ -n "${route_id}" ]] || continue
    if ! _route_id_is_safe "${route_id}"; then
      log_err "rejected candidate route id (non-printable/newline/control chars), advancing rank"
      continue
    fi
    start_ms="$(( $(date +%s%N) / 1000000 ))"
    if _probe "${route_id}"; then
      probe_ms="$(( $(date +%s%N) / 1000000 - start_ms ))"
      log_err "chosen=$(_json_str "${route_id}") alternatives=${alt_count} probe_ms=${probe_ms}"
      printf '%s\n' "${route_id}"
      exit 0
    fi
    log_err "probe failed for $(_json_str "${route_id}"), advancing rank"
  done <<< "${candidates}"

  log_err "all ranked candidates failed their liveness probe"
  exit 1
}

main "$@"
