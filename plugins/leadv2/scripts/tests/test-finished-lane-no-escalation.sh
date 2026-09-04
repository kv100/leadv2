#!/usr/bin/env bash
# test-finished-lane-no-escalation.sh — ESCALATION-OFFERS-DESTRUCTIVE-
# DEFAULTS-FOR-FINISHED-LANES-01 negative control.
#
# A lane whose lane-liveness verdict starts with `finished` (here the
# finished_unlanded rung: deliverable under docs/handoff/<tid>/, fresh within
# LEADV2_LANE_FINISHED_WINDOW_S) must NEVER be offered abandon/restart by the
# two-poll escalation in leadv2-lanes-snapshot.sh. The commit-age arm of that
# veto reads s["worktree"] -- for lead-registered rows that names the MAIN
# checkout, so a worker that committed into its own worktree and exited
# escalated anyway (four finished lanes in one hour, 2026-09-04). The fix
# consults the ladder verdict inside the SAME veto; this suite proves that
# consultation exists and bites:
#   Test 1  finished lane + gone pid -> no escalation (baseline GREEN)
#   Test 2  mutating the ladder-verdict consultation (REGEXP anchor, exactly
#           once) -> the finished lane is offered abandon/restart (RED)
#   Test 3  revert -> GREEN again
#   Test 4  genuine death (no commit, no deliverable, gone pid) still
#           escalates exactly as today -- the veto must not over-silence
#
# The deliverable age is deliberately 600s: strictly between
# LEADV2_LANE_FRESH_S (120s, the LIES-01 freshness veto) and
# LEADV2_LANE_FINISHED_WINDOW_S (1800s), so neither the freshness veto nor a
# fresher-than-window artifact can mask the rule under test.
#
# Run: bash scripts/tests/test-finished-lane-no-escalation.sh
# Optional: ESCAL_FINISHED_ARTIFACT=<dir> also writes the mutation-control
# artifact (anchor=, baseline_rc=, mutated_rc=, red_line=) there.

# run-all-triggers: leadv2-lanes-snapshot.sh

set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/leadv2-temp.sh"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
SNAPSHOT_SH="${PLUGIN_DIR}/scripts/leadv2-lanes-snapshot.sh"
LIVENESS_SH="${PLUGIN_DIR}/scripts/leadv2-lane-liveness.sh"
STATE_PATH_SH="${PLUGIN_DIR}/scripts/leadv2-state-path.sh"

# The one regexp anchor of the finished-VERDICT consultation inside the veto
# (never a line number; asserted to match exactly once before mutating).
ANCHOR='if _lv_verdict.startswith("finished") and _lv_source != "git_commit":'
MUTATION_GATE='if False:  # ESCALATION-OFFERS-DESTRUCTIVE-DEFAULTS-FOR-FINISHED-LANES-01 mutation gate'

PASS=0; FAIL=0; ERRORS=()
log()  { printf -- '[TEST] %s\n' "$*"; }
pass() { PASS=$((PASS + 1)); log "PASS: $1"; }
fail() { FAIL=$((FAIL + 1)); ERRORS+=("FAIL: $1"); log "FAIL: $1"; }

CLEANUP_DIRS=()

cleanup() {
  for d in "${CLEANUP_DIRS[@]:-}"; do
    [[ -n "$d" && -d "$d" ]] && rm -rf "$d"
  done
  # Unconditional restore safety net: the production script must end
  # byte-identical to how this suite found it, on the failure path too.
  if [[ -f "${SNAPSHOT_SH}.escfin-orig" ]]; then
    cp "${SNAPSHOT_SH}.escfin-orig" "$SNAPSHOT_SH"
    rm -f "${SNAPSHOT_SH}.escfin-orig"
  fi
  rm -f "${SNAPSHOT_SH}.bak"
  return 0
}
trap cleanup EXIT

_new_fixture() {
  local repo state
  repo="$(lv2_mktemp_dir "efn-repo")"
  state="$(lv2_mktemp_dir "efn-state")"
  CLEANUP_DIRS+=("$repo" "$state")
  ( cd "$repo" && git init -q -b main \
      && git config user.email test@example.com && git config user.name test )
  lv2_assert_scratch_repo "$repo"
  mkdir -p "$repo/docs/leadv2" "$repo/docs/handoff"
  printf -- '%s %s\n' "$repo" "$state"
}

_commit_aged() { # <repo> <message> <age_s> -- backdate so commit_age_s() sees ~age_s
  local repo="$1" msg="$2" age="$3" ts
  ts="$(( $(date +%s) - age ))"
  ( cd "$repo" && GIT_AUTHOR_DATE="@${ts}" GIT_COMMITTER_DATE="@${ts}" \
      git commit --allow-empty -q -m "$msg" )
}

_touch_aged() { # <file> <age_s> -- backdate mtime portably (no BSD/GNU date flags)
  local file="$1" age="$2"
  touch "$file"
  python3 -c "
import datetime, os, sys
dt = datetime.datetime.now() - datetime.timedelta(seconds=int(sys.argv[1]))
os.utime(sys.argv[2], (dt.timestamp(), dt.timestamp()))
" "$age" "$file"
}

_active_yaml() {
  LEADV2_PROJECT_ROOT="$1" LEADV2_STATE_ROOT="$2" \
    PROJECT_ROOT="$1" bash "$STATE_PATH_SH" active.yaml
}

_reset_poll_state() { # <repo> <state> -- seed past the D-e reconcile grace
  local repo="$1" state="$2" snap
  snap="$(LEADV2_PROJECT_ROOT="$repo" CLAUDE_PROJECT_DIR="$repo" LEADV2_STATE_ROOT="$state" \
    PROJECT_ROOT="$repo" bash "$STATE_PATH_SH" .supervise-last.json)"
  mkdir -p "$(dirname "$snap")"
  printf -- '{"rendered_at":"2020-01-01T00:00:00+00:00","tasks":{},"reported_events":[],"dead_candidates":{},"reconcile_cycle_count":5}' > "$snap"
}

_row_present() {
  python3 -c "
import yaml
d = yaml.safe_load(open('$1')) or {}
print(any(s.get('task_id')=='$2' for s in d.get('sessions', [])))
"
}

# _escalation_offered <state> <tid> -> prints "<qfile>|<labels>" when the dead
# escalation question offering abandon/restart exists for tid, else "none".
# This is the assertion the mission cares about: the finished lane was OFFERED
# abandon/restart -- option labels, not question wording.
_escalation_offered() {
  python3 -c "
import glob, sys, yaml
state, tid = sys.argv[1], sys.argv[2]
for f in sorted(glob.glob(state + '/questions/q-*.yaml')):
    try:
        q = yaml.safe_load(open(f)) or {}
    except Exception:
        continue
    if str(q.get('task_id') or '') != tid:
        continue
    labels = [str(o.get('label') or '') for o in (q.get('options') or [])]
    if 'abandon' in labels or 'restart' in labels:
        print(f + '|' + ','.join(labels))
        sys.exit(0)
print('none')
" "$1" "$2"
}

_snapshot_poll() { # <repo> <state>
  # PROJECT_ROOT is threaded explicitly: the dead-escalation ask child
  # (leadv2-ask.sh -> leadv2-state-path.sh) resolves LINK_ROOT from PROJECT_ROOT
  # ONLY -- without it the ask falls back to THIS checkout's toplevel and
  # state-path correctly ABORTs (sandbox signal vs real repo), so the
  # question file the mutation gate asserts on would never be written.
  LEADV2_PROJECT_ROOT="$1" CLAUDE_PROJECT_DIR="$1" LEADV2_STATE_ROOT="$2" \
    PROJECT_ROOT="$1" bash "$SNAPSHOT_SH" --json >/dev/null 2>&1
}

_fixture_row() { # <repo> <state> <tid> <pid> [<deliverable 1|0>]
  local repo="$1" state="$2" tid="$3" pid="$4" with_deliverable="${5:-1}" active_path
  active_path="$(_active_yaml "$repo" "$state")"
  mkdir -p "$(dirname "$active_path")"
  cat > "$active_path" <<YAML
sessions:
  - task_id: ${tid}
    session_id: efn1
    started_at: "2020-01-01T00:00:00+00:00"
    phase: build
    pid: ${pid}
    pid_birth: null
    worktree: "${repo}"
    protocol_version: 2
    backend: terminal
    last_pulse_at: "2020-01-01T00:00:00+00:00"
    stale: false
YAML
  # A lane re-registered after a prior prune must not stay invisible to the
  # ladder: leadv2-lane-liveness.sh --all drops tombstoned tids from `lanes`,
  # so the stale tombstone from an earlier phase of this suite would leave
  # lane_liveness_by_id without a row and the finished consultation cold.
  local tomb_path
  tomb_path="$(LEADV2_PROJECT_ROOT="$repo" LEADV2_STATE_ROOT="$state" \
    PROJECT_ROOT="$repo" bash "$STATE_PATH_SH" tombstones.yaml)"
  if [[ -f "$tomb_path" ]]; then
    python3 -c "
import sys, yaml
path, tid = sys.argv[1], sys.argv[2]
rows = yaml.safe_load(open(path)) or []
keep = [r for r in rows if not (isinstance(r, dict) and str(r.get('task_id')) == tid)]
if len(keep) != len(rows):
    yaml.safe_dump(keep, open(path, 'w'), default_flow_style=False, sort_keys=False)
" "$tomb_path" "$tid" || true
  fi
  # Same freshness rule for prior escalation questions: Test 2's RED leaves
  # a q-*.yaml behind that would satisfy _escalation_offered in Test 3 even
  # though the reverted code asked nothing -- remove this tid's questions.
  if [[ -d "$state/questions" ]]; then
    python3 -c "
import glob, os, sys, yaml
state, tid = sys.argv[1], sys.argv[2]
for f in glob.glob(state + '/questions/q-*.yaml'):
    try:
        q = yaml.safe_load(open(f)) or {}
    except Exception:
        continue
    if str(q.get('task_id') or '') == tid:
        os.remove(f)
" "$state" "$tid" || true
  fi
  if [[ "$with_deliverable" == 1 ]]; then
    mkdir -p "$repo/docs/handoff/$tid"
    printf -- 'deliverable body\n' > "$repo/docs/handoff/$tid/report.full.md"
    _touch_aged "$repo/docs/handoff/$tid/report.full.md" 600
  else
    rm -rf "$repo/docs/handoff/$tid"
  fi
}

_dead_pid() {
  local p
  ( sleep 0 ) & p=$!
  wait "$p" 2>/dev/null || true
  printf '%s' "$p"
}

_ladder_verdict() { # <repo> <state> <tid>
  LEADV2_PROJECT_ROOT="$1" LEADV2_STATE_ROOT="$2" PROJECT_ROOT="$1" \
    timeout 120 bash "$LIVENESS_SH" --project-root "$1" --all --json 2>/dev/null \
    | python3 -c "
import json, sys
d = json.load(sys.stdin)
for row in d.get('lanes', []):
    if row.get('lane') == '$3':
        print(str(row.get('verdict') or ''))
        break
"
}

ARTIFACT_LINES=()

# ── Test 1: finished lane + gone pid -> NO escalation (baseline) ────────────
test_1_baseline_no_escalation() {
  local repo state tid dead_pid verdict offered present baseline_rc
  read -r repo state < <(_new_fixture)
  tid="EFN-FINISHED-01"
  dead_pid="$(_dead_pid)"
  # The 2026-09-04 shape: the row's worktree names the MAIN checkout whose
  # HEAD is OUTSIDE the finished window, while the lane's OWN worktree holds
  # a commit INSIDE the window and a fresh deliverable sits under
  # docs/handoff/<tid>/ -- only the ladder's finished verdict can see it.
  _commit_aged "$repo" "stale main head" 7200
  mkdir -p "$repo/.claude/worktrees/$tid"
  ( cd "$repo/.claude/worktrees/$tid" && git init -q -b main \
      && git config user.email test@example.com && git config user.name test \
      && git commit --allow-empty -q -m "lane finished work" )
  _fixture_row "$repo" "$state" "$tid" "$dead_pid" 1
  _reset_poll_state "$repo" "$state"

  verdict="$(_ladder_verdict "$repo" "$state" "$tid" || true)"
  if [[ "$verdict" != finished_unlanded:* ]]; then
    fail "Test 1: fixture broken -- ladder verdict must be finished_unlanded:* (got $verdict)"
    return
  fi

  baseline_rc=0
  _snapshot_poll "$repo" "$state" || baseline_rc=$?
  _snapshot_poll "$repo" "$state" || baseline_rc=$?
  present="$(_row_present "$(_active_yaml "$repo" "$state")" "$tid")"
  offered="$(_escalation_offered "$state" "$tid")"
  if [[ "$present" == True && "$offered" == none && "$baseline_rc" == 0 ]]; then
    pass "Test 1: finished lane (verdict=$verdict) + gone pid -> row kept, no abandon/restart question"
  else
    fail "Test 1: finished lane escalated -- present=$present offered=$offered rc=$baseline_rc (verdict=$verdict)"
  fi
  ARTIFACT_LINES+=("baseline_rc=${baseline_rc}")
}

# ── Test 2+3: mutation gate on the ladder-verdict consultation ──────────────
test_2_3_mutation_gate() {
  local repo state tid dead_pid anchor_count offered present mutated_rc red_line
  # Anchor must exist exactly once BEFORE any mutation (REGEXP, not line no).
  anchor_count="$(grep -cF "$ANCHOR" "$SNAPSHOT_SH" || true)"
  if [[ "$anchor_count" != 1 ]]; then
    fail "Test 2: anchor matched ${anchor_count}x (need exactly 1) in $SNAPSHOT_SH -- aborting mutation gate"
    return
  fi

  cp "$SNAPSHOT_SH" "${SNAPSHOT_SH}.escfin-orig"
  sed -i.bak "s|${ANCHOR}|${MUTATION_GATE}|" "$SNAPSHOT_SH"
  local mutated_anchor_count
  mutated_anchor_count="$(grep -cF "$ANCHOR" "$SNAPSHOT_SH" || true)"
  if [[ "$mutated_anchor_count" != 0 ]]; then
    fail "Test 2: sed did not remove the anchor (${mutated_anchor_count}x left) -- aborting"
    cp "${SNAPSHOT_SH}.escfin-orig" "$SNAPSHOT_SH"; rm -f "${SNAPSHOT_SH}.escfin-orig"
    return
  fi

  read -r repo state < <(_new_fixture)
  tid="EFN-MUTGATE-01"
  dead_pid="$(_dead_pid)"
  _commit_aged "$repo" "stale main head" 7200
  _fixture_row "$repo" "$state" "$tid" "$dead_pid" 1
  _reset_poll_state "$repo" "$state"

  mutated_rc=0
  _snapshot_poll "$repo" "$state" || mutated_rc=$?
  _snapshot_poll "$repo" "$state" || mutated_rc=$?
  present="$(_row_present "$(_active_yaml "$repo" "$state")" "$tid")"
  offered="$(_escalation_offered "$state" "$tid")"

  # RED: with the finished consultation removed, the finished lane is offered
  # abandon/restart again -- asserted on the option LABELS offered to it.
  if [[ "$present" == False && "$offered" != none ]]; then
    red_line="finished lane offered abandon/restart: question=$(basename "${offered%%|*}") labels=${offered##*|}"
    pass "Test 2: mutation removed the consultation -> $red_line (RED)"
  else
    red_line=""
    fail "Test 2: mutation did NOT re-enable escalation -- present=$present offered=$offered rc=$mutated_rc"
  fi
  ARTIFACT_LINES+=("mutated_rc=${mutated_rc}")
  [[ -n "$red_line" ]] && ARTIFACT_LINES+=("red_line=${red_line}")

  # Revert -> GREEN.
  cp "${SNAPSHOT_SH}.escfin-orig" "$SNAPSHOT_SH"
  rm -f "${SNAPSHOT_SH}.escfin-orig"
  _fixture_row "$repo" "$state" "$tid" "$dead_pid" 1
  _reset_poll_state "$repo" "$state"
  _snapshot_poll "$repo" "$state" || true
  _snapshot_poll "$repo" "$state" || true
  present="$(_row_present "$(_active_yaml "$repo" "$state")" "$tid")"
  offered="$(_escalation_offered "$state" "$tid")"
  if [[ "$present" == True && "$offered" == none ]]; then
    pass "Test 3: revert restores no-escalation (row kept, no question)"
  else
    fail "Test 3: revert still escalates -- present=$present offered=$offered"
  fi
}

# ── Test 4: genuine death still escalates exactly as today ──────────────────
test_4_genuine_death_still_escalates() {
  local repo state tid dead_pid offered present
  read -r repo state < <(_new_fixture)
  tid="EFN-GENUINE-DEAD-01"
  dead_pid="$(_dead_pid)"
  # No commit anywhere (unborn HEAD), no deliverable, gone pid.
  _fixture_row "$repo" "$state" "$tid" "$dead_pid" 0
  _reset_poll_state "$repo" "$state"
  _snapshot_poll "$repo" "$state" || true
  _snapshot_poll "$repo" "$state" || true
  present="$(_row_present "$(_active_yaml "$repo" "$state")" "$tid")"
  offered="$(_escalation_offered "$state" "$tid")"
  if [[ "$present" == False && "$offered" != none ]]; then
    pass "Test 4: no commit + no deliverable + gone pid -> still escalates ($offered)"
  else
    fail "Test 4: genuine death did not escalate -- present=$present offered=$offered (veto over-silences)"
  fi
}

test_1_baseline_no_escalation
test_2_3_mutation_gate
test_4_genuine_death_still_escalates

if [[ -n "${ESCAL_FINISHED_ARTIFACT:-}" ]]; then
  mkdir -p "$ESCAL_FINISHED_ARTIFACT"
  {
    printf -- 'anchor=%s\n' "$ANCHOR"
    printf -- 'anchor_matches=1\n'
    printf -- '%s\n' "${ARTIFACT_LINES[@]:-}"
  } > "${ESCAL_FINISHED_ARTIFACT}/mutation-control.txt"
fi

printf -- '[TEST] ===================================================================\n'
printf -- '[TEST] RESULTS: %d passed, %d failed\n' "$PASS" "$FAIL"
if [[ "$FAIL" -gt 0 ]]; then
  printf -- '%s\n' "${ERRORS[@]}"
  exit 1
fi
exit 0
