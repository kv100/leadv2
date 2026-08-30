#!/usr/bin/env bash
# Mutation: replace the dirty-lane downgrade assignment in
# dispatch_ledger_write_terminal with `terminal="landed"`.
set -euo pipefail
ROOT="${LEADV2_TEST_ROOT:-$(cd "$(dirname "$0")/../.." && pwd)}"
LEDGER="${ROOT}/scripts/leadv2-dispatch-ledger.sh"
T="$(mktemp -d)"; trap 'git -C "$T/main" worktree remove --force "$T/lane" >/dev/null 2>&1 || true; rm -rf "$T"' EXIT

git init -q "$T/main"
git -C "$T/main" config user.email t@e
git -C "$T/main" config user.name t
printf 'seed\n' > "$T/main/worker.txt"
git -C "$T/main" add worker.txt && git -C "$T/main" commit -qm seed
git -C "$T/main" worktree add -q -b lane "$T/lane" HEAD
mkdir -p "$T/main/docs/handoff/dispatch-abc12345" "$T/bin"
git -C "$T/main" status --porcelain --untracked-files=all | sed -E 's/^.. //; s/^"//; s/"$//' > "$T/main/docs/handoff/dispatch-abc12345/main-dirt.base"
cat > "$T/bin/leadv2-lane-worktree.sh" <<EOF
#!/usr/bin/env bash
[[ "\$1" == path-of ]] && printf '%s\n' "$T/lane"
EOF
chmod +x "$T/bin/leadv2-lane-worktree.sh"

source "$LEDGER"
SCRIPT_DIR="$T/bin"
PROJECT_ROOT="$T/main"
LEADV2_DISPATCH_TERMINAL_LEDGER_FILE="$T/ledger.jsonl"
JOURNAL_BIN=/nonexistent

last_row() { tail -n 1 "$LEADV2_DISPATCH_TERMINAL_LEDGER_FILE"; }
assert_last() { local terminal="$1" cause="$2" row; row="$(last_row)"; [[ "$row" == *"\"terminal\":\"${terminal}\""* && "$row" == *"\"cause\":\"${cause}"* ]]; }
write_terminal() { # Preserve the production CLI's non-errexit shell contract.
  local rc
  set +e
  dispatch_ledger_write_terminal "$@"
  rc=$?
  set -e
  [[ $rc -eq 0 ]]
}

# A tracked worker file makes a real linked worktree dirty; the actual terminal
# funnel must downgrade the persisted row, not merely contain the branch text.
printf 'dirty\n' >> "$T/lane/worker.txt"
write_terminal abc12345 TASK landed completed
assert_last pass_unlanded dirty_lane:completed

# Control-plane-only residue is explicitly excluded: otherwise every real lane is
# permanently dirty and no successful lane can land.
git -C "$T/lane" checkout -- worker.txt
git -C "$T/lane" diff --exit-code -- worker.txt
mkdir -p "$T/lane/docs/leadv2/tasks/dispatch-abc12345" "$T/lane/docs/handoff/dispatch-abc12345/phases.d"
touch "$T/lane/docs/leadv2/active.yaml" "$T/lane/docs/leadv2/active.yaml.lock" "$T/lane/docs/leadv2/bus.jsonl" \
  "$T/lane/docs/leadv2/.bus-offsets" "$T/lane/docs/leadv2/.bus.lock" "$T/lane/docs/leadv2/.merge.lock" \
  "$T/lane/docs/leadv2/merge-queue.jsonl" "$T/lane/docs/leadv2/questions" "$T/lane/docs/leadv2/open-threads.md" \
  "$T/lane/docs/leadv2/tasks/dispatch-abc12345/journal.md" "$T/lane/docs/handoff/dispatch-abc12345/phases.d/e2e.yaml" \
  "$T/lane/docs/LEAD_V2_STATE.md"
if lv2_lane_dirty "$T/lane"; then
  git -C "$T/lane" status --porcelain --untracked-files=all >&2
  echo 'control-plane-only lane was classified dirty' >&2
  exit 1
fi
write_terminal clean000 TASK landed completed
assert_last landed completed

# Bootstrap-only symlinks are injected lane setup residue, not worker dirt.
mkdir -p "$T/lane/.claude"
ln -s "$T/main/seed" "$T/lane/.claude/commands"
if lv2_lane_dirty "$T/lane"; then
  git -C "$T/lane" status --porcelain --untracked-files=all >&2
  echo 'bootstrap-symlink-only lane was classified dirty' >&2
  exit 1
fi
write_terminal bootstrap00 TASK landed completed
assert_last landed completed

# The function consumes actual prior downgrade rows for the same signature and
# must turn the next dirty completion into a final refusal rather than another retry.
printf '{"task_sig":"bound000","terminal":"pass_unlanded","cause":"dirty_lane:prior-1"}\n' > "$LEADV2_DISPATCH_TERMINAL_LEDGER_FILE"
printf '{"task_sig":"bound000","terminal":"pass_unlanded","cause":"dirty_lane:prior-2"}\n' >> "$LEADV2_DISPATCH_TERMINAL_LEDGER_FILE"
printf 'dirty\n' >> "$T/lane/worker.txt"
LEADV2_DIRTY_LANE_MAX_ATTEMPTS=2 write_terminal bound000 TASK landed completed
assert_last refused dirty_lane_retry_exhausted:completed
echo 'PASS: terminal funnel downgrades worker dirt, permits control-plane/bootstrap-only lanes, and bounds retries'
