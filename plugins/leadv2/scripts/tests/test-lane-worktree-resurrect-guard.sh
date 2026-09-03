#!/usr/bin/env bash
# tests/test-lane-worktree-resurrect-guard.sh — T16 §11 (WORKTREE-
# RESURRECTOR-02): `ensure` may re-attach a worktree to a surviving
# worktree-<id> branch ONLY when the lane is registered in active.yaml AND
# has a live pid. Fresh ids (no surviving branch) are never gated; every
# infrastructure absence fails OPEN (re-creation allowed).
#
# Scratch repo per case (TEST-DESTROYS-PRODUCTION-SCRIPT-01 containment).
# Run: bash scripts/tests/test-lane-worktree-resurrect-guard.sh

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LANE_WT="${SCRIPT_DIR}/leadv2-lane-worktree.sh"
source "${SCRIPT_DIR}/leadv2-temp.sh"

PASS=0
FAIL=0
log()  { printf -- '[TEST] %s\n' "$*"; }
pass() { PASS=$(( PASS + 1 )); log "PASS: $1"; }
fail() { FAIL=$(( FAIL + 1 )); log "FAIL: $1"; }

bash -n "${LANE_WT}" 2>/dev/null && pass "bash -n leadv2-lane-worktree.sh" || fail "bash -n leadv2-lane-worktree.sh"

# A dead pid we can name: spawn+kill a sleeper, harvest its pid.
dead_pid() {
  local p
  sleep 30 & p=$!
  kill -9 "$p" 2>/dev/null; wait "$p" 2>/dev/null
  printf '%s' "$p"
}
DEAD_PID="$(dead_pid)"

# mk_repo <id> <active-yaml-or-""> — scratch repo whose lane <id> already has
# a surviving branch (worktree created, committed, worktree removed — branch
# kept, exactly the post-sweep state the resurrector abused).
mk_repo() { # <id> <active_yaml_content_or_empty>
  local id="$1" active="$2"
  local tmp; tmp="$(lv2_mktemp_dir resurrect-$id)"
  local repo="$tmp/repo"
  git init -q -b main "$repo"
  git -C "$repo" -c user.email=t@t -c user.name=t commit -q --allow-empty -m base
  LEADV2_PROJECT_ROOT="$repo" LEADV2_WORKTREE_DIR="$repo/.claude/worktrees" \
    LEADV2_LANE_RESURRECT_GUARD=0 bash "${LANE_WT}" ensure "$id" >/dev/null 2>&1
  # Simulate the sweep: remove the worktree, keep the branch.
  git -C "$repo" worktree remove --force "$repo/.claude/worktrees/$id" 2>/dev/null
  # LEADV2_STATE_ROOT sandboxes the control-plane resolver (state-path.sh
  # honors it as a test-only signal) so the fixture never touches the real
  # ~/.claude/leadv2-state tree.
  mkdir -p "$tmp/state-root"
  if [[ -n "$active" ]]; then
    printf '%s' "$active" > "$tmp/state-root/active.yaml"
  fi
  printf '%s' "$repo"
}

# Live registration row for <id> with pid $3.
reg_row() { # <id> <pid>
  printf 'sessions:\n  - task_id: %s\n    pid: %s\n    worktree: /nonexistent\n' "$1" "$2"
}

ensure_out() { # <repo> <id> [extra env as VAR=VAL...] -> stdout path only
  local repo="$1" id="$2"; shift 2
  env LEADV2_PROJECT_ROOT="$repo" \
      LEADV2_WORKTREE_DIR="$repo/.claude/worktrees" \
      LEADV2_STATE_ROOT="$repo/../state-root" \
      LEADV2_LANE_WORKTREE_ERRF="$repo/.errf" \
      "$@" bash "${LANE_WT}" ensure "$id" 2>"$repo/.stderr"
}

# A linked worktree's dir holds a ".git" FILE (not a dir); path-form-proof on
# macOS's /var vs /private/var, unlike grepping `worktree list --porcelain`.
wt_listed() { [[ -f "$1/.claude/worktrees/$2/.git" ]]; }

# ── T1: registered + LIVE pid -> re-create allowed ──────────────────────
REPO="$(mk_repo t1 "$(reg_row t1 $$)")"
OUT="$(ensure_out "$REPO" t1)"
if [[ "$OUT" == "$REPO/.claude/worktrees/t1" ]] && wt_listed "$REPO" t1; then
  pass "T1 registered + live pid: worktree re-created"
else
  fail "T1 registered + live pid: worktree re-created (out=$OUT)"
fi

# ── T2: registered + DEAD pid -> refused (shared-root fallback, no worktree)
REPO="$(mk_repo t2 "$(reg_row t2 "$DEAD_PID")")"
OUT="$(ensure_out "$REPO" t2)"
if [[ "$OUT" == "$REPO" ]] && ! wt_listed "$REPO" t2 \
   && grep -q "resurrection refused" "$REPO/.stderr"; then
  pass "T2 registered + dead pid: refused, no worktree, logged"
else
  fail "T2 registered + dead pid: refused, no worktree, logged (out=$OUT err=$(cat "$REPO/.stderr" 2>/dev/null))"
fi

# ── T3: not registered at all -> refused ────────────────────────────────
REPO="$(mk_repo t3 'sessions: []')"
OUT="$(ensure_out "$REPO" t3)"
if [[ "$OUT" == "$REPO" ]] && ! wt_listed "$REPO" t3 \
   && grep -q "resurrection refused" "$REPO/.stderr"; then
  pass "T3 unregistered lane: refused"
else
  fail "T3 unregistered lane: refused (out=$OUT)"
fi

# ── T4: kill switch -> re-create even when dead ─────────────────────────
REPO="$(mk_repo t4 "$(reg_row t4 "$DEAD_PID")")"
OUT="$(ensure_out "$REPO" t4 LEADV2_LANE_RESURRECT_GUARD=0)"
if [[ "$OUT" == "$REPO/.claude/worktrees/t4" ]] && wt_listed "$REPO" t4; then
  pass "T4 LEADV2_LANE_RESURRECT_GUARD=0: re-created (fail-open kill switch)"
else
  fail "T4 LEADV2_LANE_RESURRECT_GUARD=0: re-created (out=$OUT)"
fi

# ── T5: fresh id, no surviving branch, never registered -> created ──────
REPO="$(mk_repo t5 'sessions: []')"
OUT="$(ensure_out "$REPO" t5-fresh)"
if [[ "$OUT" == "$REPO/.claude/worktrees/t5-fresh" ]] && wt_listed "$REPO" t5-fresh \
   && ! grep -q "resurrection refused" "$REPO/.stderr"; then
  pass "T5 fresh id: gate not consulted, worktree created"
else
  fail "T5 fresh id: gate not consulted, worktree created (out=$OUT err=$(cat "$REPO/.stderr" 2>/dev/null))"
fi

# ── T6: branch survives but active.yaml MISSING -> fail-open re-create ──
REPO="$(mk_repo t6 "")"
OUT="$(ensure_out "$REPO" t6)"
if [[ "$OUT" == "$REPO/.claude/worktrees/t6" ]] && wt_listed "$REPO" t6; then
  pass "T6 no active.yaml (infra absent): fail-open, re-created"
else
  fail "T6 no active.yaml (infra absent): fail-open, re-created (out=$OUT err=$(cat "$REPO/.stderr" 2>/dev/null))"
fi

printf -- '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[[ "$FAIL" -eq 0 ]]
