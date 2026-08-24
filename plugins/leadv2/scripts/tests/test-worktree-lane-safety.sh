#!/usr/bin/env bash
# test-worktree-lane-safety.sh — SWEEPER-LANE-SAFETY-01.
#
# WHY THIS TEST EXISTS (founder, 2026-08-24, «свипер починить на уровне плагина»):
# two same-day incidents. Lane 43ae4318 was deleted outright by
# leadv2-worktree-cleanup.sh --sweep-dead — worktree remove --force + branch -D —
# before its worker ever committed (a fresh lane is ahead=0, clean, and
# dead:no_log_artifact by every existing check). Lane b413968c was gutted to a
# single docs/ dir by the merged-sweep hook, whose orchestration-dirt discard
# ran BEFORE the removal decision, so a refused removal left a husk.
#
# The fix is a shared protection gate (scripts/lib/leadv2-worktree-protected.sh)
# consulted by BOTH unattended sweepers: a worktree registered in active.yaml,
# arm-open, carrying a live registered pid, or younger than
# LEADV2_SWEEP_MIN_AGE_H is untouchable; any control-plane read error fails
# closed (nothing swept). These cases pin each probe, the fail-closed
# direction, the no-husk removal ordering, and that a true orphan is STILL
# swept — the gate must not become a second GC that never fires.
#
# Every case runs against BOTH sweepers (the SessionStart merged-sweep hook and
# cleanup --sweep-dead), red-first against the pre-fix binaries from git HEAD
# where a pre-fix binary is available. No test touches the real
# ~/.claude/leadv2-state/: LEADV2_STATE_ROOT points the control plane into the
# fixture. No test spawns a worker — P4 uses a plain `sleep` pid.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="${SCRIPT_DIR}/../../hooks/leadv2-merged-worktree-sweep.sh"
CLEANUP="${SCRIPT_DIR}/../leadv2-worktree-cleanup.sh"
CLOSE_SH="${SCRIPT_DIR}/../leadv2-dispatch-product-close.sh"

PASS=0; FAIL=0; GREEN_PRE_FIX=0
declare -a ERRORS=()
log() { printf '[TEST] %s\n' "$*"; }

WORK="$(mktemp -d "${TMPDIR:-/tmp}/wt-lane-safety.XXXXXX")"
declare -a SLEEP_PIDS=()
cleanup() {
  for p in "${SLEEP_PIDS[@]}"; do kill "$p" 2>/dev/null || true; done
  rm -rf "${WORK}"
}
trap cleanup EXIT

REPO="$(cd "${SCRIPT_DIR}" && git rev-parse --show-toplevel 2>/dev/null)"

# Pre-fix binaries for the red-first dual pass. The hook is standalone; the
# pre-fix cleanup sits in a scratch mirror of scripts/ whose siblings are
# symlinks to the current tree (it sources leadv2-branch-merged.sh and calls
# leadv2-lane-liveness.sh from its own directory).
PRE_HOOK=""; PRE_CLEANUP=""
if [[ -n "${REPO}" ]]; then
  PRE_HOOK="${WORK}/pre-hook.sh"
  git -C "${REPO}" show "HEAD:plugins/leadv2/hooks/leadv2-merged-worktree-sweep.sh" > "${PRE_HOOK}" 2>/dev/null || : > "${PRE_HOOK}"
  [[ -s "${PRE_HOOK}" ]] && chmod +x "${PRE_HOOK}" || PRE_HOOK=""
  PRE_DIR="${WORK}/pre-mirror/plugins/leadv2/scripts"
  mkdir -p "${PRE_DIR}"
  git -C "${REPO}" show "HEAD:plugins/leadv2/scripts/leadv2-worktree-cleanup.sh" > "${PRE_DIR}/leadv2-worktree-cleanup.sh" 2>/dev/null || :
  if [[ -s "${PRE_DIR}/leadv2-worktree-cleanup.sh" ]]; then
    for s in leadv2-branch-merged.sh leadv2-lane-liveness.sh leadv2-state-path.sh; do
      ln -s "${SCRIPT_DIR}/../${s}" "${PRE_DIR}/${s}" 2>/dev/null || true
    done
    PRE_CLEANUP="${PRE_DIR}/leadv2-worktree-cleanup.sh"
  else
    PRE_CLEANUP=""
  fi
fi

# ── fixture ──────────────────────────────────────────────────────────────────
# A repo with ONE merged, clean lane worktree and a fixture control plane
# (state/active.yaml with sessions: [] — the live steady state). age controls
# the creation-stamped gitdir and fallback directory mtimes: `old` backdates
# both past any plausible grace window so only the probe under test can protect
# the lane.
_mk() { # <dir> [age:young|old]
  local d="$1" age="${2:-old}"
  mkdir -p "$d/docs/leadv2"
  git -C "$d" init -q -b main
  git -C "$d" config user.email t@t && git -C "$d" config user.name t
  echo seed > "$d/seed.txt"; echo notes > "$d/docs/leadv2/open-threads.md"
  git -C "$d" add -A && git -C "$d" commit -qm seed
  mkdir -p "$d/.claude/worktrees"
  git -C "$d" worktree add -q -b worktree-lane "$d/.claude/worktrees/lane" main 2>/dev/null
  mkdir -p "$d/state"
  printf 'sessions: []\n' > "$d/state/active.yaml"
  if [[ "$age" == "old" ]]; then
    touch -t 202001010000 "$d/.claude/worktrees/lane"
    touch -t 202001010000 "$(git -C "$d/.claude/worktrees/lane" rev-parse --git-dir)/gitdir"
  fi
}

_active_with_session() { # <repo> [pid]
  local d="$1" pid="${2:-}"
  {
    printf 'sessions:\n- task_id: lane\n  class: standard\n'
    printf '  worktree: %s/.claude/worktrees/lane\n' "$d"
    printf "  branch: worktree-lane\n  started_at: '2020-01-01T00:00:00Z'\n"
    [[ -n "$pid" ]] && printf '  pid: %s\n' "$pid"
  } > "$d/state/active.yaml"
}

_run() { # <kind:hook|dead> <bin> <repo>  (env: caller-exported)
  if [[ "$1" == "hook" ]]; then
    ( cd "$3" && CLAUDE_PROJECT_DIR="$3" bash "$2" >/dev/null 2>&1 )
  else
    ( cd "$3" && LEADV2_PROJECT_ROOT="$3" bash "$2" --sweep-dead >/dev/null 2>&1 )
  fi
}

_gone() { [[ ! -d "$1/.claude/worktrees/lane" ]]; }
_lane() { printf '%s/.claude/worktrees/lane' "$1"; }
_gitdir_stamp() { git -C "$1" rev-parse --git-dir 2>/dev/null; }
_set_mtime() { # <path> <epoch>; portable across BSD/GNU touch variants
  python3 -c 'import os, sys; os.utime(sys.argv[1], (int(sys.argv[2]), int(sys.argv[2])))' "$1" "$2"
}

# ── cases ────────────────────────────────────────────────────────────────────

# P1: registered in active.yaml (any state) -> never swept.
case_p1_registered() { # <kind> <bin>
  local repo="${WORK}/p1-$RANDOM$RANDOM"; _mk "$repo" || return 2
  _active_with_session "$repo"
  export LEADV2_STATE_ROOT="$repo/state" LEADV2_SWEEP_MIN_AGE_H=0
  _run "$1" "$2" "$repo"
  ! _gone "$repo"
}

# P2: arm-registered marker, no ledger row -> arm open -> never swept.
case_p2_arm_open() { # <kind> <bin>
  local repo="${WORK}/p2-$RANDOM$RANDOM"; _mk "$repo" || return 2
  mkdir -p "$repo/docs/handoff/dispatch-lane"
  : > "$repo/docs/handoff/dispatch-lane/arm-registered"
  export LEADV2_STATE_ROOT="$repo/state" LEADV2_SWEEP_MIN_AGE_H=0
  _run "$1" "$2" "$repo"
  ! _gone "$repo"
}

# P3: arm-registered + TRUE terminal (landed) ledger row -> protection lapses
# -> swept. The gate must not become a never-fire GC.
case_p3_arm_terminal() { # <kind> <bin>
  local repo="${WORK}/p3-$RANDOM$RANDOM"; _mk "$repo" || return 2
  mkdir -p "$repo/docs/handoff/dispatch-lane"
  : > "$repo/docs/handoff/dispatch-lane/arm-registered"
  printf '{"ts":"2026-08-24T00:00:00Z","task_sig":"lane","founder_task_id":"lane","terminal":"landed","cause":"test","evidence":"t"}\n' \
    > "$repo/state/dispatch-ledger.jsonl"
  export LEADV2_STATE_ROOT="$repo/state" LEADV2_SWEEP_MIN_AGE_H=0
  _run "$1" "$2" "$repo"
  _gone "$repo"
}

# P4: registered row whose pid is a live process -> never swept. No worker is
# spawned — a plain sleep stands in for one.
case_p4_live_pid() { # <kind> <bin>
  local repo="${WORK}/p4-$RANDOM$RANDOM"; _mk "$repo" || return 2
  sleep 300 & local spid=$!
  SLEEP_PIDS+=("$spid")
  _active_with_session "$repo" "$spid"
  export LEADV2_STATE_ROOT="$repo/state" LEADV2_SWEEP_MIN_AGE_H=0
  _run "$1" "$2" "$repo"
  ! _gone "$repo"
}

# P5: no registration at all, but mtime = now -> the grace window (default 48h)
# is the only protection during the worktree-add -> registration gap.
case_p5_young() { # <kind> <bin>
  local repo="${WORK}/p5-$RANDOM$RANDOM"; _mk "$repo" young || return 2
  unset LEADV2_SWEEP_MIN_AGE_H
  export LEADV2_STATE_ROOT="$repo/state"
  _run "$1" "$2" "$repo"
  ! _gone "$repo"
}

# P6: true orphan — no row, no handoff, old, merged, clean -> swept, AND the
# sweep journals worktree_swept so a human can tell why without git forensics.
case_p6_orphan_swept_and_journaled() { # <kind> <bin>
  local repo="${WORK}/p6-$RANDOM$RANDOM"; _mk "$repo" || return 2
  export LEADV2_STATE_ROOT="$repo/state" LEADV2_SWEEP_MIN_AGE_H=0
  _run "$1" "$2" "$repo"
  _gone "$repo" || return 1
  grep -q 'worktree_swept id=lane reason=' "$repo/docs/leadv2/tasks/lane/journal.md" 2>/dev/null
}

# P7: corrupted active.yaml -> NOTHING swept (a P6-grade orphan present in the
# same repo survives) and one message says the registry could not be read.
case_p7_unreadable_registry() { # <kind> <bin>
  local repo="${WORK}/p7-$RANDOM$RANDOM"; _mk "$repo" || return 2
  printf '\x00\x00not: [yaml' > "$repo/state/active.yaml"
  export LEADV2_STATE_ROOT="$repo/state" LEADV2_SWEEP_MIN_AGE_H=0
  local err="${WORK}/p7.err"
  if [[ "$1" == "hook" ]]; then
    ( cd "$repo" && CLAUDE_PROJECT_DIR="$repo" bash "$2" >/dev/null 2>"$err" )
  else
    ( cd "$repo" && LEADV2_PROJECT_ROOT="$repo" bash "$2" --sweep-dead >/dev/null 2>"$err" )
  fi
  ! _gone "$repo" && grep -q 'protected(read-error)' "$err"
}

# P8: malformed LEADV2_SWEEP_MIN_AGE_H degrades to 48 — it must not abort the
# pass for the other worktrees; a backdated orphan is still swept.
case_p8_malformed_env() { # <kind> <bin>
  local repo="${WORK}/p8-$RANDOM$RANDOM"; _mk "$repo" || return 2
  export LEADV2_STATE_ROOT="$repo/state" LEADV2_SWEEP_MIN_AGE_H=abc
  _run "$1" "$2" "$repo"
  _gone "$repo"
}

# P9 (hook only): merged lane, orchestration-only dirt, removal made to fail
# (worktree lock). The tree is either intact or gone — NEVER a husk with its
# docs/ working state wiped. Pre-fix, the discard ran before the removal
# decision and produced exactly that husk (incident b413968c).
case_p9_no_gutting() { # <kind> <bin>
  local repo="${WORK}/p9-$RANDOM$RANDOM"; _mk "$repo" || return 2
  echo touched >> "$(_lane "$repo")/docs/leadv2/open-threads.md"
  git -C "$repo" worktree lock "$(_lane "$repo")" 2>/dev/null
  export LEADV2_STATE_ROOT="$repo/state" LEADV2_SWEEP_MIN_AGE_H=0
  _run hook "$2" "$repo"
  [[ -d "$(_lane "$repo")" ]] || return 0   # gone is acceptable
  grep -q 'touched' "$(_lane "$repo")/docs/leadv2/open-threads.md" 2>/dev/null
}

# P10 (static): the hook's _MW_ORCH_RE still matches its twin in
# leadv2-dispatch-product-close.sh — re-asserted here so this suite is the
# single place the sweeper contract lives; do not regress the existing test.
case_p10_twin() {
  local a b
  a="$(grep -oE "_MW_ORCH_RE='[^']*'" "${HOOK}" 2>/dev/null | head -1 | sed "s/^_MW_ORCH_RE=//")"
  b="$(grep -oE "_PC_PORCELAIN_EXCLUDE_RE='[^']*'" "${CLOSE_SH}" 2>/dev/null | head -1 | sed "s/^_PC_PORCELAIN_EXCLUDE_RE=//")"
  [[ -n "$a" && -n "$b" && "$a" == "$b" ]]
}

# P11: the immutable linked-worktree gitdir timestamp, not the mutable
# worktree-directory timestamp, owns probe D. A top-level touch must not keep
# an otherwise abandoned lane alive indefinitely.
case_p11_age_from_gitdir() { # <kind> <bin>
  local repo="${WORK}/p11-$RANDOM$RANDOM" lane gitdir old_epoch
  _mk "$repo" || return 2
  lane="$(_lane "$repo")"
  gitdir="$(_gitdir_stamp "$lane")/gitdir"
  old_epoch=$(( $(date +%s) - 86400 ))
  _set_mtime "$gitdir" "$old_epoch" || return 2
  touch "$lane"
  unset LEADV2_SWEEP_MIN_AGE_S
  export LEADV2_STATE_ROOT="$repo/state" LEADV2_SWEEP_MIN_AGE_H=0
  _run "$1" "$2" "$repo"
  _gone "$repo"
}

# P12: the seconds setting has precedence over the legacy hours setting. A
# five-minute-old orphan stays within the explicit one-hour grace window.
case_p12_min_age_s_precedence() { # <kind> <bin>
  local repo="${WORK}/p12-$RANDOM$RANDOM" lane gitdir recent_epoch
  _mk "$repo" || return 2
  lane="$(_lane "$repo")"
  gitdir="$(_gitdir_stamp "$lane")/gitdir"
  recent_epoch=$(( $(date +%s) - 300 ))
  _set_mtime "$gitdir" "$recent_epoch" || return 2
  export LEADV2_STATE_ROOT="$repo/state" LEADV2_SWEEP_MIN_AGE_H=0 LEADV2_SWEEP_MIN_AGE_S=3600
  _run "$1" "$2" "$repo"
  ! _gone "$repo"
}

# ── runner ───────────────────────────────────────────────────────────────────

run_case() { # <name> <fn> <kind>
  local name="$1" fn="$2" kind="$3" pre post pre_rc post_rc
  # P12 is the sole seconds-precedence case. Keep its explicit setting from
  # becoming ambient configuration for the next independently-run case.
  [[ "$name" == P12-* ]] || unset LEADV2_SWEEP_MIN_AGE_S
  case "$kind" in
    hook) pre="${PRE_HOOK}"; post="${HOOK}" ;;
    dead) pre="${PRE_CLEANUP}"; post="${CLEANUP}" ;;
  esac
  if [[ -n "${pre}" ]]; then "${fn}" "$kind" "$pre" >/dev/null 2>&1; pre_rc=$?; else pre_rc=2; fi
  "${fn}" "$kind" "$post" >/dev/null 2>&1; post_rc=$?
  if [[ ${post_rc} -ne 0 ]]; then
    FAIL=$((FAIL + 1)); ERRORS+=("${name}: post-fix rc=${post_rc}")
    log "FAIL: ${name} -- post-fix rc=${post_rc}, expected 0"; return
  fi
  if [[ ${pre_rc} -eq 0 ]]; then
    GREEN_PRE_FIX=$((GREEN_PRE_FIX + 1))
    log "GREEN-PRE-FIX: ${name} -- also passed pre-fix; a safety invariant, not evidence of this fix"
    return
  fi
  PASS=$((PASS + 1)); log "RED-then-GREEN: ${name} (pre_rc=${pre_rc} -> post_rc=0)"
}

log "PASS: bash -n sweep hook + cleanup + lib"
bash -n "${HOOK}" || { log "FAIL: bash -n hook"; exit 1; }
bash -n "${CLEANUP}" || { log "FAIL: bash -n cleanup"; exit 1; }
bash -n "${SCRIPT_DIR}/../lib/leadv2-worktree-protected.sh" || { log "FAIL: bash -n lib"; exit 1; }

for kind in hook dead; do
  run_case "P1-registered-lane-kept(${kind})"        case_p1_registered "$kind"
  run_case "P2-arm-open-lane-kept(${kind})"          case_p2_arm_open "$kind"
  run_case "P3-arm-terminal-lane-swept(${kind})"     case_p3_arm_terminal "$kind"
  run_case "P4-live-pid-lane-kept(${kind})"          case_p4_live_pid "$kind"
  run_case "P5-young-lane-kept(${kind})"             case_p5_young "$kind"
  run_case "P6-orphan-swept-and-journaled(${kind})"  case_p6_orphan_swept_and_journaled "$kind"
  run_case "P7-unreadable-registry-sweeps-nothing(${kind})" case_p7_unreadable_registry "$kind"
  run_case "P8-malformed-env-degrades(${kind})"      case_p8_malformed_env "$kind"
  run_case "P11-age-from-gitdir-not-dirmtime(${kind})" case_p11_age_from_gitdir "$kind"
  run_case "P12-min-age-s-precedence(${kind})"      case_p12_min_age_s_precedence "$kind"
done
run_case "P9-failed-removal-never-guts(hook)"        case_p9_no_gutting hook

if case_p10_twin; then
  PASS=$((PASS + 1)); log "RED-then-GREEN: P10-twin-regex-unchanged"
else
  FAIL=$((FAIL + 1)); ERRORS+=("P10-twin-regex-unchanged")
  log "FAIL: P10-twin-regex-unchanged"
fi

echo ""
echo "Results: ${PASS} passed(red->green), ${FAIL} failed, ${GREEN_PRE_FIX} green-pre-fix"
if [[ ${FAIL} -gt 0 ]]; then printf 'FAIL: %s\n' "${ERRORS[@]}"; exit 1; fi
exit 0
