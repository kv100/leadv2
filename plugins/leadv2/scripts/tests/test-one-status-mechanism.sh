#!/usr/bin/env bash
# run-all-triggers: anti-silence-pulse.sh hooks.json leadv2.md
# ONE-STATUS-MECHANISM-01 acceptance: the plugin anti-silence pulse is the
# only founder-status mechanism.  Four checks, each with a red-first control
# that runs the REAL assertion against a mutated scratch copy — a control
# that only greps its own scratch file proves nothing about the assertion it
# claims to cover, so the census the suite uses for real is the same code
# that must fail on the mutant.
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

old_names='leadv2-broad-status\.sh|leadv2-pulse-beat\.sh|leadv2-single-lead-beat\.sh|leadv2-pulse-watch\.sh|LEADV2_SINGLE_LEAD_BEAT|LEADV2_SUPERVISE_BROAD_STATUS_S|LEADV2_BROAD_STATUS_BEAT_AT|LEADV2_PULSE_WATCH'
tombstones=(leadv2-single-lead-beat.sh leadv2-pulse-watch-arm.sh leadv2-pulse-enforcer.sh)
globs=()
for t in "${tombstones[@]}"; do globs+=(--glob "!${t}"); done

# Census: no retired name on the hook manifest or any plugin surface
# (commands/, hooks/), except inside the three no-op tombstones kept for
# pre-deletion sessions (SD-DELETE-HOOK-TOMBSTONES-01).  Manifest and
# surface root are arguments so the negative controls can aim the SAME
# census at a mutated scratch copy.
census_clean() { # <hooks.json> <surface-root> — 0 = clean
  [[ -f "$1" && -d "$2/commands" && -d "$2/hooks" ]] || return 2
  ! rg -n -e "${old_names}" "$1" "$2/commands" "$2/hooks" "${globs[@]}" >/dev/null 2>&1
}
live_surface_clean() { census_clean "${HOOKS}" "${PLUGIN_ROOT}"; }

# Every registered hook command must point at a script that exists.
# Prints the count of registrations that do not resolve.
unresolvable_hooks() { # <hooks.json> <plugin-root>
  local hooks_file="$1" root="$2" cmd path n=0
  local pat='${CLAUDE_PLUGIN_ROOT}'
  while IFS= read -r cmd; do
    path="${cmd%% *}"
    path="${path//\"/}"
    path="${path//$pat/$root}"
    [[ "${path}" == /* ]] || continue
    [[ -f "${path}" ]] || n=$((n + 1))
  done < <(jq -r '.hooks[][] | .hooks[] | select(.command != null) | .command' "${hooks_file}")
  printf '%s\n' "${n}"
}

printf '%s\n' '1..4'

# 1. Exactly one mechanism: the pulse is registered, the retired chain is
# gone, nothing left on disk is live, and the hook baseline holds.  Control:
# inject a retired registration into a scratch manifest; the census that
# guards the real manifest must fail on the scratch one.
hook_count="$(jq '[.. | objects | select(has("command")) | .command] | length' "${HOOKS}")"
[[ "${hook_count}" == "84" ]] || { printf 'FAIL: hook baseline changed: %s (want 84)\n' "${hook_count}" >&2; exit 1; }
anti_regs="$(jq -r '[.hooks[][] | .hooks[] | select(.command != null) | .command] | map(select(test("anti-silence"))) | length' "${HOOKS}")"
[[ "${anti_regs}" == "2" ]] || { printf 'FAIL: anti-silence registrations: %s (want 2)\n' "${anti_regs}" >&2; exit 1; }
for t in "${tombstones[@]}"; do
  ts="${PLUGIN_ROOT}/hooks/${t}"
  if [[ -e "${ts}" ]]; then
    [[ "$(tail -n 1 "${ts}")" == "exit 0" && "$(wc -c <"${ts}")" -le 600 ]] \
      || { printf 'FAIL: tombstone is no longer a no-op: %s\n' "${t}" >&2; exit 1; }
  fi
done
live_surface_clean || { printf 'FAIL: retired entry point named on a live surface\n' >&2; exit 1; }
cp "${HOOKS}" "${TMP}/hooks.bad.json"
anchor='"hooks": {'
[[ "$(grep -cF "${anchor}" "${TMP}/hooks.bad.json")" == "1" ]] || { printf 'FAIL: control-1 anchor missing in hooks.json\n' >&2; exit 1; }
perl -0pi -e 's/"hooks": \{/"hooks": { "SessionStart": [ {"hooks": [{"command":"leadv2-pulse-beat.sh"}]} ],/s' "${TMP}/hooks.bad.json"
rg -q 'leadv2-pulse-beat\.sh' "${TMP}/hooks.bad.json" || { printf 'FAIL: control-1 injection did not land\n' >&2; exit 1; }
if census_clean "${TMP}/hooks.bad.json" "${PLUGIN_ROOT}"; then
  printf 'FAIL: control-1 census stayed clean with a retired registration injected\n' >&2; exit 1
fi
printf 'RED: census failed on scratch manifest with retired hook injected\n'
ok 'only the anti-silence plugin hooks remain (baseline=84, anti-silence regs=2)'

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

# 2. Prime the size snapshot, grow the GLM journal, and prove the row is
# live.  Control: the same tick with GLM stream evidence disabled must lose
# the alive verdict.
run_tick "${PULSE}" >/dev/null
printf '%s\n' 'second worker chunk' >>"${TMP}/glm/handle-live/journal.jsonl"
out="$(run_tick "${PULSE}")"
[[ "${out}" == *'live=1'* && "${out}" == *'lane-live'* && "${out}" == *'glm-поток'* ]] \
  || { printf 'FAIL: growing journal not reported alive: %s\n' "${out}" >&2; exit 1; }
cp "${PULSE}" "${TMP}/pulse.no-glm.sh"
anchor='strong_age, strong_tag = _gsv[0], "glm"'
[[ "$(grep -cF "${anchor}" "${TMP}/pulse.no-glm.sh")" == "1" ]] || { printf 'FAIL: control-2 anchor missing in pulse\n' >&2; exit 1; }
perl -0pi -e 's/strong_age, strong_tag = _gsv\[0\], "glm"/strong_age, strong_tag = None, None  # one-status negative control/g' "${TMP}/pulse.no-glm.sh"
if run_tick "${TMP}/pulse.no-glm.sh" | rg -q 'live=1'; then
  printf 'FAIL: control-2 mutant still reported a lane alive\n' >&2; exit 1
fi
printf 'RED: disabling GLM stream evidence removed the alive verdict\n'
ok 'growing worker journal reports the lane alive'

# 3. Calm must still speak.  Control: deleting the literal silence suffix
# must change the quiet-tick output.
empty="${TMP}/empty.yaml"
printf '%s\n' 'sessions: []' >"${empty}"
empty_out="$(ANTI_SILENCE_GLM_RUNS_DIR="${TMP}/glm" ANTI_SILENCE_GLM_SNAPSHOT="${TMP}/snapshot-empty" \
  ACTIVE_YAML="${empty}" TASKS_DIR="${TMP}/tasks" PULSE_LOG_FILE="${TMP}/empty.log" \
  PULSE_PID_FILE="${TMP}/empty.pid" PULSE_HEARTBEAT_FILE="${TMP}/empty.heartbeat" \
  bash "${PULSE}" --once --now=1789257600)"
[[ "${empty_out}" == *'live=0 — тишина'* ]] || { printf 'FAIL: quiet tick emitted nothing: %s\n' "${empty_out}" >&2; exit 1; }
cp "${PULSE}" "${TMP}/pulse.silent.sh"
anchor='print(f"{stamp} live=0 — тишина")'
[[ "$(grep -cF "${anchor}" "${TMP}/pulse.silent.sh")" == "1" ]] || { printf 'FAIL: control-3 anchor missing in pulse\n' >&2; exit 1; }
perl -0pi -e 's/print\(f"\{stamp\} live=0 — тишина"\)/print(f"{stamp} live=0")/' "${TMP}/pulse.silent.sh"
silent_out="$(ANTI_SILENCE_GLM_RUNS_DIR="${TMP}/glm" ANTI_SILENCE_GLM_SNAPSHOT="${TMP}/snapshot-silent" \
  ACTIVE_YAML="${empty}" TASKS_DIR="${TMP}/tasks" PULSE_LOG_FILE="${TMP}/silent.log" \
  PULSE_PID_FILE="${TMP}/silent.pid" PULSE_HEARTBEAT_FILE="${TMP}/silent.heartbeat" \
  bash "${TMP}/pulse.silent.sh" --once --now=1789257600)"
[[ "${silent_out}" != *'тишина'* ]] || { printf 'FAIL: control-3 output still carries the silence marker\n' >&2; exit 1; }
printf 'RED: deleting the silence marker changed the quiet-tick output\n'
ok 'a tick with no lanes still emits a silence line'

# 4. No live surface names a deleted entry point and every registration
# resolves.  Two controls: a retired path planted on a scratch surface, and
# a registration whose script does not exist — both must redden the checks
# that guard the real tree.
live_surface_clean || { printf 'FAIL: retired entry point named on a live surface\n' >&2; exit 1; }
[[ "$(unresolvable_hooks "${HOOKS}" "${PLUGIN_ROOT}")" == "0" ]] || { printf 'FAIL: unresolvable hook registrations\n' >&2; exit 1; }
mkdir -p "${TMP}/bad-surface/commands" "${TMP}/bad-surface/hooks"
printf '%s\n' 'retired command: leadv2-broad-status.sh' >"${TMP}/bad-surface/commands/leadv2.md"
if census_clean "${HOOKS}" "${TMP}/bad-surface"; then
  printf 'FAIL: control-4a census stayed clean with a retired name on a live surface\n' >&2; exit 1
fi
printf 'RED: census failed on scratch surface naming a deleted file\n'
cp "${HOOKS}" "${TMP}/hooks.deadref.json"
anchor2='"hooks": {'
[[ "$(grep -cF "${anchor2}" "${TMP}/hooks.deadref.json")" == "1" ]] || { printf 'FAIL: control-4b anchor missing in hooks.json\n' >&2; exit 1; }
# Injected under a synthetic event key (jq keeps only the last of duplicate
# keys, so reusing a real event name would hide the registration from the
# scan — the control would rot into a permanent green exactly that way).
perl -0pi -e 's/"hooks": \{/"hooks": { "MutationControlProbe": [ {"hooks": [{"command":"\${CLAUDE_PLUGIN_ROOT}\/hooks\/leadv2-vanished-control.sh"}]} ],/s' "${TMP}/hooks.deadref.json"
dead_n="$(unresolvable_hooks "${TMP}/hooks.deadref.json" "${PLUGIN_ROOT}")"
[[ "${dead_n}" -ge 1 ]] || { printf 'FAIL: control-4b unresolvable scan missed a registration with no script\n' >&2; exit 1; }
printf 'RED: unresolvable scan counted %s missing script(s) in scratch manifest\n' "${dead_n}"
ok 'no live surface names a deleted file; every registration resolves (0 unresolvable)'

printf 'PASS: %s checks\n' "${pass}"
[[ "${fail}" == 0 ]]
