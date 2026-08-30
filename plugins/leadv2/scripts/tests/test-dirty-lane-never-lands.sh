#!/usr/bin/env bash
# Mutation: replace the dirty-lane downgrade assignment in
# dispatch_ledger_write_terminal with `terminal="landed"`.
set -euo pipefail
ROOT="${LEADV2_TEST_ROOT:-$(cd "$(dirname "$0")/../.." && pwd)}"
LEDGER="${LEADV2_DIRTY_LANE_LEDGER:-${ROOT}/scripts/leadv2-dispatch-ledger.sh}"
LANE_GUARD="${ROOT}/scripts/lib/leadv2-lane-guard.sh"
T="$(mktemp -d)"
cleanup() { local rc=$?; git -C "$T/main" worktree remove --force "$T/lane" >/dev/null 2>&1 || true; rm -rf "$T"; exit "$rc"; }
trap cleanup EXIT

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

# The live macOS interpreter is bash 3.2. Under set -u an empty input must
# leave the guard clean, not abort its command-substitution caller and turn all
# worker dirt into an empty status value.
/bin/bash -c 'set -uo pipefail; source "$1"; printf "" | _pc_drop_bootstrap_dirt "$2"' _ "$LANE_GUARD" "$T/lane" >/dev/null

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

# H7-2: a consumer has the ledger link but neither local lib/ nor canonical
# guard.  The live terminal funnel must emit its named fail-closed message and
# downgrade a dirty lane; it must never persist landed in silence.
mkdir -p "$T/consumer"
ln -s "$LEDGER" "$T/consumer/leadv2-dispatch-ledger.sh"
ln -s "$ROOT/scripts/leadv2-portable-lock.sh" "$T/consumer/leadv2-portable-lock.sh"
ln -s "$T/bin/leadv2-lane-worktree.sh" "$T/consumer/leadv2-lane-worktree.sh"
printf 'still dirty\n' >> "$T/lane/worker.txt"
: > "$LEADV2_DISPATCH_TERMINAL_LEDGER_FILE"
LEADV2_CANONICAL_ROOT="$T/no-canonical" source "$T/consumer/leadv2-dispatch-ledger.sh" 2>"$T/missing-guard.err"
SCRIPT_DIR="$T/consumer"
PROJECT_ROOT="$T/main"
write_terminal missinglib TASK landed completed
assert_last pass_unlanded dirty_lane:completed
if ! grep -Fq 'lane guard unavailable' "$T/missing-guard.err"; then
  echo 'missing guard did not emit its named fail-closed error' >&2
  exit 1
fi
if grep -Fq '"terminal":"landed"' "$LEADV2_DISPATCH_TERMINAL_LEDGER_FILE"; then
  echo 'missing guard let a dirty lane record landed' >&2
  exit 1
fi
source "$LEDGER"
SCRIPT_DIR="$T/bin"
PROJECT_ROOT="$T/main"
git -C "$T/lane" checkout -- worker.txt

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
# Exercise the actual CLOSE gate before the helper assertion below, so the
# negative control proves the executable's live symbol lookup is not shadowed.
mkdir -p "$T/close-cache"
printf '#!/usr/bin/env python3\nprint("reviewer=codex")\nprint("pool=codex")\nprint("refusal=")\n' > "$T/close-cache/resolver.py"
printf '#!/usr/bin/env bash\nprintf "REVIEW_VERDICT: PASS\\nREVIEW_FINDINGS: critical=0 high=0 medium=0 low=0\\n"\n' > "$T/close-cache/codex.sh"
chmod +x "$T/close-cache/resolver.py" "$T/close-cache/codex.sh"
set +e
CLAUDE_PROJECT_ROOT="$T/main" LEADV2_DISPATCH_CACHE_DIR="$T/close-cache/cache" \
LEADV2_DISPATCH_LANE_WRITES="worker.txt" LEADV2_LANE_WORK_ROOT="$T/lane" \
LEADV2_GLM_POLICY_RESOLVER="$T/close-cache/resolver.py" LEADV2_DISPATCH_CODEX_BIN="$T/close-cache/codex.sh" \
bash "$ROOT/scripts/leadv2-dispatch-product-close.sh" "$T/main" closeboot sonnet '' 0 1 TASK >"$T/close.out" 2>&1
close_rc=$?
set -e
[[ $close_rc -eq 5 ]] # no product diff is expected; the gate still wrote its verdict
if grep -Fq 'reason: unscoped_lane_work' "$T/main/docs/handoff/dispatch-closeboot/review-gate.md"; then
  echo 'bootstrap-symlink-only lane was classified as unscoped work' >&2
  exit 1
fi
if lv2_lane_dirty "$T/lane"; then
  git -C "$T/lane" status --porcelain --untracked-files=all >&2
  echo 'bootstrap-symlink-only lane was classified dirty' >&2
  exit 1
fi
write_terminal bootstrap00 TASK landed completed
assert_last landed completed

# A pass_unlanded is a human-action state, not a transitive retry path.  A later
# refused or landed write for the same signature is a successful no-op.
printf '{"task_sig":"bound000","terminal":"pass_unlanded","cause":"dirty_lane:prior-1"}\n' > "$LEADV2_DISPATCH_TERMINAL_LEDGER_FILE"
printf 'dirty\n' >> "$T/lane/worker.txt"
LEADV2_DIRTY_LANE_MAX_ATTEMPTS=2 write_terminal bound000 TASK landed completed
assert_last pass_unlanded dirty_lane:prior-1

# N3 (review-r5.md): the pass_unlanded exception must be non-transitive across
# THE WHOLE sig8 history, not just the immediately-preceding row. A prior
# probe on an earlier commit found pass_unlanded -> refused -> landed slipping
# a landed row in, because a naive fix only re-checks the LAST row and refused
# is retryable. Drive the exact three-attempt chain the reviewer probed and
# assert the row never advances past pass_unlanded at any hop.
: > "$LEADV2_DISPATCH_TERMINAL_LEDGER_FILE"
write_terminal chain0001 TASK pass_unlanded prior-chain '' chain-attempt-1
assert_last pass_unlanded prior-chain
write_terminal chain0001 TASK refused retry-chain '' chain-attempt-2
assert_last pass_unlanded prior-chain
write_terminal chain0001 TASK landed completed '' chain-attempt-3
assert_last pass_unlanded prior-chain

# H-1/H-2 (DISPATCH-PIN-CLUSTER-01 round 7): dispatch_terminal_exists() must agree
# that a pass_unlanded-only sig8 has finished, or the deferred-retry readers in
# leadv2-dispatch-code.sh never see it as done, fall through to retry, and every
# terminal that retry could produce is exit-2'd by the write gate above -- the
# sig8 can be re-dispatched forever and can never actually terminate in the
# ledger. No suite asserted this rc before this round.
if ! dispatch_terminal_exists chain0001; then
  echo 'dispatch_terminal_exists rc1 for a pass_unlanded-only sig8 -- H-1 regression' >&2
  exit 1
fi
if dispatch_terminal_exists never-seen-sig8; then
  echo 'dispatch_terminal_exists rc0 for a sig8 with no ledger row at all' >&2
  exit 1
fi

# A killed worker is not plain `dead` when its pinned lane still carries
# uncommitted worker-owned bytes. Exercise the sweep writer itself (not a
# synthetic ledger append) through the same lane-worktree lookup used by cmd_sweep.
: > "$LEADV2_DISPATCH_TERMINAL_LEDGER_FILE"
printf 'dirty after worker death\n' >> "$T/lane/worker.txt"
dispatch_ledger_sweep_write_dead sweep000 TASK swept 'verdict=dead:no_log_artifact' attempt-sweep-1
assert_last dead_with_unlanded_work swept
if grep -F '"task_sig":"sweep000"' "$LEADV2_DISPATCH_TERMINAL_LEDGER_FILE" | grep -Fq '"terminal":"dead"'; then
  echo 'sweep recorded plain dead for dirty worker lane' >&2
  exit 1
fi
# N2: a later landed write cannot erase the dirty-death pin.
write_terminal sweep000 TASK landed completed
assert_last dead_with_unlanded_work swept

# N5: the documented terminal-ledger rollback switch also disables the sweep writer.
: > "$LEADV2_DISPATCH_TERMINAL_LEDGER_FILE"
LEADV2_DISPATCH_TERMINAL_LEDGER=0 dispatch_ledger_sweep_write_dead disabled0 TASK swept disabled attempt-disabled
[[ ! -s "$LEADV2_DISPATCH_TERMINAL_LEDGER_FILE" ]]
echo 'PASS: terminal funnel and CLOSE gate downgrade worker dirt, preserve the dirty-death pin, keep pass_unlanded non-transitive, honor the rollback switch, and permit bootstrap-only lanes'
