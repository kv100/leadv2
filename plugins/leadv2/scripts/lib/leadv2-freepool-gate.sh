#!/usr/bin/env bash
# leadv2-freepool-gate.sh — health/quota gate for the freepool arm (T19).
#
# Two checks, either can refuse the launch:
#   1. Liveness: GET the proxy's health endpoint. No response / non-2xx = arm_down.
#   2. Rolling window: error-rate/latency over the last N requests, tracked in
#      the arm-state file this gate itself appends to (record_result below).
#      Breach of either threshold = gate_broken.
#
# Contract (same shape as leadv2-glm-quota-gate.sh / the admission-refusal
# marker other arms use): on refusal, print
#   LEADV2_DISPATCH_REFUSED: <arm_down|gate_broken>
# to stderr and exit non-zero. Fail-open on any inspection error that is NOT
# itself evidence of a broken arm (e.g. jq missing) — never block dispatch on
# our own bug. FREEPOOL_SKIP_GATE=1 bypasses entirely (parity with
# FREEPOOL_SKIP_GATE in freepool-coder.sh / GLM_SKIP_QUOTA_GATE).
set -euo pipefail

readonly FREEPOOL_HEALTH_URL="${FREEPOOL_PROXY_URL:-http://127.0.0.1:8317}/health"
readonly FREEPOOL_STATE_DIR="${LEADV2_FREEPOOL_STATE_DIR:-${HOME}/.claude/leadv2-state}"
readonly FREEPOOL_STATE_FILE="${FREEPOOL_STATE_DIR}/freepool-arm-state.json"
readonly FREEPOOL_WINDOW_N="${FREEPOOL_GATE_WINDOW_N:-20}"
readonly FREEPOOL_ERROR_RATE_MAX="${FREEPOOL_GATE_ERROR_RATE_MAX:-0.30}"
readonly FREEPOOL_LATENCY_P95_MAX_S="${FREEPOOL_GATE_LATENCY_P95_MAX_S:-60}"
readonly FREEPOOL_HEALTH_TIMEOUT_S="${FREEPOOL_GATE_HEALTH_TIMEOUT_S:-5}"

log_err() { echo "[freepool-gate] $*" >&2; }

refuse() {
  local reason="$1"
  log_err "refused: ${reason}"
  printf 'LEADV2_DISPATCH_REFUSED: %s\n' "${reason}" >&2
  exit 1
}

_ensure_state_file() {
  mkdir -p "${FREEPOOL_STATE_DIR}"
  [[ -f "${FREEPOOL_STATE_FILE}" ]] || printf '{"results": []}\n' > "${FREEPOOL_STATE_FILE}"
}

# check_liveness -> 0 healthy, 1 unreachable/non-2xx.
check_liveness() {
  local code
  code="$(curl -s -o /dev/null -w '%{http_code}' --max-time "${FREEPOOL_HEALTH_TIMEOUT_S}" \
    "${FREEPOOL_HEALTH_URL}" 2>/dev/null || echo "000")"
  [[ "${code}" =~ ^2[0-9][0-9]$ ]]
}

# check_rolling_window -> 0 within thresholds, 1 breached. Fail-open (prints
# nothing, returns 0) on any parse error — a broken reader must never itself
# become a reason to refuse.
check_rolling_window() {
  _ensure_state_file
  python3 - "${FREEPOOL_STATE_FILE}" "${FREEPOOL_WINDOW_N}" \
    "${FREEPOOL_ERROR_RATE_MAX}" "${FREEPOOL_LATENCY_P95_MAX_S}" <<'PYEOF' 2>/dev/null || exit 0
import json, sys

path, window_n, err_max, lat_max = sys.argv[1], int(sys.argv[2]), float(sys.argv[3]), float(sys.argv[4])
try:
    with open(path) as f:
        data = json.load(f)
    results = data.get("results", [])[-window_n:]
except Exception:
    sys.exit(0)  # fail-open: no/garbled state == no evidence of breach

if not results:
    sys.exit(0)

errors = sum(1 for r in results if not r.get("ok", True))
error_rate = errors / len(results)
latencies = sorted(r.get("latency_s", 0) for r in results)
p95_idx = max(0, int(len(latencies) * 0.95) - 1)
p95 = latencies[p95_idx] if latencies else 0

if error_rate > err_max:
    print(f"error_rate={error_rate:.2f} > max={err_max}")
    sys.exit(2)
if p95 > lat_max:
    print(f"latency_p95={p95:.1f}s > max={lat_max}s")
    sys.exit(3)
sys.exit(0)
PYEOF
}

# record_result <ok=0|1> <latency_s> — appended by the dispatcher after each
# freepool spawn attempt so the rolling window reflects real traffic, not just
# gate probes. Kept append-bounded (last 200) so the state file never grows
# unbounded.
record_result() {
  local ok="$1" latency_s="$2"
  _ensure_state_file
  python3 - "${FREEPOOL_STATE_FILE}" "${ok}" "${latency_s}" <<'PYEOF' 2>/dev/null || true
import json, sys, time

path, ok, latency_s = sys.argv[1], sys.argv[2] == "1", float(sys.argv[3])
try:
    with open(path) as f:
        data = json.load(f)
except Exception:
    data = {"results": []}
data.setdefault("results", []).append({"ok": ok, "latency_s": latency_s, "ts": time.time()})
data["results"] = data["results"][-200:]
tmp = path + ".tmp"
with open(tmp, "w") as f:
    json.dump(data, f)
import os
os.replace(tmp, path)
PYEOF
}

main() {
  local cmd="${1:-check}"
  case "${cmd}" in
    record)
      shift
      record_result "${1:-0}" "${2:-0}"
      exit 0
      ;;
    check|"")
      [[ "${FREEPOOL_SKIP_GATE:-0}" == "1" ]] && exit 0
      if ! check_liveness; then
        refuse "arm_down"
      fi
      local breach
      breach="$(check_rolling_window)" || true
      if [[ -n "${breach}" ]]; then
        log_err "rolling window breach: ${breach}"
        refuse "gate_broken"
      fi
      exit 0
      ;;
    *)
      echo "usage: leadv2-freepool-gate.sh [check|record <ok> <latency_s>]" >&2
      exit 64
      ;;
  esac
}

main "$@"
