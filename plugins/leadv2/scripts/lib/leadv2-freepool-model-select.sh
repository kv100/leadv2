#!/usr/bin/env bash
# leadv2-freepool-model-select.sh — FREEPOOL-MODEL-SELECTOR-01.
#
# Picks the best live model for one freepool worker spawn instead of pinning
# a single static route id. Reads plugins/leadv2/config/freepool-arm.yaml's
# `model_rank` (ordered list of route-id PREFIXES, most-preferred first),
# fetches the proxy's live GET /v1/models, and for the first rank whose
# prefix has a live route, runs a cheap 1-token liveness probe. First
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
#   FREEPOOL_MODELS_FETCH_TIMEOUT_S  timeout for GET /v1/models (default 2)
#   FREEPOOL_MODEL_PROBE_TIMEOUT_S   timeout for the 1-token liveness probe (default 8)
#   FREEPOOL_AUTH_TOKEN              bearer token for the probe (required for a real probe;
#                                    if unset, the probe call is still attempted with no
#                                    auth header — a proxy that requires auth will simply
#                                    fail the probe and the rank advances, same as any
#                                    other probe failure)
set -euo pipefail

_SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

readonly FREEPOOL_BASE_URL="${FREEPOOL_PROXY_URL:-http://127.0.0.1:8317}"
readonly ARM_CONFIG="${FREEPOOL_ARM_CONFIG:-$(cd "${_SELF_DIR}/../.." && pwd)/config/freepool-arm.yaml}"
readonly CACHE_DIR_DEFAULT="${HOME}/.claude/leadv2-state"
readonly MODELS_CACHE_FILE="${FREEPOOL_MODELS_CACHE_FILE:-${CACHE_DIR_DEFAULT}/freepool-models.json}"
readonly MODELS_CACHE_TTL_S="${FREEPOOL_MODELS_CACHE_TTL_S:-60}"
readonly FETCH_TIMEOUT_S="${FREEPOOL_MODELS_FETCH_TIMEOUT_S:-2}"
readonly PROBE_TIMEOUT_S="${FREEPOOL_MODEL_PROBE_TIMEOUT_S:-8}"

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

# _rank_candidates -> one route id per line, in model_rank order, for every
# rank whose prefix matches at least one live route id. Empty output (not an
# error) when the config or the models cache is missing/unparseable.
_rank_candidates() {
  python3 - "${ARM_CONFIG}" "${MODELS_CACHE_FILE}" <<'PYEOF' 2>/dev/null || true
import json, sys
try:
    import yaml
except ImportError:
    sys.exit(0)

config_path, models_path = sys.argv[1], sys.argv[2]

try:
    with open(config_path) as f:
        cfg = yaml.safe_load(f) or {}
except Exception:
    sys.exit(0)

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

for prefix in prefixes:
    for route_id in ids:
        if route_id.startswith(prefix):
            print(route_id)
            break
PYEOF
}

# _probe <route_id> -> 0 if the 1-token liveness POST succeeds, 1 otherwise.
_probe() {
  local route_id="$1"
  local auth_header=()
  if [[ -n "${FREEPOOL_AUTH_TOKEN:-}" ]]; then
    auth_header=(-H "Authorization: Bearer ${FREEPOOL_AUTH_TOKEN}")
  fi
  local code
  code="$(curl -s -o /dev/null -w '%{http_code}' --max-time "${PROBE_TIMEOUT_S}" \
    -X POST "${FREEPOOL_BASE_URL}/v1/messages" \
    -H "Content-Type: application/json" \
    "${auth_header[@]}" \
    -d "$(printf '{"model":"%s","max_tokens":1,"messages":[{"role":"user","content":"hi"}]}' "${route_id}")" \
    2>/dev/null || echo "000")"
  [[ "${code}" =~ ^2[0-9][0-9]$ ]]
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
    start_ms="$(( $(date +%s%N) / 1000000 ))"
    if _probe "${route_id}"; then
      probe_ms="$(( $(date +%s%N) / 1000000 - start_ms ))"
      log_err "chosen=${route_id} alternatives=${alt_count} probe_ms=${probe_ms}"
      printf '%s\n' "${route_id}"
      exit 0
    fi
    log_err "probe failed for ${route_id}, advancing rank"
  done <<< "${candidates}"

  log_err "all ranked candidates failed their liveness probe"
  exit 1
}

main "$@"
