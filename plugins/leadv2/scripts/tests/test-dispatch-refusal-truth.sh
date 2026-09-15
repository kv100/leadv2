#!/usr/bin/env bash
# DISPATCH-REFUSALS-LIE-ABOUT-THEIR-CAUSE-01
# run-all-triggers: leadv2-dispatch-code leadv2_tasks_yaml_common
#
# Three production seams, driven without replacing their decisions:
#   D1 cmd_resolve's CLI parse refuses a supplied unknown kind; its classifier
#      still proves the omitted-kind conservative default.
#   D2 _resume_mission_visibility_preflight sees a real untracked file in a
#      real Git worktree, then distinguishes a file absent from disk.
#   D3 _premise_probe_gate reads a real fixture docs/tasks.yaml via the shared
#      row matcher, including external_id, and reports its searched keys on a
#      genuinely unknown task.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS="$(cd "${HERE}/.." && pwd)"
DISPATCH="${SCRIPTS}/leadv2-dispatch-code.sh"
ROOT="$(cd "${SCRIPTS}/../.." && pwd)"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/dispatch-refusal-truth.XXXXXX")"
trap 'rm -rf "${TMP}"' EXIT INT TERM
PASS=0 FAIL=0
pass() { PASS=$((PASS + 1)); printf 'PASS: %s\n' "$1"; }
fail() { FAIL=$((FAIL + 1)); printf 'FAIL: %s\n' "$1" >&2; }

# D1: this runs the entrypoint itself. The rejection must happen before the
# mission can enter any admission/prepass path.
d1_out="${TMP}/d1.out"; d1_rc=0
bash "${DISPATCH}" 'no side effects' --kind code >"${d1_out}" 2>&1 || d1_rc=$?
if [[ "${d1_rc}" == 1 ]] && grep -Fq "invalid --kind 'code'" "${d1_out}" \
  && grep -Fq 'accepted kinds: product|plugin|tooling|tool|docs|documentation|diagnosis|diagnostic|investigation' "${d1_out}"; then
  pass 'D1 unknown kind is refused with supplied value and shared accepted set'
else
  fail "D1 unknown kind refusal mismatch rc=${d1_rc}: $(tr '\n' ' ' < "${d1_out}")"
fi

# The absent-kind control calls the exact production classifier; it is not a
# restated vocabulary in this suite.
python3 - "${DISPATCH}" "${TMP}/classify.sh" <<'PY'
import sys
s = open(sys.argv[1], encoding="utf-8").read()
start = s.index("LEADV2_NON_PRODUCT_KINDS=")
end = s.index("\n}\n", s.index("classify_product_work() {")) + 3
open(sys.argv[2], "w", encoding="utf-8").write(s[start:end])
PY
source "${TMP}/classify.sh"
if [[ "$(classify_product_work '' 'ordinary work')" == $'product\tconservative_default' ]]; then
  pass 'D1 absent kind remains the conservative default'
else
  fail "D1 absent kind changed: $(classify_product_work '' 'ordinary work')"
fi

# D2: a lane one commit behind main has a file physically present but untracked.
D2_REPO="${TMP}/d2-repo"; D2_LANE="${D2_REPO}/.claude/worktrees/lane"
mkdir -p "${D2_REPO}"
(cd "${D2_REPO}" && git init -q -b main && git config user.email test@example.com && git config user.name test && printf 'seed\n' > seed && git add seed && git commit -qm seed)
mkdir -p "$(dirname "${D2_LANE}")"
(cd "${D2_REPO}" && git worktree add -q "${D2_LANE}" -b lane)
printf 'mission only in lane filesystem\n' > "${D2_LANE}/mission.md"

run_d2() { # <path> <output>
  local p="$1" out="$2" rc=0
  bash -c 'LEADV2_DISPATCH_SOURCE_ONLY=1; source "$1"; PROJECT_ROOT="$2"; LANE_WORKTREE_BIN="$3"; _resume_mission_visibility_preflight "@$4" lane' \
    _ "${DISPATCH}" "${D2_REPO}" "${SCRIPTS}/leadv2-lane-worktree.sh" "${p}" >"${out}" 2>&1 || rc=$?
  printf '%s' "${rc}"
}
d2_untracked="${TMP}/d2-untracked.out"; d2_rc="$(run_d2 mission.md "${d2_untracked}")"
if [[ "${d2_rc}" == 5 ]] && grep -Fq 'present but untracked' "${d2_untracked}" \
  && grep -Fq "git -C ${D2_LANE} add mission.md && git -C ${D2_LANE} commit -- mission.md" "${d2_untracked}"; then
  pass 'D2 untracked mission names the state and git remedy'
else
  fail "D2 untracked refusal mismatch rc=${d2_rc}: $(tr '\n' ' ' < "${d2_untracked}")"
fi
d2_absent="${TMP}/d2-absent.out"; d2_absent_rc="$(run_d2 absent.md "${d2_absent}")"
if [[ "${d2_absent_rc}" == 5 ]] && grep -Fq 'absent from both lane worktree' "${d2_absent}" \
  && ! grep -Fq 'untracked' "${d2_absent}"; then
  pass 'D2 absent mission remains a distinct disk-absence refusal'
else
  fail "D2 absent refusal mismatch rc=${d2_absent_rc}: $(tr '\n' ' ' < "${d2_absent}")"
fi

# D3: use the premise gate's source-only seam with a real YAML row and a red
# probe. A red probe returns 0 (premise alive), so external_id resolution is
# directly observable in the emitted row identity.
D3_REPO="${TMP}/d3-repo"; mkdir -p "${D3_REPO}/docs"
printf 'live defect\n' > "${D3_REPO}/live-marker"
cat > "${D3_REPO}/docs/tasks.yaml" <<YAML
tasks:
- id: internal-row-0001
  external_id: EXTERNAL-ROW-01
  node_id: leadv2:EXTERNAL-ROW-01
  intent: 'Human display name: external-id row'
  acceptance_cmd: 'test -f ${D3_REPO}/live-marker && false'
YAML
run_d3() { # <task-id> <output>
  local task="$1" out="$2" rc=0
  LEADV2_PREMISE_BACKLOG_ROOTS="${D3_REPO}" LEADV2_DISPATCH_SOURCE_ONLY=1 \
  LEADV2_DISPATCH_TERMINAL_LEDGER=0 LEADV2_JOURNAL_BIN=/bin/true LEADV2_EVENT_BIN=/bin/true \
  bash -c 'source "$1"; PROJECT_ROOT="$2"; sig8=truthd301; founder_task_id="$3"; lane_acceptance_cmd=""; placement_lane_ref=""; placement_path=""; JOURNAL_TASK=""; premise_no_probe_yet=0; _premise_probe_gate' \
    _ "${DISPATCH}" "${D3_REPO}" "${task}" >"${out}" 2>&1 || rc=$?
  printf '%s' "${rc}"
}
d3_external="${TMP}/d3-external.out"; d3_rc="$(run_d3 EXTERNAL-ROW-01 "${d3_external}")"
if [[ "${d3_rc}" == 0 ]] && grep -Fq 'row=internal-row-0001 verdict=alive rc=1' "${d3_external}"; then
  pass 'D3 external_id resolves the real backlog row'
else
  fail "D3 external_id resolution mismatch rc=${d3_rc}: $(tr '\n' ' ' < "${d3_external}")"
fi
d3_unknown="${TMP}/d3-unknown.out"; d3_unknown_rc="$(run_d3 GENUINELY-UNKNOWN-ROW "${d3_unknown}")"
if [[ "${d3_unknown_rc}" == 8 ]] && grep -Fq 'reason=backlog_row_not_found' "${d3_unknown}" \
  && grep -Fq 'searched keys: id, external_id, node_id, intent' "${d3_unknown}"; then
  pass 'D3 unknown id refuses and names searched keys'
else
  fail "D3 unknown refusal mismatch rc=${d3_unknown_rc}: $(tr '\n' ' ' < "${d3_unknown}")"
fi

printf '[DISPATCH-REFUSAL-TRUTH] pass=%d fail=%d\n' "${PASS}" "${FAIL}"
[[ "${FAIL}" -eq 0 ]]
