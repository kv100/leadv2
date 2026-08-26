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
# T19 fix-round-2 (B-H1): the pin file freepool-install.sh writes
# (config/freepool-arm.yaml) previously had no reader anywhere -- a checkout that
# drifted from the reviewed/pinned commit (upstream force-push, a manual `git pull`
# in FREEPOOL_INSTALL_DIR, anything) was never detected. Compared against a live
# `git -C $FREEPOOL_INSTALL_DIR rev-parse HEAD` on every gate check now.
readonly FREEPOOL_PIN_FILE="${LEADV2_FREEPOOL_PIN_FILE:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/config/freepool-arm.yaml}"
readonly FREEPOOL_INSTALL_DIR="${FREEPOOL_INSTALL_DIR:-${HOME}/tools/free-claude-code}"
readonly FREEPOOL_STATE_DIR="${LEADV2_FREEPOOL_STATE_DIR:-${HOME}/.claude/leadv2-state}"
readonly FREEPOOL_STATE_FILE="${FREEPOOL_STATE_DIR}/freepool-arm-state.json"
readonly FREEPOOL_WINDOW_N="${FREEPOOL_GATE_WINDOW_N:-20}"
readonly FREEPOOL_ERROR_RATE_MAX="${FREEPOOL_GATE_ERROR_RATE_MAX:-0.30}"
readonly FREEPOOL_LATENCY_P95_MAX_S="${FREEPOOL_GATE_LATENCY_P95_MAX_S:-60}"
readonly FREEPOOL_HEALTH_TIMEOUT_S="${FREEPOOL_GATE_HEALTH_TIMEOUT_S:-5}"
# FREEPOOL-GATE-STALE-WINDOW-01: without a TTL, a burst of old failures sits
# in the rolling window forever once traffic goes idle (nothing ever pushes
# them out of the last-N slice), pinning error_rate=1.00 permanently even
# after the arm recovers. Entries older than this are dropped from the
# window AT READ TIME (record_result still appends raw, unfiltered — the TTL
# is a read-side view, not a write-side prune, so no state is lost if the
# window widens later).
readonly FREEPOOL_WINDOW_TTL_S="${FREEPOOL_GATE_WINDOW_TTL_S:-1800}"
# When TTL-filtering leaves the window empty, a stale-only window must not
# silently pass (that's exactly the bug: no fresh evidence either way). One
# live health probe substitutes for evidence instead of a blind pass.
readonly FREEPOOL_STALE_PROBE_TIMEOUT_S="${FREEPOOL_GATE_STALE_PROBE_TIMEOUT_S:-3}"

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

# check_pin_drift -> 0 no drift (or nothing to compare yet), 1 drift detected.
# Fail-open when the pin file or the install checkout doesn't exist yet --
# an uninstalled arm has nothing to drift from, and check_liveness already
# refuses it as arm_down on its own. Only a REAL mismatch between a present
# pin file and a present checkout is drift.
check_pin_drift() {
  [[ -f "${FREEPOOL_PIN_FILE}" ]] || return 0
  [[ -d "${FREEPOOL_INSTALL_DIR}/.git" ]] || return 0
  local pinned live
  pinned="$(sed -n 's/^pinned_commit: *//p' "${FREEPOOL_PIN_FILE}" | head -n1)"
  [[ -n "${pinned}" ]] || return 0
  live="$(git -C "${FREEPOOL_INSTALL_DIR}" rev-parse HEAD 2>/dev/null || echo "")"
  [[ -n "${live}" ]] || return 0
  [[ "${pinned}" == "${live}" ]] || return 1
  return 0
}

# check_liveness -> 0 healthy, 1 unreachable/non-2xx.
check_liveness() {
  local code
  code="$(curl -s -o /dev/null -w '%{http_code}' --max-time "${FREEPOOL_HEALTH_TIMEOUT_S}" \
    "${FREEPOOL_HEALTH_URL}" 2>/dev/null || echo "000")"
  [[ "${code}" =~ ^2[0-9][0-9]$ ]]
}

# check_liveness_now -> like check_liveness but with the shorter stale-window
# probe timeout, used only from the empty-after-TTL path below (kept
# separate from check_liveness so the two call sites can be tuned/logged
# independently without one silently changing the other's behavior).
check_liveness_now() {
  local code
  code="$(curl -s -o /dev/null -w '%{http_code}' --max-time "${FREEPOOL_STALE_PROBE_TIMEOUT_S}" \
    "${FREEPOOL_HEALTH_URL}" 2>/dev/null || echo "000")"
  [[ "${code}" =~ ^2[0-9][0-9]$ ]]
}

# check_rolling_window -> 0 within thresholds, 1 breached, 4 window empty
# after TTL filtering (caller must live-probe). Fail-open (prints nothing,
# returns 0) on any parse error — a broken reader must never itself become a
# reason to refuse.
check_rolling_window() {
  _ensure_state_file
  python3 - "${FREEPOOL_STATE_FILE}" "${FREEPOOL_WINDOW_N}" \
    "${FREEPOOL_ERROR_RATE_MAX}" "${FREEPOOL_LATENCY_P95_MAX_S}" "${FREEPOOL_WINDOW_TTL_S}" <<'PYEOF' 2>/dev/null
import json, sys, time

path, window_n, err_max, lat_max, ttl_s = (
    sys.argv[1], int(sys.argv[2]), float(sys.argv[3]), float(sys.argv[4]), float(sys.argv[5])
)
try:
    with open(path) as f:
        data = json.load(f)
    all_results = data.get("results", [])
except Exception:
    sys.exit(0)  # fail-open: no/garbled state == no evidence of breach

try:
    now = time.time()
    # Entries with no ts (older schema, pre-TTL) are treated as fresh rather
    # than dropped — an unknown age must not itself manufacture a breach or
    # a probe.
    fresh = [r for r in all_results if (now - r.get("ts", now)) <= ttl_s]
    results = fresh[-window_n:]

    if not results:
        # Distinguish "never had any data" (still nothing to act on,
        # fail-open) from "had data but all of it aged out" (exactly the
        # stale-window bug — signal the caller to live-probe instead of
        # passing blind).
        sys.exit(4 if all_results else 0)

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
except SystemExit:
    raise
except Exception:
    # A crash in the computation itself is not evidence of a breach —
    # fail-open, same contract as the outer json-load try/except.
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
      if ! check_pin_drift; then
        refuse "pin_drift"
      fi
      local breach rc
      rc=0
      breach="$(check_rolling_window)" || rc=$?
      if (( rc == 4 )); then
        log_err "rolling window empty after ${FREEPOOL_WINDOW_TTL_S}s TTL filtering — live-probing instead of passing blind"
        if ! check_liveness_now; then
          refuse "arm_down"
        fi
      elif (( rc != 0 )); then
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
