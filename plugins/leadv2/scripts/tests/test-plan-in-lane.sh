#!/usr/bin/env bash
# changed-scope triggers, self-registered (SD-SUITE-MAP-SERIALIZES-EVERY-WAVE-01, migrated from tests/run-all.sh EXTRA_SUITE_MAP; discovered by scan_suite_triggers):
# run-all-triggers: leadv2-dispatch-code
# Mutation: replace `_deliver_plan_into_lane`'s loud refusal with `return 0`.
set -euo pipefail
ROOT="${LEADV2_TEST_ROOT:-$(cd "$(dirname "$0")/../.." && pwd)}"
DISPATCH="${ROOT}/scripts/leadv2-dispatch-code.sh"
T="$(mktemp -d)"
cleanup() { local rc=$?; git -C "$T/main" worktree remove --force "$T/lane" >/dev/null 2>&1 || true; rm -rf "$T"; exit "$rc"; }
trap cleanup EXIT

git init -q "$T/main"
git -C "$T/main" config user.email t@e
git -C "$T/main" config user.name t
touch "$T/main/seed"; git -C "$T/main" add seed && git -C "$T/main" commit -qm seed
git -C "$T/main" worktree add -q -b lane "$T/lane" HEAD

# Extract and source the real production function only: dispatch-code is a CLI
# executor, while its lower-level collaborators (emit/_dl_note) are faked below.
python3 - "$DISPATCH" "$T/deliver-plan.sh" <<'PY'
import sys
s = open(sys.argv[1]).read()
start = s.index('_deliver_plan_into_lane() {')
end = s.index('\n}\n', start) + 3
open(sys.argv[2], 'w').write(s[start:end])
PY
source "$T/deliver-plan.sh"
emit() { printf '%s %s\n' "$1" "$2" >> "$T/journal"; }
_dl_note() { :; }

mkdir -p "$T/main/docs/handoff/TASK"
printf 'task_id: TASK\n' > "$T/main/docs/handoff/TASK/context.yaml"
printf 'brief\n' > "$T/main/docs/handoff/TASK/brief.md"
printf 'architecture\n' > "$T/main/docs/handoff/TASK/plan-architect.md"
PROJECT_ROOT="$T/main"; WORK_ROOT="$T/lane"; LANE_LOCAL_PLAN_LINE=""
_deliver_plan_into_lane abc12345 TASK
[[ -f "$T/lane/docs/handoff/TASK/context.yaml" ]]
cmp -s "$T/main/docs/handoff/TASK/context.yaml" "$T/lane/docs/handoff/TASK/context.yaml"
cmp -s "$T/main/docs/handoff/TASK/plan-architect.md" "$T/lane/docs/handoff/TASK/plan-architect.md"
[[ "$LANE_LOCAL_PLAN_LINE" == *"$T/lane/docs/handoff/TASK/context.yaml"* ]]
[[ "$LANE_PLAN_DELIVERY_STATUS" == "delivered" ]]

# Make the destination structurally impossible; the real function must refuse
# with rc=5 and journal lane_plan_missing.
rm -rf "$T/lane/docs"
mkdir -p "$T/lane/docs"
touch "$T/lane/docs/handoff"
set +e
( PROJECT_ROOT="$T/main"; WORK_ROOT="$T/lane"; _deliver_plan_into_lane abc12345 TASK )
rc=$?
set -e
[[ $rc -eq 5 ]]
grep -Fq 'lane_plan_missing task=abc12345' "$T/journal"

# A call after placement resolution must never silently accept an unset root.
set +e
( PROJECT_ROOT="$T/main"; unset WORK_ROOT; _deliver_plan_into_lane abc12345 TASK )
rc=$?
set -e
[[ $rc -eq 5 ]]
grep -Fq 'reason=work_root_unset' "$T/journal"

# A real lane must not be created and then silently receive no plan because the
# founder id was lost between placement and delivery.
set +e
( PROJECT_ROOT="$T/main"; WORK_ROOT="$T/lane"; _deliver_plan_into_lane abc12345 '' )
rc=$?
set -e
[[ $rc -eq 5 ]]
grep -Fq 'lane_plan_missing task=abc12345 reason=task_id_unset' "$T/journal"

# Shared-tree dispatches are intentionally no-ops: no lane instruction is set.
LANE_LOCAL_PLAN_LINE=""
PROJECT_ROOT="$T/main"; WORK_ROOT="$T/main"
_deliver_plan_into_lane abc12345 TASK
[[ -z "$LANE_LOCAL_PLAN_LINE" ]]
[[ "$LANE_PLAN_DELIVERY_STATUS" == "not_required" ]]
grep -Fq 'lane_plan_skipped task=abc12345 reason=shared_tree' "$T/journal"

# DISPATCH-SPAWNS-INTO-A-TREE-WITHOUT-ITS-MISSION-01. A lane worktree is a fresh
# checkout of a commit, and the mission text it is spawned with names paths under
# docs/handoff/<TASK-ID>/. When context.yaml is absent this delivery used to
# return having copied NOTHING -- so the brief the mission points at was absent
# too, and the round died looking like the arm's fault (measured 2026-09-05 on
# task 11b25531: worker alive 34s, outcome no_work cause=arm_produced_nothing).
#
# The FIX is delivery, not refusal: the mission itself reaches every arm BY VALUE
# (glm/kimi take "${mission}" inline; the sonnet path writes it to a temp file
# first), so an untracked or context-less task dir is no reason to refuse a spawn.
#
# Pair, and the second half is the one that matters: carrying siblings must not
# have turned source_absent into a delivery.
mkdir -p "$T/main/docs/handoff/NOCTX"
printf 'the brief\n' > "$T/main/docs/handoff/NOCTX/brief.md"
printf 'the design\n' > "$T/main/docs/handoff/NOCTX/plan-architect.md"
rm -rf "$T/lane2"
LANE_LOCAL_PLAN_LINE=""; LANE_PLAN_DELIVERY_STATUS=""
PROJECT_ROOT="$T/main"; WORK_ROOT="$T/lane2"
_deliver_plan_into_lane abc12345 NOCTX
[[ -f "$T/lane2/docs/handoff/NOCTX/brief.md" ]]
[[ -f "$T/lane2/docs/handoff/NOCTX/plan-architect.md" ]]
cmp -s "$T/main/docs/handoff/NOCTX/brief.md" "$T/lane2/docs/handoff/NOCTX/brief.md"
grep -Fq 'lane_plan_missing task=abc12345 reason=source_absent' "$T/journal"
grep -Fq 'carried_siblings=2' "$T/journal"
# still a skip, NOT a delivery: no lane plan instruction, status unchanged
[[ "$LANE_PLAN_DELIVERY_STATUS" == "source_absent" ]]
[[ -z "$LANE_LOCAL_PLAN_LINE" ]]
[[ ! -f "$T/lane2/docs/handoff/NOCTX/context.yaml" ]]

# Paired negative: a task dir that does not exist at all must still be a plain
# source_absent with nothing carried, and must not conjure a lane directory.
rm -rf "$T/lane3"
LANE_PLAN_DELIVERY_STATUS=""
PROJECT_ROOT="$T/main"; WORK_ROOT="$T/lane3"
_deliver_plan_into_lane abc12345 GHOST
[[ "$LANE_PLAN_DELIVERY_STATUS" == "source_absent" ]]
grep -Fq 'carried_siblings=0' "$T/journal"
[[ ! -d "$T/lane3/docs/handoff/GHOST" ]]

echo 'PASS: real plan delivery copies context, brief, and plan files into a lane; missing bindings refuse loudly; a context-less task dir still carries its brief into the lane'
