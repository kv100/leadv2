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
#
# FREEPOOL-DEAD-ARM-LOOKS-LIKE-A-BUSY-ARM-01 (2026-09-04): "proxy dead" and
# "quota exhausted" used to be the SAME observable (refusal rc -> the arbiter
# rendered both as util_freepool=100), so a dead arm read as a busy one for a
# full day. Every arm_down path now (a) names the observed http code loudly,
# (b) says explicitly that this is NOT quota exhaustion, and (c) the new
# `liveness` subcommand reports the full proxy state (health + /v1/models)
# with a named reason per refusal.
set -euo pipefail

leadv2_freepool_gate_script_dir() {
  # Resolve the canonical location when this library is installed per-file.
  local source="${BASH_SOURCE[0]}" link dir
  while [[ -h "$source" ]]; do
    dir="$(cd -P "$(dirname "$source")" && pwd)"
    link="$(readlink "$source")"
    [[ "$link" == /* ]] || link="$dir/$link"
    source="$link"
  done
  cd -P "$(dirname "$source")" && pwd
}

# TESTS-POLLUTE-REAL-JOURNAL-01 §0/§6: runtime test-context detection (same
# lib leadv2-event.sh uses). Guarded source so a per-file install that did not
# carry the lib along degrades to the old behaviour instead of breaking the
# record path; see lib/leadv2-test-context.sh for why record must refuse.
if [[ -f "$(leadv2_freepool_gate_script_dir)/leadv2-test-context.sh" ]]; then
  # shellcheck source=leadv2-test-context.sh
  source "$(leadv2_freepool_gate_script_dir)/leadv2-test-context.sh"
else
  lv2_test_context() { return 1; }
fi

readonly FREEPOOL_HEALTH_URL="${FREEPOOL_PROXY_URL:-http://127.0.0.1:8317}/health"
# T19 fix-round-2 (B-H1): the pin file freepool-install.sh writes
# (config/freepool-arm.yaml) previously had no reader anywhere -- a checkout that
# drifted from the reviewed/pinned commit (upstream force-push, a manual `git pull`
# in FREEPOOL_INSTALL_DIR, anything) was never detected. Compared against a live
# `git -C $FREEPOOL_INSTALL_DIR rev-parse HEAD` on every gate check now.
readonly FREEPOOL_PIN_FILE="${LEADV2_FREEPOOL_PIN_FILE:-$(cd "$(leadv2_freepool_gate_script_dir)/../.." && pwd)/config/freepool-arm.yaml}"
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
# silently pass (that's exactly the bug: no fresh evidence either way). The
# check_liveness probe already run earlier in the same "check" invocation
# substitutes for evidence instead of a blind pass — see main()'s rc==4
# branch (P1b, FREEPOOL-MODEL-SELECTOR-01 fix-round: this used to be a
# SECOND, separately-timed live probe, doubling worst-case latency on a
# dead proxy for no new evidence).

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

# check_liveness -> 0 healthy, 1 unreachable/non-2xx. The observed HTTP code
# is left in FREEPOOL_LAST_HEALTH_CODE so callers can NAME the failure mode:
# 000 = no listener at all (the proxy process is gone — dead arm), anything
# else non-2xx = the port answers but the proxy is unhealthy.
check_liveness() {
  local code
  # FREEPOOL-DEAD-ARM-LOOKS-LIKE-A-BUSY-ARM-01: on connection-refused curl
  # exits non-zero AND still writes %{http_code} (=000) — a bare
  # `|| echo 000` appends a second 000 ("000000"). Normalize instead: take
  # whatever -w printed, coerce anything that is not a 3-digit code to 000.
  code="$(curl -s -o /dev/null -w '%{http_code}' --max-time "${FREEPOOL_HEALTH_TIMEOUT_S}" \
    "${FREEPOOL_HEALTH_URL}" 2>/dev/null || true)"
  [[ "${code}" =~ ^[0-9][0-9][0-9]$ ]] || code="000"
  FREEPOOL_LAST_HEALTH_CODE="${code}"
  [[ "${code}" =~ ^2[0-9][0-9]$ ]]
}

readonly FREEPOOL_MODELS_URL="${FREEPOOL_PROXY_URL:-http://127.0.0.1:8317}/v1/models"

# freepool_model_count -> model count (>=1) on stdout, or empty when the
# endpoint is unreachable, unparseable, or serves an empty roster. Empty (not
# 0) so the liveness report can distinguish "asked, got nothing servable".
freepool_model_count() {
  curl -s --max-time "${FREEPOOL_HEALTH_TIMEOUT_S}" "${FREEPOOL_MODELS_URL}" 2>/dev/null \
    | python3 -c 'import json,sys
try:
    d = json.load(sys.stdin)
    n = len(d.get("data") or [])
except Exception:
    sys.exit(0)
print(n) if n > 0 else None' || true
}

# freepool_liveness_report — FREEPOOL-DEAD-ARM-LOOKS-LIKE-A-BUSY-ARM-01.
# Full proxy liveness as ONE named line on stdout:
#   ok          [freepool-liveness] ok health=200 models=<N> url=...
#   dead        [freepool-liveness] arm_down health=000 reason=unreachable url=...
#   dead        [freepool-liveness] arm_down health=503 reason=health_non_2xx url=...
#   sick        [freepool-liveness] gate_broken health=200 reason=models_empty models_url=...
# Refusals also emit the standard LEADV2_DISPATCH_REFUSED marker on stderr, so
# a dead proxy can never masquerade as a busy/exhausted one: the reason is a
# WORD, never a bare number. `check` keeps its own contract; this is the
# observable the liveness suite grades and a lead can run by hand.
freepool_liveness_report() {
  local models
  if ! check_liveness; then
    if [[ "${FREEPOOL_LAST_HEALTH_CODE:-000}" == "000" ]]; then
      printf '[freepool-liveness] arm_down health=000 reason=unreachable url=%s\n' "${FREEPOOL_HEALTH_URL}"
    else
      printf '[freepool-liveness] arm_down health=%s reason=health_non_2xx url=%s\n' \
        "${FREEPOOL_LAST_HEALTH_CODE:-000}" "${FREEPOOL_HEALTH_URL}"
    fi
    printf 'LEADV2_DISPATCH_REFUSED: arm_down\n' >&2
    return 1
  fi
  models="$(freepool_model_count)"
  if [[ -z "${models}" ]]; then
    printf '[freepool-liveness] gate_broken health=%s reason=models_empty models_url=%s\n' \
      "${FREEPOOL_LAST_HEALTH_CODE:-200}" "${FREEPOOL_MODELS_URL}"
    printf 'LEADV2_DISPATCH_REFUSED: gate_broken\n' >&2
    return 1
  fi
  printf '[freepool-liveness] ok health=%s models=%s url=%s\n' \
    "${FREEPOOL_LAST_HEALTH_CODE:-200}" "${models}" "${FREEPOOL_HEALTH_URL}"
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
  # TESTS-POLLUTE-REAL-JOURNAL-01 §0/§6: the WRITER refuses a test-context
  # record into the REAL arm-state window. Measured: one run of
  # test-model-select-telemetry.sh injected 9 outcomes into
  # ~/.claude/leadv2-state/freepool-arm-state.json, 5 of them instant
  # (latency_s=0.0) ok=false records — synthetic failures that trip the
  # rolling-window breaker and circuit-break freepool out of production
  # routing. A redirected LEADV2_FREEPOOL_STATE_DIR (fixture dir) stays fully
  # supported; the dispatcher's own call sites wrap this in `|| true`, so the
  # non-zero return never breaks dispatch control flow.
  if lv2_test_context && [[ -z "${LEADV2_FREEPOOL_STATE_DIR:-}" ]]; then
    lv2_refuse_test_write "leadv2-freepool-gate.sh" "${FREEPOOL_STATE_FILE}" "LEADV2_FREEPOOL_STATE_DIR"
    return 3
  fi
  # WAVE0-LIB-SWALLOWS-ITS-OWN-FAILURE-01 (F-2): validate in bash before the
  # heredoc — float("nan") parses and "1,5" raises inside python, and the old
  # `2>/dev/null || true` turned either into rc 0 with the state file
  # untouched: the rolling window silently lost a record. rc 2 + a counted
  # line now; the state file is left exactly as it was.
  if ! [[ "${latency_s}" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
    printf '[freepool-record] wrote=0 reason=bad_latency value=%s\n' "${latency_s}" >&2
    return 2
  fi
  # _ensure_state_file under `main record` runs with set -e live: an unwritable
  # state dir used to die here with bash's raw redirect error (unnamed rc 1).
  # Part of the same F-2 contract: name it and return 2.
  _ensure_state_file \
    || { printf '[freepool-record] wrote=0 reason=state_write_error path=%s\n' "${FREEPOOL_STATE_FILE}" >&2; return 2; }
  local _fr_out="" _fr_rc=0
  _fr_out="$(python3 - "${FREEPOOL_STATE_FILE}" "${ok}" "${latency_s}" <<'PYEOF'
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
print("%d" % len(data["results"]))
PYEOF
)" || _fr_rc=$?
  if [[ "${_fr_rc}" -ne 0 ]]; then
    printf '[freepool-record] wrote=0 reason=state_write_error path=%s\n' "${FREEPOOL_STATE_FILE}" >&2
    return 2
  fi
  printf '[freepool-record] wrote=1 results=%s path=%s\n' "${_fr_out}" "${FREEPOOL_STATE_FILE}"
  return 0
}

main() {
  local cmd="${1:-check}"
  case "${cmd}" in
    record)
      shift
      record_result "${1:-0}" "${2:-0}"
      # record_result returns 3 on the test-context refusal — propagate it
      # (acceptance: the refusal is non-zero), never mask it as success.
      exit $?
      ;;
    check|"")
      [[ "${FREEPOOL_SKIP_GATE:-0}" == "1" ]] && exit 0
      if ! check_liveness; then
        # FREEPOOL-DEAD-ARM-LOOKS-LIKE-A-BUSY-ARM-01: say DEAD loudly. Before
        # this, arm_down reached the arbiter as a bare rc that rendered as
        # util_freepool=100 — indistinguishable from quota exhaustion — and
        # the only human-visible trace lived in this script's own stderr,
        # which the arbiter discarded. NOT auto-restarting the proxy here:
        # observability is this lane's scope (founder decision 2026-09-04).
        log_err "ARM DOWN: proxy unreachable at ${FREEPOOL_HEALTH_URL} (http_code=${FREEPOOL_LAST_HEALTH_CODE:-000}) — NOT quota exhaustion; freepool stays dead until the proxy is restarted (plugins/leadv2/scripts/freepool-proxy.sh start)"
        refuse "arm_down"
      fi
      if ! check_pin_drift; then
        refuse "pin_drift"
      fi
      local breach rc
      rc=0
      breach="$(check_rolling_window)" || rc=$?
      if (( rc == 4 )); then
        # FREEPOOL-MODEL-SELECTOR-01 fix-round (P1b): check_liveness above
        # already proved the arm reachable in THIS SAME invocation --
        # main() refuses via "arm_down" before reaching here otherwise -- so
        # a second live probe of the identical /health endpoint added zero
        # new evidence while doubling worst-case latency (5s + 3s = up to
        # 8s) on a slow-but-alive proxy. Reuse that result: one probe path,
        # one timeout (FREEPOOL_HEALTH_TIMEOUT_S).
        log_err "rolling window empty after ${FREEPOOL_WINDOW_TTL_S}s TTL filtering — liveness already confirmed earlier in this check, proceeding"
      elif (( rc != 0 )); then
        log_err "rolling window breach: ${breach}"
        refuse "gate_broken"
      fi
      exit 0
      ;;
    liveness)
      # FREEPOOL-DEAD-ARM-LOOKS-LIKE-A-BUSY-ARM-01: the observable liveness
      # report (health + models, named reasons) — see freepool_liveness_report.
      [[ "${FREEPOOL_SKIP_GATE:-0}" == "1" ]] && exit 0
      if freepool_liveness_report; then
        exit 0
      fi
      exit 1
      ;;
    *)
      echo "usage: leadv2-freepool-gate.sh [check|record <ok> <latency_s>|liveness]" >&2
      exit 64
      ;;
  esac
}

main "$@"
