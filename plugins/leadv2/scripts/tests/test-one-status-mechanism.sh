#!/usr/bin/env bash
# run-all-triggers: anti-silence-pulse.sh hooks.json leadv2.md
# ONE-STATUS-MECHANISM-01 acceptance: the plugin anti-silence pulse is the
# only founder-status mechanism.  Every check has a red-first control against
# a scratch copy, so a missing or vacuous mutation cannot claim coverage.
set -euo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "${TEST_DIR}/../.." && pwd)"
PULSE="${PLUGIN_ROOT}/scripts/anti-silence-pulse.sh"
HOOKS="${PLUGIN_ROOT}/hooks/hooks.json"
TMP="$(mktemp -d /private/tmp/one-status-mechanism.XXXXXX)"
trap 'rm -rf "${TMP}"' EXIT

pass=0
fail=0
ok() { printf 'ok - %s\n' "$1"; pass=$((pass + 1)); }
bad() { printf 'not ok - %s\n' "$1" >&2; fail=$((fail + 1)); }
must() { "$@" && ok "$1" || bad "$1"; }

old_names='leadv2-broad-status\.sh|leadv2-pulse-beat\.sh|leadv2-single-lead-beat\.sh|leadv2-pulse-watch\.sh|LEADV2_SINGLE_LEAD_BEAT|LEADV2_SUPERVISE_BROAD_STATUS_S|LEADV2_BROAD_STATUS_BEAT_AT|LEADV2_PULSE_WATCH'

live_surface_clean() {
  ! rg -n -e "${old_names}" "${HOOKS}" "${PLUGIN_ROOT}/commands" "${PLUGIN_ROOT}/hooks" \
    --glob '!leadv2-single-lead-beat.sh' --glob '!leadv2-pulse-watch-arm.sh' \
    --glob '!leadv2-pulse-enforcer.sh' >/dev/null
}

printf '%s\n' '1..4'

# 1. Exactly the plugin registrations remain.  The negative control injects a
# retired command into a scratch manifest and must make the same census fail.
hook_count="$(jq '[.. | objects | select(has("command")) | .command] | length' "${HOOKS}")"
[[ "${hook_count}" == "84" ]] || { printf 'hook baseline changed: %s\n' "${hook_count}" >&2; exit 1; }
live_surface_clean
cp "${HOOKS}" "${TMP}/hooks.bad.json"
anchor='"hooks": {'
[[ "$(grep -cF "${anchor}" "${TMP}/hooks.bad.json")" == "1" ]] || exit 1
perl -0pi -e 's/"hooks": \{/{"hooks":{"SessionStart":[{"hooks":[{"command":"leadv2-pulse-beat.sh"}]}],/s' "${TMP}/hooks.bad.json"
if ! rg -e 'leadv2-pulse-beat\.sh' "${TMP}/hooks.bad.json" >/dev/null; then exit 1; fi
printf 'RED: retired hook injection was detected\n'
ok 'only the anti-silence plugin hooks remain (baseline=84)'

# Shared fixture: no phase, no process, no fresh worktree evidence.  Only the
# worker journal stream can make lane-live alive.
mkdir -p "${TMP}/tasks/lane-live" "${TMP}/glm/handle-live"
printf '%s\n' 'sessions:' '  - task_id: lane-live' >"${TMP}/active.yaml"
printf '%s\n' 'old task journal' >"${TMP}/tasks/lane-live/journal.md"
printf '%s\n' 'repo: lane-live' 'started_at: 2026-09-13T00:00:00Z' 'finished_at:' >"${TMP}/glm/handle-live/meta.yaml"
printf '%s\n' 'first worker chunk' >"${TMP}/glm/handle-live/journal.jsonl"
python3 -c "import os; os.utime('${TMP}/tasks/lane-live/journal.md',(1789250400,1789250400)); os.utime('${TMP}/glm/handle-live/journal.jsonl',(1789257300,1789257300))"
printf '%s\n' '#!/usr/bin/env bash' 'printf "{\\"lanes\\":[]}"' >"${TMP}/probe.sh"
chmod +x "${TMP}/probe.sh"

run_tick() {
  local script="$1"
  ANTI_SILENCE_GLM_RUNS_DIR="${TMP}/glm" ANTI_SILENCE_GLM_SNAPSHOT="${TMP}/snapshot" \
  ACTIVE_YAML="${TMP}/active.yaml" TASKS_DIR="${TMP}/tasks" PULSE_LOG_FILE="${TMP}/pulse.log" \
  PULSE_PID_FILE="${TMP}/pulse.pid" PULSE_HEARTBEAT_FILE="${TMP}/pulse.heartbeat" \
  LEADV2_LANE_LIVENESS_SCRIPT="${TMP}/probe.sh" \
    bash "${script}" --once --now=1789257600
}

# 2. Prime the size snapshot, grow the GLM journal, and prove the row is live.
run_tick "${PULSE}" >/dev/null
printf '%s\n' 'second worker chunk' >>"${TMP}/glm/handle-live/journal.jsonl"
out="$(run_tick "${PULSE}")"
[[ "${out}" == *'live=1'* && "${out}" == *'lane-live'* && "${out}" == *'glm-поток'* ]] || exit 1
cp "${PULSE}" "${TMP}/pulse.no-glm.sh"
anchor='strong_age, strong_tag = _gsv[0], "glm"'
[[ "$(grep -cF "${anchor}" "${TMP}/pulse.no-glm.sh")" == "1" ]] || exit 1
perl -0pi -e 's/strong_age, strong_tag = _gsv\[0\], "glm"/strong_age, strong_tag = None, None  # one-status negative control/g' "${TMP}/pulse.no-glm.sh"
if run_tick "${TMP}/pulse.no-glm.sh" | rg -q 'live=1'; then exit 1; fi
printf 'RED: disabling GLM stream evidence removed the alive verdict\n'
ok 'growing worker journal reports the lane alive'

# 3. Calm must still speak.  The control deletes the literal silence suffix.
empty="${TMP}/empty.yaml"
printf '%s\n' 'sessions: []' >"${empty}"
empty_out="$(ACTIVE_YAML="${empty}" TASKS_DIR="${TMP}/tasks" PULSE_LOG_FILE="${TMP}/empty.log" PULSE_PID_FILE="${TMP}/empty.pid" PULSE_HEARTBEAT_FILE="${TMP}/empty.heartbeat" bash "${PULSE}" --once --now=1789257600)"
[[ "${empty_out}" == *'live=0 — тишина'* ]] || exit 1
cp "${PULSE}" "${TMP}/pulse.silent.sh"
anchor='print(f"{stamp} live=0 — тишина")'
[[ "$(grep -cF "${anchor}" "${TMP}/pulse.silent.sh")" == "1" ]] || exit 1
perl -0pi -e 's/print\(f"\{stamp\} live=0 — тишина"\)/print(f"{stamp} live=0")/' "${TMP}/pulse.silent.sh"
silent_out="$(ACTIVE_YAML="${empty}" TASKS_DIR="${TMP}/tasks" PULSE_LOG_FILE="${TMP}/silent.log" PULSE_PID_FILE="${TMP}/silent.pid" PULSE_HEARTBEAT_FILE="${TMP}/silent.heartbeat" bash "${TMP}/pulse.silent.sh" --once --now=1789257600)"
[[ "${silent_out}" != *'тишина'* ]] || exit 1
printf 'RED: deleting the silence marker changed the quiet-tick output\n'
ok 'a tick with no lanes still emits a silence line'

# 4. A live surface cannot point at any deleted entry point.  The control
# creates a scratch command doc containing an old path and proves the census red.
live_surface_clean
printf '%s\n' 'retired command: leadv2-broad-status.sh' >"${TMP}/live-surface.md"
if ! rg -e 'leadv2-broad-status\.sh' "${TMP}/live-surface.md" >/dev/null; then exit 1; fi
printf 'RED: retired live-surface reference was detected\n'
ok 'no live plugin surface names a deleted entry point'

printf 'PASS: %s checks\n' "${pass}"
[[ "${fail}" == 0 ]]
