#!/usr/bin/env bash
# leadv2-test-context.sh — TESTS-POLLUTE-REAL-JOURNAL-01 §1
# Runtime test-context detection for the writers of shared, out-of-tree state:
# the per-repo event journals under ~/.claude/cache/leadv2-events/ (written by
# leadv2-event.sh) and the freepool arm-state window under
# ~/.claude/leadv2-state/ (written by lib/leadv2-freepool-gate.sh record).
#
# The leak this closes: nothing marked a suite as a test AT THE WRITER, so any
# suite that forgot its redirect appended fixture rows to state every other
# repo on the host reads. Measured 2026-09-01: fixture worker_terminal rows
# faked a fleet-wide all-arms-unavailable outage in the shared journal
# (6283 of 7582 rows in leadv2.jsonl sit under task ids that never existed in
# the dispatch ledger), and ONE run of test-model-select-telemetry.sh injected
# 9 outcomes into the real freepool window — 5 of them instant
# (latency_s=0.0) ok=false records, the signature of a spawn that never
# reached the network — which is the shape that tripped the arm's
# rolling-window breaker (error_rate 0.53 > max 0.3) and circuit-broke
# freepool out of production routing.
#
# Detection is default-safe: it needs NO suite cooperation. A suite that
# forgets every env var is still caught.
#   1. LEADV2_TEST_CONTEXT=1 — fast path; the suite runners
#      (tests/run-all.sh, plugins/.../tests/run-core-offline.sh) export it so
#      every child inherits it, and anything that knows it is a test may set
#      it directly.
#   2. unset (the default) — ancestor process walk: if any process up the
#      tree runs */tests/test-*.sh or */tests/run-*.sh, this whole subtree is
#      a test. Catches a suite invoked directly with nothing exported.
#   3. LEADV2_TEST_CONTEXT=0 — explicit production assertion. Only the guard
#      suite sets this (to exercise the real write path under a throwaway
#      HOME); production code never sets it.
#
# lv2_test_context      -> 0 inside a test context, 1 otherwise.
# lv2_refuse_test_write <writer> <real-path> <redirect-env-var-name>
#                       -> loud stderr line, return 3. Writers call this at
#                          their append boundary and exit/return non-zero.

[[ -n "${__LEADV2_TEST_CONTEXT_SH:-}" ]] && return 0
__LEADV2_TEST_CONTEXT_SH=1

lv2_test_context() {
  if [[ "${LEADV2_TEST_CONTEXT:-}" == "1" ]]; then return 0; fi
  if [[ "${LEADV2_TEST_CONTEXT:-}" == "0" ]]; then return 1; fi
  # Ancestor walk: a suite drives production code as subprocesses, so the
  # suite itself is always somewhere up this process's tree. 12 hops covers
  # writer -> dispatcher -> suite -> runner -> shell -> harness; past that the
  # walk gives up clean ("not a test") rather than guessing. `ps -o command=`
  # is matched as a glob, so both `bash /abs/tests/test-x.sh` and a relative
  # `bash tests/test-x.sh` hit the pattern.
  local pid="$$" cmd="" hops=0
  while (( hops < 12 )); do
    cmd="$(ps -o command= -p "${pid}" 2>/dev/null || true)"
    case "${cmd}" in
      */tests/test-*.sh|*/tests/run-*.sh) return 0 ;;
    esac
    pid="$(ps -o ppid= -p "${pid}" 2>/dev/null | tr -d '[:space:]')"
    [[ "${pid}" =~ ^[0-9]+$ ]] || return 1
    [[ "${pid}" -le 1 ]] && return 1
    hops=$(( hops + 1 ))
  done
  return 1
}

lv2_refuse_test_write() {
  # <writer-name> <real-path-being-refused> <env-var-that-would-redirect-it>
  local writer="$1" real_path="$2" redirect_var="$3"
  printf '%s: REFUSED: test context (LEADV2_TEST_CONTEXT=%s) without %s redirect — refusing to append fixture data to real shared state %s\n' \
    "${writer}" "${LEADV2_TEST_CONTEXT:-unset}" "${redirect_var}" "${real_path}" >&2
  return 3
}
