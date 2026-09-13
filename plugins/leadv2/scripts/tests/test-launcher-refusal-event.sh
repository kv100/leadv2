#!/usr/bin/env bash
# CAPABILITY-GATES-DISAGREE-AND-THE-JOURNAL-CANNOT-SEE-IT-01:
# A real launch-registry refusal (not a fabricated stderr fixture) must become
# one joined durable event: sig8, refusing arm, exact reason, and the arm the
# dispatcher falls through to. Also proves plugin is normalized by the same
# registry vocabulary the dispatcher preflight and arbiter use.
# run-all-triggers: leadv2-dispatch-code leadv2-launch-registry

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
DISPATCH_BIN="${LEADV2_TEST_DISPATCH_BIN:-${SCRIPTS_DIR}/leadv2-dispatch-code.sh}"
REGISTRY_BIN="${SCRIPTS_DIR}/lib/leadv2-launch-registry.py"

PASS=0; FAIL=0
pass() { printf 'PASS: %s\n' "$1"; PASS=$((PASS + 1)); }
fail() { printf 'FAIL: %s%s\n' "$1" "${2:+ -- $2}"; FAIL=$((FAIL + 1)); }

bash -n "${SCRIPT_DIR}/test-launcher-refusal-event.sh" || exit 1
bash -n "${DISPATCH_BIN}" || { fail "dispatcher syntax"; exit 1; }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/launcher-refusal-event.XXXXXX")"
trap 'rm -rf "${TMP}"' EXIT
mkdir -p "${TMP}/repo" "${TMP}/events"
git -C "${TMP}/repo" init -q -b main

run_real_refusal() {  # <dispatcher> <event-dir> <decision-log> <stderr-artifact>
  local dispatcher="$1" event_dir="$2" decision_log="$3" stderr_artifact="$4"
  LEADV2_DISPATCH_SOURCE_ONLY=1 LEADV2_EVENT_LOG_DIR="${event_dir}" \
    PROJECT_ROOT="${TMP}/repo" CLAUDE_PROJECT_ROOT="${TMP}/repo" \
    LEADV2_TEST_CONTEXT=1 bash -s -- "${dispatcher}" "${REGISTRY_BIN}" "${decision_log}" "${stderr_artifact}" <<'SH'
set -uo pipefail
dispatcher="$1" registry="$2" decisions="$3" stderr_artifact="$4"
cd "${PROJECT_ROOT}"
source "${dispatcher}"
emit() { printf '%s\n' "$2" >> "${decisions}"; }

# This is the production registry binary and production capability matrix.
# The former disagreement shape now succeeds: raw kind=plugin is normalized
# by the registry itself to the matrix vocabulary's code kind.
python3 "${registry}" --kind plugin --role developer --arm sonnet --task-class standard \
  >/dev/null 2>"${stderr_artifact}.plugin"
plugin_rc=$?
[[ ${plugin_rc} -eq 0 ]] || exit 40

# This is a REAL dispatcher launch attempt, not a fixture. fable is not a
# build arm, so _spawn_worker_body invokes the production registry, receives
# its `refused: not_a_build_arm` stderr, and spawn_worker captures it before
# it removes the temporary stderr file. Keep every transient artifact inside
# this suite's disposable directory.
TMPDIR="$(dirname "${stderr_artifact}")/dispatcher-tmp"
mkdir -p "${TMPDIR}"
WORK_ROOT="${PROJECT_ROOT}"
LEADV2_BURN_GOVERNOR=0
# This regression reaches the registry before a worker could launch; keep the
# unrelated code-intel attach gate off so the real-refusal proof stays fast.
LEADV2_WORKER_MCP=0
spawn_worker fable 'real registry refusal probe' cafe0001 >/dev/null
spawn_rc=$?
[[ ${spawn_rc} -eq 2 ]] || exit 41
grep -qx 'refused: not_a_build_arm' "${TMPDIR}/leadv2-dispatch-spawn-cafe0001.stderr.log" || exit 42

# The next candidate is where the captured producer-seam refusal becomes its
# joined decision/event row.
_emit_pending_launcher_refusal cafe0001 codex
[[ ! -e "$(_launcher_refusal_file cafe0001)" ]] || exit 43
SH
}

GREEN_DECISIONS="${TMP}/green.decisions"
GREEN_STDERR="${TMP}/green.stderr"
if run_real_refusal "${DISPATCH_BIN}" "${TMP}/events" "${GREEN_DECISIONS}" "${GREEN_STDERR}"; then
  pass "plugin kind is normalized by the real launch registry; a separate real refusal reached dispatcher capture seam"
else
  fail "real registry refusal did not reach dispatcher capture seam"
fi

if grep -qx 'launcher_refused task=cafe0001 arm=fable reason=not_a_build_arm fell_through_to=codex' "${GREEN_DECISIONS}"; then
  pass "decision journal row joins sig8, arm, reason, and actual fallback"
else
  fail "decision journal row missing or malformed" "$(cat "${GREEN_DECISIONS}" 2>/dev/null)"
fi

GREEN_EVENTS="$(find "${TMP}/events" -name '*.jsonl' -type f | head -1)"
if python3 - "${GREEN_EVENTS}" <<'PY'
import json, sys
rows = [json.loads(line) for line in open(sys.argv[1]) if line.strip()]
assert len(rows) == 1, rows
row = rows[0]
assert row['kind'] == 'launcher_refused', row
assert row['task'] == 'cafe0001', row
assert row['arm'] == 'fable', row
assert row['detail'] == 'reason=not_a_build_arm fell_through_to=codex', row
PY
then
  pass "durable event row carries exact launcher refusal and fallback"
else
  fail "durable event row missing required fields" "$(cat "${GREEN_EVENTS}" 2>/dev/null)"
fi

# Negative control: mutate the capture body's reason assignment in a scratch
# copy. The real registry still refuses, but the exact-reason assertion must
# go red. This proves the suite observes the implementation rather than merely
# a fixture shaped like its expected event.
MUTANT="${TMP}/leadv2-dispatch-code.mutant.sh"
cp "${DISPATCH_BIN}" "${MUTANT}"
python3 - "${MUTANT}" <<'PY'
import sys
path = sys.argv[1]
text = open(path, encoding='utf-8').read()
old = '    reason="${raw}"\n'
if text.count(old) != 1:
    raise SystemExit('mutation anchor count != 1')
open(path, 'w', encoding='utf-8').write(text.replace(old, '    reason="unclassified"\n'))
PY
MUT_DECISIONS="${TMP}/mutant.decisions"
MUT_STDERR="${TMP}/mutant.stderr"
MUT_EVENTS="${TMP}/mutant-events"
if run_real_refusal "${MUTANT}" "${MUT_EVENTS}" "${MUT_DECISIONS}" "${MUT_STDERR}" \
  && grep -qx 'launcher_refused task=cafe0001 arm=fable reason=not_a_build_arm fell_through_to=codex' "${MUT_DECISIONS}"; then
  fail "RED control unexpectedly stayed green"
else
  pass "RED control: mutating capture reason made the real-refusal assertion red"
fi

printf '\nlauncher-refusal-event: PASS=%d FAIL=%d\n' "${PASS}" "${FAIL}"
[[ ${FAIL} -eq 0 ]]
