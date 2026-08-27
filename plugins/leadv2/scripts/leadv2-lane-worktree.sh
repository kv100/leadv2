#!/usr/bin/env bash
# leadv2-lane-worktree.sh — one git worktree per leadv2 lane, on its own branch.
#
# WHY THIS EXISTS (LANE-WORKTREE-ISOLATION-01, 2026-07-27): every leadv2 lane
# used to run in the ONE shared main checkout with ONE shared git index. That
# single fact clobbered docs/tasks.yaml twice in one day (92763d76 reverted 89
# statuses / deleted 32 rows from a base that never saw the 03:04 reconcile;
# dc22ad79 reverted 47af84254005 done->queued while filing an unrelated task),
# swept one lane's staged code into an unrelated docs commit (b74d70d6,
# SD-SHARED-INDEX-SWEPT-A-COMMIT-01 — explicit `git add <paths>` is not enough,
# only `git commit <paths>` is), and killed a lane that read another lane's
# half-written file (SD-LANES-HAVE-NO-WORKTREE-01).
#
# SD-LANES-HAVE-NO-WORKTREE-01 found the precise gap: Phase 0 of `/leadv2` is
# specified to call the EnterWorktree tool, but headless fanout children never
# reliably do — `git worktree list` showed only the main tree while N lanes
# edited it concurrently. leadv2-fanout.sh's own header claimed isolation "is
# handled by Phase 0 of the spawned session itself"; that assumption is false
# for headless/tmux/windowed children. This script is the deterministic,
# bash-level fix: leadv2-fanout.sh calls `ensure` BEFORE launching a lane and
# runs the child with cwd = the returned worktree, so isolation no longer
# depends on the spawned session's own tool-call judgment.
#
# Reuse, not reinvention: this script only CREATES the lane worktree. It uses
# the SAME path/branch convention EnterWorktree itself uses
# (.claude/worktrees/<name>, branch worktree-<name>), so the machinery that
# already exists downstream applies unchanged:
#   - Landing: Phase 6 `ExitWorktree(action="keep")` + leadv2-deploy-merge.sh,
#     which already does a divergence preflight + rebase + FF-ONLY merge (a
#     real conflict on overlapping docs/tasks.yaml edits is a loud non-zero
#     exit + merge-blocker.flag, never a silent pick-one-side) + `git push`.
#     leadv2-deploy-merge.sh already resolves the task branch as
#     `task/$TASK_ID` or `worktree-$TASK_ID` — this script only ever creates
#     the latter, so no changes were needed there.
#   - Reaping: Phase 8 `leadv2-worktree-cleanup.sh --name "$TASK_ID"` (already
#     called from commands/leadv2.md's Phase 8 step, success path only).
#
# Ops:
#   ensure <task_id> [class]   create the lane worktree+branch if absent
#                              (idempotent), print the ABS worktree path to
#                              stdout. On ANY failure: log loud to stderr and
#                              print PROJECT_ROOT (legacy shared tree) so
#                              dispatch NEVER hard-breaks — isolation degrades
#                              to the old behavior, it does not stop the lane.
#   path-of <task_id>          print the lane's ABS worktree path, or "" if no
#                              worktree exists for that task.
#
# Env:
#   LEADV2_PROJECT_ROOT   repo whose main checkout lanes fork from (required;
#                         falls back to the git toplevel of cwd).
#   LEADV2_WORKTREE_DIR   parent dir for lane worktrees
#                         (default $ROOT/.claude/worktrees — same dir
#                         EnterWorktree and leadv2-worktree-cleanup.sh use).
#   LEADV2_LANE_WORKTREE  on|off (default on). off => ensure prints PROJECT_ROOT
#                         and creates nothing (legacy escape hatch / kill-switch).
#   LEADV2_LANE_BASE      ref to fork the lane from (default: origin/main if it
#                         exists, else main, else HEAD).
#   LEADV2_LANE_WORKTREE_ERRF  stderr capture file (default /tmp/pe-lane-worktree.err).
#
# Branch naming: refs/heads/worktree-<task_id>  (matches EnterWorktree +
#                                                 leadv2-deploy-merge.sh)
# Worktree path:  $LEADV2_WORKTREE_DIR/<task_id>  (== .claude/worktrees/<task_id>)
#
# Exit codes: 0 always (ensure/path-of never block a lane; ensure falls back to
# the shared tree on any git failure instead of failing the dispatch).
set -u

# --- helpers -----------------------------------------------------------------
log()       { printf '[lane-worktree] %s\n' "$*" >&2; }
log_error() { printf '[lane-worktree] ERROR: %s\n' "$*" >&2; }

ERRF="${LEADV2_LANE_WORKTREE_ERRF:-/tmp/pe-lane-worktree.err}"
ROOT=""

# NESTED-LANE-WORKTREES-01: map any repo path to the MAIN checkout.
#
# `rev-parse --show-toplevel` inside a linked worktree returns THAT WORKTREE, and a
# worker running inside a lane exports LEADV2_PROJECT_ROOT pointing at its own lane —
# so both inputs to resolve_root read "the lane" when a child dispatch asks for "the
# repo". The child lane was then created at .claude/worktrees/<parent>/.claude/
# worktrees/<child>, where nothing reaps it: `git worktree prune` sees a live
# directory and the merged-sweep skips it because the parent is dirty. Seven such
# lanes had accumulated in persona-engine by 2026-08-22.
#
# --git-common-dir is the same for a main checkout and every worktree of it (it is
# the shared .git), so its parent is the main checkout in both cases. Fails open:
# anything unexpected leaves the input untouched, and dispatch continues as before.
main_checkout_of() { # <path> -> main checkout, or the input unchanged
  local p="$1" common
  [[ -n "$p" ]] || { printf '%s' "$p"; return; }
  common="$(git -C "$p" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)" || common=""
  # Older git has no --path-format; resolve the possibly-relative answer by hand.
  if [[ -z "$common" ]]; then
    common="$(git -C "$p" rev-parse --git-common-dir 2>/dev/null)" || common=""
    [[ -n "$common" && "$common" != /* ]] && common="$(cd "$p" && cd "$common" 2>/dev/null && pwd)"
  fi
  [[ -n "$common" ]] || { printf '%s' "$p"; return; }
  local top; top="$(dirname "$common")"
  # A bare repo has no work tree above .git — keep the caller's path.
  [[ -d "$top" ]] && git -C "$top" rev-parse --is-inside-work-tree >/dev/null 2>&1 || {
    printf '%s' "$p"; return
  }
  # Already the main checkout: hand BACK THE CALLER'S PATH, never our resolved one.
  # git answers in physical form (/private/var on macOS) while callers pass the
  # logical /var, and downstream code compares these strings — rewriting the path
  # form on the common case would be a silent behaviour change for every dispatch,
  # not just the nested one. Only an actual relocation may change the string.
  if [[ "$( (cd "$top" 2>/dev/null && pwd -P) )" == "$( (cd "$p" 2>/dev/null && pwd -P) )" ]]; then
    printf '%s' "$p"
  else
    printf '%s' "$top"
  fi
}

resolve_root() {
  [[ -n "$ROOT" ]] && return
  ROOT="${LEADV2_PROJECT_ROOT:-$(git -C "${PWD:-.}" rev-parse --show-toplevel 2>/dev/null || true)}"
  # Whatever we were handed — env or cwd — lanes belong to the main checkout.
  [[ -n "$ROOT" ]] && ROOT="$(main_checkout_of "$ROOT")"
  if [[ -z "$ROOT" ]] || ! git -C "$ROOT" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    log_error "could not resolve a git repo root (set LEADV2_PROJECT_ROOT or run inside a repo)"
    ROOT=""
  fi
}

# Latest main-ish ref to fork from: origin/main (saw sibling landings) > main
# > HEAD. Echoes the choice.
pick_base() {
  if git -C "$ROOT" rev-parse --verify -q origin/main >/dev/null 2>&1; then printf 'origin/main'
  elif git -C "$ROOT" rev-parse --verify -q main >/dev/null 2>&1; then printf 'main'
  else printf 'HEAD'; fi
}

# Print the shared tree (legacy cwd) — the safe fallback when isolation cannot
# be created. Dispatch continues; isolation is simply off for this lane.
fallback() {
  resolve_root
  printf '%s\n' "$ROOT"
}

lane_branch() { printf 'worktree-%s' "$1"; }
lane_dir()    { printf '%s/.claude/worktrees' "$ROOT"; }

# Resolve a path to its PHYSICAL form. macOS symlinks /tmp -> /private/tmp and
# /var -> /private/var; git's `worktree list --porcelain` reports the physical
# path, so any equality check against the as-given path mis-matches on macOS
# (production runs on a mac). Falls back to the as-given path if unresolvable.
phys() { ( cd "$1" 2>/dev/null && pwd -P ) 2>/dev/null || printf '%s' "$1"; }

# --- ops ---------------------------------------------------------------------
# WORKTREE-RESURRECTOR-02 (T16 §11): 0 = allow creation, 1 = refuse. The lane's
# worktree was removed but its branch survived (the dead-lane sweeps keep
# unmerged branches for merge triage); any later `ensure` for the same id used
# to silently re-attach a fresh worktree to that branch, resurrecting dead
# lanes (20 dirs / 132 branches accumulated by 2026-08-27). Re-creation is now
# allowed ONLY for a lane that is BOTH registered in active.yaml AND has a
# live pid — a lane a dispatcher/runner is actively (re)driving, which
# registers itself before spawning. Reuses the sweeper-protection lib's ONE
# primed view of the control plane (no second reader). Fail-open on any
# infrastructure absence: kill switch, missing lib, unreadable active.yaml.
resurrection_allowed() { # <task_id>
  local tid="$1" lib
  [[ "${LEADV2_LANE_RESURRECT_GUARD:-1}" == "0" ]] && return 0
  lib="$(dirname "${BASH_SOURCE[0]}")/lib/leadv2-worktree-protected.sh"
  [[ -f "$lib" ]] || return 0
  # shellcheck source=lib/leadv2-worktree-protected.sh
  source "$lib" || return 0
  lv2_wt_protect_prime "$ROOT" >/dev/null 2>&1
  [[ -z "$LV2_WT_PROTECT_ERR" ]] || return 0
  _lv2_wt_pid_alive "$tid" && return 0
  return 1
}

# ensure <task_id> [class]
cmd_ensure() {
  local task_id="${1:-}"
  # class is accepted for forward-compat (e.g. future per-class worktree dirs);
  # it does not change behavior today.
  local _class="${2:-standard}"
  resolve_root
  if [[ -z "$task_id" ]]; then
    log_error "ensure: <task_id> required"
    fallback; return 0
  fi
  if [[ -z "$ROOT" ]]; then fallback; return 0; fi

  # Kill-switch / explicit opt-out: legacy shared tree.
  if [[ "${LEADV2_LANE_WORKTREE:-on}" == "off" ]]; then
    fallback; return 0
  fi

  local wt_dir="${LEADV2_WORKTREE_DIR:-$(lane_dir)}"
  local lane_path="$wt_dir/$task_id"
  local branch; branch="$(lane_branch "$task_id")"

  # T11-D2: prune BEFORE the idempotent reuse check below -- a stale git admin entry
  # (.git/worktrees/<id>) whose directory was deleted by a crashed prior attempt would
  # otherwise still satisfy the reuse check's `worktree list --porcelain` grep, handing
  # back a lane_path with no real worktree at all (live-verified 2026-08-26 on lane
  # 92484d63: active.yaml recorded branch=main, no .claude/worktrees/92484d63/.git
  # existed). A live worktree's admin entry always has an intact directory, so prune
  # never touches it.
  git -C "$ROOT" worktree prune 2>/dev/null || true

  # Idempotent: an existing linked worktree is reused as-is. Compare on the
  # PHYSICAL path — git reports /private/var on macOS, not the /var we passed.
  if [[ -d "$lane_path" ]] && git -C "$ROOT" worktree list --porcelain 2>/dev/null | grep -q "^worktree $(phys "$lane_path")\$"; then
    # Reused worktrees need this too: every lane that predates
    # CODEX-WORKTREE-TRUST-01 exists on disk already and was never registered.
    codex_trust_worktree "$lane_path"
    printf '%s\n' "$lane_path"
    return 0
  fi

  # WORKTREE-RESURRECTOR-02 (T16 §11): no worktree here, but the lane's branch
  # survived a sweep — this `ensure` is a RE-create of a known lane, not a
  # fresh dispatch. Refuse unless the lane is live (registered + live pid).
  # On refusal ensure falls back to the shared root per its never-block
  # contract; fanout/fork-session assert isolated lanes and refuse to spawn,
  # so a dead lane is never silently re-run. Fresh ids (no surviving branch)
  # never reach this gate.
  if [[ ! -d "$lane_path" ]] \
     && git -C "$ROOT" rev-parse --verify -q "refs/heads/${branch}" >/dev/null 2>&1 \
     && ! resurrection_allowed "$task_id"; then
    log_error "ensure: resurrection refused for task=$task_id (branch ${branch} exists but lane not live in active.yaml — WORKTREE-RESURRECTOR-02) — FALLING BACK to shared tree"
    fallback
    return 0
  fi

  local base; base="${LEADV2_LANE_BASE:-$(pick_base)}"
  mkdir -p "$wt_dir"

  # T11-D2 cont'd: the prune above cleared any stale git admin entry; what's left here
  # is a non-git leftover directory (state dirs, no .git) that isn't registered with git
  # at all. `worktree add` refuses a non-empty target, so clear it -- prune already ruled
  # out that git still considers this path a live worktree.
  if [[ -e "$lane_path" ]] && ! git -C "$ROOT" worktree list --porcelain 2>/dev/null | grep -q "^worktree $(phys "$lane_path")\$"; then
    rm -rf -- "$lane_path"
  fi

  # T11-F2: the branch is born with one empty anchor commit ("lane <id> anchor"),
  # so the lane is provably 1 commit ahead of default from birth (it merges
  # cleanly later -- an empty commit never conflicts). The "dead + truly-empty
  # lane -> swept" fast path this was previously dropped for
  # (test-lane-worktree-isolation.sh, leadv2-worktree-cleanup.sh --sweep-dead /
  # --name) is NOT regressed: both now recognize a sole ahead=1 commit whose
  # subject matches the anchor pattern as still-empty for GC purposes, so a
  # genuinely dead/untouched lane stays sweepable without --force.
  #
  # Fresh branch from base + linked worktree.
  if git -C "$ROOT" worktree add -b "$branch" "$lane_path" "$base" >>"$ERRF" 2>&1; then
    git -C "$lane_path" commit --allow-empty -m "lane ${task_id} anchor" >>"$ERRF" 2>&1 || true
    codex_trust_worktree "$lane_path"
    printf '%s\n' "$lane_path"
    return 0
  fi
  # Branch may already exist from a prior aborted run — attach the worktree to it.
  if git -C "$ROOT" worktree add "$lane_path" "$branch" >>"$ERRF" 2>&1; then
    codex_trust_worktree "$lane_path"
    printf '%s\n' "$lane_path"
    return 0
  fi
  log_error "ensure: git worktree add failed for task=$task_id base=$base (see $ERRF) — FALLING BACK to shared tree"
  fallback
  return 0
}

# CODEX-WORKTREE-TRUST-01: teach Codex to trust this lane's worktree.
#
# Codex reads its per-directory policy from [projects."<exact cwd>"] in
# ~/.codex/config.toml. A worktree is a directory Codex has never seen, and in
# an unregistered cwd it opens a task thread, prints its three startup lines,
# and exits 0 having produced NO body at all -- the review engine then records
# `review_body_lost` and the round is burned. Nothing logs an error, which is
# why this cost two review rounds on 2026-08-21 before the cause was read off
# the config instead of the code. The leadv2 repo's own worktrees were already
# registered by hand; product repos' were not, so every worktree lane silently
# lost its Codex arm.
#
# Fail-open by construction: any missing file, unwritable config, or absent
# python3 leaves lane creation untouched. Registration is idempotent on the
# exact path, and mirrors the 4-key stanza the working entries already use.
codex_trust_worktree() { # <abs_worktree_path>
  local lane_path="${1:-}"
  [[ -n "$lane_path" ]] || return 0
  [[ "${LEADV2_CODEX_WORKTREE_TRUST:-on}" == "off" ]] && return 0
  local cfg="${CODEX_HOME:-$HOME/.codex}/config.toml"
  [[ -f "$cfg" && -w "$cfg" ]] || return 0
  command -v python3 >/dev/null 2>&1 || return 0
  # Register BOTH the logical and the physical path: git reports /private/var on
  # macOS while the caller passes /var, and Codex matches on the exact cwd string.
  local p
  for p in "$lane_path" "$(phys "$lane_path")"; do
    [[ -n "$p" ]] || continue
    grep -qF "[projects.\"$p\"]" "$cfg" 2>/dev/null && continue
    printf '\n[projects."%s"]\ntrust_level = "trusted"\napproval_policy = "never"\nsandbox_mode = "danger-full-access"\nnetwork_access = "enabled"\n' \
      "$p" >>"$cfg" 2>/dev/null || return 0
  done
  return 0
}

# path-of <task_id>  -> ABS path or "" (no output)
cmd_path_of() {
  local task_id="${1:-}"
  resolve_root
  [[ -z "$ROOT" || -z "$task_id" ]] && return 0
  local wt_dir="${LEADV2_WORKTREE_DIR:-$(lane_dir)}"
  local lane_path="$wt_dir/$task_id"
  if [[ -d "$lane_path" ]] && git -C "$ROOT" worktree list --porcelain 2>/dev/null | grep -q "^worktree $(phys "$lane_path")\$"; then
    printf '%s\n' "$lane_path"
  fi
}

# --- dispatch ----------------------------------------------------------------
usage() {
  cat >&2 <<'EOF'
usage: leadv2-lane-worktree.sh <op> <task_id> [class]
  op        ensure | path-of
  task_id   the lane's task id (branch worktree-<task_id>, worktree <task_id>)
  class     optional, forward-compat (ensure only)
env: LEADV2_PROJECT_ROOT, LEADV2_WORKTREE_DIR, LEADV2_LANE_WORKTREE=on|off,
     LEADV2_LANE_BASE, LEADV2_LANE_WORKTREE_ERRF

Landing and reaping a lane are NOT this script's job — reuse the existing
machinery: Phase 6 ExitWorktree(keep) + leadv2-deploy-merge.sh (ff-only merge,
conflicts loudly) lands it; Phase 8 `leadv2-worktree-cleanup.sh --name <id>`
reaps it.
EOF
}

case "${1:-}" in
  ensure)   shift; cmd_ensure "$@" ;;
  path-of)  shift; cmd_path_of "$@" ;;
  -h|--help) usage; exit 0 ;;
  *)        usage; exit 2 ;;
esac
