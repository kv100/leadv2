#!/usr/bin/env bash
# test-codex-broker-staleness.sh — CODEX-DETACH-01
#
# Root cause (established live, not from reading code): three sol workers
# died within 1-3 min each because ~/.claude/plugins/data/codex-openai-codex/
# state/<task>/broker.json named a broker process that no longer existed,
# whose sessionDir under /var/folders/.../T had been swept by the OS. Every
# new worker attached to that corpse and died. This was never a timeout.
#
# Extracts (does not source-and-run the whole wrapper) the pure helper
# functions _codex_broker_state_dir / _codex_validate_broker from
# codex-task.sh and unit-tests them against a FIXTURE state root — never
# ~/.claude/plugins/data/. A tiny stub "companion" simulates the two
# observable outcomes: attaching to a stale broker (task dies) vs raising a
# fresh one after a stale record was moved aside (task completes).

set -euo pipefail

export LEADV2_BURN_GOVERNOR=0

_src="${BASH_SOURCE[0]}"
while [ -L "$_src" ]; do
  _dir="$(cd -P "$(dirname "$_src")" && pwd)"
  _src="$(readlink "$_src")"
  case "$_src" in /*) ;; *) _src="$_dir/$_src" ;; esac
done
TEST_DIR="$(cd -P "$(dirname "$_src")" && pwd)"
unset _src _dir
CODEX_TASK="$TEST_DIR/../codex-task.sh"

pass=0
fail=0
cleanup_items=()
cleanup_pids=()
cleanup() {
  for pid in "${cleanup_pids[@]:-}"; do
    [ -n "$pid" ] && kill "$pid" 2>/dev/null || true
    [ -n "$pid" ] && wait "$pid" 2>/dev/null || true
  done
  for item in "${cleanup_items[@]:-}"; do
    rm -rf "$item" 2>/dev/null || true
  done
}
trap cleanup EXIT

harness="$(mktemp -d)"
cleanup_items+=("$harness")
harness_script="$harness/harness.sh"
{
  echo '#!/usr/bin/env bash'
  echo 'set +e'
  sed -n '/^_codex_broker_state_dir()/,/^}$/p' "$CODEX_TASK"
  sed -n '/^_codex_validate_broker()/,/^}$/p' "$CODEX_TASK"
  echo '"$@"'
} > "$harness_script"
chmod +x "$harness_script"

check_extracted() {
  local fn="$1"
  if ! grep -q "^${fn}()" "$harness_script"; then
    echo "[CODEX-BROKER-STALENESS] FAIL: ${fn} not found in ${CODEX_TASK} (extraction broke, or fn renamed)" >&2
    fail=$((fail + 1))
    return 1
  fi
  return 0
}
check_extracted "_codex_broker_state_dir" || true
check_extracted "_codex_validate_broker" || true

# Same slug+hash formula as the companion's own resolveStateDir() (state.mjs)
# -- used ONLY to compute where the fixture's broker.json must live so the
# extracted function finds it; never used to touch the companion itself.
state_dir_for() {
  python3 - "$1" <<'PY'
import hashlib, os, re, sys
root = os.path.realpath(sys.argv[1])
slug_source = os.path.basename(sys.argv[1].rstrip("/")) or "workspace"
slug = re.sub(r"[^a-zA-Z0-9._-]+", "-", slug_source).strip("-") or "workspace"
digest = hashlib.sha256(root.encode()).hexdigest()[:16]
print(f"{slug}-{digest}")
PY
}

# $1=repo(cwd) $2=state_root $3=pid $4=sessionDir(existing path, or "" to omit)
write_broker() {
  local repo="$1" state_root="$2" pid="$3" sessdir="$4"
  local sd; sd="$(state_dir_for "$repo")"
  mkdir -p "$state_root/$sd"
  if [ -n "$sessdir" ]; then
    printf '{"endpoint":"unix:%s/broker.sock","pidFile":"%s/broker.pid","logFile":"%s/broker.log","sessionDir":"%s","pid":%s}\n' \
      "$sessdir" "$sessdir" "$sessdir" "$sessdir" "$pid" > "$state_root/$sd/broker.json"
  else
    printf '{"endpoint":"unix:/nowhere/broker.sock","pidFile":"/nowhere/broker.pid","logFile":"/nowhere/broker.log","sessionDir":"/nowhere/does-not-exist","pid":%s}\n' \
      "$pid" > "$state_root/$sd/broker.json"
  fi
}

# Simulates what a real companion-driven task attempt observes AFTER our
# validation ran: if broker.json is still present it "attaches" to whatever
# is there (dies if that pid/sessionDir combo is dead — exactly today's
# incident); if broker.json is absent it raises a fresh one and completes.
stub_companion_attempt() {
  local repo="$1" state_root="$2"
  local sd; sd="$(state_dir_for "$repo")"
  local broker="$state_root/$sd/broker.json"
  if [ -f "$broker" ]; then
    echo "died:attached_to_existing_broker"
    return 1
  fi
  local fresh_sess="$state_root/$sd/fresh-session"
  mkdir -p "$fresh_sess"
  printf '{"endpoint":"unix:%s/broker.sock","pidFile":"%s/broker.pid","logFile":"%s/broker.log","sessionDir":"%s","pid":%s}\n' \
    "$fresh_sess" "$fresh_sess" "$fresh_sess" "$fresh_sess" "$$" > "$broker"
  echo "completed:fresh_broker_raised"
  return 0
}

run_case() {
  local label="$1" repo="$2" state_root="$3"
  CODEX_REAP_STATE_ROOT="$state_root" bash "$harness_script" _codex_validate_broker "$repo" >"$harness/${label}.validate.out" 2>&1
}

# --- Case 1 (acceptance test) ------------------------------------------
# Kill a live broker AND delete its sessionDir, then attempt a task: with
# validation in place it must self-heal (fresh broker, task completes).
repo1="$(mktemp -d)"; cleanup_items+=("$repo1")
git -C "$repo1" init -q
state1="$(mktemp -d)"; cleanup_items+=("$state1")
sess1="$(mktemp -d)"; cleanup_items+=("$sess1")
dead_pid=99999   # astronomically unlikely to be a live pid on any host
write_broker "$repo1" "$state1" "$dead_pid" "$sess1"
rm -rf "$sess1"   # OS swept the sessionDir

echo "[CODEX-BROKER-STALENESS] case 1: dead pid + swept sessionDir -> self-heals to completion"
run_case case1 "$repo1" "$state1"
result1="$(stub_companion_attempt "$repo1" "$state1")" || true
sd1="$(state_dir_for "$repo1")"
stale_count1=$(find "$state1/$sd1" -maxdepth 1 -name 'broker.json.stale-*' 2>/dev/null | wc -l | tr -d ' ')
if [ "$result1" = "completed:fresh_broker_raised" ] && [ "$stale_count1" -ge 1 ]; then
  echo "[CODEX-BROKER-STALENESS]   stale broker moved aside, task self-healed to completion ✓"
  pass=$((pass + 1))
else
  echo "[CODEX-BROKER-STALENESS]   FAIL: expected self-heal completion, got result='$result1' stale_count=$stale_count1" >&2
  cat "$harness/case1.validate.out" >&2 || true
  fail=$((fail + 1))
fi

# --- Case 1b (acceptance test, pid-reuse variant) -----------------------
# A LIVE pid (a real short-lived process this test controls) paired with a
# SWEPT sessionDir -- the case the brief singled out: a pid the OS reused
# for an unrelated live process must not let a pid-only check wave the
# worker onto the stale broker's corpse. sessionDir absence alone must move
# the broker aside.
repo1b="$(mktemp -d)"; cleanup_items+=("$repo1b")
git -C "$repo1b" init -q
state1b="$(mktemp -d)"; cleanup_items+=("$state1b")
sess1b="$(mktemp -d)"; cleanup_items+=("$sess1b")

sleep 60 &
live_pid=$!
cleanup_pids+=("$live_pid")

write_broker "$repo1b" "$state1b" "$live_pid" "$sess1b"
rm -rf "$sess1b"   # OS swept the sessionDir even though the pid lives on

echo "[CODEX-BROKER-STALENESS] case 1b: live (reused) pid + swept sessionDir -> self-heals to completion"
run_case case1b "$repo1b" "$state1b"
result1b="$(stub_companion_attempt "$repo1b" "$state1b")" || true
sd1b="$(state_dir_for "$repo1b")"
stale_count1b=$(find "$state1b/$sd1b" -maxdepth 1 -name 'broker.json.stale-*' 2>/dev/null | wc -l | tr -d ' ')
if [ "$result1b" = "completed:fresh_broker_raised" ] && [ "$stale_count1b" -ge 1 ]; then
  echo "[CODEX-BROKER-STALENESS]   live-pid+swept-sessionDir broker moved aside, task self-healed ✓"
  pass=$((pass + 1))
else
  echo "[CODEX-BROKER-STALENESS]   FAIL: expected self-heal completion for reused-pid case, got result='$result1b' stale_count=$stale_count1b" >&2
  cat "$harness/case1b.validate.out" >&2 || true
  fail=$((fail + 1))
fi

kill "$live_pid" 2>/dev/null || true
wait "$live_pid" 2>/dev/null || true

# --- Case 2 (control) ----------------------------------------------------
# A genuinely alive broker (real pid, real sessionDir) must be left
# untouched -- validation must not evict a healthy broker.
repo2="$(mktemp -d)"; cleanup_items+=("$repo2")
git -C "$repo2" init -q
state2="$(mktemp -d)"; cleanup_items+=("$state2")
sess2="$(mktemp -d)"; cleanup_items+=("$sess2")
write_broker "$repo2" "$state2" "$$" "$sess2"   # $$ = this test process, alive for its duration

echo "[CODEX-BROKER-STALENESS] case 2: alive pid + present sessionDir -> left untouched"
run_case case2 "$repo2" "$state2"
sd2="$(state_dir_for "$repo2")"
if [ -f "$state2/$sd2/broker.json" ]; then
  echo "[CODEX-BROKER-STALENESS]   alive broker preserved ✓"
  pass=$((pass + 1))
else
  echo "[CODEX-BROKER-STALENESS]   FAIL: alive broker.json was evicted" >&2
  cat "$harness/case2.validate.out" >&2 || true
  fail=$((fail + 1))
fi

# --- Case 3 (control) ----------------------------------------------------
# No broker.json at all (first task in a fresh repo) -- validation must be a
# silent no-op, not error, not create anything.
repo3="$(mktemp -d)"; cleanup_items+=("$repo3")
git -C "$repo3" init -q
state3="$(mktemp -d)"; cleanup_items+=("$state3")

echo "[CODEX-BROKER-STALENESS] case 3: no broker.json yet -> silent no-op"
rc3=0
run_case case3 "$repo3" "$state3" || rc3=$?
sd3="$(state_dir_for "$repo3")"
if [ "$rc3" -eq 0 ] && [ ! -e "$state3/$sd3" -o -z "$(find "$state3/$sd3" -maxdepth 1 2>/dev/null)" ]; then
  echo "[CODEX-BROKER-STALENESS]   no-op, nothing created ✓"
  pass=$((pass + 1))
else
  echo "[CODEX-BROKER-STALENESS]   FAIL: expected silent no-op, rc=$rc3" >&2
  cat "$harness/case3.validate.out" >&2 || true
  fail=$((fail + 1))
fi

# --- Case 4 (acceptance test) ---------------------------------------------
# The reaper's failure record must carry the worker log's last line and the
# broker's age plus whether its sessionDir existed at reap time -- extracts
# and calls codex-guard.sh's own mark_job_failed against a fixture job JSON,
# then asserts on the PERSISTED record (never on source text).
#
# mark_job_failed's body contains a python heredoc with an unindented dict
# closing brace ("}" at column 1) -- a plain `sed -n '/^fn()/,/^}$/p'` range
# (used above for codex-task.sh's simpler helpers) stops there instead of at
# the function's real end. extract_fn tracks brace depth line-by-line but
# skips heredoc bodies entirely (their braces don't belong to bash).
extract_fn() {
  python3 - "$1" "$2" <<'PY'
import re, sys
path, fn = sys.argv[1], sys.argv[2]
lines = open(path).read().splitlines()
start = next((i for i, l in enumerate(lines) if l == f"{fn}() {{"), None)
if start is None:
    sys.exit(1)
depth = 0
in_heredoc = False
delim = None
out = []
i = start
heredoc_re = re.compile(r"<<-?\s*(['\"]?)([A-Za-z_][A-Za-z0-9_]*)\1")
while i < len(lines):
    line = lines[i]
    out.append(line)
    if in_heredoc:
        if line == delim:
            in_heredoc = False
        i += 1
        continue
    m = heredoc_re.search(line) if "<<<" not in line else None
    if m:
        delim = m.group(2)
        in_heredoc = True
        i += 1
        continue
    depth += line.count("{") - line.count("}")
    if depth <= 0:
        break
    i += 1
print("\n".join(out))
PY
}

CODEX_GUARD="$TEST_DIR/../codex-guard.sh"
guard_harness="$(mktemp -d)"; cleanup_items+=("$guard_harness")
guard_harness_script="$guard_harness/guard_harness.sh"
{
  echo '#!/usr/bin/env bash'
  echo 'set +e'
  extract_fn "$CODEX_GUARD" "stat_mtime"
  extract_fn "$CODEX_GUARD" "acquire_job_lock"
  extract_fn "$CODEX_GUARD" "release_job_lock"
  extract_fn "$CODEX_GUARD" "mark_job_failed"
  echo '"$@"'
} > "$guard_harness_script"
chmod +x "$guard_harness_script"

if ! grep -q '^mark_job_failed()' "$guard_harness_script"; then
  echo "[CODEX-BROKER-STALENESS] FAIL: mark_job_failed not found in ${CODEX_GUARD} (extraction broke, or fn renamed)" >&2
  fail=$((fail + 1))
fi

state4="$(mktemp -d)"; cleanup_items+=("$state4")
mkdir -p "$state4/jobs"
job4="$state4/jobs/job4.json"
log4="$state4/worker4.log"
marker="WORKER-LAST-LINE-MARKER-$$"
printf 'first line\nsecond line\n%s\n' "$marker" > "$log4"
dead_pid4=99997
printf '{"id":"job4","status":"running","pid":%s,"logFile":"%s","startedAt":"2020-01-01T00:00:00.000Z"}\n' \
  "$dead_pid4" "$log4" > "$job4"
# broker.json sits beside the jobs/ dir (state_dir/broker.json), sessionDir
# swept -- the exact incident shape this diagnostic exists to name.
printf '{"pid":12345,"sessionDir":"/nowhere/does-not-exist-case4"}\n' > "$state4/broker.json"

echo "[CODEX-BROKER-STALENESS] case 4: death report enriched with last log line + broker age + sessionDir presence"
bash "$guard_harness_script" mark_job_failed "$job4" "test_reason" 0 0 "" >"$guard_harness/case4.out" 2>&1

record4="$(cat "$job4" 2>/dev/null || echo '{}')"
diag4="$(python3 - "$job4" "$marker" <<'PY'
import json, sys
path, marker = sys.argv[1], sys.argv[2]
try:
    data = json.load(open(path))
except Exception as e:
    print(f"FAIL:load_error:{e}")
    sys.exit(0)
if data.get("status") != "failed":
    print(f"FAIL:status={data.get('status')!r}")
    sys.exit(0)
diag = data.get("deathDiagnostics")
if not isinstance(diag, dict):
    print("FAIL:no_deathDiagnostics")
    sys.exit(0)
if diag.get("lastLogLine") != marker:
    print(f"FAIL:lastLogLine={diag.get('lastLogLine')!r}")
    sys.exit(0)
age = diag.get("brokerAgeSec")
if not isinstance(age, int) or age < 0:
    print(f"FAIL:brokerAgeSec={age!r}")
    sys.exit(0)
if diag.get("brokerSessionDirPresent") is not False:
    print(f"FAIL:brokerSessionDirPresent={diag.get('brokerSessionDirPresent')!r}")
    sys.exit(0)
print("OK")
PY
)"
if [ "$diag4" = "OK" ]; then
  echo "[CODEX-BROKER-STALENESS]   death record carries lastLogLine + brokerAgeSec + brokerSessionDirPresent ✓"
  pass=$((pass + 1))
else
  echo "[CODEX-BROKER-STALENESS]   FAIL: death report enrichment missing/wrong ($diag4)" >&2
  echo "record: $record4" >&2
  cat "$guard_harness/case4.out" >&2 || true
  fail=$((fail + 1))
fi

echo "[CODEX-BROKER-STALENESS] pass=$pass fail=$fail"
[ "$fail" -eq 0 ]
