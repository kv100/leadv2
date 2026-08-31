#!/usr/bin/env bash
# LANE-FINISHED-IS-NOT-DEAD-01 — a lane with no live pid AND a commit on its
# own worktree branch within a bounded window is FINISHED: a third state
# between alive and dead. Before this fix the same evidence was misread in
# BOTH directions at once: leadv2-lanes-snapshot.sh escalated it to the
# founder as "corroborated dead: pid dead" (a finished lane's own stream
# flush is stale, exactly like a genuinely dead one), while
# leadv2-dispatch-code.sh's placement probe read the SAME finished lane's
# still-fresh stream mtime as "alive" and refused re-dispatch
# (lane_is_live). Both readings are wrong about the same lane at the same
# moment; this suite proves the corrected three-state answer.
#
# Cases (mission acceptance):
#   A1  live pid                                    -> alive
#   A2  no pid + commit in window + FRESH stream     -> finished (stream
#       freshness must NOT resurrect "alive" — the exact 09:5x refusal)
#   A3  no pid + no commit + no artifact              -> dead
#   B1  placement probe reports alive                 -> refused (lane_is_live), unchanged
#   B2  placement probe reports finished:*             -> NOT refused, pin proceeds
#   B3  placement probe reports dead:*                 -> NOT refused, pin proceeds (unchanged)
#   C-finished  real finished evidence                 -> no ask.sh escalation, row survives
#   C-dead      real dead evidence, corroborated twice  -> ask.sh escalation fires, row tombstoned+pruned
#
# A and C exercise the REAL leadv2-lane-liveness.sh / leadv2-lanes-snapshot.sh
# (copied into a scratch plugin dir, tripwire-guarded against mutating the
# real files). B exercises the REAL leadv2-dispatch-code.sh placement seam
# with a stub liveness probe (same technique as test-lane-placement-pin.sh),
# isolating the placement-consumption contract from the oracle computation
# already proven in A.
set -uo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/leadv2-temp.sh"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REAL_PLUGIN_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
tmp="$(lv2_mktemp_dir lane-finished-state)"

PASS=0; FAIL=0
ok()  { printf '[TEST] PASS: %s\n' "$1"; PASS=$((PASS+1)); }
bad() { printf '[TEST] FAIL: %s\n' "$1" >&2; FAIL=$((FAIL+1)); }
check() {  # <haystack> <needle> <label>
  if grep -q -- "$2" <<<"$1"; then ok "$3"; else printf '  got: %s\n' "$1" >&2; bad "$3"; fi
}

# ── TEST-DESTROYS-PRODUCTION-SCRIPT-01 containment (same pattern as
#    test-lane-liveness-sentinel.sh): every subject runs from a scratch copy
#    of scripts/, tripwired against a real-file byte change on exit.
PLUGIN_DIR="$tmp/plugin"
mkdir -p "$PLUGIN_DIR"
cp -a "${REAL_PLUGIN_DIR}/scripts" "$PLUGIN_DIR/"
case "$PLUGIN_DIR" in
  "$tmp"/*) ;;
  *) printf '[TEST-SAFETY] ABORT: PLUGIN_DIR %s did not resolve under scratch root %s\n' "$PLUGIN_DIR" "$tmp" >&2; exit 90 ;;
esac
case "$PLUGIN_DIR" in
  "$REAL_PLUGIN_DIR"|"$REAL_PLUGIN_DIR"/*)
    printf '[TEST-SAFETY] ABORT: PLUGIN_DIR resolves inside real plugin tree\n' >&2; exit 90 ;;
esac
export CLAUDE_PLUGIN_ROOT="$PLUGIN_DIR"

_lv2_md5() { md5 -q "$1" 2>/dev/null || md5sum "$1" 2>/dev/null | awk '{print $1}'; }
REAL_LIVENESS="${REAL_PLUGIN_DIR}/scripts/leadv2-lane-liveness.sh"
REAL_SNAPSHOT="${REAL_PLUGIN_DIR}/scripts/leadv2-lanes-snapshot.sh"
REAL_LIVENESS_MD5_BEFORE="$(_lv2_md5 "$REAL_LIVENESS")"
REAL_SNAPSHOT_MD5_BEFORE="$(_lv2_md5 "$REAL_SNAPSHOT")"
lv2_tripwire() {
  local a b
  a="$(_lv2_md5 "$REAL_LIVENESS")"; b="$(_lv2_md5 "$REAL_SNAPSHOT")"
  if [[ "$a" != "$REAL_LIVENESS_MD5_BEFORE" ]]; then
    printf '[TEST-SAFETY] FATAL: test mutated production path %s\n' "$REAL_LIVENESS" >&2; exit 91
  fi
  if [[ "$b" != "$REAL_SNAPSHOT_MD5_BEFORE" ]]; then
    printf '[TEST-SAFETY] FATAL: test mutated production path %s\n' "$REAL_SNAPSHOT" >&2; exit 91
  fi
}
cleanup() { lv2_tripwire; rm -rf "$tmp"; }
trap cleanup EXIT

LIVENESS="${PLUGIN_DIR}/scripts/leadv2-lane-liveness.sh"
SNAPSHOT_SH="${PLUGIN_DIR}/scripts/leadv2-lanes-snapshot.sh"
STATE_PATH_SH="${PLUGIN_DIR}/scripts/leadv2-state-path.sh"
DC="${PLUGIN_DIR}/scripts/leadv2-dispatch-code.sh"

# Deterministic git identity for every fixture commit — HOME is sandboxed
# below so no real ~/.gitconfig is consulted.
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@e.com
export GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@e.com

find_unused_pid() {
  local p=99999
  while kill -0 "$p" 2>/dev/null; do p=$((p + 1)); done
  echo "$p"
}
DEAD_PID="$(find_unused_pid)"

set_mtime_ago() {  # <path> <secs>
  python3 - "$1" "$2" <<'PY'
import os, sys, time
path, secs = sys.argv[1], int(sys.argv[2])
t = time.time() - secs
os.utime(path, (t, t))
PY
}

commit_at_age() {  # <repo_dir> <secs_ago>
  local repo="$1" secs="$2" ts
  mkdir -p "$repo"
  [[ -d "$repo/.git" ]] || (cd "$repo" && git init -q)
  ts=$(( $(date +%s) - secs ))
  printf 'x\n' >> "$repo/f.txt"
  (cd "$repo" && git add f.txt \
    && GIT_AUTHOR_DATE="@${ts}" GIT_COMMITTER_DATE="@${ts}" \
       git commit -q -m "c-${secs}")
}

# ════════════════════════════════════════════════════════════════════════════
# PART A — direct oracle: leadv2-lane-liveness.sh --lane --json --no-codex
# ════════════════════════════════════════════════════════════════════════════
A_ROOT="$tmp/a-repo"
mkdir -p "$A_ROOT/docs/leadv2" "$A_ROOT/docs/handoff"
(cd "$A_ROOT" && git init -q)
lv2_assert_scratch_repo "$A_ROOT"

# --- A1: live pid, fresh stream -> alive -----------------------------------
a1_lane="$A_ROOT/docs/handoff/A1-ALIVE"; mkdir -p "$a1_lane"
printf '{"type":"assistant"}\n' > "$a1_lane/developer.stream.jsonl"
set_mtime_ago "$a1_lane/developer.stream.jsonl" 10
cat > "$A_ROOT/docs/leadv2/active.yaml" <<YAML
sessions:
  - task_id: A1-ALIVE
    pid: $$
    log_path: docs/handoff/A1-ALIVE/developer.stream.jsonl
YAML
a1_out="$(LEADV2_PROJECT_ROOT="$A_ROOT" bash "$LIVENESS" --project-root "$A_ROOT" --lane A1-ALIVE --json --no-codex)"
check "$a1_out" '"verdict":"alive"' 'A1: live pid + fresh stream -> alive'

# --- A2: dead pid + commit in window + FRESH stream -> finished:* ---------
# The exact 09:5x refusal: a fresh stream mtime alone must not resurrect
# "alive" once the pid is gone and a commit already landed.
a2_wt="$tmp/a2-worktree"
commit_at_age "$a2_wt" 300
a2_lane="$A_ROOT/docs/handoff/A2-FINISHED"; mkdir -p "$a2_lane"
printf '{"type":"assistant"}\n' > "$a2_lane/developer.stream.jsonl"
set_mtime_ago "$a2_lane/developer.stream.jsonl" 10   # fresh — inside silent_max
cat > "$A_ROOT/docs/leadv2/active.yaml" <<YAML
sessions:
  - task_id: A2-FINISHED
    pid: ${DEAD_PID}
    log_path: docs/handoff/A2-FINISHED/developer.stream.jsonl
    worktree: ${a2_wt}
YAML
a2_out="$(LEADV2_PROJECT_ROOT="$A_ROOT" bash "$LIVENESS" --project-root "$A_ROOT" --lane A2-FINISHED --json --no-codex)"
check "$a2_out" '"verdict":"finished:' 'A2: dead pid + commit in window + fresh stream -> finished (not alive)'
check "$a2_out" '"reason":"commit_within_window"' 'A2: reason is commit_within_window'

# --- A3: dead pid, no worktree, no commit, stale artifact -> dead:* -------
a3_lane="$A_ROOT/docs/handoff/A3-DEAD"; mkdir -p "$a3_lane"
printf '{"type":"assistant"}\n' > "$a3_lane/developer.stream.jsonl"
set_mtime_ago "$a3_lane/developer.stream.jsonl" 9999   # past abandon_max (3600)
cat > "$A_ROOT/docs/leadv2/active.yaml" <<YAML
sessions:
  - task_id: A3-DEAD
    pid: ${DEAD_PID}
    log_path: docs/handoff/A3-DEAD/developer.stream.jsonl
YAML
a3_out="$(LEADV2_PROJECT_ROOT="$A_ROOT" bash "$LIVENESS" --project-root "$A_ROOT" --lane A3-DEAD --json --no-codex)"
check "$a3_out" '"verdict":"dead:' 'A3: dead pid + no commit + stale artifact -> dead'

# ════════════════════════════════════════════════════════════════════════════
# PART B — placement consumption: leadv2-dispatch-code.sh --resume-lane
# (stub liveness probe, same technique as test-lane-placement-pin.sh)
# ════════════════════════════════════════════════════════════════════════════
export LEADV2_BURN_GOVERNOR=0
B_TARGET="$tmp/b-target"
mkdir -p "$B_TARGET"
(cd "$B_TARGET" && git init -q -b main \
  && printf 'seed\n' > .gitignore && git add .gitignore && git commit -qm seed)
B_WT="${B_TARGET}/.claude/worktrees/B-LANE-01"
mkdir -p "$(dirname "$B_WT")"
(cd "$B_TARGET" && git worktree add -q "$B_WT" -b worktree-B-LANE-01) 2>/dev/null
(cd "$B_WT" && printf 'lane work\n' > lane.txt && git add lane.txt && git commit -qm lane-seed)

B_GLM_STUB="$tmp/b-glm-stub.sh"
cat > "$B_GLM_STUB" <<'SH'
#!/usr/bin/env bash
RUNS="${LEADV2_STUB_GLM_RUNS:-/tmp/leadv2-stub-glm-runs}"
case "${1:-}" in
  bg) mkdir -p "$RUNS"; h="stub-$(date +%s)-$$"; printf '%s' "$h" > "$RUNS/$h"; printf '%s\n' "$h"; exit 0 ;;
  status) [[ -n "${2:-}" && -f "$RUNS/$2" ]] && exit 0; exit 1 ;;
  *) exit 0 ;;
esac
SH
chmod +x "$B_GLM_STUB"
B_JOURNAL_STUB="$tmp/b-journal-stub.sh"; printf '#!/usr/bin/env bash\nexit 0\n' > "$B_JOURNAL_STUB"; chmod +x "$B_JOURNAL_STUB"

b_liveness_stub_for() {  # <verdict> <reason> <age_s> -> writes stub, prints path
  local verdict="$1"
  local reason="$2"
  local age="$3"
  local slug; slug="$(printf '%s' "$verdict" | tr -c 'a-zA-Z0-9' '_')"
  local stub="$tmp/b-liveness-${slug}.sh"
  cat > "$stub" <<SH
#!/usr/bin/env bash
printf '{"lane":"B-LANE-01","verdict":"${verdict}","reason":"${reason}","age_s":${age},"pid_alive":false}\n'
exit 0
SH
  chmod +x "$stub"
  printf '%s' "$stub"
}

b_setup_env() {
  export CLAUDE_PROJECT_DIR="$B_TARGET"
  export CLAUDE_PROJECT_ROOT="$B_TARGET"
  unset PROJECT_ROOT 2>/dev/null || true
  unset LEADV2_LANE_WORK_ROOT 2>/dev/null || true
  export LEADV2_DISPATCH_GLM_BIN="$B_GLM_STUB"
  export LEADV2_STUB_GLM_RUNS="$tmp/b-glm-runs"
  export LEADV2_JOURNAL_BIN="$B_JOURNAL_STUB"
  export LEADV2_DISPATCH_LEDGER_BIN="${REAL_PLUGIN_DIR}/scripts/leadv2-dispatch-ledger.sh"
  export LEADV2_STATE_PATH_BIN="$STATE_PATH_SH"
  export LEADV2_ROUTER_V2=0
  export GLM_POLICY_RESOLVER=""
  export LEADV2_LANE_SHAPE=off
  export LEADV2_DISPATCH_E2E_GATE=0
  export LEADV2_DISPATCH_REVIEW_GATE=0
  export LEADV2_DISPATCH_PENDING_TTL_S=5
  export LEADV2_DISPATCH_CONFIRMED_TTL_S=10
  export LEADV2_STATE_BASE="$tmp/b-state-$RANDOM"
  export LEADV2_DISPATCH_CACHE_DIR="$tmp/b-cache-$RANDOM"
}

# --- B1: verdict=alive -> refused (lane_is_live), unchanged regression control
b_setup_env
# NOTE (environment finding): the full leadv2-dispatch-code.sh success path
# (placement passes -> real spawn pipeline) hangs indefinitely in THIS
# sandbox even on an UNRELATED, pre-existing suite (test-lane-placement-pin.sh
# P-a, reproduced standalone: >60s, zero output, no relation to this diff —
# matches memory run-all-changed-preexisting-reds' "LANE-PLACEMENT-01" entry).
# The REFUSAL path is provably fast (exit 5 at the placement gate itself,
# before any spawn) and is asserted on rc directly (B1). For the two
# NOT-refused cases (B2/B3) we bound the wait with `timeout` and assert the
# one decisive, real signal the placement gate itself prints — "REFUSE
# placement... lane_is_live" — never appears, i.e. the process demonstrably
# passed the gate rather than exiting 5. What happens further downstream
# (the real spawn pipeline) is out of this lane's scope and independently
# broken in this sandbox regardless of the verdict fed to it.
export LEADV2_DISPATCH_LANE_LIVENESS_BIN="$(b_liveness_stub_for alive process_alive 5)"
b1_rc=0
b1_err="$tmp/b1-stderr.txt"
timeout 8 bash "$DC" --kind tooling --resume-lane B-LANE-01 "B1 placement test" >/dev/null 2>"$b1_err" || b1_rc=$?
if [[ "$b1_rc" -eq 5 ]]; then ok "B1: alive verdict -> dispatch refused (rc=5)"; else bad "B1: alive verdict -> expected rc=5, got rc=$b1_rc"; fi
check "$(cat "$b1_err")" 'lane_is_live' 'B1: stderr contains lane_is_live'

# --- B2: verdict=finished:* -> NOT refused, gate does not fire -------------
b_setup_env
export LEADV2_DISPATCH_LANE_LIVENESS_BIN="$(b_liveness_stub_for finished:900 commit_within_window 5)"
b2_rc=0
b2_err="$tmp/b2-stderr.txt"
timeout 8 bash "$DC" --kind tooling --resume-lane B-LANE-01 "B2 placement test" >/dev/null 2>"$b2_err" || b2_rc=$?
if [[ "$b2_rc" -eq 5 ]]; then
  bad "B2: finished verdict -> placement gate refused (rc=5), expected pass-through"
else
  ok "B2: finished verdict -> placement gate did not refuse (rc=$b2_rc, exit 124=bounded-wait past the gate)"
fi
if grep -q 'lane_is_live' "$b2_err" 2>/dev/null; then bad "B2: stderr must NOT contain lane_is_live"; else ok "B2: stderr has no lane_is_live refusal"; fi

# --- B3: verdict=dead:* -> NOT refused, gate does not fire (unchanged) -----
b_setup_env
export LEADV2_DISPATCH_LANE_LIVENESS_BIN="$(b_liveness_stub_for dead:silent_9999s_no_process log_silent_no_process 9999)"
b3_rc=0
b3_err="$tmp/b3-stderr.txt"
timeout 8 bash "$DC" --kind tooling --resume-lane B-LANE-01 "B3 placement test" >/dev/null 2>"$b3_err" || b3_rc=$?
if [[ "$b3_rc" -eq 5 ]]; then
  bad "B3: dead verdict -> placement gate refused (rc=5), expected pass-through (unchanged)"
else
  ok "B3: dead verdict -> placement gate did not refuse (rc=$b3_rc), unchanged"
fi
if grep -q 'lane_is_live' "$b3_err" 2>/dev/null; then bad "B3: stderr must NOT contain lane_is_live"; else ok "B3: stderr has no lane_is_live refusal"; fi

# ════════════════════════════════════════════════════════════════════════════
# PART C — escalation veto: leadv2-lanes-snapshot.sh (real liveness oracle,
# stubbed leadv2-ask.sh so no real founder-question channel is touched)
# ════════════════════════════════════════════════════════════════════════════
C_ASK_LOG="$tmp/c-ask-calls.log"
: > "$C_ASK_LOG"
cat > "${PLUGIN_DIR}/scripts/leadv2-ask.sh" <<SH
#!/usr/bin/env bash
printf '%s\n' "\$*" >> "${C_ASK_LOG}"
exit 0
SH
chmod +x "${PLUGIN_DIR}/scripts/leadv2-ask.sh"

C_ROOT="$tmp/c-repo"
mkdir -p "$C_ROOT/docs/leadv2" "$C_ROOT/docs/handoff"
(cd "$C_ROOT" && git init -q)
lv2_assert_scratch_repo "$C_ROOT"
C_STATE="$tmp/c-state"
mkdir -p "$C_STATE"
# This host provides PyYAML from its Python user-site — capture that
# immutable dependency before changing HOME (same gotcha test-lanes-
# snapshot.sh's setup documents), else lanes-snapshot.sh's embedded python3
# fails to import yaml under the sandboxed HOME below.
LV2_PY_USER_SITE="$(python3 -c 'import site; print(site.getusersitepackages())')"
export HOME="$tmp/c-home"; mkdir -p "$HOME"
export XDG_CACHE_HOME="$tmp/c-cache"; mkdir -p "$XDG_CACHE_HOME"
export PYTHONPATH="$LV2_PY_USER_SITE${PYTHONPATH:+:$PYTHONPATH}"
export LEADV2_STATE_ROOT="$C_STATE"
export CLAUDE_PROJECT_DIR="$C_ROOT"
export PROJECT_ROOT="$C_ROOT"
export LEADV2_PROJECT_ROOT="$C_ROOT"
unset CLAUDE_PROJECT_ROOT LEADV2_DISPATCH_LANE_LIVENESS_BIN 2>/dev/null || true
active_path="$(bash "$STATE_PATH_SH" active.yaml)"
tombstones_path="$(bash "$STATE_PATH_SH" tombstones.yaml)"
snapshot_path="$(bash "$STATE_PATH_SH" .supervise-last.json)"
mkdir -p "$(dirname "$active_path")"

OLD_STARTED="2020-01-01T00:00:00+00:00"

# --- C-finished: real dead pid + real recent commit -> no escalation -------
cf_wt="$tmp/cf-worktree"
commit_at_age "$cf_wt" 120
cf_lane="$C_ROOT/docs/handoff/CF-FINISHED"; mkdir -p "$cf_lane"
printf '{"type":"assistant"}\n' > "$cf_lane/developer.stream.jsonl"
# 200s: past the pre-existing freshness veto's default 120s window
# (LEADV2_LANE_FRESH_S) but well inside the 900s finished window, so ONLY the
# new finished-veto (not the old freshness veto) can save this row from
# escalation -- otherwise this case is vacuous under a mutation that neuters
# commit_finished_check (verified: with a fresh 10s stream the old veto alone
# clears `reasons` regardless of the new fix, per mutation-testing control).
set_mtime_ago "$cf_lane/developer.stream.jsonl" 200
cat > "$active_path" <<YAML
sessions:
  - task_id: CF-FINISHED
    started_at: "${OLD_STARTED}"
    phase: build
    pid: ${DEAD_PID}
    pid_birth: null
    protocol_version: 2
    backend: headless
    log_path: docs/handoff/CF-FINISHED/developer.stream.jsonl
    worktree: ${cf_wt}
    last_pulse_at: "${OLD_STARTED}"
    stale: false
YAML
# Escalation/prune only fire on the SECOND consecutive poll (corroboration)
# -- a single poll never escalates regardless of the finished-veto, which
# would make this case vacuous. Seed CF-FINISHED as an already-corroborated
# dead_candidate from a prior poll so THIS poll is the corroborating one,
# and only the finished-veto (not "no corroboration yet") can be the reason
# it survives.
mkdir -p "$(dirname "$snapshot_path")"
cat > "$snapshot_path" <<JSON
{"rendered_at":"2020-01-01T00:00:00+00:00","tasks":{},"reported_events":[],
 "dead_candidates":{"CF-FINISHED":"2020-01-01T00:00:00+00:00"},"reconcile_cycle_count":5}
JSON
cf_out="$(LEADV2_SUPERVISE_OBSERVE_ONLY=0 bash "$SNAPSHOT_SH" --json 2>/dev/null)" || { bad "C-finished: lanes-snapshot.sh exited nonzero"; cf_out=""; }
if [[ -n "$cf_out" ]]; then
  cf_still_present="$(python3 -c "
import yaml
d = yaml.safe_load(open('$active_path')) or {}
print(any(s.get('task_id')=='CF-FINISHED' for s in d.get('sessions', [])))
")"
  if [[ "$cf_still_present" == True ]]; then ok "C-finished: row survives (not pruned)"; else bad "C-finished: row was pruned — should have stayed (finished != dead)"; fi
fi
if [[ -s "$C_ASK_LOG" ]] && grep -q 'CF-FINISHED' "$C_ASK_LOG"; then
  bad "C-finished: ask.sh escalation fired for a finished lane"
else
  ok "C-finished: no ask.sh escalation for a finished lane"
fi

# --- C-dead: real dead pid, no worktree, no commit, stale artifact,
#     corroborated on a second poll -> escalation fires, row pruned ---------
: > "$C_ASK_LOG"
cd_lane="$C_ROOT/docs/handoff/CD-DEAD"; mkdir -p "$cd_lane"
printf '{"type":"assistant"}\n' > "$cd_lane/developer.stream.jsonl"
set_mtime_ago "$cd_lane/developer.stream.jsonl" 9999
cat > "$active_path" <<YAML
sessions:
  - task_id: CD-DEAD
    started_at: "${OLD_STARTED}"
    phase: build
    pid: ${DEAD_PID}
    pid_birth: null
    protocol_version: 2
    backend: headless
    log_path: docs/handoff/CD-DEAD/developer.stream.jsonl
    last_pulse_at: "${OLD_STARTED}"
    stale: false
YAML
cat > "$snapshot_path" <<JSON
{"rendered_at":"${OLD_STARTED}","tasks":{},"reported_events":[],
 "dead_candidates":{"CD-DEAD":"${OLD_STARTED}"},"reconcile_cycle_count":5}
JSON
cd_out="$(LEADV2_SUPERVISE_OBSERVE_ONLY=0 bash "$SNAPSHOT_SH" --json 2>/dev/null)" || { bad "C-dead: lanes-snapshot.sh exited nonzero"; cd_out=""; }
if [[ -n "$cd_out" ]]; then
  cd_removed="$(python3 -c "
import yaml
d = yaml.safe_load(open('$active_path')) or {}
print(not any(s.get('task_id')=='CD-DEAD' for s in d.get('sessions', [])))
")"
  cd_tombstoned="false"
  if [[ -f "$tombstones_path" ]]; then
    cd_tombstoned="$(python3 -c "
import yaml
d = yaml.safe_load(open('$tombstones_path')) or []
print(any(t.get('task_id')=='CD-DEAD' for t in d))
")"
  fi
  if [[ "$cd_removed" == True && "$cd_tombstoned" == True ]]; then
    ok "C-dead: corroborated dead row pruned AND tombstoned (unchanged)"
  else
    bad "C-dead: removed=$cd_removed tombstoned=$cd_tombstoned"
  fi
fi
if grep -q 'CD-DEAD' "$C_ASK_LOG" 2>/dev/null && grep -q 'corroborated dead' "$C_ASK_LOG" 2>/dev/null; then
  ok "C-dead: ask.sh escalation fired for a genuinely dead lane"
else
  bad "C-dead: ask.sh escalation did NOT fire for a genuinely dead lane"
fi

echo ""
echo "=== Results: ${PASS} passed, ${FAIL} failed ==="
if [[ "$FAIL" -gt 0 ]]; then exit 1; fi
printf '\n[TEST-SAFETY] tripwire: '; lv2_tripwire
