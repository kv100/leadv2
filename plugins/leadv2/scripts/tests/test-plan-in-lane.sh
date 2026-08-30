#!/usr/bin/env bash
# Mutation: replace `_deliver_plan_into_lane`'s `exit 5` with `return 0`.
set -euo pipefail
ROOT="${LEADV2_TEST_ROOT:-$(cd "$(dirname "$0")/../.." && pwd)}"
DISPATCH="${ROOT}/scripts/leadv2-dispatch-code.sh"
T="$(mktemp -d)"; trap 'git -C "$T/main" worktree remove --force "$T/lane" >/dev/null 2>&1 || true; rm -rf "$T"' EXIT

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
PROJECT_ROOT="$T/main"; WORK_ROOT="$T/lane"; LANE_LOCAL_PLAN_LINE=""
_deliver_plan_into_lane abc12345 TASK
[[ -f "$T/lane/docs/handoff/TASK/context.yaml" ]]
cmp -s "$T/main/docs/handoff/TASK/context.yaml" "$T/lane/docs/handoff/TASK/context.yaml"
[[ "$LANE_LOCAL_PLAN_LINE" == *"$T/lane/docs/handoff/TASK/context.yaml"* ]]

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

# Shared-tree dispatches are intentionally no-ops: no lane instruction is set.
LANE_LOCAL_PLAN_LINE=""
PROJECT_ROOT="$T/main"; WORK_ROOT="$T/main"
_deliver_plan_into_lane abc12345 TASK
[[ -z "$LANE_LOCAL_PLAN_LINE" ]]
echo 'PASS: real plan delivery copies into a lane, refuses/journals an impossible copy, and no-ops in the shared tree'
