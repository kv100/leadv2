#!/usr/bin/env bash
# Mutation: replace the non-excluded-path `return 0` in
# lv2_lane_containment_violation with `return 1`.
set -euo pipefail
ROOT="${LEADV2_TEST_ROOT:-$(cd "$(dirname "$0")/../.." && pwd)}"
LIB="${ROOT}/scripts/lib/leadv2-lane-guard.sh"
T="$(mktemp -d)"; trap 'git -C "$T/main" worktree remove --force "$T/lane" >/dev/null 2>&1 || true; rm -rf "$T"' EXIT

git init -q "$T/main"
git -C "$T/main" config user.email t@e
git -C "$T/main" config user.name t
touch "$T/main/seed"; git -C "$T/main" add seed && git -C "$T/main" commit -qm seed
git -C "$T/main" worktree add -q -b lane "$T/lane" HEAD
mkdir -p "$T/main/docs/handoff/dispatch-abc12345"
git -C "$T/main" status --porcelain --untracked-files=all | sed -E 's/^.. //; s/^"//; s/"$//' > "$T/main/docs/handoff/dispatch-abc12345/main-dirt.base"
source "$LIB"

# A post-baseline write in the main checkout is a real containment violation.
printf 'escape\n' > "$T/main/outside-lane.txt"
lv2_lane_containment_violation abc12345 "$T/lane" "$T/main"
rm "$T/main/outside-lane.txt"

# Every observed control-plane residue is excluded.  A false positive here would
# make every lane dirty and refuse all landings.
mkdir -p "$T/main/docs/leadv2/tasks/dispatch-abc12345" "$T/main/docs/handoff/dispatch-abc12345/phases.d"
touch "$T/main/docs/leadv2/active.yaml" "$T/main/docs/leadv2/active.yaml.lock" "$T/main/docs/leadv2/bus.jsonl" \
  "$T/main/docs/leadv2/.bus-offsets" "$T/main/docs/leadv2/.bus.lock" "$T/main/docs/leadv2/.merge.lock" \
  "$T/main/docs/leadv2/merge-queue.jsonl" "$T/main/docs/leadv2/questions" "$T/main/docs/leadv2/open-threads.md" \
  "$T/main/docs/leadv2/tasks/dispatch-abc12345/journal.md" "$T/main/docs/handoff/dispatch-abc12345/phases.d/review.yaml" \
  "$T/main/docs/LEAD_V2_STATE.md"
if lv2_lane_containment_violation abc12345 "$T/lane" "$T/main"; then
  echo 'control-plane residue falsely reported as containment violation' >&2
  exit 1
fi
echo 'PASS: real main-checkout write violates containment; the complete observed control-plane residue set does not'
