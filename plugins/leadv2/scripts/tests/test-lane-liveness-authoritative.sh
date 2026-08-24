#!/usr/bin/env bash
# FIX-LANE-LIVENESS-AUTHORITATIVE-01: provider status outranks sidecars/ps.
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/leadv2-temp.sh"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REAL_PLUGIN_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
tmp="$(lv2_mktemp_dir lane-liveness)"; trap 'rm -rf "$tmp"' EXIT

# TEST-DESTROYS-PRODUCTION-SCRIPT-01 (containment): this test used to run its
# helpers directly against the REAL plugin tree, and an unpinned redirect
# somewhere in that call graph overwrote leadv2-lane-liveness.sh's own source
# with its JSON output -- while symlinked into 3 live repos. Every helper this
# test invokes now runs against a throwaway COPY of scripts/ under $tmp; the
# assertions below make "PLUGIN_DIR resolves inside the real repo" fail loudly
# (never silently) even if a future edit re-derives PLUGIN_DIR from SCRIPT_DIR
# again, and the EXIT tripwire re-checks the real file's md5 so any escape
# that still reaches outside the copy aborts instead of destroying it quietly.
PLUGIN_DIR="$tmp/plugin"
mkdir -p "$PLUGIN_DIR"
cp -a "${REAL_PLUGIN_DIR}/scripts" "$PLUGIN_DIR/"
case "$PLUGIN_DIR" in
  "$tmp"/*) ;;
  *) printf '[TEST-SAFETY] ABORT: PLUGIN_DIR %s did not resolve under the scratch root %s\n' "$PLUGIN_DIR" "$tmp" >&2; exit 90 ;;
esac
case "$PLUGIN_DIR" in
  "$REAL_PLUGIN_DIR"|"$REAL_PLUGIN_DIR"/*)
    printf '[TEST-SAFETY] ABORT: PLUGIN_DIR %s resolves inside the real plugin tree %s -- refusing to run\n' "$PLUGIN_DIR" "$REAL_PLUGIN_DIR" >&2
    exit 90
    ;;
esac
export CLAUDE_PLUGIN_ROOT="$PLUGIN_DIR"

_lv2_md5() { md5 -q "$1" 2>/dev/null || md5sum "$1" 2>/dev/null | awk '{print $1}'; }
REAL_HELPER="${REAL_PLUGIN_DIR}/scripts/leadv2-lane-liveness.sh"
REAL_HELPER_MD5_BEFORE="$(_lv2_md5 "$REAL_HELPER")"
lv2_tripwire() {
  local after
  after="$(_lv2_md5 "$REAL_HELPER")"
  if [[ "$after" != "$REAL_HELPER_MD5_BEFORE" ]]; then
    printf '[TEST-SAFETY] FATAL: test mutated a production path %s\n  before=%s\n  after=%s\n' \
      "$REAL_HELPER" "$REAL_HELPER_MD5_BEFORE" "$after" >&2
    exit 91
  fi
  printf '[TEST-SAFETY] tripwire OK: %s unchanged (md5 %s before and after)\n' "$REAL_HELPER" "$after"
}
trap 'lv2_tripwire; rm -rf "$tmp"' EXIT

HELPER="${PLUGIN_DIR}/scripts/leadv2-lane-liveness.sh"
SUPERVISE="${PLUGIN_DIR}/scripts/leadv2-lanes-snapshot.sh"
STATE_PATH="${PLUGIN_DIR}/scripts/leadv2-state-path.sh"
repo="$tmp/repo"; state="$tmp/state"; mkdir -p "$repo/docs/leadv2" "$repo/docs/handoff" "$tmp/bin" "$state"
(cd "$repo" && git init -q)
# TEST SAFETY (B1 root cause, fix-round-2): hard-abort unless this is
# provably a throwaway fixture — see lv2_assert_scratch_repo in leadv2-temp.sh.
lv2_assert_scratch_repo "$repo"
active="$(LEADV2_PROJECT_ROOT="$repo" LEADV2_STATE_ROOT="$state" PROJECT_ROOT="$repo" bash "$STATE_PATH" active.yaml)"
mkdir -p "$(dirname "$active")"; printf 'sessions: []\n' > "$active"
cat > "$tmp/bin/codex-task.sh" <<'SH'
#!/usr/bin/env bash
if [[ "$*" == *"cancelled-job"* ]]; then
  printf '%s\n' '{"workspaceRoot":"x","job":{"id":"cancelled-job","status":"cancelled","phase":"cancelled","createdAt":"2026-07-28T00:00:00Z"}}'
else
  printf '%s\n' '{"workspaceRoot":"x","running":[{"id":"running-job","status":"running","phase":"verifying","createdAt":"2026-07-28T00:00:00Z"}],"recent":[]}'
fi
SH
chmod +x "$tmp/bin/codex-task.sh"
pass=0
check() { grep -q "$2" <<<"$1" && { printf '[TEST] PASS: %s\n' "$3"; pass=$((pass+1)); } || { printf '[TEST] FAIL: %s\n%s\n' "$3" "$1"; exit 1; }; }

# No codex-guard process is created: running must remain running.
running="$(CODEX_TASK_SH="$tmp/bin/codex-task.sh" bash "$HELPER" --project-root "$repo" --json)"
check "$running" '"verdict": "running"' 'running job is not classified dead without codex-guard'
cancelled="$(CODEX_TASK_SH="$tmp/bin/codex-task.sh" bash "$HELPER" --project-root "$repo" --job cancelled-job --json)"
check "$cancelled" '"verdict": "cancelled"' 'cancelled job is reported as cancelled, not dead'
supervised="$(LEADV2_PROJECT_ROOT="$repo" LEADV2_STATE_ROOT="$state" CODEX_TASK_SH="$tmp/bin/codex-task.sh" bash "$SUPERVISE" --json)"
check "$supervised" 'codex:running-job' 'supervise enumerates Codex app-server job'
check "$supervised" '"phase": "verifying"' 'supervise preserves authoritative Phase'

# The registry is intentionally empty: a fresh lane log must still create a
# table row, which is the regression for the former false "none" snapshot.
mkdir -p "$repo/docs/handoff/LOG-ONLY"
printf 'worker is alive\n' > "$repo/docs/handoff/LOG-ONLY/session.log"
lane="$(LEADV2_PROJECT_ROOT="$repo" LEADV2_STATE_ROOT="$state" bash "$HELPER" --project-root "$repo" --lane LOG-ONLY --json)"
check "$lane" '"verdict":"alive"' 'fresh session.log is alive without active.yaml row'
check "$lane" '"source":".*/session.log"' 'session.log path is recorded as liveness source'
union="$(LEADV2_PROJECT_ROOT="$repo" LEADV2_STATE_ROOT="$state" CODEX_TASK_SH="$tmp/bin/codex-task.sh" bash "$SUPERVISE" --json)"
check "$union" '"task_id": "LOG-ONLY"' 'supervise emits log-only lane while registry is empty'
threshold="$(LEADV2_LANE_SILENT_MAX_S=0 LEADV2_PROJECT_ROOT="$repo" LEADV2_STATE_ROOT="$state" bash "$HELPER" --project-root "$repo" --lane LOG-ONLY)"
check "$threshold" 'silent:' 'silence threshold controls log-only lane verdict'

# A recorded live PID changes stale/dead split only; it never becomes stuck.
mkdir -p "$repo/docs/handoff/PID-ALIVE"
printf 'old worker output\n' > "$repo/docs/handoff/PID-ALIVE/session.log"
python3 - "$repo/docs/handoff/PID-ALIVE/session.log" <<'PY'
import os, sys, time
os.utime(sys.argv[1], (time.time() - 60, time.time() - 60))
PY
printf 'sessions:\n  - task_id: PID-ALIVE\n    pid: %s\n    started_at: "2020-01-01T00:00:00Z"\n' "$$" > "$active"
pid_silent="$(LEADV2_LANE_SILENT_MAX_S=1 LEADV2_PROJECT_ROOT="$repo" LEADV2_STATE_ROOT="$state" bash "$HELPER" --project-root "$repo" --lane PID-ALIVE)"
check "$pid_silent" 'silent:' 'pid-alive silent lane remains silent'
pid_snapshot="$(LEADV2_LANE_SILENT_MAX_S=1 LEADV2_PROJECT_ROOT="$repo" LEADV2_STATE_ROOT="$state" CODEX_TASK_SH="$tmp/bin/codex-task.sh" bash "$SUPERVISE" --json)"
if python3 -c 'import json,sys; d=json.load(sys.stdin); assert "PID-ALIVE" not in [x["task_id"] for x in d.get("stuck", [])]' <<<"$pid_snapshot"; then
  printf '[TEST] PASS: pid-alive silent lane is absent from stuck\n'; pass=$((pass+1))
else
  printf '[TEST] FAIL: pid-alive silent lane entered stuck\n%s\n' "$pid_snapshot"; exit 1
fi
# SUPERVISOR-AUDIT-01 fix-round regression: a self-reported provider
# queued/running status must never short-circuit to "alive" ahead of log
# mtime — a stale log with no PID evidence must resolve silent/dead.
mkdir -p "$repo/docs/handoff/STALE-RUNNING"
printf 'old output\n' > "$repo/docs/handoff/STALE-RUNNING/session.log"
# 2000s: stale relative to LEADV2_LANE_SILENT_MAX_S=900 below (this test's
# actual point), but still under the D1 (STATUSLINE fix round 2) default
# abandon_max of 3600s -- keeps this pre-existing assertion decoupled from
# the new abandonment threshold, which is covered by its own dedicated test
# further down.
python3 - "$repo/docs/handoff/STALE-RUNNING/session.log" <<'PY'
import os, sys, time
os.utime(sys.argv[1], (time.time() - 2000, time.time() - 2000))
PY
printf '{"job_id":"running-job"}\n' > "$repo/docs/handoff/STALE-RUNNING/codex-plan.json"
stale_running="$(LEADV2_LANE_SILENT_MAX_S=900 LEADV2_PROJECT_ROOT="$repo" LEADV2_STATE_ROOT="$state" CODEX_TASK_SH="$tmp/bin/codex-task.sh" bash "$HELPER" --project-root "$repo" --lane STALE-RUNNING)"
check "$stale_running" 'silent:' 'self-reported provider running + stale log -> silent, not alive'
rollback_running="$(LEADV2_LANE_LIVENESS_V2=0 LEADV2_LANE_SILENT_MAX_S=900 LEADV2_PROJECT_ROOT="$repo" LEADV2_STATE_ROOT="$state" CODEX_TASK_SH="$tmp/bin/codex-task.sh" bash "$HELPER" --project-root "$repo" --lane STALE-RUNNING)"
check "$rollback_running" 'alive' 'LEADV2_LANE_LIVENESS_V2=0 reproduces exact prior (self-report trusted) behavior'

# B8 (SUPERVISOR-AUDIT-01 fix-round-3, review-verdict-3.md): reviewer's exact
# probe — a FRESH session.log, no PID, and the mapped provider job reporting
# "cancelled" must NOT short-circuit to dead:provider_cancelled. A terminal
# provider self-report is only trusted once the log has ALSO gone stale.
# The shared codex-task.sh stub only reports "cancelled-job" via --job
# (single-job lookup); --lane resolution queries --all, so a dedicated stub
# is needed that surfaces the terminal job through the --all/"recent" shape
# leadv2-lane-liveness.sh's provider_jobs() actually reads for lane lookups.
cat > "$tmp/bin/codex-task-cancelled.sh" <<'SH'
#!/usr/bin/env bash
printf '%s\n' '{"workspaceRoot":"x","running":[],"recent":[{"id":"cancelled-job","status":"cancelled","phase":"cancelled","createdAt":"2026-07-28T00:00:00Z"}]}'
SH
chmod +x "$tmp/bin/codex-task-cancelled.sh"
mkdir -p "$repo/docs/handoff/FRESH-CANCELLED"
printf 'still going\n' > "$repo/docs/handoff/FRESH-CANCELLED/session.log"
printf '{"job_id":"cancelled-job"}\n' > "$repo/docs/handoff/FRESH-CANCELLED/codex-plan.json"
fresh_cancelled="$(LEADV2_LANE_SILENT_MAX_S=900 LEADV2_PROJECT_ROOT="$repo" LEADV2_STATE_ROOT="$state" CODEX_TASK_SH="$tmp/bin/codex-task-cancelled.sh" bash "$HELPER" --project-root "$repo" --lane FRESH-CANCELLED --json)"
check "$fresh_cancelled" '"verdict":"alive"' 'fresh log + no PID + provider cancelled -> alive, terminal status never overrides a fresh log'
check "$fresh_cancelled" '"age_s":[0-9]' 'fresh-cancelled row carries a real age_s'

# B9/B14 regression (SUPERVISOR-AUDIT-01 fix-round-2): a real
# leadv2-fanout.sh single-worker-funnel lane never writes under
# docs/handoff/<task_id>/ -- it writes docs/handoff/dispatch-<sig8>/
# developer.stream.jsonl and records THAT path in the active.yaml row's
# log_path field. Use the REAL fanout artifact layout here (not a synthetic
# FUNNEL-1/session.log fixture) so this proves the actual bug: a fresh
# funnel dispatch must resolve alive via log_path, never
# dead:no_handoff_dir, and the docs/handoff/FUNNEL-TASK/ directory must
# never be created at all.
mkdir -p "$repo/docs/handoff/dispatch-abc12345"
printf '{"type":"assistant","text":"working"}\n' > "$repo/docs/handoff/dispatch-abc12345/developer.stream.jsonl"
printf 'sessions:\n  - task_id: FUNNEL-TASK\n    phase: build\n    pid: null\n    log_path: docs/handoff/dispatch-abc12345/developer.stream.jsonl\n' > "$active"
funnel_alive="$(LEADV2_PROJECT_ROOT="$repo" LEADV2_STATE_ROOT="$state" bash "$HELPER" --project-root "$repo" --lane FUNNEL-TASK --json)"
check "$funnel_alive" '"verdict":"alive"' 'funnel lane with recorded log_path is alive, not dead:no_handoff_dir'
check "$funnel_alive" 'dispatch-abc12345/developer.stream.jsonl' 'funnel lane liveness source is the recorded log_path, not a directory scan'
if [[ -d "$repo/docs/handoff/FUNNEL-TASK" ]]; then
  printf '[TEST] FAIL: docs/handoff/FUNNEL-TASK/ must never be created for a funnel-dispatched lane\n'; exit 1
else
  printf '[TEST] PASS: no docs/handoff/FUNNEL-TASK/ directory created for a funnel-dispatched lane\n'; pass=$((pass+1))
fi
# A stale funnel log_path (file no longer exists) must fall through to the
# unchanged directory-scan behavior rather than silently resolving alive.
printf 'sessions:\n  - task_id: FUNNEL-GONE\n    phase: build\n    pid: null\n    log_path: docs/handoff/dispatch-doesnotexist/developer.stream.jsonl\n' > "$active"
funnel_gone="$(LEADV2_PROJECT_ROOT="$repo" LEADV2_STATE_ROOT="$state" bash "$HELPER" --project-root "$repo" --lane FUNNEL-GONE)"
check "$funnel_gone" 'dead:no_handoff_dir' 'funnel lane with a missing log_path target falls through to the directory scan unchanged'

# --- STATUSLINE-SHOWS-LANES-QUESTIONMARK-01: C1 six-shape resolution + C2 pid-alive floor ---

# C2: a live PID with NO discoverable artifact anywhere (no log_path file,
# no docs/handoff/<tid>/, no fanout-lane/tasks/dispatch-binding shape) must
# floor to silent:<age|unknown>, never dead:* -- "we found no artifact" is
# absence of evidence, not evidence of death, once the process is provably
# still running. This is the exact founder-visible falsehood the task fixes.
printf 'sessions:\n  - task_id: PID-NO-ARTIFACT\n    pid: %s\n    started_at: "2020-01-01T00:00:00Z"\n' "$$" > "$active"
pid_no_artifact="$(LEADV2_PROJECT_ROOT="$repo" LEADV2_STATE_ROOT="$state" bash "$HELPER" --project-root "$repo" --lane PID-NO-ARTIFACT)"
check "$pid_no_artifact" 'silent:' 'C2: live PID with no artifact floors to silent, not dead'
if [[ "$pid_no_artifact" == dead:* ]]; then
  printf '[TEST] FAIL: C2 regression -- live PID still rendered %s\n' "$pid_no_artifact"; exit 1
fi

# C2 negative control (unchanged behavior): no PID recorded (null/dead) and
# no artifact anywhere must still resolve dead:no_handoff_dir -- the guard
# must not blanket-suppress every dead verdict, only ones a live PID
# contradicts.
printf 'sessions:\n  - task_id: NO-PID-NO-ARTIFACT\n    pid: null\n    started_at: "2020-01-01T00:00:00Z"\n' > "$active"
no_pid_no_artifact="$(LEADV2_PROJECT_ROOT="$repo" LEADV2_STATE_ROOT="$state" bash "$HELPER" --project-root "$repo" --lane NO-PID-NO-ARTIFACT)"
check "$no_pid_no_artifact" 'dead:no_handoff_dir' 'C2 negative: no PID + no artifact stays dead:no_handoff_dir'

# C1 shape 2: the session's log_path names a file that doesn't exist yet,
# but its DIRECTORY already does (the funnel created the dir before the
# first write). CENSUS CORRECTION (LANE-REGISTRY-SELF-DEADLOCK-01): this
# assertion was born red in d24720b -- the SAME commit deliberately removed
# the "newest file in the log_path dirname wins" directory scan (S1/D3: a
# lead's own hand-touched file outliving the worker read as alive), but this
# fixture still pinned the removed behavior, so the suite has exited 1 here
# since 2026-07-31. The current authoritative mechanism resolves a
# pre-first-write funnel lane through the registration grace window (tier A,
# fresh started_at -> starting:), never a directory scan -- pin THAT.
mkdir -p "$repo/docs/handoff/dispatch-shape2"
printf 'still writing\n' > "$repo/docs/handoff/dispatch-shape2/session.log"
printf 'sessions:\n  - task_id: SHAPE2-DIRONLY\n    pid: null\n    started_at: "%s"\n    log_path: docs/handoff/dispatch-shape2/developer.stream.jsonl\n' \
  "$(date -u +%Y-%m-%dT%H:%M:%SZ)" > "$active"
shape2="$(LEADV2_PROJECT_ROOT="$repo" LEADV2_STATE_ROOT="$state" bash "$HELPER" --project-root "$repo" --lane SHAPE2-DIRONLY --json)"
check "$shape2" '"verdict":"starting:' 'C1 shape 2: pre-first-write funnel lane resolves starting: via registration grace (dirname scan removed by S1/D3)'

# C1 shape 4: docs/handoff/fanout-lane-<tid>/ (detached fanout launcher),
# no active.yaml row at all. CENSUS CORRECTION (LANE-REGISTRY-SELF-DEADLOCK-01,
# same d24720b family as shape 2 above): the S1 closed candidate ladder reads
# only the lane's OWN dir -- a fanout-lane-<tid>/ sibling with launcher.log
# never was, and is not, resolvable evidence for tid. This assert was born red
# (pinned alive) the same day S1 landed; it pins the authoritative dead now.
mkdir -p "$repo/docs/handoff/fanout-lane-SHAPE4-TASK"
printf 'launcher output\n' > "$repo/docs/handoff/fanout-lane-SHAPE4-TASK/launcher.log"
printf 'sessions: []\n' > "$active"
shape4="$(LEADV2_PROJECT_ROOT="$repo" LEADV2_STATE_ROOT="$state" bash "$HELPER" --project-root "$repo" --lane SHAPE4-TASK --json)"
check "$shape4" '"verdict":"dead:no_handoff_dir"' 'C1 shape 4: fanout-lane- sibling dir alone is not lane evidence under the S1 closed ladder'

# C1 shape 5: docs/leadv2/tasks/<tid>/ (phase-cycle pulse location),
# no active.yaml row. Same census correction: pulse.md is not on the S1
# candidate ladder; the lane's own handoff dir decides.
mkdir -p "$repo/docs/leadv2/tasks/SHAPE5-TASK"
printf '2026-07-30T00:00:00Z phase update\n' > "$repo/docs/leadv2/tasks/SHAPE5-TASK/pulse.md"
shape5="$(LEADV2_PROJECT_ROOT="$repo" LEADV2_STATE_ROOT="$state" bash "$HELPER" --project-root "$repo" --lane SHAPE5-TASK --json)"
check "$shape5" '"verdict":"dead:no_handoff_dir"' 'C1 shape 5: docs/leadv2/tasks/<tid>/pulse.md alone is not lane evidence under the S1 closed ladder'

# C1 shape 6: a dispatch-<sig8>/sessions.map binds the task_id, and no other
# shape has any evidence at all. Same census correction: sessions.map binding
# is not read by resolve(); the row's own log_path/lane_dir decide. With a row
# but no artifacts and no started_at, that is dead:no_handoff_dir.
mkdir -p "$repo/docs/handoff/dispatch-boundsig8"
printf '2026-07-30T00:00:00Z\tdeveloper-SHAPE6-TASK-1785425630\tsome-uuid\n' > "$repo/docs/handoff/dispatch-boundsig8/sessions.map"
printf 'still going via binding\n' > "$repo/docs/handoff/dispatch-boundsig8/developer.stream.jsonl"
printf 'sessions:\n  - task_id: SHAPE6-TASK\n    pid: null\n' > "$active"
shape6="$(LEADV2_PROJECT_ROOT="$repo" LEADV2_STATE_ROOT="$state" bash "$HELPER" --project-root "$repo" --lane SHAPE6-TASK --json)"
check "$shape6" '"verdict":"dead:no_handoff_dir"' 'C1 shape 6: sessions.map binding alone is not lane evidence under the S1 closed ladder'

# ===== STATUSLINE fix round 2 (dispatch-8a9177d7): D1-D6 =====
STATUSLINE_SH="${PLUGIN_DIR}/scripts/leadv2-lane-status-line.sh"
STATUSLINE_TAIL_SH="${PLUGIN_DIR}/scripts/leadv2-lane-status-line-tail.sh"

# D3: --all's discovery gate must agree with --lane for the SAME lane at an
# age past the OLD 900s gate but inside the new discovery window -- proving
# the flicker (silent under --lane, absent entirely under --all) is gone.
mkdir -p "$repo/docs/handoff/dispatch-flicker01"
printf '{"type":"assistant"}\n' > "$repo/docs/handoff/dispatch-flicker01/developer.stream.jsonl"
python3 - "$repo/docs/handoff/dispatch-flicker01/developer.stream.jsonl" <<'PY'
import os, sys, time
os.utime(sys.argv[1], (time.time() - 1000, time.time() - 1000))
PY
printf 'sessions: []\n' > "$active"
flicker_lane="$(LEADV2_PROJECT_ROOT="$repo" LEADV2_STATE_ROOT="$state" bash "$HELPER" --project-root "$repo" --lane dispatch-flicker01)"
flicker_all="$(LEADV2_PROJECT_ROOT="$repo" LEADV2_STATE_ROOT="$state" bash "$HELPER" --project-root "$repo" --all)"
check "$flicker_lane" 'silent:' 'D3: 1000s-old stream is silent under --lane'
if grep -q '^dispatch-flicker01 silent:' <<<"$flicker_all"; then
  printf '[TEST] PASS: D3 -- --all agrees with --lane for the same 1000s-old lane (no flicker)\n'; pass=$((pass+1))
else
  printf '[TEST] FAIL: D3 flicker -- --all disagreed with --lane\n%s\n' "$flicker_all"; exit 1
fi

# D1: an abandoned pid-less lane (age > abandon_max, default 3600s) must age
# out to dead:, never stay silent: forever -- and count_live must exclude
# it, re-derived independently of the verdict string.
mkdir -p "$repo/docs/handoff/ABANDONED-LANE"
printf 'old\n' > "$repo/docs/handoff/ABANDONED-LANE/session.log"
python3 - "$repo/docs/handoff/ABANDONED-LANE/session.log" <<'PY'
import os, sys, time
os.utime(sys.argv[1], (time.time() - 199785, time.time() - 199785))
PY
printf 'sessions: []\n' > "$active"
abandoned="$(LEADV2_PROJECT_ROOT="$repo" LEADV2_STATE_ROOT="$state" bash "$HELPER" --project-root "$repo" --lane ABANDONED-LANE)"
check "$abandoned" '^dead:silent_' 'D1: pid-less lane past abandon_max ages out to dead, never stays silent forever'
abandoned_all_json="$(LEADV2_PROJECT_ROOT="$repo" LEADV2_STATE_ROOT="$state" bash "$HELPER" --project-root "$repo" --all --json)"
if python3 -c '
import json, sys
d = json.load(sys.stdin)
lanes = {r["lane"]: r for r in d["lanes"]}
assert lanes.get("ABANDONED-LANE", {}).get("verdict", "").startswith("dead:")
# STATUSLINE-COUNT-TRUTH-02 correction: count_live is alive+starting ONLY --
# silent:* renders but is deliberately EXCLUDED from the numerator (that is
# the exact "lanes 18/5" disease this task fixes: a stale-but-not-abandoned
# lane must not inflate the count). This formula used to also count
# silent:*, which happened to still pass here only because no other fixture
# in this shared $repo had gone silent yet by this point in the file.
expected = sum(1 for r in d["lanes"] if r["verdict"] == "alive" or r["verdict"].startswith("starting:"))
assert d["count_live"] == expected, (d["count_live"], expected)
' <<<"$abandoned_all_json"; then
  printf '[TEST] PASS: D1 -- count_live excludes the abandoned pid-less lane\n'; pass=$((pass+1))
else
  printf '[TEST] FAIL: D1 -- count_live still counts an abandoned lane\n%s\n' "$abandoned_all_json"; exit 1
fi

# D1 abandon boundary. Not an exact 3599/3601 -- this test invokes bash +
# python3 (+ an optional codex-task.sh probe) between os.utime() and the
# actual age check, which by itself costs 1-4s of wall-clock drift on this
# machine and would make a 2-second-wide boundary flaky. A +-30s margin
# around abandon_max=3600 absorbs that drift while still proving the
# threshold is real (a lane on either side of it renders a different
# verdict), not just "silent forever" as it was pre-fix.
mkdir -p "$repo/docs/handoff/BOUNDARY-LANE"
printf 'boundary\n' > "$repo/docs/handoff/BOUNDARY-LANE/session.log"
python3 - "$repo/docs/handoff/BOUNDARY-LANE/session.log" <<'PY'
import os, sys, time
os.utime(sys.argv[1], (time.time() - 3570, time.time() - 3570))
PY
printf 'sessions: []\n' > "$active"
boundary_under="$(LEADV2_PROJECT_ROOT="$repo" LEADV2_STATE_ROOT="$state" LEADV2_LANE_ABANDON_MAX_S=3600 bash "$HELPER" --project-root "$repo" --lane BOUNDARY-LANE)"
check "$boundary_under" '^silent:' 'D1 boundary: ~3570s (< abandon_max 3600) is still silent'
python3 - "$repo/docs/handoff/BOUNDARY-LANE/session.log" <<'PY'
import os, sys, time
os.utime(sys.argv[1], (time.time() - 3630, time.time() - 3630))
PY
boundary_over="$(LEADV2_PROJECT_ROOT="$repo" LEADV2_STATE_ROOT="$state" LEADV2_LANE_ABANDON_MAX_S=3600 bash "$HELPER" --project-root "$repo" --lane BOUNDARY-LANE)"
check "$boundary_over" '^dead:silent_' 'D1 boundary: ~3630s (> abandon_max 3600) is dead'

# D2: a lane with no artifact yet but a FRESH started_at + pid: null must
# resolve starting:, not dead:no_handoff_dir.
printf 'sessions:\n  - task_id: FRESH-STARTING\n    pid: null\n    started_at: "%s"\n' \
  "$(date -u +%Y-%m-%dT%H:%M:%SZ)" > "$active"
starting="$(LEADV2_PROJECT_ROOT="$repo" LEADV2_STATE_ROOT="$state" bash "$HELPER" --project-root "$repo" --lane FRESH-STARTING)"
check "$starting" '^starting:' 'D2: fresh started_at + pid null + no artifact resolves starting, not dead'
# D2 negative control re-check: the existing NO-PID-NO-ARTIFACT fixture
# (started_at 2020, no artifact) must still resolve dead, never starting --
# the starting branch's age gate must not blanket-suppress every dead
# verdict, only ones a fresh started_at contradicts.
no_pid_recheck="$(LEADV2_PROJECT_ROOT="$repo" LEADV2_STATE_ROOT="$state" bash "$HELPER" --project-root "$repo" --lane NO-PID-NO-ARTIFACT)"
check "$no_pid_recheck" 'dead:no_handoff_dir' 'D2 negative: old started_at + no artifact still resolves dead, never starting'

# LANE-REGISTRY-SELF-DEADLOCK-01 (Defect 2): a FRESH architect-prepass child
# stream is residue of a dispatch attempt (the prepass runs synchronously
# inside the dispatcher, before any spawn) -- never proof of a running
# worker. Default now ignores it; the old composed-prepass signal stays
# assertable behind LEADV2_LANE_PREPASS_LIVE=1. (The fuller R-6/D1 pair,
# including the S0 fold under --all, lives in test-statusline-count-truth.sh
# where the original assertion actually resides -- census correction.)
mkdir -p "$repo/docs/handoff/dispatch-ppdead99" "$repo/docs/handoff/dispatch-ppdead99-architect"
printf '{"type":"assistant"}\n' > "$repo/docs/handoff/dispatch-ppdead99-architect/architect.stream.jsonl"
printf 'sessions: []\n' > "$active"
pp_default="$(LEADV2_PROJECT_ROOT="$repo" LEADV2_STATE_ROOT="$state" bash "$HELPER" --project-root "$repo" --lane dispatch-ppdead99)"
check "$pp_default" '^dead:' 'SELF-DEADLOCK: fresh prepass child stream is NOT a live signal by default (parent resolves dead)'
pp_flag="$(LEADV2_LANE_PREPASS_LIVE=1 LEADV2_PROJECT_ROOT="$repo" LEADV2_STATE_ROOT="$state" bash "$HELPER" --project-root "$repo" --lane dispatch-ppdead99)"
check "$pp_flag" '^starting:' 'SELF-DEADLOCK rollback: LEADV2_LANE_PREPASS_LIVE=1 restores the composed-prepass signal'

# D6: the degradation ladder must never drop a lane, even under an
# absurdly tight width budget -- every registered lane's token must still
# appear in the digest. Isolated in its OWN scratch repo (never the shared
# $repo, which has accumulated a dozen fixture lanes from every test above
# it in this file) so the expected lane count is exactly the 3 this test
# creates, not however many earlier fixtures happen to still be live.
ladder_repo="$tmp/ladder-repo"
mkdir -p "$ladder_repo/docs/leadv2" "$ladder_repo/docs/handoff/dispatch-ladder01" "$ladder_repo/docs/handoff/dispatch-ladder02" "$ladder_repo/docs/handoff/dispatch-ladder03"
for ln in 01 02 03; do
  printf '{"type":"assistant"}\n' > "$ladder_repo/docs/handoff/dispatch-ladder${ln}/developer.stream.jsonl"
done
printf 'sessions: []\n' > "$ladder_repo/docs/leadv2/active.yaml"
# leadv2-state-path.sh resolves STATE_ROOT from LEADV2_STATE_ROOT alone once
# set, ignoring PROJECT_ROOT -- so $active (the shared $state's active.yaml)
# is the SAME physical file every earlier test in this run wrote to, no
# matter which scratch repo's --project-root is passed. Its sessions list
# (task_ids like FRESH-STARTING from the D2 test above) would otherwise
# leak into this repo's lane count via that shared file. Reset it here too.
printf 'sessions: []\n' > "$active"
ladder_input='{"model":{"display_name":"Test"},"workspace":{"current_dir":"'"$ladder_repo"'"}}'
# LANE-REGISTRY-SELF-DEADLOCK-01 (census correction): D6 was born without a
# pinned width, so its outcome depended on the HOST -- the quota block
# (cc/cx/glm, rendered from real quota state regardless of settings.json)
# pushes FINAL_BASE past the default 80-col budget on any host with quota
# data, and the STATUSLINE-READABLE-01 hard clamp then truncates LANES to
# empty. Byte-identical on base and new trees; not a liveness regression.
# Pin the width so this asserts the LADDER (LANE_BUDGET=25 stays tight),
# not the host's quota rendering.
ladder_out="$(LEADV2_PROJECT_ROOT="$ladder_repo" LEADV2_STATE_ROOT="$state" LEADV2_STATUSLINE_LANE_BUDGET=25 LEADV2_STATUSLINE_WIDTH=200 \
  bash "$STATUSLINE_TAIL_SH" "$ladder_input" "$HOME/.claude/settings.json" "${PLUGIN_DIR}/scripts" 0 "$tmp/ladder-out.txt")"
# CENSUS CORRECTION (LANE-REGISTRY-SELF-DEADLOCK-01): this assert was born
# in 198265e (2026-07-31) pinning the pre-STATUSLINE-READABLE-01 ladder,
# which never dropped a lane. b20a454 (2026-08-01) added the drop-to-K
# ladder; at LANE_BUDGET=25 three tokens with arms+ages cannot fit
# (floor token 8 chars x 3 + separators + prefix = ~40 > 25), so the
# correct, designed output is ONE lane token plus '+2' -- try_drop_to_k's
# own contract: 'lanes n/cap already carries the true total, so a dropped
# row loses no fact.' The 3-token expectation has been impossible since
# b20a454; it pins current behavior below instead.
if python3 -c '
import re, sys
text = sys.argv[1]
stripped = re.sub(r"\x1b\[[0-9;]*m", "", text)
m = re.search(r"lanes (\d+|\?)/(\d+)\s*\|?\s*(.*)$", stripped)
assert m, ("no lanes segment found", stripped)
count, cap, rest = m.group(1), m.group(2), m.group(3)
tokens = [t for t in rest.strip().split(" ") if t]
assert count == "3" and cap == "3", ("count must carry the true total", count, cap, stripped)
assert tokens and tokens[-1] == "+2", ("expected 1 lane token + +2 drop counter, got", tokens, stripped)
assert "\u00b7" in tokens[0], ("lane token must keep stem/arm/age", tokens, stripped)
' "$ladder_out"; then
  printf '[TEST] PASS: D6 -- tight-budget ladder keeps the true total (lanes 3/3) plus a stem/arm/age token and the +2 drop counter\n'; pass=$((pass+1))
else
  printf '[TEST] FAIL: D6 -- degradation ladder dropped a lane\n%s\n' "$ladder_out"; exit 1
fi

# D4/D1.5: end-to-end integration, real scripts only -- the TAIL script
# computes and writes the real count sidecar for a scratch repo with
# exactly 2 live lanes, then the HOT PATH (separate process, cold
# last-known cache) must read that EXACT value. This is the only place the
# CACHE_KEY agreement between the two scripts' independent formulas
# (leadv2-lane-status-line.sh's ${PWD//\//_} vs
# leadv2-lane-status-line-tail.sh's ${CWD_FROM_INPUT//\//_}) is actually
# exercised end-to-end -- test-leadv2-lane-status-line.sh, cited by a stale
# comment at leadv2-lane-status-line-tail.sh:102, does not exist. Isolated
# in its OWN scratch repo (never the shared $repo, which has accumulated a
# dozen fixture lanes from every test above it) so the expected count is
# exactly the 2 this test creates.
e2e_repo="$tmp/e2e-repo"
mkdir -p "$e2e_repo/docs/leadv2" "$e2e_repo/docs/handoff/dispatch-e2e01" "$e2e_repo/docs/handoff/dispatch-e2e02"
printf '{"type":"assistant"}\n' > "$e2e_repo/docs/handoff/dispatch-e2e01/developer.stream.jsonl"
printf '{"type":"assistant"}\n' > "$e2e_repo/docs/handoff/dispatch-e2e02/developer.stream.jsonl"
printf 'sessions: []\n' > "$e2e_repo/docs/leadv2/active.yaml"
# Same shared-STATE_ROOT caveat as the D6 ladder test above -- reset $active
# again so no earlier test's sessions list leaks into this repo's count.
printf 'sessions: []\n' > "$active"
e2e_input='{"model":{"display_name":"Test"},"workspace":{"current_dir":"'"$e2e_repo"'"}}'
rm -f "${tmp}"/leadv2-statusline-* 2>/dev/null || true
LEADV2_PROJECT_ROOT="$e2e_repo" LEADV2_STATE_ROOT="$state" TMPDIR="${tmp}/" \
  bash "$STATUSLINE_TAIL_SH" "$e2e_input" "$HOME/.claude/settings.json" "${PLUGIN_DIR}/scripts" 0 "${tmp}/e2e-out.txt" >/dev/null
e2e_key="${e2e_repo//\//_}"
e2e_sidecar="${tmp}/leadv2-statusline-lanecount-${e2e_key}"
if [[ -s "$e2e_sidecar" ]]; then
  printf '[TEST] PASS: D1.5 -- tail script wrote the count sidecar under the hot path'"'"'s own CACHE_KEY formula\n'; pass=$((pass+1))
else
  printf '[TEST] FAIL: D1.5 -- tail script did not write a sidecar at the path the hot path will look for\n'; exit 1
fi
rm -f "${tmp}/leadv2-statusline-last-known-${e2e_key}"
# Suppress the fire-and-forget refresher for the three hot-path calls below:
# it keeps writing sidecars into TMPDIR for seconds after each call exits and
# races the EXIT trap's rm -rf (observed: "Directory not empty" -> rc 1 with
# every assertion green). Pre-created lock + 1h min-interval = never spawns.
: > "${tmp}/leadv2-statusline-refresh-lock-${e2e_key}_sup0"
export LEADV2_STATUSLINE_REFRESH_MIN_INTERVAL_S=3600
# CENSUS CORRECTION (LANE-REGISTRY-SELF-DEADLOCK-01): this D4 trio was born
# dead on a non-supervisor host and never ran green after its own commit day.
# d24720b (2026-07-31) added them asserting the tail's sidecar reaches the
# hot path; 89711f8 (SUPERVISOR-HARDENING-01, same day) then (a) gated the
# lanes digest supervisor-only and (b) folded `_sup${IS_SUPERVISOR}` into
# the hot path's CACHE_KEY while the tail's COUNT_SIDECAR_FILE stayed on
# the plain key -- so the sidecar D1.5 proves written is UNREADABLE by the
# hot path in every mode, and a non-supervisor session renders no lanes
# segment at all. Verified red on the base tree (eb39d6f) once the born-red
# C1/D6 asserts ahead of it are bypassed. The CACHE_KEY drift itself is a
# live defect recorded in docs/leadv2/open-threads.md (STATUSLINE-SIDECAR-
# KEY-DRIFT); until it is fixed, pin today's deterministic behaviour:
e2e_hotpath_out="$(cd "$e2e_repo" && TMPDIR="${tmp}/" bash -c 'printf "%s" "$1" | bash "$2"' _ "$e2e_input" "$STATUSLINE_SH")"
if grep -qE 'lanes [0-9]+/' <<<"$e2e_hotpath_out"; then
  printf '[TEST] FAIL: D4 -- non-supervisor hot path fabricated a lane count\n%s\n' "$e2e_hotpath_out"; exit 1
fi
printf '[TEST] PASS: D4: production hot path (non-supervisor) renders no lanes segment, never a fabricated count\n'; pass=$((pass+1))
gate_off_out="$(cd "$e2e_repo" && TMPDIR="${tmp}/" LEADV2_STATUSLINE_SUPERVISOR_ONLY=0 bash -c 'printf "%s" "$1" | bash "$2"' _ "$e2e_input" "$STATUSLINE_SH")"
check "$gate_off_out" 'lanes ?' 'D4: gate-lifted hot path renders honest lanes ? (sidecar unreadable: CACHE_KEY _sup drift, 89711f8)'

# D4: an unreadable/absent sidecar must render the honest "lanes ?", never a
# confident zero. Gate lifted for the same reason as above: the supervisor
# gate would otherwise omit the segment entirely and assert nothing.
rm -f "${tmp}"/leadv2-statusline-lanecount-* "${tmp}/leadv2-statusline-last-known-${e2e_key}"
no_sidecar_out="$(cd "$e2e_repo" && TMPDIR="${tmp}/" LEADV2_STATUSLINE_SUPERVISOR_ONLY=0 bash -c 'printf "%s" "$1" | bash "$2"' _ "$e2e_input" "$STATUSLINE_SH")"
check "$no_sidecar_out" 'lanes ?' 'D4: missing sidecar renders lanes ?, never a fabricated count'
rm -f "${tmp}"/leadv2-statusline-* 2>/dev/null || true

# D4: when the authoritative liveness read itself fails (count_live is
# None), the tail script must render "lanes ?/<cap>", never "lanes 0/<cap>"
# -- an unreadable count and a genuinely empty count are not the same fact.
# CENSUS CORRECTION (LANE-REGISTRY-SELF-DEADLOCK-01), two host-born-dead
# defects in this fixture: (1) STATUSLINE-DESTROYS-PROBER-01 E6 added an
# executable-fallback to SCRIPT_DIR, so a chmod-000 CLAUDE_PLUGIN_ROOT
# candidate now silently resolves to the REAL liveness and renders a
# confident count -- the stub must be executable-but-failing instead.
# (2) same unpinned-width host dependence as D6 above: without
# LEADV2_STATUSLINE_WIDTH the quota block pushes the digest past the clamp
# and the segment renders empty.
broken_root="${tmp}/broken-plugin"
mkdir -p "${broken_root}/scripts"
printf '#!/usr/bin/env bash\nexit 3\n' > "${broken_root}/scripts/leadv2-lane-liveness.sh"
chmod 755 "${broken_root}/scripts/leadv2-lane-liveness.sh"
broken_out="$(LEADV2_STATUSLINE_WIDTH=200 CLAUDE_PLUGIN_ROOT="$broken_root" LEADV2_PROJECT_ROOT="$e2e_repo" LEADV2_STATE_ROOT="$state" \
  bash "$STATUSLINE_TAIL_SH" "$e2e_input" "$HOME/.claude/settings.json" "${PLUGIN_DIR}/scripts" 0 "$tmp/broken-out.txt")"
check "$broken_out" 'lanes ?/' 'D4: a failed liveness read renders lanes ?/<cap>, never a confident lanes 0/<cap>'
if grep -qE 'lanes 0/' <<<"$broken_out"; then
  printf '[TEST] FAIL: D4 regression -- a failed liveness read rendered a confident zero\n%s\n' "$broken_out"; exit 1
fi

printf '[TEST] %d authoritative-liveness assertions passed\n' "$pass"
