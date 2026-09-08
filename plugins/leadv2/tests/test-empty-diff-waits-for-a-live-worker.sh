#!/usr/bin/env bash
# run-all-triggers: leadv2-dispatch-product-close
# Real close process + real delayed worker; only review and state writers are stubs.
set -uo pipefail
export LEADV2_TEST_CONTEXT=1
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PC="${HERE}/../scripts/leadv2-dispatch-product-close.sh"
T="$(mktemp -d /tmp/b4-empty-diff.XXXXXX)" || exit 2
PIDS=()
cleanup() {
  local pid
  for pid in "${PIDS[@]:-}"; do [[ -n "$pid" ]] && kill "$pid" 2>/dev/null || true; done
  for pid in "${PIDS[@]:-}"; do [[ -n "$pid" ]] && wait "$pid" 2>/dev/null || true; done
  rm -rf "$T"
}
trap cleanup EXIT
PASS=0; FAIL=0
assert_eq() {
  if [[ "$1" == "$2" ]]; then
    printf 'PASS %s: %s\n' "$3" "$1"; PASS=$((PASS + 1))
  else
    printf 'FAIL %s: got=%s expected=%s\n' "$3" "$1" "$2"; FAIL=$((FAIL + 1))
  fi
}
cat > "$T/ledger.sh" <<'STUB'
#!/usr/bin/env bash
if [[ "$1" == write-terminal ]]; then
  printf '%s\n' "$4" > "$B4_CASE/terminal"
  printf '%s\n' "$5" > "$B4_CASE/cause"
fi
STUB
cat > "$T/review.sh" <<'STUB'
#!/usr/bin/env bash
# Review must receive the late bytes, not merely be invoked.
while [[ $# -gt 0 ]]; do
  case "$1" in --diff) diff="$2"; shift 2 ;; *) shift ;; esac
done
grep -q 'late worker bytes' "$diff" || exit 7
printf 'reviewed\n' > "$B4_CASE/reviewed"
STUB
printf '#!/usr/bin/env bash\nexit 0\n' > "$T/noop.sh"

run_case() {
  local name="$1" arm="$2" mode="$3" d root handoff pid handle rc started elapsed worker_pid=
  d="$T/$name"; root="$d/repo"; handoff="$root/docs/handoff/dispatch-b4test"
  mkdir -p "$handoff" "$d/claude-runs/run"
  printf "run\n" > "$handoff/.claude-session-runner.run-id"
  git -C "$root" init -q -b main
  git -C "$root" config user.email b4@test.invalid
  git -C "$root" config user.name B4
  printf 'seed\n' > "$root/work.txt"
  git -C "$root" add work.txt
  git -C "$root" commit -qm seed
  if [[ "$mode" == live || "$mode" == heartbeat || "$mode" == finalizer ]]; then
    # The historical fable path has NO wait window: it exits on the first probe.
    # Six seconds exceeds that immediate evaluation; continuing heartbeats model
    # an arbitrarily long Bash/think before the first byte of deliverable exists.
    (
      for n in 1 2 3 4 5 6; do
        printf '{"type":"tool_progress","elapsed_time_seconds":%s}\n' "$n" >> "$handoff/developer.stream.jsonl"
        sleep 1
      done
      printf 'late worker bytes\n' >> "$root/work.txt"
      touch "$d/claude-runs/run/.finalized"
    ) &
    pid=$!; worker_pid="$pid"; PIDS+=("$pid")
  else
    (exit 0) & pid=$!; wait "$pid"
  fi
  if [[ "$mode" == finalizer ]]; then
    printf '%s\n' "$pid" > "$d/claude-runs/run/finalizer_pid"
    (exit 0) & pid=$!; wait "$pid"
  fi
  printf "%s\n" "$pid" > "$d/claude-runs/run/pid"
  [[ -z "$worker_pid" ]] && touch "$d/claude-runs/run/.finalized"
  handle="PID=$pid LABEL=developer-b4 SESSION_ID=test STREAM=$handoff/developer.stream.jsonl"
  [[ "$mode" == numeric ]] && handle="$pid"
  if [[ "$mode" == heartbeat || "$mode" == stale ]]; then
    handle="PID=unknown LABEL=developer-b4 STREAM=$handoff/developer.stream.jsonl"
  fi
  if [[ "$mode" == stale ]]; then
    printf '{"type":"tool_progress","elapsed_time_seconds":300}\n' > "$handoff/developer.stream.jsonl"
    touch -t 200001010000 "$handoff/developer.stream.jsonl"
  fi
  started=$SECONDS
  B4_CASE="$d" CLAUDE_PROJECT_ROOT="$root" LEADV2_PROJECT_ROOT="$root" \
    LEADV2_CANONICAL_ROOT="$root" LEADV2_EVENT_LOG_DIR="$d/events" \
    LEADV2_DISPATCH_CACHE_DIR="$d/cache" LEADV2_PC_RUNS_ROOT="$d/runs" \
    LEADV2_CLAUDE_RUNS_DIR="$d/claude-runs" LEADV2_JOB_REGISTRY_ROOT="$d/jobs" \
    LEADV2_LANE_WORK_ROOT="$root" LEADV2_DISPATCH_LANE_WRITES=work.txt \
    LEADV2_JOURNAL_BIN="$T/noop.sh" LEADV2_DISPATCH_LEDGER_BIN="$T/ledger.sh" \
    LEADV2_REVIEW_ENGINE=1 LEADV2_REVIEW_RUN_BIN="$T/review.sh" \
    LEADV2_PC_CLAUDE_STREAM_STALE_S=2 \
    LEADV2_PC_WORKER_POLL_S=1 LEADV2_PC_WORKER_MAX_WAIT_S=12 \
    LEADV2_BUILDER_SELFCHECK=0 LEADV2_PC_DWR_RESUME=0 \
    timeout 25 bash "$PC" "$root" b4test "$arm" "$handle" 0 1 > "$d/close.log" 2>&1
  rc=$?; elapsed=$((SECONDS - started))
  if [[ "$mode" == live || "$mode" == heartbeat || "$mode" == finalizer ]]; then
    wait "$worker_pid" || true
    assert_eq "$(cat "$d/terminal" 2>/dev/null || echo absent)" landed "$name terminal value"
    assert_eq "$(cat "$d/reviewed" 2>/dev/null || echo absent)" reviewed "$name late bytes reached review"
    assert_eq "$rc" 0 "$name close rc"
  else
    assert_eq "$(cat "$d/terminal" 2>/dev/null || echo absent)" no_work "$name terminal value"
    assert_eq "$(cat "$d/cause" 2>/dev/null || echo absent)" empty_diff "$name cause"
    assert_eq "$rc" 5 "$name close rc"
    if (( elapsed < 12 )); then assert_eq prompt prompt "$name exited promptly (${elapsed}s)";
    else assert_eq "${elapsed}s" '<12s' "$name exited promptly"; fi
  fi
  PIDS=()
  if [[ "$rc" != 0 && "$rc" != 5 ]]; then tail -5 "$d/close.log"; fi
}
run_case fable_late fable live
run_case fable_exited fable dead
run_case fable_heartbeat_only fable heartbeat
run_case fable_stale_heartbeat fable stale
run_case fable_finalizer fable finalizer
run_case sonnet_raw_handle sonnet live
run_case haiku_exited haiku dead
run_case opus_exited opus dead
run_case sonnet_numeric_compat sonnet numeric
printf 'RESULT pass=%s fail=%s\n' "$PASS" "$FAIL"
(( FAIL == 0 ))
