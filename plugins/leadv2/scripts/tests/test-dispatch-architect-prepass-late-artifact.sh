#!/usr/bin/env bash
# ARCHITECT-PREPASS-ORPHAN-01 (D1): a prepass whose artifact exists must never be
# treated as a failure, even when the launcher rc is non-zero and the artifact
# write completes a beat AFTER the launcher itself returns control (observed live:
# lane 75d151fe -- subsession terminal_reason=completed/subtype=success, a complete
# architect.full.md on disk, yet "architect_prepass status=failed reason=failed_rc_1"
# parked the lane). The fake architect binary below reproduces the exact mechanism:
# it backgrounds the artifact write (detached from its own stdout/stderr so it does
# not hold the launcher pipe open), then exits 1 immediately -- so dispatch-code.sh
# reads the candidate files before the write has landed on disk unless it polls.
set -uo pipefail

ROOT="$(mktemp -d)"; trap 'rm -rf "$ROOT"' EXIT
REPO="$ROOT/repo"; mkdir -p "$REPO/.claude/ref" "$REPO/docs/leadv2/.bus-offsets"
(cd "$REPO" && git init -q && git config user.email test@example.com && git config user.name test && : > seed && git add seed && git commit -qm seed)
printf 'router:\n  glm_policy:\n    sonnet_exceptions: [safety_gate_publish_payments]\n    opus_only_mission_kinds: []\n    codex_fitting_mission_kinds: []\n' > "$REPO/.claude/ref/leadv2-routing.yaml"
WORKER="$ROOT/worker"; ARCH="$ROOT/architect"
printf '#!/usr/bin/env bash\nnohup sleep 60 >/dev/null 2>&1 &\nprintf "PID=%%s LABEL=test SESSION_ID=test\\n" "$!"\n' > "$WORKER"
cat > "$ARCH" <<'EOF'
#!/usr/bin/env bash
task_id=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --task-id) task_id="$2"; shift 2;;
    *) shift;;
  esac
done
adir="${PROJECT_ROOT}/docs/handoff/${task_id}"
mkdir -p "$adir"
( sleep 0.6
  cat > "$adir/architect.full.md" <<'DESIGN'
# Design
changes: a.txt, b.txt, c.txt
acceptance:
  surface: file_artifact
  observable: file exists
  authored_at: 2026-08-07T00:00:00Z
LANE_WRITES: a.txt,b.txt,c.txt
DELIVERABLE_COMPLETE
DESIGN
) </dev/null >/dev/null 2>&1 &
disown 2>/dev/null || true
exit 1
EOF
chmod +x "$WORKER" "$ARCH"
DISPATCH="$(cd "$(dirname "$0")/.." && pwd)/leadv2-dispatch-code.sh"
# FOREIGN-PROJECT-ROOT-GUARD-01 default-on (dispatch-b4042501-review, blocker 2):
# cd into $REPO before invoking dispatch, like every other fixture that `git
# init`s its own throwaway repo -- otherwise cwd's git toplevel is this suite's
# OWN checkout, the guard sees a genuine env/cwd mismatch, and PROJECT_ROOT gets
# silently rerooted onto the real checkout instead of the fixture's $REPO.
( cd "$REPO" && \
LEADV2_DISPATCH_ARCHITECT_GATE=1 \
CLAUDE_PROJECT_ROOT="$REPO" LEADV2_PROJECT_ROOT="$REPO" LEADV2_DISPATCH_CACHE_DIR="$ROOT/cache" \
LEADV2_DISPATCH_SUBSESSION_BIN="$WORKER" LEADV2_DISPATCH_ARCHITECT_BIN="$ARCH" \
LEADV2_DISPATCH_ARCHITECT_TIMEOUT_SEC=10 LEADV2_DISPATCH_E2E_GATE=0 LEADV2_DISPATCH_REVIEW_GATE=0 \
LEADV2_ROUTER_V2=0 LEADV2_EXCLUDED_ARMS=__none__ LEADV2_LANE_SHAPE=off \
  bash "$DISPATCH" 'test D1 artifact lands after launcher rc returns' --kind product --protected --writes "a.txt,b.txt,c.txt" >"$ROOT/out.log" 2>&1 )
rc=$?

grep -q 'architect_prepass task=.* status=ran' "$ROOT/out.log" || {
  echo "FAIL a design that landed on disk a beat late was not accepted as ran:"
  cat "$ROOT/out.log"
  exit 1
}
grep -q 'reason=failed_rc_1' "$ROOT/out.log" && {
  echo "FAIL the late-landing artifact was still classified as a failed_rc_1 prepass failure:"
  cat "$ROOT/out.log"
  exit 1
}
grep -q 'worker_spawned' "$ROOT/out.log" || {
  echo "FAIL product task never reached worker_spawned despite a valid design existing on disk:"
  cat "$ROOT/out.log"
  exit 1
}
echo 'PASS: architect_prepass polls briefly for a late-landing artifact instead of racing a single stat (ARCHITECT-PREPASS-ORPHAN-01 D1)'
