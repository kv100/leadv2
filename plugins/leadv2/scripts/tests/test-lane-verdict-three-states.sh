#!/usr/bin/env bash
# tests/test-lane-verdict-three-states.sh — D2-UNBLIND-AND-THIRD-STATE-M0M1-01 (M1).
#
# The ladder in leadv2-lane-liveness.sh was two-valued at the bottom: a lane
# with no worker stream and no live pid fell to dead:no_handoff_dir /
# dead:no_log_artifact no matter WHAT else it had produced. The 2026-09-03
# incident: five workers finished, wrote docs/handoff/dispatch-<sig>/
# developer.full.md, landed no commit, and every one was declared dead --
# four re-dispatches each destroyed the previous round's only evidence.
#
# M1 adds rung E4 (the deliverable) so that shape resolves
# finished_unlanded:<age>s -- a SIBLING of finished: (consumers match
# finished*), emitted BEFORE dead:no_log_artifact can be reached -- plus an
# unknown:yaml_unreadable guard so an unreadable registry can never
# manufacture a terminal dead. Nothing is renamed: alive, starting:*, silent:*,
# dead:* and child keep their exact literals (leadv2-dispatch-ledger.sh:981,
# :1380, :1409 match them as literals).
#
# Fix round 2 (D2-E4-RESOLVES-THE-WRONG-DIR-01): E4 searched only
# docs/handoff/<tid>/, but the lead names lanes by FOUNDER task id and the
# funnel writes the deliverable to docs/handoff/dispatch-<sig8>/ -- so E4 was
# green in fixtures and inert in production (three live lanes, two with
# running workers, all read dead:no_log_artifact). Tests 10-12 use
# founder-shaped ids whose registry row carries the production log_path
# pointer: deliverable under the dispatch dir -> finished_unlanded; no
# deliverable anywhere -> still dead; dispatch dir present but UNREADABLE ->
# unknown (a check that could not look, never coerced to dead).
#
# This suite drives the REAL leadv2-lane-liveness.sh against scratch
# fixtures. It performs NO in-suite mutation of production scripts: the
# negative control for this lane is leadv2-mutation-control.sh (see
# docs/handoff/D2-SINGLE-LIVENESS-VERDICT/mutation-control/).
#
# Run: bash plugins/leadv2/scripts/tests/test-lane-verdict-three-states.sh

set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/leadv2-temp.sh"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
LIVENESS_SH="${PLUGIN_DIR}/scripts/leadv2-lane-liveness.sh"
STATE_PATH_SH="${PLUGIN_DIR}/scripts/leadv2-state-path.sh"

PASS=0; FAIL=0; ERRORS=()
log()  { printf -- '[TEST] %s\n' "$*"; }
pass() { PASS=$((PASS + 1)); log "PASS: $1"; }
fail() { FAIL=$((FAIL + 1)); ERRORS+=("FAIL: $1"); log "FAIL: $1"; }

CLEANUP_DIRS=()
_SLEEPER_PID=""

cleanup() {
  [[ -n "${_SLEEPER_PID}" ]] && kill "${_SLEEPER_PID}" 2>/dev/null || true
  wait "${_SLEEPER_PID}" 2>/dev/null || true
  for d in "${CLEANUP_DIRS[@]:-}"; do
    [[ -n "$d" && -d "$d" ]] && rm -rf "$d"
  done
  return 0
}
trap cleanup EXIT

_new_fixture() {
  # Deliberately NO seed commit: every fixture here needs a worktree with an
  # UNBORN HEAD so commit_age_s() returns None and the E4 rung under test is
  # isolated from the pre-existing finished: (E3) rung. Test 9 is the one
  # exception and makes its own commit (and verifies it landed).
  local repo state
  repo="$(lv2_mktemp_dir "d2ts-repo")"
  state="$(lv2_mktemp_dir "d2ts-state")"
  CLEANUP_DIRS+=("$repo" "$state")
  ( cd "$repo" && git init -q -b main \
      && git config user.email test@example.com && git config user.name test ) || return 1
  lv2_assert_scratch_repo "$repo"
  mkdir -p "$repo/docs/leadv2" "$repo/docs/handoff"
  printf -- '%s %s\n' "$repo" "$state"
}

_assert_unborn_head() { # <repo> — verify the fixture's own git setup
  if git -C "$1" log -1 >/dev/null 2>&1; then
    return 1
  fi
  return 0
}

_active_yaml() {
  LEADV2_PROJECT_ROOT="$1" LEADV2_STATE_ROOT="$2" \
    PROJECT_ROOT="$1" bash "$STATE_PATH_SH" active.yaml
}

_row_present() { # <active.yaml> <task_id> — re-read the registry (post-state, never rc)
  python3 -c "
import yaml
d = yaml.safe_load(open('$1')) or {}
print(any(s.get('task_id')=='$2' for s in d.get('sessions', [])))
"
}

_fixture_row() { # <active.yaml> <task_id> <pid> <repo> [log_path]
  local active="$1" tid="$2" pid="$3" repo="$4" log_path="${5:-}"
  cat > "$active" <<YAML
sessions:
  - task_id: ${tid}
    session_id: d2-${tid}
    started_at: "2020-01-01T00:00:00+00:00"
    phase: build
    pid: ${pid}
    pid_birth: null
    worktree: "${repo}"
    protocol_version: 2
    backend: terminal
    ${log_path:+log_path: "${log_path}"}
    last_pulse_at: "2020-01-01T00:00:00+00:00"
    stale: false
YAML
}

_dead_pid() {
  # A pid that has already exited by the time the caller reads it.
  local p
  ( sleep 0 ) & p=$!
  wait "$p" 2>/dev/null || true
  printf '%s' "$p"
}

_start_sleeper() { sleep 300 & _SLEEPER_PID=$!; }
_stop_sleeper() {
  [[ -n "${_SLEEPER_PID}" ]] && kill "${_SLEEPER_PID}" 2>/dev/null || true
  wait "${_SLEEPER_PID}" 2>/dev/null || true
  _SLEEPER_PID=""
}

_set_mtime_ago() { # <path> <seconds-ago>
  python3 -c "
import os, sys, time
os.utime(sys.argv[1], (time.time() - float(sys.argv[2]),) * 2)
" "$1" "$2"
}

_verdict() { # <repo> <state> <tid> -> the raw verdict string
  local out
  out="$(LEADV2_PROJECT_ROOT="$1" LEADV2_STATE_ROOT="$2" \
    bash "$LIVENESS_SH" --project-root "$1" --lane "$3" --no-codex --json 2>/dev/null || true)"
  printf '%s' "$out" | python3 -c "import json,sys; print(json.load(sys.stdin).get('verdict'))"
}

_json_field() { # <repo> <state> <tid> <python-expr over d>
  local out
  out="$(LEADV2_PROJECT_ROOT="$1" LEADV2_STATE_ROOT="$2" \
    bash "$LIVENESS_SH" --project-root "$1" --lane "$3" --no-codex --json 2>/dev/null || true)"
  printf '%s' "$out" | python3 -c "import json,sys; d=json.load(sys.stdin); print($4)"
}

# ── Test 1: THE INCIDENT — deliverable + no commits + dead pid -> finished_unlanded ──

test_1_deliverable_no_commit_is_finished_unlanded() {
  log "Test 1: dead pid + non-empty developer.full.md + unborn HEAD -> finished_unlanded:*, never dead:*"
  local repo state active_path tid dead_pid verdict
  read -r repo state < <(_new_fixture) || { fail "Test 1: fixture"; return; }
  active_path="$(_active_yaml "$repo" "$state")"
  mkdir -p "$(dirname "$active_path")"
  dead_pid="$(_dead_pid)"
  tid="D2-UNLANDED-ROUND"
  mkdir -p "$repo/docs/handoff/${tid}"
  printf -- '# developer.full.md\nRound complete; work described; nothing committed.\n' \
    > "$repo/docs/handoff/${tid}/developer.full.md"
  _fixture_row "$active_path" "$tid" "$dead_pid" "$repo"

  # Verify the fixture's own setup — a green test on a broken fixture is the
  # false-green this suite exists to prevent.
  [[ -s "$repo/docs/handoff/${tid}/developer.full.md" ]] || { fail "Test 1: setup — deliverable not non-empty on disk"; return; }
  [[ "$(_row_present "$active_path" "$tid")" == True ]] || { fail "Test 1: setup — registry row absent (post-state read)"; return; }
  _assert_unborn_head "$repo" || { fail "Test 1: setup — worktree unexpectedly has a commit"; return; }

  verdict="$(_verdict "$repo" "$state" "$tid")"
  if [[ "$verdict" =~ ^finished_unlanded:[0-9]+s$ ]] && [[ "$verdict" != dead:* ]]; then
    pass "Test 1: verdict=$verdict (finished_unlanded:*, never dead:*)"
  else
    fail "Test 1: verdict=$verdict (must match finished_unlanded:<age>s, never dead:*)"
  fi
}

# ── Test 1b: sibling-prefix contract — finished*) matches, dead:* does not ──

test_1b_sibling_prefix_contract() {
  log "Test 1b: a consumer case arm finished*) matches the new verdict; dead:* / silent:* / starting:* do not"
  local repo state active_path tid dead_pid verdict
  read -r repo state < <(_new_fixture) || { fail "Test 1b: fixture"; return; }
  active_path="$(_active_yaml "$repo" "$state")"
  mkdir -p "$(dirname "$active_path")"
  dead_pid="$(_dead_pid)"
  tid="D2-SIBLING-PREFIX"
  mkdir -p "$repo/docs/handoff/${tid}"
  printf -- 'summary\n' > "$repo/docs/handoff/${tid}/developer.summary.md"
  _fixture_row "$active_path" "$tid" "$dead_pid" "$repo"
  [[ -s "$repo/docs/handoff/${tid}/developer.summary.md" ]] || { fail "Test 1b: setup — deliverable not non-empty"; return; }

  verdict="$(_verdict "$repo" "$state" "$tid")"
  case "$verdict" in
    finished*) : ;;
    *) fail "Test 1b: verdict=$verdict does not match the finished* prefix consumers rely on"; return ;;
  esac
  case "$verdict" in
    dead:*|silent:*|starting:*|alive|child)
      fail "Test 1b: verdict=$verdict collided with a renamed existing literal" ;;
    *)
      pass "Test 1b: verdict=$verdict matches finished* and no existing literal" ;;
  esac
}

# ── Test 2: THE MIRROR — no deliverable, no commits -> still dead ──

test_2_no_deliverable_still_dead() {
  log "Test 2 (mirror): dead pid + handoff dir with NO deliverable, no commits -> dead:*, so state 3 was not bought by never reporting dead"
  local repo state active_path tid dead_pid verdict
  read -r repo state < <(_new_fixture) || { fail "Test 2: fixture"; return; }
  active_path="$(_active_yaml "$repo" "$state")"
  mkdir -p "$(dirname "$active_path")"
  dead_pid="$(_dead_pid)"
  tid="D2-GENUINELY-DEAD"
  mkdir -p "$repo/docs/handoff/${tid}"
  : > "$repo/docs/handoff/${tid}/notes.txt"
  _fixture_row "$active_path" "$tid" "$dead_pid" "$repo"
  [[ "$(_row_present "$active_path" "$tid")" == True ]] || { fail "Test 2: setup — registry row absent"; return; }

  verdict="$(_verdict "$repo" "$state" "$tid")"
  if [[ "$verdict" == dead:* ]]; then
    pass "Test 2: verdict=$verdict (dead:* — real death detection is intact)"
  else
    fail "Test 2: verdict=$verdict (must be dead:* — the third state must not swallow genuine death)"
  fi
}

test_2b_no_handoff_dir_still_dead() {
  log "Test 2b: dead pid + NO handoff dir at all -> dead:no_handoff_dir, never finished_unlanded"
  local repo state active_path tid dead_pid verdict
  read -r repo state < <(_new_fixture) || { fail "Test 2b: fixture"; return; }
  active_path="$(_active_yaml "$repo" "$state")"
  mkdir -p "$(dirname "$active_path")"
  dead_pid="$(_dead_pid)"
  tid="D2-NO-DIR-DEAD"
  _fixture_row "$active_path" "$tid" "$dead_pid" "$repo"
  [[ "$(_row_present "$active_path" "$tid")" == True ]] || { fail "Test 2b: setup — registry row absent"; return; }
  [[ ! -d "$repo/docs/handoff/${tid}" ]] || { fail "Test 2b: setup — dir unexpectedly exists"; return; }

  verdict="$(_verdict "$repo" "$state" "$tid")"
  if [[ "$verdict" == "dead:no_handoff_dir" ]]; then
    pass "Test 2b: verdict=$verdict"
  else
    fail "Test 2b: verdict=$verdict (must be dead:no_handoff_dir)"
  fi
}

# ── Test 3: unreadable / absent registry -> unknown:*, never dead ──

test_3_unreadable_registry_is_unknown() {
  log "Test 3: corrupt active.yaml / absent active.yaml + artifactless lane -> unknown:*, never dead:*"
  local repo state active_path tid dead_pid verdict
  read -r repo state < <(_new_fixture) || { fail "Test 3: fixture"; return; }
  active_path="$(_active_yaml "$repo" "$state")"
  mkdir -p "$(dirname "$active_path")"
  dead_pid="$(_dead_pid)"
  tid="D2-REGISTRY-UNREADABLE"
  _fixture_row "$active_path" "$tid" "$dead_pid" "$repo"

  printf -- 'sessions: [{{{{ not yaml at all' > "$active_path"
  [[ -f "$active_path" ]] || { fail "Test 3: setup — corrupt registry not written"; return; }
  verdict="$(_verdict "$repo" "$state" "$tid")"
  if [[ "$verdict" == unknown:* ]] && [[ "$verdict" != dead:* ]]; then
    pass "Test 3a: corrupt registry -> verdict=$verdict (unknown:*, never dead)"
  else
    fail "Test 3a: verdict=$verdict (must be unknown:*, never dead)"
  fi

  rm -f "$active_path"
  [[ ! -e "$active_path" ]] || { fail "Test 3: setup — registry still present after rm"; return; }
  verdict="$(_verdict "$repo" "$state" "$tid")"
  if [[ "$verdict" == unknown:* ]] && [[ "$verdict" != dead:* ]]; then
    pass "Test 3b: absent registry -> verdict=$verdict (unknown:*, never dead)"
  else
    fail "Test 3b: verdict=$verdict (must be unknown:*, never dead)"
  fi
}

# ── Test 4: -s guard — an empty placeholder report is not evidence ──

test_4_empty_deliverable_is_not_evidence() {
  log "Test 4: 0-byte developer.full.md -> dead:*, never finished_unlanded"
  local repo state active_path tid dead_pid verdict
  read -r repo state < <(_new_fixture) || { fail "Test 4: fixture"; return; }
  active_path="$(_active_yaml "$repo" "$state")"
  mkdir -p "$(dirname "$active_path")"
  dead_pid="$(_dead_pid)"
  tid="D2-EMPTY-REPORT"
  mkdir -p "$repo/docs/handoff/${tid}"
  : > "$repo/docs/handoff/${tid}/developer.full.md"
  _fixture_row "$active_path" "$tid" "$dead_pid" "$repo"
  [[ -f "$repo/docs/handoff/${tid}/developer.full.md" && ! -s "$repo/docs/handoff/${tid}/developer.full.md" ]] \
    || { fail "Test 4: setup — report must exist and be 0 bytes"; return; }

  verdict="$(_verdict "$repo" "$state" "$tid")"
  if [[ "$verdict" == dead:* ]]; then
    pass "Test 4: verdict=$verdict (placeholder report ignored, dead detection intact)"
  else
    fail "Test 4: verdict=$verdict (must be dead:* — an empty report is not finished evidence)"
  fi
}

# ── Test 5: mtime guard — a stale prior-round report is not fresh evidence ──

test_5_stale_deliverable_past_window_is_dead() {
  log "Test 5: deliverable mtime 7200s ago (> LEADV2_LANE_FINISHED_WINDOW_S 1800) -> dead:*, never finished_unlanded"
  local repo state active_path tid dead_pid verdict
  read -r repo state < <(_new_fixture) || { fail "Test 5: fixture"; return; }
  active_path="$(_active_yaml "$repo" "$state")"
  mkdir -p "$(dirname "$active_path")"
  dead_pid="$(_dead_pid)"
  tid="D2-STALE-REPORT"
  mkdir -p "$repo/docs/handoff/${tid}"
  printf -- 'prior round report\n' > "$repo/docs/handoff/${tid}/developer.full.md"
  _set_mtime_ago "$repo/docs/handoff/${tid}/developer.full.md" 7200
  _fixture_row "$active_path" "$tid" "$dead_pid" "$repo"
  [[ -s "$repo/docs/handoff/${tid}/developer.full.md" ]] || { fail "Test 5: setup — report missing"; return; }

  verdict="$(_verdict "$repo" "$state" "$tid")"
  if [[ "$verdict" == dead:* ]]; then
    pass "Test 5: verdict=$verdict (stale report from a prior round does not read as freshly finished)"
  else
    fail "Test 5: verdict=$verdict (must be dead:* — age past the finished window)"
  fi
}

# ── Test 6: newest non-empty report wins (summary.md counts; stale full.md cannot mask it) ──

test_6_summary_md_and_newest_wins() {
  log "Test 6: fresh *.summary.md alone -> finished_unlanded; stale full.md + fresh summary.md -> finished_unlanded (newest wins)"
  local repo state active_path tid dead_pid verdict
  read -r repo state < <(_new_fixture) || { fail "Test 6: fixture"; return; }
  active_path="$(_active_yaml "$repo" "$state")"
  mkdir -p "$(dirname "$active_path")"
  dead_pid="$(_dead_pid)"
  tid="D2-SUMMARY-ONLY"
  mkdir -p "$repo/docs/handoff/${tid}"
  printf -- 'exec summary\n' > "$repo/docs/handoff/${tid}/developer.summary.md"
  _fixture_row "$active_path" "$tid" "$dead_pid" "$repo"
  [[ -s "$repo/docs/handoff/${tid}/developer.summary.md" ]] || { fail "Test 6: setup — summary report missing"; return; }
  verdict="$(_verdict "$repo" "$state" "$tid")"
  if [[ "$verdict" == finished_unlanded:* ]]; then
    pass "Test 6a: verdict=$verdict (*.summary.md alone is deliverable evidence)"
  else
    fail "Test 6a: verdict=$verdict (must be finished_unlanded:*)"
  fi

  # stale full.md (7200s) next to the fresh summary.md above: the NEWEST
  # non-empty report must decide, not the first glob hit.
  printf -- 'prior round\n' > "$repo/docs/handoff/${tid}/developer.full.md"
  _set_mtime_ago "$repo/docs/handoff/${tid}/developer.full.md" 7200
  [[ -s "$repo/docs/handoff/${tid}/developer.full.md" ]] || { fail "Test 6: setup — stale full.md missing"; return; }
  verdict="$(_verdict "$repo" "$state" "$tid")"
  if [[ "$verdict" == finished_unlanded:* ]]; then
    pass "Test 6b: verdict=$verdict (stale full.md did not mask the fresh summary.md)"
  else
    fail "Test 6b: verdict=$verdict (must be finished_unlanded:* — newest non-empty report wins)"
  fi
}

# ── Test 7: a LIVE pid outranks the deliverable — never finished while the worker runs ──

test_7_live_pid_with_deliverable_is_not_finished() {
  log "Test 7: live worker pid + deliverable on disk -> silent:* (C2 floor), never finished_unlanded / dead"
  local repo state active_path tid verdict
  read -r repo state < <(_new_fixture) || { fail "Test 7: fixture"; return; }
  active_path="$(_active_yaml "$repo" "$state")"
  mkdir -p "$(dirname "$active_path")"
  tid="D2-LIVE-WRITER"
  mkdir -p "$repo/docs/handoff/${tid}"
  printf -- 'half-written report\n' > "$repo/docs/handoff/${tid}/developer.full.md"
  _start_sleeper
  _fixture_row "$active_path" "$tid" "$_SLEEPER_PID" "$repo"
  [[ -s "$repo/docs/handoff/${tid}/developer.full.md" ]] || { fail "Test 7: setup — report missing"; return; }
  [[ "$(_row_present "$active_path" "$tid")" == True ]] || { fail "Test 7: setup — registry row absent"; return; }

  verdict="$(_verdict "$repo" "$state" "$tid")"
  if [[ "$verdict" == silent:* ]]; then
    pass "Test 7: verdict=$verdict (live worker mid-report is silent, never finished_unlanded)"
  else
    fail "Test 7: verdict=$verdict (must be silent:* — E4 only fires once process evidence says not-alive)"
  fi
  _stop_sleeper
}

# ── Test 8: E3 still outranks E4 — a landed commit reads finished:, not finished_unlanded ──

test_8_landed_commit_still_finished() {
  log "Test 8: dead pid + recent commit + deliverable -> finished:* (E3 above E4), never finished_unlanded"
  local repo state active_path tid dead_pid verdict
  read -r repo state < <(_new_fixture) || { fail "Test 8: fixture"; return; }
  active_path="$(_active_yaml "$repo" "$state")"
  mkdir -p "$(dirname "$active_path")"
  dead_pid="$(_dead_pid)"
  tid="D2-LANDED-ROUND"
  mkdir -p "$repo/docs/handoff/${tid}"
  printf -- 'round report\n' > "$repo/docs/handoff/${tid}/developer.full.md"
  # The ONE fixture with a commit — and its own load-sensitive-commit guard:
  # verify the commit exists on disk before trusting it (a discarded-status
  # commit inside ( … ) produced a false red in this repo on 2026-09-03).
  ( cd "$repo" && git commit --allow-empty -q -m "landed work" ) \
    || { fail "Test 8: setup — commit command failed"; return; }
  git -C "$repo" rev-parse --verify HEAD >/dev/null 2>&1 \
    || { fail "Test 8: setup — commit did not land (fixture setup status check)"; return; }
  _fixture_row "$active_path" "$tid" "$dead_pid" "$repo"
  [[ -s "$repo/docs/handoff/${tid}/developer.full.md" ]] || { fail "Test 8: setup — report missing"; return; }

  verdict="$(_verdict "$repo" "$state" "$tid")"
  if [[ "$verdict" == finished:* ]] && [[ "$verdict" != finished_unlanded:* ]]; then
    pass "Test 8: verdict=$verdict (commit outranks deliverable — ladder order intact)"
  else
    fail "Test 8: verdict=$verdict (must be finished:* without the unlanded suffix)"
  fi
}

# ── Test 9: JSON evidence trail — source/reason/age_s identify the rung ──

test_9_json_evidence_trail() {
  log "Test 9: --json row carries source=deliverable, reason=no_pid_recent_deliverable, numeric age_s"
  local repo state active_path tid dead_pid src reason age
  read -r repo state < <(_new_fixture) || { fail "Test 9: fixture"; return; }
  active_path="$(_active_yaml "$repo" "$state")"
  mkdir -p "$(dirname "$active_path")"
  dead_pid="$(_dead_pid)"
  tid="D2-JSON-TRAIL"
  mkdir -p "$repo/docs/handoff/${tid}"
  printf -- 'report\n' > "$repo/docs/handoff/${tid}/developer.full.md"
  _fixture_row "$active_path" "$tid" "$dead_pid" "$repo"
  [[ -s "$repo/docs/handoff/${tid}/developer.full.md" ]] || { fail "Test 9: setup — report missing"; return; }

  src="$(_json_field "$repo" "$state" "$tid" "d.get('source')")"
  reason="$(_json_field "$repo" "$state" "$tid" "d.get('reason')")"
  age="$(_json_field "$repo" "$state" "$tid" "d.get('age_s')")"
  if [[ "$src" == "deliverable" && "$reason" == "no_pid_recent_deliverable" && "$age" =~ ^[0-9]+$ ]]; then
    pass "Test 9: source=$src reason=$reason age_s=$age"
  else
    fail "Test 9: source=$src reason=$reason age_s=$age"
  fi
}

# ── Test 10: fix round 2 — founder-shaped id, deliverable under the DISPATCH dir ──

test_10_founder_id_finds_dispatch_dir_deliverable() {
  log "Test 10: founder-shaped id + row log_path -> dispatch-<sig8>/ deliverable -> finished_unlanded:*, never dead:*"
  local repo state active_path tid dead_pid verdict
  read -r repo state < <(_new_fixture) || { fail "Test 10: fixture"; return; }
  active_path="$(_active_yaml "$repo" "$state")"
  mkdir -p "$(dirname "$active_path")"
  dead_pid="$(_dead_pid)"
  tid="SOME-TASK-NAME-01"
  # Production shape, as measured on main 2026-09-04: the founder-named dir
  # holds planning artifacts only; the deliverable lives under dispatch-<sig8>.
  mkdir -p "$repo/docs/handoff/${tid}" "$repo/docs/handoff/dispatch-c3a41e77"
  printf -- 'class: Standard\n' > "$repo/docs/handoff/${tid}/task-class.yaml"
  printf -- '# developer.full.md\nRound complete; nothing committed.\n' \
    > "$repo/docs/handoff/dispatch-c3a41e77/developer.full.md"
  _fixture_row "$active_path" "$tid" "$dead_pid" "$repo" \
    "docs/handoff/dispatch-c3a41e77/developer.stream.jsonl"
  [[ -s "$repo/docs/handoff/dispatch-c3a41e77/developer.full.md" ]] \
    || { fail "Test 10: setup — dispatch-dir deliverable missing"; return; }
  [[ ! -e "$repo/docs/handoff/${tid}/developer.full.md" && ! -e "$repo/docs/handoff/${tid}/developer.summary.md" ]] \
    || { fail "Test 10: setup — tid dir must hold NO deliverable (the production shape)"; return; }
  [[ "$(_row_present "$active_path" "$tid")" == True ]] || { fail "Test 10: setup — registry row absent"; return; }

  verdict="$(_verdict "$repo" "$state" "$tid")"
  if [[ "$verdict" =~ ^finished_unlanded:[0-9]+s$ ]] && [[ "$verdict" != dead:* ]]; then
    pass "Test 10: verdict=$verdict (founder id reached the dispatch-dir deliverable)"
  else
    fail "Test 10: verdict=$verdict (must be finished_unlanded:<age>s — E4 resolved the wrong dir)"
  fi
}

# ── Test 11: fix round 2 — founder-shaped id, NO deliverable anywhere → still dead ──

test_11_founder_id_no_deliverable_anywhere_still_dead() {
  log "Test 11: founder-shaped id + dispatch dir with NO report -> dead:*, so the fix did not make every lane look finished"
  local repo state active_path tid dead_pid verdict
  read -r repo state < <(_new_fixture) || { fail "Test 11: fixture"; return; }
  active_path="$(_active_yaml "$repo" "$state")"
  mkdir -p "$(dirname "$active_path")"
  dead_pid="$(_dead_pid)"
  tid="SOME-DEAD-TASK-01"
  mkdir -p "$repo/docs/handoff/${tid}" "$repo/docs/handoff/dispatch-99b1d0e4"
  printf -- 'planning note\n' > "$repo/docs/handoff/${tid}/brain.yaml"
  printf -- 'admitted\n' > "$repo/docs/handoff/dispatch-99b1d0e4/admission-receipt.yaml"
  _fixture_row "$active_path" "$tid" "$dead_pid" "$repo" \
    "docs/handoff/dispatch-99b1d0e4/developer.stream.jsonl"
  [[ ! -e "$repo/docs/handoff/dispatch-99b1d0e4/developer.full.md" && ! -e "$repo/docs/handoff/dispatch-99b1d0e4/developer.summary.md" ]] \
    || { fail "Test 11: setup — dispatch dir must hold no report"; return; }

  verdict="$(_verdict "$repo" "$state" "$tid")"
  if [[ "$verdict" == dead:* ]]; then
    pass "Test 11: verdict=$verdict (genuine death intact from a founder-shaped id)"
  else
    fail "Test 11: verdict=$verdict (must be dead:* — the third state must not swallow real death)"
  fi
}

# ── Test 12: fix round 2 — dispatch dir EXISTS but cannot be READ → unknown ──

test_12_unreadable_dispatch_dir_is_unknown() {
  log "Test 12: founder-shaped id + chmod-000 dispatch dir -> unknown:*, never dead:* / finished_unlanded:*"
  local repo state active_path tid dead_pid verdict ddir
  read -r repo state < <(_new_fixture) || { fail "Test 12: fixture"; return; }
  active_path="$(_active_yaml "$repo" "$state")"
  mkdir -p "$(dirname "$active_path")"
  dead_pid="$(_dead_pid)"
  tid="SOME-BLIND-TASK-01"
  ddir="$repo/docs/handoff/dispatch-7f00ca11"
  mkdir -p "$repo/docs/handoff/${tid}" "$ddir"
  printf -- 'planning note\n' > "$repo/docs/handoff/${tid}/brain.yaml"
  printf -- 'invisible report\n' > "$ddir/developer.full.md"
  chmod 000 "$ddir"
  _fixture_row "$active_path" "$tid" "$dead_pid" "$repo" \
    "docs/handoff/dispatch-7f00ca11/developer.stream.jsonl"
  # Fixture self-check: if the platform did not actually block reads (e.g.
  # running as root), this test cannot assert what it exists to assert -- fail
  # loudly rather than pass silently on an unenforced precondition.
  if python3 -c "import os,sys; os.listdir(sys.argv[1])" "$ddir" 2>/dev/null; then
    chmod 700 "$ddir"
    fail "Test 12: setup — chmod 000 did not block listdir on this platform; refusing to assert"
    return
  fi

  verdict="$(_verdict "$repo" "$state" "$tid")"
  chmod 700 "$ddir"
  if [[ "$verdict" == unknown:* ]] && [[ "$verdict" != dead:* ]] && [[ "$verdict" != finished_unlanded:* ]]; then
    pass "Test 12: verdict=$verdict (a dir E4 could not look at is unknown, never dead)"
  else
    fail "Test 12: verdict=$verdict (must be unknown:* — an unreadable deliverable dir is never evidence of death)"
  fi
}

test_1_deliverable_no_commit_is_finished_unlanded
test_1b_sibling_prefix_contract
test_2_no_deliverable_still_dead
test_2b_no_handoff_dir_still_dead
test_3_unreadable_registry_is_unknown
test_4_empty_deliverable_is_not_evidence
test_5_stale_deliverable_past_window_is_dead
test_6_summary_md_and_newest_wins
test_7_live_pid_with_deliverable_is_not_finished
test_8_landed_commit_still_finished
test_9_json_evidence_trail
test_10_founder_id_finds_dispatch_dir_deliverable
test_11_founder_id_no_deliverable_anywhere_still_dead
test_12_unreadable_dispatch_dir_is_unknown

echo
log "==================================================================="
log "RESULTS: $PASS passed, $FAIL failed"
if [[ $FAIL -gt 0 ]]; then
  for e in "${ERRORS[@]}"; do log "$e"; done
  exit 1
fi
exit 0
