#!/usr/bin/env bash
# leadv2-suite-falsifiable.sh — SUITE-THAT-CANNOT-FAIL-01.
#
# Decides, from BEHAVIOUR ONLY (never from the suite's source text), whether a
# test suite is capable of failing. Motivation: commit 0d61b3c shipped a
# 59-line "test suite" with zero assertions and zero failure paths — exit 0
# for any input — and it looked like delivered, tested work. This checker is
# the machine answer to that shape.
#
# Method: run the suite as-is (baseline), then re-run it under generic failure
# injections that any honest suite must notice. A suite whose exit code stays
# 0 while every assertion tool is broken, its working directory is emptied and
# its environment is stripped, cannot distinguish correct from incorrect
# behaviour — it is not falsifiable and carries no evidence.
#
# Injections (all generic — no naming convention, no source inspection):
#   probe assertion_tools_broken — PATH-front shims make grep/egrep/fgrep/
#     diff/cmp exit 1. These are the canonical assertion tools; setup tools
#     (mktemp, mkdir, dirname, rm, interpreters) are deliberately NOT
#     shimmed, so a suite whose SETUP merely crashes is not confused with a
#     suite whose ASSERTIONS fired. Shims log every invocation to a marker
#     file, so "engaged" (the suite really called a sabotaged tool) is
#     distinguishable from "never touched".
#   probe empty_cwd              — run from a directory containing nothing.
#   probe stripped_env           — env -i: only PATH/HOME/TMPDIR survive.
#
# Exit codes:
#   0  falsifiable        — some injection changed the suite's exit code
#   1  NOT falsifiable    — green baseline, every injection left it green
#   2  could not determine— suite missing, not runnable, timed out, or already
#                            red at baseline (e.g. missing dependency): never
#                            a pass, and never an accusation
#   3  usage error
#
# Bash 3.2 compatible (no mapfile, arrays guarded under set -u).
set -uo pipefail

if [[ $# -ne 1 ]]; then
  printf 'Usage: %s <suite-path>\n' "$0" >&2
  exit 3
fi

SUITE="$1"
if [[ ! -f "${SUITE}" ]]; then
  printf 'leadv2-suite-falsifiable: not a file: %s\n' "${SUITE}" >&2
  exit 3
fi
SUITE_ABS="$(cd "$(dirname "${SUITE}")" && pwd)/$(basename "${SUITE}")"
SUITE_DIR="$(dirname "${SUITE_ABS}")"

# PPC-G1: default was 60s. BEAT-LOOP-ORPHANS-01 measured a 22-case suite
# taking 71s wall-clock under concurrent-lane load (53 orphaned beat/pulse
# loops driving load average to 244), which killed this watchdog mid-baseline
# and produced a false "could_not_determine — suite timed out" verdict for a
# suite that was never given a real chance to run (RESUME-LANE-ACCEPTS-PATH-01
# blocked on it). This checker runs the wrapped suite up to 4 times
# sequentially (baseline + 3 injection probes), so a single generous constant
# — not a per-run scaling factor — is the right lever: 180s gives >2x margin
# over the observed 71s without weakening the actual falsifiability logic
# below (the mutation/injection checks are untouched). Callers who need a
# different budget still override via LEADV2_SUITE_FALSIFIABLE_TIMEOUT.
TIMEOUT_S="${LEADV2_SUITE_FALSIFIABLE_TIMEOUT:-180}"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/leadv2-falsify.XXXXXX")"
trap 'rm -rf "${WORK}"' EXIT
SHIM_DIR="${WORK}/shims"
MARKER="${WORK}/shim-hits"
mkdir -p "${SHIM_DIR}"

# Failing shims for the assertion tools. /bin/sh shebang so a shim never
# re-enters PATH resolution for an interpreter.
for _tool in grep egrep fgrep diff cmp; do
  cat > "${SHIM_DIR}/${_tool}" <<SHIMEOF
#!/bin/sh
printf '%s\n' "${_tool}" >> "\${LEADV2_FALSIFY_SHIM_HITS:-/dev/null}" 2>/dev/null
echo "leadv2-falsify: ${_tool} sabotaged (failure injection)" >&2
exit 1
SHIMEOF
  chmod +x "${SHIM_DIR}/${_tool}"
done

# run_suite <label> <cwd> <shim-path-or-empty> <strip-env 0|1>
# Echoes "rc=<n>" (rc=125 means timed out). Never inherits -e: every exit
# code is data here. Bash 3.2 has no `wait -n`, so the timeout is a watchdog
# subshell (kill -0 on an unreaped zombie is always true and cannot be used
# to poll for completion).
run_suite() {
  local label="$1" cwd="$2" shim_prefix="$3" strip_env="$4"
  local out="${WORK}/out.${label}"
  if [[ "${strip_env}" == "1" ]]; then
    (
      cd "${cwd}" 2>/dev/null || exit 99
      exec env -i PATH="${shim_prefix:+${shim_prefix}:}${PATH}" \
        HOME="${HOME:-/tmp}" TMPDIR="${TMPDIR:-/tmp}" \
        bash "${SUITE_ABS}"
    ) > "${out}" 2>&1 &
  else
    (
      cd "${cwd}" 2>/dev/null || exit 99
      if [[ -n "${shim_prefix}" ]]; then
        exec env PATH="${shim_prefix}:${PATH}" bash "${SUITE_ABS}"
      else
        exec bash "${SUITE_ABS}"
      fi
    ) > "${out}" 2>&1 &
  fi
  local pid=$! rc=0 timed_out=0
  ( sleep "${TIMEOUT_S}"; kill -TERM "${pid}" 2>/dev/null ) >/dev/null 2>&1 &
  local wd=$!
  wait "${pid}"; rc=$?
  if ! kill -TERM "${wd}" 2>/dev/null; then timed_out=1; fi
  wait "${wd}" 2>/dev/null
  if [[ ${timed_out} -eq 1 ]]; then
    printf 'rc=125'
  else
    printf 'rc=%s' "${rc}"
  fi
}

printf 'leadv2-suite-falsifiable: suite=%s\n' "${SUITE_ABS}"

# ── Baseline ────────────────────────────────────────────────────────────────
BASE="$(run_suite baseline "${SUITE_DIR}" "" 0)"
BASE_RC="${BASE#rc=}"
printf 'baseline: rc=%s\n' "${BASE_RC}"
if [[ "${BASE_RC}" == "125" ]]; then
  printf 'verdict: could_not_determine — suite timed out (%ss) at baseline\n' "${TIMEOUT_S}"
  exit 2
fi
if [[ "${BASE_RC}" != "0" ]]; then
  # Already red as-is (missing dependency, broken fixture, real failure). We
  # cannot assess falsifiability from a failing run, and we refuse to guess:
  # report undetermined. Not a pass, not an accusation.
  printf 'verdict: could_not_determine — suite is already red at baseline (rc=%s); falsifiability needs a green run\n' "${BASE_RC}"
  exit 2
fi

# ── Injection battery ───────────────────────────────────────────────────────
ENGAGED=0
UNDETERMINED_PROBES=0

P1="$(LEADV2_FALSIFY_SHIM_HITS="${MARKER}" run_suite assertion_tools_broken "${SUITE_DIR}" "${SHIM_DIR}" 0)"
P1_RC="${P1#rc=}"
if [[ -f "${MARKER}" ]]; then
  ENGAGED=$(wc -l < "${MARKER}" | tr -d ' ')
fi
printf 'probe[assertion_tools_broken]: rc=%s shim_invocations=%s\n' "${P1_RC}" "${ENGAGED}"

mkdir -p "${WORK}/empty"
P2="$(run_suite empty_cwd "${WORK}/empty" "" 0)"
P2_RC="${P2#rc=}"
printf 'probe[empty_cwd]: rc=%s\n' "${P2_RC}"

P3="$(run_suite stripped_env "${SUITE_DIR}" "" 1)"
P3_RC="${P3#rc=}"
printf 'probe[stripped_env]: rc=%s\n' "${P3_RC}"

# ── Verdict ─────────────────────────────────────────────────────────────────
for probe_rc in "${P1_RC}" "${P2_RC}" "${P3_RC}"; do
  if [[ "${probe_rc}" != "0" && "${probe_rc}" != "125" ]]; then
    printf 'verdict: falsifiable — a failure injection turned the suite red (rc=%s)\n' "${probe_rc}"
    exit 0
  fi
  [[ "${probe_rc}" == "125" ]] && UNDETERMINED_PROBES=$((UNDETERMINED_PROBES + 1))
done

if [[ ${UNDETERMINED_PROBES} -gt 0 ]]; then
  printf 'verdict: could_not_determine — %s probe(s) timed out under injection, none went red\n' "${UNDETERMINED_PROBES}"
  exit 2
fi

# Green under everything we could break. Name the suite and say what a worker
# must do — a refusal nobody can act on just produces another round of this.
printf 'verdict: NOT FALSIFIABLE — %s\n' "${SUITE_ABS}"
printf '  exit code 0 under every failure injection (assertion tools broken:\n'
printf '  %s sabotaged-tool call(s); empty working directory; stripped environment).\n' "${ENGAGED}"
printf '  A suite that stays exit 0 no matter what breaks cannot distinguish\n'
printf '  correct from incorrect behaviour, so it carries no evidence.\n'
printf '  A printed "FAIL:" line that leaves $? at 0 is NOT an assertion: make the\n'
printf '  suite exit non-zero on failure (exit 1, or let the failing command\n'
printf '  propagate — no "|| true" around the checked command).\n'
exit 1
