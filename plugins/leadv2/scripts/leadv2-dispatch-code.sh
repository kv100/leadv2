#!/usr/bin/env bash
# leadv2-dispatch-code.sh — the single funnel for out-of-pipeline code-writing dispatch.
# ROUTING-ENFORCEMENT-01 / R1 (founder P1, 2026-07-25). Authoritative spec:
#   docs/handoff/ROUTING-ENFORCEMENT-01/design.md
#
# ONE PATH (T13-SLICE2-01, 2026-08-26): this script IS the canonical dispatch door -- every
# out-of-pipeline spawn (atomic_dispatch_reserve_spawn_confirm, atomic_dispatch_reserve_
# confirm_opus, cmd_advance_arm) resolves its model and records its build-phase gate here, in
# one of these three call sites, and nowhere else. Arm SELECTION at those spawn sites is
# route_arbiter-gated at exactly FOUR sites, all in this file: cmd_resolve's initial
# candidate-chain resolve (T17 primary), its bench-fallback re-entry (ARBITER-BENCH-FALLBACK-
# GAP-01), its exit76_receipt continuation (T13-SLICE1 W3), and cmd_advance_arm's arm_advance
# re-arbitration (T13 slice2 fix-round F1) -- no spawn path may pick an arm by static chain
# position alone; the arbiter re-runs over the remaining arms and journals
# route_headroom_chosen before the spawn, failing open to the static pick only on an arbiter
# fault. leadv2-fanout.sh / leadv2-fanout-lane-
# launcher.sh are NOT a second dispatch path or supervisor-only leftovers -- they are the
# daemon self-spawn backend (leadv2-self-spawn.sh via leadv2-session-spawner.sh,
# LEADV2_DAEMON=1) and the fork-session backend, and both DELEGATE into this funnel for the
# actual model resolution + spawn rather than resolving a model themselves. The architect
# prepass (ARCHITECT_PREPASS_* below) is likewise not a separate pre-path -- it has always
# lived inside this file's own Phase-2 step, awaited before Build, with Trivial-class waivers;
# there was never a standalone prepass script to fold in. (Founder scope decision, answer b to
# q-d0d2fc6a: fanout stays on disk; C1 was re-scoped to documenting this, not deleting it.)
#
# PROBLEM THIS SOLVES
#   Out-of-pipeline dev has no router: the lead calls Agent(...) or glm-coder.sh directly
#   and is itself the router, so it picks a model on every dispatch and forgets. The in-
#   pipeline resolver (leadv2-router.sh) only governs /leadv2 phases. This script gives
#   out-of-pipeline dev the same shape: ONE dispatch door that reads the SAME routing
#   policy and RESOLVES the model, so the lead never names a model for code work.
#
# WHAT IT DOES (P1 scope)
#   1. ROUTER: reads `glm_policy` from .claude/ref/leadv2-routing.yaml (single source of
#      truth — same block leadv2-router.sh:197-252 reads), applies the same precedence of
#      sonnet_exceptions / opus_only_mission_kinds predicates, and resolves arm=glm|sonnet
#      (opus arms are reported but NOT auto-dispatched — those stay lead judgment). Emits
#      and journals `route_resolved by=router model=<arm> task=<sig8> rule=<id>`.
#   2. ANTI-DOUBLE-SPEND: a task-signature ledger refuses a SECOND dispatch of the same
#      normalized mission (one task = one model), and a review ledger refuses a SECOND
#      review of the same diff-hash (one review). Refusals are journaled.
#
# KILL SWITCH / NO-OP
#   LEADV2_DISPATCH_ENFORCE=0 -> dedup checks are skipped (resolve+journal still run, no
#   refuse), so existing dispatch is unaffected when the router is "off". Default 1.
#   LEADV2_DISPATCH_SPAWN=0 (or --no-spawn) -> resolve+journal only, no worker launched
#   (e.g. for dedup-only tests). Default 1 (spawn IS the default — see WHAT IT DOES §3).
#   Ledger dirs honor LEADV2_DISPATCH_CACHE_DIR (default ~/.claude/cache) so tests are
#   hermetic and never touch the real cache. LEADV2_DISPATCH_GLM_BIN / _SUBSESSION_BIN
#   override the launchers (test seams; each launcher owns its own stub hooks —
#   GLM_CLAUDE_BIN/GLM_RUNS_DIR/GLM_SECRETS_FILE for glm-coder.sh, LEADV2_DRY_RUN for
#   claude-subsession.sh — this script does not duplicate their stubbing logic).
#
# WHAT IT DOES (R1 FIX, 2026-07-25 — adversarial-review Critical #2)
#   3. SPAWN: resolve+record is not enough on its own -- a routed dispatch that only
#      journals and exits deadlocks (the fence denied the original Agent() call; nothing
#      ever relaunches the work). By DEFAULT (kill switch LEADV2_DISPATCH_SPAWN=0 / flag
#      --no-spawn) this script now actually LAUNCHES the resolved worker and returns
#      immediately with its handle: arm=glm -> `glm-coder.sh bg` (detaches via its own
#      setsid+disown, prints a run-id); arm=sonnet -> `claude-subsession.sh` without
#      --wait (setsid_wrapper+exec detaches the backgrounded `claude` process itself,
#      SD-SONNET-ARM-DETACH-01, prints PID+SESSION_ID, exits immediately). Both
#      launchers already own "detach, never block the caller" -- this script does not
#      duplicate that logic, only calls it. arm=opus is never spawned (lead judgment,
#      unchanged). A `worker_spawned by=router model=<arm> task=<sig8> handle=<h>` line is
#      journaled/emitted so a spawn is never silent.
#
# SCOPE NOTES (what this P1 deliberately does NOT do — later design phases)
#   - Does NOT auto-fallback GLM->Sonnet (design §3(c), Phase 4).
#   - Does NOT add the Bash/code-review PreToolUse fences (design Phase 2/4).
#   The resolver predicates mirror leadv2-router.sh:225-252; if that copy changes, update
#   both (Phase 3 extracts a shared `--resolve-glm` sub-mode — until then THIS is the
#   out-of-pipeline copy and the yaml is the single source of the active exception LIST).
#
# WHAT IT DOES (R1 FIX PASS 2, 2026-07-25 — 4 operational bugs from adversarial review)
#   4. The dispatch-ledger reservation (item 2 above) used to be PERMANENT the instant it
#      was written, before the worker was ever confirmed alive. Three bugs fell out of that:
#      (a) a launch failure left the reservation standing -> the identical retry was refused
#          as a duplicate forever (dead task, no path back to GLM/Sonnet).
#      (b) a no-op launcher (exits 0, spawns nothing -- e.g. LEADV2_DISPATCH_GLM_BIN=/bin/true)
#          emitted `worker_spawned` with an EMPTY handle and consumed the reservation: a
#          silent no-op that looked like a successful dispatch.
#      (c) --no-spawn (dry-run/resolve-only) still wrote the SAME permanent reservation, so a
#          preview call poisoned the ledger for the real dispatch that followed it.
#      FIX: the reservation is now provisional. spawn_worker() requires a non-empty handle
#      AND verifies liveness before reporting success (glm: the launcher's own `status`
#      subcommand resolves a live run-dir without this script duplicating its path logic;
#      sonnet: `kill -0` on the PID parsed from claude-subsession.sh's handle line). Any
#      spawn failure (rc!=0, empty handle, or dead liveness check) OR a --no-spawn dry-run
#      rolls the reservation back (originally via a separately-locked atomic_dispatch_
#      rollback() -- FIX PASS 3 below replaced that with a rollback done INSIDE the SAME
#      held lock as the reservation write, closing a race the separate-lock shape left
#      open; see item 5) -- the identical mission is retryable on the next call in every
#      one of those three cases. A caller-supplied
#      `--glm-failures` count is also no longer trusted to flip glm->sonnet on its own
#      (F1 spoof: no real GLM-failure ledger backs it yet) -- a value that would trip the
#      glm_failed_twice rule is capped to 0 and the ignore is journaled.
#
# WHAT IT DOES (R1 FIX PASS 3, 2026-07-25 — race + 4 High from re-review of fix-pass-2)
#   5. CORE FIX: fix-pass-2's reservation was written under flock, the lock was RELEASED,
#      then spawn ran OUTSIDE the lock, then rollback re-acquired the lock. That opened an
#      UNBOUNDED visibility window: caller A reserves+releases, spawn is pending; caller B
#      checks under lock, SEES A's live-looking reservation, is REFUSED; A's spawn then
#      fails and rolls back -- B was wrongly refused for a task that never dispatched.
#      FIX: atomic_dispatch_reserve_spawn_confirm() now holds ONE `flock -w 10 -x 9` across
#      the ENTIRE check -> reserve -> spawn -> confirm/rollback sequence for the glm/sonnet
#      arms. Both launchers' LAUNCH step is non-blocking (verified against source: glm-
#      coder.sh cmd_bg's acquire_lock is a non-blocking mkdir-try that fails fast (exit 75)
#      rather than waiting, then setsid_wrapper+disown backgrounds the real work and prints
#      the run-id; claude-subsession.sh without --wait launches the `claude` worker via its
#      OWN setsid_wrapper (SD-SONNET-ARM-DETACH-01), echoes PID+SESSION_ID, exits) -- so the
#      lock is held only for the reservation write plus a
#      sub-second launch, never for the worker's lifetime. A concurrent caller blocking on
#      `flock -w 10` sees, on entry, the FINAL committed state only: a confirmed row ->
#      refuse; no row (rolled back) -> proceed. No visibility window, no reservation-id
#      needed. (arm=opus never spawns, so it keeps using the simpler reserve-only
#      atomic_dispatch_check_and_record -- no race is possible with nothing to roll back.)
#   6. Four High findings fixed alongside the core fix:
#      a. rollback now removes only the EXACT row this call wrote (full-line match via
#         `grep -vxF`), not a blanket task_sig filter -- see _dispatch_append_line /
#         _dispatch_rollback_row_locked.
#      b. cmd_resolve now checks the rollback outcome; a rollback that fails to write
#         (mktemp/mv) is reported as a hard ERROR (`dispatch_rollback_failed`, non-zero
#         exit) -- it never journals a false `dispatch_rolled_back` success.
#      c. the rollback write itself checks its `mv` return code and propagates failure
#         instead of unconditionally succeeding.
#      d. spawn_worker(sonnet) now requires a parseable `PID=` token in the launcher's
#         handle before treating it as live; a handle with no PID is a launch failure
#         (previously: no-PID handles fell through the `kill -0` check untested and were
#         accepted as live).
#
# WHAT IT DOES (FIX PASS 4, 2026-07-25 — REDESIGN: never hold the lock across spawn)
#   7. Fix-pass-3's "one held flock across reserve->spawn->confirm/rollback" was itself
#      BLOCKED on re-review for two fundamental reasons, so this is a structural redesign,
#      not a patch:
#        (A) the flock FD (9) opened by `) 9>"${lockf}"` is inherited by every descendant
#            process forked while it's open -- including a DETACHED worker a launcher
#            backgrounds (glm-coder.sh's setsid_wrapper+disown, claude-subsession.sh's
#            own setsid_wrapper around the backgrounded `claude` call). flock's lock is
#            tied to the OPEN FILE DESCRIPTION, not
#            the locking process: even after fix-pass-3's own subshell exited, a detached
#            worker that inherited a copy of fd 9 kept the lock held for the WORKER'S ENTIRE
#            LIFETIME (minutes-to-hours), so the very next dispatch of ANY task_sig in the
#            repo (the lock is per-repo, not per-sig) timed out on `flock -w 10`.
#        (B) the launch step is not sub-second in practice -- GLM's own quota-read can block
#            up to ~15s -- which exceeds `flock -w 10` on its own even without the FD leak,
#            so a concurrent caller could be wrongly refused by a timeout that has nothing to
#            do with an actual duplicate.
#      FIX: the flock critical section NEVER wraps spawn again. Ledger state moves through
#      pending -> confirmed with a per-reservation UNIQUE token (pid + epoch + random/uuid --
#      not a 1-second timestamp, so two same-second callers still get DISTINCT rows) and two
#      TTLs: PENDING_TTL (>=30s, safely above the ~15s max launch -- LEADV2_DISPATCH_PENDING_TTL_S,
#      default 30) and CONFIRMED_TTL (>= a worker's max realistic lifetime -- a live task should
#      never look "free" while it's still legitimately running -- LEADV2_DISPATCH_CONFIRMED_TTL_S,
#      default 7200/2h) so a worker that dies without ever reaching confirm/abort doesn't block
#      re-dispatch of the same task_sig forever.
#        - dispatch_reserve() (short flock, ledger read+append only -- milliseconds): refuses
#          (rc=2) if a CONFIRMED row for the sig is younger than CONFIRMED_TTL, or a PENDING
#          row for the sig is younger than PENDING_TTL (still legitimately in flight). Else
#          appends a PENDING row carrying our unique token and returns it. A ledger WRITE
#          failure (read-only/full fs) is rc=1 -- hard fail, no spawn attempted (mission
#          Finding: "append-fail-then-false-success").
#        - spawn_worker() runs OUTSIDE any held lock, with the lock fd explicitly closed
#          (`9>&-`) on every launcher invocation as defense-in-depth (belt-and-suspenders:
#          the redesign already means no fd 9 is open in this process by the time spawn_worker
#          runs, since dispatch_reserve's flock subshell has already exited by then -- the
#          explicit close guards against a FUTURE regression, or against this script itself
#          being invoked from inside another caller's own fd-9 flock scope).
#        - dispatch_confirm() (short flock): flips OUR row (matched by the EXACT unique token,
#          never a blanket sig filter) from pending to confirmed. Only called after
#          spawn_worker has POSITIVELY verified liveness (glm: run-dir status check; sonnet:
#          `kill -0` on a parsed PID) -- spawn_worker's own binary success/failure return IS
#          the "real liveness or drop the claim" gate: a return of 0 only ever happens after a
#          positive liveness check, so confirming right after never confirms a merely-not-yet-
#          disproven worker.
#        - dispatch_abort() (short flock): removes OUR row (matched by the EXACT unique token)
#          -- never a blanket sig filter, so a concurrent caller's own in-flight row for the
#          SAME sig (legal once ENFORCE=0, or once ours is confirmed and theirs is a distinct
#          later attempt) is never collaterally deleted. Called when spawn_worker fails, or for
#          --no-spawn (dry-run never confirms).
#      Net effect on races: caller B blocking on dispatch_reserve's short flock sees, on entry,
#      only the LATEST committed row for the sig (pending-and-fresh -> refused; pending-and-
#      stale -> reclaimed, B proceeds; confirmed-and-fresh -> refused; none/removed -> B
#      proceeds) -- B is never blocked for the WORKER'S lifetime, only for the sub-millisecond
#      reserve step, so B typically resolves in well under a second even while A's own launch
#      is still mid-flight (refused fast) or has already failed and rolled back (accepted fast).
#      Stale PENDING/expired CONFIRMED rows are never proactively deleted (only exact-token
#      confirm/abort ever rewrites a row) -- they're simply ignored by dispatch_reserve's
#      blocking check once past their TTL; the ledger accumulates orphaned rows from dead
#      launchers over time, an accepted tradeoff (no GC required for correctness).
#
# WHAT IT DOES (DISPATCH-OUTCOME-LEDGER-01, 2026-07-29 -- OUTCOME, not intent)
#   8. The ledger above records that a task was SENT (reserved/confirmed), not whether it
#      was DONE. Incident: three lanes were dispatched to Codex at 0 credits; each returned
#      status=completed/phase=done and produced NOTHING -- no commit, no diff, no evidence --
#      yet their CONFIRMED rows blocked re-dispatch of the identical mission for the full
#      CONFIRMED_TTL (2h), recoverable only by hand-editing the ledger file (--force is, by
#      design, never permitted for dedup). FIX: dispatch_reserve now resolves OUTCOME for a
#      matching CONFIRMED-and-fresh row before treating it as blocking:
#        - _dispatch_worker_liveness(arm, handle) reuses each arm's OWN spawn-time liveness
#          check (glm: glm-coder.sh status; sonnet: kill -0; codex: leadv2-lane-liveness.sh,
#          the shared authoritative-provider-status tool) -- composes with the LANE-SHAPE-01
#          liveness primitives rather than re-deriving them. "alive" or "unknown" (liveness
#          can't be proven) BLOCKS, same as today -- a live or unprovable task is never freed.
#        - Only once liveness says "dead" (finished) does _dispatch_evidence_exists(created_
#          epoch, sig8) run: only a lane-attributed handoff artifact or a commit whose
#          message names sig8 (normally `dispatch-<sig8>`) counts. A clock-only commit from
#          another concurrent lane is never evidence. Handoff artifacts are authoritative
#          because dispatch derives their directory from this exact sig8; commits are
#          authoritative only with the explicit sig8 marker because this ledger does not
#          persist a per-lane worktree ref. A git/stat/input failure defaults to "evidence
#          exists" (blocks) -- the ledger only ever frees a sig it has POSITIVELY proven
#          finished-and-empty.
#      "Runtime state churn" -- lock files, the bus offset store, the cross-worktree
#      active.yaml registry -- is excluded from evidence by EVIDENCE_EXCLUDE_RE (override:
#      LEADV2_DISPATCH_EVIDENCE_EXCLUDE_RE) so a lane that only touched its own bookkeeping
#      is correctly treated as empty, not as having shipped real work.
#      PERFORMANCE (do not repeat FIX PASS 4's mistake): liveness/evidence checks are READ-
#      ONLY external calls (status queries, git log) that can be slow -- they run OUTSIDE the
#      lock, in a first unlocked pass. dispatch_reserve then re-acquires the short flock and
#      re-checks with the ORIGINAL pure/local (awk-only, no external calls) TTL logic,
#      excluding by exact token only the row(s) the unlocked pass already proved reclaimable
#      -- any OTHER row (e.g. a concurrent caller's fresh reservation racing in that tiny
#      window) still blocks normally. The lock is never held across a status/evidence check,
#      exactly as fix-pass-4 requires for spawn.
#      ONE-STEP ROLLBACK: LEADV2_DISPATCH_OUTCOME_LEDGER=0 restores today's behavior exactly
#      -- a CONFIRMED row blocks for the full CONFIRMED_TTL regardless of outcome. Default 1.
#      LEADV2_DISPATCH_EVIDENCE_ATTRIBUTION=0 is the narrower one-step rollback for this
#      attribution rule: it restores the former clock-wide commit check. Default 1.
#
# WHAT IT DOES (DISPATCH-LEDGER-PARTIAL-CLOSE-01, 2026-07-29 -- checkpointed != finished)
#   9. Item 8 above answers "did anything happen?" -- LANE-TURNCAP-CHECKPOINT-01 (220eeaf)
#      made that diverge from "was the mission finished?": a lane cut off at --max-turns now
#      commits whatever it has before dying, so _dispatch_evidence_exists finds a real commit
#      and item 8's outcome resolution reads it as completed work, blocking re-dispatch of a
#      mission that only got partway through. FIX: _dispatch_checkpointed_cutoff(sig8,
#      created_epoch) runs BEFORE the evidence check on a "dead" row and frees it (does not
#      block) when BOTH already-recorded signals say "cut off, never recovered":
#        - docs/handoff/dispatch-<sig8>/CHECKPOINT.md exists with mtime >= created_epoch --
#          the exact artifact LANE-TURNCAP-CHECKPOINT-01 writes the moment session-runner.sh
#          detects turn_cap_exhausted (spawn_worker's sonnet arm always launches with
#          --task-id "dispatch-${sig8}", so this path needs no lookup table).
#        - docs/handoff/dispatch-<sig8>/phase8-passed.flag (session-runner.sh's own SENTINEL,
#          the same "mission finished" proof it uses for completion_proof_present) does NOT
#          exist -- if it does, the lane recovered on a later resume attempt within the SAME
#          reservation and genuinely finished; that case falls through to item 8's ordinary
#          evidence check and stays blocked, unchanged. No third notion of doneness invented
#          -- this composes the checkpoint marker (220eeaf) with the existing sentinel
#          session-runner.sh already treats as authoritative.
#      STOP-GATE-CHECKPOINT-DEDUP-01 (2026-08-21): the note above is MODEL-written and is
#      frequently absent (leadv2-turncap-checkpoint-commit.sh:22 documents the model not
#      complying) even though the MACHINE-written checkpoint commit
#      (`wip(<sig8>): auto-checkpoint on worker exit (STOP-GATE)`, pc_stop_gate_autocommit
#      in leadv2-dispatch-product-close.sh) always lands in the lane's own worktree on a
#      killed worker. _dispatch_checkpointed_cutoff now ALSO accepts that commit as proof
#      of cutoff (OR, not replacement, of the note path): it resolves the lane worktree via
#      LANE_WORKTREE_BIN path-of <sig8>, greps that worktree's log for the exact STOP-GATE
#      commit message for <sig8>, and requires the commit's OWN committer timestamp (`%ct`,
#      not file mtime) be >= created_epoch -- same freshness contract as the note, so a
#      checkpoint from an older attempt never frees a newer reservation. Fails closed: a
#      missing/unreadable worktree or an undateable commit does not free the row.
#      Never runs on a live or unprovable row (liveness dead-only, same gate as item 8).
#      ONE-STEP ROLLBACK: LEADV2_DISPATCH_CHECKPOINT_CUTOFF=0 disables this carve-out only --
#      a checkpointed-and-cut-off row then falls through to item 8's evidence check exactly as
#      before (blocks, since the checkpoint commit itself counts as evidence). Default 1.
#
# PRODUCT-READINESS-GATES-01 (ST-9, 2026-07-29)
#   Product work is engine/platform/web behaviour.  plugin, tooling, docs, and pure
#   diagnosis are the only fast-path classes.  The classifier is deliberately
#   conservative: an absent/unknown kind is PRODUCT, never fast-path.  Every dispatch
#   journals its classification and reason.  Product gates each default on and have a
#   one-flip rollback: LEADV2_DISPATCH_ARCHITECT_GATE=0,
#   LEADV2_DISPATCH_E2E_GATE=0, LEADV2_DISPATCH_REVIEW_GATE=0.  A prepass may be skipped
#   only when --writes proves exactly one file; that exception is journaled.  The
#   supervisor only dispatches: architect, e2e, and review are agents/scripts.

set -uo pipefail   # -u safe (quote everything, no unbound vars); NO -e (refusals must journal)

# DISPATCH-FG-GUARD-01 C3: snapshot argv BEFORE any parsing/shift so the
# live-lane refusal can echo back the caller's own command verbatim.
LEADV2_DISPATCH_ARGV_REPLAY="$(printf '%q ' "$0" "$@")"

# SWIFTBAR-LIVE-01 round 2 (§2.4): script-scope globals carrying the founder
# task id + mission file path from `main`'s arg parse to dispatch_reserve.
# Globals, not locals passed down the call stack: dispatch_reserve is also
# reachable from atomic_dispatch_reserve_confirm_opus and from tests where
# `main` never ran, so bash dynamic scoping cannot be relied on. `:-""`
# default keeps `set -u` safe before main ever sets them.
DISPATCH_FOUNDER_TASK_ID="${DISPATCH_FOUNDER_TASK_ID:-}"
DISPATCH_MISSION_PATH="${DISPATCH_MISSION_PATH:-}"
# N7F-LANE-NAME: display-only lane name, resolved ONCE in `main` (precedence: --task-id
# > mission H1 heading > empty -> "unnamed" at the surface). Deliberately separate from
# DISPATCH_FOUNDER_TASK_ID -- that value is a real identity consumed by active.yaml
# stamping, tasks.yaml unclaim, and lane-worktree path resolution; synthesising a name
# into it would corrupt those. DISPATCH_LANE_NAME is fed ONLY to the two ledger writers.
DISPATCH_LANE_NAME="${DISPATCH_LANE_NAME:-}"

SCRIPT_NAME="leadv2-dispatch-code"
# FOREIGN-PROJECT-ROOT-GUARD-01: env roots are normally accepted only when they
# agree with cwd's repository.  The one deliberate exception is an explicit
# --resume-lane/--worktree pin that we can prove belongs to the env repository:
# the pin is an unambiguous dispatch target, whereas an inherited root alone is
# indistinguishable from a leaked parent-session value.
# (CLAUDE_PROJECT_ROOT > CLAUDE_PROJECT_DIR > PROJECT_ROOT > LEADV2_PROJECT_ROOT >
# cwd-derived git toplevel) -- live incident: a bg bash spawned from a
# persona-engine `claude` session, after the human ran `cd ~/Projects/leadv2`,
# still had CLAUDE_PROJECT_DIR=~/Projects/persona-engine in its inherited env.
# That leaked value outranked the cwd, so the lane worktree landed under
# persona-engine/.claude/worktrees/6632fad9 -- no plugins/ dir at all -- and the
# worker went on to edit canonical ~/Projects/leadv2 main directly, uncommitted.
#
# An env-provided root that is itself a real, DIFFERENT git repo from cwd is
# indistinguishable, from inside this script, from a DELIBERATE test-fixture
# override -- most suites in tests/ that `git init` a throwaway repo under
# mktemp ALSO `cd` into it before invoking this script, so cwd's own git
# toplevel already equals the throwaway repo and no mismatch is ever seen.
# review-round-2 (dispatch-b4042501-review, blocker 2): the guard now
# DEFAULTS ON -- fix-forward for the one identified conflicting fixture
# (test-dispatch-architect-prepass-late-artifact.sh, which never cd's into
# its throwaway repo) was to cd it like every other suite, not to ship the
# live guard inert. LEADV2_FOREIGN_ROOT_GUARD=0 remains available as an
# explicit escape hatch for a caller that KNOWS its env/cwd split is
# intentional (kept for symmetry, not exercised by tests/).
_LV2_ENV_ROOT="${CLAUDE_PROJECT_ROOT:-${CLAUDE_PROJECT_DIR:-${PROJECT_ROOT:-${LEADV2_PROJECT_ROOT:-}}}}"
_LV2_FOREIGN_ROOT_ENV=""; _LV2_FOREIGN_ROOT_CWD=""
# Physical containment is intentionally symmetric for a pinned worktree: an
# inherited root may name the repository, a directory below it, or an enclosing
# workspace directory.  In all three cases a pin proven to share that physical
# tree is the authoritative dispatch target.
_lv2_path_contains() {
  local parent="$1" child="$2"
  [[ "${child}" == "${parent}" || "${child}" == "${parent}/"* ]]
}
# GATE-WRONG-ROOT-FALSE-DEAD-01 (repo-CLAUDE.md): resolve the cwd git root ONCE,
# unconditionally, so it is defined identically on every branch below -- the
# prior guard-off else-branch left this unset and silently fell back to
# _LV2_CWD_GIT_ROOT="" (regression proven live, see FOREIGN-ROOT-ELSE-BRANCH-01
# test), rooting the whole control plane at $(pwd) for any invocation with no
# env root set from a subdirectory of a git repo.
_LV2_CWD_GIT_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || true)"
# review-round-2 (dispatch-b4042501-review, item 4): both sides of every root
# comparison below MUST be the physical (realpath) form, not whatever spelling
# `git rev-parse --show-toplevel` happened to print. An env root reached through
# a symlink hop (macOS /tmp -> /private/tmp; a repo's own leadv2 symlink into
# canonical) resolves to the SAME real directory as cwd's toplevel but a
# DIFFERENT string, which previously read as foreign and rejected a legitimate
# explicit pin even though the candidate was, physically, inside the env repo.
[[ -n "${_LV2_CWD_GIT_ROOT}" ]] && _LV2_CWD_GIT_ROOT="$(cd "${_LV2_CWD_GIT_ROOT}" 2>/dev/null && pwd -P || printf '%s' "${_LV2_CWD_GIT_ROOT}")"
if [[ -n "${_LV2_ENV_ROOT}" ]]; then
  PROJECT_ROOT="${_LV2_ENV_ROOT}"
  _LV2_ENV_PHYSICAL_ROOT="$(cd "${_LV2_ENV_ROOT}" 2>/dev/null && pwd -P || true)"
  if [[ "${LEADV2_FOREIGN_ROOT_GUARD:-1}" == "1" ]]; then
    if [[ -n "${_LV2_CWD_GIT_ROOT}" ]]; then
      _LV2_ENV_GIT_ROOT="$(cd "${_LV2_ENV_ROOT}" 2>/dev/null && git rev-parse --show-toplevel 2>/dev/null || true)"
      [[ -n "${_LV2_ENV_GIT_ROOT}" ]] && _LV2_ENV_GIT_ROOT="$(cd "${_LV2_ENV_GIT_ROOT}" 2>/dev/null && pwd -P || printf '%s' "${_LV2_ENV_GIT_ROOT}")"
      if [[ -n "${_LV2_ENV_GIT_ROOT}" && "${_LV2_ENV_GIT_ROOT}" != "${_LV2_CWD_GIT_ROOT}" ]]; then
        # Placement is resolved later, after the mission signature exists, but root
        # selection happens here.  Preflight the *requested* existing placement so
        # the guard does not discard the only root from which --resume-lane can be
        # resolved.  This grants no authority to a bare flag: its candidate must
        # already be a git worktree of the env repository; the full resolver below
        # still rejects missing, foreign, and live lanes before any state write.
        _LV2_PINNED_ROOT=""
        _LV2_PIN_ARG=""
        _LV2_PIN_FLAG=""
        _LV2_PIN_VALUE=""
        _LV2_PIN_NEEDS_VALUE=0
        for _LV2_PIN_ARG in "$@"; do
          if (( _LV2_PIN_NEEDS_VALUE == 1 )); then
            _LV2_PIN_VALUE="${_LV2_PIN_ARG}"
            _LV2_PIN_NEEDS_VALUE=0
            break
          fi
          case "${_LV2_PIN_ARG}" in
            --resume-lane|--worktree) _LV2_PIN_NEEDS_VALUE=1; _LV2_PIN_FLAG="${_LV2_PIN_ARG}" ;;
          esac
        done
        if [[ -n "${_LV2_PIN_VALUE}" ]]; then
          if [[ "${_LV2_PIN_FLAG}" == "--resume-lane" ]]; then
            _LV2_PIN_CANDIDATE="${LEADV2_WORKTREE_DIR:-${_LV2_ENV_GIT_ROOT}/.claude/worktrees}/${_LV2_PIN_VALUE}"
          else
            _LV2_PIN_CANDIDATE="${_LV2_PIN_VALUE}"
          fi
          _LV2_PINNED_ROOT="$(cd "${_LV2_PIN_CANDIDATE}" 2>/dev/null && cd "$(dirname "$(git rev-parse --git-common-dir 2>/dev/null)")" 2>/dev/null && pwd -P || true)"
        fi
        if [[ -n "${_LV2_PINNED_ROOT}" && -n "${_LV2_ENV_PHYSICAL_ROOT}" ]] && \
              { _lv2_path_contains "${_LV2_ENV_PHYSICAL_ROOT}" "${_LV2_PINNED_ROOT}" || \
                _lv2_path_contains "${_LV2_PINNED_ROOT}" "${_LV2_ENV_PHYSICAL_ROOT}"; }; then
          # An explicit pin proven to be in/around the physical env root wins
          # over the unrelated cwd.  Canonicalise PROJECT_ROOT to the pin's
          # owning repository: a parent/child env spelling is not itself a
          # safe control-plane root for journals and ledgers.
          PROJECT_ROOT="${_LV2_PINNED_ROOT}"
        else
          echo "[leadv2-dispatch-code] WARN: foreign project root detected (env=${_LV2_ENV_GIT_ROOT} cwd=${_LV2_CWD_GIT_ROOT}) -- using cwd-derived root (FOREIGN-PROJECT-ROOT-GUARD-01)" >&2
          PROJECT_ROOT="${_LV2_CWD_GIT_ROOT}"
          _LV2_FOREIGN_ROOT_ENV="${_LV2_ENV_GIT_ROOT}"
          _LV2_FOREIGN_ROOT_CWD="${_LV2_CWD_GIT_ROOT}"
        fi
      fi
    fi
  fi
else
  PROJECT_ROOT="${_LV2_CWD_GIT_ROOT:-$(pwd)}"
fi
# LANDING-BLOCKER-R2 (C1): WORK_ROOT is the tree the lane's code edits land in -- it is
# NOT PROJECT_ROOT. PROJECT_ROOT stays the control-plane root (journal, docs/handoff,
# active.yaml, cache, ledger) everywhere below; only worker --cwd and the review-gate's
# diff_root use WORK_ROOT. The launcher exports LEADV2_LANE_WORK_ROOT after `ensure`-ing
# the lane worktree; fall back to PROJECT_ROOT (today's shared-tree behavior) if unset or
# the path no longer exists (fail-open, matches leadv2-lane-worktree.sh's own fail-open).
WORK_ROOT="${LEADV2_LANE_WORK_ROOT:-}"
[[ -n "$WORK_ROOT" && -d "$WORK_ROOT" ]] || WORK_ROOT="$PROJECT_ROOT"
export LEADV2_LANE_WORK_ROOT="$WORK_ROOT"
# LANDED-AT-SPAWN-01: Ledger keying follows the DISPATCH TARGET (the main checkout that
# owns the lane worktree), never the caller session's env. PROJECT_ROOT above is resolved
# from CLAUDE_PROJECT_ROOT/CLAUDE_PROJECT_DIR -- i.e. wherever the HUMAN launched the
# session -- so a persona-engine session dispatching into a leadv2 lane would write
# terminals and reservations into persona-engine's state dir. LEDGER_REPO_ROOT is the
# main checkout that owns WORK_ROOT's linked worktree; every _dl_note call and every
# repo_slug-derived path (reservation ledger, review ledger, dispatch lock) keys off it.
# The cd must happen INSIDE WORK_ROOT: --git-common-dir returns a relative path (".git")
# for an ordinary checkout and an absolute path for a linked worktree, so resolving from
# anywhere else silently yields the wrong root. bash 3.2 safe.
LEDGER_REPO_ROOT="$(cd "${WORK_ROOT}" 2>/dev/null && cd "$(dirname "$(git rev-parse --git-common-dir 2>/dev/null)")" 2>/dev/null && pwd)"
[[ -n "${LEDGER_REPO_ROOT}" && -d "${LEDGER_REPO_ROOT}" ]] || LEDGER_REPO_ROOT="${PROJECT_ROOT}"
# W-1a §3.1: set to 1 the moment a dispatch confirms a live worker (arc==0). The EXIT-trap
# reap (_reap_lane_worktree_if_unused, called from cleanup_pending_dispatch) uses this to
# reap an orphaned lane worktree ONLY when no worker was spawned -- a successful spawn
# leaves the worktree on disk for the async worker + close gate (§3.3 emits the loud line).
_DISPATCH_WORKER_LIVE=0
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-"$0"}")" 2>/dev/null && pwd)"
if [[ "${LEADV2_TRACE:-0}" == "1" ]]; then . "${SCRIPT_DIR}/lib/leadv2-trace.sh"
else lv2_trace_begin() { :; }; lv2_trace_end() { :; }; lv2_trace_arm_exit() { :; }; fi
# CLOSE-GATE-BYPASSABLE-BY-ENV-01 L3 (defence in depth): the real scrub point
# is leadv2-session-runner.sh, the single funnel every lane's own process
# passes through -- this call additionally scrubs THIS dispatcher's own
# environment before it launches any provider channel, so a bypass var set on
# the supervising session cannot ride along even through a channel that does
# not go through the session runner.
# shellcheck source=leadv2-helpers.sh
source "${SCRIPT_DIR}/leadv2-helpers.sh" 2>/dev/null || true
declare -F lv2_scrub_bypass_env >/dev/null 2>&1 && lv2_scrub_bypass_env
# STATUSLINE-COUNT-TRUTH-01: single source of truth for the architect-prepass
# dir suffix -- leadv2-lane-liveness.sh folds dispatch-<sig8>-<role> ids back
# into their parent using this SAME constant, so the registrar and the fold
# rule can never drift apart. Export-only, no flock, safe to source directly.
# shellcheck source=leadv2-lane-child-suffixes.sh
source "${SCRIPT_DIR}/leadv2-lane-child-suffixes.sh"
ARCHITECT_LANE_SUFFIX="${LEADV2_LANE_CHILD_SUFFIXES%%,*}"
# SWIFTBAR-R4 RC-1: flock(1) doesn't exist on the widget's acceptance PATH (no
# util-linux on macOS) -- lv2_lock_wait delegates to real flock when present,
# else an mkdir-based fallback with the same rc0/rc3 contract.
# shellcheck source=leadv2-portable-lock.sh
source "${SCRIPT_DIR}/leadv2-portable-lock.sh"
ROUTING_YAML="${PROJECT_ROOT}/.claude/ref/leadv2-routing.yaml"
ROUTING_CONFIG_ABSENT=0
# ARM-LADDER-HAS-NO-QUOTA-PRECHECK-01 P3: when the project root has no routing
# config (dispatching from inside the plugin repo itself), fall back to the
# plugin's own canonical config so we do not log no_routing_yaml and route blind.
# LEADV2_ROUTING_YAML_PLUGIN_OVERRIDE: test-only seam to simulate a missing
# plugin config.
if [[ ! -f "${ROUTING_YAML}" ]]; then
  _plugin_routing_yaml="${LEADV2_ROUTING_YAML_PLUGIN_OVERRIDE:-${SCRIPT_DIR}/../config/leadv2-routing.yaml}"
  if [[ -f "${_plugin_routing_yaml}" ]]; then
    ROUTING_YAML="${_plugin_routing_yaml}"
  else
    ROUTING_CONFIG_ABSENT=1
  fi
fi
# T17: the arbiter is intentionally optional at load time. A missing/corrupt
# copy falls through to the established ladder and is made observable at the
# call site, rather than making dispatch unavailable.
ROUTE_ARBITER_LIB="${LEADV2_ROUTE_ARBITER_LIB:-${SCRIPT_DIR}/lib/leadv2-route-arbiter.sh}"
[[ -f "${ROUTE_ARBITER_LIB}" ]] && source "${ROUTE_ARBITER_LIB}" || true
# Overridable so tests can point at /bin/true and avoid writing to the real per-task journal.
JOURNAL_BIN="${LEADV2_JOURNAL_BIN:-${SCRIPT_DIR}/leadv2-journal.sh}"
# V3-WORKER-MESSAGING-01 slice 1: tier-0 durable event emitter (docs/specs/
# worker-messaging-v3.md §1-2,§6). Overridable so tests can point at /bin/true
# and avoid writing to the real ~/.claude/cache/leadv2-events tree.
EVENT_BIN="${LEADV2_EVENT_BIN:-${SCRIPT_DIR}/leadv2-event.sh}"
# _emit_event <kind> <task> [<arm>] [<handle>] [<detail>] -- fail-open (`|| true`,
# stdout/stderr fully redirected): a missing/broken emitter binary must never
# affect this dispatcher's own control flow. --repo is this dispatch's own
# repo_slug, matching the per-repo JSONL convention the spec's Tier-0 uses.
_emit_event() {
  local kind="$1" task="${2:-}" arm="${3:-}" handle="${4:-}" detail="${5:-}"
  bash "${EVENT_BIN}" emit --repo "$(repo_slug)" --kind "${kind}" --task "${task}" \
    --arm "${arm}" --handle "${handle}" --detail "${detail}" >/dev/null 2>&1 || true
}
# T-o (SUPERVISOR-AUDIT-01): the terminal-state ledger CLI. ALWAYS invoked as a subprocess
# (`bash "${LEDGER_BIN}" ...`) -- never `source`d. leadv2-dispatch-ledger.sh's own doc
# header explains why: sourcing it collided with this script's own fd-9 flock (dispatch_
# reserve/confirm/abort all use `flock -x 9`), which silently broke the pre-existing
# duplicate_task_signature refusal's stdout. A subprocess has its own fd table, so this
# collision cannot happen -- see _dl_note() below, which also closes fd 9 defensively
# (`9>&-`), matching the belt-and-suspenders idiom already used at every launcher call site
# in this file (search `9>&-`). LEADV2_DISPATCH_TERMINAL_LEDGER=0 disables all writes
# (one-step rollback); this is purely additive observability and never gates a decision.
LEDGER_BIN="${LEADV2_DISPATCH_LEDGER_BIN:-${SCRIPT_DIR}/leadv2-dispatch-ledger.sh}"
TERMINAL_LEDGER="${LEADV2_DISPATCH_TERMINAL_LEDGER:-1}"

# LOW-2 (fixround-tails): a bare "$$" attempt token recycles across days/reboots -- a later,
# unrelated process that happens to reuse this pid would be misread as the SAME attempt by
# the ledger's dedup/sweep-compare logic. ATTEMPT_EPOCH is this process's own start time,
# computed ONCE so every write within this single invocation (including any exit-trap retry)
# reuses the identical value. _dl_attempt_token() qualifies the token as
# <sig8>-<started_at-epoch>-<pid> everywhere an attempt is written or compared.
ATTEMPT_EPOCH="$(date +%s 2>/dev/null || printf '0')"
_dl_attempt_token() { printf '%s-%s-%s' "${1:-nosig}" "${ATTEMPT_EPOCH}" "$$"; }

# Phase stamps into active.yaml (SUPERVISOR-AUDIT-01 addendum, founder 2026-07-30):
# fix-fanout made THIS funnel dispatch the lifecycle owner of its active.yaml row, but
# nothing here ever advanced `phase` past the "spawning" value _fanout_register_session's
# registration sets, so a task that had already built and passed e2e still showed
# "spawning:10m" on the statusline. Stamp the SAME low-level op the registration path
# uses (leadv2_active_update_phase -> update_phase, a cheap one-field PATCH under the
# existing yaml lock, defined in leadv2-active-registry.sh) at each transition this
# funnel already passes through. Fails open (no-op) if active.yaml/the registry script
# is missing or the row isn't there — a statusline cosmetic must never block dispatch.
# The active.yaml row is keyed by the FOUNDER task id (fanout's LAUNCH_IDS), never the
# internal dispatch sig8 -- passing sig8 here would silently match nothing. An empty/unset
# task_id (no --task-id caller) is guarded explicitly: leadv2_active_update_phase's own
# "${1:?...}" would otherwise abort this whole script under `set -u` on an empty arg.
_ACTIVE_REGISTRY_SH="${SCRIPT_DIR}/leadv2-active-registry.sh"
[[ -f "${_ACTIVE_REGISTRY_SH}" ]] && source "${_ACTIVE_REGISTRY_SH}"
_LANE_STATE_SH="${SCRIPT_DIR}/lib/leadv2-lane-state.sh"
[[ -f "${_LANE_STATE_SH}" ]] && source "${_LANE_STATE_SH}"
# SILENT-DEATH-01 (SUPERVISOR-AUDIT-01, 2026-07-30): leadv2-active-registry.sh sets its own
# `set -euo pipefail` (line 26) for standalone use; `source` runs it in THIS shell, so its -e
# silently overrides line 242's deliberate "NO -e (refusals must journal)" for the rest of
# this script's execution. With errexit on, every designed-to-be-caught non-zero return
# (dispatch_reserve's rc=2 duplicate, lock timeouts, ledger-write failures, ...) aborts the
# whole process AT THE FAILING STATEMENT instead of reaching the `case`/`emit decision`/
# `printf dispatch_refused` handling a few lines later -- rc leaks out correctly but the
# refusal is never journaled or printed (100% reproducible: pin the exact mechanism with
# `bash -x`, not by theorizing about load/flock contention). Restore immediately after the
# source so a library's own options can never leak into a caller that opted out of them.
set +e
# REPORT-ONLY-GATE-01: shared parse/locate/substantive/harvest lib for report-declaring
# lanes (LANE_DELIVERABLE: report:<path>). Guarded source + no-op stub, the same
# degrade-never-break idiom as _REFUSAL_CLASSIFY_SH in product-close: a missing lib
# means no lane can flip to kind=report, never a broken dispatch. The lib sets
# `-uo pipefail` only (no -e to leak past the `set +e` above).
_REPORT_DELIVERABLE_SH="${SCRIPT_DIR}/lib/leadv2-report-deliverable.sh"
if [[ ! -f "${_REPORT_DELIVERABLE_SH}" ]]; then
  _REPORT_DELIVERABLE_SH="${LEADV2_CANONICAL_ROOT:-${HOME}/Projects/leadv2}/plugins/leadv2/scripts/lib/leadv2-report-deliverable.sh"
fi
if [[ -f "${_REPORT_DELIVERABLE_SH}" ]]; then
  source "${_REPORT_DELIVERABLE_SH}"
else
  lv2_deliverable_parse() { return 1; }
fi
_stamp_active_phase() { # <task_id> <phase>
  [[ -n "${1:-}" ]] || return 0
  declare -F leadv2_active_update_phase >/dev/null || return 0
  LEADV2_PROJECT_ROOT="${PROJECT_ROOT}" leadv2_active_update_phase "$1" "$2" >/dev/null 2>&1 || true
}

CACHE_BASE="${LEADV2_DISPATCH_CACHE_DIR:-${HOME}/.claude/cache}"
# V3-GLM-LADDER-01 r3: derive unconditionally from CACHE_BASE -- an inherited
# DISPATCH_LEDGER_DIR (this var was never exported anywhere in this codebase,
# so the only source is an ambient shell/CI export) used to win via `:-` and
# silently bypass per-run cache sandboxing (LEADV2_DISPATCH_CACHE_DIR), benching
# arms off a stale/poisoned ledger dir. Fail closed: always derive from the
# already-sandboxed CACHE_BASE.
DISPATCH_LEDGER_DIR="${CACHE_BASE}/dispatch-ledger"
# wave2 round2 finding 3: same STATE_PATH_BIN resolver leadv2-dispatch-ledger.sh's
# terminal ledger uses (LEAD-CONTROL-PLANE-01) -- close_owner_pidfile() below must land
# in the SAME cross-worktree location the sweep reads, not a per-worktree repo path.
STATE_PATH_BIN="${LEADV2_STATE_PATH_BIN:-${SCRIPT_DIR}/leadv2-state-path.sh}"
REVIEW_LEDGER_DIR="${CACHE_BASE}/code-review-ledger"
# shellcheck disable=SC2034  # documented config surface (see usage()); the fence hook
# itself, not this script, is the consumer -- Bash-fence wiring is out of scope here.
FENCE_LOG="${LEADV2_DISPATCH_FENCE_LOG:-${CACHE_BASE}/dispatch-fence/denies.jsonl}"
ENFORCE="${LEADV2_DISPATCH_ENFORCE:-1}"
ACTIVE_DISPATCH_TOKEN=""
# FIX PASS 4: pending/confirmed TTLs (see the FIX PASS 4 doc block above). PENDING_TTL must
# stay safely above the launch step's worst-case duration (GLM quota-read ~15s); CONFIRMED_TTL
# must stay above a worker's realistic max lifetime so a still-running task never looks free.
PENDING_TTL="${LEADV2_DISPATCH_PENDING_TTL_S:-30}"
CONFIRMED_TTL="${LEADV2_DISPATCH_CONFIRMED_TTL_S:-7200}"
# DISPATCH-OUTCOME-LEDGER-01 (see doc block item 8): one-step rollback flag + the evidence
# exclusion list (runtime-state churn that must never count as "real work").
OUTCOME_LEDGER="${LEADV2_DISPATCH_OUTCOME_LEDGER:-1}"
_EVIDENCE_EXCLUDE_RE_DEFAULT='\.lock$|(^|/)docs/leadv2/\.bus-offsets/|(^|/)docs/leadv2/active\.yaml$'
EVIDENCE_EXCLUDE_RE="${LEADV2_DISPATCH_EVIDENCE_EXCLUDE_RE:-${_EVIDENCE_EXCLUDE_RE_DEFAULT}}"
# DISPATCH-LEDGER-PARTIAL-CLOSE-01 (see doc block item 9): one-step rollback for the
# checkpointed-cutoff carve-out.
CHECKPOINT_CUTOFF="${LEADV2_DISPATCH_CHECKPOINT_CUTOFF:-1}"
# DISPATCH-EVIDENCE-NOT-ATTRIBUTED-01: keep the attribution and max-turns reclaim behind
# one narrow rollback switch; OUTCOME_LEDGER=0 remains the broader pre-outcome rollback.
EVIDENCE_ATTRIBUTION="${LEADV2_DISPATCH_EVIDENCE_ATTRIBUTION:-1}"
ARCHITECT_GATE="${LEADV2_DISPATCH_ARCHITECT_GATE:-1}"
# The architect is advisory.  Keep this comfortably below the two-minute
# caller deadline; an invalid override is treated as the safe default.
# PREPASS-TIMEOUT-REALISTIC-01 (2026-07-29): was 30s, which no architect can meet — the real
# designs it produces run 13-21KB and take minutes. Every "prepass failed" today was this
# timeout firing on work that was proceeding normally, and the design landed in the handoff
# dir seconds after we had already given up on it.
ARCHITECT_PREPASS_TIMEOUT_SEC="${LEADV2_DISPATCH_ARCHITECT_TIMEOUT_SEC:-420}"
[[ "${ARCHITECT_PREPASS_TIMEOUT_SEC}" =~ ^[1-9][0-9]*$ ]] || ARCHITECT_PREPASS_TIMEOUT_SEC=420
# How many times to re-run the architect before giving up. A product task is NEVER dispatched
# without a design (founder, 2026-07-29): the gate exists so the work is thought through, and
# running it raw makes the downstream review and end-to-end gates inspect something nobody
# scoped. If every attempt fails the task is PARKED and surfaced, not silently degraded.
ARCHITECT_PREPASS_ATTEMPTS="${LEADV2_DISPATCH_ARCHITECT_ATTEMPTS:-2}"
[[ "${ARCHITECT_PREPASS_ATTEMPTS}" =~ ^[1-9][0-9]*$ ]] || ARCHITECT_PREPASS_ATTEMPTS=2
ARCHITECT_PREPASS_REASON=""
# PREPASS-PROVIDER-FALLBACK-01 §2/§6: provider-aware architect fallback. When the
# selected architect provider fails with a PROVIDER-class failure (authentication,
# rate limit, quota -- classified from the launcher's own stream/handoff evidence
# by _architect_failure_class), the same prepass prompt is retried through another
# configured arm's OWN launcher (codex-task.sh --wait / glm-coder.sh run) before
# the attempt is declared failed; the fallback design is validated by the same
# guards as a Claude design. =0 independently disables only this fallback
# attempt; it does not promise to revert unrelated dispatcher behaviour.
ARCHITECT_FALLBACK="${LEADV2_DISPATCH_ARCHITECT_FALLBACK:-1}"
ARCHITECT_FALLBACK_ARM_USED=""
# Armed only while a fallback's disposable workspace exists.  The process-wide
# EXIT cleanup owns it so signals cannot strand a fallback worktree.
ARCHITECT_FALLBACK_WORKSPACE_BASE=""
# The foreground Python supervisor for an active fallback provider.  The
# signal trap interrupts and reaps this PID before EXIT cleanup removes its
# workspace.
ARCHITECT_FALLBACK_RUNNER_PID=""
ARCHITECT_FALLBACK_RUNNER_PID_FILE=""
ARCHITECT_FALLBACK_RUNNER_GO_FILE=""
# T-c (SUPERVISOR-AUDIT-01): sig-keyed prepass cache + reduced prompt for short missions.
# =0 restores today's behavior byte-for-byte (always re-run the architect, full prompt).
PREPASS_CACHE="${LEADV2_PREPASS_CACHE:-1}"
E2E_GATE="${LEADV2_DISPATCH_E2E_GATE:-1}"
REVIEW_GATE="${LEADV2_DISPATCH_REVIEW_GATE:-1}"
# P0-WORK-CANNOT-LAND-UNSCOPABLE-DIFF-01: a product lane must declare which files it will
# touch -- either the founder-supplied row `writes` field or the architect prepass's own
# `LANE_WRITES:` line -- or its finished diff cannot be scoped to its own tree at review
# time (leadv2-dispatch-product-close.sh unscopable_diff). =0 restores today byte-for-byte
# (no writes declaration required, no park).
REQUIRE_LANE_WRITES="${LEADV2_REQUIRE_LANE_WRITES:-1}"
# RED-FIRST-GATE-01 R2: the prepass mission prompt now asks for a surface-observable
# `acceptance:` block (see architect_prepass's printf text). =1 parks a design that
# lacks it, same PARK-and-surface mechanism as REQUIRE_LANE_WRITES. Default 0 -- this
# is a landing-day opt-in so no in-flight or historical dispatch retro-parks; flip to
# 1 after a soak, mirroring LEADV2_REQUIRE_LANE_WRITES's own rollout.
REQUIRE_ACCEPTANCE="${LEADV2_REQUIRE_ACCEPTANCE:-0}"
# PHASES-ARE-THE-ONLY-PATH-01: three-valued phase precondition gate.
# 0 = disabled (byte-identical to today's behaviour, one-flip rollback);
# warn = journal phase_precondition_warn + proceed;
# 1 = refuse dispatch on missing mandatory phases.
# PHASE-DISCIPLINE-01 D3: with the env UNSET, the effective default is now
# enforce (1, pre-build scope) for admission class >= Standard and warn for
# Light — "nothing reaches a bare worker unclassified". An explicitly set
# value (0/warn/1) keeps its exact pre-flip semantics; LEADV2_REQUIRE_PHASES=0
# remains the byte-identical kill switch.
REQUIRE_PHASES="${LEADV2_REQUIRE_PHASES:-warn}"
REQUIRE_PHASES_ENV_SET=0
[[ -n "${LEADV2_REQUIRE_PHASES:-}" ]] && REQUIRE_PHASES_ENV_SET=1
PHASE_RECORD_BIN="${LEADV2_PHASE_RECORD_BIN:-${SCRIPT_DIR}/leadv2-phase-record.sh}"
# PHASE-DISCIPLINE-01 D1/D2: shared admission map + receipt writer (also
# sourced by leadv2-backlog-pump.sh — one inode of class-mapping truth).
TASK_JUDGE_BIN="${LEADV2_TASK_JUDGE_BIN:-${SCRIPT_DIR}/leadv2-task-judge.sh}"
if [[ -f "${SCRIPT_DIR}/lib/leadv2-admission-class.sh" ]]; then
  # shellcheck disable=SC1091
  source "${SCRIPT_DIR}/lib/leadv2-admission-class.sh" || true
fi
# B1 R2: record-review refuses a build worker minting a review of ITS OWN diff from
# inside a lane worktree (self-attestation). Set to 0 to disable the check (emergency escape).
REVIEW_RECORDER_GUARD="${LEADV2_REVIEW_RECORDER_GUARD:-1}"

log()        { printf '[%s] %s\n' "$SCRIPT_NAME" "$*" >&2; }
log_err()    { printf '[%s] ERROR: %s\n' "$SCRIPT_NAME" "$*" >&2; }

# repo slug (ledger file naming; sanitized to filesystem-safe).
# LANDED-AT-SPAWN-01: slug the DISPATCH TARGET (LEDGER_REPO_ROOT), not PROJECT_ROOT.
# One edit covers dispatch_ledger_file (reserve/confirm/abort), review_ledger_file, and
# dispatch_lock_file -- every repo_slug callsite follows the target uniformly.
repo_slug() {
  local base
  base="$(basename "${LEDGER_REPO_ROOT:-${PROJECT_ROOT}}")"
  printf '%s' "${base}" | tr -cd 'A-Za-z0-9._-'
}

dispatch_ledger_file() { printf '%s/%s.jsonl' "${DISPATCH_LEDGER_DIR}" "$(repo_slug)"; }
review_ledger_file()   { printf '%s/%s.jsonl' "${REVIEW_LEDGER_DIR}"   "$(repo_slug)"; }

# wave2 round2 finding 3: mirrors leadv2-dispatch-ledger.sh's own close_owner_pidfile() --
# duplicated (not sourced) for the same reason this file never sources that one (see its
# "WHY A CLI, NOT A LIBRARY" doc header). Both copies MUST resolve to the identical path
# for a given sig8; the resolver (leadv2-state-path.sh) is the shared source of truth,
# not this function's own logic.
close_owner_pidfile() {
  local sig8="$1" p=""
  if [[ -f "${STATE_PATH_BIN}" ]]; then
    p="$(PROJECT_ROOT="${PROJECT_ROOT}" bash "${STATE_PATH_BIN}" --no-link "dispatch-close-owner/${sig8}.pid" 2>/dev/null || true)"
  fi
  if [[ -z "${p}" ]]; then
    p="${CACHE_BASE}/dispatch-close-owner/${sig8}.pid"
  fi
  printf '%s' "${p}"
}

# S-3 round 3 (LANE-START-SHA-01): the lane's start commit in WORK_ROOT, recorded once per
# dispatch so a later close gate (a different process, possibly a manual re-run) can rebuild
# a `git diff <start-sha> -- <lane_writes>` even when the lane has since committed its own
# work and `git diff HEAD` would show nothing. File, not just an env var passed to the one
# child that reads it immediately -- see leadv2-dispatch-product-close.sh's _pc_diff_base().
lane_start_sha_file() { printf '%s/dispatch-%s.start-sha' "${CACHE_BASE}" "$1"; }

# ARM-PRODUCES-NOTHING-02: the registration file that tells the close gate's silent-arm
# probe whether an arm was ever spawned for this lane.  Same handoff dir both processes
# already agree on by convention; trivially constructible in a test fixture.  Env override
# for test isolation / non-conventional handoff root.
_dispatch_arm_registered_file() {  # <sig8> -> path on stdout
  if [[ -n "${LEADV2_DISPATCH_ARM_REGISTERED_FILE:-}" ]]; then
    printf '%s' "${LEADV2_DISPATCH_ARM_REGISTERED_FILE}"
  else
    printf '%s/docs/handoff/dispatch-%s/arm-registered' "${PROJECT_ROOT}" "$1"
  fi
}

# ARM-PRODUCES-NOTHING-02: append one line per spawn.  Every failure swallowed (|| true) —
# a failed write degrades to the pre-existing empty_diff path, never a false verdict.
#
# BROAD-STATUS-RELAY-SCOPE-01 round 2 (D1): additive LEAD_SESSION=<sanitized
# CLAUDE_CODE_SESSION_ID> field -- the dispatching session's own id, sanitized
# the same way the single-lead-beat hook sanitizes SAFE_SID (tr -c
# 'A-Za-z0-9._-' '_', first 64 chars) so the two can be string-compared
# directly. This is the ONLY in-write-set way to attribute a live lane back
# to the Claude session that dispatched it: lanes detach via
# setsid+disown, so process ancestry cannot do it. Readers that don't know
# this field (every reader predating this lane) are unaffected -- it is
# appended after the existing fields, never inserted between them.
#
# round 3: CLAUDE_CODE_SESSION_ID is the real Claude Code platform var; a
# Bash subprocess never sees CLAUDE_SESSION_ID (round-2 read empty always).
# CLAUDE_SESSION_ID is kept as a legacy fallback only.
_dispatch_register_arm() {  # <sig8> <arm> [handle] -> always rc0
  local sig8="$1" arm="$2" handle="${3:-}" f dir lead_session
  [[ -n "${arm}" ]] || return 0
  f="$(_dispatch_arm_registered_file "${sig8}")"
  dir="$(dirname "${f}")"
  mkdir -p "${dir}" 2>/dev/null || true
  lead_session="$(printf '%s' "${CLAUDE_CODE_SESSION_ID:-${CLAUDE_SESSION_ID:-}}" | tr -c 'A-Za-z0-9._-' '_')"
  lead_session="${lead_session:0:64}"
  printf 'arm=%s handle=%s epoch=%s LEAD_SESSION=%s\n' "${arm}" "${handle}" "$(date +%s 2>/dev/null || printf '0')" "${lead_session}" \
    >> "${f}" 2>/dev/null || true
}

record_lane_start_sha() {  # <sig8> -> writes LANE_START_SHA best-effort, never fails the caller
  # LANE-PLACEMENT-01: on a --resume-lane/--worktree pin this HEAD is the PINNED tree's HEAD.
  # Chosen deliberately: the close-gate diff then covers the new round, plus any uncommitted
  # carry-over from the prior round (HEAD predates it).  Over-inclusive by construction, and it
  # can never HIDE prior uncommitted work — only a base LATER than HEAD could do that.
  local sig8="$1" sha f tmp
  sha="$(git -C "${WORK_ROOT}" rev-parse HEAD 2>/dev/null || true)"
  LANE_START_SHA="${sha}"
  [[ -n "${sha}" ]] || return 0
  f="$(lane_start_sha_file "${sig8}")"
  mkdir -p "$(dirname "${f}")" 2>/dev/null || return 0
  tmp="${f}.tmp.$$"
  if printf '%s\n' "${sha}" > "${tmp}" 2>/dev/null; then
    mv -f "${tmp}" "${f}" 2>/dev/null || true
  else
    rm -f "${tmp}" 2>/dev/null || true
  fi
}

# LANE-REGISTRY-SELF-DEADLOCK-01: pull one field out of a lane-liveness --json
# row. Empty output (not an error) on any parse failure -- the placement probe
# is advisory and fail-open by contract.
_placement_probe_field() {  # <json-row> <field>
  printf '%s' "${1:-}" | python3 -c '
import sys, json
try:
    r = json.loads(sys.stdin.read())
    v = r.get(sys.argv[1])
    if v is not None: print(v)
except Exception:
    pass
' "${2:-}" 2>/dev/null || true
}

# LANE-PLACEMENT-NOT-ADDRESSABLE-01: resolve an EXISTING lane worktree by lane key or by
# explicit absolute path, validate it, and pin WORK_ROOT to it instead of ensure-creating
# a new one.  Called from cmd_resolve after sig8/JOURNAL_TASK exist (so refusals are
# journalable) but BEFORE record_lane_start_sha, _dl_note, dispatch_reserve, architect_prepass
# — no ledger row, no terminal row, no reservation, no spawn can precede a refusal.
#
# Inputs (script-scope, set by the arg loop):
#   placement_lane_ref  — value of --resume-lane (a task-sig8 or founder-id)
#   placement_path      — value of --worktree (absolute path)
# Both empty → no-op (return 0 immediately; the ensure path runs unchanged).
# Both set  → impossible (mutual exclusion enforced in the arg loop before we get here).
#
# Refusal contract: journal the decision, print one stderr line, exit 5.
# (Codes 1=usage, 2=dup-sig, 3=arm=opus, 4=spawn-fail are already taken.)
_resolve_pinned_placement() {
  [[ -n "${placement_lane_ref:-}" || -n "${placement_path:-}" ]] || return 0

  local candidate="" key="" reason="" ref=""
  local project_root_phys
  project_root_phys="$(cd "${PROJECT_ROOT}" 2>/dev/null && pwd -P)"

  # Step 1: Candidate.
  if [[ -n "${placement_lane_ref}" ]]; then
    ref="${placement_lane_ref}"
    key="${placement_lane_ref}"
    candidate="$(LEADV2_PROJECT_ROOT="${PROJECT_ROOT}" bash "${LANE_WORKTREE_BIN}" path-of "${placement_lane_ref}" 2>/dev/null)"
    if [[ -z "${candidate}" ]]; then
      reason="no_lane_worktree_for_ref"
      local _wt_dir="${LEADV2_WORKTREE_DIR:-${PROJECT_ROOT}/.claude/worktrees}"
      emit decision "lane_placement_refused task=${sig8:-?} reason=${reason} ref=${ref} looked_for=${_wt_dir}/${ref}"
      printf '[leadv2-dispatch-code] REFUSE placement: %s ref=%s path=%s\n' \
        "${reason}" "${ref}" "${_wt_dir}/${ref}" >&2
      exit 5
    fi
  else
    # --worktree: explicit absolute path
    ref="${placement_path}"
    key="$(basename "${placement_path}")"
    if [[ "${placement_path}" != /* ]]; then
      reason="not_absolute"
      emit decision "lane_placement_refused task=${sig8:-?} reason=${reason} ref=${ref}"
      printf '[leadv2-dispatch-code] REFUSE placement: %s ref=%s path=%s\n' \
        "${reason}" "${ref}" "${placement_path}" >&2
      exit 5
    fi
    candidate="${placement_path}"
  fi

  # Step 2: Exists.
  if [[ ! -d "${candidate}" ]]; then
    reason="placement_not_found"
    emit decision "lane_placement_refused task=${sig8:-?} reason=${reason} ref=${ref} path=${candidate}"
    printf '[leadv2-dispatch-code] REFUSE placement: %s ref=%s path=%s\n' \
      "${reason}" "${ref}" "${candidate}" >&2
    exit 5
  fi

  # Step 3: Physical form (macOS /tmp → /private/tmp).
  candidate="$(cd "${candidate}" 2>/dev/null && pwd -P)"

  # Step 4: Same-repo — the candidate's git-common-dir parent must equal PROJECT_ROOT.
  local cand_root
  cand_root="$(cd "${candidate}" 2>/dev/null && cd "$(dirname "$(git rev-parse --git-common-dir 2>/dev/null)" 2>/dev/null)" 2>/dev/null && pwd -P)"
  if [[ -z "${cand_root}" ]]; then
    reason="not_a_git_worktree"
    emit decision "lane_placement_refused task=${sig8:-?} reason=${reason} ref=${ref} path=${candidate}"
    printf '[leadv2-dispatch-code] REFUSE placement: %s ref=%s path=%s\n' \
      "${reason}" "${ref}" "${candidate}" >&2
    exit 5
  fi
  if [[ "${cand_root}" != "${project_root_phys}" ]]; then
    reason="foreign_repo"
    emit decision "lane_placement_refused task=${sig8:-?} reason=${reason} ref=${ref} path=${candidate} cand_root=${cand_root} project_root=${project_root_phys}"
    printf '[leadv2-dispatch-code] REFUSE placement: %s ref=%s path=%s\n' \
      "${reason}" "${ref}" "${candidate}" >&2
    exit 5
  fi

  # Step 5: Not live-claimed.  Probe both id spellings the handoff tree uses.
  # Fail-open: probe failure/empty → treated as not live (advisory, never blocks a resume).
  # LANE-REGISTRY-SELF-DEADLOCK-01: ONE --json probe per candidate id (was a
  # plain probe plus a --json re-probe on the live branch); verdict+reason+age
  # all come from the same row now, and a `lane_liveness verdict=<live|dead>`
  # decision line is journaled on BOTH branches so the next forensic session
  # sees WHY a lane was reclaimed (deliverable #2). signal derives from the
  # row's reason: pid evidence vs stream freshness vs none.
  local _row _v _reason _signal _age _live=0 _probe_id
  for _probe_id in "dispatch-${key}" "${key}"; do
    _row="$(bash "${LANE_LIVENESS_BIN}" --project-root "${PROJECT_ROOT}" --lane "${_probe_id}" --no-codex --json 2>/dev/null || true)"
    _v="$(_placement_probe_field "${_row}" verdict)"
    _reason="$(_placement_probe_field "${_row}" reason)"
    _age="$(_placement_probe_field "${_row}" age_s)"
    [[ -z "${_age}" ]] && _age="?"
    _signal="none"
    case "${_reason}" in
      *process_alive*|*no_process*) _signal="pid_identity" ;;
      *log_fresh*|*stream_fresh*)   _signal="stream_fresh" ;;
    esac
    if [[ "${_v}" == "alive" || "${_v}" == starting:* ]]; then
      _live=1
      break
    fi
  done
  if (( _live == 1 )); then
    reason="lane_is_live"
    emit decision "lane_liveness verdict=live task=${sig8:-?} signal=${_signal} probe_id=${_probe_id} raw=${_v} age=${_age}"
    emit decision "lane_placement_refused task=${sig8:-?} reason=${reason} ref=${ref} path=${candidate} probe_id=${_probe_id} verdict=${_v} age=${_age}"
    printf '[leadv2-dispatch-code] REFUSE placement: %s ref=%s path=%s\n' \
      "${reason}" "${ref}" "${candidate}" >&2
    printf '  verdict=%s age=%ss probe_id=%s\n' \
      "${_v}" "${_age}" "${_probe_id}" >&2
    printf 'The lane is still running. Re-run once it clears:\n  %s &\n' \
      "${LEADV2_DISPATCH_ARGV_REPLAY}" >&2
    exit 5
  fi
  # Dead branch: the pin will proceed (Step 6) -- journal WHY the lane was
  # judged not live, with the same signal vocabulary as the refusal branch.
  [[ -n "${_probe_id:-}" ]] && emit decision "lane_liveness verdict=dead task=${sig8:-?} signal=${_signal} probe_id=${_probe_id:-none} raw=${_v:-none} reason=${_reason:-none}"

  # Step 6: Commit the pin.
  WORK_ROOT="${candidate}"
  export LEADV2_LANE_WORK_ROOT="${WORK_ROOT}"
  PLACEMENT_PINNED=1
  _set_worktree_pin_line
  local _mode="resume-lane"
  [[ -n "${placement_path}" ]] && _mode="worktree"
  emit decision "lane_placement_pinned task=${sig8:-?} mode=${_mode} path=${WORK_ROOT} key=${key}"

  # LANE-BEHIND-MAIN-01: a lane that has drifted behind the default branch produces
  # verdicts about a tree that is not the one it will merge into -- in BOTH directions,
  # which is what makes it expensive rather than merely untidy. On 2026-08-22 lane
  # 70d40b43 (20 behind) failed test-target-topic-gate.sh and read as a brand-safety
  # regression; it only lacked personas/respiro-brand/topic-policy.md, which main had
  # gained the day before, and that suite is 120/0 on main. The same night lane
  # a14c371d (27 behind) reported "24 passed / 0 failed -- deploy gate cleared" and the
  # lead recorded it as mergeable; the green was measured against a tree missing 27
  # commits. Nothing anywhere computed this number.
  #
  # ADVISE, never block: the drift is usually harmless, the merge may need judgement,
  # and refusing here would strand finished work behind an automatic gate. Emitting it
  # is what was missing -- the decision line makes it greppable in the journal and the
  # stderr line makes it visible to whoever dispatched.
  if [[ -d "${WORK_ROOT}" ]]; then
    local _lbm_base _lbm_behind
    _lbm_base="$(git -C "${WORK_ROOT}" symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null)"
    _lbm_base="${_lbm_base#origin/}"
    [[ -n "${_lbm_base}" ]] || _lbm_base=main
    if git -C "${WORK_ROOT}" rev-parse --verify --quiet "${_lbm_base}" >/dev/null 2>&1; then
      _lbm_behind="$(git -C "${WORK_ROOT}" rev-list --count "HEAD..${_lbm_base}" 2>/dev/null || echo 0)"
      _lbm_behind="${_lbm_behind:-0}"
      if [[ "${_lbm_behind}" =~ ^[0-9]+$ ]] && (( _lbm_behind > ${LEADV2_LANE_BEHIND_ADVISE_AT:-10} )); then
        emit decision "lane_behind_base task=${sig8:-?} key=${key} base=${_lbm_base} behind=${_lbm_behind}"
        printf '[leadv2-dispatch-code] ⚠ LANE %s IS %s COMMITS BEHIND %s — gate results measure a tree that is not %s.\n' \
          "${key}" "${_lbm_behind}" "${_lbm_base}" "${_lbm_base}" >&2
        printf '  Merge %s into the lane before trusting a pass or diagnosing a failure.\n' "${_lbm_base}" >&2
      fi
    fi
  fi
}

# PLACEMENT-PIN-DEFAULT-01: single construction site for the worker-prompt pin prefix.
# Idempotent + value-stable: safe to call from the flagged path and again from the
# default path.  No-op when WORK_ROOT is the shared tree (nothing to pin to).
_set_worktree_pin_line() {
  [[ -n "${WORK_ROOT:-}" && "${WORK_ROOT}" != "${PROJECT_ROOT}" ]] || return 0
  WORKTREE_PIN_LINE="WORKTREE PIN: all edits go in ${WORK_ROOT}; do NOT cd to the main checkout even if the mission text names it."
}

# ── V3-GLM-LADDER-01: deferred-GLM park, codex credit watchdog, loud sonnet exceptions ──
# Runtime state lives under docs/leadv2/ (plugin-owned, gitignored). All three helpers
# are additive observability -- none may ever abort cmd_resolve (R8: callers wrap with
# `|| true`) and none may take fd 9 (the dispatch lock fd; R3 -- fd 9 is closed before a
# detached worker spawn and any lock taken here must never be inherited by one). Fd 8 is
# this subsystem's own sidecar lock fd, scoped tightly around each read-modify-write and
# always closed (`8>&-`) before returning -- never held across a spawn_worker call.
_leadv2_glm_deferred_path() { printf '%s/docs/leadv2/glm-deferred.jsonl' "${PROJECT_ROOT}"; }
_leadv2_arm_exceptions_path() { printf '%s/docs/leadv2/.arm-exceptions-%s' "${PROJECT_ROOT}" "${1}"; }
_leadv2_codex_credits_stamp_path() { printf '%s/docs/leadv2/.codex-credits-empty.stamp' "${PROJECT_ROOT}"; }
_leadv2_glm_deferred_mission_path() { printf '%s/docs/leadv2/glm-deferred.d/%s.md' "${PROJECT_ROOT}" "${1}"; }

# $1=sig8 $2=reason(LAST_ARM_OUTCOME, quota family only) $3=mission_text — park a
# quota-refused glm-fitting task. Gate (design §4): caller only invokes this when
# candidate==glm at refusal time (or the precheck bench, D3), which is already the
# router's own answer to "is this task glm-fitting" -- do not re-classify.
# D4: the mission text is copied into glm-deferred.d/<sig8>.md at park time so a later
# --retry-all can dispatch it as a brand-new task without depending on an artifact
# (lane-mission.md) that only exists for the product class and only after this point.
_glm_park_deferred() {
  local sig8="$1" reason="$2" mission_text="${3:-}"
  local path; path="$(_leadv2_glm_deferred_path)"
  mkdir -p "$(dirname "${path}")" 2>/dev/null || return 0
  local mission_path=""
  if [[ -n "${mission_text}" ]]; then
    mission_path="$(_leadv2_glm_deferred_mission_path "${sig8}")"
    mkdir -p "$(dirname "${mission_path}")" 2>/dev/null || mission_path=""
    if [[ -n "${mission_path}" ]]; then
      printf '%s' "${mission_text}" > "${mission_path}" 2>/dev/null || mission_path=""
    fi
  fi
  local refused_at; refused_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  local quota_pct="null"
  if [[ -n "${v2_headroom:-}" ]]; then
    quota_pct="$(python3 -c '
import json, sys
try:
    h = json.loads(sys.argv[1])
    v = h.get("glm") if isinstance(h, dict) else None
    print(json.dumps(v) if isinstance(v, (int, float)) else "null")
except Exception:
    print("null")
' "${v2_headroom}" 2>/dev/null || printf 'null')"
  fi
  local row
  row="$(python3 -c '
import json, sys
sig8, mission_path, founder_task_id, refused_at, reason, quota_pct_raw = sys.argv[1:7]
try:
    quota_pct = json.loads(quota_pct_raw)
except Exception:
    quota_pct = None
print(json.dumps({
    "sig8": sig8, "mission_path": mission_path, "founder_task_id": founder_task_id,
    "refused_at": refused_at, "reason": reason, "quota_pct": quota_pct,
    "retried_at": None,
}, separators=(",", ":")))
' "${sig8}" "${mission_path}" "${founder_task_id:-}" "${refused_at}" "${reason}" "${quota_pct}" 2>/dev/null)"
  [[ -n "${row}" ]] || return 0
  (
    lv2_lock_wait "${path}.lock" 10 || exit 3
    printf '%s\n' "${row}" >>"${path}"
    # R1: cap at newest 500 rows, drop rows older than 7 days; state the truncation.
    python3 -c '
import datetime, json, sys
path = sys.argv[1]
cutoff = datetime.datetime.now(datetime.timezone.utc) - datetime.timedelta(days=7)
rows = []
try:
    with open(path, encoding="utf-8") as fh:
        for line in fh:
            line = line.strip()
            if not line:
                continue
            try:
                row = json.loads(line)
            except Exception:
                continue
            ts = row.get("refused_at", "")
            try:
                when = datetime.datetime.strptime(ts, "%Y-%m-%dT%H:%M:%SZ").replace(tzinfo=datetime.timezone.utc)
            except Exception:
                when = None
            if when is not None and when < cutoff:
                continue
            rows.append(row)
except OSError:
    sys.exit(0)
truncated = len(rows) > 500
dropped_sig8s = {r.get("sig8") for r in rows[:-500]} if truncated else set()
rows = rows[-500:]
kept_sig8s = {r.get("sig8") for r in rows}
tmp = path + ".tmp"
with open(tmp, "w", encoding="utf-8") as fh:
    for row in rows:
        fh.write(json.dumps(row, separators=(",", ":")) + "\n")
    if truncated:
        fh.write(json.dumps({"_truncated": True}, separators=(",", ":")) + "\n")
import os
os.replace(tmp, path)
# D4/risk-mitigation: an orphaned park no longer has ANY row (dropped by truncation
# and not re-kept under a later row) -- unlink its mission copy so glm-deferred.d/
# does not grow unbounded alongside the 500-row/7-day cap.
mission_dir = os.path.join(os.path.dirname(path), "glm-deferred.d")
for sig8 in dropped_sig8s - kept_sig8s:
    if not sig8:
        continue
    try:
        os.remove(os.path.join(mission_dir, sig8 + ".md"))
    except OSError:
        pass
' "${path}" 2>/dev/null || true
  ) 9>"${path}.lock"
  true
}

# glm-deferred subcommand: list / retry-all / json.
cmd_glm_deferred() {
  local mode="list"
  case "${1:-}" in
    ""|--list) mode="list" ;;
    --json) mode="json" ;;
    --retry-all) mode="retry-all" ;;
    *) printf 'usage: %s glm-deferred [--list|--retry-all|--json]\n' "${SCRIPT_NAME}" >&2; exit 2 ;;
  esac
  local path; path="$(_leadv2_glm_deferred_path)"
  if [[ ! -r "${path}" ]]; then
    if [[ "${mode}" == "json" ]]; then
      printf '[]\n'
    else
      printf 'no deferred glm tasks\n'
    fi
    return 0
  fi
  case "${mode}" in
    list|json)
      python3 -c '
import json, sys
path, mode = sys.argv[1], sys.argv[2]
rows = []
retried = set()
raw = []
try:
    with open(path, encoding="utf-8") as fh:
        for line in fh:
            line = line.strip()
            if not line:
                continue
            try:
                row = json.loads(line)
            except Exception:
                continue
            if "_truncated" in row:
                continue
            raw.append(row)
except OSError:
    raw = []
for row in raw:
    if row.get("retried_at"):
        retried.add(row.get("sig8"))
pending = [r for r in raw if r.get("sig8") not in retried]
if mode == "json":
    print(json.dumps(pending, separators=(",", ":")))
else:
    if not pending:
        print("no deferred glm tasks")
    for r in pending:
        print("%s %s quota=%s %s" % (
            r.get("sig8", "-"), r.get("refused_at", "-"), r.get("quota_pct", "null"),
            r.get("mission_path", "") or "-",
        ))
' "${path}" "${mode}"
      ;;
    retry-all)
      local _rp_json
      _rp_json="$(python3 -c '
import json, sys
path = sys.argv[1]
raw = []
try:
    with open(path, encoding="utf-8") as fh:
        for line in fh:
            line = line.strip()
            if not line:
                continue
            try:
                row = json.loads(line)
            except Exception:
                continue
            if "_truncated" in row:
                continue
            raw.append(row)
except OSError:
    raw = []
retried = {r.get("sig8") for r in raw if r.get("retried_at")}
pending = [r for r in raw if r.get("sig8") not in retried]
for r in pending:
    print("%s\t%s" % (r.get("sig8", ""), r.get("mission_path", "") or ""))
' "${path}")"
      if [[ -z "${_rp_json}" ]]; then
        printf 'no deferred glm tasks\n'
        return 0
      fi
      local _qg_bin="${LEADV2_ROUTER_V2_BIN:-${SCRIPT_DIR}/leadv2-router-v2.sh}"
      local _sig8 _mpath
      while IFS=$'\t' read -r _sig8 _mpath; do
        [[ -n "${_sig8}" ]] || continue
        # D5 row 1: a landed sonnet fallback already did the work -- reap, never retry.
        if bash "${LEDGER_BIN}" exists "${_sig8}" >/dev/null 2>&1; then
          _leadv2_glm_deferred_mark_retried "${path}" "${_sig8}" "reaped_fallback_landed"
          printf 'reaped %s fallback_landed\n' "${_sig8}"
          continue
        fi
        # D5 row 2: still gated -- leave pending, no state change.
        local _rp_out _rp_eligible
        _rp_out="$(bash "${_qg_bin}" resolve --chain glm --task-id "${_sig8}" 2>/dev/null)"
        _rp_eligible="$(printf '%s\n' "${_rp_out}" | sed -n 's/^eligible=//p')"
        if [[ "${_rp_eligible}" != "glm" ]]; then
          printf 'still_gated %s\n' "${_sig8}"
          continue
        fi
        # D5 row 3: no usable parked mission -- leave pending (H3 data-loss case).
        if [[ -z "${_mpath}" || ! -s "${_mpath}" ]]; then
          printf 'skipped_no_mission %s\n' "${_sig8}"
          continue
        fi
        # D5 row 4/5: dispatch the parked mission as a brand-new task (new sig8). The
        # old sig8 is never re-dispatched -- only reaped on success.
        local _child_errf _child_out _child_rc _new_sig8
        _child_errf="$(mktemp 2>/dev/null || printf '/tmp/glm-retry-%s.err' "${_sig8}")"
        _child_out="$(bash "${BASH_SOURCE[0]}" "@${_mpath}" 2>"${_child_errf}")"
        _child_rc=$?
        if [[ ${_child_rc} -eq 0 ]]; then
          _new_sig8="$(printf '%s\n' "${_child_out}" | sed -n 's/.*task=\([^ ]*\).*/\1/p' | head -1)"
          _leadv2_glm_deferred_mark_retried "${path}" "${_sig8}" "retried_all"
          printf 'retried %s as=%s\n' "${_sig8}" "${_new_sig8:-unknown}"
        else
          local _last_err; _last_err="$(tail -1 "${_child_errf}" 2>/dev/null)"
          printf 'retry_failed %s rc=%s %s\n' "${_sig8}" "${_child_rc}" "${_last_err}"
        fi
        rm -f "${_child_errf}" 2>/dev/null || true
      done <<<"${_rp_json}"
      ;;
  esac
}

# burn-deferred subcommand: list / retry-all / json. Mirrors cmd_glm_deferred above field
# for field except burn24h in place of quota_pct. §2.3 --retry-all semantics: the governor
# verdict is checked ONCE before the loop, not per row (200 rows would mean 200 sqlite
# opens, and a verdict that could flip mid-loop) -- if still hard, nothing is retried and
# the caller is told so in one line.
cmd_burn_deferred() {
  local mode="list"
  case "${1:-}" in
    ""|--list) mode="list" ;;
    --json) mode="json" ;;
    --retry-all) mode="retry-all" ;;
    *) printf 'usage: %s burn-deferred [--list|--retry-all|--json]\n' "${SCRIPT_NAME}" >&2; exit 2 ;;
  esac
  local path; path="$(_leadv2_burn_deferred_path)"
  if [[ ! -r "${path}" ]]; then
    if [[ "${mode}" == "json" ]]; then
      printf '[]\n'
    else
      printf 'no burn-deferred rows\n'
    fi
    return 0
  fi
  case "${mode}" in
    list|json)
      python3 -c '
import json, sys
path, mode = sys.argv[1], sys.argv[2]
raw = []
try:
    with open(path, encoding="utf-8") as fh:
        for line in fh:
            line = line.strip()
            if not line:
                continue
            try:
                row = json.loads(line)
            except Exception:
                continue
            if "_truncated" in row:
                continue
            raw.append(row)
except OSError:
    raw = []
retried = {r.get("sig8") for r in raw if r.get("retried_at")}
pending = [r for r in raw if r.get("sig8") not in retried]
if mode == "json":
    print(json.dumps(pending, separators=(",", ":")))
else:
    if not pending:
        print("no burn-deferred rows")
    for r in pending:
        print("%s %s burn24h=%s %s" % (
            r.get("sig8", "-"), r.get("refused_at", "-"), r.get("burn24h", "null"),
            r.get("mission_path", "") or "-",
        ))
' "${path}" "${mode}"
      ;;
    retry-all)
      local _bd_verdict_line _bd_verdict _bd_burn24h _bd_hard
      _bd_verdict_line="$(bash "${BURN_GOVERNOR_BIN}" verdict 2>/dev/null)"
      _bd_verdict="$(printf '%s\n' "${_bd_verdict_line}" | sed -n 's/.*verdict=\([a-z]*\).*/\1/p')"
      if [[ "${_bd_verdict}" == "hard" ]]; then
        _bd_burn24h="$(printf '%s\n' "${_bd_verdict_line}" | sed -n 's/.*burn24h=\([0-9]*\).*/\1/p')"
        _bd_hard="$(printf '%s\n' "${_bd_verdict_line}" | sed -n 's/.*hard=\([0-9]*\).*/\1/p')"
        local _bd_total
        _bd_total="$(python3 -c '
import json, sys
path = sys.argv[1]
raw = []
try:
    with open(path, encoding="utf-8") as fh:
        for line in fh:
            line = line.strip()
            if not line:
                continue
            try:
                row = json.loads(line)
            except Exception:
                continue
            if "_truncated" in row:
                continue
            raw.append(row)
except OSError:
    raw = []
retried = {r.get("sig8") for r in raw if r.get("retried_at")}
pending = [r for r in raw if r.get("sig8") not in retried]
print(len(pending))
' "${path}" 2>/dev/null)"
        printf 'burn-deferred: still over hard cap (burn24h=%s >= %s) — 0 of %s retried\n' \
          "${_bd_burn24h}" "${_bd_hard}" "${_bd_total:-0}"
        return 0
      fi
      local _rp_json
      _rp_json="$(python3 -c '
import json, sys
path = sys.argv[1]
raw = []
try:
    with open(path, encoding="utf-8") as fh:
        for line in fh:
            line = line.strip()
            if not line:
                continue
            try:
                row = json.loads(line)
            except Exception:
                continue
            if "_truncated" in row:
                continue
            raw.append(row)
except OSError:
    raw = []
retried = {r.get("sig8") for r in raw if r.get("retried_at")}
pending = [r for r in raw if r.get("sig8") not in retried]
for r in pending:
    print("%s\t%s" % (r.get("sig8", ""), r.get("mission_path", "") or ""))
' "${path}")"
      if [[ -z "${_rp_json}" ]]; then
        printf 'no burn-deferred rows\n'
        return 0
      fi
      local _sig8 _mpath
      while IFS=$'\t' read -r _sig8 _mpath; do
        [[ -n "${_sig8}" ]] || continue
        # same D5 row-1 parity as glm-deferred: a landed fallback is reaped, never retried.
        if bash "${LEDGER_BIN}" exists "${_sig8}" >/dev/null 2>&1; then
          _leadv2_burn_deferred_mark_retried "${path}" "${_sig8}" "reaped_fallback_landed"
          printf 'reaped %s fallback_landed\n' "${_sig8}"
          continue
        fi
        if [[ -z "${_mpath}" || ! -s "${_mpath}" ]]; then
          printf 'skipped_no_mission %s\n' "${_sig8}"
          continue
        fi
        local _child_errf _child_out _child_rc _new_sig8
        _child_errf="$(mktemp 2>/dev/null || printf '/tmp/burn-retry-%s.err' "${_sig8}")"
        _child_out="$(bash "${BASH_SOURCE[0]}" "@${_mpath}" 2>"${_child_errf}")"
        _child_rc=$?
        if [[ ${_child_rc} -eq 0 ]]; then
          _new_sig8="$(printf '%s\n' "${_child_out}" | sed -n 's/.*task=\([^ ]*\).*/\1/p' | head -1)"
          _leadv2_burn_deferred_mark_retried "${path}" "${_sig8}" "retried_all"
          printf 'retried %s as=%s\n' "${_sig8}" "${_new_sig8:-unknown}"
        else
          local _last_err; _last_err="$(tail -1 "${_child_errf}" 2>/dev/null)"
          printf 'retry_failed %s rc=%s %s\n' "${_sig8}" "${_child_rc}" "${_last_err}"
        fi
        rm -f "${_child_errf}" 2>/dev/null || true
      done <<<"${_rp_json}"
      ;;
  esac
}

# D6: append a retired-marker row for $2=sig8 under the SAME lock as the read that
# decided to retire it, so a concurrent --retry-all never double-dispatches. reason=$3
# is informational only (list/json already filter on retried_at presence, not reason).
_leadv2_glm_deferred_mark_retried() {
  local path="$1" sig8="$2" reason="$3"
  local retried_at; retried_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  local new_row
  new_row="$(python3 -c '
import json, sys
sig8, reason, retried_at = sys.argv[1:4]
print(json.dumps({
    "sig8": sig8, "mission_path": "", "founder_task_id": "",
    "refused_at": retried_at, "reason": reason, "quota_pct": None,
    "retried_at": retried_at,
}, separators=(",", ":")))
' "${sig8}" "${reason}" "${retried_at}")"
  (
    lv2_lock_wait "${path}.lock" 10 || exit 3
    printf '%s\n' "${new_row}" >>"${path}"
  ) 9>"${path}.lock"
}

# ── BURN-GOVERNOR-01: 24h local token-burn gate, parallel sibling of the V3-GLM-LADDER-01
# block above -- copies its park/retry pattern verbatim rather than generalizing it into a
# shared helper (architect prepass §7 non-goals: generalizing would touch the highest-risk
# code in this file). Provider-agnostic: burn-deferred.jsonl is a SEPARATE file from
# glm-deferred.jsonl, never merged into it. Same fd discipline as above: fd 9 is the
# dispatch lock fd (never taken here outside a park's own subshell), fd 8 is the V3-GLM
# sidecar's -- this subsystem never touches either.
_leadv2_burn_deferred_path() { printf '%s/docs/leadv2/burn-deferred.jsonl' "${PROJECT_ROOT}"; }
_leadv2_burn_deferred_mission_path() { printf '%s/docs/leadv2/burn-deferred.d/%s.md' "${PROJECT_ROOT}" "${1}"; }

# $1=sig8 $2=mission_text $3=burn24h -- park a burn-hard-refused task. Modelled on
# _glm_park_deferred above; D4 (architect prepass §2.4/glm parity): the mission text is
# copied into burn-deferred.d/<sig8>.md at park time so a later --retry-all can dispatch it
# as a brand-new task without depending on lane-mission.md (product-class-only, and only
# after this point). Best-effort: mkdir/lock failures never abort the caller -- but ARE
# journalled (burn_gate park=failed) so a refused-and-unrecorded task stays visible.
_burn_park_deferred() {
  local sig8="$1" mission_text="${2:-}" burn24h="${3:-0}"
  local path; path="$(_leadv2_burn_deferred_path)"
  mkdir -p "$(dirname "${path}")" 2>/dev/null || { emit decision "burn_gate task=${sig8} park=failed reason=mkdir_failed"; return 0; }
  local mission_path=""
  if [[ -n "${mission_text}" ]]; then
    mission_path="$(_leadv2_burn_deferred_mission_path "${sig8}")"
    mkdir -p "$(dirname "${mission_path}")" 2>/dev/null || mission_path=""
    if [[ -n "${mission_path}" ]]; then
      printf '%s' "${mission_text}" > "${mission_path}" 2>/dev/null || mission_path=""
    fi
  fi
  local refused_at; refused_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  local row
  row="$(python3 -c '
import json, sys
sig8, mission_path, founder_task_id, refused_at, burn24h_raw = sys.argv[1:6]
try:
    burn24h = int(burn24h_raw)
except Exception:
    burn24h = None
print(json.dumps({
    "sig8": sig8, "mission_path": mission_path, "founder_task_id": founder_task_id,
    "refused_at": refused_at, "reason": "burn_hard_24h", "burn24h": burn24h,
    "retried_at": None,
}, separators=(",", ":")))
' "${sig8}" "${mission_path}" "${founder_task_id:-}" "${refused_at}" "${burn24h}" 2>/dev/null)"
  if [[ -z "${row}" ]]; then
    emit decision "burn_gate task=${sig8} park=failed reason=row_build_failed"
    return 0
  fi
  local _bpd_rc=0
  (
    lv2_lock_wait "${path}.lock" 10 || exit 3
    printf '%s\n' "${row}" >>"${path}"
    # R1 parity: cap at newest 500 rows, drop rows older than 7 days; unlink orphaned
    # mission copies the same way _glm_park_deferred's truncation does.
    python3 -c '
import datetime, json, sys
path = sys.argv[1]
cutoff = datetime.datetime.now(datetime.timezone.utc) - datetime.timedelta(days=7)
rows = []
try:
    with open(path, encoding="utf-8") as fh:
        for line in fh:
            line = line.strip()
            if not line:
                continue
            try:
                row = json.loads(line)
            except Exception:
                continue
            ts = row.get("refused_at", "")
            try:
                when = datetime.datetime.strptime(ts, "%Y-%m-%dT%H:%M:%SZ").replace(tzinfo=datetime.timezone.utc)
            except Exception:
                when = None
            if when is not None and when < cutoff:
                continue
            rows.append(row)
except OSError:
    sys.exit(0)
truncated = len(rows) > 500
dropped_sig8s = {r.get("sig8") for r in rows[:-500]} if truncated else set()
rows = rows[-500:]
kept_sig8s = {r.get("sig8") for r in rows}
tmp = path + ".tmp"
with open(tmp, "w", encoding="utf-8") as fh:
    for row in rows:
        fh.write(json.dumps(row, separators=(",", ":")) + "\n")
    if truncated:
        fh.write(json.dumps({"_truncated": True}, separators=(",", ":")) + "\n")
import os
os.replace(tmp, path)
mission_dir = os.path.join(os.path.dirname(path), "burn-deferred.d")
for sig8 in dropped_sig8s - kept_sig8s:
    if not sig8:
        continue
    try:
        os.remove(os.path.join(mission_dir, sig8 + ".md"))
    except OSError:
        pass
' "${path}" 2>/dev/null || true
  ) 9>"${path}.lock" || _bpd_rc=$?
  if [[ "${_bpd_rc}" != "0" ]]; then
    emit decision "burn_gate task=${sig8} park=failed reason=lock_timeout"
  fi
  true
}

_leadv2_burn_deferred_mark_retried() {
  local path="$1" sig8="$2" reason="$3"
  local retried_at; retried_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  local new_row
  new_row="$(python3 -c '
import json, sys
sig8, reason, retried_at = sys.argv[1:4]
print(json.dumps({
    "sig8": sig8, "mission_path": "", "founder_task_id": "",
    "refused_at": retried_at, "reason": reason, "burn24h": None,
    "retried_at": retried_at,
}, separators=(",", ":")))
' "${sig8}" "${reason}" "${retried_at}" 2>/dev/null)"
  [[ -n "${new_row}" ]] || return 0
  (
    lv2_lock_wait "${path}.lock" 10 || exit 3
    printf '%s\n' "${new_row}" >>"${path}"
  ) 9>"${path}.lock"
}

# BURN-GOVERNOR-01 D2/D1/D5/D6/D7: pre-arm burn gate. Called from cmd_resolve FIRST --
# before _resolve_pinned_placement and everything after it (ensure/record_lane_start_sha/
# dispatch_reserve/architect_prepass; architect prepass §1.2). A refusal here writes no
# ledger row, creates no worktree, costs zero worker tokens. `--force` never bypasses it
# (only LEADV2_BURN_OVERRIDE=1 does, and that path is loudly journaled with overridden=1,
# same convention as the quota override paths elsewhere in this file). Fail-open by
# construction: an empty/unparseable governor line is treated as verdict=ok (no output).
_burn_gate() {
  local governor_line
  governor_line="$(bash "${BURN_GOVERNOR_BIN}" verdict 2>/dev/null)"
  [[ -n "${governor_line}" ]] || return 0

  local verdict burn24h soft hard reason
  verdict="$(printf '%s\n' "${governor_line}" | sed -n 's/.*verdict=\([a-z]*\).*/\1/p')"
  burn24h="$(printf '%s\n' "${governor_line}" | sed -n 's/.*burn24h=\([0-9]*\).*/\1/p')"
  soft="$(printf '%s\n' "${governor_line}" | sed -n 's/.*soft=\([0-9]*\).*/\1/p')"
  hard="$(printf '%s\n' "${governor_line}" | sed -n 's/.*hard=\([0-9]*\).*/\1/p')"
  reason="$(printf '%s\n' "${governor_line}" | sed -n 's/.*reason=\([^ ]*\).*/\1/p')"

  case "${verdict}" in
    soft)
      emit decision "burn_gate task=${sig8} verdict=soft burn24h=${burn24h} soft=${soft} hard=${hard} reason=${reason}"
      printf '[leadv2-dispatch-code] ⚠ BURN GATE: 24h burn %s >= soft %s — dispatch allowed, consider deferring non-critical lanes\n' \
        "${burn24h}" "${soft}" >&2
      ;;
    hard)
      if [[ "${LEADV2_BURN_OVERRIDE:-0}" == "1" ]]; then
        emit decision "burn_gate task=${sig8} verdict=hard burn24h=${burn24h} soft=${soft} hard=${hard} reason=${reason} overridden=1"
        printf '[leadv2-dispatch-code] ⚠ BURN GATE OVERRIDDEN: 24h burn %s >= hard %s — LEADV2_BURN_OVERRIDE=1, dispatch allowed\n' \
          "${burn24h}" "${hard}" >&2
        return 0
      fi
      emit decision "burn_gate task=${sig8} verdict=hard burn24h=${burn24h} soft=${soft} hard=${hard} reason=${reason} ref=${placement_lane_ref:-${placement_path:-}}"
      printf '[leadv2-dispatch-code] ⛔ BURN GATE: 24h burn %s >= hard cap %s — lane refused, task parked\n' \
        "${burn24h}" "${hard}" >&2
      _burn_park_deferred "${sig8}" "${mission}" "${burn24h}"
      return 1
      ;;
    *) return 0 ;;
  esac
}

# $1=credits-json (from route_headroom_chosen's payload) — emit ONE deduped
# codex_credits_empty journal line per 24h window. R8: caller wraps with `|| true`.
_codex_credits_watch() {
  local credits_json="${1:-}"
  [[ -n "${credits_json}" && "${credits_json}" != "{}" ]] || return 0
  local has_credits
  has_credits="$(python3 -c '
import json, sys
try:
    d = json.loads(sys.argv[1])
    codex = d.get("codex") if isinstance(d, dict) else None
    if not isinstance(codex, dict):
        print("unknown"); sys.exit(0)
    if "has_credits" in codex:
        print("true" if codex.get("has_credits") else "false")
    elif "balance" in codex:
        print("false" if str(codex.get("balance")) == "0" else "true")
    else:
        print("unknown")
except Exception:
    print("unknown")
' "${credits_json}" 2>/dev/null || printf 'unknown')"
  local stamp; stamp="$(_leadv2_codex_credits_stamp_path)"
  mkdir -p "$(dirname "${stamp}")" 2>/dev/null || return 0
  if [[ "${has_credits}" == "true" ]]; then
    rm -f "${stamp}" 2>/dev/null || true
    return 0
  fi
  [[ "${has_credits}" == "false" ]] || return 0
  (
    lv2_lock_wait "${stamp}.lock" 10 || exit 3
    local now since_line since fresh=1
    now="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    if [[ -r "${stamp}" ]]; then
      since_line="$(head -1 "${stamp}" 2>/dev/null)"
      since="${since_line#since=}"
      if [[ -n "${since}" ]] && python3 -c '
import datetime, sys
since_raw, now_raw = sys.argv[1], sys.argv[2]
try:
    since = datetime.datetime.strptime(since_raw, "%Y-%m-%dT%H:%M:%SZ").replace(tzinfo=datetime.timezone.utc)
    now = datetime.datetime.strptime(now_raw, "%Y-%m-%dT%H:%M:%SZ").replace(tzinfo=datetime.timezone.utc)
    sys.exit(0 if (now - since).total_seconds() < 86400 else 1)
except Exception:
    sys.exit(1)
' "${since}" "${now}"; then
        fresh=0
      fi
    fi
    if [[ ${fresh} -eq 1 ]]; then
      printf 'since=%s\n' "${now}" >"${stamp}.tmp" && mv "${stamp}.tmp" "${stamp}"
      emit decision "codex_credits_empty since=${now}"
    fi
  ) 9>"${stamp}.lock"
  true
}

# $1=reason $2=sig8 — bump today's sonnet-fallback-after-glm-refusal counter.
# D1: the counter counts distinct sig8 per UTC day -- a repeat bump for a sig8 already
# recorded is a no-op (does not bump count, does not rewrite last_reason).
# _LEADV2_EXC_DAY is computed once per cmd_resolve invocation (R6) so one dispatch
# never straddles two daily files even across a UTC-midnight boundary.
_arm_exception_bump() {
  local reason="$1" sig8="$2"
  local day="${_LEADV2_EXC_DAY:-$(date -u +%Y%m%d)}"
  local path; path="$(_leadv2_arm_exceptions_path "${day}")"
  mkdir -p "$(dirname "${path}")" 2>/dev/null || return 0
  (
    lv2_lock_wait "${path}.lock" 10 || exit 3
    if [[ -r "${path}" ]] && grep -qF "sig8=${sig8}" "${path}" 2>/dev/null; then
      exit 0
    fi
    local count=0
    if [[ -r "${path}" ]]; then
      count="$(grep -c '^sig8=' "${path}" 2>/dev/null || printf '0')"
      [[ "${count}" =~ ^[0-9]+$ ]] || count=0
    fi
    count=$((count + 1))
    {
      printf 'count=%s\n' "${count}"
      printf 'last_reason=%s\n' "${reason}"
      if [[ -r "${path}" ]]; then
        grep '^sig8=' "${path}" 2>/dev/null
      fi
      printf 'sig8=%s\n' "${sig8}"
    } >"${path}.tmp" && mv "${path}.tmp" "${path}"
  ) 9>"${path}.lock"
  true
}

# Journal + stderr-emit one structured line. $1=journal-type, $2..=text (one logical line).
# Invoked via `bash <path>` (not direct exec): leadv2-journal.sh ships non-executable, and
# leadv2-state-atomic-write.sh:260 sets this idiom. LEADV2_JOURNAL_BIN override (e.g.
# /bin/true) makes tests hermetic without touching the real per-task journal.
emit() {
  local jtype="$1"; shift
  local line="$*"
  if [[ -n "${JOURNAL_TASK:-}" && -f "${JOURNAL_BIN}" ]]; then
    # review-round-2 item 1 (dispatch-b4042501-review): leadv2-journal.sh resolves
    # its OWN PROJECT_ROOT independently (CLAUDE_PROJECT_ROOT > CLAUDE_PROJECT_DIR >
    # cwd git toplevel) -- without this override it re-reads the same ambient
    # CLAUDE_PROJECT_DIR the foreign-root guard just rejected, so a
    # project_root_guard line (or any line, in any foreign-root dispatch) landed in
    # the LOSING repo's journal, never the winning root's -- indistinguishable from
    # "not written to the task journal" from the caller's point of view.
    CLAUDE_PROJECT_ROOT="${PROJECT_ROOT}" bash "${JOURNAL_BIN}" append "${JOURNAL_TASK}" "${jtype}" "${line}" >/dev/null 2>&1 || true
  fi
  log "${line}"
}

# FP-06: model-selection telemetry -- one machine-parseable row per dispatch
# attempt, emitted at the attempt's terminal. Win = a confirmed LIVE spawn
# (the lane's later landed/parked/dead verdict belongs to the close gate, not
# to model selection); fail = the candidate chain is exhausted (or the arbiter
# hard-refused). Fields read the caller cmd_resolve's locals (bash dynamic
# scoping) plus the _MS_* globals initialized at candidate-loop entry.
# fallback_depth counts route_fallback transitions before the terminal arm
# (how many arms were tried and lost before this one); floor mirrors the
# arm_floor_applied journal decision. Also appended as a CSV row under
# docs/leadv2/ (header auto-created) so FP-04's 20-diff quality gate has a
# dataset. Fail-open everywhere: telemetry must never change a dispatch
# outcome, so every CSV step is best-effort.
_model_select_telemetry() {  # <terminal:win|fail> <cause> [arm]
  local _t="$1" _c="$2" _a="${3:-${arm:-unknown}}"
  local _s=0
  if [[ -n "${_MS_T0:-}" && "${_MS_T0}" =~ ^[0-9]+$ ]]; then
    _s=$(( $(_now_epoch) - _MS_T0 )); [[ "${_s}" -lt 0 ]] && _s=0
  fi
  local _class
  _class="$(printf '%s' "${ADMISSION_CLASS:-${task_class:-standard}}" | tr '[:upper:]' '[:lower:]')"
  local _wk="${ADMISSION_WORK_KIND:-${kind:-code}}"
  emit decision "model_select_telemetry task=${sig8:-} role=worker class=${_class} work_kind=${_wk} arm=${_a} model=${_MS_MODEL:-${_a}} fallback_depth=${_MS_FALLBACKS:-0} floor=${_MS_FLOOR:-none} spawn_to_terminal_s=${_s} terminal=${_t} cause=${_c}"
  local _csv="${PROJECT_ROOT:-}/docs/leadv2/model-select-telemetry.csv" _dir
  [[ -n "${PROJECT_ROOT:-}" ]] || return 0
  _dir="$(dirname "${_csv}")"
  mkdir -p "${_dir}" 2>/dev/null || return 0
  [[ -f "${_csv}" ]] || printf 'task,role,class,work_kind,arm,model,fallback_depth,floor,spawn_to_terminal_s,terminal,cause\n' > "${_csv}" 2>/dev/null || return 0
  printf '%s\n' "task=${sig8:-} role=worker class=${_class} work_kind=${_wk} arm=${_a} model=${_MS_MODEL:-${_a}} fallback_depth=${_MS_FALLBACKS:-0} floor=${_MS_FLOOR:-none} spawn_to_terminal_s=${_s} terminal=${_t} cause=${_c}" \
    | awk '{n=split($0,kv," "); for(i=1;i<=n;i++){split(kv[i],p,"="); printf "%s%s", p[2], (i<n?",":"\n")}}' >> "${_csv}" 2>/dev/null || true
}

# T-o: write-once terminal-state row for <sig8> via leadv2-dispatch-ledger.sh's CLI.
# ALWAYS a subprocess (see LEDGER_BIN's doc comment above) -- never source this. Purely
# additive observability: fail-open (`|| true`), stdout/stderr fully redirected, fd 9
# explicitly closed so a missing/broken ledger binary can never touch this script's own
# stdout or its own flock fd 9.
# <sig8> <terminal:landed|parked|refused|dead> <cause> [<evidence>] [<founder_task_id>]
# wave2 round3 finding 3: passes this process's own attempt token to the ledger --
# each dispatch-code.sh invocation is exactly one attempt, so this only ever collides with
# itself (never blocking a genuinely later attempt at the same sig8 from recording its own
# real outcome after a refused/parked one). LOW-2: the token is qualified
# <sig8>-<epoch>-<pid> (_dl_attempt_token above), not a bare pid, so a recycled pid across
# reboots/days can never be misread as the same attempt.
_dl_note() {
  # V3-WORKER-MESSAGING-01 slice 1: worker_terminal event, independent of the
  # TERMINAL_LEDGER flag below -- this is a second, cheaper reader surface
  # (spec §6/§7.6 "mirror for now"), not gated on the ledger's own on/off switch.
  _emit_event worker_terminal "$1" "" "" "$2:$3"
  [[ "${TERMINAL_LEDGER}" == "1" && -f "${LEDGER_BIN}" ]] || return 0
  # N7F-LANE-NAME: 7th positional is the display name, read from the DISPATCH_LANE_NAME
  # global (never from this fn's own args -- its 5-arg signature stays unchanged so its
  # ~15 callsites need zero edits). write-terminal falls back to founder_task_id itself
  # when this is empty.
  # LANDED-AT-SPAWN-01: key the terminal ledger to the DISPATCH TARGET, not the caller
  # session. Both names because ledger:83 prefers PROJECT_ROOT while other leadv2 callers
  # key off LEADV2_PROJECT_ROOT -- threading both keeps the fix uniform.
  PROJECT_ROOT="${LEDGER_REPO_ROOT}" LEADV2_PROJECT_ROOT="${LEDGER_REPO_ROOT}" \
    bash "${LEDGER_BIN}" write-terminal "$1" "${5:-}" "$2" "$3" "${4:-}" "$(_dl_attempt_token "$1")" "${DISPATCH_LANE_NAME:-}" "${6:-}" "${7:-}" >/dev/null 2>&1 9>&- || true
}

# ── task signature: normalize mission text, sha256 ────────────────────────────────
# Collapse all whitespace to single spaces, strip CR, trim. Two missions that differ only
# in indentation/case-folded-by-whitespace collapse to the same sig (one task = one model).
compute_sig() {
  tr -d '\r' | tr -s '[:space:]' ' ' | sed -e 's/^ //' -e 's/ $//' | shasum -a 256 | awk '{print $1}'
}

# ── N7F-LANE-NAME: display-name extraction (pure fn of mission text) ──────────────
# Precedence lives in `main` (--task-id wins outright); this fn is only rule 2, the
# mission-H1 fallback. bash 3.2 safe -- no declare -A, no ${var^^}, no mapfile, no <<<.
# Steps mirror the design doc 1:1 so a future reader can diff behaviour against spec:
#   1. first line matching ^#[[:space:]]; none -> empty (-> caller renders "unnamed")
#   2. strip the leading '#' + whitespace
#   3. keep the segment before the first ' — ' / ' – ' / ' -- ' / ': ' separator
#   4. collapse internal whitespace, trim both ends
#   5. strip \ and " (same sanitiser the reserve writer already applies), then other
#      JSON control chars
#   6. clamp to 64 chars (surface applies its own _clip40 on top)
#   7. empty after 1-6 -> empty
_dispatch_lane_name_from_mission() {
  local mission="$1" heading name
  heading="$(printf '%s\n' "${mission}" | grep '^#[[:space:]]' | head -n 1)"
  [[ -n "${heading}" ]] || { printf ''; return 0; }
  name="${heading#\#}"
  name="${name#"${name%%[![:space:]]*}"}"
  case "${name}" in
    *" — "*)  name="${name%% — *}" ;;
    *" – "*)  name="${name%% – *}" ;;
    *" -- "*) name="${name%% -- *}" ;;
    *": "*)   name="${name%%: *}" ;;
  esac
  name="$(printf '%s' "${name}" | tr -s '[:space:]' ' ')"
  name="${name#"${name%%[![:space:]]*}"}"
  name="${name%"${name##*[![:space:]]}"}"
  name="${name//\\/}"; name="${name//\"/}"
  name="$(printf '%s' "${name}" | tr -d '\000-\037')"
  name="${name:0:64}"
  printf '%s' "${name}"
}

sig_is_hex() { printf '%s' "$1" | grep -qxE '[0-9a-f]{64}'; }

# ── GLM-FIRST-01 / T-q policy resolver ────────────────────────────────────────────
# T-b (SUPERVISOR-AUDIT-01): the predicate chain used to be duplicated inline here AND
# in leadv2-router.sh's per-invocation python helper. Both now call the ONE resolver at
# lib/leadv2-glm-policy-resolve.py — see that file for the full rule set + the T-q
# codex_quota_gate / review_arm_exclusions enforcement (job=build here; router.sh passes
# job=review for phase=review). Signals arrive via DC_* env vars set from the caller's
# flags. Prints four lines: arm=<glm|sonnet|opus|codex>  rule=<id|none|...>
# reason=<glm_default|...>  tier=<standard|...|(empty)>
# (line-per-field, NOT tab-delimited — BSD sed treats \t as literal 't', which corrupts values.)
# Fail-safe: any error/missing-resolver -> arm=glm UNLESS DC_SAFETY/DC_PROTECTED is
# set, in which case it fails CLOSED to arm=sonnet (reason=*_failclosed, observable).
# MAJOR fix (review-verdict.md dispatch-code.sh:339-376): a lookup relative only to
# this caller's SCRIPT_DIR silently resolved to nothing in a vendored copy that
# missed the lib/ sync (drift) -- resolve_arm()'s own error fallback then read
# that as "resolver errored" and defaulted to the cheap arm, bypassing
# safety/protected-path routing there. Prefer the co-located copy; fall back to
# the verified canonical plugin root (same convention leadv2-drift-guard.sh:58-59
# uses) rather than accept a path that quietly doesn't exist.
GLM_POLICY_RESOLVER="${GLM_POLICY_RESOLVER:-}"
if [[ -z "${GLM_POLICY_RESOLVER}" ]]; then
  if [[ -f "${SCRIPT_DIR}/lib/leadv2-glm-policy-resolve.py" ]]; then
    GLM_POLICY_RESOLVER="${SCRIPT_DIR}/lib/leadv2-glm-policy-resolve.py"
  else
    _canonical_resolver="${LEADV2_CANONICAL_ROOT:-${HOME}/Projects/leadv2}/plugins/leadv2/scripts/lib/leadv2-glm-policy-resolve.py"
    [[ -f "${_canonical_resolver}" ]] && GLM_POLICY_RESOLVER="${_canonical_resolver}"
  fi
fi
resolve_arm() {
  local signals_json
  # Resolver unresolvable in ANY copy (both lookups above missed): fail CLOSED on
  # safety/protected signals instead of the prior blanket arm=glm default -- a
  # missing lib/ must never silently bypass safety routing.
  if [[ -z "${GLM_POLICY_RESOLVER}" || ! -f "${GLM_POLICY_RESOLVER}" ]]; then
    if [[ "${DC_SAFETY:-0}" == "1" || "${DC_PROTECTED:-0}" == "1" ]]; then
      printf 'arm=sonnet\nrule=none\nreason=resolver_missing_failclosed\ntier=\n'
    else
      printf 'arm=glm\nrule=none\nreason=resolver_missing\ntier=\n'
    fi
    return
  fi
  signals_json="$(python3 -c '
import json, os, sys
e = os.environ
def _b(k): return bool(int(e.get(k, "0") or 0))
def _f(k):
    try: return float(e.get(k, "0") or 0)
    except (TypeError, ValueError): return 0.0
print(json.dumps({
    "mission_kind": e.get("DC_KIND", ""),
    "protected_path": _b("DC_PROTECTED"),
    "safety_touched": _b("DC_SAFETY"),
    "subsystem_count": _f("DC_SUBSYSTEM_COUNT"),
    "needs_midflight_interaction": _b("DC_INTERACTIVE"),
    "ui_design_judgment": _b("DC_UI_JUDGMENT"),
    "glm_failure_count": _f("DC_GLM_FAILURES"),
    "glm_lock_busy": _b("DC_GLM_LOCK_BUSY"),
}))
' 2>/dev/null)" || signals_json='{}'
  # Build argv via an array, not an unquoted ${VAR:+word "$VAR"} splice: the latter
  # collapsed "--quota-live" + path into ONE argv element in this exact
  # local-signals_json-then-conditional-flag shape (bash 5.3, reproducible), which
  # made argparse silently reject the flag and fail the resolver on every call
  # (found by T-b's live-policy harness — the CLI mode had never been exercised).
  local -a _resolver_args=(--routing-yaml "${ROUTING_YAML}" --job build --base-arm glm --signals "${signals_json}")
  [[ -n "${GLM_POLICY_QUOTA_LIVE:-}" ]] && _resolver_args+=(--quota-live "${GLM_POLICY_QUOTA_LIVE}")
  DC_PROTECTED="${DC_PROTECTED:-0}" \
  DC_SAFETY="${DC_SAFETY:-0}" \
  DC_SUBSYSTEM_COUNT="${DC_SUBSYSTEM_COUNT:-0}" \
  DC_INTERACTIVE="${DC_INTERACTIVE:-0}" \
  DC_UI_JUDGMENT="${DC_UI_JUDGMENT:-0}" \
  DC_KIND="${DC_KIND:-}" \
  DC_GLM_FAILURES="${DC_GLM_FAILURES:-0}" \
  DC_GLM_LOCK_BUSY="${DC_GLM_LOCK_BUSY:-0}" \
  python3 "${GLM_POLICY_RESOLVER}" "${_resolver_args[@]}" \
    2>/dev/null || {
      if [[ "${DC_SAFETY:-0}" == "1" || "${DC_PROTECTED:-0}" == "1" ]]; then
        printf 'arm=sonnet\nrule=none\nreason=resolver_error_failclosed\ntier=\n'
      else
        printf 'arm=glm\nrule=none\nreason=resolver_error\ntier=\n'
      fi
    }
}

# ── ARM-LADDER-HAS-NO-QUOTA-PRECHECK-01 ──────────────────────────────────────
# P1: read the dispatch ladder from the routing YAML instead of hardcoding it.
# P2: quota precheck that skips arms whose provider is locked out.
# Both are fail-open: a missing/unreadable config or lockout record never blocks
# an arm we could have used.

# Global arrays populated by _load_dispatch_ladder().
_LADDER_IDS=()
_LADDER_PROVIDERS=()
_LADDER_UNTRUSTED=()
_LADDER_WHEN=()

# Read the dispatch_ladder from router: in the routing YAML.
# Populates _LADDER_IDS, _LADDER_PROVIDERS, _LADDER_UNTRUSTED and _LADDER_WHEN
# (parallel arrays). Falls back to the legacy hardcoded order
# (glm,kimi,codex,sonnet) if the YAML or key is absent.
# T19 fix-round C1: _LADDER_UNTRUSTED carries each entry's `untrusted: true`
# flag (third-party arms like freepool) so _build_candidate_chain can strip
# them from a protected/safety chain by FACT, not by a hand-kept exclusion
# list -- mirrors the `untrusted` reader added to leadv2-routing.yaml.
# T19 fix-round C2: _LADDER_WHEN carries each entry's `when:` list
# (comma-joined, e.g. "standard,bulk" or "all") so _build_candidate_chain can
# enforce it against the dispatch's --task-class instead of it being a yaml
# key nobody parses.
_load_dispatch_ladder() {
  _LADDER_IDS=()
  _LADDER_PROVIDERS=()
  _LADDER_UNTRUSTED=()
  _LADDER_WHEN=()
  local _parsed
  _parsed="$(python3 -c '
import sys, yaml
try:
    d = yaml.safe_load(open(sys.argv[1])) or {}
except Exception:
    sys.exit(1)
ladder = (d.get("router") or {}).get("dispatch_ladder") or []
for e in ladder:
    eid = e.get("id", "")
    if not eid:
        continue
    if e.get("dispatch", True) is False:
        continue
    untrusted = "1" if e.get("untrusted") else "0"
    when = e.get("when") or ["all"]
    if isinstance(when, str):
        when = [when]
    when_field = ",".join(str(w) for w in when) or "all"
    print(eid + "\t" + e.get("provider", eid) + "\t" + untrusted + "\t" + when_field)
' "${ROUTING_YAML}" 2>/dev/null)" || _parsed=""
  # T19 fix-round (H2b / critic H3): ROUTING_YAML resolution above only falls
  # back to the plugin's canonical yaml when the TENANT FILE ITSELF is absent.
  # All 3 live tenant repos HAVE a .claude/ref/leadv2-routing.yaml, so that
  # fallback never fires -- but none of those tenant files carry a
  # router.dispatch_ladder key at all, so `_parsed` above comes back empty and
  # this function fell straight to the legacy hardcoded order (glm codex
  # sonnet), which has no freepool entry. Result: freepool was dead in every
  # tenant repo regardless of the plugin yaml change, verified by grepping
  # persona-engine's own routing yaml for `dispatch_ladder` (zero hits).
  # Fix: when the resolved ROUTING_YAML has no dispatch_ladder key, retry
  # against the plugin's own canonical yaml specifically for that key, before
  # falling back to the hardcoded legacy order. A tenant yaml that DOES define
  # its own dispatch_ladder (even a short one) is respected as-is -- this only
  # covers the "key entirely absent" case, same semantics as the file-level
  # fallback above.
  if [[ -z "${_parsed}" ]]; then
    _plugin_ladder_yaml="${LEADV2_ROUTING_YAML_PLUGIN_OVERRIDE:-${SCRIPT_DIR}/../config/leadv2-routing.yaml}"
    if [[ -f "${_plugin_ladder_yaml}" && "${_plugin_ladder_yaml}" != "${ROUTING_YAML}" ]]; then
      _parsed="$(python3 -c '
import sys, yaml
try:
    d = yaml.safe_load(open(sys.argv[1])) or {}
except Exception:
    sys.exit(1)
ladder = (d.get("router") or {}).get("dispatch_ladder") or []
for e in ladder:
    eid = e.get("id", "")
    if not eid:
        continue
    if e.get("dispatch", True) is False:
        continue
    untrusted = "1" if e.get("untrusted") else "0"
    when = e.get("when") or ["all"]
    if isinstance(when, str):
        when = [when]
    when_field = ",".join(str(w) for w in when) or "all"
    print(eid + "\t" + e.get("provider", eid) + "\t" + untrusted + "\t" + when_field)
' "${_plugin_ladder_yaml}" 2>/dev/null)" || _parsed=""
    fi
  fi
  if [[ -n "${_parsed}" ]]; then
    while IFS=$'\t' read -r _id _prov _untrusted _when; do
      _LADDER_IDS+=("${_id}")
      _LADDER_PROVIDERS+=("${_prov}")
      _LADDER_UNTRUSTED+=("${_untrusted:-0}")
      _LADDER_WHEN+=("${_when:-all}")
    done <<< "${_parsed}"
  fi
  # Fallback: legacy hardcoded order.
  if [[ ${#_LADDER_IDS[@]} -eq 0 ]]; then
    # Degraded-mode mirror of DISPATCHABLE_BUILD_ARMS in
    # lib/leadv2-glm-policy-resolve.py — asserted equal by
    # tests/test-arm-ladder-vocabulary-drift.sh.
    # kimi retired as a build arm (founder order 2026-08-04,
    # DISPATCH-KIMI-ARM-MISMATCH-01 / 3398d11).
    _LADDER_IDS=(glm codex sonnet)
    _LADDER_PROVIDERS=(glm codex anthropic)
    _LADDER_UNTRUSTED=(0 0 0)
    _LADDER_WHEN=(all all all)
  fi
}

# Build candidate_arms from the ladder: the resolved arm and every arm after
# it in ladder order. If the arm is not in the ladder, return the full ladder.
# T19 fix-round C1: once the positional chain is built, strip every arm
# flagged `untrusted: true` in the ladder (e.g. freepool) whenever the task is
# protected/safety-touched (DC_PROTECTED / DC_SAFETY env, same signals
# resolve_arm() already reads) -- class-aware, applied at every chain
# position, not just the primary-arm resolution. A named journal line makes
# the skip a fact, not a silent drop; if the filter would empty the chain,
# sonnet is kept as the fail-closed terminal arm.
_build_candidate_chain() {  # <arm> <sig8> ; mutates candidate_arms
  local _arm="$1" _sig8="$2" _i _found=0
  candidate_arms=()
  for _i in "${!_LADDER_IDS[@]}"; do
    if [[ "${_found}" == "1" ]]; then
      candidate_arms+=("${_LADDER_IDS[$_i]}")
    elif [[ "${_LADDER_IDS[$_i]}" == "${_arm}" ]]; then
      _found=1
      candidate_arms+=("${_LADDER_IDS[$_i]}")
    fi
  done
  if [[ "${_found}" != "1" ]]; then
    candidate_arms=(sonnet)
    emit decision "arm_vocabulary_mismatch by=router arm=${_arm} fallback=sonnet task=${_sig8} reason=launcher_unknown_arm"
    log_err "arm_vocabulary_mismatch: unknown arm=${_arm} for task=${_sig8}, falling back to sonnet"
  fi
  if [[ "${DC_PROTECTED:-0}" == "1" || "${DC_SAFETY:-0}" == "1" ]]; then
    local -a _trusted=()
    local _cand _cand_i _cand_untrusted
    for _cand in "${candidate_arms[@]}"; do
      _cand_untrusted=0
      for _cand_i in "${!_LADDER_IDS[@]}"; do
        if [[ "${_LADDER_IDS[$_cand_i]}" == "${_cand}" ]]; then
          _cand_untrusted="${_LADDER_UNTRUSTED[$_cand_i]:-0}"
          break
        fi
      done
      if [[ "${_cand_untrusted}" == "1" ]]; then
        emit decision "arm_excluded by=router arm=${_cand} task=${_sig8} reason=protected_path"
        continue
      fi
      _trusted+=("${_cand}")
    done
    [[ ${#_trusted[@]} -eq 0 ]] && _trusted=(sonnet)
    candidate_arms=("${_trusted[@]}")
  fi
  # T19 fix-round C2: `when:` on a ladder entry (e.g. freepool's
  # `when: [standard, bulk]`) previously had no reader -- every task class,
  # Heavy included, could spill to it. Enforce it against --task-class
  # (DC_TASK_CLASS env, lowercased; defaults to "standard" -- see cmd_resolve).
  # An entry's when list of "all" is always eligible; an unset/empty when list
  # is treated as "all" too (matches the loader's own default), so this can
  # never regress an arm that never declared a when constraint.
  local _size_class="${DC_TASK_CLASS:-standard}"
  _size_class="${_size_class,,}"
  local -a _sized=()
  local _s_cand _s_i _s_when _s_ok
  for _s_cand in "${candidate_arms[@]}"; do
    _s_when="all"
    for _s_i in "${!_LADDER_IDS[@]}"; do
      if [[ "${_LADDER_IDS[$_s_i]}" == "${_s_cand}" ]]; then
        _s_when="${_LADDER_WHEN[$_s_i]:-all}"
        break
      fi
    done
    _s_ok=0
    if [[ -z "${_s_when}" || ",${_s_when}," == *",all,"* ]]; then
      _s_ok=1
    elif [[ ",${_s_when}," == *",${_size_class},"* ]]; then
      _s_ok=1
    fi
    if [[ "${_s_ok}" != "1" ]]; then
      emit decision "arm_excluded by=router arm=${_s_cand} task=${_sig8} reason=arm_not_capable_for_size task_class=${_size_class} when=${_s_when}"
      continue
    fi
    _sized+=("${_s_cand}")
  done
  [[ ${#_sized[@]} -eq 0 ]] && _sized=(sonnet)
  candidate_arms=("${_sized[@]}")
}

# Return the provider for a given arm id from the loaded ladder.
_arm_provider() {  # <arm_id> -> provider string
  local _arm="$1" _i
  for _i in "${!_LADDER_IDS[@]}"; do
    if [[ "${_LADDER_IDS[$_i]}" == "${_arm}" ]]; then
      printf '%s' "${_LADDER_PROVIDERS[$_i]}"
      return
    fi
  done
  printf '%s' "${_arm}"
}

# Single reader for the DISPATCHABLE_BUILD_ARMS set (lib/leadv2-glm-policy-resolve.py).
# Fail-open default matches the pre-extraction inline behaviour: a broken
# importlib read must never fail the dispatcher closed. Emits a distinct
# journal line when the read itself fails, so a silent fallback is visible.
_dispatchable_arms() {  # () -> stdout: space-separated ids
  local _sig8="${1:-}" _dispatchable
  _dispatchable="$(python3 -c '
import importlib.util, sys
spec = importlib.util.spec_from_file_location("_pr", sys.argv[1])
m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)
print(" ".join(sorted(m.DISPATCHABLE_BUILD_ARMS)))
' "${SCRIPT_DIR}/lib/leadv2-glm-policy-resolve.py" 2>/dev/null)"
  if [[ -z "${_dispatchable}" ]]; then
    _dispatchable="glm codex sonnet"
    emit decision "dispatchable_arms_read_failed task=${_sig8} fallback=glm,codex,sonnet reason=importlib_read_failed"
  fi
  printf '%s' "${_dispatchable}"
}

# Map a router_v2 arm id to the launcher's spawn-case vocabulary. Table-free
# prefix strip: claude-<model> -> <model>. Everything else is identity, so a
# future claude-fable needs no edit here.
_normalize_v2_arm() {  # <v2_arm_id> -> stdout: launcher arm id
  local _id="$1"
  case "${_id}" in
    claude-*) printf '%s' "${_id#claude-}" ;;
    *) printf '%s' "${_id}" ;;
  esac
}

# Drop any id in candidate_arms that is not in DISPATCHABLE_BUILD_ARMS.
# Shared by both v1 (ladder-derived) and v2 (resolver-derived) candidate
# chains so the retirement of an arm (dispatch:false / commented-out) is
# enforced identically on both paths -- never a second hand-kept exclusion
# list. Mutates the caller's candidate_arms array in place.
# Optional third arg (ROUTER-V2-BYPASSES-ARM-LADDER-FILTER-01): the v2
# chain-adoption SITE that called in (initial|quota_filter|quota_gate). Key
# order is unchanged, site= is only APPENDED, so existing greps for
# `arm_dropped_not_dispatchable ... router=v2` keep matching.
_filter_arms_to_dispatchable() {  # <sig8> <router_label:v1|v2> [site]
  local _sig8="$1" _router="$2" _site="${3:-}" _dispatchable _id _keep _d
  _dispatchable="$(_dispatchable_arms "${_sig8}")"
  local -a _kept=()
  for _id in "${candidate_arms[@]}"; do
    _keep=0
    for _d in ${_dispatchable}; do
      [[ "${_id}" == "${_d}" ]] && { _keep=1; break; }
    done
    if [[ "${_keep}" == "1" ]]; then
      _kept+=("${_id}")
    else
      emit decision "arm_dropped_not_dispatchable arm=${_id} task=${_sig8} router=${_router} reason=not_in_DISPATCHABLE_BUILD_ARMS${_site:+ site=${_site}}"
    fi
  done
  candidate_arms=("${_kept[@]}")
}

# ROUTER-V2-BYPASSES-ARM-LADDER-FILTER-01: the single adopter every v2
# chain-adoption site goes through -- primary resolve (site=initial), the
# LEADV2_ROUTER_V2_QUOTA_FILTER re-resolve (site=quota_filter) and the
# glm_refused_quota_gate reroute (site=quota_gate). Split -> _normalize_v2_arm
# -> _filter_arms_to_dispatchable, so "every chain the launcher consumes has
# passed DISPATCHABLE_BUILD_ARMS" holds structurally, not positionally at one
# of three sites. Mutates the CALLER's candidate_arms in place (dynamic
# scoping, same mechanism _filter_arms_to_dispatchable already relies on).
# Returns 0 when at least one dispatchable arm survives; on an empty survivor
# set emits dispatch_rolled_back reason=all_arms_not_dispatchable_v2 (with
# site=) and returns 4 -- the CALLER decides whether that means exit (initial,
# quota_filter) or fall back to the pre-reroute chain (quota_gate: an exit
# inside the candidate loop would turn a recoverable refusal into a dead lane).
_adopt_v2_chain() {  # <sig8> <site: initial|quota_filter|quota_gate> <csv_chain>
  local _sig8="$1" _site="$2" _csv="$3" _a
  IFS=',' read -r -a candidate_arms <<< "${_csv}"
  local -a _norm=()
  for _a in "${candidate_arms[@]}"; do
    [[ -n "${_a}" ]] || continue
    _norm+=("$(_normalize_v2_arm "${_a}")")
  done
  candidate_arms=("${_norm[@]}")
  _filter_arms_to_dispatchable "${_sig8}" v2 "${_site}"
  if [[ ${#candidate_arms[@]} -eq 0 || -z "${candidate_arms[0]:-}" ]]; then
    emit decision "dispatch_rolled_back reason=all_arms_not_dispatchable_v2 task=${_sig8} router=v2 site=${_site}"
    return 4
  fi
  return 0
}

# C1 tenant-yaml resurrection guard: after _load_dispatch_ladder populates
# _LADDER_IDS from the (possibly stale) project or plugin yaml, drop any id
# not in DISPATCHABLE_BUILD_ARMS. This prevents a stale tenant yaml that still
# lists kimi as dispatchable from resurrecting a retired arm.
_filter_ladder_to_dispatchable() {  # <sig8>
  local _sig8="$1" _dispatchable _id _i _keep _d
  _dispatchable="$(_dispatchable_arms "${_sig8}")"
  local -a _new_ids=() _new_provs=()
  for _i in "${!_LADDER_IDS[@]}"; do
    _id="${_LADDER_IDS[$_i]}"
    _keep=0
    for _d in ${_dispatchable}; do
      [[ "${_id}" == "${_d}" ]] && { _keep=1; break; }
    done
    if [[ "${_keep}" == "1" ]]; then
      _new_ids+=("${_id}")
      _new_provs+=("${_LADDER_PROVIDERS[$_i]}")
    else
      emit decision "arm_dropped_not_dispatchable arm=${_id} task=${_sig8} router=v1 reason=not_in_DISPATCHABLE_BUILD_ARMS"
    fi
  done
  _LADDER_IDS=("${_new_ids[@]}")
  _LADDER_PROVIDERS=("${_new_provs[@]}")
}

# P2: per-provider lockout record directory. Lives alongside the dispatch ledger.
QUOTA_LOCKOUT_DIR="${LEADV2_QUOTA_LOCKOUT_DIR:-${DISPATCH_LEDGER_DIR}}"

# PROVIDER-LOCKOUT-FALSE-BLOCK-01: the lockout store's ONE bash-side interpreter.
# <provider> -> "locked <remaining_s>" | "expired" | "absent" | "malformed".
# Missing/malformed/expired ALWAYS read as not-locked — never fail closed.
_lockout_state() {  # <provider>
  local provider="$1" _lock_file _out
  _lock_file="${QUOTA_LOCKOUT_DIR}/quota-lockout-${provider}.json"
  [[ -f "${_lock_file}" ]] || { printf 'absent\n'; return 0; }
  _out="$(python3 - "${_lock_file}" 2>/dev/null <<'PY'
import json, sys, time
try:
    d = json.load(open(sys.argv[1]))
    until = int(d.get("locked_until_epoch"))
except Exception:
    print("malformed"); raise SystemExit(0)
now = int(time.time())
print("locked %d" % (until - now) if until > now else "expired")
PY
)" || _out=""
  case "${_out}" in
    'locked '*|expired|malformed) printf '%s\n' "${_out}" ;;
    *)                             printf 'malformed\n' ;;
  esac
}

# <provider> <field> -> the record's field, fail-open "unknown" on any read error.
_lockout_record_field() {  # <provider> <field>
  local provider="$1" field="$2" _out
  _out="$(python3 - "${QUOTA_LOCKOUT_DIR}/quota-lockout-${provider}.json" "${field}" 2>/dev/null <<'PY'
import json, sys
try:
    d = json.load(open(sys.argv[1]))
    v = d.get(sys.argv[2], "")
    print(v if v not in (None, "") else "unknown")
except Exception:
    print("unknown")
PY
)" || _out=""
  [[ -n "${_out}" ]] || _out="unknown"
  printf '%s' "${_out}"
}

# <provider> -> prior record's strikes count, fail-open 0 (none/malformed/absent).
_lockout_prior_strikes() {  # <provider>
  local _n
  _n="$(_lockout_record_field "$1" strikes)"
  [[ "${_n}" =~ ^[0-9]+$ ]] || _n=0
  printf '%s' "$(( _n > 0 ? _n : 0 ))"
}

# Check whether a provider is currently locked out.
# Returns 0 (available) or 1 (locked). A missing/unreadable record ALWAYS
# means "not locked" — never fail closed. Reimplemented as a thin wrapper over
# _lockout_state so expiry has exactly ONE rule bash-side (the python resolver's
# _lockout_blocked already honoured it — F4/F5 in the design, regression-locked
# by tests/test-lockout-failure-class.sh T4/T5).
_provider_available() {  # <provider> -> 0=available, 1=locked
  local _st
  _st="$(_lockout_state "$1")"
  case "${_st}" in
    'locked '*) return 1 ;;
    *)          return 0 ;;
  esac
}

# PROVIDER-LOCKOUT-FALSE-BLOCK-01 Defect C: losing the PRIMARY code writer for
# hours must be LOUD. Renders a stderr banner at the head of every dispatch
# while the routing ladder's FIRST dispatchable arm's provider is locked. The
# primary is read from _LADDER_IDS[0] after _load_dispatch_ladder — never a
# hardcoded arm name (R6); a ladder that somehow stays empty skips the banner
# (fail-quiet). LEADV2_LOCKOUT_LOUD_MINUTES (default 0 = always) suppresses the
# banner for lockouts shorter than N minutes, so a 10-minute self-healing
# post-spawn bench does not become noise.
_lockout_bench_banner() {  # <sig8>
  local sig8="$1" _st _primary _prov _remaining _mins _cls _until _source _loud
  (( ${#_LADDER_IDS[@]} > 0 )) || _load_dispatch_ladder
  (( ${#_LADDER_IDS[@]} > 0 )) || return 0
  _primary="${_LADDER_IDS[0]}"
  _prov="$(_arm_provider "${_primary}")"
  _st="$(_lockout_state "${_prov}")"
  [[ "${_st}" == 'locked '* ]] || return 0
  _remaining="${_st#locked }"
  _mins=$(( _remaining / 60 + ( _remaining % 60 > 0 ? 1 : 0 ) ))
  _loud="${LEADV2_LOCKOUT_LOUD_MINUTES:-0}"
  [[ "${_loud}" =~ ^[0-9]+$ ]] || _loud=0
  (( _mins >= _loud )) || return 0
  _cls="$(_lockout_record_field "${_prov}" class)"
  _until="$(_lockout_record_field "${_prov}" locked_until)"
  _source="$(_lockout_record_field "${_prov}" source)"
  printf '⚠ PRIMARY ARM BENCHED: %s for %dm (class=%s, until %s) — cause: %s\n' \
    "${_prov}" "${_mins}" "${_cls}" "${_until}" "${_source}" >&2
  emit decision "primary_arm_benched provider=${_prov} arm=${_primary} class=${_cls} minutes=${_mins} until=${_until} source=${_source} task=${sig8}"
}

# <class> <site> -> the class's lockout cap in minutes (design §3 duration table).
_lockout_class_cap() {  # <class> <site>
  local cls="$1" site="$2" cap
  case "${cls}" in
    launcher_never_started) cap=30 ;;
    worker_killed)          cap=60 ;;
    infra_transient)        cap=60 ;;
    provider_refusal)
      if [[ "${site}" == "postspawn" ]]; then
        # THE single change that kills the 24h bench: after-enqueue evidence is
        # untrusted, so a post-spawn refusal self-heals in minutes-scale.
        cap="${LEADV2_LOCKOUT_CAP_POSTSPAWN:-60}"
      else
        cap="${LEADV2_QUOTA_LOCKOUT_MAX_MINUTES:-4320}"
      fi
      ;;
    *) cap=60 ;;
  esac
  [[ "${cap}" =~ ^[0-9]+$ ]] || cap=60
  printf '%s' "${cap}"
}

# <minutes> -> now+minutes ISO (UTC). Same portable date idiom as the old
# _default_quota_lockout_iso (macOS -v first, GNU -d fallback).
_lockout_iso_from_minutes() {  # <minutes>
  date -u -v+"$1"M +%Y-%m-%dT%H:%M:%SZ 2>/dev/null \
    || date -u -d "+$1 minutes" +%Y-%m-%dT%H:%M:%SZ
}

# <iso> <max_minutes> -> the ISO clamped to now+max (i.e. the min of the two);
# empty on an unparseable input (caller falls back to the minutes path).
_lockout_iso_clamped() {  # <iso> <max_minutes>
  python3 - "$1" "$2" 2>/dev/null <<'PY'
import sys, time
from datetime import datetime, timezone
try:
    dt = datetime.fromisoformat(sys.argv[1].replace("Z", "+00:00"))
    iso_e = int(dt.timestamp())
except Exception:
    raise SystemExit(0)
try:
    cap = int(time.time()) + int(sys.argv[2]) * 60
except Exception:
    raise SystemExit(0)
print(datetime.fromtimestamp(min(iso_e, cap), tz=timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"))
PY
}

# <iso> -> whole minutes from now until the ISO (rounded up), fail-open 0.
_iso_remaining_minutes() {  # <iso>
  local _m
  _m="$(python3 - "$1" 2>/dev/null <<'PY'
import sys, time
from datetime import datetime
try:
    dt = datetime.fromisoformat(sys.argv[1].replace("Z", "+00:00"))
    rem = int(dt.timestamp()) - int(time.time())
except Exception:
    print(0); raise SystemExit(0)
print(max(0, -(-rem // 60)))
PY
)" || _m=""
  [[ "${_m}" =~ ^[0-9]+$ ]] || _m=0
  printf '%s' "${_m}"
}

# _classify_arm_failure <site> <arm> <text> [probe_rc] [refusal_reason]
#   -> "class|minutes|evidence" on stdout. Falls back to unclassified|0|no_classifier
#   when the lib is absent/unreadable (fail-open = NO lockout, R3).
_classify_arm_failure() {  # <site> <arm> <text> [probe_rc] [refusal_reason]
  local site="$1" arm="$2" text="$3" probe_rc="${4:-}" refusal="${5:-}"
  local lib="${SCRIPT_DIR}/lib/leadv2-lockout-classify.py" out
  [[ -f "${lib}" ]] || { printf 'unclassified|0|no_classifier\n'; return 0; }
  out="$(printf '%s' "${text}" | python3 "${lib}" --site "${site}" \
    ${refusal:+--refusal-reason "${refusal}"} \
    ${probe_rc:+--probe-rc "${probe_rc}"} 2>/dev/null)" || out=""
  [[ "${out}" =~ ^[a-z_]+\|[0-9]+\|.+$ ]] || out="unclassified|0|no_classifier"
  printf '%s\n' "${out}"
}

# Record a quota lockout for a provider.
# <provider> <locked_until_iso> <source> [<class>]
# Additive keys (PROVIDER-LOCKOUT-FALSE-BLOCK-01): "class" (unknown when the
# caller passes none) and "strikes" (prior record's strikes + 1, read
# fail-open). Consumers reading only locked_until_epoch are unaffected.
# Known race (design R4): two concurrent dispatches can lose one strike —
# worst case a SHORTER lockout, i.e. the fail-open direction. Documented.
_record_quota_lockout() {
  local provider="$1" _iso="$2" _source="$3" _class="${4:-}" _lock_file _epoch _strikes
  _lock_file="${QUOTA_LOCKOUT_DIR}/quota-lockout-${provider}.json"
  _epoch="$(python3 -c "
import sys
from datetime import datetime
try:
    dt = datetime.fromisoformat(sys.argv[1].replace('Z','+00:00'))
    print(int(dt.timestamp()))
except Exception:
    print(0)
" "${_iso}" 2>/dev/null)" || return 0
  [[ "${_epoch}" =~ ^[0-9]+$ && "${_epoch}" != "0" ]] || return 0
  _strikes=$(( $(_lockout_prior_strikes "${provider}") + 1 ))
  [[ -n "${_class}" ]] || _class="unknown"
  mkdir -p "${QUOTA_LOCKOUT_DIR}" 2>/dev/null || true
  local _tmp_file="${_lock_file}.tmp.$$"
  python3 -c "
import json, sys
d = {'provider': sys.argv[1], 'locked_until': sys.argv[2],
     'locked_until_epoch': int(sys.argv[3]), 'source': sys.argv[4],
     'class': sys.argv[5], 'strikes': int(sys.argv[6])}
with open(sys.argv[7], 'w') as f:
    json.dump(d, f)
" "${provider}" "${_iso}" "${_epoch}" "${_source}" "${_class}" "${_strikes}" "${_tmp_file}" 2>/dev/null || true
  mv -f "${_tmp_file}" "${_lock_file}" 2>/dev/null || true
}

# _record_postspawn_lockout <arm> <final_output_text>
#   -> rc0: record written; stdout "class|minutes|strikes|source|iso|evidence"
#   -> rc1: unclassified, NO record written (design data-flow step 4);
#           stdout "unclassified|0|0|<evidence>||<evidence>"
# Shared by _wait_arm_early_verdict and cmd_record_quota_lockout so both
# post-spawn sites classify identically.
_record_postspawn_lockout() {  # <arm> <final_output_text>
  local arm="$1" text="$2"
  local _cls_line _cls _cls_min _evidence
  _cls_line="$(_classify_arm_failure postspawn "${arm}" "${text}")"
  IFS='|' read -r _cls _cls_min _evidence <<<"${_cls_line}"
  if [[ "${_cls}" == "unclassified" ]]; then
    printf 'unclassified|0|0|%s||%s\n' "${_evidence}" "${_evidence}"
    return 1
  fi
  local _prov _cap _strikes _minutes _iso _source _clamped
  _prov="$(_arm_provider "${arm}")"
  _cap="$(_lockout_class_cap "${_cls}" postspawn)"
  _strikes=$(( $(_lockout_prior_strikes "${_prov}") + 1 ))
  _minutes="${_cls_min}"
  _iso=""
  _source="class_${_cls}"
  if [[ "${_cls}" == "provider_refusal" ]]; then
    local _iso_src
    _iso_src="$(_quota_return_time "${text}")"
    _iso="${_iso_src%%|*}"
    if [[ -n "${_iso}" ]]; then
      _source="${_iso_src##*|}"
      _clamped="$(_lockout_iso_clamped "${_iso}" "${_cap}")"
      if [[ -n "${_clamped}" ]]; then
        [[ "${_clamped}" != "${_iso}" ]] && _source="provider_time_clamped_postspawn"
        _iso="${_clamped}"
      fi
    else
      _source="default"
    fi
  fi
  if [[ -z "${_iso}" ]]; then
    # Strikes escalation (design §3): double per re-lock, capped at the class
    # cap — a genuinely dry provider converges to the cap instead of costing a
    # day on the first mistake, and a false class self-heals in minutes.
    local _k=$(( _strikes - 1 )); (( _k > 6 )) && _k=6
    while (( _k > 0 )); do _minutes=$(( _minutes * 2 )); _k=$(( _k - 1 )); done
    (( _minutes > _cap )) && _minutes="${_cap}"
    _iso="$(_lockout_iso_from_minutes "${_minutes}")"
  else
    _minutes="$(_iso_remaining_minutes "${_iso}")"
  fi
  _record_quota_lockout "${_prov}" "${_iso}" "postspawn_failure:${arm}" "${_cls}"
  printf '%s|%s|%s|%s|%s|%s\n' "${_cls}" "${_minutes}" "${_strikes}" "${_source}" "${_iso}" "${_evidence}"
  return 0
}

# _default_quota_lockout_iso: the flat "now + LEADV2_QUOTA_LOCKOUT_MINUTES" fallback,
# unchanged from before CODEX-QUOTA-LOCKOUT-NEVER-FIRES-FOR-CODEX-01 -- used whenever
# _quota_return_time (leadv2-quota-error-parse.py) has nothing parseable to offer.
_default_quota_lockout_iso() {
  date -u -v+"${LEADV2_QUOTA_LOCKOUT_MINUTES:-30}"M +%Y-%m-%dT%H:%M:%SZ 2>/dev/null \
    || date -u -d "+${LEADV2_QUOTA_LOCKOUT_MINUTES:-30} minutes" +%Y-%m-%dT%H:%M:%SZ
}

# _maybe_record_quota_lockout: called from each arm's refusal branch when the
# refusal reason is quota-shaped. Writes a lockout record so the NEXT dispatch
# skips this provider via the quota precheck.
# <arm> <refusal_reason> [<raw_launcher_text>] -- the raw text (launcher stdout+stderr,
# when the caller has it) is fed to _quota_return_time so a provider-stated reset time
# improves on the flat default; when absent (back-compat: older/direct callers that only
# ever passed 2 args) this degrades EXACTLY to the pre-existing flat-default behavior --
# same call sites, same rc contract, unchanged when nothing is parseable.
_maybe_record_quota_lockout() {  # <arm> <refusal_reason> [<raw_text>]
  case "${2}" in
    quota|quota_gate|quota_exhausted|rate_limit*) ;;
    *) return 0 ;;
  esac
  # PROVIDER-LOCKOUT-FALSE-BLOCK-01: classify for the additive class/strikes
  # keys. A quota-shaped refusal reason forces provider_refusal, so behaviour
  # (hours-scale, LEADV2_QUOTA_LOCKOUT_* floor/ceiling) is unchanged here --
  # only the record's observability grows.
  local _cls_line _cls _cls_min _ev
  _cls_line="$(_classify_arm_failure launcher_refusal "${1}" "${3:-}" "" "${2}")"
  IFS='|' read -r _cls _cls_min _ev <<<"${_cls_line}"
  [[ "${_cls}" == "provider_refusal" ]] || _cls="provider_refusal"
  local _prov _iso_src _iso _source _strikes
  _prov="$(_arm_provider "${1}")"
  _strikes=$(( $(_lockout_prior_strikes "${_prov}") + 1 ))
  _iso_src="$(_quota_return_time "${3:-}")"
  _iso="${_iso_src%%|*}"
  _source="${_iso_src##*|}"
  if [[ -z "${_iso}" ]]; then
    _iso="$(_default_quota_lockout_iso)"
    _source="default"
  fi
  _record_quota_lockout "${_prov}" "${_iso}" "launcher_refusal:${2}" "${_cls}"
  emit decision "quota_lockout_recorded provider=${_prov} arm=${1} reason=${2} class=${_cls} minutes=$(_iso_remaining_minutes "${_iso}") strikes=${_strikes} source=${_source}"
}

# ── end ARM-LADDER-HAS-NO-QUOTA-PRECHECK-01 ───────────────────────────────────
# router-v2's filter, not in this funnel.
# PREPASS-PROVIDER-FALLBACK-01-R2: resolver stderr is no longer discarded. This
# function runs inside a command substitution, so globals do not propagate --
# stage/detail for a FAILED resolution are written to $V2_FAIL_FILE (created by
# the caller, read back after the rc check) as two lines: stage=<name> and
# detail=<bounded first stderr lines>. The caller's refusal journal line and
# log_err then name the failing stage and the config it complains about, so a
# `router_v2_unavailable` is actionable instead of a bare rc.
_v2_fail() {  # <stage> <stderr_file | detail-text>  (text mode: 3rd arg "-detail")
  [[ -n "${V2_FAIL_FILE:-}" ]] || return 0
  local _detail
  if [[ "${3:-}" == "-detail" ]]; then
    _detail="$2"
  else
    _detail="$(head -3 "$2" 2>/dev/null | tr '\n' ' ' | tr -cd '[:print:]' | cut -c1-200)"
  fi
  printf 'stage=%s\ndetail=%s\n' "$1" "${_detail}" > "${V2_FAIL_FILE}" 2>/dev/null || true
}
resolve_v2_dispatch() {
  local mission="$1" sig8="$2" class="$3" kind="$4" protected="$5" tmp out estimate allowed task_class rc errf miss
  local rv2="${LEADV2_ROUTER_V2_BIN:-${SCRIPT_DIR}/leadv2-router-v2.sh}" judge="${LEADV2_TASK_JUDGE_BIN:-${SCRIPT_DIR}/leadv2-task-judge.sh}" bandit="${LEADV2_ROUTE_BANDIT_BIN:-${SCRIPT_DIR}/leadv2-route-bandit.sh}"
  miss=""
  local _c
  for _c in "$rv2" "$judge" "$bandit"; do [[ -f "$_c" ]] || miss="${miss}${miss:+ }${_c}"; done
  if [[ -n "$miss" ]]; then
    _v2_fail "component_missing" "missing: ${miss}" -detail
    return 1
  fi
  tmp="$(mktemp -d "${TMPDIR:-/tmp}/leadv2-dispatch-v2.XXXXXX")" || return 1
  errf="${tmp}/stage.err"
  printf '%s' "$mission" > "$tmp/mission"
  out="$(PROJECT_ROOT="$PROJECT_ROOT" LEADV2_ROUTING_YAML="$ROUTING_YAML" bash "$rv2" filter --task-id "$sig8" --mission-kind "$kind" $([[ "$protected" == 1 ]] && printf -- '--protected-path') 2>"$errf")" \
    || { _v2_fail "filter" "$errf"; rm -rf "$tmp"; return 1; }
  python3 -c 'import json,sys; r=sys.stdin.read().splitlines(); e=next((x[9:] for x in r if x.startswith("eligible=")),""); f=next((x[9:] for x in r if x.startswith("filtered=")),"[]"); json.dump({"eligible":[x for x in e.split(",") if x],"filtered":json.loads(f)},sys.stdout)' <<<"$out" > "$tmp/l1.json" 2>"$errf" \
    || { _v2_fail "l1_parse" "$errf"; rm -rf "$tmp"; return 1; }
  estimate="$(PROJECT_ROOT="$PROJECT_ROOT" LEADV2_ROUTER_V2=1 bash "$judge" --mission-file "$tmp/mission" --task-id "$sig8" --class "$class" 2>"$errf")" \
    || { _v2_fail "judge" "$errf"; rm -rf "$tmp"; return 1; }
  printf '%s' "$estimate" > "$tmp/estimate.json"
  allowed="$(python3 -c 'import json,sys; print(json.dumps(json.load(open(sys.argv[1]))["eligible"]))' "$tmp/l1.json")"
  task_class="$(python3 -c 'import json,sys; e=json.load(open(sys.argv[1])); print(e["work_kind"]+":"+("short" if e["duration_class"]=="short" and e["complexity"] in ("trivial","simple") else "long"))' "$tmp/estimate.json")"
  out="$(PROJECT_ROOT="$PROJECT_ROOT" LEADV2_PROJECT_ROOT="$PROJECT_ROOT" LEADV2_ROUTER_V2=1 bash "$bandit" sample --context-key "$task_class" --allowed "$allowed" --heuristic glm 2>"$errf")" || true
  printf '%s\n' "$out" | sed -n 's/^samples=//p' | head -1 > "$tmp/samples.json"
  python3 -c 'import json,sys; json.load(open(sys.argv[1]))' "$tmp/samples.json" >/dev/null 2>&1 || python3 -c 'import json,sys; print(json.dumps({x:.75 for x in json.load(open(sys.argv[1]))["eligible"]}))' "$tmp/l1.json" > "$tmp/samples.json"
  python3 -c 'import json,sys,yaml; json.dump(((yaml.safe_load(open(sys.argv[1])) or {}).get("router_v2") or {}).get("headroom_weights",[]),open(sys.argv[2],"w"))' "$ROUTING_YAML" "$tmp/weights.json" 2>"$errf" \
    || { _v2_fail "weights_parse" "$errf"; rm -rf "$tmp"; return 1; }
  out="$(PROJECT_ROOT="$PROJECT_ROOT" LEADV2_ROUTING_YAML="$ROUTING_YAML" bash "$rv2" resolve --task-id "$sig8" --routing-yaml "$ROUTING_YAML" --l1-json "$tmp/l1.json" --estimate-json "$tmp/estimate.json" --samples-json "$tmp/samples.json" --headroom-weights-json "$tmp/weights.json" --account "${LEADV2_ROUTER_V2_ACCOUNT:-unknown}" 2>"$errf")"; rc=$?
  [[ $rc -eq 0 ]] || { _v2_fail "resolve" "$errf"; rm -rf "$tmp"; return "$rc"; }
  rm -rf "$tmp"; printf '%s\ntier=%s\n' "$out" "${LEADV2_ROUTER_V2_CODEX_TIER:-standard}"
}

# ── dispatch-ledger dedup (FIX PASS 4: pending/confirmed + TTL, see doc block above) ──
dispatch_lock_file() { printf '%s/.%s.dispatch.lock' "${DISPATCH_LEDGER_DIR}" "$(repo_slug)"; }
_now_epoch() { date +%s 2>/dev/null || printf '0'; }

# Unique per-reservation token: pid + epoch + uuid/urandom -- NOT a bare 1-second timestamp,
# so two callers that reserve in the SAME UTC second still get DISTINCT, individually
# addressable tokens (mission: "SAME-SECOND UNIQUE"). uuidgen ships on macOS + most Linux
# (util-linux); /dev/urandom is the fallback, $RANDOM x3 the last-resort fallback.
_dispatch_new_token() {
  local pid rnd
  pid="${BASHPID:-$$}"
  if command -v uuidgen >/dev/null 2>&1; then
    rnd="$(uuidgen 2>/dev/null)"   # opaque token -- case doesn't matter, no need to fold
  fi
  if [[ -z "${rnd:-}" ]]; then
    rnd="$(od -An -N8 -tx1 /dev/urandom 2>/dev/null | tr -d ' \n')"
  fi
  [[ -n "${rnd:-}" ]] || rnd="${RANDOM}${RANDOM}${RANDOM}"
  printf '%s-%s-%s' "${pid}" "$(_now_epoch)" "${rnd}"
}

# ── DISPATCH-OUTCOME-LEDGER-01 helpers (doc block item 8) ─────────────────────────
# Extracts the fields the outcome check needs from one ledger row, in a SINGLE python
# call (rows are small, but a sig with an active row is looked up on every dispatch of
# that mission, so one parse beats five). Missing/unparseable fields come back empty --
# callers already treat empty arm/handle as "unknown liveness" (blocks, same as today).
_dispatch_row_fields() {  # <json_line> -> "state<TAB>created_epoch<TAB>arm<TAB>handle<TAB>token<TAB>task_id"
  # SD-CHECKPOINT-CUTOFF-LANEID-01: task_id appended (never inserted -- every existing
  # caller's positional `read` still lands token in the right var) so a caller that DOES
  # need the founder task_id / lane-id (the checkpoint-commit-cutoff worktree resolve) can
  # get it from the SAME row it already parsed, instead of a second lookup.
  python3 -c "
import json, sys
try:
    d = json.loads(sys.argv[1])
except Exception:
    d = {}
print('\t'.join(str(d.get(k, '') or '') for k in ('state', 'created_epoch', 'arm', 'handle', 'token', 'task_id')))
" "$1" 2>/dev/null
}

# Strips a raw launcher handle down to the bare identifier the liveness check needs, and to
# something safe to hand-embed in JSON (no quotes/backslashes). glm run-ids and codex job-
# ids are already alnum/dash. sonnet's raw handle is claude-subsession.sh's whole handle
# line, "PID=<n> LABEL=... SESSION_ID=..." -- only the PID is a liveness token.
_dispatch_normalize_handle() {  # <arm> <raw_handle> -> normalized handle (may be empty)
  local arm="$1" raw="$2"
  case "${arm}" in
    sonnet) printf '%s\n' "${raw}" | sed -n 's/^PID=\([0-9][0-9]*\).*/\1/p' ;;
    # kimi run-ids are alnum/dash, same shape as glm's -- explicit case for
    # readability, identical to the default branch (KIMI-CHANNEL-01).
    kimi)   printf '%s' "${raw//[\"\\]/}" ;;
    *)      printf '%s' "${raw//[\"\\]/}" ;;
  esac
}

# Per-arm liveness, reusing the SAME checks each arm's own spawn-time verification already
# performs (glm: glm-coder.sh status; sonnet: kill -0; codex: leadv2-lane-liveness.sh, the
# shared authoritative-provider-status tool -- composes with it instead of re-deriving codex
# job state here). "unknown" is the safe default on any ambiguity (unreadable status, no
# handle recorded -- e.g. a pre-existing row from before this feature shipped, or an opus
# row that never spawns): a row whose liveness can't be proven dead keeps blocking, exactly
# like today, never freed on a guess.
_dispatch_worker_liveness() {  # <arm> <handle> -> alive|dead|unknown (stdout)
  local arm="$1" handle="$2"
  [[ -n "${handle}" ]] || { printf 'unknown'; return; }
  case "${arm}" in
    glm)
      local raw status
      raw="$(bash "${GLM_BIN}" status "${handle}" 2>/dev/null)" || { printf 'unknown'; return; }
      status="$(printf '%s\n' "${raw}" | sed -n 's/^status:[[:space:]]*//p' | head -1)"
      case "${status}" in
        running)         printf 'alive' ;;
        complete|failed) printf 'dead' ;;
        *)               printf 'unknown' ;;
      esac
      ;;
    kimi)
      # KIMI-CHANNEL-01: identical shape to the glm case above -- kimi-coder.sh's
      # `status` subcommand resolves the same run-dir its own `bg` call created.
      local raw status
      raw="$(bash "${KIMI_BIN}" status "${handle}" 2>/dev/null)" || { printf 'unknown'; return; }
      status="$(printf '%s\n' "${raw}" | sed -n 's/^status:[[:space:]]*//p' | head -1)"
      case "${status}" in
        running)         printf 'alive' ;;
        complete|failed) printf 'dead' ;;
        *)               printf 'unknown' ;;
      esac
      ;;
    freepool)
      # T19: identical shape to the glm case above -- freepool-coder.sh's
      # `status` subcommand resolves the same run-dir its own `bg` call created.
      local raw status
      raw="$(bash "${FREEPOOL_BIN}" status "${handle}" 2>/dev/null)" || { printf 'unknown'; return; }
      status="$(printf '%s\n' "${raw}" | sed -n 's/^status:[[:space:]]*//p' | head -1)"
      case "${status}" in
        running)         printf 'alive' ;;
        complete|failed) printf 'dead' ;;
        *)               printf 'unknown' ;;
      esac
      ;;
    sonnet)
      if [[ "${handle}" =~ ^[0-9]+$ ]] && kill -0 "${handle}" 2>/dev/null; then
        printf 'alive'
      else
        printf 'dead'
      fi
      ;;
    codex)
      local liveness_bin verdict
      liveness_bin="${LEADV2_DISPATCH_LANE_LIVENESS_BIN:-${SCRIPT_DIR}/leadv2-lane-liveness.sh}"
      [[ -f "${liveness_bin}" ]] || { printf 'unknown'; return; }
      verdict="$(CODEX_TASK_SH="${CODEX_BIN}" bash "${liveness_bin}" \
        --project-root "${PROJECT_ROOT}" --job "${handle}" --json 2>/dev/null \
        | python3 -c "
import json, sys
try:
    d = json.load(sys.stdin); jobs = d.get('jobs') or []
    print(jobs[0].get('verdict', 'unknown') if jobs else 'unknown')
except Exception:
    print('unknown')
" 2>/dev/null)"
      case "${verdict}" in
        running)               printf 'alive' ;;
        done|failed|cancelled) printf 'dead' ;;
        *)                     printf 'unknown' ;;
      esac
      ;;
    *) printf 'unknown' ;;
  esac
}

# rc0: attributed evidence found or the check is undeterminable; rc1: POSITIVELY proven
# empty. Attribution is either a current reservation's own completion/checkpoint/summary
# artifact or a non-runtime commit since <created_epoch> whose message explicitly names
# <sig8>. This intentionally does NOT treat another lane's same-clock commit as evidence.
# The asymmetry is deliberate: any unreadable/malformed input blocks rather than frees.
_dispatch_handoff_evidence_exists() {  # <sig8> <created_epoch> -> rc0 evidence/unknown; rc1 none
  local sig8="$1" created="$2" dir artifact mtime
  [[ "${created}" =~ ^[0-9]+$ ]] || return 0
  dir="${PROJECT_ROOT}/docs/handoff/dispatch-${sig8}"
  [[ -e "${dir}" ]] || return 1
  [[ -d "${dir}" && -r "${dir}" ]] || return 0
  for artifact in "${dir}/SUMMARY.md" "${dir}/summary.md" "${dir}/CHECKPOINT.md" "${dir}/phase8-passed.flag"; do
    [[ -e "${artifact}" ]] || continue
    [[ -f "${artifact}" ]] || return 0
    mtime="$(stat -f %m "${artifact}" 2>/dev/null || stat -c %Y "${artifact}" 2>/dev/null)" || return 0
    [[ "${mtime}" =~ ^[0-9]+$ ]] || return 0
    (( mtime >= created )) && return 0
  done
  return 1
}

_dispatch_evidence_exists() {  # <created_epoch> <sig8> -> rc0 evidence/unknown; rc1 none
  local created="$1" sig8="$2" since_iso raw grc
  [[ "${created}" =~ ^[0-9]+$ ]] || return 0
  [[ "${sig8}" =~ ^[a-f0-9]{8}$ ]] || return 0
  if [[ "${EVIDENCE_ATTRIBUTION}" == "1" ]] && _dispatch_handoff_evidence_exists "${sig8}" "${created}"; then
    return 0
  fi
  since_iso="$(python3 -c "
import datetime, sys
print(datetime.datetime.utcfromtimestamp(int(sys.argv[1])).strftime('%Y-%m-%dT%H:%M:%SZ'))
" "${created}" 2>/dev/null)"
  [[ -n "${since_iso}" ]] || return 0
  if [[ "${EVIDENCE_ATTRIBUTION}" == "1" ]]; then
    raw="$(git -C "${PROJECT_ROOT}" log --all --since="${since_iso}" --fixed-strings --grep="${sig8}" --name-only --pretty=format: 2>/dev/null)"; grc=$?
  else
    raw="$(git -C "${PROJECT_ROOT}" log --all --since="${since_iso}" --name-only --pretty=format: 2>/dev/null)"; grc=$?
  fi
  [[ ${grc} -eq 0 ]] || return 0
  printf '%s\n' "${raw}" | grep -vE '^\s*$' | grep -vE "${EVIDENCE_EXCLUDE_RE}" | grep -q .
}

# DISPATCH-LEDGER-PARTIAL-CLOSE-01 (see doc block item 9): deterministic docs/handoff paths
# for the two already-recorded signals this composes -- spawn_worker's sonnet arm always
# launches with --task-id "dispatch-${sig8}", so both paths are derivable from sig8 alone.
_dispatch_checkpoint_marker() {  # <sig8> -> path (stdout)
  printf '%s/docs/handoff/dispatch-%s/CHECKPOINT.md' "${PROJECT_ROOT}" "$1"
}
_dispatch_completion_sentinel() {  # <sig8> -> path (stdout)
  printf '%s/docs/handoff/dispatch-%s/phase8-passed.flag' "${PROJECT_ROOT}" "$1"
}

# rc0: this lane's stream positively ends at the provider turn cap and has no completion
# sentinel, so it is cut off (not complete). Only the final complete JSON record from the
# last 64KiB is inspected: streams can be megabytes, and malformed/truncated/missing input
# deliberately returns rc1 so ordinary conservative evidence handling still blocks. The last
# nonblank line itself must parse; do not skip a malformed tail and mistake an older event for
# the stream's terminal record.
_dispatch_maxturns_cutoff() {  # <sig8> <created_epoch> -> rc0 cutoff; rc1 not proven
  local sig8="$1" created="$2" stream mtime
  [[ -f "$(_dispatch_completion_sentinel "${sig8}")" ]] && return 1
  [[ "${created}" =~ ^[0-9]+$ ]] || return 1
  stream="${PROJECT_ROOT}/docs/handoff/dispatch-${sig8}/developer.stream.jsonl"
  [[ -f "${stream}" && -r "${stream}" ]] || return 1
  mtime="$(stat -f %m "${stream}" 2>/dev/null || stat -c %Y "${stream}" 2>/dev/null)" || return 1
  [[ "${mtime}" =~ ^[0-9]+$ ]] && (( mtime >= created )) || return 1
  tail -c 65536 "${stream}" 2>/dev/null | python3 -c '
import json, sys
lines = [raw for raw in sys.stdin.buffer.read().splitlines() if raw.strip()]
if not lines:
    raise SystemExit(1)
try:
    event = json.loads(lines[-1])
except (UnicodeDecodeError, json.JSONDecodeError):
    raise SystemExit(1)
terminal = event.get("terminal_reason") == "max_turns"
subtype = event.get("subtype") == "error_max_turns"
raise SystemExit(0 if terminal or subtype else 1)
' 2>/dev/null
}

# STOP-GATE-CHECKPOINT-DEDUP-01: the machine-written checkpoint COMMIT
# (pc_stop_gate_autocommit, leadv2-dispatch-product-close.sh) as the OTHER proof of
# cutoff -- same freshness contract as the note (mtime >= created), but keyed off the
# commit's own committer timestamp, not a file mtime. Resolves the lane worktree via
# LANE_WORKTREE_BIN (same seam _resolve_pinned_placement / spawn_product_close already
# use), so a missing/renamed/unreadable worktree fails closed (rc1) rather than guessing
# a path. On rc0, leaves the freeing commit's short sha in _DISPATCH_CHECKPOINT_SHA for
# the caller's journal line; callers MUST reset that var before invoking (this function
# does so itself, guarding against a stale value leaking from a prior failed row).
#
# SD-CHECKPOINT-CUTOFF-LANEID-01 (2026-08-21): the lane worktree is created keyed on
# ${founder_task_id:-sig8} (leadv2-dispatch-code.sh:4353's `ensure` call, same key
# leadv2-lane-worktree.sh's `path-of` needs) -- founder_task_id is a fanout/lane id
# (e.g. `14bd0c10`), NOT the mission's task_sig. A lane dispatched with a founder task id
# therefore lives at `.claude/worktrees/<founder_task_id>`, never at
# `.claude/worktrees/<sig8>`. This function used to resolve ONLY by sig8, so it silently
# `path-of`'d nothing for every founder-task-bound lane (the common fanout/lane shape) and
# fell straight to `return 1` (fail-closed) -- a live checkpoint commit was on disk but
# unreachable, and the row never got freed. Verified live: lane worktree
# `.claude/worktrees/14bd0c10` held the STOP-GATE checkpoint commit; `path-of 21f644a1`
# (its task_sig) resolved to nothing. Fix: try the row's own task_id (the founder/lane id,
# now threaded in from the ledger row via _dispatch_row_fields) FIRST, falling back to sig8
# only when task_id is empty/unresolvable -- byte-identical to today for any row that has
# no task_id (dispatch_reserve only ever writes DISPATCH_FOUNDER_TASK_ID there, so a plain
# dispatch-only mission's row still resolves by sig8 exactly as before).
_DISPATCH_CHECKPOINT_SHA=""
_dispatch_checkpoint_commit_cutoff() {  # <sig8> <created_epoch> [<lane_task_id>] -> rc0 cutoff; rc1 not
  local sig8="$1" created="$2" lane_task_id="${3:-}" lane="" sha ctime
  _DISPATCH_CHECKPOINT_SHA=""
  [[ "${created}" =~ ^[0-9]+$ ]] || return 1
  [[ -n "${LANE_WORKTREE_BIN:-}" && -f "${LANE_WORKTREE_BIN}" ]] || return 1
  if [[ -n "${lane_task_id}" && "${lane_task_id}" != "${sig8}" ]]; then
    lane="$(LEADV2_PROJECT_ROOT="${PROJECT_ROOT}" bash "${LANE_WORKTREE_BIN}" path-of "${lane_task_id}" 2>/dev/null)"
  fi
  if [[ -z "${lane}" ]]; then
    lane="$(LEADV2_PROJECT_ROOT="${PROJECT_ROOT}" bash "${LANE_WORKTREE_BIN}" path-of "${sig8}" 2>/dev/null)"
  fi
  [[ -n "${lane}" && -d "${lane}" ]] || return 1
  [[ -d "${lane}/.git" || -f "${lane}/.git" ]] || return 1
  # Newest matching commit first (log is reverse-chronological by default); a fixed-
  # string grep on the exact message pc_stop_gate_autocommit writes -- never a loose
  # pattern that could match an unrelated wip() commit.
  sha="$(git -C "${lane}" log -1 --fixed-strings \
    --grep="wip(${sig8}): auto-checkpoint on worker exit (STOP-GATE)" \
    --format=%H -- . 2>/dev/null)" || return 1
  [[ -n "${sha}" ]] || return 1
  ctime="$(git -C "${lane}" log -1 --format=%ct "${sha}" 2>/dev/null)" || return 1
  [[ "${ctime}" =~ ^[0-9]+$ ]] || return 1
  (( ctime >= created )) || return 1
  _DISPATCH_CHECKPOINT_SHA="${sha:0:8}"
  return 0
}

# rc0: this row is checkpointed-and-cut-off and never recovered -- free it. rc1: not (no
# checkpoint marker/commit, both predate this reservation, or the mission's own completion
# sentinel says it finished -- see doc block item 9 for why the sentinel check comes first).
_dispatch_checkpointed_cutoff() {  # <sig8> <created_epoch> [<lane_task_id>] -> rc0 cutoff; rc1 not
  local sig8="$1" created="$2" lane_task_id="${3:-}" marker mtime
  [[ -f "$(_dispatch_completion_sentinel "${sig8}")" ]] && return 1
  [[ "${created}" =~ ^[0-9]+$ ]] || created=0
  marker="$(_dispatch_checkpoint_marker "${sig8}")"
  if [[ -f "${marker}" ]]; then
    mtime="$(stat -f %m "${marker}" 2>/dev/null || stat -c %Y "${marker}" 2>/dev/null)"
    if [[ "${mtime}" =~ ^[0-9]+$ ]] && (( mtime >= created )); then
      return 0
    fi
  fi
  # Model-written note absent or stale -- fall back to the machine-written STOP-GATE
  # checkpoint commit (OR, not a replacement: either proof frees the row).
  _dispatch_checkpoint_commit_cutoff "${sig8}" "${created}" "${lane_task_id}"
}

# DEDUP-REFUSED-RETRY-01: reads the terminal-ledger's LAST recorded word for <sig8> (see
# leadv2-dispatch-ledger.sh's dispatch_terminal_last_state doc comment). ALWAYS a
# subprocess -- never sourced (LEDGER_BIN's own doc comment above: sourcing collided with
# this script's fd-9 flock). Fail-open to "" (empty) on TERMINAL_LEDGER=0 or a missing/
# broken ledger binary -- the caller treats "" as "no terminal row" and falls through to
# the pre-existing evidence-based check, so a ledger outage can only ever cost the (safe,
# fail-closed) OLD behaviour back, never a spurious free.
_dispatch_terminal_ledger_state() {
  local sig8="$1"
  [[ "${TERMINAL_LEDGER}" == "1" && -f "${LEDGER_BIN}" ]] || { printf ''; return 0; }
  PROJECT_ROOT="${LEDGER_REPO_ROOT}" LEADV2_PROJECT_ROOT="${LEDGER_REPO_ROOT}" \
    bash "${LEDGER_BIN}" state "${sig8}" 2>/dev/null 9>&- || printf ''
}

# LANE-OBSERVABILITY-02 change 2: same read-only subprocess shape as
# _dispatch_terminal_ledger_state above, but for the LAST row's `cause` — the
# prepass invalidation gate needs it to recognise a census/prepass refusal.
# Fail-open to "" on every error (a ledger outage must never invalidate a
# valid cached prepass, only ever cost the safe old behaviour).
_dispatch_terminal_ledger_cause() {
  local sig8="$1"
  [[ "${TERMINAL_LEDGER}" == "1" && -f "${LEDGER_BIN}" ]] || { printf ''; return 0; }
  PROJECT_ROOT="${LEDGER_REPO_ROOT}" LEADV2_PROJECT_ROOT="${LEDGER_REPO_ROOT}" \
    bash "${LEDGER_BIN}" cause "${sig8}" 2>/dev/null 9>&- || printf ''
}

# rc0: this row still blocks (worker alive, liveness undetermined, terminal-ledger says
# landed, or finished-with-evidence and no terminal row overrides it). rc1: this row no
# longer blocks (terminal-ledger says refused or dead, OR worker finished AND left no
# evidence -- the mission's failure mode: "returned status=completed and produced nothing"
# -- OR was checkpointed-and-cut-off at the turn cap and never recovered).
#
# DEDUP-REFUSED-RETRY-01: a scope-gate (or any pre-verdict) refusal writes terminal=refused
# to the terminal ledger via dispatch-code.sh's own _dl_note before the worker's process
# exits -- but by the time a LATER dispatch attempt re-checks this sig8, worker liveness
# has already resolved to "dead" (the process is long gone), and the refused lane's own
# worktree/mission/handoff files can still satisfy _dispatch_evidence_exists (it looks for
# ARTIFACTS, not a verdict) -- so the OLD dead-branch fell through to the evidence check and
# wrongly kept blocking a row the ledger itself had already recorded as refused. A refused
# row never reached a verdict, so there is no evidence to protect -- it must free
# unconditionally. terminal=dead (a SWEEP-recorded outcome, not to be confused with the
# `liveness` value of the same name a few lines up) is likewise a recorded, no-further-
# recovery outcome and must free the same way. terminal=landed is the opposite case (real
# work merged) and must keep blocking even though liveness is independently dead.
# Deliberately checked ONLY inside the `dead` liveness branch (alive/unknown never reach
# here -- "Alive or unknown still blocks" is untouched) and ONLY as an ADDITIONAL branch
# ahead of the pre-existing evidence check -- when there is NO terminal row (state == ""),
# execution falls through unchanged to _dispatch_evidence_exists, so the dead+evidence
# protection for a finished-but-unclosed round (no terminal row at all) is byte-identical
# to before this change.
_dispatch_outcome_blocks() {  # <arm> <handle> <created_epoch> <sig8> [<lane_task_id>] -> rc0 blocks; rc1 free
  local arm="$1" handle="$2" created="$3" sig8="$4" lane_task_id="${5:-}" liveness
  liveness="$(_dispatch_worker_liveness "${arm}" "${handle}")"
  case "${liveness}" in
    dead)
      if [[ "${EVIDENCE_ATTRIBUTION}" == "1" ]] && _dispatch_maxturns_cutoff "${sig8}" "${created}"; then
        emit decision "dispatch_reclaimed task=${sig8} arm=${arm} handle=${handle} reason=maxturns_cutoff"
        return 1
      fi
      if [[ "${CHECKPOINT_CUTOFF}" == "1" ]] && _dispatch_checkpointed_cutoff "${sig8}" "${created}" "${lane_task_id}"; then
        if [[ -n "${_DISPATCH_CHECKPOINT_SHA:-}" ]]; then
          log "dispatch_reclaimed task=${sig8} arm=${arm} handle=${handle} reason=checkpointed_cutoff commit=${_DISPATCH_CHECKPOINT_SHA}"
        else
          log "dispatch_reclaimed task=${sig8} arm=${arm} handle=${handle} reason=checkpointed_cutoff"
        fi
        return 1
      fi
      local _term_state
      _term_state="$(_dispatch_terminal_ledger_state "${sig8}")"
      case "${_term_state}" in
        refused|dead)
          emit decision "dispatch_reclaimed task=${sig8} arm=${arm} handle=${handle} reason=terminal_${_term_state}"
          return 1
          ;;
        landed)
          return 0
          ;;
      esac
      if _dispatch_evidence_exists "${created}" "${sig8}"; then
        return 0
      fi
      emit decision "dispatch_reclaimed task=${sig8} arm=${arm} handle=${handle} reason=unattributed_empty"
      return 1
      ;;
    *) return 0 ;;   # alive or unknown -- never free a live or unprovable task
  esac
}

# OUTSIDE any lock (see doc block item 8 PERFORMANCE note): walks every row for <sig>. A row
# that unconditionally blocks (pending-and-fresh, or confirmed-and-fresh whose outcome is
# alive/unknown/finished-with-evidence) makes the whole sig blocked -- rc0, nothing printed.
# A confirmed-and-fresh row that resolves to finished-with-no-evidence does NOT block; its
# token is echoed on stdout (space-separated, one call may accumulate several) so the
# caller's short in-lock re-check can exclude EXACTLY that row by identity without re-running
# the slow checks that already decided it -- never a blanket sig-level bypass.
_dispatch_sig_blocked() {  # <ledger_file> <sig> <now_epoch> -> rc0 blocked; rc1 free (stdout: reclaimed tokens)
  local f="$1" sig="$2" now="$3"
  [[ -f "${f}" ]] || return 1
  local needle="\"task_sig\":\"${sig}\"" line fields state created arm handle token row_task_id age sig8 reclaimed=""
  sig8="${sig:0:8}"
  while IFS= read -r line; do
    [[ -n "${line}" && "${line}" == *"${needle}"* ]] || continue
    fields="$(_dispatch_row_fields "${line}")"
    IFS=$'\t' read -r state created arm handle token row_task_id <<< "${fields}"
    [[ "${created}" =~ ^[0-9]+$ ]] || created=0
    age=$(( now - created ))
    if [[ "${state}" == "pending" && ${age} -lt ${PENDING_TTL} ]]; then
      printf '%s' "${reclaimed}"; return 0
    fi
    if [[ "${state}" == "confirmed" && ${age} -lt ${CONFIRMED_TTL} ]]; then
      if [[ "${OUTCOME_LEDGER}" != "1" ]]; then
        printf '%s' "${reclaimed}"; return 0
      fi
      if _dispatch_outcome_blocks "${arm}" "${handle}" "${created}" "${sig8}" "${row_task_id}"; then
        printf '%s' "${reclaimed}"; return 0
      fi
      reclaimed="${reclaimed}${reclaimed:+ }${token}"
    fi
  done < "${f}"
  printf '%s' "${reclaimed}"
  return 1
}

# Pure/local (awk, instant -- no external calls): the ORIGINAL fix-pass-4 semantics, blocked
# if ANY row for <sig> is confirmed-and-fresh or pending-and-fresh, EXCEPT a row whose token
# is in <exclude_tokens> (space-separated). This is the short in-lock race-guard run AFTER
# the slower, unlocked, outcome-aware _dispatch_sig_blocked above has already decided which
# specific rows are reclaimable -- see doc block item 8 PERFORMANCE note for why the outcome
# check itself must never run under the lock.
_dispatch_sig_blocked_fast() {  # <ledger_file> <sig> <now_epoch> <exclude_tokens> -> rc0 blocked
  local f="$1" sig="$2" now="$3" exclude="$4"
  [[ -f "${f}" ]] || return 1
  awk -v needle="\"task_sig\":\"${sig}\"" -v now="${now}" -v ptt="${PENDING_TTL}" -v ctt="${CONFIRMED_TTL}" -v excl=" ${exclude} " '
    index($0, needle) == 0 { next }
    {
      state = ""; created = 0; token = ""
      if (match($0, /"state":"[a-z]+"/)) {
        s = substr($0, RSTART, RLENGTH); gsub(/"state":"|"/, "", s); state = s
      }
      if (match($0, /"created_epoch":[0-9]+/)) {
        c = substr($0, RSTART, RLENGTH); sub(/"created_epoch":/, "", c); created = c + 0
      }
      if (match($0, /"token":"[^"]*"/)) {
        t = substr($0, RSTART, RLENGTH); gsub(/"token":"|"/, "", t); token = t
      }
      if (index(excl, " " token " ") > 0) next
      age = now - created
      if (state == "confirmed" && age < ctt) { print "blocked"; exit }
      if (state == "pending"   && age < ptt) { print "blocked"; exit }
    }
  ' "${f}" | grep -q '^blocked$'
}

_dispatch_append_pending_locked() {  # <file> <sig> <arm> <rule> <token> <created_epoch> [task_id] [mission_path] [lane_label]
  local f="$1" sig="$2" arm="$3" rule="$4" token="$5" created="$6" ts
  # STATUS-SURFACE-R5-01 (C1c): carry a human task_id + mission_path on the
  # pending row so the status surface can show a name without falling back to
  # the handoff-dir read. Both are optional and empty when the dispatcher
  # genuinely has neither; the reader tolerates absent keys (backward/forward
  # compatible). Strip backslash + double-quote so neither can break the JSON.
  local task_id="${7:-}" mission_path="${8:-}" lane_label="${9:-}"
  task_id="${task_id//\\/}"; task_id="${task_id//\"/}"
  # SWIFTBAR-LIVE-01 round 2: clamp task_id to 64 chars so a pathological
  # --task-id cannot produce an unbounded ledger line.
  task_id="${task_id:0:64}"
  mission_path="${mission_path//\\/}"; mission_path="${mission_path//\"/}"
  # N1B F4: lane_label is a DISPLAY label (prose-derived), never an identity.
  # It gets the same sanitiser task_id does -- a prose-derived value is exactly
  # the input that needs backslash/quote stripping + length clamping. It is
  # NEVER eligible for the tasks.yaml identity lookup in the reader.
  lane_label="${lane_label//\\/}"; lane_label="${lane_label//\"/}"
  lane_label="${lane_label:0:64}"
  ts="$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date +%s)"
  printf '{"task_sig":"%s","arm":"%s","rule":"%s","repo":"%s","ts":"%s","token":"%s","state":"pending","created_epoch":%s,"task_id":"%s","mission_path":"%s","lane_label":"%s"}\n' \
    "${sig}" "${arm}" "${rule}" "$(repo_slug)" "${ts}" "${token}" "${created}" "${task_id}" "${mission_path}" "${lane_label}" >> "${f}"
}

# reserve (SHORT lock: ledger read-check + append ONLY -- milliseconds, never across spawn).
# Returns via exit code + stdout: 0 = reserved, stdout is our unique token; 2 = duplicate
# (a confirmed-and-fresh or pending-and-fresh row already claims this sig -- refuse); 3 =
# lock-wait timeout (hard error, nothing written); 1 = the ledger WRITE itself failed
# (read-only/full fs) -- hard error, caller must NOT proceed to spawn (mission: APPEND-FAIL).
dispatch_reserve() {  # <sig> <arm> <rule> -> stdout: token (rc0 only)
  local sig="$1" arm="$2" rule="$3" lockf f
  f="$(dispatch_ledger_file)"; lockf="$(dispatch_lock_file)"
  mkdir -p "${DISPATCH_LEDGER_DIR}"

  # DISPATCH-OUTCOME-LEDGER-01: outcome resolution (liveness + evidence) happens in a FIRST
  # pass OUTSIDE any lock -- these are read-only external calls (status queries, git log)
  # that can be slow, and fix-pass-4 already learned the hard way that holding the per-repo
  # lock across a slow call blocks every OTHER task's dispatch too. The result is only ever
  # "which specific rows (by exact token) are proven reclaimable" -- the lock still governs
  # every actual write.
  local now reclaimed="" outer_rc=0
  now="$(_now_epoch)"
  if [[ "${ENFORCE}" == "1" ]]; then
    reclaimed="$(_dispatch_sig_blocked "${f}" "${sig}" "${now}")"; outer_rc=$?
    [[ ${outer_rc} -eq 0 ]] && return 2
  fi

  (
    lv2_lock_wait "${lockf}" 10 || exit 3
    local now2 token
    now2="$(_now_epoch)"
    if [[ "${ENFORCE}" == "1" ]] && _dispatch_sig_blocked_fast "${f}" "${sig}" "${now2}" "${reclaimed}"; then
      exit 2
    fi
    token="$(_dispatch_new_token)"
    if ! _dispatch_append_pending_locked "${f}" "${sig}" "${arm}" "${rule}" "${token}" "${now2}" \
      "${DISPATCH_FOUNDER_TASK_ID:-}" "${DISPATCH_MISSION_PATH:-}" "${DISPATCH_LANE_NAME:-}"; then
      exit 1
    fi
    printf '%s' "${token}"
    exit 0
  ) 9>"${lockf}"
}

# confirm/abort (SHORT lock each, re-acquired AFTER spawn has already run outside any lock).
# Both match by the EXACT unique token -- never a blanket task_sig filter -- so a concurrent
# caller's own in-flight or already-confirmed row for the SAME sig is never collaterally
# touched (mission: "SAME-SECOND UNIQUE ... each rollback removes only its own row").
_dispatch_confirm_locked() {  # <file> <token> <handle> -> rc0 confirmed; rc1 write failed; rc2 row not found
  local f="$1" token="$2" handle="${3:-}" tmp found=0 ln new
  [[ -f "${f}" ]] || return 2
  tmp="$(mktemp "${f}.confirm.XXXXXX")" || return 1
  while IFS= read -r ln || [[ -n "${ln}" ]]; do
    if [[ "${ln}" == *"\"token\":\"${token}\""* && "${ln}" == *'"state":"pending"'* ]]; then
      new="${ln/\"state\":\"pending\"/\"state\":\"confirmed\"}"
      # DISPATCH-OUTCOME-LEDGER-01: persist the launcher handle on the row so a later
      # dispatch of the SAME sig can resolve this row's liveness/evidence outcome (doc
      # block item 8). Only glm/sonnet/codex confirms carry a handle; opus never spawns.
      if [[ -n "${handle}" ]]; then
        new="${new%\}}"
        new="${new},\"handle\":\"${handle}\"}"
      fi
      printf '%s\n' "${new}" >> "${tmp}"
      found=1
    else
      printf '%s\n' "${ln}" >> "${tmp}"
    fi
  done < "${f}"
  if ! mv "${tmp}" "${f}"; then
    rm -f "${tmp}" 2>/dev/null
    return 1
  fi
  [[ ${found} -eq 1 ]] && return 0 || return 2
}
_dispatch_abort_locked() {  # <file> <token> -> rc0 removed (or already absent); rc1 write failed
  local f="$1" token="$2" tmp
  [[ -f "${f}" ]] || return 0
  tmp="$(mktemp "${f}.abort.XXXXXX")" || return 1
  # grep -v on a file whose only row matches yields empty output + rc=1 -- not checked, the
  # empty tmp file is still the correct result; only the mv rc below determines success.
  grep -vF "\"token\":\"${token}\"" "${f}" > "${tmp}" 2>/dev/null
  if ! mv "${tmp}" "${f}"; then
    rm -f "${tmp}" 2>/dev/null
    return 1
  fi
  return 0
}
dispatch_confirm() {  # <token> <handle> -> rc0 confirmed; rc1 write-fail(hard); rc2 not-found; rc3 lock-timeout
  local token="$1" handle="${2:-}" f lockf
  f="$(dispatch_ledger_file)"; lockf="$(dispatch_lock_file)"
  ( lv2_lock_wait "${lockf}" 10 || exit 3
    _dispatch_confirm_locked "${f}" "${token}" "${handle}"
  ) 9>"${lockf}"
}
dispatch_abort() {  # <token> -> rc0 removed/absent; rc1 write-fail(hard); rc3 lock-timeout
  local token="$1" f lockf
  f="$(dispatch_ledger_file)"; lockf="$(dispatch_lock_file)"
  ( lv2_lock_wait "${lockf}" 10 || exit 3
    _dispatch_abort_locked "${f}" "${token}"
  ) 9>"${lockf}"
}

# An interruption after reserve but before confirm used to leave a PENDING claim until
# its TTL elapsed.  Normal failure paths still finalize explicitly; this is only the
# process-lifetime safety net for signals/unexpected exits in that small window.
# W-1a §3.1: reap an orphaned lane worktree when this dispatch produced NO live worker.
# Mirrors leadv2-fanout-lane-launcher.sh's _reap_lane_worktree_if_unused (its rc 2/3/*
# branches) -- that launcher reap only covers the FANOUT lineage. The direct-dispatch path
# (backlog pump, supervisor pump) reaches THIS EXIT trap instead, and without this it would
# leak a worktree per dead lane (acceptance item 3). Non-destructive by construction: a dirty
# tree, unmerged commits, or a merge-blocker.flag keep the worktree (cleanup.sh --name
# refuses without --force, and this never passes --force). A successful spawn set
# _DISPATCH_WORKER_LIVE=1 and is explicitly skipped so the async worker's tree survives.
# Keyed on ${founder_task_id:-sig8} -- the SAME key `ensure` (cmd_resolve) and the close
# gate's path-of fallback use. Best-effort: `|| true` throughout, never fails the exit path.
_reap_lane_worktree_if_unused() {
  [[ "${_DISPATCH_WORKER_LIVE:-0}" != "1" ]] || return 0
  local _wt="${WORK_ROOT:-}"
  [[ -n "${_wt}" && -d "${_wt}" && "${_wt}" != "${PROJECT_ROOT:-}" ]] || return 0
  local _key="${founder_task_id:-${sig8:-}}"
  [[ -n "${_key}" ]] || return 0
  [[ -z "$(git -C "${_wt}" status --porcelain 2>/dev/null)" ]] || return 0
  local _upstream _ahead
  _upstream="$(git -C "${_wt}" rev-parse --abbrev-ref --symbolic-full-name '@{upstream}' 2>/dev/null || printf 'main')"
  _ahead="$(git -C "${_wt}" rev-list --count "${_upstream}.." 2>/dev/null || printf '0')"
  [[ "${_ahead}" == "0" ]] || return 0
  bash "${SCRIPT_DIR}/leadv2-worktree-cleanup.sh" --name "${_key}" >/dev/null 2>&1 || true
}
cleanup_pending_dispatch() {
  # PREPASS-PROVIDER-FALLBACK-01-R5 H3: ONE disarmable EXIT trap owns the
  # pre-registered lane-row release for every terminal exit of this process.
  # cmd_resolve arms it at registration (DISPATCH_SLOT_REG_ID); a confirmed
  # worker spawn hands the row over and a post-spawn ambiguity disarms it (the
  # DISPATCH_SLOT_REG_ID="" sites in cmd_resolve). Every proven no-worker exit
  # -- phase-precondition refusal, prepass park, lane-shape refusal, router-v2
  # refusal, duplicate signature, ledger failure, all-arms exhaustion/refusal,
  # dry-run, signal death -- therefore releases the row without a per-exit
  # call site. Owner-verified inside _release_registered_lane (H2).
  if [[ -n "${DISPATCH_SLOT_REG_ID:-}" ]]; then
    declare -F lane_deregister >/dev/null 2>&1 && lane_deregister "${DISPATCH_SLOT_REG_ID}" "dispatcher_exit" >/dev/null 2>&1 || true
    _release_registered_lane "${DISPATCH_SLOT_REG_ID}" "${DISPATCH_SLOT_SIG8:-}" "exit_trap"
  fi
  # PREPASS-PROVIDER-FALLBACK-01-R9 H3: fallback creation arms this global
  # before `git worktree add`; therefore EXIT and signals after either creation
  # step dispose the temporary workspace.  The normal path disarms it only
  # after _afb_discard_workspace returns.
  if [[ -n "${ARCHITECT_FALLBACK_WORKSPACE_BASE:-}" ]]; then
    _afb_discard_workspace "${ARCHITECT_FALLBACK_WORKSPACE_BASE}"
    ARCHITECT_FALLBACK_WORKSPACE_BASE=""
  fi
  _reap_lane_worktree_if_unused
  local token="${ACTIVE_DISPATCH_TOKEN:-}"
  [[ -n "${token}" ]] || return 0
  ACTIVE_DISPATCH_TOKEN=""
  dispatch_abort "${token}" >/dev/null 2>&1 || true
}
trap cleanup_pending_dispatch EXIT
_dispatch_signal_exit() { # <signal-number> -- interrupt a foreground fallback runner first
  local signal_number="$1" runner_pid="${ARCHITECT_FALLBACK_RUNNER_PID:-}" i
  if [[ -z "${runner_pid}" && -n "${ARCHITECT_FALLBACK_RUNNER_PID_FILE:-}" && -r "${ARCHITECT_FALLBACK_RUNNER_PID_FILE}" ]]; then
    runner_pid="$(cat "${ARCHITECT_FALLBACK_RUNNER_PID_FILE}" 2>/dev/null || true)"
  fi
  if [[ -n "${runner_pid}" ]]; then
    kill -TERM "${runner_pid}" 2>/dev/null || true
    # `wait` is interruptible, unlike a foreground command substitution.  Reap
    # the bounded Python supervisor before running EXIT cleanup so it can kill
    # its provider process group and no fallback child outlives this dispatcher.
    wait "${runner_pid}" 2>/dev/null || true
    # When _architect_timed_run is inside a command substitution its Python
    # supervisor is a child of that subshell, not this trap's shell.  It cannot
    # be waited here, so verify its TERM handler has exited before workspace
    # cleanup can remove its pid file.
    for i in $(seq 1 40); do
      kill -0 "${runner_pid}" 2>/dev/null || break
      sleep 0.05
    done
    ARCHITECT_FALLBACK_RUNNER_PID=""
  fi
  exit "$((128 + signal_number))"
}
trap '_dispatch_signal_exit 2' INT
trap '_dispatch_signal_exit 15' TERM
lv2_trace_arm_exit "lane" "$@"

# ── review-ledger dedup ───────────────────────────────────────────────────────────
diff_seen() {  # <hash> -> 0 if already reviewed
  local f; f="$(review_ledger_file)"
  [[ -f "$f" ]] || return 1
  grep -qF "\"diff_hash\":\"$1\"" "$f"
}
record_review() {  # <diff_hash> <verdict> <reviewer> <run_id> [guard_token]
  local f ts guard_token="${5:-}"
  f="$(review_ledger_file)"; ts="$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date +%s)"
  mkdir -p "${REVIEW_LEDGER_DIR}"
  if [[ -n "$guard_token" ]]; then
    printf '{"diff_hash":"%s","verdict":"%s","reviewer":"%s","run_id":"%s","repo":"%s","ts":"%s","guard_token":"%s"}\n' \
      "$1" "$2" "$3" "$4" "$(repo_slug)" "$ts" "$guard_token" >> "$f"
  else
    printf '{"diff_hash":"%s","verdict":"%s","reviewer":"%s","run_id":"%s","repo":"%s","ts":"%s"}\n' \
      "$1" "$2" "$3" "$4" "$(repo_slug)" "$ts" >> "$f"
  fi
}
review_lock_file() { printf '%s/.%s.review.lock' "${REVIEW_LEDGER_DIR}" "$(repo_slug)"; }

# Same atomicity fix as atomic_dispatch_check_and_record, for the review ledger's
# diff_hash race (Finding 3/4 both name diff_hash alongside task_sig).
# B1 R3: also maintains a row-count sidecar so raw >> appends are detectable.
# B1 R4: also maintains an "adopted" marker outside the ledger dir so that
# sidecar-absent can be distinguished from "never used" vs "deleted after use".
# B1 R5: also mints a per-invocation guard token stored in the provenance dir
# (outside the ledger), checked back by _verify_artifact.  An attacker writing
# raw ledger rows must also forge the tokens file outside the ledger dir.
_review_sidecar_file() { printf '%s/%s.jsonl.rows' "${REVIEW_LEDGER_DIR}" "$(repo_slug)"; }
_review_adopted_marker() { printf '%s/code-review-provenance/%s.adopted' "${CACHE_BASE}" "$(repo_slug)"; }
_review_tokens_file() { printf '%s/code-review-provenance/%s.tokens' "${CACHE_BASE}" "$(repo_slug)"; }
_increment_review_sidecar() {
  local sidecar rows bootstrap=0
  sidecar="$(_review_sidecar_file)"
  if [[ ! -f "$sidecar" ]]; then
    # Bootstrap: seed to current line count (record_review already appended)
    rows="$(wc -l < "$(review_ledger_file)" 2>/dev/null | tr -d ' ')"
    rows="${rows:-0}"
    bootstrap=1
    # B1 R4: write the adopted marker once — outside the ledger dir so a raw
    # attacker who can write to code-review-ledger/ cannot remove it by accident.
    local _adopted_dir _adopted_file
    _adopted_file="$(_review_adopted_marker)"
    _adopted_dir="$(dirname "$_adopted_file")"
    mkdir -p "$_adopted_dir" 2>/dev/null || true
    : > "$_adopted_file" 2>/dev/null || true
  else
    rows="$(<"$sidecar")"
    rows="${rows// /}"
    rows="${rows:-0}"
  fi
  # On normal increments, +1 for the row just written.
  # On bootstrap, the wc -l already counts it.
  [[ "$bootstrap" == "0" ]] && rows=$((rows + 1))
  local tmp
  tmp="$(mktemp "${REVIEW_LEDGER_DIR}/.rows.XXXXXX")" || return 0
  printf '%d\n' "$rows" > "$tmp"
  mv -f "$tmp" "$sidecar" 2>/dev/null || true
}
atomic_review_check_and_record() {  # <diff_hash> <verdict> <reviewer> <run_id>
  local hash="$1" verdict="$2" reviewer="$3" run_id="$4" lockf
  mkdir -p "${REVIEW_LEDGER_DIR}"
  lockf="$(review_lock_file)"
  # B1 R5: mint a per-invocation guard token under flock.  The caller cannot
  # supply this — it is generated here, embedded in the ledger row, and recorded
  # in the provenance dir (outside the attacker-writable ledger dir).
  local _gt _gt_file _gt_dir
  _gt="$(head -c 16 /dev/urandom 2>/dev/null | od -An -tx1 | tr -d ' \n' || printf 'fallback%d' $$)"
  _gt_file="$(_review_tokens_file)"
  _gt_dir="$(dirname "$_gt_file")"
  mkdir -p "$_gt_dir" 2>/dev/null || true
  (
    lv2_lock_wait "${lockf}" 10 || exit 3
    if [[ "${ENFORCE}" == "1" ]] && diff_seen "${hash}"; then
      exit 2
    fi
    record_review "${hash}" "${verdict}" "${reviewer}" "${run_id}" "${_gt}"
    _increment_review_sidecar
    # R9: bind the token to the diff_hash it was minted for, so a stolen
    # token cannot vouch for a different diff's ledger row.
    printf '%s %s\n' "${hash}" "${_gt}" >> "$_gt_file" 2>/dev/null || true
    exit 0
  ) 9>"${lockf}"
}

# json-safe: strip quotes/backslashes/newlines from a free-form field (reviewer/run-id).
# shellcheck disable=SC1003  # tr -d '"\\' is correct as-is (literal quote+backslash set)
sanitize_field() { printf '%s' "$1" | tr -d '"\\' | tr '\n' ' ' | tr -cd 'A-Za-z0-9._:/-'; }

# ── PRODUCT-READINESS-GATES-01: classification + architect prepass ─────────────
# A fast path must be explicit.  Do not infer "docs" from a filename or assume a
# diagnosis is harmless merely because its prose contains no change verb: unknown means
# product and gets all three gates.
classify_product_work() { # <kind> <mission> -> product|non_product<TAB>reason
  local kind mission
  kind="$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')"
  mission="$(printf '%s' "$2" | tr '[:upper:]' '[:lower:]')"
  case "${kind}" in
    plugin|tooling|tool|docs|documentation|diagnosis|diagnostic|investigation)
      printf 'non_product\texplicit_kind_%s' "${kind}"; return ;;
  esac
  if [[ "${mission}" =~ ^[[:space:]]*(docs?-only|documentation-only|pure[[:space:]]+diagnosis|diagnosis-only|tooling-only|plugin-only) ]]; then
    printf 'non_product\texplicit_mission_fast_path'; return
  fi
  printf 'product\tconservative_default'
}

_prepass_file() { printf '%s/docs/handoff/dispatch-%s/architect-prepass.md' "${PROJECT_ROOT}" "$1"; }

# Harvest the architect's `LANE_WRITES:` declaration out of its prepass artifact.
# M7 (LANDING-BLOCKER-R2): match tolerantly -- markdown emphasis (`**LANE_WRITES:**`) or
# leading indentation must not read as "absent" (fail-closed still applies: no match at
# all -> empty, guard decides).
# L12 (LANDING-BLOCKER-R2): reject an over-broad entry rather than trusting it -- one that
# is empty/`.`/`/`, one built entirely of `*`/`/` (the whole `*`, `**`, `*/*`, `**/*`,
# `**/**` family), or a bare wildcard-free top-level segment that is an existing directory
# under WORK_ROOT (a repo-root dir name like `plugins` or `agent`). Each of those over-
# declares the whole tree and would re-mix lanes at review time exactly like no
# declaration at all.
_prepass_writes() { # <sig8> -> CSV writes or empty
  local f line entry norm
  f="$(_prepass_file "$1")"
  [[ -s "${f}" ]] || return 0
  line="$(grep -m1 -iE '^[[:space:]*_]*LANE_WRITES[*_]*:' "${f}" 2>/dev/null)" || return 0
  line="$(printf '%s' "${line}" | sed -E 's/^[[:space:]*_]*LANE_WRITES[*_]*:[[:space:]]*//I')"
  local -a raw_entries kept=()
  IFS=',' read -ra raw_entries <<< "${line}"
  for entry in "${raw_entries[@]}"; do
    entry="$(printf '%s' "${entry}" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
    [[ -z "${entry}" ]] && continue
    norm="${entry#./}"
    while [[ "${norm}" == *//* ]]; do norm="${norm//\/\//\/}"; done
    norm="${norm%/}"
    [[ -z "${norm}" || "${norm}" == "." || "${norm}" == "/" ]] && continue
    [[ -z "$(printf '%s' "${norm}" | tr -d '*/')" ]] && continue
    if [[ "${norm}" != *'*'* && "${norm}" != */* && -d "${WORK_ROOT}/${norm}" ]]; then continue; fi
    kept+=("${norm}")
  done
  (IFS=','; printf '%s' "${kept[*]:-}")
}

# REPORT-ONLY-GATE-01: harvest the mission's own `LANE_DELIVERABLE:` declaration, using
# the same tolerant matcher as _prepass_writes above (markdown emphasis / leading
# indentation must not read as "absent"). Harvested from the MISSION, never from the
# architect prepass: a report lane is a property of the founder's ask, not of a design.
# Returns the raw declaration (e.g. "report:docs/handoff/X/report.md") or empty.
_mission_deliverable() { # <mission-text> -> declaration or empty
  local line
  line="$(printf '%s' "$1" | grep -m1 -iE '^[[:space:]*_]*LANE_DELIVERABLE[*_]*:' 2>/dev/null)" || return 0
  printf '%s' "${line}" | sed -E 's/^[[:space:]*_]*LANE_DELIVERABLE[*_]*:[[:space:]]*//I'
}

# KIMI-CHANNEL-REHAB-01: only narrow, bounded implementation missions enter the
# Kimi rung. A founder's --kimi-fit override deliberately bypasses every
# heuristic. On the explicit non-product/no-prepass path, an absent write-set
# means unknown-but-small rather than broad; the char cap remains the bound.
# Sets KIMI_ADMISSION_WRITES / KIMI_ADMISSION_PREPASS / KIMI_ADMISSION_REASON
# for the decision journal.
_kimi_admissible() { # <mission> <sig8> <writes_csv> <kimi_fit> -> 0 admissible, 1 not
  local mission="$1" sig8="$2" writes_csv="$3" kimi_fit="$4"
  local max_chars="${LEADV2_KIMI_MAX_MISSION_CHARS:-2500}"
  local max_writes="${LEADV2_KIMI_MAX_WRITES:-2}"
  local prepass_file entry
  KIMI_ADMISSION_WRITES=0
  KIMI_ADMISSION_PREPASS=0
  KIMI_ADMISSION_REASON=""
  [[ "${kimi_fit}" == "1" ]] && return 0
  [[ "${max_chars}" =~ ^[0-9]+$ ]] || max_chars=2500
  [[ "${max_writes}" =~ ^[0-9]+$ ]] || max_writes=2

  prepass_file="$(_prepass_file "${sig8}")"
  [[ -f "${prepass_file}" ]] && KIMI_ADMISSION_PREPASS=1
  if [[ ${#mission} -gt ${max_chars} ]]; then
    KIMI_ADMISSION_REASON="chars_over"
    return 1
  fi

  [[ -n "${writes_csv}" ]] || writes_csv="$(_prepass_writes "${sig8}")"
  local -a entries=()
  [[ -n "${writes_csv}" ]] && IFS=',' read -r -a entries <<< "${writes_csv}"
  for entry in "${entries[@]}"; do
    entry="$(printf '%s' "${entry}" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
    [[ -n "${entry}" ]] && KIMI_ADMISSION_WRITES=$((KIMI_ADMISSION_WRITES + 1))
  done
  if [[ ${KIMI_ADMISSION_WRITES} -gt ${max_writes} ]]; then
    KIMI_ADMISSION_REASON="writes_over"
    return 1
  fi
  if [[ ${KIMI_ADMISSION_PREPASS} == "1" ]]; then
    KIMI_ADMISSION_REASON="prepass_present"
    return 1
  fi
  return 0
}

# DISPATCH-KIMI-ARM-MISMATCH-01 (2026-08-05): single source of truth for the
_apply_kimi_admission() { # <mission> <sig8> <writes_csv> <kimi_fit>; mutates candidate_arms
  local mission="$1" sig8="$2" writes_csv="$3" kimi_fit="$4" _a
  _kimi_admissible "${mission}" "${sig8}" "${writes_csv}" "${kimi_fit}" && return 0
  local -a _filtered=()
  for _a in "${candidate_arms[@]}"; do [[ "${_a}" == "kimi" ]] || _filtered+=("${_a}"); done
  candidate_arms=("${_filtered[@]}")
  emit decision "kimi_skipped reason=${KIMI_ADMISSION_REASON:-chars_over} task=${sig8} chars=${#mission} writes=${KIMI_ADMISSION_WRITES:-0} prepass=${KIMI_ADMISSION_PREPASS:-0}"
}

# _lane_writes_guard <sig8> <row_writes> <have_prepass:0|1> -> 0 ok, 1 park
# H6 (LANDING-BLOCKER-R2): one call site per architect_prepass exit path, including the
# ARCHITECT_GATE kill-switch and the provably_one_file early return -- neither may dispatch
# an undeclared, unisolated lane. Fail-closed unless REQUIRE_LANE_WRITES=1: a row-declared
# writes CSV, the prepass artifact's own LANE_WRITES: line, or an existing lane worktree
# (isolation substitutes for a declaration) each independently satisfy the guard.
_lane_writes_guard() {
  local sig8="$1" row_writes="$2" have_prepass="$3"
  [[ "${REQUIRE_LANE_WRITES}" == "1" ]] || return 0
  [[ -n "${row_writes}" ]] && return 0
  # REPORT-ONLY-GATE-01: a report lane legitimately has NO LANE_WRITES — its deliverable
  # lives under docs/handoff/ by contract, which the writes grammar itself excludes. A
  # lane that declared (and had validated, at resolve time) an exactly-parsable
  # `report:<path>` deliverable satisfies the guard through that declaration instead.
  # LANE_DELIVERABLE_DECL is set once in cmd_resolve before any prepass call site.
  # REQUIRE_LANE_WRITES semantics for diff lanes above are untouched.
  if [[ -n "${LANE_DELIVERABLE_DECL:-}" ]] && lv2_deliverable_parse "${LANE_DELIVERABLE_DECL}" >/dev/null; then
    emit decision "lane_writes task=${sig8} source=report_deliverable"
    return 0
  fi
  if [[ "${have_prepass}" == "1" ]] && [[ -n "$(_prepass_writes "${sig8}")" ]]; then return 0; fi
  local _wt=""
  # R2 (W-1 lane-worktree-isolation prepass): pin LEADV2_PROJECT_ROOT to the main
  # checkout. Unpinned, `resolve_root()` falls back to `git rev-parse --show-toplevel`
  # of cwd -- inside a lane worktree that resolves to the WORKTREE itself, so
  # lane_dir() computes <worktree>/.claude/worktrees (a nested-worktree path that never
  # exists) and path-of silently returns empty. The other two call sites
  # (leadv2-fanout-lane-launcher.sh:366, leadv2-dispatch-product-close.sh:386) already
  # pin this; this was the one that didn't.
  [[ -n "${founder_task_id:-}" ]] && _wt="$(LEADV2_PROJECT_ROOT="${PROJECT_ROOT}" bash "${LANE_WORKTREE_BIN}" path-of "${founder_task_id}" 2>/dev/null)"
  [[ -n "${_wt}" ]] && return 0
  ARCHITECT_PREPASS_REASON="no_lane_writes"
  emit decision "architect_prepass task=${sig8} status=failed reason=no_lane_writes"
  return 1
}

# _acceptance_guard <sig8> <design_file> -> 0 ok, 1 park
# RED-FIRST-GATE-01 R2: refuses a design whose acceptance is missing, not one
# of the five surface types, or reads as an internal contract (the exact
# phrasing skills/leadv2-plan/SKILL.md used to mandate, and the root cause of
# tautological review). Heuristic content scan of the prepass artifact itself
# -- this dispatch flow has no context.yaml to run leadv2-acceptance-shape.sh
# validate against; the full leadv2-plan pipeline (Phase 2) is the path that
# writes context.yaml and runs the real validator.
_acceptance_guard() {
  local sig8="$1" design_file="$2"
  [[ "${REQUIRE_ACCEPTANCE}" == "1" ]] || return 0
  [[ -f "${design_file}" ]] || return 0
  if grep -q '^acceptance:' "${design_file}" \
     && grep -qE '^[[:space:]]*surface:[[:space:]]*(rendered_line|prod_db_row|log_line|http_response|file_artifact)[[:space:]]*$' "${design_file}" \
     && grep -qE '^[[:space:]]*observable:' "${design_file}" \
     && grep -qE '^[[:space:]]*authored_at:' "${design_file}" \
     && ! grep -qiE '^[[:space:]]*observable:.*(function |returns |exit code|variable|is set to)' "${design_file}"; then
    return 0
  fi
  ARCHITECT_PREPASS_REASON="no_acceptance_block"
  emit decision "architect_prepass task=${sig8} status=failed reason=no_acceptance_block"
  return 1
}

# _admission_classify <mission> <sig> <sig8> <explicit-class> <flagged 0|1>
# PHASE-DISCIPLINE-01 D1/D2 (steps 1-2). Deterministic TaskEstimate->class map
# over the ALREADY-AVAILABLE judge (leadv2-task-judge.sh, haiku + code-only
# fallback + sig8 cache — never a new classifier subsystem). Sets globals:
#   ADMISSION_CLASS  Light|Standard|Heavy
#   ADMISSION_ROUTE  dispatch (Light) | phases (Standard/Heavy)
#   ADMISSION_SOURCE judge|fallback|flag|classifier_error
#   ADMISSION_WORK_KIND  build|review|diagnose|docs ("" on classifier_error)
#   DISPATCH_FREEPOOL_ROLE  D6 projection of work_kind ("" = don't export)
# Persists the admission receipt (task id + mission digest bound) and journals
# `task_class=<c> route=<r> source=<s>` EXACTLY ONCE per intake (a receipt
# already on disk means this mission was admitted before — no second line).
# Classifier failure NEVER falls open to bare dispatch: Standard/phases,
# source=classifier_error.
_admission_classify() {
  local mission="$1" sig="$2" sig8="$3" explicit="$4" flagged="$5"
  ADMISSION_CLASS="Standard"; ADMISSION_ROUTE="phases"
  ADMISSION_SOURCE="classifier_error"; ADMISSION_WORK_KIND=""
  DISPATCH_FREEPOOL_ROLE=""
  local receipt_task_id="${founder_task_id:-dispatch-${sig8}}"
  local existing
  existing="$(leadv2_admission_read_receipt "${PROJECT_ROOT}" "${sig8}" 2>/dev/null || true)"
  if [[ -n "${existing}" ]]; then
    local r_cls r_route r_src r_wk r_digest
    IFS=$'\t' read -r r_cls r_route r_src r_wk r_digest _ <<<"${existing}"
    if [[ "${r_digest}" == "${sig}" ]]; then
      # Same mission digest: this is a re-entry (e.g. Phase-4 spawn from the
      # full cycle), not a new intake — reuse the receipt, no second journal
      # line, and the guard below decides admission from the phase records.
      ADMISSION_CLASS="${r_cls}"; ADMISSION_ROUTE="${r_route}"
      ADMISSION_SOURCE="${r_src}"; ADMISSION_WORK_KIND="${r_wk}"
      DISPATCH_FREEPOOL_ROLE="$(leadv2_admission_freepool_role "${r_wk}")"
      return 0
    fi
    # sig8 collision with a different digest: refuse to trust it, journal loud.
    emit decision "admission_receipt_mismatch task=${sig8} receipt_digest=${r_digest}"
  fi
  local mfile estimate pair
  mfile="$(mktemp "${TMPDIR:-/tmp}/leadv2-admission.XXXXXX")" || return 0
  printf '%s' "${mission}" > "${mfile}"
  estimate="$(PROJECT_ROOT="${PROJECT_ROOT}" bash "${TASK_JUDGE_BIN}" \
    --mission-file "${mfile}" --task-id "dispatch-${sig8}" 2>/dev/null)"
  local jrc=$?
  rm -f "${mfile}" 2>/dev/null || true
  pair=""
  if [[ ${jrc} -eq 0 && -n "${estimate}" ]]; then
    pair="$(leadv2_admission_class "${explicit}" "${flagged}" "${estimate}")"
  fi
  if [[ -n "${pair}" ]]; then
    IFS=$'\t' read -r ADMISSION_CLASS ADMISSION_SOURCE <<<"${pair}"
    ADMISSION_WORK_KIND="$(printf '%s' "${estimate}" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("work_kind",""))' 2>/dev/null || true)"
  else
    # task-judge failed outright (missing binary, rc!=0, unparseable): the
    # conservative class is Standard -> phases, never bare dispatch.
    ADMISSION_CLASS="Standard"; ADMISSION_SOURCE="classifier_error"; ADMISSION_WORK_KIND=""
  fi
  case "${ADMISSION_CLASS}" in
    Standard|Heavy|Strategic) ADMISSION_ROUTE="phases" ;;
    *)                        ADMISSION_CLASS="Light"; ADMISSION_ROUTE="dispatch" ;;
  esac
  DISPATCH_FREEPOOL_ROLE="$(leadv2_admission_freepool_role "${ADMISSION_WORK_KIND}")"
  leadv2_admission_write_receipt "${PROJECT_ROOT}" "${sig8}" "${receipt_task_id}" \
    "${sig}" "${ADMISSION_CLASS}" "${ADMISSION_ROUTE}" "${ADMISSION_SOURCE}" \
    "${ADMISSION_WORK_KIND:-unknown}" 2>/dev/null \
    || emit decision "admission_receipt_write_failed task=${sig8}"
  emit decision "task_class=${ADMISSION_CLASS} route=${ADMISSION_ROUTE} source=${ADMISSION_SOURCE} task=${sig8}"
  return 0
}

# _phase_precondition_guard <sig8> <class> <writes> [waiver-args...] -> 0 proceed, 1 refuse
# PHASES-ARE-THE-ONLY-PATH-01: sits at the same structural slot as _lane_writes_guard/
# _acceptance_guard, after arg validation, before any spawn side effect and before
# _stamp_active_phase prepass. Exit code 4 from phase-record.sh (config error / refused
# waiver) ALWAYS refuses in every mode including 0 — a malformed override is a
# configuration error, not a phase gap.
# PHASE-DISCIPLINE-01 D3: with LEADV2_REQUIRE_PHASES unset, the effective mode is
# enforce (pre-build scope: classify/plan/gate1 only) for class >= Standard and
# warn for Light. Explicit env values keep their exact prior semantics; =0 stays
# the byte-identical kill switch (first return below).
# Same-task Phase-4 re-entry: leadv2-gate1-prompt.sh records classify/plan/gate1
# under the admission receipt's sig8 (task_id join key), so the assert below
# admits a Phase-4 spawn from an approved full cycle — never a foreign task's.
_phase_precondition_guard() {
  # B2: mode 0 is the documented rollback and the emergency kill switch. It must be
  # byte-identical to pre-C4 behaviour: no subprocess, no journal event, no refusal for
  # ANY reason including a malformed phases.yaml or a refused waiver. Round 4 removed
  # this return and made `=0` able to refuse on rc 4 — that is not a kill switch.
  [[ "${REQUIRE_PHASES}" == "0" ]] && return 0
  local sig8="$1" cls="$2" writes="${3:-}"
  shift 3 2>/dev/null || shift $# 2>/dev/null || true
  local -a waiver_args=()
  while [[ $# -gt 0 ]]; do
    waiver_args+=("$1"); shift
  done

  local mode="${REQUIRE_PHASES}"
  # PHASE-DISCIPLINE-01 D3: env unset -> enforce (pre-build scope) for
  # class >= Standard; Light keeps the historical warn default. Explicit env
  # values (0/warn/1) keep their exact pre-flip semantics + full scope.
  local scope="full"
  if [[ "${REQUIRE_PHASES_ENV_SET:-0}" != "1" ]]; then
    case "$cls" in
      Standard|Heavy|Strategic)
        mode="1"
        scope="pre-build"
        ;;
      *)
        mode="warn"
        ;;
    esac
  fi
  if [[ "$mode" != "warn" && "$mode" != "1" && "$mode" != "0" ]]; then
    emit decision "phase_precondition_badmode value=${mode}"
    mode="warn"
  fi
  # PHASE-DISCIPLINE-01: cmd_resolve sets PHASE_GUARD_SCOPE=pre-build when the
  # admission receipt says route=phases (a Phase-4 re-entry needs only the
  # pre-build phases satisfied, not the whole cycle it is IN THE MIDDLE of).
  [[ "${PHASE_GUARD_SCOPE:-full}" == "pre-build" ]] && scope="pre-build"

  # `assert` defaults to full completion and deliberately has no --full flag.
  # Passing only --pre-build preserves warn-mode's historic journal-and-proceed
  # behaviour and leaves Light dispatches unaffected.
  local assert_out assert_rc
  local -a assert_args
  assert_args=(assert "${sig8}" --class "${cls}")
  [[ "${scope}" == "pre-build" ]] && assert_args+=(--pre-build)
  [[ -n "${writes}" ]] && assert_args+=(--writes "${writes}")
  assert_args+=("${waiver_args[@]}")
  assert_out="$(bash "${PHASE_RECORD_BIN}" "${assert_args[@]}" 2>&1)" || assert_rc=$?
  assert_rc="${assert_rc:-0}"

  # Same-task Phase-4 re-entry bridge: leadv2-gate1-prompt.sh, on accept,
  # records classify/plan/gate1 under the admission receipt's sig8 (the
  # receipt's task_id field is the join key — a foreign task's records can
  # never satisfy this). Those records are exactly what the assert above
  # reads, so a Phase-4 re-entry from an approved full cycle passes while a
  # cold Standard dispatch without them is refused.

  case "$assert_rc" in
    0)
      return 0
      ;;
    3)
      local missing_csv="${assert_out#missing=}"
      if [[ "$mode" == "1" ]]; then
        emit decision "phase_precondition_refused task=${sig8} class=${cls} missing=${missing_csv} mode=1"
        log_err "dispatch refused: missing mandatory phases: ${missing_csv}"
        local mp
        for mp in $(printf '%s' "${missing_csv}" | tr ',' ' '); do
          log_err "  remedy: ${PHASE_RECORD_BIN} record ${sig8} ${mp} --artifact <path>"
        done
        return 1
      else
        # mode 0 or warn: missing phases do not block
        [[ "$mode" == "warn" ]] \
          && emit decision "phase_precondition_warn task=${sig8} class=${cls} missing=${missing_csv} mode=warn"
        return 0
      fi
      ;;
    4)
      # Config error / refused waiver — always refuse in modes warn and 1.
      emit decision "phase_precondition_config_error task=${sig8} detail=${assert_out}"
      log_err "phase precondition config error: ${assert_out}"
      return 1
      ;;
    *)
      # B4: unexpected exit code (e.g. python3 missing → rc=127, disk-full
      # mktemp, unbound-variable abort).  In enforce mode this refuses (must
      # say WHY).  In warn mode it must journal a distinct line and PROCEED —
      # the "warn" contract is that infra trouble never silently becomes a
      # hard repo-wide refusal.
      if [[ "$mode" == "1" ]]; then
        emit decision "phase_precondition_refused task=${sig8} class=${cls} reason=unexpected_rc value=${assert_rc}"
        log_err "phase precondition: unexpected exit ${assert_rc}: ${assert_out}"
        return 1
      else
        emit decision "phase_precondition_warn task=${sig8} class=${cls} reason=unexpected_rc value=${assert_rc} mode=${mode}"
        log_err "phase precondition: unexpected exit ${assert_rc} (proceeding in ${mode} mode): ${assert_out}"
        return 0
      fi
      ;;
  esac
}

# ── PREPASS-PROVIDER-FALLBACK-01 §1: truthful architect failure classes ─────────
# Live evidence, dispatches 17309830 and 321ade3a: both architect runs wrote
# stream-json ending in "error":"authentication_failed" (text: "OAuth session
# expired and could not be refreshed") into their handoff dir, yet the dispatcher
# surfaced only opaque failed_rc_1 and parked. Classify from the launcher's
# captured output AND the handoff dir's own stream files -- the artifact, not
# stdout, is where the provider's real error lands (same lesson as
# PREPASS-READS-ARTIFACT-01 above). stdout: "<class>" or "<class>TAB<bounded
# detail>"; never empty. rc 124 is handled by the caller (timeout), not here.
# PREPASS-PROVIDER-FALLBACK-01-R5 (Codex review H4): each decision-driving
# pattern set carries its evidence inline.
#   AUTH — live artifact verified on disk 2026-08-24:
#     docs/handoff/dispatch-17309830-architect/architect.stream.jsonl (final
#     line) = {"...","text":"Failed to authenticate: OAuth session expired and
#     could not be refreshed","error":"authentication_failed",
#     "is_api_error_message":true}; dispatch-321ade3a-architect identical
#     shape. UNVERIFIED beyond the Anthropic prepass path: no captured artifact
#     exists for OTHER providers' auth errors -- the HTTP 401 / api-key
#     alternatives mirror the in-repo precedent pattern sets below, nothing
#     here is enabled on them alone (a mis-classified foreign error simply
#     stays failed_rc_N and does not trigger fallback).
#   RATE / QUOTA — UNVERIFIED as prepass-path evidence (no captured prepass
#     artifact exists); the patterns are the live-proven in-repo quota
#     classifier's: `_quota_shaped` in this file and lib/leadv2-lockout-
#     classify.py `_QUOTA_REFUSAL_RE` (:43-45), whose provenance is the
#     2026-08-17 05:49Z `429 rate limit` incident (test-lockout-failure-class.sh
#     header). The mapping itself is pinned by fixtures in
#     tests/test-dispatch-prepass-provider-fallback.sh (auth/rate/quota/opaque
#     matrix + precedence).
_ARCH_FAIL_AUTH_RE='authentication_failed|OAuth session expired|could not be refreshed|api[ _-]?key (expired|invalid|not valid)|HTTP 401|unauthorized'
_ARCH_FAIL_RATE_RE='rate[ _-]?limit|HTTP 429|too many requests|overloaded_error'
_ARCH_FAIL_QUOTA_RE='usage limit|quota exceeded|exceeded your current|plan limit'
_architect_failure_class() {  # <adir> <captured_out> <rc> -> "<class>[\t<detail>]"
  local adir="$1" cap="$2" rc="$3" ev="" s cls detail
  ev="${cap}"
  for s in "${adir}"/architect.stream.jsonl "${adir}"/*.stream.jsonl; do
    [[ -f "${s}" ]] || continue
    ev="${ev}
$(tail -c 262144 "${s}" 2>/dev/null)"
  done
  case "$(printf '%s' "${ev}" | grep -iE "${_ARCH_FAIL_AUTH_RE}" | head -1)" in
    ?*) cls="authentication_failed" ;;
    *)
      case "$(printf '%s' "${ev}" | grep -iE "${_ARCH_FAIL_RATE_RE}" | head -1)" in
        ?*) cls="rate_limited" ;;
        *)
          case "$(printf '%s' "${ev}" | grep -iE "${_ARCH_FAIL_QUOTA_RE}" | head -1)" in
            ?*) cls="quota_exceeded" ;;
            *)  cls="failed_rc_${rc}"; printf '%s' "${cls}"; return ;;
          esac ;;
      esac ;;
  esac
  detail="$(printf '%s' "${ev}" | grep -iE "${_ARCH_FAIL_AUTH_RE}|${_ARCH_FAIL_RATE_RE}|${_ARCH_FAIL_QUOTA_RE}" \
    | head -2 | tr '\n' ' ' | tr -cd '[:print:]' | cut -c1-220)"
  printf '%s\t%s' "${cls}" "${detail}"
}

# PREPASS-PROVIDER-FALLBACK-01 §2: bounded runner for a fallback-arm launcher.
# Same contract as the primary architect invocation below (timeout; kill the
# WHOLE descendant tree on expiry, not just the process group --
# ARCHITECT-PREPASS-ORPHAN-01; stdout+stderr captured; launcher rc preserved,
# 124 on timeout). Runs the arm's OWN launcher script via bash -- the dispatcher
# never calls a raw provider CLI. NOTE: no apostrophes in the heredoc body
# (same bash heredoc quirk as the primary invocation below).
_architect_timed_run() {  # <timeout_sec> <cmd...> -> stdout=output, rc=launcher rc
  local tmo="$1"; shift
  python3 - "${tmo}" "${ARCHITECT_FALLBACK_RUNNER_GO_FILE:-}" "$@" <<'PY' 2>&1 &
import os, signal, subprocess, sys, time
timeout, go_file = sys.argv[1:3]
proc = None
def stop_process_group():
    if proc is None:
        return
    try:
        os.killpg(proc.pid, signal.SIGKILL)
    except ProcessLookupError:
        pass
def interrupted(signum, _frame):
    stop_process_group()
    sys.exit(128 + signum)
signal.signal(signal.SIGTERM, interrupted)
signal.signal(signal.SIGINT, interrupted)
try:
    # Parent writes its runner PID before creating this gate.  No provider
    # process group can exist while the gate is closed, so a TERM in the
    # fork/register interval can always terminate this known supervisor first.
    while go_file and not os.path.exists(go_file):
        time.sleep(0.01)
    proc = subprocess.Popen(
        sys.argv[3:], env=os.environ.copy(), text=True,
        stdout=subprocess.PIPE, stderr=subprocess.STDOUT, start_new_session=True)
    stdout, _ = proc.communicate(timeout=int(timeout))
    sys.stdout.write(stdout or "")
    sys.exit(proc.returncode)
except subprocess.TimeoutExpired:
    if proc is not None:
        def _descendants(pid):
            try:
                out = subprocess.run(["pgrep", "-P", str(pid)], capture_output=True, text=True, timeout=5)
                kids = [int(x) for x in out.stdout.split()]
            except Exception:
                kids = []
            found = list(kids)
            for k in kids:
                found.extend(_descendants(k))
            return found
        for pid in _descendants(proc.pid) + [proc.pid]:
            try: os.kill(pid, signal.SIGKILL)
            except ProcessLookupError: pass
        stop_process_group()
        stdout, _ = proc.communicate()
        sys.stdout.write(stdout or "")
    print("architect_prepass_timeout", file=sys.stderr)
    sys.exit(124)
PY
  ARCHITECT_FALLBACK_RUNNER_PID=$!
  # Test seam for the fork->registration boundary.  It is deliberately before
  # PID-file publication and before opening the child gate; TERM here must
  # still reap ARCHITECT_FALLBACK_RUNNER_PID and must find no provider.
  if [[ -n "${LEADV2_FALLBACK_REGISTRATION_BARRIER_FILE:-}" ]]; then
    printf 'runner_pid=%s\n' "${ARCHITECT_FALLBACK_RUNNER_PID}" > "${LEADV2_FALLBACK_REGISTRATION_BARRIER_FILE}"
    while [[ ! -e "${LEADV2_FALLBACK_REGISTRATION_BARRIER_FILE}.release" ]]; do sleep 0.02; done
  fi
  if [[ -n "${ARCHITECT_FALLBACK_RUNNER_PID_FILE:-}" ]]; then
    local pid_tmp="${ARCHITECT_FALLBACK_RUNNER_PID_FILE}.tmp.$$"
    if printf '%s' "${ARCHITECT_FALLBACK_RUNNER_PID}" > "${pid_tmp}" 2>/dev/null; then
      mv -f "${pid_tmp}" "${ARCHITECT_FALLBACK_RUNNER_PID_FILE}" 2>/dev/null || rm -f "${pid_tmp}"
    fi
  fi
  # The runner cannot start its provider until this parent has published the
  # PID above.  File creation is the one-way registration handshake.
  [[ -z "${ARCHITECT_FALLBACK_RUNNER_GO_FILE:-}" ]] || : > "${ARCHITECT_FALLBACK_RUNNER_GO_FILE}"
  local runner_rc=0
  wait "${ARCHITECT_FALLBACK_RUNNER_PID}" || runner_rc=$?
  [[ -z "${ARCHITECT_FALLBACK_RUNNER_PID_FILE:-}" ]] || rm -f "${ARCHITECT_FALLBACK_RUNNER_PID_FILE}" 2>/dev/null || true
  [[ -z "${ARCHITECT_FALLBACK_RUNNER_GO_FILE:-}" ]] || rm -f "${ARCHITECT_FALLBACK_RUNNER_GO_FILE}" 2>/dev/null || true
  ARCHITECT_FALLBACK_RUNNER_PID=""
  return "${runner_rc}"
}

# PREPASS-PROVIDER-FALLBACK-01 §2: when the selected architect provider failed
# with a PROVIDER-class failure, walk the CONFIGURED dispatch ladder (canonical
# routing YAML via _load_dispatch_ladder), skip arms on the failed provider and
# arms under an active quota lockout (_provider_available), and run the SAME
# prepass prompt through the fallback arm's own launcher:
#   codex -> codex-task.sh task <prompt> --wait --tier standard --cwd <ws>
#   glm   -> glm-coder.sh run @<mission-file> --out <tmp> --cwd <ws>
# The design text is written to <out_file> and validated by the SAME guards as a
# Claude design (§3). Per-arm outcomes are journaled (§5). rc 0 = an arm produced
# a design; rc 1 = none did. Never retried inside itself -- the outer
# ARCHITECT_PREPASS_ATTEMPTS loop keeps that contract.
#
# R5 H1 (Codex review finding 1): both fallback launchers are CODE-CAPABLE, so
# they must never run with --cwd ${PROJECT_ROOT} -- a model deviation could
# modify the shared main checkout before worker admission or close-gate
# tracking. Every arm now runs inside a DISPOSABLE ISOLATED git worktree (a
# `git worktree add --detach` snapshot of ${PROJECT_ROOT}@HEAD under /tmp): the
# shared checkout is never the launcher's cwd, the agent may write only inside
# the disposable copy, ONLY the validated design artifact is extracted out of
# it, and _afb_discard_workspace removes the workspace on every terminal path
# of this function (arm success, per-arm failure, ladder exhaustion, workspace
# creation failure). If the worktree cannot be created the fallback aborts
# WITHOUT ever falling back to ${PROJECT_ROOT}.
#
# R5 H4 -- launcher result contracts and their evidence:
#   codex: `task <prompt> --wait` blocks foreground (codex-task.sh:1272-1281,
#     "P0 (CODEX-WAIT-AND-TIER-01) -- --wait forces foreground blocking") and
#     returns the full result inline on stdout with the launcher rc preserved
#     (codex-task.sh:1773-1775 "--wait/foreground runs already return the full
#     result inline"; final pipe at codex-task.sh:1883-1888 keeps stdout and
#     exits PIPESTATUS[0]). --cwd is forwarded to codex-companion's own
#     resolveCommandCwd (codex-task.sh:1772-1776). UNVERIFIED: that the inline
#     result for a task prompt is CLEAN design text with no metadata preamble
#     -- no captured probe of a real codex task run sits in this repo. Behavior
#     does not rest on that assumption alone: the captured stdout is accepted
#     as a design only after the SAME _lane_writes_guard + _acceptance_guard
#     that gate a Claude design (architect_prepass below), so preamble-laden or
#     non-conforming output is refused and the attempt parks, never dispatches.
#   glm: usage `glm-coder.sh run "<prompt|@file>" [--out <file>] [--cwd <dir>]`
#     (glm-coder.sh:160 usage line, --out consumed at :301); the design is read
#     from the --out FILE, never stdout (same artifact-not-stdout lesson as
#     PREPASS-READS-ARTIFACT-01). UNVERIFIED: that --out content is the raw
#     design with no wrapper -- same compensating control via the guards.
#   Both launchers are stubbed at their own seams in
#   tests/test-dispatch-prepass-provider-fallback.sh, which pins the
#   dispatcher-side parsing (codex: rc0 + non-empty stdout; glm: rc0 +
#   non-empty --out file) and the workspace isolation/cleanup.
_afb_discard_workspace() {  # <ws_base> -- best-effort disposal on EVERY terminal path
  local base="$1"
  [[ -n "${base}" && -d "${base}" ]] || return 0
  git -C "${PROJECT_ROOT:-.}" worktree remove --force "${base}/wt" >/dev/null 2>&1 || rm -rf "${base}/wt"
  rm -rf "${base}" 2>/dev/null || true
  git -C "${PROJECT_ROOT:-.}" worktree prune >/dev/null 2>&1 || true
  return 0
}

_architect_fallback_design() {  # <mission_file> <sig8> <fail_class> <out_file> <failed_provider>
  local mfile="$1" sig8="$2" failcls="$3" out_file="$4" failed_prov="$5"
  local i arm prov out rc glm_out run_out ws_base ws _afb_ok=0
  # R5 H1: disposable isolated workspace -- never ${PROJECT_ROOT} as cwd.
  ws_base="$(mktemp -d "${TMPDIR:-/tmp}/leadv2-afb.XXXXXX")" || return 1
  # Arm process-global EXIT/signal cleanup immediately: a signal between this
  # point and normal disposal must not strand a disposable worktree.
  ARCHITECT_FALLBACK_WORKSPACE_BASE="${ws_base}"
  ARCHITECT_FALLBACK_RUNNER_PID_FILE="${ws_base}/.fallback-runner.pid"
  ARCHITECT_FALLBACK_RUNNER_GO_FILE="${ws_base}/.fallback-runner.go"
  ws="${ws_base}/wt"
  if ! git -C "${PROJECT_ROOT}" worktree add --detach "${ws}" HEAD >/dev/null 2>&1; then
    _afb_discard_workspace "${ws_base}"
    ARCHITECT_FALLBACK_WORKSPACE_BASE=""
    ARCHITECT_FALLBACK_RUNNER_PID_FILE=""
    ARCHITECT_FALLBACK_RUNNER_GO_FILE=""
    emit decision "architect_prepass_fallback task=${sig8} outcome=aborted reason=workspace_unavailable"
    return 1
  fi
  (( ${#_LADDER_IDS[@]} )) || _load_dispatch_ladder
  for i in "${!_LADDER_IDS[@]}"; do
    arm="${_LADDER_IDS[${i}]}"; prov="${_LADDER_PROVIDERS[${i}]}"
    if [[ "${prov}" == "${failed_prov}" ]]; then
      emit decision "architect_prepass_fallback task=${sig8} arm=${arm} outcome=skipped reason=same_provider"
      continue
    fi
    case "${arm}" in
      codex|glm) : ;;
      *)
        emit decision "architect_prepass_fallback task=${sig8} arm=${arm} outcome=skipped reason=no_architect_launcher"
        continue ;;
    esac
    if ! _provider_available "${prov}"; then
      emit decision "architect_prepass_fallback task=${sig8} arm=${arm} outcome=skipped reason=provider_locked_out"
      continue
    fi
    case "${arm}" in
      codex)
        run_out="$(mktemp "${TMPDIR:-/tmp}/leadv2-architect-codex.XXXXXX")" || break
        # Do not command-substitute the supervisor: Bash defers the parent's
        # TERM trap while waiting on that form.  Redirecting its output lets
        # the trap-owning shell wait directly and interrupt its process group.
        if PROJECT_ROOT="${ws}" _architect_timed_run "${ARCHITECT_PREPASS_TIMEOUT_SEC}" \
                 bash "${CODEX_BIN}" task "$(cat "${mfile}")" --wait --tier standard --cwd "${ws}" > "${run_out}"; then
          rc=0
        else
          rc=$?
        fi
        out="$(cat "${run_out}" 2>/dev/null || true)"
        rm -f "${run_out}"
        if [[ ${rc} -eq 0 && -n "${out}" ]] && printf '%s\n' "${out}" > "${out_file}" 2>/dev/null; then
          _afb_ok=1
          ARCHITECT_FALLBACK_ARM_USED="${arm}"
          emit decision "architect_prepass_fallback task=${sig8} arm=${arm} outcome=used reason=${failcls} isolation=disposable_worktree"
          break
        fi
        emit decision "architect_prepass_fallback task=${sig8} arm=${arm} outcome=failed rc=${rc} reason=${failcls}"
        ;;
      glm)
        glm_out="$(mktemp "${TMPDIR:-/tmp}/leadv2-architect-glm.XXXXXX")" || break
        if PROJECT_ROOT="${ws}" GLM_TIMEOUT="${ARCHITECT_PREPASS_TIMEOUT_SEC}" \
                 _architect_timed_run "${ARCHITECT_PREPASS_TIMEOUT_SEC}" \
                 bash "${GLM_BIN}" run "@${mfile}" --out "${glm_out}" --cwd "${ws}" >/dev/null; then
          rc=0
        else
          rc=$?
        fi
        if [[ ${rc} -eq 0 && -s "${glm_out}" ]] && cat "${glm_out}" > "${out_file}" 2>/dev/null; then
          rm -f "${glm_out}"
          _afb_ok=1
          ARCHITECT_FALLBACK_ARM_USED="${arm}"
          emit decision "architect_prepass_fallback task=${sig8} arm=${arm} outcome=used reason=${failcls} isolation=disposable_worktree"
          break
        fi
        rm -f "${glm_out}"
        emit decision "architect_prepass_fallback task=${sig8} arm=${arm} outcome=failed rc=${rc} reason=${failcls}"
        ;;
    esac
  done
  # R5 H1: the disposable workspace is removed on EVERY terminal path -- arm
  # success (break above), per-arm failure, ladder exhaustion, write failure.
  _afb_discard_workspace "${ws_base}"
  ARCHITECT_FALLBACK_WORKSPACE_BASE=""
  ARCHITECT_FALLBACK_RUNNER_PID_FILE=""
  ARCHITECT_FALLBACK_RUNNER_GO_FILE=""
  (( ${_afb_ok} == 1 )) || return 1
  return 0
}

# PREPASS-PROVIDER-FALLBACK-01 §4: a parked/not-dispatched lane must not leave the
# dispatcher's own root PID consuming an active worker slot. Registration happens
# BEFORE the phase guard, architect prepass and router resolution (so supervise
# can watch the lane work); every exit between registration and an actual worker
# spawn must therefore release the row. Live evidence: dispatches 17309830 /
# 321ade3a parked at prepass and left root-Codex PID 99921 registered as two
# active Standard lanes with no worker launched. Best-effort by design: a registry
# failure is journaled but never converts a park into a crash.
#
# R5 (Codex review H2+H3, review-codex.md findings 2+3): the R4 release
# (a) unregistered by bare task_id -- a concurrent retry whose register merely
# REFRESHED another live dispatcher's row (register-op semantics,
# leadv2-active-registry.sh:174-186: a live-PID existing row is refreshed in
# place and the EXISTING session_id is returned) would delete that dispatcher's
# row and bypass supervision/capacity accounting; and (b) was scattered across
# a handful of exits while the other thirteen proven no-worker terminal exits
# left the row behind. Both fixed here:
#   - release is OWNER-VERIFIED: the session_id leadv2_active_register PRINTED
#     at registration, the registering durable PID, and pid_role must still
#     name THIS attempt's row (a refreshed foreign row keeps the other
#     dispatcher's pid; a post-spawn row carries pid_role=worker). A foreign or
#     worker-owned row is never unregistered by this dispatcher.
#   - release is driven by ONE disarmable EXIT trap (cleanup_pending_dispatch,
#     below) instead of per-exit call sites: every `exit N` after registration
#     releases the row unless a confirmed worker spawn -- or an ambiguous
#     post-spawn failure -- disarmed it first (see the DISPATCH_SLOT_REG_ID=""
#     handoff/disarm sites in cmd_resolve).
DISPATCH_SLOT_REG_ID=""
DISPATCH_SLOT_SESSION=""
DISPATCH_SLOT_PID=""
DISPATCH_SLOT_SIG8=""
DISPATCH_SLOT_PRESPAWN_DISARMED=""
_dispatch_disarm_slot_before_spawn() {
  # R10 H1: the launcher may expose a live GLM/Codex worker before control
  # returns to this shell.  Disarm the parent EXIT cleanup *before* invoking
  # it; a signal in that interval therefore preserves the registry row.  A
  # known no-worker result re-arms the same captured ownership below.
  [[ -n "${DISPATCH_SLOT_REG_ID:-}" ]] || return 0
  DISPATCH_SLOT_PRESPAWN_DISARMED="${DISPATCH_SLOT_REG_ID}"
  DISPATCH_SLOT_REG_ID=""
}
_dispatch_rearm_slot_after_no_spawn() {
  [[ -n "${DISPATCH_SLOT_PRESPAWN_DISARMED:-}" ]] || return 0
  DISPATCH_SLOT_REG_ID="${DISPATCH_SLOT_PRESPAWN_DISARMED}"
  DISPATCH_SLOT_PRESPAWN_DISARMED=""
}
_release_registered_lane() {  # <reg_id> <sig8> <where> -- owner-verified, idempotent
  local rid="$1" s8="$2" where="$3"
  [[ -n "${rid}" && -n "${DISPATCH_SLOT_REG_ID}" ]] || return 0
  DISPATCH_SLOT_REG_ID=""    # idempotent: only the FIRST release attempt acts
  if ! declare -F _leadv2_yaml_file >/dev/null 2>&1 || ! declare -F _leadv2_yaml_lockfile >/dev/null 2>&1; then
    emit decision "active_lane_release_skipped task=${s8:-} id=${rid} where=${where} reason=no_registry"
    return 0
  fi
  # R9 H1: compare AND delete under the registry's own flock.  A prior read
  # followed by leadv2_active_unregister could delete a row refreshed by a
  # different dispatcher in between.  Missing, unreadable, malformed, worker,
  # or ownership-mismatched rows all fail closed and are never removed.
  local yf lf release_rc
  yf="$(LEADV2_PROJECT_ROOT="${PROJECT_ROOT}" _leadv2_yaml_file 2>/dev/null)"
  lf="$(LEADV2_PROJECT_ROOT="${PROJECT_ROOT}" _leadv2_yaml_lockfile 2>/dev/null)"
  if [[ -z "${yf}" || -z "${lf}" || ! -f "${yf}" ]]; then
    emit decision "active_lane_release_skipped task=${s8:-} id=${rid} where=${where} reason=registry_unreadable"
    return 0
  fi
  python3 - "${lf}" "${yf}" "${rid}" "${DISPATCH_SLOT_SESSION}" "${DISPATCH_SLOT_PID}" <<'PY' 2>/dev/null
import fcntl, os, sys, tempfile
try:
    import yaml
except Exception:
    sys.exit(3)
lock_path, path, task_id, session, pid = sys.argv[1:6]
try:
    lock = open(lock_path, "a+")
except OSError:
    sys.exit(3)
try:
    fcntl.flock(lock, fcntl.LOCK_EX)
    with open(path, encoding="utf-8") as fh:
        data = yaml.safe_load(fh)
    if not isinstance(data, dict) or not isinstance(data.get("sessions"), list):
        sys.exit(3)
    rows = [row for row in data["sessions"] if isinstance(row, dict) and row.get("task_id") == task_id]
    if len(rows) != 1:
        sys.exit(2)
    row = rows[0]
    if (row.get("pid_role") == "worker" or not session or row.get("session_id") != session
            or not pid or str(row.get("pid")) != pid):
        sys.exit(2)
    data["sessions"].remove(row)
    fd, tmp = tempfile.mkstemp(prefix=".active-release-", dir=os.path.dirname(path))
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as out:
            yaml.safe_dump(data, out, default_flow_style=False, sort_keys=False)
            out.flush()
            os.fsync(out.fileno())
        os.replace(tmp, path)
    except Exception:
        try: os.unlink(tmp)
        except OSError: pass
        raise
except Exception:
    sys.exit(3)
finally:
    try: fcntl.flock(lock, fcntl.LOCK_UN)
    except Exception: pass
    lock.close()
sys.exit(0)
PY
  release_rc=$?
  case "${release_rc}" in
    0) emit decision "active_lane_released task=${s8:-} id=${rid} where=${where}" ;;
    2) emit decision "active_lane_release_skipped task=${s8:-} id=${rid} where=${where} reason=not_owner_row_intact" ;;
    *) emit decision "active_lane_release_failed task=${s8:-} id=${rid} where=${where} reason=registry_compare_delete_error" ;;
  esac
  return 0
}

architect_prepass() { # <raw mission> <sig8> <writes> -> 0 ran/skipped/disabled, 1 failed
  local raw="$1" sig8="$2" writes="$3" f mfile out rc count
  ARCHITECT_PREPASS_REASON=""
  ARCHITECT_FALLBACK_ARM_USED=""
  if [[ "${ARCHITECT_GATE}" != "1" ]]; then
    # H6 (LANDING-BLOCKER-R2): the kill-switch used to return before any writes check ran,
    # so ARCHITECT_GATE=0 could dispatch an undeclared, unisolated lane silently. Row-
    # declared writes or an existing lane worktree still satisfy the guard, so the
    # kill-switch remains usable -- it just can no longer bypass isolation.
    _lane_writes_guard "${sig8}" "${writes}" 0 || return 1
    emit decision "architect_prepass task=${sig8} status=disabled reason=kill_switch"
    return 0
  fi
  # A comma-separated declaration is proof only when it has exactly one non-empty entry.
  # PREPASS-PROVIDER-FALLBACK-01-R1: printf '%s' left the stream without a final
  # newline, so wc -l counted ONE declared path as zero and TWO as one -- the
  # two-path case then took the provably_one_file skip below and dodged prepass
  # entirely (an admission shortcut). printf '%s\n' counts truthfully across
  # 0/1/2/duplicate/blank/malformed CSVs: blank entries are dropped by the sed,
  # duplicates count as declared entries, 2+ always runs the prepass.
  count="$(printf '%s\n' "${writes}" | tr ',' '\n' | sed '/^[[:space:]]*$/d' | wc -l | tr -d ' ')"
  if [[ "${count}" == "1" ]]; then
    # H6: trivially satisfied (count==1 implies non-empty writes) -- called anyway so
    # there is exactly one guard call site per exit path.
    _lane_writes_guard "${sig8}" "${writes}" 0 || return 1
    emit decision "architect_prepass task=${sig8} status=skipped reason=provably_one_file writes=${writes}"
    return 0
  fi
  f="$(_prepass_file "${sig8}")"; mkdir -p "$(dirname "${f}")" || return 1

  # LANE-OBSERVABILITY-02 change 2: a RESUMED lane (--resume-lane/--worktree pin
  # resolved by _resolve_pinned_placement -> PLACEMENT_PINNED=1) must not be
  # re-fed a prepass the previous round already refuted or that predates the
  # lane base moving (merge/ff in the worktree) — the exact poison that killed
  # rounds 2-3 of dispatch-16fbe872. Evaluated BEFORE the PREPASS_CACHE
  # sig-match check below so an invalidated artifact can never be served from
  # cache. Non-resume runs are untouched. LEADV2_PREPASS_INVALIDATE=0 restores
  # today (never invalidate on resume). The machine read is the ${f}.head
  # SIDECAR (a worker that rewrites the prepass body cannot corrupt the check);
  # the HTML comment stamped into the artifact's first line is for humans.
  if [[ "${PLACEMENT_PINNED:-0}" == "1" && "${LEADV2_PREPASS_INVALIDATE:-1}" == "1" && -s "${f}" ]]; then
    local _pp_inv_reason="" _pp_old_head="" _pp_new_head _pp_last_cause
    _pp_new_head="$(git -C "${WORK_ROOT}" rev-parse HEAD 2>/dev/null || true)"
    if [[ -n "${_pp_new_head}" ]]; then
      if [[ -f "${f}.head" ]]; then
        _pp_old_head="$(cat "${f}.head" 2>/dev/null || true)"
        [[ "${_pp_old_head}" != "${_pp_new_head}" ]] && _pp_inv_reason="head_moved"
      else
        # every pre-existing artifact (pre-dating this change) has no .head —
        # treat as stale and invalidate exactly ONCE; the regeneration stamps
        # it, so the next resume at the same HEAD hits the cache.
        _pp_inv_reason="head_moved"; _pp_old_head="unstamped"
      fi
    fi
    if [[ -z "${_pp_inv_reason}" ]]; then
      # (a) the previous terminal for this sig8 refuted the census/prepass:
      # last row cause matching census|prepass|falsif|refus (case-insensitive).
      _pp_last_cause="$(_dispatch_terminal_ledger_cause "${sig8}")"
      if printf '%s' "${_pp_last_cause}" | grep -qiE 'census|prepass|falsif|refus'; then
        _pp_inv_reason="prepass_refuted"
      fi
    fi
    if [[ -n "${_pp_inv_reason}" ]]; then
      local _pp_epoch _pp_arch
      _pp_epoch="$(date +%s 2>/dev/null || printf '0')"
      _pp_arch="$(dirname "${f}")/architect-prepass.${_pp_epoch}.md"
      mv -f "${f}" "${_pp_arch}" 2>/dev/null || true
      mv -f "${f}.sig" "${_pp_arch}.sig" 2>/dev/null || true
      mv -f "${f}.head" "${_pp_arch}.head" 2>/dev/null || true
      emit decision "architect_prepass task=${sig8} status=invalidated reason=${_pp_inv_reason} old_head=${_pp_old_head:-unknown} new_head=${_pp_new_head:-unknown} archived=architect-prepass.${_pp_epoch}.md"
    fi
  fi

  # T-c (SUPERVISOR-AUDIT-01): sig-keyed cache. A stamp file next to the prepass artifact
  # holds the full mission-text hash (compute_sig, not just sig8) that produced it; a
  # byte-for-byte-identical retry of the SAME mission reuses the design instead of paying
  # the architect's cost again. LEADV2_PREPASS_CACHE=0 restores today (always re-run).
  if [[ "${PREPASS_CACHE}" == "1" && -s "${f}" && -f "${f}.sig" ]]; then
    local _pc_raw_sig _pc_stamp
    _pc_raw_sig="$(printf '%s' "${raw}" | compute_sig)"
    _pc_stamp="$(cat "${f}.sig" 2>/dev/null)"
    if [[ -n "${_pc_raw_sig}" && "${_pc_raw_sig}" == "${_pc_stamp}" ]]; then
      # H4 (LANDING-BLOCKER-R2): every pre-existing .sig stamp predates the LANE_WRITES
      # prompt line, so a byte-identical retry of a row with no declared writes would
      # otherwise serve a cached artifact the park guard never checked and skip straight
      # to dispatch. Treat "no row writes AND cached artifact has no LANE_WRITES line" as
      # a cache miss -- fall through and re-run the architect once -- instead of trusting
      # the stamp blindly.
      if [[ -n "${writes}" || -n "$(_prepass_writes "${sig8}")" ]]; then
        emit decision "architect_prepass task=${sig8} status=cached reason=sig_match artifact=docs/handoff/dispatch-${sig8}/architect-prepass.md"
        return 0
      fi
      emit decision "architect_prepass task=${sig8} status=cache_miss reason=cached_artifact_no_lane_writes"
    fi
  fi

  mfile="$(mktemp "${TMPDIR:-/tmp}/leadv2-architect-prepass.XXXXXX")" || return 1
  # T-c: a short mission (<15 lines) gets a terser prompt -- same architect, same model,
  # just less framing text to process. LEADV2_PREPASS_CACHE=0 restores the single long
  # prompt for every mission regardless of length.
  local _pc_lines
  _pc_lines="$(printf '%s\n' "${raw}" | grep -c .)"
  if [[ "${PREPASS_CACHE}" == "1" && "${_pc_lines}" -lt 15 ]]; then
    printf '%s\n' "Architect prepass (short mission). Terse scoped design only: changes, exact files, explicit non-goals. State acceptance as an 'acceptance:' block with surface (rendered_line|prod_db_row|log_line|http_response|file_artifact), observable (what a human sees at that surface -- never a function name, return value, exit code, or variable), and authored_at (now, ISO-8601) -- never a shell command, grep pattern, or test invocation; that is an internal contract, not acceptance (RED-FIRST-GATE-01 R2). End with a line 'LANE_WRITES: <comma-separated repo-relative paths or globs>' listing every file the implementation will write -- no docs/leadv2 or docs/handoff entries; this line is required.\n\nMISSION:\n${raw}" > "${mfile}"
  else
    printf '%s\n' "You are the architect prepass. Turn this mission into a MECHANISM-CLOSED implementation design. State: changes, exact files, and explicit non-goals. Do not implement.

MECHANISM CLOSURE (PREPASS-MECHANISM-CLOSURE-01) -- four sections, all required, all read from the tree rather than assumed. The mission's findings tell you where to LOOK; they do not bound what the design must handle. Rounds multiply when a design is complete with respect to a findings list and incomplete with respect to the mechanism, so close the mechanism here, once, instead of discovering it one review round at a time:
  1. CALLERS/CALLEES: every caller of each function you touch and every function it calls, with file:line. If a caller is on a different path (prefill vs v4-runner, post vs comment), say so -- an independent copy that nobody named is the usual miss.
  2. STATES AND RETURN CODES: a table of every state the mechanism can be in and every rc it can return, and for EACH rc what the caller does with it. Trace terminal outcomes to the end: if an rc reaches a loop that does not retry, or a gate that aborts, write the user-visible consequence in plain words ('no post is drafted for that tenant today'), not the rc.
  3. CONFIGURATION BOUNDARIES: for every input the mechanism reads -- file, flag, env var, DB column -- enumerate absent, empty, minimum, maximum/over-cap, and malformed. Name the behaviour at each. An over-cap or malformed input that takes down more than the one operation it belongs to is a defect, not a safety feature.
  4. COUNTEREXAMPLE: answer in one paragraph -- 'after every finding in this mission is fixed, what can STILL violate the invariant this mechanism exists to protect?' If the honest answer is 'nothing I can find', say that and say what you checked.
If code discovery contradicts the mission's framing, say so plainly and design against the code. The mission is the reason to look, not the boundary of what is true. State acceptance as an 'acceptance:' block with surface (rendered_line|prod_db_row|log_line|http_response|file_artifact), observable (what a human sees at that surface -- never a function name, return value, exit code, or variable), and authored_at (now, ISO-8601) -- never a shell command, grep pattern, or test invocation; that is an internal contract, not acceptance (RED-FIRST-GATE-01 R2). End with a line 'LANE_WRITES: <comma-separated repo-relative paths or globs>' listing every file the implementation will write -- no docs/leadv2 or docs/handoff entries; this line is required.\n\nMISSION:\n${raw}" > "${mfile}"
  fi
  # macOS has no portable `timeout`. Python waits for the launcher only; a
  # timed-out advisory prepass is deliberately allowed to finish or be reaped
  # independently while this dispatch immediately continues with the raw task.
  out="$(PROJECT_ROOT="${PROJECT_ROOT}" python3 - "${ARCHITECT_PREPASS_TIMEOUT_SEC}" "${ARCHITECT_BIN}" "${LEADV2_DISPATCH_ARCHITECT_MODEL:-opus}" "dispatch-${sig8}-${ARCHITECT_LANE_SUFFIX}" "${mfile}" <<'PY' 2>&1
import os, signal, subprocess, sys
timeout, binary, model, task_id, mission_file = sys.argv[1:]
proc = None
try:
    proc = subprocess.Popen(
        ["bash", binary, "--role", "architect", "--model", model,
         "--task-id", task_id, "--mission-file", mission_file, "--wait"],
        env=os.environ.copy(), text=True, stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT, start_new_session=True,
    )
    stdout, _ = proc.communicate(timeout=int(timeout))
    sys.stdout.write(stdout or "")
    sys.exit(proc.returncode)
except subprocess.TimeoutExpired as exc:
    # ARCHITECT-PREPASS-ORPHAN-01: os.killpg alone only reaches processes still
    # in the launcher own process group. A descendant that calls os.setsid()
    # (observed: the underlying agent CLI or an MCP helper it spawns) moves
    # itself to a new session/group and survives killpg indefinitely -- the
    # mechanism behind a lane that was still writing to its stream file 63
    # minutes after prepass entered. Walk the actual descendant tree via pgrep
    # and kill every PID individually; killpg stays as a backstop for the
    # common (non-escaped) case. NOTE: no apostrophes in this heredoc -- a
    # bash quirk with $(...) around <<'PY' breaks parsing on unmatched single
    # quotes even inside the quoted heredoc body.
    if proc is not None:
        def _descendants(pid):
            try:
                out = subprocess.run(["pgrep", "-P", str(pid)], capture_output=True, text=True, timeout=5)
                kids = [int(x) for x in out.stdout.split()]
            except Exception:
                kids = []
            found = list(kids)
            for k in kids:
                found.extend(_descendants(k))
            return found
        for pid in _descendants(proc.pid) + [proc.pid]:
            try: os.kill(pid, signal.SIGKILL)
            except ProcessLookupError: pass
        try: os.killpg(proc.pid, signal.SIGKILL)
        except ProcessLookupError: pass
        stdout, _ = proc.communicate()
        sys.stdout.write(stdout or "")
    print("architect_prepass_timeout", file=sys.stderr)
    sys.exit(124)
PY
)"; rc=$?
  # PREPASS-PROVIDER-FALLBACK-01 §2: mfile is NOT removed here any more -- a
  # provider-class failure below re-feeds this exact prompt to a fallback arm's
  # own launcher. It is removed on every path that leaves this block.
  # PREPASS-READS-ARTIFACT-01 (2026-07-29): the design is NOT on the launcher's stdout.
  # claude-subsession.sh writes the agent's actual text to its handoff dir and prints only
  # a handle on stdout / cost+session diagnostics on stderr -- exactly the trap FIX PASS 5
  # documents for spawn_worker below, repeated here. Capturing `2>&1` therefore wrote log
  # metadata into architect-prepass.md, workers found no design, and the gate then killed
  # or stalled every product dispatch (observed live 2026-07-29: the architect had in fact
  # produced a correct 21KB design that nobody ever read). Read the ARTIFACT.
  local adir="${PROJECT_ROOT}/docs/handoff/dispatch-${sig8}-${ARCHITECT_LANE_SUFFIX}"
  local design="" _pp_wait_tries=0
  while :; do
    for cand in "${adir}/architect.full.md" "${adir}/architect.md" "${adir}/architect.summary.md"; do
      [[ -s "${cand}" ]] && { design="${cand}"; break; }
    done
    [[ -n "${design}" ]] && break
    # ARTIFACT-LAND-AFTER-READ-01: only on a non-zero launcher rc is there any
    # reason to doubt a first empty read -- a rc=0 return already implies
    # claude-subsession.sh itself found the deliverable on disk. Poll briefly
    # (bounded 2s) rather than declaring the prepass failed off a single stat
    # that can race the artifact's own write finishing.
    _pp_wait_tries=$((_pp_wait_tries + 1))
    [[ ${rc} -ne 0 && ${_pp_wait_tries} -le 10 ]] || break
    sleep 0.2
  done
  if [[ ${rc} -ne 0 && -z "${design}" ]]; then
    # PREPASS-PROVIDER-FALLBACK-01 §1: surface the REAL failure class from the
    # launcher's stream/handoff evidence (live 17309830/321ade3a: authentication_
    # failed was on disk, the journal said failed_rc_1). rc 124 stays `timeout`.
    local _pp_cls _pp_detail="" _pp_failed_prov
    _pp_cls="$(_architect_failure_class "${adir}" "${out}" "${rc}")"
    [[ ${rc} -eq 124 ]] && _pp_cls="timeout"
    if [[ "${_pp_cls}" == *$'\t'* ]]; then
      _pp_detail="${_pp_cls#*$'\t'}"
      _pp_detail="$(printf '%s' "${_pp_detail}" | tr -c '[:print:]' ' ' | tr -s ' ')"
    fi
    _pp_cls="${_pp_cls%%$'\t'*}"
    ARCHITECT_PREPASS_REASON="${_pp_cls}"
    emit decision "architect_prepass task=${sig8} status=failed reason=${_pp_cls} rc=${rc} arm=claude${_pp_detail:+ detail=${_pp_detail}}"
    log_err "architect prepass failed (arm=claude, class=${_pp_cls}): ${out}"
    # §2: a PROVIDER-class failure (never a design-quality failure, never a
    # timeout) retries the same prompt through another configured arm's own
    # launcher before this attempt is declared failed. The fallback design is
    # validated exactly like a Claude design by the shared guards below (§3).
    case "${LEADV2_DISPATCH_ARCHITECT_MODEL:-opus}" in
      opus|sonnet|haiku|claude*) _pp_failed_prov="anthropic" ;;
      *) _pp_failed_prov="$(_arm_provider "${LEADV2_DISPATCH_ARCHITECT_MODEL:-opus}")" ;;
    esac
    if [[ "${ARCHITECT_FALLBACK}" == "1" ]] \
       && [[ "${_pp_cls}" == "authentication_failed" || "${_pp_cls}" == "rate_limited" || "${_pp_cls}" == "quota_exceeded" ]] \
       && _architect_fallback_design "${mfile}" "${sig8}" "${_pp_cls}" "${f}" "${_pp_failed_prov}"; then
      design="fallback"
    else
      rm -f "${mfile}"
      return 1
    fi
  fi
  rm -f "${mfile}"
  if [[ "${design}" == "fallback" ]]; then
    :  # already written to ${f} by _architect_fallback_design
  elif [[ -n "${design}" ]]; then
    cat "${design}" > "${f}" || return 1
  else
    printf '%s\n' "${out}" > "${f}" || return 1
  fi
  [[ -s "${f}" ]] || { ARCHITECT_PREPASS_REASON="empty_output"; emit decision "architect_prepass task=${sig8} status=failed reason=empty_output"; return 1; }
  # P0-WORK-CANNOT-LAND-UNSCOPABLE-DIFF-01: a product lane with no declared writes -- neither
  # the founder's row `writes` field (this function's own `writes` arg) nor the architect's
  # own LANE_WRITES: line -- cannot be scoped to its own tree when review builds the diff
  # (leadv2-dispatch-product-close.sh unscopable_diff). A lane worktree already isolates the
  # lane on its own branch, so it substitutes for a declaration. LEADV2_REQUIRE_LANE_WRITES=0
  # restores today (never guard).
  if ! _lane_writes_guard "${sig8}" "${writes}" 1 || ! _acceptance_guard "${sig8}" "${f}"; then
    # M7 (LANDING-BLOCKER-R2): stamp the .sig cache BEFORE returning so a byte-identical
    # retry of this same non-compliant mission hits the cache path (H4 re-runs once, then
    # parks) instead of paying a second full architect run before parking.
    if [[ "${PREPASS_CACHE}" == "1" ]]; then
      printf '%s' "$(printf '%s' "${raw}" | compute_sig)" > "${f}.sig" 2>/dev/null || true
    fi
    return 1
  fi
  # T-c: stamp the mission-text hash that produced this design so a later byte-identical
  # retry (same sig8) can be served from cache. Fail-open: a stamp write failure never
  # fails the prepass itself, it only means the NEXT call re-runs (safe, just slower).
  # LANE-OBSERVABILITY-02 change 2: the same block now also stamps the generation
  # HEAD — a human-readable HTML comment on the artifact's first line (inert to
  # every existing line-scanner reader: they key on headings / LANE_WRITES: /
  # acceptance: lines, never line 1) and the machine-read ${f}.head SIDECAR the
  # resume invalidation gate above compares against. Both fail-open the same
  # way as .sig: a stamp failure only costs the next resume one regeneration.
  if [[ "${PREPASS_CACHE}" == "1" ]]; then
    printf '%s' "$(printf '%s' "${raw}" | compute_sig)" > "${f}.sig" 2>/dev/null || true
    local _pp_head_sha _pp_hdr_tmp
    _pp_head_sha="$(git -C "${WORK_ROOT}" rev-parse HEAD 2>/dev/null || true)"
    if [[ -n "${_pp_head_sha}" ]]; then
      printf '%s\n' "${_pp_head_sha}" > "${f}.head" 2>/dev/null || true
      _pp_hdr_tmp="${f}.hdr.$$"
      if printf '<!-- leadv2-prepass base_head=%s generated_at=%s -->\n' \
           "${_pp_head_sha}" "$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || printf '%s' "$(date +%s)")" \
           > "${_pp_hdr_tmp}" 2>/dev/null && cat "${f}" >> "${_pp_hdr_tmp}" 2>/dev/null; then
        mv -f "${_pp_hdr_tmp}" "${f}" 2>/dev/null || rm -f "${_pp_hdr_tmp}" 2>/dev/null || true
      else
        rm -f "${_pp_hdr_tmp}" 2>/dev/null || true
      fi
    fi
  fi
  # PREPASS-PROVIDER-FALLBACK-01 §5: journal which arm actually produced the
  # design (claude = the primary launcher; codex/glm = a fallback arm selected
  # by _architect_fallback_design). Whether a worker was actually launched is
  # journaled downstream: worker_spawned on success, action=not_dispatched +
  # worker_launched=0 on the park path.
  emit decision "architect_prepass task=${sig8} status=ran arm=${ARCHITECT_FALLBACK_ARM_USED:-claude} artifact=docs/handoff/dispatch-${sig8}/architect-prepass.md source=${design:-stdout}"
}

# ── MON-PULSE-01: dispatcher-owned lane watch + single-lead beat default-on ───────
# Founder order 2026-08-28 (3rd PULSE-IN-SINGLE-LEAD-01): lane tracking and the
# founder pulse must work IN THE PLUGIN, never as session-improvised lead
# Monitors (two `tail -n 0` Monitors missed a dispatch_terminal written 25s
# post-spawn). At worker_spawned the dispatcher itself arms, detached (nohup):
#   1. leadv2-lane-pulse-watch.sh — replay-safe per-lane journal watch that
#      pulses every terminal state (dispatch_terminal|dispatch_refused|
#      worker_died) for ITS sig via the existing leadv2-pulse.sh, pulses
#      review_gate as a mid-flight beat but keeps watching, and never re-
#      pulses lines a previous watcher already pulsed (per-sig seen ledger);
#   2. leadv2-single-lead-beat-loop.sh — the BROAD_STATUS beat, default-on in
#      single-lead mode while >=1 lane is live (armed once; pidfile guard).
# Both are fail-open by construction: a missing binary, a full /tmp, or a dead
# spawn can never affect this dispatcher's own control flow. LEADV2_PULSE_MODE=0
# (and for the beat LEADV2_SINGLE_LEAD_BEAT=0) is the kill-switch. The bins are
# env-overridable so tests stub them without touching the real watchers. Runs
# inside a command-substitution subshell (spawn_worker's stdout is captured),
# so every fd is explicitly redirected -- a background child holding the
# capture pipe open would hang the caller. 9>&- matches the file-wide flock-fd
# idiom used at every launcher call site.
LANE_PULSE_WATCH_BIN="${LEADV2_DISPATCH_LANE_PULSE_WATCH_BIN:-${SCRIPT_DIR}/leadv2-lane-pulse-watch.sh}"
SINGLE_LEAD_BEAT_LOOP_BIN="${LEADV2_DISPATCH_BEAT_LOOP_BIN:-${SCRIPT_DIR}/leadv2-single-lead-beat-loop.sh}"
_arm_lane_pulse_watch() {  # <sig8> — fail-open, never blocks dispatch
  [[ "${LEADV2_PULSE_MODE:-1}" == "1" ]] || return 0
  [[ -f "${LANE_PULSE_WATCH_BIN}" ]] || return 0
  LEADV2_PROJECT_ROOT="${PROJECT_ROOT}" \
    nohup bash "${LANE_PULSE_WATCH_BIN}" --sig "${1}" >/dev/null 2>&1 </dev/null 9>&- &
}
_arm_single_lead_beat() {  # fail-open, armed once (loop's own pidfile guards re-arm)
  [[ "${LEADV2_PULSE_MODE:-1}" == "1" ]] || return 0
  [[ "${LEADV2_SINGLE_LEAD_BEAT:-1}" == "0" ]] && return 0
  [[ -f "${SINGLE_LEAD_BEAT_LOOP_BIN}" ]] || return 0
  LEADV2_PROJECT_ROOT="${PROJECT_ROOT}" \
    nohup bash "${SINGLE_LEAD_BEAT_LOOP_BIN}" >/dev/null 2>&1 </dev/null 9>&- &
}

# ── spawn: actually launch the resolved worker (Finding 2) ────────────────────────
# GLM_BIN/SUBSESSION_BIN are sibling scripts, overridable so tests stub the underlying
# `claude` call via EACH launcher's OWN seam (glm-coder.sh: GLM_CLAUDE_BIN/GLM_RUNS_DIR/
# GLM_SECRETS_FILE; claude-subsession.sh: LEADV2_DRY_RUN=1) -- this script never
# duplicates that stubbing, it only calls the launcher and reports its handle.
GLM_BIN="${LEADV2_DISPATCH_GLM_BIN:-${SCRIPT_DIR}/glm-coder.sh}"
# KIMI-CHANNEL-01: sibling launcher, same bg/status contract as glm-coder.sh.
KIMI_BIN="${LEADV2_DISPATCH_KIMI_BIN:-${SCRIPT_DIR}/kimi-coder.sh}"
# T19: sibling launcher, same bg/status contract as glm-coder.sh (clone,
# pointed at the local freepool-proxy.sh instead of Z.AI). Own admission gate
# (leadv2-freepool-gate.sh) refuses independently of quota -- arm_down/gate_broken.
FREEPOOL_BIN="${LEADV2_DISPATCH_FREEPOOL_BIN:-${SCRIPT_DIR}/freepool-coder.sh}"
SUBSESSION_BIN="${LEADV2_DISPATCH_SUBSESSION_BIN:-${SCRIPT_DIR}/claude-subsession.sh}"
ARCHITECT_BIN="${LEADV2_DISPATCH_ARCHITECT_BIN:-${SUBSESSION_BIN}}"
# codex-task.sh is the sanctioned Codex channel -- it already owns tier resolution
# (--tier top|standard|volume), detach (task --background), and its own job registry;
# this script never reimplements any of that, only calls it and reads its handle/status.
CODEX_BIN="${LEADV2_DISPATCH_CODEX_BIN:-${SCRIPT_DIR}/codex-task.sh}"
LANE_WORKTREE_BIN="${LEADV2_DISPATCH_LANE_WORKTREE_BIN:-${SCRIPT_DIR}/leadv2-lane-worktree.sh}"
# LANE-PLACEMENT-01: liveness probe seam — the placement validator uses this to refuse
# hijacking a still-live lane.  Overridable for tests (stub returns dead/alive on demand).
LANE_LIVENESS_BIN="${LEADV2_DISPATCH_LANE_LIVENESS_BIN:-${SCRIPT_DIR}/leadv2-lane-liveness.sh}"
# BURN-GOVERNOR-01: 24h local token-burn verdict, consulted by _burn_gate below.
BURN_GOVERNOR_BIN="${LEADV2_BURN_GOVERNOR_BIN:-${SCRIPT_DIR}/leadv2-burn-governor.sh}"

# <arm> <mission> <sig8> -> prints `worker_spawned ...`, journals it, returns 0/1.
# Both launchers detach on their own (glm-coder.sh: setsid_wrapper + disown;
# claude-subsession.sh without --wait: setsid_wrapper detaches the backgrounded `claude`
# worker itself, SD-SONNET-ARM-DETACH-01 -- prints PID, exits) -- this function never
# blocks on the worker finishing, so it cannot deadlock the caller.
# FIX PASS 5 (2026-07-25, live spawn failure): the launchers print their HANDLE on stdout
# but diagnostics on stderr (claude-subsession.sh:458 `cost recorded:` -> stderr, :861
# `PID=... SESSION_ID=...` -> stdout). Capturing `2>&1` merged them, so `tail -1` grabbed
# whichever line flushed last -- in practice the stderr cost line -- and the PID-required
# guard then rejected a worker that had actually launched. Streams are kept SEPARATE now:
# stdout carries the handle, stderr is retained only for the failure message. This is
# launcher-format-agnostic (no PID-pattern grep needed). The wrapper owns the stderr
# tempfile so every early `return` in the body still cleans it up.
# V3-ENV-GUARDS-01 item 3: worker-launcher environment asserts.
# _worker_env_asserts <arm> <sig8> -> always 0, journals exactly two lines.
# Runs inside dispatch-code's OWN process, called once at the top of
# spawn_worker() before any launcher is invoked -- plain unset/export here is
# inherited by every launcher this process execs next (no env -i rewrite
# needed; the candidate loop spawns one arm at a time per process, so this
# process-global mutation cannot race a sibling arm).
#   A1: CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS must never reach a worker (a
#       stray shell profile on the host exporting =1 would leak into every
#       worker and regress routing) -- unset unless already unset/0.
#   A2: CLAUDE_CODE_ENABLE_TODO_TOOLS -- CC 2.1.233 stopped shipping the
#       Task-tool family (TaskCreate/Update/List, TodoWrite) by default on
#       Sonnet 5/Opus 4.8+; leadv2-continuation-guard.sh counts TaskCreate/
#       TaskUpdate as productive tool calls and hooks.json registers a
#       TaskCreated event, so a worker without these tools is mis-scored and
#       the event never fires. Set =1 unless opted out via
#       LEADV2_WORKER_TODO_TOOLS=0.
_worker_env_asserts() {  # <arm> <sig8>
  local arm="$1" sig8="$2"
  local ateams="${CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS:-}"
  if [[ -n "${ateams}" && "${ateams}" != "0" ]]; then
    unset CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS
    emit decision "worker_env_assert arm=${arm} task=${sig8} var=CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS action=unset was=${ateams}"
  else
    emit decision "worker_env_assert arm=${arm} task=${sig8} var=CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS action=ok"
  fi
  if [[ "${LEADV2_WORKER_TODO_TOOLS:-1}" == "0" ]]; then
    emit decision "worker_env_assert arm=${arm} task=${sig8} var=CLAUDE_CODE_ENABLE_TODO_TOOLS action=skip reason=opt_out"
  else
    export CLAUDE_CODE_ENABLE_TODO_TOOLS=1
    emit decision "worker_env_assert arm=${arm} task=${sig8} var=CLAUDE_CODE_ENABLE_TODO_TOOLS action=set value=1"
  fi
  return 0
}

spawn_worker() {
  local errf rc
  LAST_ARM_OUTCOME="$1_failed_launcher"
  # Last common admission door: cmd_resolve, advance-arm, and future callers
  # cannot start a model process after a hard burn verdict.
  if ! _burn_gate; then
    LAST_ARM_OUTCOME="$1_refused_budget_gate"
    emit decision "arm_refused by=router model=$1 task=$3 reason=budget_gate_pre_spawn"
    printf '%s' "${LAST_ARM_OUTCOME}" > "${TMPDIR:-/tmp}/leadv2-spawn-outcome.$$" 2>/dev/null || true
    return 2
  fi
  _worker_env_asserts "$1" "$3"
  errf="$(mktemp "${TMPDIR:-/tmp}/leadv2-dispatch-err.XXXXXX")" || {
    log_err "spawn($1): could not create stderr tempfile"; return 1
  }
  _spawn_worker_body "$1" "$2" "$3" "${errf}"; rc=$?
  # REVIEW FIX (critic High, 2026-07-25): the inline log message is capped, so on FAILURE
  # keep the launcher's FULL stderr on disk instead of discarding everything past the tail.
  # The old `2>&1` bug at least preserved all of it in ${out}; this fix pass exists because a
  # launch failure was hard to diagnose, so truncating the next one's evidence would be a
  # regression in exactly the failure mode it targets.
  if [[ ${rc} -ne 0 && -s "${errf}" ]]; then
    local keep="${TMPDIR:-/tmp}/leadv2-dispatch-spawn-$3.stderr.log"
    if cp "${errf}" "${keep}" 2>/dev/null; then
      log_err "spawn($1) full launcher stderr preserved at ${keep}"
    fi
  fi
  rm -f "${errf}"
  # N1-EMPTY-LANE-IS-NOT-A-PASS (B.2): LAST_ARM_OUTCOME is set inside this
  # function, but spawn_worker runs inside a command substitution
  # (spawn_out="$(spawn_worker ...)") so a plain global does NOT escape the
  # subshell back to the caller. Persist it to a per-process temp file so
  # atomic_dispatch_reserve_spawn_confirm can restore it in its OWN scope -- the
  # candidate loop's arc==7 branch reads it to decide whether a refusal carries
  # a routing signal worth re-resolving on (glm_refused_lock_busy).
  printf '%s' "${LAST_ARM_OUTCOME}" > "${TMPDIR:-/tmp}/leadv2-spawn-outcome.$$" 2>/dev/null || true
  return ${rc}
}

spawn_product_close() { # <sig8> <author arm> <normalized handle> <quota-eligible arms csv> <lane_writes_csv> <founder_task_id> <lane_mission_path> [<lane_deliverable_decl>]
  # N7F-LANE-NAME: forwards DISPATCH_LANE_NAME as close_bin's 8th positional (not a 7th
  # param on this fn -- read from the global, same pattern as _dl_note above) so the
  # display name survives the worker->close-phase handoff for act two.
  local sig8="$1" author="$2" handle="$3" reviewer_arms="${4:-}" lane_writes_csv="${5:-}"
  local founder_task_id="${6:-}" lane_mission_path="${7:-}" lane_deliverable_decl="${8:-}"
  [[ "${E2E_GATE}" == "1" || "${REVIEW_GATE}" == "1" ]] || return 0
  local close_bin="${LEADV2_DISPATCH_PRODUCT_CLOSE_BIN:-${SCRIPT_DIR}/leadv2-dispatch-product-close.sh}"
  if [[ ! -f "${close_bin}" ]]; then
    emit decision "product_close task=${sig8} status=failed reason=close_script_missing"
    return 1
  fi
  # ARM-PRODUCES-NOTHING-AND-CHAIN-NEVER-ADVANCES-01: thread the resolved candidate
  # chain (LEADV2_DISPATCH_CANDIDATE_ARMS -- read by the close gate's silent-arm probe
  # to find the next arm to advance to) and the ONE lane-mission artifact this dispatch
  # already wrote to disk, so the close gate can re-spawn the next arm on an identical
  # mission without re-deriving it. ONE-PATH-EVERYWHERE-01: the sibling
  # LEADV2_DISPATCH_REVIEWER_ARMS export was deleted here -- it was dead (see the
  # `reviewer_arms` local's own comment below); leadv2-dispatch-product-close.sh /
  # leadv2-review-run.sh resolve their own reviewer pool independently.
  PROJECT_ROOT="${PROJECT_ROOT}" LEADV2_DISPATCH_CACHE_DIR="${CACHE_BASE}" \
    LEADV2_JOURNAL_BIN="${JOURNAL_BIN}" LEADV2_DISPATCH_CODEX_BIN="${CODEX_BIN}" \
    LEADV2_DISPATCH_ARCHITECT_BIN="${ARCHITECT_BIN}" \
    LEADV2_DISPATCH_CANDIDATE_ARMS="${reviewer_arms}" \
    LEADV2_DISPATCH_LANE_MISSION="${lane_mission_path}" \
    LEADV2_DISPATCH_LANE_WRITES="${lane_writes_csv}" \
    LEADV2_DISPATCH_LANE_DELIVERABLE="${lane_deliverable_decl}" \
    LEADV2_LANE_WORK_ROOT="${WORK_ROOT}" \
    LEADV2_LANE_START_SHA="${LANE_START_SHA:-}" \
    "${BASH:-bash}" "${close_bin}" "${PROJECT_ROOT}" "${sig8}" "${author}" "${handle}" "${E2E_GATE}" "${REVIEW_GATE}" "${founder_task_id}" "${DISPATCH_LANE_NAME:-}" \
      >/dev/null 2>&1 &
  local _pc_pid=$!
  # wave2 round2 finding 3: stamp the close-owner record with the REAL os pid of the
  # just-forked child ourselves, before this function returns -- eliminates the startup
  # race where product-close.sh wrote its OWN pid as its first executed line (a window
  # existed between fork and that write during which a concurrent sweep saw no record at
  # all and wrongly treated the lane as "close gate never launched").
  local _pc_pidfile _pc_pidfile_tmp
  _pc_pidfile="$(close_owner_pidfile "${sig8}")"
  mkdir -p "$(dirname "${_pc_pidfile}")" 2>/dev/null
  # wave2 round3 finding 2: temp file + atomic rename, mirroring leadv2-dispatch-
  # product-close.sh's own self-refresh fix -- a direct `>` truncate-in-place left a
  # window where a concurrent sweep could read a truncated/empty pid and misclassify a
  # live close-owner as dead.
  _pc_pidfile_tmp="${_pc_pidfile}.tmp.$$"
  if printf '%s\n' "${_pc_pid}" > "${_pc_pidfile_tmp}" 2>/dev/null; then
    mv -f "${_pc_pidfile_tmp}" "${_pc_pidfile}" 2>/dev/null || true
  else
    rm -f "${_pc_pidfile_tmp}" 2>/dev/null || true
  fi
  emit decision "product_close task=${sig8} status=spawned author=${author}"
}

# A launcher can decline an arm without being broken.  The GLM quota gate's
# documented REROUTE message is such an admission decision; test launchers and
# future gates may use the explicit LEADV2_DISPATCH_REFUSED marker.  Keep this
# narrow: an arbitrary non-zero exit remains a genuine launcher failure.
refusal_reason() { # <arm> <exit-code> <stdout> <stderr> -> reason, or rc 1
  local arm="$1" rc="$2" out="$3" err="$4" combined
  combined="${out}"$'\n'"${err}"
  local marker
  marker="$(printf '%s\n' "${combined}" | sed -n 's/.*LEADV2_DISPATCH_REFUSED:[[:space:]]*\([A-Za-z0-9._-][A-Za-z0-9._-]*\).*/\1/p' | head -1)"
  # Every arm shares this contract.  Non-zero alone is still a launcher failure;
  # only the documented admission exit codes plus an explicit marker are refusals.
  # KIMI-CHANNEL-01: kimi-coder.sh's launch probe fails closed with rc=77 (no
  # run-id printed yet) -- distinct from glm's rc 1 (quota)/rc 2 (peak) so the
  # two channels' launch failures are never confused, but the SAME marker
  # contract applies: only a launcher that both exits one of its documented
  # admission codes AND emits the LEADV2_DISPATCH_REFUSED marker counts as a
  # refusal (safe to silently reroute); any other non-zero exit is a genuine
  # launcher failure.
  if [[ -n "${marker}" && ( "${rc}" == "1" || "${rc}" == "2" \
        || ( "${arm}" == "kimi" && "${rc}" == "77" ) \
        || ( ( "${arm}" == "glm" || "${arm}" == "glm-flash" ) && "${rc}" == "75" ) \
        || ( "${arm}" == "freepool" && "${rc}" == "75" ) ) ]]; then
    printf '%s' "${marker}"
    return 0
  fi
  # Compatibility only for older GLM quota gates.  Source gates now emit the marker.
  # GLM-53-FLASH-ARM-01: glm-flash shares the glm launcher, so it shares these
  # glm admission contracts (quota gate, per-repo portable lock) verbatim.
  if [[ ( "${arm}" == "glm" || "${arm}" == "glm-flash" ) && "${rc}" == "1" && "${combined}" == *"[glm-quota-gate] REROUTE"* ]]; then
    printf '%s' quota_gate
    return 0
  fi
  # N1-EMPTY-LANE-IS-NOT-A-PASS (B.1): legacy-compat shim for a glm launcher build
  # that predates the LEADV2_DISPATCH_REFUSED: lock_busy marker. The portable-lock
  # path exits 75 with a plain-English "another GLM run is active for this repo"
  # message; without this it was mis-typed as a launcher crash (spawn_failed ...
  # launcher_nonzero_exit) and blind-spilled to kimi. The marker is the contract;
  # this narrow string match is the back-compat belt -- comment-tagged like the
  # REROUTE shim above.
  if [[ ( "${arm}" == "glm" || "${arm}" == "glm-flash" ) && "${rc}" == "75" \
        && "${combined}" == *"another GLM run is active for this repo"* ]]; then
    printf '%s' lock_busy
    return 0
  fi
  return 1
}

_spawn_worker_body() {
  local arm="$1" mission="$2" sig8="$3" errf="$4"
  local out rc handle err
  # LANE-PLACEMENT-01: prepend the worktree pin line ONCE here — covers all four arms
  # (glm/kimi/sonnet/codex) with a single insertion, no per-arm drift.  Prepended AFTER
  # compute_sig/classify/router so sig8, dedup ledger, and routing are byte-identical with
  # or without a flag (prepending before compute_sig would change sig8 and defeat dedup).
  # CLAIM-EVIDENCE-GATE-01 round 2 (H2): prepend the evidence-contract text to every
  # non-claude arm's mission, same placement invariant as WORKTREE_PIN_LINE above --
  # AFTER compute_sig/classify/router so sig8, the dedup ledger, and routing stay
  # byte-identical. Order: pin line first (its own comment requires that), then the
  # contract, then the mission body. Round 1 shipped the review-side rule
  # (leadv2-review-run.sh blocks untagged claims) with no reader on the writing side
  # for glm/kimi/codex -- this closes that gap. leadv2-helpers.sh is sourced with
  # `|| true` above; guard non-empty and never fail open silently (that shape is H1).
  if [[ -n "${_LEADV2_FOREGROUND_CONTRACT_MISSION:-}" ]]; then
    mission="${_LEADV2_FOREGROUND_CONTRACT_MISSION}"$'\n\n'"${mission}"
  else
    log_err "_LEADV2_FOREGROUND_CONTRACT_MISSION unavailable (leadv2-helpers.sh not sourced?) — falling back to embedded literal"
    mission="FOREGROUND WORK CONTRACT: never end a turn while a job you started is still running. Run verification in the FOREGROUND with an explicit timeout. If a job must run detached, wait for it and report its result in the SAME turn before finishing. Standing by, waiting for, or will report when it completes is a protocol violation, not a completion."$'\n\n'"${mission}"
  fi
  if [[ -n "${_LEADV2_EVIDENCE_CONTRACT_MISSION:-}" ]]; then
    mission="${_LEADV2_EVIDENCE_CONTRACT_MISSION}"$'\n\n'"${mission}"
  else
    log_err "_LEADV2_EVIDENCE_CONTRACT_MISSION unavailable (leadv2-helpers.sh not sourced?) — falling back to embedded literal"
    mission="EVIDENCE CONTRACT: every factual claim about an external system or API needs a probe artifact; if you have none, prefix the claim with UNVERIFIED: — an untagged evidence-free external-system claim is a protocol violation."$'\n\n'"${mission}"
  fi
  [[ -z "${WORKTREE_PIN_LINE:-}" ]] || mission="${WORKTREE_PIN_LINE}"$'\n\n'"${mission}"
  case "${arm}" in
    glm|glm-flash)
      # GLM-53-FLASH-ARM-01: glm-flash is the same launcher (glm-coder.sh) on
      # the glm-5.3-flash model -- one case row, model selected through the
      # wrapper's GLM_MODEL env seam so the spawn argv never forks per model.
      # Default arm=glm leaves GLM_MODEL unset so the wrapper's own
      # glm-5.3 default holds (single source of model truth stays in the
      # wrapper + the routing yaml's ladder/matrix, never here).
      local _glm_model=""
      if [[ "${arm}" == "glm-flash" ]]; then
        _glm_model="glm-5.3-flash"
      fi
      # FIX PASS 4: `9>&-` closes the lock fd for this call as defense-in-depth -- the
      # redesign already never holds the dispatch lock across spawn (spawn_worker runs
      # outside any lock this script itself opens), but a launcher spawns a DETACHED
      # background worker (setsid_wrapper+disown) that would otherwise inherit ANY fd 9
      # left open by an outer caller (e.g. this script invoked from inside another
      # script's own fd-9 flock scope) and keep that lock held for the worker's lifetime
      # -- exactly the bug this redesign fixes (see FIX PASS 4 doc block).
      # The GLM wrapper owns the terminal JSON envelope and invokes the shared
      # dev cost shim only after it exists.  Stamp this dispatch identity here
      # so direct and dispatcher-launched lanes use one attribution contract.
      out="$(LEADV2_COSTLOG_ARM="glm-coder:${arm}" LEADV2_WORKER_ROLE=developer GLM_MODEL="${_glm_model}" bash "${GLM_BIN}" bg "${mission}" --cwd "${WORK_ROOT}" 2>"${errf}" 9>&-)"; rc=$?
      err="$(tail -20 "${errf}" 2>/dev/null)"
      if [[ ${rc} -ne 0 ]]; then
        local refusal
        refusal="$(refusal_reason "${arm}" "${rc}" "${out}" "${err}" || true)"
        if [[ -n "${refusal}" ]]; then
          LAST_ARM_OUTCOME="glm_refused_${refusal}"
          emit decision "arm_refused by=router model=${arm} task=${sig8} reason=glm_refused_${refusal}"
          _maybe_record_quota_lockout "glm" "${refusal}" "${out}"$'\n'"${err}"
          log "spawn(${arm}) refused: ${refusal}"
          return 2
        fi
        emit decision "spawn_failed by=router model=${arm} task=${sig8} rc=${rc} reason=launcher_nonzero_exit"
        log_err "spawn(${arm}) failed rc=${rc}: ${out} ${err}"
        return 1
      fi
      handle="$(printf '%s\n' "${out}" | tail -1)"
      # FIX PASS 2 (Finding 2, fake-launcher/empty-handle no-op): a launcher that exits
      # 0 without spawning anything (e.g. LEADV2_DISPATCH_GLM_BIN=/bin/true) must not be
      # treated as a live worker.
      if [[ -z "${handle}" ]]; then
        emit decision "spawn_failed by=router model=${arm} task=${sig8} reason=empty_handle"
        log_err "spawn(${arm}) returned an empty handle -- treating as launch failure (no-op launcher?)"
        return 1
      fi
      # Liveness: glm-coder.sh's own `status` subcommand resolves the SAME run-dir this
      # `bg` call used (its RUNS_DIR logic, not duplicated here); no live run record for
      # the handle means no live worker -- the run-id itself isn't a PID, so this is the
      # glm-arm equivalent of the kill -0 check below.
      if ! bash "${GLM_BIN}" status "${handle}" >/dev/null 2>&1 9>&-; then
        emit decision "spawn_failed by=router model=${arm} task=${sig8} handle=${handle} reason=not_live"
        log_err "spawn(${arm}) handle=${handle} has no live run record -- treating as launch failure"
        return 1
      fi
      ;;
    kimi)
      # KIMI-CHANNEL-01: sibling of the glm case above, same bg/status contract
      # (kimi-coder.sh is a clone of glm-coder.sh). The only launcher-specific
      # difference is its launch-probe refusal rc (77, vs. glm's 1/2) --
      # refusal_reason() already knows about that distinction.
      out="$(bash "${KIMI_BIN}" bg "${mission}" --cwd "${WORK_ROOT}" 2>"${errf}" 9>&-)"; rc=$?
      err="$(tail -20 "${errf}" 2>/dev/null)"
      if [[ ${rc} -ne 0 ]]; then
        local refusal
        refusal="$(refusal_reason "${arm}" "${rc}" "${out}" "${err}" || true)"
        if [[ -n "${refusal}" ]]; then
          LAST_ARM_OUTCOME="kimi_refused_${refusal}"
          emit decision "arm_refused by=router model=kimi task=${sig8} reason=kimi_refused_${refusal}"
          _maybe_record_quota_lockout "kimi" "${refusal}" "${out}"$'\n'"${err}"
          log "spawn(kimi) refused: ${refusal}"
          return 2
        fi
        emit decision "spawn_failed by=router model=kimi task=${sig8} rc=${rc} reason=launcher_nonzero_exit"
        log_err "spawn(kimi) failed rc=${rc}: ${out} ${err}"
        return 1
      fi
      handle="$(printf '%s\n' "${out}" | tail -1)"
      if [[ -z "${handle}" ]]; then
        emit decision "spawn_failed by=router model=kimi task=${sig8} reason=empty_handle"
        log_err "spawn(kimi) returned an empty handle -- treating as launch failure (no-op launcher?)"
        return 1
      fi
      # Liveness: same shape as the glm arm's check above -- kimi-coder.sh's
      # own `status` subcommand resolves the same run-dir this `bg` call used.
      if ! bash "${KIMI_BIN}" status "${handle}" >/dev/null 2>&1 9>&-; then
        emit decision "spawn_failed by=router model=kimi task=${sig8} handle=${handle} reason=not_live"
        log_err "spawn(kimi) handle=${handle} has no live run record -- treating as launch failure"
        return 1
      fi
      ;;
    freepool)
      # T19: sibling of the glm case above, same bg/status contract
      # (freepool-coder.sh is a clone of glm-coder.sh, pointed at the local
      # freepool-proxy.sh). Launch-probe refusal comes from its own
      # leadv2-freepool-gate.sh (marker + rc 1 for gate_broken/arm_down, or rc
      # 75 for the inherited lock_busy path) -- refusal_reason() already knows
      # about both.
      local _fp_spawn_start _fp_spawn_ok=0
      _fp_spawn_start="$(date +%s)"
      # PHASE-DISCIPLINE-01 D6 (a38a5bd fix): export FREEPOOL_ROLE HERE, at
      # the real dispatch call site, from the admission TaskEstimate's
      # work_kind (review->review, build/diagnose->implement, docs->bulk).
      # The mission-text regex inside freepool-coder.sh is demoted to a narrow
      # DIRECT-invocation fallback and must not be the live path for dispatched
      # missions. DISPATCH_FREEPOOL_ROLE is empty on the advance-arm path (no
      # estimate) and on classifier_error -- export nothing there.
      if [[ -n "${DISPATCH_FREEPOOL_ROLE:-}" ]]; then
        emit decision "freepool_select role=${DISPATCH_FREEPOOL_ROLE} task=${sig8} source=work_kind"
        out="$(FREEPOOL_ROLE="${DISPATCH_FREEPOOL_ROLE}" bash "${FREEPOOL_BIN}" bg "${mission}" --cwd "${WORK_ROOT}" 2>"${errf}" 9>&-)"; rc=$?
      else
        out="$(bash "${FREEPOOL_BIN}" bg "${mission}" --cwd "${WORK_ROOT}" 2>"${errf}" 9>&-)"; rc=$?
      fi
      err="$(tail -20 "${errf}" 2>/dev/null)"
      if [[ ${rc} -ne 0 ]]; then
        local refusal
        refusal="$(refusal_reason "${arm}" "${rc}" "${out}" "${err}" || true)"
        if [[ -n "${refusal}" ]]; then
          LAST_ARM_OUTCOME="freepool_refused_${refusal}"
          emit decision "arm_refused by=router model=freepool task=${sig8} reason=freepool_refused_${refusal}"
          _maybe_record_quota_lockout "freepool" "${refusal}" "${out}"$'\n'"${err}"
          log "spawn(freepool) refused: ${refusal}"
          return 2
        fi
        emit decision "spawn_failed by=router model=freepool task=${sig8} rc=${rc} reason=launcher_nonzero_exit"
        log_err "spawn(freepool) failed rc=${rc}: ${out} ${err}"
        bash "${SCRIPT_DIR}/lib/leadv2-freepool-gate.sh" record 0 "$(( $(date +%s) - _fp_spawn_start ))" 2>/dev/null || true
        return 1
      fi
      handle="$(printf '%s\n' "${out}" | tail -1)"
      if [[ -z "${handle}" ]]; then
        emit decision "spawn_failed by=router model=freepool task=${sig8} reason=empty_handle"
        log_err "spawn(freepool) returned an empty handle -- treating as launch failure (no-op launcher?)"
        return 1
      fi
      # Liveness: same shape as the glm arm's check above -- freepool-coder.sh's
      # own `status` subcommand resolves the same run-dir this `bg` call used.
      if ! bash "${FREEPOOL_BIN}" status "${handle}" >/dev/null 2>&1 9>&-; then
        emit decision "spawn_failed by=router model=freepool task=${sig8} handle=${handle} reason=not_live"
        log_err "spawn(freepool) handle=${handle} has no live run record -- treating as launch failure"
        bash "${SCRIPT_DIR}/lib/leadv2-freepool-gate.sh" record 0 "$(( $(date +%s) - _fp_spawn_start ))" 2>/dev/null || true
        return 1
      fi
      _fp_spawn_ok=1
      bash "${SCRIPT_DIR}/lib/leadv2-freepool-gate.sh" record "${_fp_spawn_ok}" "$(( $(date +%s) - _fp_spawn_start ))" 2>/dev/null || true
      ;;
    sonnet)
      local mfile
      mfile="$(mktemp "${TMPDIR:-/tmp}/leadv2-dispatch-mission.XXXXXX")" || {
        log_err "spawn(sonnet): could not create mission tempfile"; return 1
      }
      printf '%s' "${mission}" > "${mfile}"
      # FIX PASS 4: same `9>&-` defense-in-depth as the glm arm above -- claude-subsession.sh
      # without --wait: setsid_wrapper detaches the backgrounded `claude` worker itself
      # (SD-SONNET-ARM-DETACH-01), a DETACHED worker that would otherwise
      # inherit any inherited fd 9.
      # LANDING-BLOCKER-R2 (C1): claude-subsession.sh takes no --cwd flag and relies on
      # inherited $PWD; make that explicit (cd "${WORK_ROOT}") instead of relying on this
      # process having already been `cd`'d there by its caller -- same value glm/codex now
      # get via --cwd, so all three arms are cwd-independent of how dispatch-code.sh itself
      # was invoked.
      out="$(cd "${WORK_ROOT}" && PROJECT_ROOT="${PROJECT_ROOT}" bash "${SUBSESSION_BIN}" \
             --role developer --model sonnet \
             --task-id "dispatch-${sig8}" --mission-file "${mfile}" 2>"${errf}" 9>&-)"; rc=$?
      rm -f "${mfile}"
      err="$(tail -20 "${errf}" 2>/dev/null)"
      if [[ ${rc} -ne 0 ]]; then
        local refusal
        refusal="$(refusal_reason "${arm}" "${rc}" "${out}" "${err}" || true)"
        if [[ -n "${refusal}" ]]; then
          LAST_ARM_OUTCOME="sonnet_refused_${refusal}"
          emit decision "arm_refused by=router model=sonnet task=${sig8} reason=sonnet_refused_${refusal}"
          _maybe_record_quota_lockout "sonnet" "${refusal}" "${out}"$'\n'"${err}"
          log "spawn(sonnet) refused: ${refusal}"
          return 2
        fi
        emit decision "spawn_failed by=router model=sonnet task=${sig8} rc=${rc} reason=launcher_nonzero_exit"
        log_err "spawn(sonnet) failed rc=${rc}: ${out} ${err}"
        return 1
      fi
      handle="$(printf '%s\n' "${out}" | tail -1)"
      if [[ -z "${handle}" ]]; then
        emit decision "spawn_failed by=router model=sonnet task=${sig8} reason=empty_handle"
        log_err "spawn(sonnet) returned an empty handle -- treating as launch failure (dry-run launcher?)"
        return 1
      fi
      # Liveness: claude-subsession.sh's handle line is `PID=<pid> LABEL=... SESSION_ID=...`
      # (no --wait path); kill -0 the forked PID -- a printed line alone is not proof the
      # process is actually alive.
      # FIX PASS 3 (High finding d): a handle with NO parseable `PID=` token used to fall
      # through this check untested and was accepted as live -- a launcher that prints any
      # non-empty, non-PID text (e.g. only `SESSION_ID=...`) passed the empty-handle guard
      # above and was then wrongly treated as a confirmed spawn. A PID is REQUIRED now; its
      # absence is itself a launch failure, not a skip.
      local pid
      pid="$(printf '%s\n' "${handle}" | sed -n 's/^PID=\([0-9][0-9]*\).*/\1/p')"
      if [[ -z "${pid}" ]]; then
        emit decision "spawn_failed by=router model=sonnet task=${sig8} handle=${handle} reason=no_pid_in_handle"
        log_err "spawn(sonnet) handle='${handle}' has no parseable PID= token -- treating as launch failure"
        return 1
      fi
      if ! kill -0 "${pid}" 2>/dev/null; then
        # PLUGIN-TOOLING-FIX-01 B: "not alive" alone is undiagnosable. The real cause
        # (e.g. `--output-format=stream-json requires --verbose`, see claude-subsession.sh
        # ~line 358-360) is the first line of the arm's own stream file. This is the
        # SAME path convention this file already uses for developer-role liveness at
        # ~line 1324/3262 (`docs/handoff/dispatch-${sig8}/developer.stream.jsonl`),
        # built from vars (PROJECT_ROOT, sig8) already in scope here -- not a new path.
        # Emit 3 lines max, 200 chars each -- never a stream dump.
        local _stream_file _cause
        _stream_file="${PROJECT_ROOT}/docs/handoff/dispatch-${sig8}/developer.stream.jsonl"
        if [[ ! -e "${_stream_file}" ]]; then
          _cause="<no stream file at ${_stream_file}>"
        elif [[ ! -s "${_stream_file}" ]]; then
          _cause="<stream file empty: ${_stream_file}>"
        else
          _cause="$(grep -v '^[[:space:]]*$' "${_stream_file}" 2>/dev/null | head -3 \
                    | cut -c1-200 | tr '\n' '|' | tr -s ' ')"
        fi
        emit decision "spawn_failed by=router model=sonnet task=${sig8} handle=${handle} reason=not_live cause=${_cause}"
        log_err "spawn(sonnet) pid=${pid} is not alive -- treating as launch failure; first stream lines: ${_cause}"
        return 1
      fi
      # LANE-REGISTRY-SELF-DEADLOCK-01 Defect 1: stamp the WORKER's pid + birth
      # onto this lane's active.yaml row, AFTER the spawn is proven live. The
      # row itself was registered pre-spawn with the LEAD session's durable pid
      # (pid_role=lead_durable); without this stamp liveness trusts the lead's
      # pid forever and a dead worker's lane can never be reclaimed. A file
      # write escapes this command-substitution subshell (same as
      # _dispatch_register_arm below). Guarded on DISPATCH_REG_ID: the
      # cmd_advance_arm path never sets it -- prefer skip over guessing the row
      # (design R5). `|| true` + explicit `set +e`: the sourced registry re-
      # asserts -e and a stamp failure must never kill the dispatch (E2E-GATE-
      # RESIDUE-01 round 4 root cause).
      if [[ -n "${DISPATCH_REG_ID:-}" ]] && declare -F leadv2_active_set_worker_pid >/dev/null 2>&1; then
        set +e
        local _wpid_birth
        _wpid_birth="$(_lv2_pid_birth "${pid}" 2>/dev/null || printf '')"
        LEADV2_PROJECT_ROOT="${PROJECT_ROOT}" leadv2_active_set_worker_pid \
          "${DISPATCH_REG_ID}" "${pid}" "${_wpid_birth}" >/dev/null 2>&1 || true
        declare -F lane_adopt_pid >/dev/null 2>&1 && \
          lane_adopt_pid "${DISPATCH_REG_ID}" "${DISPATCH_LEAD_SESSION_ID:-direct}" "${WORK_ROOT:-${PROJECT_ROOT}}" "build" "${pid}" >/dev/null 2>&1 || true
      fi
      ;;
    codex)
      # CODEX arm (ROUTING-ENFORCEMENT-01): launch through the sanctioned codex-task.sh
      # channel only -- `task ... --background` detaches its own job (codex-companion's
      # enqueueBackgroundTask, not something this script spawns/detaches itself) and prints
      # "<title> started in the background as <jobId>." on stdout; codex-task.sh's own
      # CODEX-NEVER-LOSE-01 guard already arms a watcher for that job, this script only
      # needs the jobId back. RESOLVED_CODEX_TIER is set by cmd_resolve from the yaml's
      # glm_policy.codex_default_tier (or defaults to "standard" if unset/empty).
      local tier="${RESOLVED_CODEX_TIER:-standard}"
      local tier_args=(--tier "${tier}")
      # --tier top is gated on --reason by codex-task.sh itself; this router only ever
      # resolves "standard" from the yaml today, but honor a manually-forced top without
      # hard-failing the spawn.
      [[ "${tier}" == "top" ]] && tier_args+=(--reason "leadv2-dispatch-code: codex-fitting mission")
      # `9>&-` closes the lock fd for this call as defense-in-depth -- same rationale as
      # the glm/sonnet arms above: codex-task.sh's --background path detaches a job worker
      # that must never inherit an open fd 9.
      out="$(bash "${CODEX_BIN}" task "${mission}" --background --cwd "${WORK_ROOT}"              "${tier_args[@]}" 2>"${errf}" 9>&-)"; rc=$?
      err="$(tail -20 "${errf}" 2>/dev/null)"
      if [[ ${rc} -ne 0 ]]; then
        local refusal
        refusal="$(refusal_reason "${arm}" "${rc}" "${out}" "${err}" || true)"
        if [[ -n "${refusal}" ]]; then
          LAST_ARM_OUTCOME="codex_refused_${refusal}"
          emit decision "arm_refused by=router model=codex task=${sig8} reason=codex_refused_${refusal}"
          _maybe_record_quota_lockout "codex" "${refusal}" "${out}"$'\n'"${err}"
          log "spawn(codex) refused: ${refusal}"
          return 2
        fi
        emit decision "spawn_failed by=router model=codex task=${sig8} rc=${rc} reason=launcher_nonzero_exit"
        log_err "spawn(codex) failed rc=${rc}: ${out} ${err}"
        return 1
      fi
      # jobId format: <task|review>-<base36-timestamp>-<random6> -- same regex
      # codex-task.sh's own CODEX-NEVER-LOSE-01 guard uses to parse its background output.
      handle="$(printf '%s
' "${out}" | grep -oE '(task|review)-[a-z0-9]+-[a-z0-9]+' | head -1)"
      if [[ -z "${handle}" ]]; then
        emit decision "spawn_failed by=router model=codex task=${sig8} reason=empty_handle"
        log_err "spawn(codex) returned no parseable jobId -- treating as launch failure (no-op launcher?)"
        return 1
      fi
      # Liveness: codex-task.sh's own `status <jobId>` resolves the SAME job registry
      # `task --background` just wrote to (codex-companion's buildSingleJobSnapshot) --
      # it exits non-zero ("No job found for ...") when the id is unknown, so this is the
      # codex-arm equivalent of the glm arm's `status` check / the sonnet arm's `kill -0`.
      if ! bash "${CODEX_BIN}" status "${handle}" >/dev/null 2>&1 9>&-; then
        emit decision "spawn_failed by=router model=codex task=${sig8} handle=${handle} reason=not_live"
        log_err "spawn(codex) handle=${handle} has no live job record -- treating as launch failure"
        return 1
      fi
      ;;
    *)
      log_err "spawn_worker: unsupported arm for spawn: ${arm}"
      return 1
      ;;
  esac
  # SD-LEDGER-SWEEP-HARDEN-01: this process's own attempt token (_dl_attempt_token, LOW-2:
  # qualified <sig8>-<epoch>-<pid>, never a bare pid) is ALREADY what _dl_note passes to the
  # terminal ledger's write-terminal (see that function's own doc comment above) --
  # printed on stdout here too so a synchronous caller (leadv2-fanout.sh's single-worker
  # funnel, which captures this whole stdout as dc_out) can stamp the SAME token onto the
  # lane's active.yaml row via leadv2_active_set_attempt, letting the dispatch-ledger sweep
  # later attribute a dead verdict to the EXACT attempt that died, not the sig8 as a whole.
  # attempt=<token> is placed BEFORE handle= on the stdout line, never after: fanout.sh's
  # handle extraction (`sed -n 's/.*handle=\(.*\)$/\1/p'`) captures to END OF LINE, so a
  # field appended after handle= would get swallowed into the captured handle string.
  local _spawn_attempt; _spawn_attempt="$(_dl_attempt_token "${sig8}")"
  emit decision "worker_spawned by=router model=${arm} task=${sig8} attempt=${_spawn_attempt} handle=${handle}"
  _emit_event worker_spawned "${sig8}" "${arm}" "${handle}"
  printf 'worker_spawned model=%s task=%s attempt=%s handle=%s\n' "${arm}" "${sig8}" "${_spawn_attempt}" "${handle}"
  # ARM-PRODUCES-NOTHING-02: record the arm registration so the close gate's silent-arm
  # probe can distinguish "arm was spawned but wrote nothing" from "no arm was ever spawned".
  # This one site covers BOTH the router path and cmd_advance_arm (both call spawn_worker ->
  # _spawn_worker_body).  A file write escapes this command-substitution subshell.
  _dispatch_register_arm "${sig8}" "${arm}" "${handle}"
  # MON-PULSE-01: this one choke point (router + arm_advance) arms the
  # dispatcher-owned lane watch for THIS sig and the single-lead beat loop.
  # Fail-open; the watchers own their own pidfile/replay-safety semantics.
  _arm_lane_pulse_watch "${sig8}"
  _arm_single_lead_beat
  # S7-RETARGET-PERSIST-01: names which mission version this dispatch launched, so
  # "it relaunched the old premise" is a grep of this log, not archaeology. Fail-open
  # by construction: sig/head are already-in-hand local values (no failure mode), rev
  # is env-passed only (task-retarget.sh --json prints `export LEADV2_MISSION_REV=<n>`
  # for a retarget-then-dispatch sequence to carry) -- never a DB call in this hot path.
  emit decision "mission-version task=${founder_task_id:--} sig=${sig8} rev=${LEADV2_MISSION_REV:-?} head=\"$(printf '%s' "${mission}" | tr '\n' ' ' | cut -c1-90)\""
  return 0
}

# ── CODEX-QUOTA-LOCKOUT-NEVER-FIRES-FOR-CODEX-01: generic post-spawn verdict seam ──
# Root cause this section fixes: codex's launcher (codex-task.sh ... --background)
# exits 0 the instant the job is ENQUEUED, so _maybe_record_quota_lockout (called only
# from the `rc -ne 0` refusal branch above) never runs for codex even when the job later
# dies from a quota error inside its own detached job log. The functions below poll the
# launcher's OWN status/output verb for a bounded window right after spawn -- same idea
# KIMI-CHANNEL-REHAB-01 already used for kimi's async no-work verdict, generalized so it
# is available to every arm that has a status verb, without ever hardcoding an arm name
# into ELIGIBILITY/ROUTING logic. Per-arm knowledge is confined to the small adapter
# functions below (how do I ask THIS launcher for status/output) -- never "should this
# arm be tried", which stays the router's job alone.

# _arm_status_probe <arm> <handle> -> raw status text on stdout, rc0.
# rc1 when this arm has no async status adapter (sonnet/opus are a bare PID, nothing to
# poll) -- callers must treat rc1 exactly like state=unknown, i.e. proceed as before this
# fix existed. Bounded by `timeout 10` so a hanging launcher can never block dispatch.
_arm_status_probe() {  # <arm> <handle>
  local arm="$1" handle="$2" bin=""
  case "${arm}" in
    codex)    bin="${CODEX_BIN}" ;;
    kimi)     bin="${KIMI_BIN}" ;;
    glm)      bin="${GLM_BIN}" ;;
    freepool) bin="${FREEPOOL_BIN}" ;;
    *)     return 1 ;;
  esac
  [[ -n "${bin}" && -f "${bin}" ]] || return 1
  timeout 10 bash "${bin}" status "${handle}" 2>/dev/null
  return 0
}

# _arm_status_state <arm> <raw_text> -> echoes running|complete|failed|unknown.
# Deliberately arm-agnostic text parsing (no arm branch here) -- reads the same
# `status:` line shape KIMI-CHANNEL-REHAB-01's poller already relied on, and falls back
# to a bare terminal-state word for launchers (codex's cross-workspace status fallback)
# that render `<id> <status> <phase> ...` instead. Unrecognized text -> unknown, NEVER
# failed -- an adapter must never manufacture a false-dead verdict out of noise.
_arm_status_state() {  # <arm> <raw_text>
  local raw="$2" line
  line="$(printf '%s\n' "${raw}" | sed -n 's/^status:[[:space:]]*//p' | tail -1)"
  line="$(printf '%s' "${line}" | tr -d '"'\''' | tr '[:upper:]' '[:lower:]' | tr -d '[:space:]')"
  if [[ -z "${line}" ]]; then
    if printf '%s' "${raw}" | grep -qiE '(^|[^a-z])(failed|error|crashed)([^a-z]|$)'; then
      line="failed"
    elif printf '%s' "${raw}" | grep -qiE '(^|[^a-z])(complete|completed|success|succeeded|done)([^a-z]|$)'; then
      line="complete"
    elif printf '%s' "${raw}" | grep -qiE '(^|[^a-z])(running|queued|in_progress|inprogress|pending)([^a-z]|$)'; then
      line="running"
    fi
  fi
  case "${line}" in
    failed|error|crashed)                              printf 'failed\n' ;;
    complete|completed|success|succeeded|done)          printf 'complete\n' ;;
    running|queued|in_progress|inprogress|pending)       printf 'running\n' ;;
    *)                                                   printf 'unknown\n' ;;
  esac
}

# _arm_no_work_signal <arm> <raw_text> -> rc0 when this raw text is THIS arm's own
# "ran, found nothing to do" terminal marker (never a quota-shaped failure). Preserves
# KIMI-CHANNEL-REHAB-01's exact channel_outcome=no_work / exit_code=78 contract; every
# other arm has no such channel, so rc1 unconditionally.
_arm_no_work_signal() {  # <arm> <raw_text>
  local arm="$1" raw="$2" status exit_code channel_outcome
  case "${arm}" in
    kimi) ;;
    *) return 1 ;;
  esac
  status="$(printf '%s\n' "${raw}" | sed -n 's/^status:[[:space:]]*//p' | head -1)"
  exit_code="$(printf '%s\n' "${raw}" | sed -n 's/^exit_code:[[:space:]]*//p' | head -1)"
  channel_outcome="$(printf '%s\n' "${raw}" | sed -n 's/^channel_outcome:[[:space:]]*//p' | head -1)"
  [[ "${status}" == "failed" && "${exit_code}" == "78" && "${channel_outcome}" == "no_work" ]] || return 1
  return 0
}

# _arm_exit76_signal <arm> <raw_text> -> rc0 when this raw text is GLM's own
# GLM_FALLBACK_TO_SONNET terminal marker (T13-SLICE1 W3: glm-coder.sh writes
# `status: failed` + `exit_code: 76` in meta.yaml -- see finalize_meta / the
# two-sentinel contract -- when it produced no coherent result and wants the
# lane retried on a different arm; this is NEVER a quota-shaped failure and
# was previously falling through to the generic `failed` classifier, which
# has no quota marker to find and lets the lane die with no spill at all).
# Every other arm has no such receipt, so rc1 unconditionally.
_arm_exit76_signal() {  # <arm> <raw_text>
  local arm="$1" raw="$2" status exit_code
  case "${arm}" in
    glm) ;;
    *) return 1 ;;
  esac
  status="$(printf '%s\n' "${raw}" | sed -n 's/^status:[[:space:]]*//p' | head -1)"
  exit_code="$(printf '%s\n' "${raw}" | sed -n 's/^exit_code:[[:space:]]*//p' | head -1)"
  [[ "${status}" == "failed" && "${exit_code}" == "${GLM_FALLBACK_EXIT_CODE:-76}" ]] || return 1
  return 0
}

# _arm_final_output <arm> <handle> -> last LEADV2_ARM_TAIL_LINES (default 60) lines of
# the job's own log/output on stdout. Never fatal: empty output on any failure. Prefers
# a dedicated log/output verb (glm/kimi's `tail`, or a `log=<path>` field codex's status
# fallback already renders); falls back to the raw status text itself when neither is
# available (e.g. real codex-task.sh has no separate log verb on its happy path).
_arm_final_output() {  # <arm> <handle>
  local arm="$1" handle="$2" bin="" tail_n="${LEADV2_ARM_TAIL_LINES:-60}" raw logpath out
  case "${arm}" in
    codex)    bin="${CODEX_BIN}" ;;
    kimi)     bin="${KIMI_BIN}" ;;
    glm)      bin="${GLM_BIN}" ;;
    freepool) bin="${FREEPOOL_BIN}" ;;
    *)     return 0 ;;
  esac
  [[ -n "${bin}" && -f "${bin}" ]] || return 0
  # Prefer an explicit log verb (fakes used by tests, and any future real launcher verb).
  out="$(timeout 10 bash "${bin}" log "${handle}" 2>/dev/null)"
  if [[ -n "${out}" ]]; then
    printf '%s\n' "${out}" | tail -n "${tail_n}"
    return 0
  fi
  raw="$(timeout 10 bash "${bin}" status "${handle}" 2>/dev/null)"
  logpath="$(printf '%s\n' "${raw}" | sed -n 's/.*[[:space:]]log=\([^[:space:]]*\).*/\1/p' | tail -1)"
  if [[ -n "${logpath}" && -f "${logpath}" ]]; then
    tail -n "${tail_n}" "${logpath}" 2>/dev/null
    return 0
  fi
  out="$(timeout 10 bash "${bin}" tail "${handle}" 2>/dev/null)"
  if [[ -n "${out}" ]]; then
    printf '%s\n' "${out}" | tail -n "${tail_n}"
    return 0
  fi
  printf '%s\n' "${raw}" | tail -n "${tail_n}"
  return 0
}

# _quota_shaped "<text>" -> rc0 iff the text case-insensitively matches a PRIMARY
# quota-refusal pattern. A separate supporting-only pattern set (resets?/try again
# at|in|after) is NOT tested here -- it never triggers this classifier alone, it only
# helps _quota_return_time locate the reset-time substring once quota-shaped is true.
_quota_shaped() {  # <text>
  printf '%s' "$1" | grep -iE \
    'usage limit|quota (exceeded|exhausted|reached)|rate limit(ed)?|out of (credits|tokens|quota)|insufficient (credits|quota|balance)|too many requests|(^|[^0-9])429([^0-9]|$)|you.?ve hit your (usage|rate) limit' \
    >/dev/null 2>&1
}

# _quota_return_time "<text>" -> "<ISO>|<source>" on stdout, or nothing when the text
# has no parseable reset time. Thin wrapper around leadv2-quota-error-parse.py (pure
# stdin->stdout, always exits 0) -- lib path resolved the same way this file already
# resolves lib/leadv2-glm-policy-resolve.py (relative to SCRIPT_DIR, no ../ hop math).
_quota_return_time() {  # <text>
  local parser="${SCRIPT_DIR}/lib/leadv2-quota-error-parse.py"
  [[ -f "${parser}" ]] || return 0
  printf '%s' "$1" | python3 "${parser}" \
    --floor-minutes "${LEADV2_QUOTA_LOCKOUT_MINUTES:-30}" \
    --max-minutes "${LEADV2_QUOTA_LOCKOUT_MAX_MINUTES:-4320}" 2>/dev/null
}

# _arm_early_verdict_window <arm> -> the post-spawn poll window in seconds. Kimi keeps
# its own pre-existing override name (LEADV2_KIMI_VERDICT_WAIT_S, default 60, exactly
# as KIMI-CHANNEL-REHAB-01 set it) so no operator env is silently repointed by this
# refactor; every other arm uses the new generic LEADV2_ARM_EARLY_VERDICT_S (default 20).
_arm_early_verdict_window() {  # <arm>
  local arm="$1" w
  case "${arm}" in
    kimi) w="${LEADV2_KIMI_VERDICT_WAIT_S:-60}" ;;
    *)    w="${LEADV2_ARM_EARLY_VERDICT_S:-20}" ;;
  esac
  [[ "${w}" =~ ^[0-9]+$ ]] || w=20
  printf '%s' "${w}"
}

# _wait_arm_early_verdict <arm> <handle> <sig8> -> post-spawn verdict for the
# candidate-loop:
#   0  proceed as today (no adapter for this arm, still running/unknown at window
#      expiry, job completed, or a failure that is NOT quota-shaped -- an ordinary
#      failure is the close gate's problem, not a lockout)
#   7  quota-shaped failure -- a lockout was recorded (or attempted); spill to the
#      next candidate arm exactly like the existing rc=7 branch already does
#   78 arm-specific no-work terminal (currently only kimi's channel_outcome) --
#      UNCHANGED from the pre-existing kimi-only contract
#   76 GLM_FALLBACK_TO_SONNET receipt (T13-SLICE1 W3): glm-coder.sh's own
#      exit_code=76 two-sentinel contract -- ran, produced no coherent result,
#      wants THIS SAME lane retried on the next arm, never a quota lockout.
# Replaces the old hardcoded `if [[ "${arm}" == "kimi" ]]` call-site gate: this is now
# called unconditionally for every arm, and it no-ops safely (returns 0 promptly) for
# arms with no status adapter, since _arm_status_probe rc1 is treated as unknown.
_wait_arm_early_verdict() {  # <arm> <handle> <sig8>
  local arm="$1" handle="$2" sig8="$3"
  local timeout_s poll_s="${LEADV2_ARM_EARLY_VERDICT_POLL_S:-1}"
  timeout_s="$(_arm_early_verdict_window "${arm}")"
  [[ "${poll_s}" =~ ^[0-9]+([.][0-9]+)?$ ]] || poll_s=1
  [[ "${poll_s}" != "0" && "${poll_s}" != "0.0" ]] || poll_s=0.1
  # Kill switch: an explicit 0 (either the arm-specific or generic override) skips the
  # wait entirely and proceeds exactly as dispatch did before this fix existed.
  [[ "${timeout_s}" != "0" ]] || return 0

  local started="${SECONDS}" raw state
  while true; do
    raw="$(_arm_status_probe "${arm}" "${handle}")" || raw=""
    if _arm_no_work_signal "${arm}" "${raw}"; then
      return 78
    fi
    if _arm_exit76_signal "${arm}" "${raw}"; then
      return 76
    fi
    state="$(_arm_status_state "${arm}" "${raw}")"
    case "${state}" in
      complete)
        return 0
        ;;
      failed)
        # PROVIDER-LOCKOUT-FALSE-BLOCK-01: the tail is CLASSIFIED first, and a
        # quota marker no longer outranks a kill/infra marker (the 05:49Z
        # incident: a killed worker whose 60-line tail still carried one
        # earlier, survived 429 retry line benched GLM for 24h). Unclassified
        # => no record at all (today's non-quota behaviour, preserved).
        local final_out _plo _plo_rc _pcls _pmin _pstrikes _psrc _piso _pev
        final_out="$(_arm_final_output "${arm}" "${handle}")"
        _plo="$(_record_postspawn_lockout "${arm}" "${final_out}")" && _plo_rc=0 || _plo_rc=1
        IFS='|' read -r _pcls _pmin _pstrikes _psrc _piso _pev <<<"${_plo}"
        if [[ "${_plo_rc}" != "0" || "${_pcls}" == "unclassified" ]]; then
          emit decision "arm_postspawn_verdict arm=${arm} state=failed quota=no"
          emit decision "arm_failure_classified arm=${arm} site=postspawn class=unclassified evidence=${_pev} lockout=none"
          return 0
        fi
        local _reason="postspawn_${_pcls}"
        [[ "${_pcls}" == "provider_refusal" ]] && _reason="postspawn_quota"
        emit decision "quota_lockout_recorded provider=$(_arm_provider "${arm}") arm=${arm} reason=${_reason} class=${_pcls} minutes=${_pmin} strikes=${_pstrikes} source=${_psrc} until=${_piso}"
        return 7
        ;;
      running|unknown)
        : # fall through to the timeout check below
        ;;
    esac
    if (( SECONDS - started >= timeout_s )); then
      return 0
    fi
    sleep "${poll_s}"
  done
}

# CODEX-DOOR-DEAD-01 §2 mitigation: a first-byte deadline for the codex BUILDER arm
# only. `task ... --background` (spawn_worker's codex branch) returns rc0 the instant
# codex-companion's enqueueBackgroundTask ACCEPTS the job -- nothing upstream of this
# proves the job actually STARTED producing output. leading hypothesis H3 (a job
# accepted and then never run -- worker not draining the queue, or dying before its
# first write) would present exactly as the four dead lanes did: valid jobId,
# waiting_worker forever, zero bytes, no stream. The reproduction run for this task
# (trivial task, --background --cwd <scratch>) did NOT trigger H3 -- the runtime was
# healthy and the first byte landed in well under 15s -- so this is a bounded,
# observable SAFETY NET for a fault this pass could not reproduce live, not a
# confirmed fix. Default 180s (LEADV2_CODEX_FIRST_BYTE_SECS) converts a 20-minute
# silent hang into a bounded, self-healing spill instead of leaving the close loop to
# poll waiting_worker indefinitely.
#
# _codex_first_byte_probe <handle> -> rc0 iff codex-companion's own `log <handle>`
# verb (the SAME verb _arm_final_output prefers) returns non-empty text. Deliberately
# does NOT fall back to the raw `status` text the way _arm_final_output does -- a
# live job always has SOME status text, so that fallback would make this probe
# report "first byte" on every enqueued-but-silent job, defeating the whole point.
_codex_first_byte_probe() {  # <handle>
  local handle="$1" out
  out="$(timeout 10 bash "${CODEX_BIN}" log "${handle}" 2>/dev/null)"
  [[ -n "${out}" ]]
}

# _codex_first_byte_deadline_check <handle> <sig8> -> 0 = proceed (byte already
# landed, or the deadline is disabled via LEADV2_CODEX_FIRST_BYTE_SECS=0), 7 =
# declared dead (no byte within the deadline) -- caller must abort the reservation
# and spill to the next candidate arm, exactly like the existing postspawn-quota
# rc=7 branch. On declaring dead, stands codex down for a bounded window via the
# CODEX-DOOR-DEAD-01 §3 stand-down mode (never the quota-classification mode --
# there is no launcher output to classify here, only silence).
_codex_first_byte_deadline_check() {  # <handle> <sig8>
  local handle="$1" sig8="$2"
  local deadline="${LEADV2_CODEX_FIRST_BYTE_SECS:-180}"
  [[ "${deadline}" =~ ^[0-9]+$ ]] || deadline=180
  [[ "${deadline}" != "0" ]] || return 0
  local poll_s="${LEADV2_ARM_EARLY_VERDICT_POLL_S:-1}"
  [[ "${poll_s}" =~ ^[0-9]+([.][0-9]+)?$ ]] || poll_s=1
  [[ "${poll_s}" != "0" && "${poll_s}" != "0.0" ]] || poll_s=0.1
  local started="${SECONDS}"
  while true; do
    if _codex_first_byte_probe "${handle}"; then
      return 0
    fi
    if (( SECONDS - started >= deadline )); then
      emit decision "arm_dead_no_first_byte arm=codex task=${sig8} job=${handle}"
      bash "${DISPATCH_SELF_BIN:-${SCRIPT_DIR}/leadv2-dispatch-code.sh}" record-quota-lockout \
        --provider codex --hours 1 --reason arm_dead_no_first_byte >/dev/null 2>&1 || true
      return 7
    fi
    sleep "${poll_s}"
  done
}

# SD-CODEX-SILENT-INSTANT-COMPLETE-01: a codex rollout can pass the first-byte
# check above (it wrote real bytes -- observed ~100KB of context in the live
# incident) and STILL be dead: codex-companion emits a `task_complete` event
# with `last_agent_message: null` within 1-3s of `task_started` and detaches.
# No prior guard catches this shape because bytes DID land. Live probe of the
# exact dead event (this session, 2026-08-20):
#   {"timestamp":"2026-08-20T02:22:58.199Z","type":"event_msg","payload":
#    {"type":"task_complete","turn_id":"01a01cfa-8ccd-7101-bdd7-b1c4cec4af81",
#     "last_agent_message":null,"completed_at":1787192578,"duration_ms":946}}
#   (from ~/.codex/sessions/2026/08/20/rollout-2026-08-20T05-22-53-...jsonl)
#
# _codex_newest_rollout_since <since_epoch> <expected_cwd> -> prints the
# best-guess ~/.codex/sessions/**/rollout-*.jsonl path with mtime >=
# since_epoch on line 1, then the TOTAL count of mtime-window candidates
# (regardless of cwd match) on line 2, for the caller to journal an
# ambiguity warning on. Uses python3 (already a hard dependency elsewhere
# in this script) instead of `find -newermt`, which BSD/bfs `find` on this
# host does not reliably support the same way GNU find does.
# nit 2-A (V3-ENV-GUARDS-01 review): a bare mtime scan of the whole
# $CODEX_HOME/sessions tree can be judged by a SIBLING dispatch's rollout
# (two codex arms in different lanes, same host, overlapping window).
# session_meta.cwd (recorded by codex at session start) is a HARD filter when
# expected_cwd is known (round-1 HIGH fix): a concurrent sibling dispatch's
# rollout can otherwise be picked as "newest of the whole window" and its
# turn_aborted/null-message shape then kills THIS dispatch. Falling back to
# "newest of anyone" is only safe when the caller has no cwd to scope by at
# all (expected_cwd empty) -- with a known expected_cwd and zero exact
# matches (own rollout not written yet, or a path-spelling mismatch), the
# correct behaviour is "no candidate", not "guess a stranger's". The total
# window count is still reported (from ALL candidates, matched or not) so
# the caller can journal ambiguity whenever it is > 1.
_codex_newest_rollout_since() {  # <since_epoch> <expected_cwd>
  local since="$1" expected_cwd="$2" codex_home
  codex_home="${CODEX_HOME:-$HOME/.codex}"
  python3 - "$codex_home" "$since" "$expected_cwd" 2>/dev/null <<'PY'
import json, os, sys
root = os.path.join(sys.argv[1], "sessions")
since = int(sys.argv[2])
expected_cwd = sys.argv[3]
candidates = []  # (mtime, path, cwd)
for dirpath, _dirnames, filenames in os.walk(root):
    for fn in filenames:
        if not (fn.startswith("rollout-") and fn.endswith(".jsonl")):
            continue
        p = os.path.join(dirpath, fn)
        try:
            m = os.path.getmtime(p)
        except OSError:
            continue
        if m < since:
            continue
        cwd = None
        try:
            with open(p, "r", errors="replace") as fh:
                first = fh.readline()
            d = json.loads(first)
            if d.get("type") == "session_meta":
                cwd = d.get("payload", {}).get("cwd")
        except (OSError, ValueError):
            cwd = None
        candidates.append((m, p, cwd))
candidates.sort(key=lambda t: t[0])
if expected_cwd:
    pool = [c for c in candidates if c[2] == expected_cwd]
else:
    pool = candidates
print(pool[-1][1] if pool else "")
print(len(candidates))
PY
}

# _codex_rollout_dead_shape <rollout_file> -> rc0 = dead shape found (terminal
# task_complete, last_agent_message is null/absent); rc2 = terminal
# task_complete with a real message (healthy completion, not dead); rc1 =
# no terminal task_complete event in the file yet (still running, or file
# unreadable/missing). Scans from the end -- task_complete is always the
# last event_msg of a turn.
_codex_rollout_dead_shape() {  # <rollout_file>
  local f="$1"
  [[ -n "${f}" && -f "${f}" ]] || return 1
  python3 - "$f" 2>/dev/null <<'PY'
import json, sys
path = sys.argv[1]
try:
    with open(path, "r", errors="replace") as fh:
        lines = fh.readlines()
except OSError:
    sys.exit(1)
for line in reversed(lines):
    line = line.strip()
    if not line:
        continue
    try:
        d = json.loads(line)
    except ValueError:
        continue
    if d.get("type") != "event_msg":
        continue
    payload = d.get("payload")
    if not isinstance(payload, dict) or payload.get("type") != "task_complete":
        continue
    sys.exit(0 if payload.get("last_agent_message") is None else 2)
sys.exit(1)
PY
}

# _codex_instant_complete_deadline_check <sig8> <since_epoch> [expected_cwd]
# -> 0 = proceed (a real terminal message was found, a non-terminal event
# newer than spawn was seen -- job demonstrably alive, nit 2-B -- or the
# window elapsed with no dead shape; the existing early-verdict/first-byte
# machinery covers every other outcome), 7 = declared dead (task_complete +
# last_agent_message null found within the window) -- caller must abort the
# reservation and spill, exactly like _codex_first_byte_deadline_check's
# rc=7 contract. Records a provider strike via the same record-quota-lockout
# path on the dead verdict. expected_cwd (nit 2-A) scopes the rollout scan
# to this dispatch's own --cwd when possible; ambiguity (>1 window
# candidate) is journaled either way.
_codex_instant_complete_deadline_check() {  # <sig8> <since_epoch> [expected_cwd]
  local sig8="$1" since="$2" expected_cwd="${3:-}"
  local deadline="${LEADV2_CODEX_INSTANT_COMPLETE_SECS:-30}"
  [[ "${deadline}" =~ ^[0-9]+$ ]] || deadline=30
  [[ "${deadline}" != "0" ]] || return 0
  local poll_s="${LEADV2_ARM_EARLY_VERDICT_POLL_S:-1}"
  [[ "${poll_s}" =~ ^[0-9]+([.][0-9]+)?$ ]] || poll_s=1
  [[ "${poll_s}" != "0" && "${poll_s}" != "0.0" ]] || poll_s=0.1
  local started="${SECONDS}" scan_out f count rc
  while true; do
    scan_out="$(_codex_newest_rollout_since "${since}" "${expected_cwd}")"
    f="$(printf '%s\n' "${scan_out}" | sed -n '1p')"
    count="$(printf '%s\n' "${scan_out}" | sed -n '2p')"
    if [[ "${count}" =~ ^[0-9]+$ && ${count} -gt 1 ]]; then
      emit decision "arm_dead_instant_complete_ambiguous_rollout arm=codex task=${sig8} candidates=${count} picked=${f}"
    fi
    if [[ -n "${f}" ]]; then
      _codex_rollout_dead_shape "${f}"; rc=$?
      if [[ ${rc} -eq 0 ]]; then
        emit decision "arm_dead_instant_complete arm=codex task=${sig8} rollout=${f}"
        bash "${DISPATCH_SELF_BIN:-${SCRIPT_DIR}/leadv2-dispatch-code.sh}" record-quota-lockout \
          --provider codex --hours 1 --reason arm_dead_instant_complete >/dev/null 2>&1 || true
        return 7
      elif [[ ${rc} -eq 2 ]]; then
        return 0   # terminal, real last_agent_message -- healthy, proceed
      else
        # rc=1: no terminal event yet, but this rollout only qualified
        # because its mtime already postdates spawn -- some non-terminal
        # event has landed. The job is demonstrably alive; no reason to pay
        # the rest of the window waiting for its terminal event (nit 2-B).
        return 0
      fi
    fi
    if (( SECONDS - started >= deadline )); then
      return 0   # still running past the window, no dead shape -- proceed
    fi
    sleep "${poll_s}"
  done
}

# CODEX-ARM-WORKTREE-SCOPE-01: the codex WORKER arm (long missions, via
# codex-task.sh's `task --background`) has been observed dying 5x in one day
# in shapes neither _codex_first_byte_deadline_check nor
# _codex_instant_complete_deadline_check catch: (a) codex-companion's own job
# store loses the row entirely (a later `status <jobId>` call that succeeded
# once at spawn time -- see the not_live guard right after the spawn call --
# later returns "No job found") and (b) codex emits a `turn_aborted` event
# (not `task_complete`) and then goes silent -- a different terminal shape
# than the null-message task_complete instant-complete already handles.
# Both are "the job was live a moment ago and is now provably gone" -- the
# same "arm_dead" contract as the instant-complete check, just a later/looser
# poll window (worker missions take longer to produce first output than the
# instant-complete window is sized for).
#
# _codex_rollout_turn_aborted <rollout_file> -> rc0 = a turn_aborted event_msg
# found (dead), rc1 = not found / unreadable. Scans from the end, same
# convention as _codex_rollout_dead_shape.
_codex_rollout_turn_aborted() {  # <rollout_file>
  local f="$1"
  [[ -n "${f}" && -f "${f}" ]] || return 1
  python3 - "$f" 2>/dev/null <<'PY'
import json, sys
path = sys.argv[1]
try:
    with open(path, "r", errors="replace") as fh:
        lines = fh.readlines()
except OSError:
    sys.exit(1)
for line in reversed(lines):
    line = line.strip()
    if not line:
        continue
    try:
        d = json.loads(line)
    except ValueError:
        continue
    if d.get("type") != "event_msg":
        continue
    payload = d.get("payload")
    if isinstance(payload, dict) and payload.get("type") == "turn_aborted":
        sys.exit(0)
sys.exit(1)
PY
}

# _codex_worker_liveness_deadline_check <handle> <sig8> <since_epoch> [expected_cwd]
# -> 0 = proceed (job store still has the row and no turn_aborted event seen
# right now -- the generic early-verdict/first-byte/instant-complete
# machinery already covers every other outcome), 7 = declared dead (job
# store lost the row, or a turn_aborted event landed) -- caller must abort
# the reservation and spill, exactly like the sibling deadline checks' rc=7
# contract. Records a provider strike via the same record-quota-lockout
# path on the dead verdict, reason=arm_dead_worker_liveness.
# SINGLE-SHOT, not a poll loop: nit 2-B (this same file) established that
# any positive liveness evidence available right now is proof enough to
# stop waiting -- a job-store row present at check time is exactly that
# evidence. Looping this check to a 60s deadline on the happy path would
# tax EVERY healthy codex spawn with up to an extra minute of blocking
# wait, directly undoing 2-B's "return early once alive" fix; the window
# this check is named for is the interval since spawn already elapsed by
# the first-byte + instant-complete checks before it, not a new wait here.
_codex_worker_liveness_deadline_check() {  # <handle> <sig8> <since_epoch> [expected_cwd]
  local handle="$1" sig8="$2" since="$3" expected_cwd="${4:-}"
  local deadline="${LEADV2_CODEX_WORKER_LIVENESS_SECS:-60}"
  [[ "${deadline}" =~ ^[0-9]+$ ]] || deadline=60
  [[ "${deadline}" != "0" ]] || return 0
  local scan_out f status_out status_rc
  # codex-status-liveness fix-2: `status` exiting nonzero is NOT by itself proof the
  # job row is gone -- a transient companion/IPC hiccup or a malformed response also
  # exits nonzero, and treating either as "dead" spilled a healthy job (round-1 HIGH).
  # Only a positively-parsed "No job found" response (the exact missing-row message
  # codex-task.sh's own status adapter documents -- see the not_live guard at spawn
  # time above) proves the row is gone. Any other nonzero is unknown/fail-open:
  # journal it and leave the reservation intact, no strike.
  status_out="$(bash "${CODEX_BIN}" status "${handle}" 2>&1 9>&-)"; status_rc=$?
  if [[ ${status_rc} -ne 0 ]]; then
    if printf '%s' "${status_out}" | grep -qi 'no job found'; then
      emit decision "arm_dead_worker_liveness arm=codex task=${sig8} handle=${handle} reason=vanished_job"
      bash "${DISPATCH_SELF_BIN:-${SCRIPT_DIR}/leadv2-dispatch-code.sh}" record-quota-lockout \
        --provider codex --hours 1 --reason arm_dead_worker_liveness >/dev/null 2>&1 || true
      return 7
    fi
    emit decision "codex_worker_liveness_status_unknown arm=codex task=${sig8} handle=${handle} rc=${status_rc}"
    return 0
  fi
  scan_out="$(_codex_newest_rollout_since "${since}" "${expected_cwd}")"
  f="$(printf '%s\n' "${scan_out}" | sed -n '1p')"
  if [[ -n "${f}" ]] && _codex_rollout_turn_aborted "${f}"; then
    emit decision "arm_dead_worker_liveness arm=codex task=${sig8} handle=${handle} reason=turn_aborted rollout=${f}"
    bash "${DISPATCH_SELF_BIN:-${SCRIPT_DIR}/leadv2-dispatch-code.sh}" record-quota-lockout \
      --provider codex --hours 1 --reason arm_dead_worker_liveness >/dev/null 2>&1 || true
    return 7
  fi
  return 0   # job store row present, no turn_aborted seen -- proceed
}

# ── CORE FIX (fix-pass-4 REDESIGN): reserve (short lock) -> spawn (NO lock) -> confirm/
# abort (short lock) -- see the FIX PASS 4 doc block at the top of this file for why
# fix-pass-3's "one held flock across the whole sequence" was itself blocked (FD-inheritance
# into a detached worker + a launch step that isn't sub-second). Only used for arm in
# {glm, sonnet} (the arms that spawn); arm=opus never spawns and uses
# atomic_dispatch_reserve_confirm_opus below (reserve, then immediately confirm -- nothing
# to ever roll back).
# <sig> <arm> <rule> <mission> <sig8> <do_spawn 0|1> -> stdout: any worker_spawned /
# spawn_failed lines spawn_worker itself prints+journals (unchanged behavior). Returns:
#   0 = confirmed (row kept, live worker spawned; only reachable when do_spawn=1)
#   2 = duplicate/blocked task_sig (a confirmed-and-fresh or pending-and-fresh row already
#       claims it) -- refused before any write, nothing to roll back
#   3 = lock-wait timeout on the reserve step -- hard error, ledger state untouched
#   4 = not confirmed (spawn failed, or do_spawn=0 dry-run) -- abort SUCCEEDED, row removed,
#       an identical retry will be accepted
#   5 = not confirmed AND the abort/confirm WRITE itself failed (mktemp/mv) -- the row may
#       still be present; caller MUST treat this as a hard error, never report a rollback
#       success
#   6 = the RESERVATION write itself failed (read-only/full fs) -- hard error, nothing was
#       ever written, no spawn was attempted (mission: APPEND-FAIL)
#   7 = arm refused admission, or Kimi completed with channel_no_work -- abort SUCCEEDED
atomic_dispatch_reserve_spawn_confirm() {  # <sig> <arm> <rule> <mission> <sig8> <do_spawn>
  local sig="$1" arm="$2" rule="$3" mission="$4" sig8="$5" do_spawn="$6"
  local token trc
  token="$(dispatch_reserve "${sig}" "${arm}" "${rule}")"; trc=$?
  case "${trc}" in
    0) : ;;                 # reserved -- proceed to spawn, outside any lock
    2) return 2 ;;
    3) return 3 ;;
    *) return 6 ;;          # ledger write failed -- nothing to spawn, nothing to roll back
  esac
  ACTIVE_DISPATCH_TOKEN="${token}"

  local src=1 spawn_out="" _codex_spawn_epoch=0
  # SD-CODEX-SILENT-INSTANT-COMPLETE-01: captured before spawn so the
  # instant-complete rollout scan below never mistakes a PRIOR unrelated
  # codex session's rollout file for this one's.
  [[ "${arm}" == "codex" ]] && _codex_spawn_epoch="$(date +%s)"
  if [[ "${do_spawn}" == "1" ]]; then
    spawn_out="$(spawn_worker "${arm}" "${mission}" "${sig8}")"; src=$?
    printf '%s\n' "${spawn_out}"
    # N1-EMPTY-LANE-IS-NOT-A-PASS (B.2): restore the outcome spawn_worker set
    # inside its subshell (see spawn_worker's temp-file write) so the candidate
    # loop's arc branches read the REAL refusal reason, not a value lost to the
    # command substitution. Plain assignment (no `local`) reaches the caller.
    _spawn_oc="$(cat "${TMPDIR:-/tmp}/leadv2-spawn-outcome.$$" 2>/dev/null || true)"
    [[ -n "${_spawn_oc}" ]] && LAST_ARM_OUTCOME="${_spawn_oc}"
  fi
  if [[ "${do_spawn}" == "1" && ${src} -eq 0 ]]; then
    # spawn_worker only ever returns 0 after POSITIVELY verifying liveness (glm: run-dir
    # status check; sonnet: kill -0 on a parsed PID) -- "real liveness or drop the claim"
    # is already enforced by spawn_worker's own return contract, so confirming right after
    # a 0 return never confirms a merely-unproven worker.
    # DISPATCH-OUTCOME-LEDGER-01: parse the handle spawn_worker just printed (its one
    # "worker_spawned ... handle=<h>" line) and persist a normalized form on the confirmed
    # row so a LATER dispatch of the same sig can resolve this row's outcome.
    local crc raw_handle handle
    raw_handle="$(printf '%s\n' "${spawn_out}" | sed -n 's/.*[[:space:]]handle=\(.*\)$/\1/p' | tail -1)"
    handle="$(_dispatch_normalize_handle "${arm}" "${raw_handle}")"
    LAST_WORKER_HANDLE="${handle}"
    dispatch_confirm "${token}" "${handle}"; crc=$?
    ACTIVE_DISPATCH_TOKEN=""
    [[ ${crc} -eq 0 ]] || return 5   # live worker, but confirmation write failed

    # Confirm BEFORE waiting so the pending TTL cannot expire during a long async
    # run. Generic post-spawn verdict window (_wait_arm_early_verdict, CODEX-QUOTA-
    # LOCKOUT-NEVER-FIRES-FOR-CODEX-01) -- called unconditionally for every arm, not
    # just kimi: it no-ops (rc0 promptly) for arms with no status adapter. If the
    # terminal artifact says no-work (today: only kimi's channel_outcome) or a
    # quota-shaped failure (today: any arm with a status/log adapter -- primarily
    # closes the codex gap this fix exists for), remove this exact confirmed row and
    # hand rc=7 to the existing candidate-loop spill branch.
    local _early_rc=0
    _wait_arm_early_verdict "${arm}" "${handle}" "${sig8}" || _early_rc=$?
    if [[ ${_early_rc} -eq 76 ]]; then
      # T13-SLICE1 W3: GLM's own GLM_FALLBACK_TO_SONNET receipt (exit_code=76)
      # -- never a quota lockout, so no _record_postspawn_lockout call. Reuses
      # the existing rc=7 spill contract verbatim (same abort + candidate-loop
      # advance) so this arm gets exactly the same "retry the SAME lane on the
      # next arm" treatment kimi's channel_no_work already gets; the outer
      # loop's case 7 branch turns LAST_ARM_OUTCOME into the route_fallback
      # reason= field for free. LAST_ARM_CONTINUATION carries GLM's own tail
      # output into the next arm's mission (consumed once by the candidate
      # loop, then cleared).
      LAST_ARM_OUTCOME="exit76_receipt"
      LAST_ARM_CONTINUATION="$(_arm_final_output "${arm}" "${handle}")"
      # T13-SLICE1 R3/R4: match the EXACT sentinel token (word-bounded fixed
      # string), never a substring -- "GLM_PERMANENT_FAILURE_RETRY" or any
      # other longer identifier containing the bare prefix must NOT trip this
      # branch. Suppress only the RESPAWN (never re-enter the candidate loop
      # for this permanently-failed worker), but still surface a failure rc --
      # returning 0 here previously told the caller's rc=0 branch this was a
      # confirmed, live spawn and let the close flow run against a dead
      # worker. rc=5 reuses the existing "hard failure, ambiguous/dead state,
      # no respawn" contract (case 5 in atomic_dispatch_reserve_spawn_confirm's
      # caller): it marks the lane dead and exits non-zero instead of exiting 0.
      if printf '%s\n%s\n' "${spawn_out}" "${LAST_ARM_CONTINUATION}" | grep -Eq '(^|[^A-Za-z0-9_.-])GLM_PERMANENT_FAILURE_SENTINEL($|[^A-Za-z0-9_.-])'; then
        LAST_ARM_OUTCOME="exit76_permanent_sentinel"
        LAST_ARM_CONTINUATION=""
        emit decision "route_fallback_suppressed from=${arm} task=${sig8} reason=permanent_sentinel"
        log "spawn(${arm}) completed: permanent sentinel; fallback suppressed; reporting failure (no respawn)"
        return 5
      fi
      emit decision "arm_refused by=router model=${arm} task=${sig8} reason=exit76_receipt"
      log "spawn(${arm}) completed: exit76_receipt; spilling to next arm"
      local exit76_abort_rc=0
      dispatch_abort "${token}" || exit76_abort_rc=$?
      [[ ${exit76_abort_rc} -eq 0 ]] && return 7
      return 5
    elif [[ ${_early_rc} -eq 78 ]]; then
      LAST_ARM_OUTCOME="${arm}_channel_no_work"
      emit decision "arm_refused by=router model=${arm} task=${sig8} reason=channel_no_work"
      log "spawn(${arm}) completed: channel_no_work; spilling to next arm"
      local early_abort_rc=0
      dispatch_abort "${token}" || early_abort_rc=$?
      [[ ${early_abort_rc} -eq 0 ]] && return 7
      return 5
    elif [[ ${_early_rc} -eq 7 ]]; then
      LAST_ARM_OUTCOME="${arm}_refused_postspawn_quota"
      emit decision "arm_refused by=router model=${arm} task=${sig8} reason=postspawn_quota"
      log "spawn(${arm}) failed post-spawn: quota-shaped; spilling to next arm"
      local early_abort_rc=0
      dispatch_abort "${token}" || early_abort_rc=$?
      [[ ${early_abort_rc} -eq 0 ]] && return 7
      return 5
    fi
    # CODEX-DOOR-DEAD-01 §2: codex builder only, and only reached here when the
    # generic early-verdict window above found neither a terminal failure nor
    # no-work -- i.e. the job is still "running/unknown" (or already completed,
    # in which case the probe below finds output instantly and returns at once).
    if [[ "${arm}" == "codex" ]]; then
      local _fb_rc=0
      _codex_first_byte_deadline_check "${handle}" "${sig8}" || _fb_rc=$?
      if [[ ${_fb_rc} -eq 7 ]]; then
        LAST_ARM_OUTCOME="codex_dead_no_first_byte"
        emit decision "arm_refused by=router model=codex task=${sig8} reason=no_first_byte"
        log "spawn(codex) no first byte within deadline; spilling to next arm"
        local fb_abort_rc=0
        dispatch_abort "${token}" || fb_abort_rc=$?
        [[ ${fb_abort_rc} -eq 0 ]] && return 7
        return 5
      fi
      # SD-CODEX-SILENT-INSTANT-COMPLETE-01: bytes landed (first-byte check
      # above passed) but the job may STILL be dead -- codex-companion can
      # emit task_complete/last_agent_message=null within 1-3s and detach.
      local _ic_rc=0
      _codex_instant_complete_deadline_check "${sig8}" "${_codex_spawn_epoch}" "${WORK_ROOT}" || _ic_rc=$?
      if [[ ${_ic_rc} -eq 7 ]]; then
        LAST_ARM_OUTCOME="codex_dead_instant_complete"
        emit decision "arm_refused by=router model=codex task=${sig8} reason=instant_complete"
        log "spawn(codex) instant-complete with null last_agent_message; spilling to next arm"
        local ic_abort_rc=0
        dispatch_abort "${token}" || ic_abort_rc=$?
        [[ ${ic_abort_rc} -eq 0 ]] && return 7
        return 5
      fi
      # CODEX-ARM-WORKTREE-SCOPE-01: bytes landed and no instant-complete dead
      # shape was seen, but a WORKER mission (long-running, task --background)
      # can still vanish from codex-companion's job store or emit a
      # turn_aborted event well after the instant-complete window closes --
      # poll for up to LEADV2_CODEX_WORKER_LIVENESS_SECS (default 60).
      local _wl_rc=0
      _codex_worker_liveness_deadline_check "${handle}" "${sig8}" "${_codex_spawn_epoch}" "${WORK_ROOT}" || _wl_rc=$?
      if [[ ${_wl_rc} -eq 7 ]]; then
        LAST_ARM_OUTCOME="codex_dead_worker_liveness"
        emit decision "arm_refused by=router model=codex task=${sig8} reason=worker_liveness"
        _emit_event arm_refused "${sig8}" codex "${handle}" worker_liveness
        log "spawn(codex) worker liveness probe declared dead; spilling to next arm"
        local wl_abort_rc=0
        dispatch_abort "${token}" || wl_abort_rc=$?
        [[ ${wl_abort_rc} -eq 0 ]] && return 7
        return 5
      fi
    fi
    return 0
  fi

  # Not confirmed -- either do_spawn=0 (dry-run, never confirms) or spawn_worker failed
  # (which itself already covers "empty/absent handle = launch failure -> delete pending").
  local arc
  dispatch_abort "${token}"; arc=$?
  ACTIVE_DISPATCH_TOKEN=""
  if [[ ${arc} -eq 0 ]]; then
    [[ ${src} -eq 2 ]] && return 7
    return 4
  fi
  return 5
}

# opus arm never spawns, so there is nothing to roll back -- reserve, then immediately
# confirm (both short locks; the token is never exposed outside this function). Preserves
# the exact external rc contract the old atomic_dispatch_check_and_record had: 0 = recorded,
# 2 = duplicate/blocked, 3 = lock timeout; any other failure (reservation OR confirm write
# failing) collapses to 1 (hard error) -- the caller's existing `-ne 0` catch-all already
# treats that as an error, so no call-site change was needed beyond the function name.
atomic_dispatch_reserve_confirm_opus() {  # <sig> <arm> <rule>
  local sig="$1" arm="$2" rule="$3" token trc crc
  token="$(dispatch_reserve "${sig}" "${arm}" "${rule}")"; trc=$?
  case "${trc}" in
    0) : ;;
    2) return 2 ;;
    3) return 3 ;;
    *) return 1 ;;
  esac
  dispatch_confirm "${token}"; crc=$?
  [[ ${crc} -eq 0 ]] && return 0
  return 1
}

usage() {
  cat >&2 <<EOF
Usage:
  $SCRIPT_NAME <mission|@file|-> [--protected] [--safety] [--subsystems N]
                [--ui-judgment] [--interactive] [--kind <k>] [--glm-failures N]
                [--glm-lock-busy] [--force] [--no-spawn] [--task-class <class>]
                [--resume-lane <task-sig8|founder-id>] [--worktree <abs-path>]
                --task-class <trivial|light|standard|heavy|strategic|bulk>: named task-size
                class, consulted by the dispatch ladder's `when:` gate (e.g. freepool's
                `when: [standard, bulk]`) so an untrusted third-party arm only ever sees the
                task sizes it was actually approved for. Defaults to "Standard" for a caller
                that never resolved a size class (today's behaviour, unchanged).
                Resolve the code-writing model (glm|sonnet|codex) via routing.yaml glm_policy,
                journal route_resolved, refuse a duplicate task-signature (ATOMIC; --force
                never bypasses it), then LAUNCH the resolved worker and print its handle
                (--no-spawn / LEADV2_DISPATCH_SPAWN=0 for resolve-only). Default arm=glm.
                --resume-lane / --worktree pin WORK_ROOT to an EXISTING lane worktree instead
                of ensure-creating a new one (mutually exclusive; resumes finished/dead lanes,
                never hijacks a running one).
                Exit codes: 0 spawned/resolved, 2 duplicate task-sig, 3 arm=opus (lead
                judgment, not auto-dispatched), 4 spawn failed (retryable -- a failed
                spawn or --no-spawn never leaves a blocking ledger row behind), 5 placement
                refused (nonexistent/foreign-repo/live lane — no ledger row, no spawn),
                6 burn hard cap (BURN-GOVERNOR-01: 24h local token burn >= hard cap --
                no ledger row, no worktree, no spawn; task parked to burn-deferred.jsonl;
                LEADV2_BURN_OVERRIDE=1 bypasses, --force never does).
  $SCRIPT_NAME record-review --diff-hash <h> --verdict <PASS|FAIL|PASS_WITH_NITS>
                [--reviewer <s>] [--run-id <s>]
                Record a Codex review verdict; refuse a duplicate diff-hash (ATOMIC).
  $SCRIPT_NAME status          Print both ledgers for this repo.
  $SCRIPT_NAME glm-deferred [--list|--retry-all|--json]
                List/retry/json-dump glm tasks parked after a quota refusal
                (docs/leadv2/glm-deferred.jsonl). --retry-all re-dispatches any row whose
                quota window has reopened; manual-only, no auto-retry daemon.
  $SCRIPT_NAME burn-deferred [--list|--retry-all|--json]
                List/retry/json-dump tasks parked after a BURN-GOVERNOR-01 hard-cap refusal
                (docs/leadv2/burn-deferred.jsonl). --retry-all re-dispatches any row only when
                the governor verdict is no longer hard; manual-only, no auto-retry daemon.
Env: LEADV2_DISPATCH_ENFORCE=0 disables dedup (no-op/pass-through). LEADV2_DISPATCH_SPAWN=0
     disables worker launch (resolve-only). LEADV2_DISPATCH_CACHE_DIR relocates the ledgers
     (tests). LEADV2_DISPATCH_FENCE_LOG sets the fence deny-log path. LEADV2_DISPATCH_GLM_BIN
     / LEADV2_DISPATCH_SUBSESSION_BIN / LEADV2_DISPATCH_CODEX_BIN override the launchers
     (tests). LEADV2_BURN_GOVERNOR=0 disables the burn gate entirely. LEADV2_BURN_SOFT_24H /
     LEADV2_BURN_HARD_24H set the 24h-burn soft/hard caps (default 800000000 / 1300000000).
     LEADV2_BURN_OVERRIDE=1 bypasses a hard-cap refusal (journaled, --force never bypasses it).
     LEADV2_BURN_GOVERNOR_BIN / LEADV2_CLAUDE_BURN_DIR override the governor script / its
     ~/.claude/burn telemetry dir (tests).
EOF
  exit 1
}

# ── record-review subcommand ──────────────────────────────────────────────────────
cmd_record_review() {
  local diff_hash="" verdict="" reviewer="codex:standard" run_id="manual"
  while [[ $# -gt 0 ]]; do
    case "$1" in
      # R1 FIX (Finding 5): guard every valued flag's arg-count BEFORE shift 2 --
      # `shift 2` with only 1 positional left fails (bash leaves $# unchanged, no -e
      # to stop it) -> the case falls through to the same flag again -> infinite loop.
      --diff-hash) [[ $# -ge 2 ]] || { log_err "record-review: --diff-hash requires a value"; usage; }
                   diff_hash="$2"; shift 2 ;;
      --verdict)   [[ $# -ge 2 ]] || { log_err "record-review: --verdict requires a value"; usage; }
                   verdict="$2";   shift 2 ;;
      --reviewer)  [[ $# -ge 2 ]] || { log_err "record-review: --reviewer requires a value"; usage; }
                   reviewer="$2";  shift 2 ;;
      --run-id)    [[ $# -ge 2 ]] || { log_err "record-review: --run-id requires a value"; usage; }
                   run_id="$2";    shift 2 ;;
      -h|--help)   usage ;;
      *) log_err "record-review: unknown arg: $1"; usage ;;
    esac
  done
  if ! sig_is_hex "${diff_hash}"; then
    log_err "record-review: --diff-hash must be a 64-char hex sha256"; exit 1
  fi
  case "${verdict}" in
    PASS|FAIL|PASS_WITH_NITS) ;;
    *) log_err "record-review: --verdict must be PASS|FAIL|PASS_WITH_NITS (got: ${verdict:-<empty>})"; exit 1 ;;
  esac
  reviewer="$(sanitize_field "${reviewer}")"; run_id="$(sanitize_field "${run_id}")"
  JOURNAL_TASK="review-${diff_hash:0:8}"

  # B1 R2 (PHASES-ARE-THE-ONLY-PATH-01): refuse a build worker minting a review of
  # ITS OWN diff from inside a lane worktree (self-attestation).  Recording a review
  # of a DIFFERENT diff from inside a worktree is allowed -- the guard compares the
  # provided diff_hash against the SHA-256 of the current worktree's own diff against
  # its base, computed with the same scheme as leadv2-dispatch-product-close.sh's
  # _pc_repo_diff: git diff <base> with docs/leadv2+docs/handoff excluded, taking the
  # larger of HEAD-diff and base-diff ("never-smaller" guard).  Base resolution mirrors
  # _pc_diff_base: lane start-sha (env or cache file) → origin/main merge-base → HEAD.
  if [[ "${REVIEW_RECORDER_GUARD}" == "1" ]]; then
    local _cwd _git_dir _common_dir
    _cwd="$PWD"
    _git_dir="$(git -C "$_cwd" rev-parse --git-dir 2>/dev/null || true)"
    _common_dir="$(git -C "$_cwd" rev-parse --git-common-dir 2>/dev/null || true)"
    if [[ -n "$_git_dir" && -n "$_common_dir" && "$_git_dir" != "$_common_dir" ]] \
       || [[ "$_cwd" == */.claude/worktrees/* ]]; then
      local _repo_root _base _head_diff _base_diff _wt_diff _wt_hash _wt_sig8 _start_sha
      _repo_root="$(git -C "$_cwd" rev-parse --show-toplevel 2>/dev/null || true)"
      if [[ -n "$_repo_root" ]]; then
        # Resolve base: same candidates as _pc_diff_base (start-sha cache → origin/main → HEAD).
        _start_sha="${LEADV2_LANE_START_SHA:-}"
        if [[ -z "$_start_sha" ]]; then
          _wt_sig8="$(basename "$_cwd")"
          _start_sha="$(cat "$(lane_start_sha_file "${_wt_sig8}")" 2>/dev/null || true)"
        fi
        _base=""
        if [[ -n "$_start_sha" ]] && git -C "$_repo_root" cat-file -e "${_start_sha}^{commit}" 2>/dev/null; then
          _base="$(git -C "$_repo_root" merge-base "${_start_sha}" HEAD 2>/dev/null || true)"
        fi
        if [[ -z "$_base" ]] && git -C "$_repo_root" cat-file -e "origin/main^{commit}" 2>/dev/null; then
          _base="$(git -C "$_repo_root" merge-base origin/main HEAD 2>/dev/null || true)"
        fi
        # Never-smaller: compute both HEAD-diff and base-diff, keep the larger.
        _head_diff="$(git -C "$_repo_root" diff HEAD -- ':(exclude)docs/leadv2' ':(exclude)docs/handoff' 2>/dev/null || true)"
        if [[ -n "$_base" ]]; then
          _base_diff="$(git -C "$_repo_root" diff "$_base" -- ':(exclude)docs/leadv2' ':(exclude)docs/handoff' 2>/dev/null || true)"
        else
          _base_diff=""
        fi
        if [[ ${#_base_diff} -gt ${#_head_diff} ]]; then
          _wt_diff="$_base_diff"
        else
          _wt_diff="$_head_diff"
        fi
        _wt_hash="$(printf '%s' "${_wt_diff}" | shasum -a 256 | awk '{print $1}')"
        if [[ "$_wt_hash" == "$diff_hash" ]]; then
          emit decision "review_record_refused reason=self_review_worktree diff=${diff_hash:0:8} cwd=${_cwd}"
          printf 'review_refused reason=self_review_worktree\n'
          exit 1
        fi
      fi
    fi
  fi

  local rrc
  atomic_review_check_and_record "${diff_hash}" "${verdict}" "${reviewer}" "${run_id}"
  rrc=$?
  if [[ ${rrc} -eq 2 ]]; then
    emit decision "review_refused reason=duplicate_diff_hash diff=${diff_hash:0:8} ledger=$(review_ledger_file)"
    printf 'review_refused reason=duplicate_diff_hash diff=%s\n' "${diff_hash:0:8}"
    exit 2
  elif [[ ${rrc} -ne 0 ]]; then
    log_err "review ledger record failed (rc=${rrc}) for diff=${diff_hash:0:8}"
    exit 1
  fi
  emit decision "review_recorded verdict=${verdict} diff=${diff_hash:0:8} reviewer=${reviewer}"
  printf 'review_recorded verdict=%s diff=%s\n' "${verdict}" "${diff_hash:0:8}"
  exit 0
}

cmd_status() {
  local df rf
  df="$(dispatch_ledger_file)"; rf="$(review_ledger_file)"
  printf 'dispatch-ledger: %s (%s rows)\n' "$df" "$([[ -f "$df" ]] && wc -l < "$df" | tr -d ' ' || echo 0)"
  [[ -f "$df" ]] && cat "$df"
  printf 'review-ledger:   %s (%s rows)\n' "$rf" "$([[ -f "$rf" ]] && wc -l < "$rf" | tr -d ' ' || echo 0)"
  [[ -f "$rf" ]] && cat "$rf"
  exit 0
}

# ── resolve (default) path ────────────────────────────────────────────────────────
cmd_resolve() {
  # cmd_resolve exits the process via `exit N` on every path (never `return`,
  # confirmed by census) -- this span is closed by the outer `lane` arm_exit
  # trap's stack-drain, never by an explicit end call in this function.
  lv2_trace_begin "lane.resolve"
  # Reconcile before admission: stale rows never consume a slot and a live
  # orphan is made visible before this dispatch can duplicate it.
  declare -F lane_reconcile >/dev/null 2>&1 && lane_reconcile >/dev/null 2>&1 || true
  # R6: computed once for this invocation so a single dispatch never straddles two
  # daily counter files even if it runs across a UTC-midnight boundary.
  local _LEADV2_EXC_DAY; _LEADV2_EXC_DAY="$(date -u +%Y%m%d)"
  local mission="" protected=0 safety=0 subsystems=0 ui=0 interactive=0 kind="" glmfails=0 lockbusy=0 force=0 kimi_fit=0 task_class="Standard" task_class_flagged=0
  local lane_writes="" lane_acceptance_cmd="" lane_rollback=0 lane_deliverable=""
  local -a phase_waivers=()
  # BLOCKING fix (review-verdict.md fanout.sh:1410-1426): optional founder task id
  # for callers (leadv2-fanout.sh's funnel) that dispatch on behalf of a specific
  # docs/tasks.yaml row. Additive/optional -- callers that omit it (backlog-pump,
  # direct CLI use) see no change. Bridges the sig8-keyed dispatch ledger back to
  # the founder task id so liveness/product-close can resolve one from the other,
  # and lets the close gate release the ORIGINAL claim on the same id (see
  # spawn_product_close below and leadv2-dispatch-product-close.sh's EXIT trap).
  local founder_task_id=""
  # LANE-PLACEMENT-01: explicit lane placement (--resume-lane / --worktree).
  local placement_lane_ref="" placement_path=""
  local spawn="${LEADV2_DISPATCH_SPAWN:-1}"
  local raw
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --protected)    protected=1;   shift ;;
      --safety)       safety=1;      shift ;;
      # R1 FIX (Finding 5): guard arg-count BEFORE shift 2 -- a valued flag with no
      # value left `shift 2` failing silently (no -e) and the SAME flag re-matching
      # next iteration = infinite loop (verified: timeout exit 124 on the old stub).
      --subsystems)   [[ $# -ge 2 ]] || { log_err "--subsystems requires a value"; usage; }
                      subsystems="$2"; shift 2 ;;
      --ui-judgment)  ui=1;          shift ;;
      --interactive)  interactive=1; shift ;;
      --kind)         [[ $# -ge 2 ]] || { log_err "--kind requires a value"; usage; }
                      kind="$2"; shift 2 ;;
      # T19 fix-round C2: named task-size class (trivial/light/standard/heavy/
      # strategic/bulk), consulted by _build_candidate_chain against a ladder
      # entry's `when:` list (e.g. freepool's `when: [standard, bulk]`).
      # Defaults to "standard" -- callers that never pass this see no change.
      --task-class)   [[ $# -ge 2 ]] || { log_err "--task-class requires a value"; usage; }
                      task_class="$2"; task_class_flagged=1; shift 2 ;;
      --glm-failures) [[ $# -ge 2 ]] || { log_err "--glm-failures requires a value"; usage; }
                      glmfails="$2"; shift 2 ;;
      --glm-lock-busy) lockbusy=1;   shift ;;
      --force)        force=1;       shift ;;
      --kimi-fit)     kimi_fit=1;    shift ;;
      --spawn)        spawn=1;       shift ;;  # default; kept explicit for callers/back-compat
      --no-spawn)     spawn=0;       shift ;;  # resolve+journal only, no worker launched (tests)
      # LANE-SHAPE-01: optional lane-shape declaration inputs (spec §8 context.yaml
      # additions). All no-ops when LEADV2_LANE_SHAPE=off (default) — see the gate
      # block below and leadv2-lane-shape.sh.
      --writes)          [[ $# -ge 2 ]] || { log_err "--writes requires a value"; usage; }
                          lane_writes="$2"; shift 2 ;;
      # REPORT-ONLY-GATE-01: optional deliverable declaration "report:<repo-relative
      # path>" — the row/dispatcher declaration, highest precedence; the mission's own
      # LANE_DELIVERABLE: line is the fallback. Unknown kinds are ignored + journalled
      # at resolve time (below), never a silent lane-kind flip.
      --lane-deliverable) [[ $# -ge 2 ]] || { log_err "--lane-deliverable requires a value"; usage; }
                          lane_deliverable="$2"; shift 2 ;;
      --acceptance-cmd)  [[ $# -ge 2 ]] || { log_err "--acceptance-cmd requires a value"; usage; }
                          lane_acceptance_cmd="$2"; shift 2 ;;
      --rollback-onestep) lane_rollback=1; shift ;;
      --phase-waiver) [[ $# -ge 2 ]] || { log_err "--phase-waiver requires a value"; usage; }
                      phase_waivers+=("$2"); shift 2 ;;
      # LANE-PLACEMENT-01: pin WORK_ROOT to an EXISTING lane worktree instead of
      # ensure-creating a new one.  Two spellings, one code path.  Mutual-exclusion
      # is enforced here (before any state write, exit 1 = usage).
      --resume-lane)  [[ $# -ge 2 ]] || { log_err "--resume-lane requires a value"; usage; }
                      placement_lane_ref="$2"; shift 2 ;;
      --worktree)     [[ $# -ge 2 ]] || { log_err "--worktree requires a value"; usage; }
                      placement_path="$2"; shift 2 ;;
      --task-id)      [[ $# -ge 2 ]] || { log_err "--task-id requires a value"; usage; }
                      founder_task_id="$2"; shift 2 ;;
      -h|--help)      usage ;;
      --*)            log_err "unknown arg: $1"; usage ;;
      *)              mission="${mission}${mission:+ }$1"; shift ;;  # collect positional mission
    esac
  done

  # LANE-PLACEMENT-01: both placement flags together = usage error (exit 1, no state write).
  if [[ -n "${placement_lane_ref}" && -n "${placement_path}" ]]; then
    log_err "--resume-lane and --worktree are mutually exclusive"; usage
  fi

  # Resolve the mission text: @file -> read file; "-" -> stdin; else inline.
  raw="${mission}"
  if [[ -z "${raw}" ]]; then
    log_err "missing mission (positional arg, @file, or -)"; usage
  fi
  local mission_file=""
  if [[ "${raw}" == @* ]]; then
    local p="${raw#@}"
    [[ -r "$p" ]] || { log_err "cannot read mission file: $p"; exit 1; }
    mission="$(cat "$p")"
    mission_file="$p"
  elif [[ "${raw}" == "-" ]]; then
    mission="$(cat)"
  fi
  [[ -n "${mission//[[:space:]]/}" ]] || { log_err "mission is empty after whitespace strip"; exit 1; }

  local sig sig8
  sig="$(printf '%s' "${mission}" | compute_sig)"
  sig8="${sig:0:8}"
  # A Phase-4 re-entry has a richer build mission than the original intake.
  # When its founder task receipt exists, retain the receipt's intake digest so
  # Gate-1 records and this guard address the same phases.d directory.
  if [[ -n "${founder_task_id:-}" ]] && declare -F leadv2_admission_find_receipt_for_task >/dev/null 2>&1; then
    local intake_receipt intake_sig8 intake_cls intake_route intake_src intake_wk intake_sig intake_tid
    intake_receipt="$(leadv2_admission_find_receipt_for_task "${PROJECT_ROOT}" "${founder_task_id}" 2>/dev/null || true)"
    if [[ -n "${intake_receipt}" ]]; then
      IFS=$'\t' read -r intake_sig8 intake_cls intake_route intake_src intake_wk intake_sig intake_tid <<<"${intake_receipt}"
      sig="${intake_sig}"
      sig8="${intake_sig8}"
    fi
  fi
  JOURNAL_TASK="dispatch-${sig8}"
  if [[ -z "${sig}" ]] || ! sig_is_hex "${sig}"; then
    log_err "signature computation failed"; exit 1
  fi
  # FOREIGN-PROJECT-ROOT-GUARD-01: journal the override now that JOURNAL_TASK exists
  # (the detection itself runs before sig8/JOURNAL_TASK are known -- see PROJECT_ROOT
  # resolution above).
  if [[ -n "${_LV2_FOREIGN_ROOT_ENV:-}" ]]; then
    emit decision "project_root_guard task=${sig8} status=foreign_env_overridden env_root=${_LV2_FOREIGN_ROOT_ENV} cwd_root=${_LV2_FOREIGN_ROOT_CWD}"
  fi
  # REPORT-ONLY-GATE-01: resolve the lane's deliverable declaration ONCE, before the
  # architect prepass inlines its design into ${mission} (the declaration is the
  # founder's statement of intent in the ORIGINAL mission, not a property of a design)
  # and before _lane_writes_guard can park on a missing LANE_WRITES. Precedence mirrors
  # lane_writes: row/CLI --lane-deliverable wins, else the mission's own LANE_DELIVERABLE
  # line. Absent => kind=diff => today's behaviour byte-for-byte. Only an exactly-
  # parsable `report:<path>` flips the kind; anything else is ignored AND journalled so
  # the dispatcher notices, never a silent lane-kind change. The validated declaration
  # also flows to product-close via spawn_product_close's LEADV2_DISPATCH_LANE_DELIVERABLE.
  LANE_DELIVERABLE_DECL=""
  local _ld_decl="${lane_deliverable}"
  [[ -n "${_ld_decl}" ]] || _ld_decl="$(_mission_deliverable "${mission}")"
  if [[ -n "${_ld_decl}" ]]; then
    if lv2_deliverable_parse "${_ld_decl}" >/dev/null; then
      LANE_DELIVERABLE_DECL="${_ld_decl}"
      emit decision "lane_deliverable task=${sig8} status=declared decl=${_ld_decl}"
    else
      emit decision "lane_deliverable task=${sig8} status=ignored reason=unknown_kind decl=${_ld_decl}"
    fi
  fi
  # BURN-GOVERNOR-01: 24h local token-burn gate, runs FIRST -- before the placement pin,
  # before the ensure block, before any reservation/terminal/spawn (architect prepass
  # §1.2 D2). Refuses (exit 6) only on verdict=hard and LEADV2_BURN_OVERRIDE!=1.
  _burn_gate || exit 6
  # LANE-PLACEMENT-01: resolve an explicit --resume-lane/--worktree pin BEFORE the ensure
  # block, BEFORE record_lane_start_sha, BEFORE any reservation/terminal/spawn.  Refuses
  # (exit 5) on: nonexistent path, not-a-worktree, foreign repo, live-claimed lane.  No
  # flag set → no-op (returns 0 immediately; ensure path runs byte-identical to today).
  _resolve_pinned_placement
  # LANE-WORKTREE-ISOLATION-01 lane-entry fix (W-1 architect prepass §0.1/§1.1 step 3):
  # this is the ONE call site every lane passes through regardless of who invoked it --
  # fanout's three lead-session launch paths, the detached per-lane launcher, AND a
  # direct lead dispatch that skips fanout entirely. The prepass found that the direct-
  # dispatch path (the one every real dispatch-<sig8> lane on 08-01/08-02 actually took)
  # never called `ensure`, so isolation was committed, tested, and documented, and had
  # never once fired for a real lane -- every lane silently ran in the shared tree.
  # `ensure` here closes that gap unconditionally, keyed on the FOUNDER task id (falling
  # back to this dispatch's own sig8 when no --task-id was given) -- the SAME key
  # leadv2-fanout-lane-launcher.sh:366 and the close gate's path-of fallback
  # (leadv2-dispatch-product-close.sh:386, `path-of "${FOUNDER_TASK_ID:-${TASK}}"`) use.
  # Keying on this script's own sig8 instead would make the close gate look in the wrong
  # worktree -- filed CRITICAL (R1) in the prepass.
  #
  # Idempotent + fail-open by construction: if LEADV2_LANE_WORK_ROOT already points at a
  # real dir other than PROJECT_ROOT (the launcher already `ensure`d it), this is a no-op
  # -- `ensure` itself just re-confirms the existing worktree and returns the same path.
  # `ensure` never fails the dispatch: on any git failure it falls back to PROJECT_ROOT
  # (today's shared-tree behavior), so isolation failing here only ever degrades, never
  # blocks. R8: a silent fallback is indistinguishable from a working feature -- that IS
  # the disease this task exists to end -- so every fallback is journaled loudly below.
  if [[ "${PLACEMENT_PINNED:-0}" != "1" ]]; then
   if [[ -z "${WORK_ROOT}" || ! -d "${WORK_ROOT}" || "${WORK_ROOT}" == "${PROJECT_ROOT}" ]]; then
    local _lane_ensure_key="${founder_task_id:-${sig8}}"
    local _lane_dir
    _lane_dir="$(LEADV2_PROJECT_ROOT="${PROJECT_ROOT}" bash "${LANE_WORKTREE_BIN}" ensure "${_lane_ensure_key}" "${kind:-standard}" 2>/dev/null)"
    if [[ -n "${_lane_dir}" && -d "${_lane_dir}" ]]; then
      if [[ "${_lane_dir}" == "${PROJECT_ROOT}" ]]; then
        emit decision "lane_worktree_fallback task=${sig8} founder_task=${_lane_ensure_key} reason=ensure_fell_back_to_shared_tree"
      else
        WORK_ROOT="${_lane_dir}"
        export LEADV2_LANE_WORK_ROOT="${WORK_ROOT}"
      fi
    fi
  fi
  fi  # LANE-PLACEMENT-01: close PLACEMENT_PINNED guard
  # PLACEMENT-PIN-DEFAULT-01: pin the prompt on EVERY dispatch whose work root is a lane
  # worktree — the ensure-created path (2272) and the launcher-pre-exported path (267)
  # both land here, and both were unpinned.  Idempotent w.r.t. the flagged path above.
  _set_worktree_pin_line
  # LANE-START-SHA-01: unconditional, before any arm spawn -- overwrites any stale value
  # from a prior dispatch that reused this cache dir (mitigates R2: a nested/child dispatch
  # never inherits a parent's start sha because it always re-records its own here first).
  record_lane_start_sha "${sig8}"
  # PROVIDER-LOCKOUT-FALSE-BLOCK-01 Defect C: a live lockout on the ladder's
  # first dispatchable provider is announced on stderr HERE, before any route
  # line, so the lead sees the bench without grepping a journal.
  _lockout_bench_banner "${sig8}"
  [[ -n "${founder_task_id}" ]] && emit decision "dispatch_task_bound task=${sig8} founder_task=${founder_task_id}"
  # SWIFTBAR-LIVE-01 round 2 (§2.4): persist onto the script-scope globals so
  # dispatch_reserve can write them onto the ledger row -- this was the missing
  # link; founder_task_id was already bound above but never reached the row.
  DISPATCH_FOUNDER_TASK_ID="${founder_task_id}"
  DISPATCH_MISSION_PATH="${mission_file}"
  # PHASE-DISCIPLINE-01 steps 1-2: admission classification BEFORE any routing,
  # lane registration, or spawn side effect. task_class becomes the estimate-
  # mapped class (explicit --task-class escalate-only per D1); the guard below
  # refuses class>=Standard without same-task pre-build phase records.
  _admission_classify "${mission}" "${sig}" "${sig8}" "${task_class}" "${task_class_flagged:-0}"
  task_class="${ADMISSION_CLASS}"
  # Admission says this mission lives in the full phase cycle: its Phase-4
  # re-entries need only the pre-build phases satisfied (the cycle is mid-
  # flight), not the whole-cycle completion contract. Explicit
  # LEADV2_REQUIRE_PHASES keeps its MODE semantics; this only narrows scope.
  [[ "${ADMISSION_ROUTE}" == "phases" ]] && export PHASE_GUARD_SCOPE=pre-build
  # N7F-LANE-NAME: resolve the display name ONCE, here, before any spawn side effect.
  # Rule 1 (--task-id) wins outright over rule 2 (mission H1) -- a caller that already
  # bound an identity gets that as its name too, and this also guards the fanout path
  # (which always passes --task-id) against ever being hijacked by mission prose. Rule 3
  # is load-bearing: no fallback to sig8, filename, or prose -- genuinely nameless stays
  # empty and the surface renders "unnamed".
  if [[ -n "${founder_task_id}" ]]; then
    DISPATCH_LANE_NAME="${founder_task_id}"
  else
    DISPATCH_LANE_NAME="$(_dispatch_lane_name_from_mission "${mission}")"
  fi

  # Product classifications are visible even when a later shape/router/ledger gate refuses
  # the task.  This is intentionally before any reservation/spawn side effect.
  local product_class classification_reason
  IFS=$'\t' read -r product_class classification_reason <<< "$(classify_product_work "${kind}" "${mission}")"
  emit decision "dispatch_classified task=${sig8} class=${product_class} reason=${classification_reason} kind=${kind:-unknown}"

  # PHASES-ARE-THE-ONLY-PATH-01 §7: register the dispatch lane in active.yaml.
  # Without this, leadv2_active_update_phase finds no row to patch and the mirror
  # stays empty forever (backlog-pump.sh:250-256 states this outright).
  # leadv2_active_register is idempotent (refreshes existing row if PID alive).
  #
  # STATUS-SURFACE-SHOWS-STALE-TRUTH-01 C5: this used to be gated on
  # `-n "${founder_task_id}"` alone, so every hand-dispatched lane (i.e. every
  # lane outside fanout, which always passes --task-id) skipped registration
  # entirely and never showed a phase/PID in the supervise table. Every lane
  # has an identity even without --task-id: the worker is spawned with
  # --task-id "dispatch-${sig8}" (see the sonnet arm above) and that same id
  # names its docs/handoff/dispatch-${sig8}/ dir, so register under that
  # identity when founder_task_id is absent -- byte-identical to today for
  # fanout (which always sets founder_task_id).
  local reg_id="${founder_task_id:-dispatch-${sig8}}"
  # LANE-REGISTRY-SELF-DEADLOCK-01: script-scope mirror of reg_id so
  # _spawn_worker_body (which runs in a command substitution and cannot read
  # this local) can stamp the post-spawn worker pid onto the row. A file write
  # escapes the subshell — same pattern as _dispatch_register_arm at :3795.
  DISPATCH_REG_ID="${reg_id}"
  if [[ -f "${SCRIPT_DIR}/leadv2-active-registry.sh" ]]; then
    if ! LEADV2_PROJECT_ROOT="${PROJECT_ROOT}" source "${SCRIPT_DIR}/leadv2-active-registry.sh" 2>/dev/null; then
      emit decision "active_register_miss task=${sig8}"
    else
      # R5 H2: capture the ownership identity -- the session_id register PRINTS
      # (a refresh returns the EXISTING row's id; the pid check discriminates)
      # and the durable PID it stamps -- so any later release can prove the row
      # is still THIS attempt's before unregistering it (see
      # _dispatch_slot_owned). The grep keeps ONLY the s-<ts>-<pid>-<pid>
      # session_id line: render_index prints its own "[registry] rendered ..."
      # line to STDOUT too (observed live 2026-08-24), so a bare tail -1 would
      # capture chatter, not the id. LEADV2_PROJECT_ROOT is passed explicitly:
      # a `VAR=x source` prefix does not persist past the source command.
      # The registry is sourced code and can inherit `errexit`; registration
      # output is advisory, so collect and parse it with errexit explicitly
      # disabled.  A registrar error or chatter-only output is handled below
      # as active_register_miss, never as an unjournalled dispatcher exit.
      local _register_out _register_rc
      set +e
      _register_out="$(LEADV2_PROJECT_ROOT="${PROJECT_ROOT}" leadv2_active_register "${reg_id}" "${task_class}" "${PROJECT_ROOT}" "${DISPATCH_LANE_NAME:-}" 2>/dev/null)"
      _register_rc=$?
      DISPATCH_SLOT_SESSION="$(printf '%s\n' "${_register_out}" | sed -nE '/^s-[0-9]{8}T[0-9]{6}Z-[0-9]+-[0-9]+$/p' | tail -n 1)"
      set +e
      if [[ -n "${DISPATCH_SLOT_SESSION}" ]]; then
        DISPATCH_SLOT_REG_ID="${reg_id}"
        DISPATCH_SLOT_PID="$(_lv2_durable_pid 2>/dev/null || printf '%s' "$$")"
        DISPATCH_SLOT_SIG8="${sig8}"
      else
        emit decision "active_register_miss task=${sig8} rc=${_register_rc}"
      fi
      # The lane-state module is the cap authority.  Existing registry rows
      # remain readable for legacy consumers; this adds identity/history.
      local _lead_session_id="${LEADV2_LEAD_SESSION_ID:-${LEADV2_PARENT_SESSION_ID:-${CLAUDE_SESSION_ID:-direct}}}"
      DISPATCH_LEAD_SESSION_ID="${_lead_session_id}"
      lane_register "${reg_id}" "${_lead_session_id}" "${WORK_ROOT:-${PROJECT_ROOT}}" "spawning" "${DISPATCH_SLOT_PID:-$$}"
      local _lane_register_rc=$?
      if [[ "${_lane_register_rc}" != "0" ]]; then
        if [[ "${_lane_register_rc}" == "3" ]]; then
          emit decision "dispatch_refused reason=lead_session_lane_cap task=${sig8} lead_session=${_lead_session_id}"
          exit 3
        fi
        emit decision "lane_state_register_failed task=${sig8} rc=${_lane_register_rc}"
      fi
    fi
    # LANE-TRUTH-BATCH-01 Row 1: stamp the real stream path so liveness resolves
    # this lane, not pulse.md.  leadv2_active_register defaults log_path to
    # pulse.md; the worker stream lives at developer.stream.jsonl.  fanout's
    # finalize register cannot fix this — its live-PID guard sees the durable
    # PID from self-registration and skips the overwrite.
    leadv2_active_set_log_path "${reg_id}" "docs/handoff/dispatch-${sig8}/developer.stream.jsonl" 2>/dev/null || true
  fi
  # SILENT-DEATH-01 sibling guard: leadv2-active-registry.sh sets `set -euo
  # pipefail` for standalone use.  The `source` inside the if-block above runs
  # in THIS shell, so it silently re-enables -e (which line 242 deliberately
  # opts out of — "NO -e (refusals must journal)").  The first guard at line
  # 367 covers the initial source at line 356; this covers the re-source that
  # happens at dispatch time.  Without it, spawn_worker returning rc=2 (arm
  # refusal) kills the process before the candidate loop can advance to the
  # next arm.  (E2E-GATE-RESIDUE-01 round 4 root cause.)
  set +e

  # PHASES-ARE-THE-ONLY-PATH-01: record classify as done (it just happened).
  bash "${PHASE_RECORD_BIN}" record "${sig8}" classify --status done \
    --task-id "${founder_task_id}" --owner "$(basename "$0"):cmd_resolve" 2>/dev/null || true

  # PHASES-ARE-THE-ONLY-PATH-01 §5: precondition guard at the same structural slot
  # as _lane_writes_guard / _acceptance_guard — after arg validation, before spawn.
  local _phase_waiver_args=()
  for _pw in "${phase_waivers[@]+"${phase_waivers[@]}"}"; do
    _phase_waiver_args+=(--waiver "$_pw")
  done
  _phase_precondition_guard "${sig8}" "${task_class}" "${lane_writes}" "${_phase_waiver_args[@]+"${_phase_waiver_args[@]}"}" || {
    # PREPASS-PROVIDER-FALLBACK-01-R5 §4: refused before any spawn -- the EXIT
    # trap (cleanup_pending_dispatch) releases the registered row on this exit.
    exit 3
  }

  if [[ "${product_class}" == "product" ]]; then
    # PREPASS-DEGRADES-01 (2026-07-29): a prepass failure must NEVER stop the work. On
    # 2026-07-29 this hard exit killed product dispatches outright -- the task never
    # launched at all -- which is strictly worse than dispatching an unrefined mission.
    # The gate exists to IMPROVE a mission when it can, not to hold the fleet hostage when
    # it cannot. Degrade to the raw mission and journal why, loudly.
    # PREPASS-RETRY-THEN-PARK-01 (2026-07-29, founder decision, SUPERSEDES the degrade-to-raw
    # behaviour described just above): retry, never skip. A product task that reaches a worker
    # without a design defeats the entire purpose -- the cross-provider review and the
    # end-to-end gate would then be inspecting something nobody ever scoped. Blocking forever
    # is wrong; dispatching unrefined is also wrong; PARKING and surfacing it is the honest
    # third option.
    _stamp_active_phase "${founder_task_id}" "prepass"
    local _pp_ok=0 _pp_try=1
    while (( _pp_try <= ARCHITECT_PREPASS_ATTEMPTS )); do
      if architect_prepass "${mission}" "${sig8}" "${lane_writes}"; then _pp_ok=1; break; fi
      emit decision "architect_prepass task=${sig8} status=retrying attempt=${_pp_try}/${ARCHITECT_PREPASS_ATTEMPTS} reason=${ARCHITECT_PREPASS_REASON:-no_design}"
      _pp_try=$(( _pp_try + 1 ))
    done
    if (( _pp_ok == 0 )); then
      emit decision "architect_prepass task=${sig8} status=parked reason=no_design_after_${ARCHITECT_PREPASS_ATTEMPTS}_attempts action=not_dispatched"
      # PLUGIN-RELIABILITY-01 D3: loud prepass_parked signal so supervise surfaces it.
      emit decision "prepass_parked task=${sig8} founder_task_id=${founder_task_id} reason=no_design_after_${ARCHITECT_PREPASS_ATTEMPTS}_attempts last_reason=${ARCHITECT_PREPASS_REASON:-unknown} worker_launched=0"
      log_err "architect prepass produced no design for product task=${sig8} after ${ARCHITECT_PREPASS_ATTEMPTS} attempts -- task PARKED, not dispatched."
      _dl_note "${sig8}" parked "no_design_after_${ARCHITECT_PREPASS_ATTEMPTS}_attempts" "" "${founder_task_id}"
      # PLUGIN-RELIABILITY-01 D3 (round 2): write a questions/ pending entry
      # so the supervise loop's _pc_emit_pending_questions surfaces it to the
      # founder. --no-block: writes the V2 control-plane record and returns
      # immediately — the question is visible in the questions dir for the
      # founder/supervise loop, but the dispatcher does NOT hang for 1800s
      # (round 1 Critical: --timeout 1800 blocked cmd_resolve synchronously).
      _ask_bin="${SCRIPT_DIR}/leadv2-ask.sh"
      if [[ -x "${_ask_bin}" ]]; then
        bash "${_ask_bin}" "dispatch-${sig8}" "Architect prepass parked after ${ARCHITECT_PREPASS_ATTEMPTS} attempts (last: ${ARCHITECT_PREPASS_REASON:-unknown}). Retry or abort?" \
          --option "retry|Retry prepass" --option "abort|Abort task" \
          --default-option "retry" --no-block >/dev/null 2>&1 || true
        _emit_event question_asked "${sig8}" "" "" "prepass_parked_retry_or_abort"
      fi
      # PREPASS-PROVIDER-FALLBACK-01-R5 §4: no worker was launched -- the EXIT
      # trap releases the registered row, so a parked lane holds no active slot.
      exit 3
    fi
    # PHASES-ARE-THE-ONLY-PATH-01: record plan phase done (prepass produced a design).
    local _pp_file_record; _pp_file_record="$(_prepass_file "${sig8}")"
    if [[ -s "${_pp_file_record}" ]]; then
      bash "${PHASE_RECORD_BIN}" record "${sig8}" plan --status done \
        --artifact "docs/handoff/dispatch-${sig8}/architect-prepass.md" \
        --task-id "${founder_task_id}" --owner "$(basename "$0"):cmd_resolve" 2>/dev/null || true
    fi
    # P0-WORK-CANNOT-LAND-UNSCOPABLE-DIFF-01: the row-declared `lane_writes` always wins --
    # a founder declaration is never overridden. Only when the row carried none does the
    # architect's own LANE_WRITES: line (already proven present by the guard above) fill it,
    # so it flows unchanged into lane-shape classify and spawn_product_close below.
    if [[ -z "${lane_writes}" ]]; then
      lane_writes="$(_prepass_writes "${sig8}")"
      [[ -n "${lane_writes}" ]] && emit decision "lane_writes task=${sig8} source=prepass writes=${lane_writes}"
    fi
    # The developer receives the independently-produced design -- but INLINE, and only
    # when one actually exists. Two failures on 2026-07-29 came from this line: it replaced
    # the mission with a bare pointer to a file that was empty (so the worker closed as a
    # no-op) or that the worker was unsure it was allowed to read (so it asked and stalled
    # for 51 minutes). A pointer is not a mission. Inline the design, keep the original
    # mission as context, and if there is no design, dispatch the original unchanged.
    local _pp_file; _pp_file="$(_prepass_file "${sig8}")"
    if [[ -s "${_pp_file}" ]]; then
      mission="Product implementation task dispatch-${sig8}. Implement this mechanism-closed design; preserve its non-goals. Before closing, run the required end-to-end gate and the cross-provider review gate recorded for this task.

PREPASS-MECHANISM-CLOSURE-01 — the design is authoritative, but it is not infallible, and you are the one reading the actual code. If discovery FALSIFIES its census — a caller it did not list, a return code whose consequence differs from what it claims, a configuration state it missed — STOP and say so in your report instead of implementing around it. Silently implementing a design whose census is wrong is how a defect becomes the next review round. Correcting the census in your report is a valid, valuable deliverable; quietly widening scope beyond it is not.

===== SCOPED DESIGN (authoritative) =====
$(cat "${_pp_file}")
===== END SCOPED DESIGN =====

===== ORIGINAL MISSION (context only; the design above wins on any conflict) =====
${mission}"
    fi
  fi

  # KIMI-CHANNEL-REHAB-01 M4: admission measures the actual scoped mission,
  # before the fixed async-question boilerplate below. The 2500-char cap is a
  # mission-scope bound, not a budget for dispatcher-owned instructions.
  local kimi_admission_mission="${mission}"

  # QUESTION-CHANNEL-DEAD-01 (willingness half): dispatch-code.sh is a lane
  # launcher with NO instruction of its own about the async question channel
  # -- every prior caller (leadv2-fanout.sh, claude-subsession.sh, ...) had to
  # remember to inject it into the mission text, and none of them did for the
  # GLM/Codex/Sonnet arms spawned here. A lane that is never told it may ask
  # simply never asks, regardless of how well the delivery path works. Append
  # a fixed, deterministic instruction block to EVERY mission AFTER the sig
  # is computed, so dedup identity still keys on the caller's actual task
  # content, not on this constant suffix.
  mission="${mission}

---
If you hit a decision you cannot safely make yourself (including destructive
options, a policy conflict, or missing authorization), ask via the async
question channel and wait for the answer rather than guessing or stalling:
  bash \"\${CLAUDE_PLUGIN_ROOT}/../../scripts/leadv2-ask.sh\" \"${JOURNAL_TASK}\" \"<question>\" \\
    --option \"a|<reversible label>\" --option \"b|<label>\" --default-option \"a\" [--timeout <sec=1800>]
It blocks until answered via \`/leadv2 reply <q-id> <option>\` and prints the
chosen option. Every question must declare its clearly reversible option with
\`--default-option\`; on timeout the lane proceeds on it and the decision is
journaled and surfaced in open-threads. Without a default, the task is parked
human-needed and its slot is freed. Do not use this for routine progress or
confirmation-seeking; only for a decision you cannot make yourself."

  # BUILDER-SELFCHECK-GATE-01 (item 3): one paragraph telling every product lane it
  # must falsify its own diff before submitting it. Guarded by the SAME kill-switch
  # the gate itself reads (product-close.sh), so LEADV2_BUILDER_SELFCHECK=0 restores
  # the mission text byte-for-byte, not just the gate behaviour. Appended AFTER the
  # dedup sig is computed, same as the async-question block above -- lane dedup
  # identity stays keyed on the caller's actual task content.
  if [[ "${LEADV2_BUILDER_SELFCHECK:-1}" != 0 ]]; then
    mission="${mission}

Before you finish, run your own falsification set and paste its raw output into
your final report: \`bash -n\` every shell file you changed, \`python3 -m
py_compile\` every Python file you changed, and the repo's changed-scope test
runner. Show the red output you got and the green output after your fix. A lane
whose self-check is missing or red is refused before any reviewer is spent on
it -- you will have burned the lane for nothing."
  fi

  # V3-STOP-GATE-01: one paragraph telling every product lane an uncommitted exit
  # is an incident, not a clean stop. Guarded by the SAME kill-switch the gate
  # itself reads (product-close.sh), same idiom as the BUILDER-SELFCHECK-GATE-01
  # paragraph above -- LEADV2_STOP_GATE=0 restores the mission text byte-for-byte.
  # Appended after the dedup sig is computed, same reason as above.
  if [[ "${LEADV2_STOP_GATE:-1}" != 0 ]]; then
    mission="${mission}

Commit your work on the lane branch before ending your session; an uncommitted
exit is treated as an incident."
  fi

  # LANE-SHAPE-01 gate (docs/specs/lane-shape.md task 2): classify solo vs line
  # BEFORE any ledger reservation or spawn. off (default) = no-op, zero behavior
  # change (spec §9 Stage 0). enforce refuses a diagnostic mission (names a
  # defect / uses a fix verb) that carries no ## Evidence block, and refuses a
  # mission whose declared writes are not shape-eligible (contracts/,
  # supabase/migrations/, or >=2 core subsystems) by routing it to the
  # classified pipeline instead of a bare lane dispatch. This never touches the
  # router/ledger/spawn logic below — a lane-shape refusal exits before any of
  # that runs, so it composes with the existing duplicate-signature and
  # refusal-advance behavior rather than replacing it.
  if [[ "${LEADV2_LANE_SHAPE:-off}" != "off" ]]; then
    local _ls_bin="${LEADV2_LANE_SHAPE_BIN:-${SCRIPT_DIR}/leadv2-lane-shape.sh}"
    local _ls_rc=0
    "${_ls_bin}" classify --task-id "dispatch-${sig8}" --mission "${mission}" \
      ${lane_writes:+--writes "${lane_writes}"} \
      ${lane_acceptance_cmd:+--acceptance-cmd "${lane_acceptance_cmd}"} \
      $([[ "${lane_rollback}" == "1" ]] && printf -- '--rollback-onestep') \
      || _ls_rc=$?
    case "${_ls_rc}" in
      0) : ;;  # accepted (or warn-mode violation, already logged)
      3) emit decision "dispatch_refused reason=not_shape_eligible task=${sig8}"
         _dl_note "${sig8}" refused not_shape_eligible "" "${founder_task_id}"
         printf 'dispatch_refused reason=not_shape_eligible task=%s\n' "${sig8}"
         # R5 §4: EXIT trap releases the registered row (no worker spawned).
         exit 2 ;;
      2) emit decision "dispatch_refused reason=diagnostic_mission_missing_evidence task=${sig8}"
         _dl_note "${sig8}" refused diagnostic_mission_missing_evidence "" "${founder_task_id}"
         printf 'dispatch_refused reason=diagnostic_mission_missing_evidence task=%s\n' "${sig8}"
         # R5 §4: EXIT trap releases the registered row (no worker spawned).
         exit 2 ;;
      *) log_err "leadv2-lane-shape.sh classify failed unexpectedly (rc=${_ls_rc}) for task=${sig8}"
         _dl_note "${sig8}" dead lane_shape_classify_failed "rc=${_ls_rc}" "${founder_task_id}"
         # R5 §4: EXIT trap releases the registered row (no worker spawned).
         exit 1 ;;
    esac
  fi

  # FIX PASS 2 (Finding 3 / F1 spoof): a caller-supplied --glm-failures count is
  # UNVERIFIED -- no real GLM-failure ledger backs it yet -- so trusting it directly lets
  # a caller flip glm->sonnet on request alone (`--glm-failures 2`), defeating GLM-FIRST.
  # Cap: any value that would trip the glm_failed_twice rule (>=2) is IGNORED (forced to
  # 0) and the ignore is journaled so a caller relying on it notices; values below the
  # trip threshold are already no-ops, so nothing to cap there. Applies to a raw env
  # override too -- the export below always uses this capped local, never a passed-through
  # value, so DC_GLM_FAILURES can't be smuggled in from the caller's environment either.
  local glmfails_num=0
  [[ "${glmfails}" =~ ^[0-9]+$ ]] && glmfails_num="${glmfails}"
  if (( glmfails_num >= 2 )); then
    emit decision "glm_failures_flag_ignored value=${glmfails} reason=unverified_caller_input_not_ledger_backed task=${sig8}"
    glmfails=0
  fi

  # ROUTER: resolve the model from routing.yaml glm_policy (NOT from a lead choice).
  # Resolution is pure (no side effects, deterministic from the SAME sig/flags every
  # call) so computing it before the atomic ledger section below is safe even for the
  # losing side of a race — only the ledger read+write needs to be atomic.
  export DC_PROTECTED="${protected}" DC_SAFETY="${safety}" DC_SUBSYSTEM_COUNT="${subsystems}" \
         DC_INTERACTIVE="${interactive}" DC_UI_JUDGMENT="${ui}" DC_KIND="${kind}" \
         DC_GLM_FAILURES="${glmfails}" DC_GLM_LOCK_BUSY="${lockbusy}" \
         DC_TASK_CLASS="${task_class}"
  local resolved arm rule reason tier readings router_label v2_eligible v2_ordered v2_headroom v2_vector v2_credits
  router_label="v1"
  if [[ "${LEADV2_ROUTER_V2:-0}" == "1" ]]; then
    router_label="v2"
    # PREPASS-PROVIDER-FALLBACK-01-R2: resolve_v2_dispatch runs inside a command
    # substitution, so its stage/detail for a failure cross the subshell boundary
    # via this file (see _v2_fail). Live 2026-08-24 evidence: filter exits rc=2
    # with "router_v2.arms is empty or missing" on stderr, the dispatcher logged
    # a bare `router_v2_unavailable rc=1` and the operator had nothing to act on.
    local _v2err _v2stage="unknown" _v2detail=""
    _v2err="$(mktemp "${TMPDIR:-/tmp}/leadv2-v2err.XXXXXX")" || _v2err=""
    resolved="$(V2_FAIL_FILE="${_v2err}" resolve_v2_dispatch "${mission}" "${sig8}" "${task_class}" "${kind}" "${protected}")" || {
      local v2rc=$?
      if [[ -n "${_v2err}" && -s "${_v2err}" ]]; then
        _v2stage="$(sed -n 's/^stage=//p' "${_v2err}" | head -1)"
        _v2detail="$(sed -n 's/^detail=//p' "${_v2err}" | head -1)"
      fi
      rm -f "${_v2err}"
      emit decision "dispatch_refused reason=router_v2_unavailable task=${sig8} router=v2 rc=${v2rc} stage=${_v2stage} detail=${_v2detail:-no_stderr_captured}"
      log_err "router v2 resolver failed at stage=${_v2stage} rc=${v2rc}: ${_v2detail:-no stderr captured}. Fix the router_v2 config it names (typically router_v2.arms in ${ROUTING_YAML}); LEADV2_ROUTER_V2=0 is the documented per-dispatch rollback, not a standing default."
      _dl_note "${sig8}" dead "router_v2_unavailable_rc_${v2rc}" "" "${founder_task_id}"
      # R5 §4: EXIT trap releases the registered row (no worker spawned).
      exit 1
    }
    rm -f "${_v2err}"
  else
    resolved="$(resolve_arm)"
  fi
  arm="$(printf '%s\n' "${resolved}" | sed -n 's/^arm=//p')"
  [[ -z "${arm}" && "${router_label}" == "v2" ]] && arm="$(printf '%s\n' "${resolved}" | sed -n 's/^winner=//p')"
  rule="$(printf '%s\n' "${resolved}" | sed -n 's/^rule=//p')"
  reason="$(printf '%s\n' "${resolved}" | sed -n 's/^reason=//p')"
  tier="$(printf '%s\n' "${resolved}" | sed -n 's/^tier=//p')"
  v2_eligible="$(printf '%s\n' "${resolved}" | sed -n 's/^eligible=//p')"
  v2_ordered="$(printf '%s\n' "${resolved}" | sed -n 's/^ordered=//p')"
  v2_headroom="$(printf '%s\n' "${resolved}" | sed -n 's/^headroom=//p')"
  v2_vector="$(printf '%s\n' "${resolved}" | sed -n 's/^vector=//p')"
  v2_credits="$(printf '%s\n' "${resolved}" | sed -n 's/^credits=//p')"
  local codex_quota_blocked codex_block_reason
  codex_quota_blocked="$(printf '%s\n' "${resolved}" | sed -n 's/^codex_quota_blocked=//p')"
  # PROVIDER-LOCKOUT-FALSE-BLOCK-01 Defect B: the resolver's fail-closed
  # decision itself is out of scope, but an UNREADABLE quota read must be
  # distinguishable in the journal from a genuine >=threshold reading — the
  # two previously rendered identically as rule=codex_quota_gate_80pct.
  codex_block_reason="$(printf '%s\n' "${resolved}" | sed -n 's/^codex_block_reason=//p')"
  # GLM-FIRST-RECOVERY-01 (C3): the resolver's gate-path-only live-reading line
  # (glm=2% codex=unknown anthropic=44%) rides the journal emit so a lead can
  # tell a correct peak-hour fallback from a stuck-probe inversion. Absent line
  # (happy path / gate absent / resolver v1 fallback) -> byte-identical emit.
  readings="$(printf '%s\n' "${resolved}" | sed -n 's/^readings=//p')"
  [[ "${router_label}" == "v2" ]] && rule="router_v2"
  [[ -n "${arm}" ]] || { log_err "resolver returned no arm: ${resolved}"; exit 1; }
  emit decision "arm_resolved job=build arm=${arm} reason=${rule}${readings:+ readings=${readings}}"
  # DISPATCH-BALANCE-BY-LIVE-QUOTA-01: the balancer's choice must be re-derivable
  # from the journal alone -- one decision line whenever the resolver balanced the
  # no-exception default between the GLM and Anthropic buckets (reason prefix
  # glm_default:balanced; the balance_unknown / balance_anthropic_locked keeps stay
  # glm and ride the arm_resolved line above). readings carries the two live
  # percentages that produced the choice, so a human can read the numbers and see
  # why that arm won without re-reading a provider endpoint.
  [[ "${reason}" == glm_default:balanced* ]] \
    && emit decision "dispatch_balance task=${sig8} arm=${arm} reason=${reason}${readings:+ readings=${readings}}"
  # RESOLVED_CODEX_TIER is read by _spawn_worker_body's codex case (global, not passed as
  # a positional -- spawn_worker's signature is shared across all three spawning arms).
  [[ "${arm}" == "codex" ]] && export RESOLVED_CODEX_TIER="${tier:-standard}"

  # ANTI-DOUBLE-SPEND: one task = one model.
  # R1 FIX (Finding 3): --force NEVER bypasses the duplicate-task_sig refusal in the
  # automated path. The router itself never sets an override; --force is still accepted
  # so callers don't hard-fail on an unknown arg, but it is a documented no-op for dedup
  # purposes (logged as such below).

  # opus arms are lead judgment (design/safety/arch) — resolved but NOT auto-dispatched,
  # so there is nothing to spawn or roll back. Keep the simpler reserve-only atomic (no
  # race is possible here: nothing ever needs to be undone for this arm).
  if [[ "${arm}" == "opus" ]]; then
    local orc
    atomic_dispatch_reserve_confirm_opus "${sig}" "${arm}" "${rule}"
    orc=$?
    if [[ ${orc} -eq 2 ]]; then
      if [[ "${force}" == "1" ]]; then
        emit decision "dispatch_override_rejected reason=force_not_permitted task=${sig8} ledger=$(dispatch_ledger_file)"
      fi
      emit decision "dispatch_refused reason=duplicate_task_signature task=${sig8} ledger=$(dispatch_ledger_file)"
      # FIX (wave2 finding 3): do NOT terminalize this caller against the shared sig8
      # key. A duplicate-signature refusal only tells us ANOTHER caller for the same
      # sig is already in flight -- it says nothing about how that other caller's
      # dispatch will end. Writing "refused" here would win the terminal ledger's
      # write-once race and permanently discard whatever landed/parked/dead verdict
      # the actual winner eventually earns.
      printf 'dispatch_refused reason=duplicate_task_signature task=%s\n' "${sig8}"
      exit 2
    elif [[ ${orc} -ne 0 ]]; then
      log_err "dispatch ledger record failed (rc=${orc}) for task=${sig8}"
      _dl_note "${sig8}" dead "ledger_record_failed_rc_${orc}" "" "${founder_task_id}"
      exit 1
    fi
    emit decision "route_resolved by=router router=${router_label} model=opus task=${sig8} rule=${rule} reason=${reason}"
    printf 'route_resolved by=router router=%s model=opus task=%s rule=%s reason=%s\n' "${router_label}" "${sig8}" "${rule}" "${reason}"
    log "route_note model=opus requires_lead_judgment (GLM banned for kind=${kind:-<none>}); not auto-dispatched"
    # FIX (wave2 finding 4): opus dispatch is explicitly NOT auto-dispatched -- nothing
    # ran, nothing was ever going to run, and the lead's own judgment (a separate,
    # out-of-band action) is what actually resolves this task. "landed" claimed
    # delivered work that never happened; "parked" is the true state until the lead
    # acts.
    _dl_note "${sig8}" parked resolved_opus_lead_judgment "" "${founder_task_id}"
    exit 3
  fi

  # A refusal is an admission signal, not a broken launcher.  The candidate
  # chain follows the dispatch_ladder from the routing YAML (P1): the resolved
  # arm is first, followed by every arm after it in ladder order.  A hard class
  # exception resolving directly to sonnet therefore cannot escape back to GLM.
  local -a candidate_arms attempted
  # FP-06 telemetry bookkeeping (see _model_select_telemetry): attempt clock,
  # fallback counter, floor mirror and the arbiter's model for the live chain.
  # Deliberately NOT `local` -- the file-scope helper reads them via bash
  # dynamic scoping, same pattern as DISPATCH_FREEPOOL_ROLE.
  _MS_T0="$(_now_epoch)"; _MS_FALLBACKS=0; _MS_FLOOR="none"; _MS_MODEL=""
  if [[ "${router_label}" == "v2" ]]; then
    # ordered= is additive.  Old/stubbed resolvers may not know it, in which
    # case preserve their eligible= behavior rather than failing closed.
    local _v2_chain="${v2_eligible}"
    if [[ "${LEADV2_ROUTER_V2_QUOTA_ORDER:-1}" != "0" && -n "${v2_ordered}" ]]; then
      _v2_chain="${v2_ordered}"
    elif [[ "${LEADV2_ROUTER_V2_QUOTA_ORDER:-1}" != "0" ]]; then
      emit decision "router_v2_no_ordered_key task=${sig8}"
    fi
    IFS=',' read -r -a candidate_arms <<< "${_v2_chain}"
    [[ ${#candidate_arms[@]} -gt 0 && -n "${candidate_arms[0]}" ]] || { emit decision "dispatch_rolled_back reason=all_arms_exhausted task=${sig8} router=v2"; _dl_note "${sig8}" refused all_arms_exhausted_v2 "" "${founder_task_id}"; exit 4; }
    # ARM-LADDER-KIMI-RESURRECTED-01 follow-up + ROUTER-V2-BYPASSES-ARM-LADDER-
    # FILTER-01: v2's eligible=/ordered= comes straight from the router-v2
    # resolver, which never consulted DISPATCHABLE_BUILD_ARMS and speaks a
    # different arm-id vocabulary (claude-sonnet, not sonnet). All three v2
    # adoption sites now go through _adopt_v2_chain (normalize -> filter ->
    # empty-guard) so a retired id (e.g. a stale tenant yaml still listing
    # kimi) cannot survive at ANY of them.
    if ! _adopt_v2_chain "${sig8}" initial "${_v2_chain}"; then
      _dl_note "${sig8}" refused all_arms_not_dispatchable_v2 "" "${founder_task_id}"
      exit 4
    fi
    _apply_kimi_admission "${kimi_admission_mission}" "${sig8}" "${lane_writes}" "${kimi_fit}"
  else
    _load_dispatch_ladder
    _filter_ladder_to_dispatchable "${sig8}"
    [[ "${ROUTING_CONFIG_ABSENT:-0}" == "1" ]] && \
      emit decision "routing_config_degraded task=${sig8} reason=no_routing_yaml_project_or_plugin ladder=legacy_hardcoded arms=$(IFS=,; printf '%s' "${_LADDER_IDS[*]}")"
    _build_candidate_chain "${arm}" "${sig8}"
    # T-q codex_quota_gate (SUPERVISOR-AUDIT-01 T-b): strip codex from the fixed
    # glm->codex->sonnet fallback chain when the resolver's live codex-quota read
    # is >= build_threshold_pct — an arm the resolver itself refuses to hand out
    # as PRIMARY must not still be reachable as a SPILL target.
    if [[ "${codex_quota_blocked:-0}" == "1" ]]; then
      local -a _filtered=()
      local _a
      for _a in "${candidate_arms[@]}"; do
        if [[ "${_a}" == "codex" ]]; then
          # dispatch-8e2a32be: this silent strip predates the resolver's D4 on-disk
          # lockout read -- once D4 started setting codex_quota_blocked=1 from the
          # lockout file (not just a live quota pct read), this branch started firing
          # for the lockout case too, BEFORE the ARM-LADDER-HAS-NO-QUOTA-PRECHECK-01
          # loop below ever sees "codex" in candidate_arms -- so that loop's own
          # quota_precheck_skip line never fires for codex. Emit the same-shaped line
          # here so a lockout-caused strip is exactly as loud as a live-quota-caused one.
          emit decision "quota_precheck_skip model=codex provider=codex task=${sig8} reason=provider_quota_locked class=${codex_block_reason:-unknown}"
        else
          _filtered+=("${_a}")
        fi
      done
      candidate_arms=("${_filtered[@]}")
    fi
    _apply_kimi_admission "${kimi_admission_mission}" "${sig8}" "${lane_writes}" "${kimi_fit}"
  fi

  # T17: arbiter is the first candidate-chain source. The legacy resolver and
  # ladder above remain a deliberately fail-open fallback for an arbiter fault.
  local -a _pre_arb_candidate_arms=("${candidate_arms[@]}")
  if declare -F route_arbiter >/dev/null 2>&1; then
    local _arb_desc _arb_out _arb_rc _arb_arm _arb_chain _arb_reason _arb_util _arb_tier _arb_model _arb_floor_applied _arb_floor_reason
    # T17 fix-round (H2): protected/safety/ui_judgment reach the arbiter ONLY
    # through --protected/--safety/--ui-judgment CLI flags, which no real
    # caller passes (same no-writers shape as T19) -- so every arbiter-routed
    # mission looked unprotected regardless of content. Derive the same
    # signal the pre-existing sonnet_exceptions mission-scan already computes
    # (safety_gate_publish_payments / ui_design_judgment keyword classes) and
    # OR it into the CLI-flag value rather than overriding it -- an explicit
    # --protected/--safety/--ui-judgment flag always still wins.
    local _arb_protected="${protected}" _arb_safety="${safety}" _arb_ui="${ui}"
    if [[ "${_arb_safety}" != "1" ]] && printf '%s' "${mission}" | grep -qiE 'safety[_-]?gate|\bpublish\b|\bpayments?\b'; then
      _arb_safety=1
    fi
    if [[ "${_arb_ui}" != "1" ]] && printf '%s' "${mission}" | grep -qiE '\bui[_ -]?design\b|\bui[_ -]?judgment\b|\bpixel[_ -]?perfect\b'; then
      _arb_ui=1
    fi
    [[ "${_arb_safety}" == "1" || "${_arb_ui}" == "1" ]] && _arb_protected=1
    _arb_desc="$(python3 -c 'import json,sys; print(json.dumps({"kind":sys.argv[1],"size":sys.argv[2],"protected":sys.argv[3]=="1","safety":sys.argv[4]=="1","ui_judgment":sys.argv[5]=="1","task":sys.argv[6]}))' "${kind:-code}" "${task_class:-standard}" "${_arb_protected}" "${_arb_safety}" "${_arb_ui}" "${sig8}")"
    _arb_out="$(route_arbiter worker "${_arb_desc}")"; _arb_rc=$?
    _arb_arm="$(printf '%s\n' "${_arb_out}" | sed -n 's/.*arm=\([^ ]*\).*/\1/p')"
    _arb_chain="$(printf '%s\n' "${_arb_out}" | sed -n 's/.*chain=\([^ ]*\).*/\1/p')"
    _arb_reason="$(printf '%s\n' "${_arb_out}" | sed -n 's/.*reason=\([^ ]*\).*/\1/p')"
    _arb_util="$(printf '%s\n' "${_arb_out}" | sed -n 's/.*\(util_glm=.*\)$/\1/p')"
    _arb_tier="$(printf '%s\n' "${_arb_out}" | sed -n 's/.*tier=\([^ ]*\).*/\1/p')"
    _arb_model="$(printf '%s\n' "${_arb_out}" | sed -n 's/.*model=\([^ ]*\).*/\1/p')"
    # FP-08 fix-round (H1/H3): the capability-floor journal comes from the
    # arbiter's OWN output line for THIS invocation (`floor_applied=1
    # floor_reason=<raw-class>/<kind>`), emitted when the demotion is APPLIED
    # in the effective ranking -- never from a cross-run state file, which a
    # failed arbiter write could leave carrying the PREVIOUS task's floor
    # attribution (round-1 M3), and never from a raw Python bool whose `True`
    # never matched this shell's `== "true"` probe (round-1 H3: the journal
    # line was unreachable dead code).
    _arb_floor_applied="$(printf '%s\n' "${_arb_out}" | sed -n 's/.*[[:space:]]floor_applied=\([01]\).*/\1/p')"
    _arb_floor_reason="$(printf '%s\n' "${_arb_out}" | sed -n 's/.*[[:space:]]floor_reason=\([^[:space:]]*\).*/\1/p')"
    if [[ "${_arb_floor_applied}" == "1" && -n "${_arb_floor_reason}" ]]; then
      emit decision "arm_floor_applied arm=freepool task=${sig8} reason=${_arb_floor_reason}"
      _MS_FLOOR="applied"
    fi
    # FP-06: journal the resolved capability-floor mode once per dispatch
    # (env > yaml > default, resolved inside the arbiter; a missing knob is
    # today's bulk_only). Parsed from the arbiter's OWN output line for this
    # invocation, same provenance rule as the floor tokens above.
    # BSD-sed has no \| BRE alternation (macOS) -- grep -oE extracts the
    # token instead; head -1 guards against any duplicate token.
    _arb_floor_mode="$(printf '%s\n' "${_arb_out}" | grep -oE ' floor_mode=(bulk_only|full)' | head -1 | sed 's/.*=//')"
    _arb_floor_mode_src="$(printf '%s\n' "${_arb_out}" | grep -oE ' floor_mode_source=(yaml|env|default)' | head -1 | sed 's/.*=//')"
    [[ -n "${_arb_floor_mode}" ]] && emit decision "freepool_floor_mode mode=${_arb_floor_mode} source=${_arb_floor_mode_src:-default} task=${sig8}"
    if [[ ${_arb_rc} -eq 0 && -n "${_arb_arm}" && "${_arb_arm}" != refuse && -n "${_arb_chain}" ]]; then
      # T17 fix-round (C2): the arbiter chain must pass the SAME
      # DISPATCHABLE_BUILD_ARMS filter every other chain-adoption site uses
      # (ROUTER-V2-BYPASSES-ARM-LADDER-FILTER-01) -- the arbiter's own matrix
      # can list haiku/opus as capable-and-uncapped, but neither is safe to
      # auto-spawn, and the pre-fix wiring set candidate_arms directly from
      # _arb_chain with no filter at all.
      if _adopt_v2_chain "${sig8}" arbiter "${_arb_chain}"; then
        # T17 fix-round (H1): journal the arm that will ACTUALLY spawn first
        # (candidate_arms[0], post-filter/post-rotation), not the raw
        # arbiter pick -- the spawn loop below iterates candidate_arms from
        # index 0, so pre-fix the journal's arm= value and the first
        # worker_spawned model could legitimately differ.
        arm="${candidate_arms[0]}"; reason="${_arb_reason:-cheapest_capable}"; router_label="arbiter"
        _MS_MODEL="${_arb_model:-${arm}}"
        [[ "${arm}" == codex ]] && export RESOLVED_CODEX_TIER="${_arb_tier:-standard}"
        emit decision "route_resolved by=arbiter role=worker arm=${arm} model=${_arb_model:-${arm}} tier=${RESOLVED_CODEX_TIER:-${_arb_tier:-standard}} task=${sig8} reason=${reason} arbiter_pick=${_arb_arm} ${_arb_util}"
      else
        candidate_arms=("${_pre_arb_candidate_arms[@]}")
        emit decision "arbiter_broken task=${sig8} rc=${_arb_rc} reason=fail_open_to_ladder note=chain_not_dispatchable arbiter_pick=${_arb_arm}"
      fi
    elif [[ ${_arb_rc} -eq 3 && "${_arb_reason}" == all_arms_capped ]]; then
      emit decision "route_resolved by=arbiter role=worker arm=refuse task=${sig8} reason=all_arms_capped ${_arb_util}"
      _model_select_telemetry fail all_arms_capped refuse
      _dl_note "${sig8}" refused all_arms_capped "${_arb_util}" "${founder_task_id}"
      exit 4
    else
      # rc=68 (no_capable_cell, a config-vocabulary gap -- T17 C1) falls
      # through here too: a config drift is never a hard refusal, only a
      # fail-open to the ladder, same as any other arbiter fault.
      emit decision "arbiter_broken task=${sig8} rc=${_arb_rc} reason=fail_open_to_ladder"
    fi
  else
    emit decision "arbiter_broken task=${sig8} rc=127 reason=missing_fail_open_to_ladder"
  fi

  # ARM-LADDER-HAS-NO-QUOTA-PRECHECK-01 P2: skip arms whose provider is locked
  # out before attempting to spawn. A per-provider lockout record
  # (quota-lockout-<provider>.json in the ledger dir) carries locked_until_epoch.
  # A missing/unreadable record means "not locked" — never fail closed. Each
  # skip is journalled so a lead reading the journal sees WHY an arm was passed
  # over.
  local _glm_quota_benched=""
  local _primary_arm_benched=0
  if [[ ${#candidate_arms[@]} -gt 0 ]]; then
    local -a _qpc_kept=()
    local _qpc_arm _qpc_prov
    for _qpc_arm in "${candidate_arms[@]}"; do
      _qpc_prov="$(_arm_provider "${_qpc_arm}")"
      if _provider_available "${_qpc_prov}"; then
        _qpc_kept+=("${_qpc_arm}")
      else
        [[ "${_qpc_arm}" == "${candidate_arms[0]:-}" ]] && _primary_arm_benched=1
        emit decision "quota_precheck_skip model=${_qpc_arm} provider=${_qpc_prov} task=${sig8} reason=provider_quota_locked class=$(_lockout_record_field "${_qpc_prov}" class)"
        # V3-GLM-LADDER-01 C1/D3: a glm bench here is the same founder-visible event as
        # a live glm_refused_* refusal (candidate never even got attempted) -- park +
        # count it identically so the ladder-loop can't hide behind the precheck.
        # GLM-53-FLASH-ARM-01: glm-flash benches on the same glm provider lockout
        # record, so it is the same founder-visible event too.
        if [[ "${_qpc_arm}" == "glm" || "${_qpc_arm}" == "glm-flash" ]]; then
          _glm_quota_benched="glm_refused_quota_precheck"
          _glm_park_deferred "${sig8}" "${_glm_quota_benched}" "${mission}" || true
          # A bench is the same founder-visible event as a live refusal (D3) --
          # the credit watchdog must fire here too, not only from the live-refusal
          # reroute path below, or it silently stops updating once glm starts
          # getting benched instead of attempted-and-refused.
          local _qpc_credits_out _qpc_credits
          _qpc_credits_out="$(bash "${LEADV2_ROUTER_V2_BIN:-${SCRIPT_DIR}/leadv2-router-v2.sh}" resolve --chain "${_qpc_arm}" --task-id "${sig8}" 2>/dev/null)"
          _qpc_credits="$(printf '%s\n' "${_qpc_credits_out}" | sed -n 's/^credits=//p')"
          _codex_credits_watch "${_qpc_credits:-}" || true
        fi
      fi
    done
    if [[ ${#_qpc_kept[@]} -eq 0 ]]; then
      emit decision "dispatch_rolled_back reason=all_arms_quota_locked task=${sig8}"
      log_err "every candidate arm is quota-locked; refusing to dispatch"
      _dl_note "${sig8}" refused all_arms_quota_locked "" "${founder_task_id}"
      exit 4
    fi
    candidate_arms=("${_qpc_kept[@]}")
  fi

  # ARBITER-BENCH-FALLBACK-GAP-01: a provider lockout can remove the arm the
  # initial arbiter chose after that initial decision.  Re-enter the arbiter
  # with precisely the still-spawnable arms, rather than letting the legacy
  # candidate order decide the fallback leg.  The allowed set prevents the
  # arbiter from resurrecting the benched arm from its capability matrix.
  if [[ "${_primary_arm_benched}" == "1" && ${#candidate_arms[@]} -gt 0 ]] && declare -F route_arbiter >/dev/null 2>&1; then
    local _bf_desc _bf_out _bf_rc _bf_chain _bf_arm _bf_util _bf_allowed
    _bf_allowed="$(IFS=,; printf '%s' "${candidate_arms[*]}")"
    _bf_desc="$(python3 -c 'import json,sys; print(json.dumps({"kind":sys.argv[1],"size":sys.argv[2],"allowed_arms":[x for x in sys.argv[3].split(",") if x]}))' "${kind:-code}" "${task_class:-standard}" "${_bf_allowed}")"
    _bf_out="$(route_arbiter worker "${_bf_desc}")"; _bf_rc=$?
    _bf_arm="$(printf '%s\n' "${_bf_out}" | sed -n 's/.*arm=\([^ ]*\).*/\1/p')"
    _bf_chain="$(printf '%s\n' "${_bf_out}" | sed -n 's/.*chain=\([^ ]*\).*/\1/p')"
    _bf_util="$(printf '%s\n' "${_bf_out}" | sed -n 's/.*\(util_glm=.*\)$/\1/p')"
    if [[ ${_bf_rc} -eq 0 && -n "${_bf_arm}" && "${_bf_arm}" != refuse ]] && _adopt_v2_chain "${sig8}" bench_fallback "${_bf_chain}"; then
      arm="${candidate_arms[0]}"; router_label="arbiter"
      emit decision "route_headroom_chosen task=${sig8} arm=${arm} after=primary_arm_benched ordered=$(IFS=,; printf '%s' "${candidate_arms[*]}") source=arbiter ${_bf_util}"
    else
      emit decision "arbiter_broken task=${sig8} rc=${_bf_rc} reason=bench_fallback_fail_open_to_ladder"
    fi
  fi

  # ROUTER-QUOTA-DRIVEN-01 (T6): filter candidate_arms by LIVE quota truth
  # BEFORE the operator-override block below. An arm with zero usable headroom
  # (leadv2-quota-read.py T1 usable_now = remaining_pct / max(hours_to_reset,1))
  # is skipped AUTOMATICALLY and returns to rotation on its own the instant its
  # window resets -- no file to edit, nothing to remember. This is what
  # replaced the 2026-07-28 incident: Codex at 0 credits still answers
  # status=completed, so only the quota READER -- never a spawn outcome --
  # can see it is dry; a hand-maintained exclusion list was the stopgap until
  # this shipped and is founder-rejected as the permanent answer.
  # V2 is shadow/off by default.  LEADV2_ROUTER_V2=0 is the one-step rollback
  # and leaves the legacy candidate order byte-for-byte untouched; the narrow
  # QUOTA_FILTER switch remains available while this early compatibility path
  # is replaced by the complete L1→L3 resolver in the later integration task.
  if [[ "${LEADV2_ROUTER_V2:-0}" == "1" && "${LEADV2_ROUTER_V2_QUOTA_FILTER:-1}" != "0" && "${router_label}" != "v2" ]]; then
    local _rv2_bin="${LEADV2_ROUTER_V2_BIN:-${SCRIPT_DIR}/leadv2-router-v2.sh}"
    if [[ -f "${_rv2_bin}" ]]; then
      local _rv2_chain _rv2_out _rv2_rc _rv2_eligible _rv2_ordered
      _rv2_chain="$(IFS=,; printf '%s' "${candidate_arms[*]}")"
      _rv2_out="$(bash "${_rv2_bin}" resolve --chain "${_rv2_chain}" --task-id "${sig8}" 2>/dev/null)"
      _rv2_rc=$?
      _rv2_eligible="$(printf '%s\n' "${_rv2_out}" | sed -n 's/^eligible=//p')"
      _rv2_ordered="$(printf '%s\n' "${_rv2_out}" | sed -n 's/^ordered=//p')"
      if [[ ${_rv2_rc} -eq 3 || -z "${_rv2_eligible}" ]]; then
        emit decision "dispatch_rolled_back reason=all_arms_exhausted task=${sig8} by=router_v2 chain=${_rv2_chain}"
        log_err "every candidate arm is quota-exhausted (chain='${_rv2_chain}'); refusing to dispatch"
        _dl_note "${sig8}" refused all_arms_exhausted_quota "chain=${_rv2_chain}" "${founder_task_id}"
        exit 4
      fi
      local _rv2_pick="${_rv2_eligible}"
      if [[ "${LEADV2_ROUTER_V2_QUOTA_ORDER:-1}" != "0" && -n "${_rv2_ordered}" ]]; then
        _rv2_pick="${_rv2_ordered}"
      else
        [[ "${LEADV2_ROUTER_V2_QUOTA_ORDER:-1}" != "0" ]] && emit decision "router_v2_no_ordered_key task=${sig8}"
      fi
      # ROUTER-V2-BYPASSES-ARM-LADDER-FILTER-01 site A: adopt through the SAME
      # normalize + DISPATCHABLE_BUILD_ARMS filter as the primary v2 path --
      # never a raw read -a from the resolver's ordered=/eligible=. (This
      # branch is currently UNREACHABLE: router_label is "v2" exactly when
      # LEADV2_ROUTER_V2=1, and this guard needs the opposite combination. The
      # adopter is wired anyway so a future guard fix cannot re-open the hole.)
      if ! _adopt_v2_chain "${sig8}" quota_filter "${_rv2_pick}"; then
        log_err "every re-resolved arm is not dispatchable (chain='${_rv2_pick}'); refusing to dispatch"
        _dl_note "${sig8}" refused all_arms_not_dispatchable_v2 "chain=${_rv2_pick}" "${founder_task_id}"
        exit 4
      fi
    fi
  fi

  # ARM-EXCLUSION-01: take an arm out of service without editing the chain.
  # Source: $LEADV2_EXCLUDED_ARMS, else ~/.claude/leadv2-excluded-arms (one arm
  # per line, '#' comments ignored).  This is now an explicit OPERATOR OVERRIDE
  # applied after the automatic quota filter above -- kept for the "take this
  # arm out no matter what its quota says" emergency case, not as the primary
  # exhaustion-detection path.  Revert = delete the file / unset the env var.
  local _ex_src="${LEADV2_EXCLUDED_ARMS:-}"
  if [[ -z "${_ex_src}" && -r "${HOME}/.claude/leadv2-excluded-arms" ]]; then
    _ex_src=$(grep -vE '^\s*(#|$)' "${HOME}/.claude/leadv2-excluded-arms" 2>/dev/null | tr '\n' ' ')
  fi
  if [[ -n "${_ex_src//[[:space:],]/}" ]]; then
    local -a _kept=()
    local _ex_arm
    for _ex_arm in "${candidate_arms[@]}"; do
      if [[ " ${_ex_src//,/ } " == *" ${_ex_arm} "* ]]; then
        emit decision "arm_excluded by=router model=${_ex_arm} task=${sig8} reason=operator_excluded"
        continue
      fi
      _kept+=("${_ex_arm}")
    done
    if [[ ${#_kept[@]} -eq 0 ]]; then
      log_err "every candidate arm is excluded (excluded='${_ex_src}'); refusing to dispatch"
      _dl_note "${sig8}" refused all_arms_excluded "excluded=${_ex_src}" "${founder_task_id}"
      exit 4
    fi
    candidate_arms=("${_kept[@]}")
  fi

  # Record the final chain before the candidate loop consumes it.  In
  # particular, this makes a Kimi admission skip observable in the same
  # decision journal as the resolved route.
  emit decision "candidate_chain task=${sig8} arms=$(IFS=,; printf '%s' "${candidate_arms[*]}")"
  if [[ "${router_label}" == "v2" && "${LEADV2_ROUTER_V2_QUOTA_ORDER:-1}" != "0" && -n "${v2_headroom}" ]]; then
    local _v2_scores _v2_unknown
    _v2_scores="$(python3 -c 'import json,sys; v=json.loads(sys.argv[1] or "[]"); print(json.dumps({r["arm"]:r.get("score") for r in v}, sort_keys=True, separators=(",", ":")))' "${v2_vector:-[]}" 2>/dev/null || printf '{}')"
    _v2_unknown="$(python3 -c 'import json,sys; h=json.loads(sys.argv[1]); print(",".join(sorted(k for k,v in h.items() if v is None)) or "none")' "${v2_headroom}" 2>/dev/null || printf 'none')"
    emit decision "route_headroom_chosen task=${sig8} arm=${candidate_arms[0]} after=initial ordered=$(IFS=,; printf '%s' "${candidate_arms[*]}") headroom=${v2_headroom} credits=${v2_credits:-{}} scores=${_v2_scores} source=router_v2 unknown=${_v2_unknown}"
    # NOT ${v2_credits:-{}} -- bash misparses a {-default containing its own
    # braces (adds a stray trailing "}"); plain expansion + the helper's own
    # empty-string no-op does the same job safely.
    _codex_credits_watch "${v2_credits:-}" || true
  fi

  # SUPERVISOR-AUDIT-01 model-stamp extension (founder 2026-07-30): stamp the
  # arm_resolved value now (the resolver's PRIMARY pick) so the row is never
  # left at fanout's pre-routing classifier guess even if the candidate loop
  # below never gets a chance to run. The loop's arc==0 branch re-stamps with
  # the ACTUALLY-launched candidate (same "build" phase, model only) once one
  # is confirmed -- arm_resolved != candidate whenever the primary is refused
  # mid-loop (e.g. glm quota-gate refusal falling to sonnet), so that second
  # stamp is the one that ends up truthful, not this one.
  _stamp_active_phase "${founder_task_id}" "build" "${arm}"
  # PHASES-ARE-THE-ONLY-PATH-01: record build phase as running with the resolved arm handle.
  bash "${PHASE_RECORD_BIN}" record "${sig8}" build --status running \
    --handle "dispatch-${sig8}-build" \
    --task-id "${founder_task_id}" --owner "$(basename "$0"):cmd_resolve" 2>/dev/null || true
  # N1-EMPTY-LANE-IS-NOT-A-PASS (B.2): the candidate loop is wrapped in a restartable
  # while so a lock-busy refusal can re-resolve the arm mid-loop and re-enter over a
  # rebuilt chain. bash expands "${candidate_arms[@]}" once at for-entry, so merely
  # reassigning the array would NOT change the remaining iterations -- the break+reenter
  # handshake (_reenter=1 -> break for -> outer while continues) is what makes a
  # mid-loop chain swap effective. One-shot via _reresolved_lock_busy (no unbounded retry).
  local candidate arc _reresolved_lock_busy="" _reordered_after_quota_gate="" _quota_gate_reroute=0 _reenter _fallback_from="" _fallback_reason=""
  while true; do
  _reenter=0
  for candidate in "${candidate_arms[@]}"; do
    if [[ -n "${_fallback_from}" ]]; then
      emit decision "route_fallback from=${_fallback_from} to=${candidate} task=${sig8} reason=${_fallback_reason:-arm_refused}"
      _MS_FALLBACKS=$(( ${_MS_FALLBACKS:-0} + 1 ))
      _fallback_from=""; _fallback_reason=""
    fi
    # T17 fix-round (H3): when the arbiter routed this lane, its tier= is the
    # authority for the arbiter's own pick (candidate_arms[0]) -- ${tier}
    # here is the pre-arbiter ladder/resolver tier and does not apply to an
    # arbiter-chosen codex cell. Later loop iterations (fallback candidates
    # past index 0) are not arbiter picks even on an arbiter-routed lane, so
    # this only substitutes on the exact first-iteration match.
    if [[ "${candidate}" == "codex" ]]; then
      if [[ "${router_label:-}" == "arbiter" && "${candidate}" == "${candidate_arms[0]:-}" && -n "${_arb_tier:-}" ]]; then
        export RESOLVED_CODEX_TIER="${_arb_tier}"
      else
        export RESOLVED_CODEX_TIER="${tier:-standard}"
      fi
    fi
    local _candidate_mission="${mission}"
    if [[ -n "${LAST_ARM_CONTINUATION:-}" ]]; then
      # T13-SLICE1 W3: carry GLM's exit76-receipt tail output into the next
      # arm's mission exactly once, then clear it so a later, unrelated
      # candidate never inherits a stale continuation block.
      _candidate_mission="${_candidate_mission}

===== CONTINUATION FROM GLM (exit76_receipt) =====
${LAST_ARM_CONTINUATION}
===== END CONTINUATION ====="
      LAST_ARM_CONTINUATION=""
    fi
    if [[ "${candidate}" == "sonnet" && "${_quota_gate_reroute}" == "1" ]]; then
      _candidate_mission="GLM_FIRST_EXCEPTION=glm_quota_gate_80
(router-issued: GLM quota gate refused this lane at >=80%; arm chosen from live headroom.)

${mission}"
    fi
    # R10 H1: do this in the parent shell, before atomic_dispatch... can call
    # a launcher.  Its worker becomes independently live before that function
    # returns; leaving the EXIT slot armed until the later arc==0 branch made a
    # TERM in that window delete GLM/Codex's still-live registry row.
    [[ "${spawn}" == "1" ]] && _dispatch_disarm_slot_before_spawn
    atomic_dispatch_reserve_spawn_confirm "${sig}" "${candidate}" "${rule}" "${_candidate_mission}" "${sig8}" "${spawn}"
    arc=$?
    # Re-arm only outcomes that prove no launcher ran (duplicate/lock/reserve)
    # or that spawn_worker rejected before reporting liveness.  Ambiguous and
    # post-spawn outcomes remain disarmed: preserving a possible live worker is
    # safer than deleting its row from an EXIT trap.
    case "${arc}" in 2|3|4|6) _dispatch_rearm_slot_after_no_spawn ;; esac
    case "${arc}" in
    2)
      if [[ "${force}" == "1" ]]; then
        emit decision "dispatch_override_rejected reason=force_not_permitted task=${sig8} ledger=$(dispatch_ledger_file)"
      fi
      emit decision "dispatch_refused reason=duplicate_task_signature task=${sig8} ledger=$(dispatch_ledger_file)"
      # FIX (wave2 round2 finding 1): same reasoning as the opus duplicate branch above --
      # a duplicate-signature refusal only means ANOTHER caller for this sig8 is already in
      # flight. Writing "refused" here would win the terminal ledger's write-once race and
      # permanently discard whatever landed/parked/dead verdict the actual winner earns.
      printf 'dispatch_refused reason=duplicate_task_signature task=%s\n' "${sig8}"
      exit 2
      ;;
    0)
      # Re-stamp with the CONFIRMED-launched arm, phase unchanged -- the truthful value
      # once the primary arm_resolved pick was refused and the loop fell to a fallback.
      _stamp_active_phase "${founder_task_id}" "build" "${candidate}"
      # PHASES-ARE-THE-ONLY-PATH-01: re-record build with the confirmed candidate.
      bash "${PHASE_RECORD_BIN}" record "${sig8}" build --status running \
        --handle "dispatch-${sig8}-${candidate}" \
        --task-id "${founder_task_id}" --owner "$(basename "$0"):cmd_resolve" 2>/dev/null || true
      # (dispatch-00629379, 2026-07-30; env cleaned up under ONE-PATH-EVERYWHERE-01):
      # `reviewer_arms` here now feeds ONLY LEADV2_DISPATCH_CANDIDATE_ARMS (the silent-
      # arm advance-arm probe) -- the sibling LEADV2_DISPATCH_REVIEWER_ARMS export was
      # DEAD (leadv2-dispatch-product-close.sh never read it) and has been deleted.
      # Reusing the BUILD candidate chain as the reviewer list was the root cause of
      # "review gate has no available reviewer" (candidate==author always collided);
      # product-close / leadv2-review-run.sh resolve their own reviewer pool via
      # lib/leadv2-glm-policy-resolve.py --review-pool --author, an ordered, quota-
      # filtered, author-excluding pool independent of this build chain. The local var
      # itself is kept (not deleted) to avoid an unrelated call-signature change here.
      local reviewer_arms
      reviewer_arms="$(IFS=,; printf '%s' "${candidate_arms[*]}")"
      # ARM-PRODUCES-NOTHING-AND-CHAIN-NEVER-ADVANCES-01 (3a): persist the lane's
      # mission text ONCE here, at spawn time, so a later `advance-arm` re-spawn (fired
      # from the close gate's silent-arm probe) can launch the next candidate on the
      # SAME mission without re-deriving it from router state that may have moved on.
      local _lane_mission_path=""
      if [[ "${product_class}" == "product" ]]; then
        _lane_mission_path="${PROJECT_ROOT}/docs/handoff/dispatch-${sig8}/lane-mission.md"
        mkdir -p "$(dirname "${_lane_mission_path}")" 2>/dev/null
        printf '%s' "${mission}" > "${_lane_mission_path}" 2>/dev/null || _lane_mission_path=""
      fi
      if [[ "${product_class}" == "product" ]] && ! spawn_product_close "${sig8}" "${candidate}" "${LAST_WORKER_HANDLE:-}" "${reviewer_arms}" "${lane_writes}" "${founder_task_id}" "${_lane_mission_path}" "${LANE_DELIVERABLE_DECL:-}"; then
        # The worker is already live; make the failed postflight launch visible rather than
        # pretending close evidence will arrive.  Do not kill the independently-owned worker.
        log_err "product close gate could not be launched for task=${sig8}"
      fi
      # V3-GLM-LADDER-01 Lever 3: attempted[] (not LAST_ARM_OUTCOME) is the durable
      # record of what was refused earlier in the loop -- by the time sonnet lands here,
      # LAST_ARM_OUTCOME has been overwritten by sonnet's own spawn outcome.
      if [[ "${candidate}" == "sonnet" ]]; then
        local _attempted_entry _exc_reason=""
        if [[ -n "${_glm_quota_benched}" ]]; then
          _exc_reason="${_glm_quota_benched}"
        else
          for _attempted_entry in "${attempted[@]}"; do
            case "${_attempted_entry}" in
              glm_refused_quota_gate|glm_refused_postspawn_quota)
                _exc_reason="${_attempted_entry}"
                break
                ;;
            esac
          done
        fi
        [[ -n "${_exc_reason}" ]] && { _arm_exception_bump "${_exc_reason}" "${sig8}" || true; }
      fi
      emit decision "route_resolved by=router router=${router_label} model=${candidate} task=${sig8} rule=${rule} reason=${reason}"
      printf 'route_resolved by=router router=%s model=%s task=%s rule=%s reason=%s\n' "${router_label}" "${candidate}" "${sig8}" "${rule}" "${reason}"
      # FP-06: dispatch-attempt terminal -- the confirmed live spawn IS this
      # attempt's win. Emitted before the LANDED-AT-SPAWN block so the row
      # lands even if a later line in this branch were to fail.
      _model_select_telemetry win worker_spawned "${candidate}"
      # A product dispatch's terminal state is owned by dispatch-product-close.sh (it runs
      # the e2e/review gates and knows the real outcome) -- writing "landed" HERE for a
      # product task would let a later, more informative dead/parked verdict from that
      # script lose the write-once race. A non-product spawn has no terminal at spawn time
      # either: every non-product arm reaches rc=0 here only after launching an ASYNC
      # background worker that has done zero work, and "landed" is a future-claim that
      # permanently blocks the lane's real terminal under write-once semantics and trips
      # the codex-lead dup-guard. Absence of a terminal row IS the honest state until the
      # lane's own close/sweep path resolves it. The already-written confirmed reservation
      # row (dispatch_confirm) remains the only spawn-time record; no new row type is
      # needed -- dispatch_ledger_sweep_write_dead already recovers abandoned lanes.
      # (LANDED-AT-SPAWN-01)
      # W-1a §3.1: a live worker was spawned -- do NOT reap this lane's worktree on EXIT
      # (the async worker + close gate still need it). §3.3: emit the loud interim line
      # naming the absolute path where the finished lane's worktree is left on disk --
      # the stated interim behaviour (a finished lane leaves its worktree with a loud line).
      _DISPATCH_WORKER_LIVE=1
      # R5 §4 worker-spawn HANDOFF: the active row now belongs to the spawned
      # worker (_spawn_worker_body's set_worker_pid flipped pid_role to
      # "worker"), so the EXIT-trap slot release is disarmed from here on.
      DISPATCH_SLOT_REG_ID=""
      DISPATCH_SLOT_PRESPAWN_DISARMED=""
      if [[ -n "${WORK_ROOT}" && "${WORK_ROOT}" != "${PROJECT_ROOT}" ]]; then
        emit decision "lane_worktree_left task=${sig8} founder_task=${founder_task_id:-} path=${WORK_ROOT}"
        log "lane worktree left on disk for task=${sig8}: ${WORK_ROOT}"
      fi
      exit 0
      ;;
    7)
      attempted+=("${LAST_ARM_OUTCOME:-${candidate}_refused}")
      _fallback_from="${candidate}"; _fallback_reason="${LAST_ARM_OUTCOME:-arm_refused}"
      # An exit-76 receipt is a new spawn leg, not permission to continue in
      # the stale ladder order.  Re-arbitrate over the remaining candidates.
      if [[ "${LAST_ARM_OUTCOME:-}" == "exit76_receipt" ]] && declare -F route_arbiter >/dev/null 2>&1; then
        local -a _e76_remaining=()
        local _e76_a
        for _e76_a in "${candidate_arms[@]}"; do [[ "${_e76_a}" == "${candidate}" ]] || _e76_remaining+=("${_e76_a}"); done
        if [[ ${#_e76_remaining[@]} -gt 0 ]]; then
          local _e76_allowed _e76_desc _e76_out _e76_rc _e76_arm _e76_chain _e76_util
          _e76_allowed="$(IFS=,; printf '%s' "${_e76_remaining[*]}")"
          _e76_desc="$(python3 -c 'import json,sys; print(json.dumps({"kind":sys.argv[1],"size":sys.argv[2],"allowed_arms":[x for x in sys.argv[3].split(",") if x]}))' "${kind:-code}" "${task_class:-standard}" "${_e76_allowed}")"
          _e76_out="$(route_arbiter worker "${_e76_desc}")"; _e76_rc=$?
          _e76_arm="$(printf '%s\n' "${_e76_out}" | sed -n 's/.*arm=\([^ ]*\).*/\1/p')"
          _e76_chain="$(printf '%s\n' "${_e76_out}" | sed -n 's/.*chain=\([^ ]*\).*/\1/p')"
          _e76_util="$(printf '%s\n' "${_e76_out}" | sed -n 's/.*\(util_glm=.*\)$/\1/p')"
          if [[ ${_e76_rc} -eq 0 && -n "${_e76_arm}" && "${_e76_arm}" != refuse ]] && _adopt_v2_chain "${sig8}" exit76_continuation "${_e76_chain}"; then
            arm="${candidate_arms[0]}"; router_label="arbiter"; _reenter=1
            emit decision "route_headroom_chosen task=${sig8} arm=${arm} after=exit76_continuation ordered=$(IFS=,; printf '%s' "${candidate_arms[*]}") source=arbiter ${_e76_util}"
            break
          fi
          emit decision "arbiter_broken task=${sig8} rc=${_e76_rc} reason=exit76_fail_open_to_ladder"
        fi
      fi
      # V3-GLM-LADDER-01 Lever 1: park BEFORE the re-resolve/fallthrough below, so a
      # crash between refusal and the sonnet respawn still leaves the task recoverable.
      # Gate: candidate==glm at refusal time is already the router's own "glm-fitting"
      # answer -- do not re-classify (design §4).
      # D2: park + count only the quota family -- a transient refusal (e.g.
      # glm_refused_lock_busy) parks nothing and bumps nothing.
      # GLM-53-FLASH-ARM-01: glm-flash parks identically -- same quota family,
      # same launcher refusal vocabulary (glm_refused_*).
      if [[ "${candidate}" == "glm" || "${candidate}" == "glm-flash" ]]; then
        case "${LAST_ARM_OUTCOME:-}" in
          glm_refused_quota_gate|glm_refused_postspawn_quota)
            _glm_park_deferred "${sig8}" "${LAST_ARM_OUTCOME}" "${_candidate_mission}" || true
            ;;
        esac
      fi
      if [[ "${LAST_ARM_OUTCOME:-}" == "glm_refused_quota_gate" && -z "${_reordered_after_quota_gate}" && "${LEADV2_ROUTER_V2_ON_QUOTA_GATE:-1}" != "0" ]]; then
        _reordered_after_quota_gate=1
        local _qg_bin="${LEADV2_ROUTER_V2_BIN:-${SCRIPT_DIR}/leadv2-router-v2.sh}" _qg_chain _qg_out _qg_rc _qg_eligible _qg_ordered _qg_headroom _qg_vector _qg_credits
        local _qg_remaining
        local -a _qg_next=()
        for _qg_remaining in "${candidate_arms[@]}"; do
          # GLM-53-FLASH-ARM-01: drop BOTH glm arms from the post-quota-gate
          # reorder -- they share the one glm quota bucket that just refused.
          [[ "${_qg_remaining}" == "glm" || "${_qg_remaining}" == "glm-flash" ]] || _qg_next+=("${_qg_remaining}")
        done
        _qg_chain="$(IFS=,; printf '%s' "${_qg_next[*]}")"
        if [[ -n "${_qg_chain}" && -f "${_qg_bin}" ]]; then
          _qg_out="$(bash "${_qg_bin}" resolve --chain "${_qg_chain}" --task-id "${sig8}" 2>/dev/null)"; _qg_rc=$?
          _qg_eligible="$(printf '%s\n' "${_qg_out}" | sed -n 's/^eligible=//p')"
          _qg_ordered="$(printf '%s\n' "${_qg_out}" | sed -n 's/^ordered=//p')"
          _qg_headroom="$(printf '%s\n' "${_qg_out}" | sed -n 's/^headroom=//p')"
          _qg_vector="$(printf '%s\n' "${_qg_out}" | sed -n 's/^vector=//p')"
          _qg_credits="$(printf '%s\n' "${_qg_out}" | sed -n 's/^credits=//p')"
          if [[ ${_qg_rc} -eq 0 && -n "${_qg_eligible}" ]]; then
            local _qg_pick="${_qg_eligible}"
            if [[ "${LEADV2_ROUTER_V2_QUOTA_ORDER:-1}" != "0" && -n "${_qg_ordered}" ]]; then
              _qg_pick="${_qg_ordered}"
            else
              [[ "${LEADV2_ROUTER_V2_QUOTA_ORDER:-1}" != "0" ]] && emit decision "router_v2_no_ordered_key task=${sig8}"
            fi
            # ROUTER-V2-BYPASSES-ARM-LADDER-FILTER-01 site B: adopt through the
            # shared normalize + DISPATCHABLE_BUILD_ARMS filter, but NEVER exit
            # on an empty survivor set -- B runs inside the candidate loop, so
            # an exit here would turn a recoverable refusal into a dead lane.
            # Adopt into a scratch copy; keep the pre-reroute chain on failure.
            local -a _qg_pre=("${candidate_arms[@]}")
            if _adopt_v2_chain "${sig8}" quota_gate "${_qg_pick}"; then
              local _qg_scores _qg_unknown
              _qg_scores="$(python3 -c 'import json,sys; v=json.loads(sys.argv[1] or "[]"); print(json.dumps({r["arm"]:r.get("score") for r in v}, sort_keys=True, separators=(",", ":")))' "${_qg_vector:-[]}" 2>/dev/null || printf '{}')"
              _qg_unknown="$(python3 -c 'import json,sys; h=json.loads(sys.argv[1]); print(",".join(sorted(k for k,v in h.items() if v is None)) or "none")' "${_qg_headroom}" 2>/dev/null || printf 'none')"
              emit decision "route_headroom_chosen task=${sig8} arm=${candidate_arms[0]} after=glm_quota_gate ordered=$(IFS=,; printf '%s' "${candidate_arms[*]}") headroom=${_qg_headroom} credits=${_qg_credits:-{}} scores=${_qg_scores} source=router_v2 unknown=${_qg_unknown}"
              _codex_credits_watch "${_qg_credits:-}" || true
              _quota_gate_reroute=1
              _reenter=1
              break
            fi
            # Empty survivor set: the helper already journalled
            # dispatch_rolled_back ... site=quota_gate. Fall back to the
            # pre-reroute chain instead of dying here.
            candidate_arms=("${_qg_pre[@]}")
            emit decision "router_v2_reorder_failed task=${sig8} rc=0 reason=no_dispatchable_arms"
          fi
          # PLUGIN-RELIABILITY-01 D5: journal reorder failure so refusal chains
          # are debuggable instead of silently falling through.
          if [[ ${_qg_rc} -ne 0 ]]; then
            emit decision "router_v2_reorder_failed task=${sig8} rc=${_qg_rc} reason=resolve_nonzero"
          elif [[ -z "${_qg_eligible}" ]]; then
            emit decision "router_v2_reorder_failed task=${sig8} rc=0 reason=no_eligible_arms"
          fi
        fi
      fi
      # N1-EMPTY-LANE-IS-NOT-A-PASS (B.2): a lock-busy refusal carries a routing
      # signal (DC_GLM_LOCK_BUSY) the resolver consumes only at CLASSIFICATION time
      # -- before any spawn is attempted (resolve_arm at :2101 binds arm/rule/reason
      # once, up front). A lock that becomes busy AT spawn time never reached it, so
      # the PRIMARY arm was resolved against a pre-lock picture and the policy rule
      # glm_lock_busy_no_second_channel (routing.yaml sonnet_exceptions) could not
      # fire. Re-resolve NOW with the signal set: the resolver -- not a hardcoded
      # list -- decides where the refused work goes. If it returns a DIFFERENT arm,
      # rebuild the candidate chain from it and re-enter the loop; if it returns the
      # same arm (rule not configured), fall through to the existing chain. One-shot.
      if [[ "${LAST_ARM_OUTCOME:-}" == "glm_refused_lock_busy" && -z "${_reresolved_lock_busy}" ]]; then
        _reresolved_lock_busy=1
        if [[ "${DC_GLM_LOCK_BUSY:-}" != "1" ]]; then
          export DC_GLM_LOCK_BUSY=1
          local _rr _rr_arm _rr_rule _rr_reason
          _rr="$(resolve_arm)"
          _rr_arm="$(printf '%s\n' "${_rr}" | sed -n 's/^arm=//p')"
          _rr_rule="$(printf '%s\n' "${_rr}" | sed -n 's/^rule=//p')"
          _rr_reason="$(printf '%s\n' "${_rr}" | sed -n 's/^reason=//p')"
          if [[ -n "${_rr_arm}" && "${_rr_arm}" != "${arm}" ]]; then
            arm="${_rr_arm}"; rule="${_rr_rule}"; reason="${_rr_reason}"
            emit decision "arm_reresolved by=router trigger=glm_lock_busy arm=${arm} rule=${rule} reason=${reason} task=${sig8} router=${router_label}"
            _build_candidate_chain "${arm}" "${sig8}"
            _apply_kimi_admission "${kimi_admission_mission}" "${sig8}" "${lane_writes}" "${kimi_fit}"
            _reenter=1
            break   # break the for; outer while re-enters over the rebuilt chain
          fi
        fi
      fi
      continue
      ;;
    4)
      if [[ "${spawn}" != "1" ]]; then
        emit decision "route_resolved by=router router=${router_label} model=${candidate} task=${sig8} rule=${rule} reason=${reason}"
        printf 'route_resolved by=router router=%s model=%s task=%s rule=%s reason=%s\n' "${router_label}" "${candidate}" "${sig8}" "${rule}" "${reason}"
        emit decision "dispatch_rolled_back reason=no_spawn_dry_run task=${sig8}"
        # Dry-run: nothing was spawned or reserved (dispatch_abort already ran). No terminal
        # state exists to record -- writing one here would falsely claim a real dispatch
        # happened and block a LATER real (--spawn) call for the same sig8 forever.
        exit 0
      fi
      attempted+=("${LAST_ARM_OUTCOME:-${candidate}_failed_launcher}")
      _fallback_from="${candidate}"; _fallback_reason="${LAST_ARM_OUTCOME:-launcher_failed}"
      continue
      ;;
    5)
      # High finding b/c (fix-pass-4: now also covers a confirm-write failure AFTER a
      # successful spawn, not just an abort/rollback-write failure): the row may still be
      # sitting in the ledger in the wrong state, or the worker may be live but unrecorded.
      # NEVER report dispatch_rolled_back here; this is a hard error, distinct from the
      # retryable rc=4 case above.
      log_err "dispatch reservation could not be finalized for task=${sig8} model=${candidate} -- ledger write (confirm or abort) FAILED; a spawned worker may be live but NOT recorded -- check manually"
      emit decision "dispatch_rollback_failed task=${sig8} model=${candidate} rule=${rule} reason=$([[ "${spawn}" == "1" ]] && printf spawn_failed_or_confirm_write_failed || printf no_spawn_dry_run)"
      _dl_note "${sig8}" dead rollback_failed "model=${candidate}" "${founder_task_id}"
      # R5 §4: rc=5 means the spawn state is AMBIGUOUS (a worker may be live but
      # unrecorded) -- disarm the slot release; a genuinely dead row is the
      # sweep's to reap, never released on a guess.
      DISPATCH_SLOT_REG_ID=""
      exit 1
      ;;
    6)
      # FIX PASS 4: the RESERVATION write itself failed (read-only/full fs) -- nothing was
      # ever written, no spawn was ever attempted. Distinct from rc=5 (a write failure AFTER
      # a reservation already existed) so the log/journal reason is unambiguous.
      log_err "dispatch reservation FAILED for task=${sig8} model=${candidate} -- ledger write did not land (read-only/full fs?); refusing to spawn"
      emit decision "dispatch_reservation_failed task=${sig8} model=${candidate} rule=${rule}"
      _dl_note "${sig8}" dead reservation_failed "model=${candidate}" "${founder_task_id}"
      exit 1
      ;;
    3)
      log_err "dispatch lock-wait timeout for task=${sig8}"
      _dl_note "${sig8}" dead lock_timeout "" "${founder_task_id}"
      exit 1
      ;;
    *)
      log_err "atomic_dispatch_reserve_spawn_confirm: unexpected rc=${arc} for task=${sig8}"
      _dl_note "${sig8}" dead "unexpected_rc_${arc}" "" "${founder_task_id}"
      # R5 §4: unknown spawn state -- disarm rather than release on a guess.
      DISPATCH_SLOT_REG_ID=""
      exit 1
      ;;
    esac
  done
  [[ "${_reenter}" == "1" ]] && continue
  break
  done

  local attempted_csv
  attempted_csv="$(IFS=,; printf '%s' "${attempted[*]}")"
  emit decision "dispatch_rolled_back reason=all_arms_unavailable task=${sig8} attempts=${attempted_csv}"
  _model_select_telemetry fail all_arms_unavailable "${candidate}"
  log_err "all eligible dispatch arms declined or failed for task=${sig8}: ${attempted_csv}"
  _dl_note "${sig8}" dead all_arms_unavailable "attempts=${attempted_csv}" "${founder_task_id}"
  exit 4
}

# ARM-PRODUCES-NOTHING-AND-CHAIN-NEVER-ADVANCES-01 (3b): re-spawns the NEXT candidate arm
# on the SAME lane worktree/mission after the close gate's silent-arm probe (Fix 1, in
# leadv2-dispatch-product-close.sh) determined the current arm produced nothing. Reuses
# the existing spawn machinery (spawn_worker + _stamp_active_phase + spawn_product_close)
# instead of reimplementing any of it. Deliberately does NOT call dispatch_reserve/
# atomic_dispatch_reserve_spawn_confirm -- the duplicate-signature guard exists to stop
# TWO callers racing to claim the SAME sig8; here the sig8 is already confirmed to this
# lane (checked below) and this is a continuation of that same lane, not a new claim.
#   leadv2-dispatch-code.sh advance-arm --sig8 <sig8> --arm <next_arm>
#     --mission-file <path> --task-id <founder_task_id> [--worktree <lane_root>]
#     [--writes <csv>]
# exit 4 (no journal-worthy spawn attempted) when no CONFIRMED reservation row exists for
# this sig8 in the dispatch_reserve/confirm ledger (dispatch_ledger_file, NOT the terminal
# ledger) -- that row is this function's proof the sig8 legitimately belongs to a lane
# that already went through admission once.
#
# T13 slice2 fix-round (F1): bash-3.2-safe CSV suffix walk, mirroring
# _pc_next_arm_in_chain in leadv2-dispatch-product-close.sh. Returns the
# comma-joined suffix of <chain_csv> starting AT <arm> (inclusive) -- the arms
# not yet tried when the close gate advances a chain -- or rc1 when <arm> is
# absent from the chain or the chain is empty. Runs positionally clobbering
# (`set --`); call it in a command substitution like the product-close twin.
_advance_remaining_chain() {  # <chain_csv> <arm> -> stdout csv suffix; rc1 if arm not in chain
  local chain="$1" want="$2" tok out="" found=0
  [[ -n "${chain}" && -n "${want}" ]] || return 1
  local _oldifs="${IFS}"
  IFS=','
  set -- ${chain}
  IFS="${_oldifs}"
  for tok in "$@"; do
    tok="${tok#"${tok%%[![:space:]]*}"}"; tok="${tok%"${tok##*[![:space:]]}"}"
    [[ -z "${tok}" ]] && continue
    [[ ${found} -eq 0 && "${tok}" == "${want}" ]] && found=1
    if [[ ${found} -eq 1 ]]; then
      [[ -n "${out}" ]] && out="${out},${tok}" || out="${tok}"
    fi
  done
  [[ ${found} -eq 1 && -n "${out}" ]] || return 1
  printf '%s' "${out}"
}

cmd_advance_arm() {
  local sig8="" arm="" mission_file="" task_id="" worktree="" writes=""
  local -a phase_waivers=()
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --sig8)         [[ $# -ge 2 ]] || { log_err "--sig8 requires a value"; exit 4; }; sig8="$2"; shift 2 ;;
      --arm)          [[ $# -ge 2 ]] || { log_err "--arm requires a value"; exit 4; }; arm="$2"; shift 2 ;;
      --mission-file) [[ $# -ge 2 ]] || { log_err "--mission-file requires a value"; exit 4; }; mission_file="$2"; shift 2 ;;
      --task-id)      [[ $# -ge 2 ]] || { log_err "--task-id requires a value"; exit 4; }; task_id="$2"; shift 2 ;;
      --worktree)     [[ $# -ge 2 ]] || { log_err "--worktree requires a value"; exit 4; }; worktree="$2"; shift 2 ;;
      --writes)       [[ $# -ge 2 ]] || { log_err "--writes requires a value"; exit 4; }; writes="$2"; shift 2 ;;
      --phase-waiver) [[ $# -ge 2 ]] || { log_err "--phase-waiver requires a value"; exit 4; }; phase_waivers+=("$2"); shift 2 ;;
      *) log_err "advance-arm: unknown argument: $1"; exit 4 ;;
    esac
  done
  if [[ -z "${sig8}" || -z "${arm}" || -z "${mission_file}" ]]; then
    log_err "advance-arm: --sig8, --arm and --mission-file are required"
    exit 4
  fi
  if [[ ! -f "${mission_file}" ]]; then
    emit decision "arm_advance_refused task=${sig8} reason=no_mission_file"
    exit 4
  fi

  local ledger_f confirmed
  ledger_f="$(dispatch_ledger_file)"
  confirmed=""
  if [[ -f "${ledger_f}" ]]; then
    confirmed="$(grep -F "\"task_sig\":\"${sig8}" "${ledger_f}" 2>/dev/null | grep -F '"state":"confirmed"' | tail -1)"
  fi
  if [[ -z "${confirmed}" ]]; then
    emit decision "arm_advance_refused task=${sig8} reason=no_confirmed_reservation"
    log_err "advance-arm: no confirmed reservation for task=${sig8}; refusing"
    exit 4
  fi

  # PHASES-ARE-THE-ONLY-PATH-01 §5/D2: advance-arm also spawns a worker, so the
  # guard must run here too. cmd_advance_arm has no --class flag; resolve it
  # from the confirmed dispatch-ledger row, default to Standard if absent.
  local _adv_class
  _adv_class="$(printf '%s' "${confirmed}" | sed -n 's/.*"task_class":"\([^"]*\)".*/\1/p')"
  if [[ -z "${_adv_class}" ]]; then
    _adv_class="Standard"
    emit decision "phase_class_defaulted task=${sig8}"
  fi
  local _phase_waiver_args=()
  for _pw in "${phase_waivers[@]+"${phase_waivers[@]}"}"; do
    _phase_waiver_args+=(--waiver "$_pw")
  done
  _phase_precondition_guard "${sig8}" "${_adv_class}" "${writes}" "${_phase_waiver_args[@]+"${_phase_waiver_args[@]}"}" || exit 3

  local mission
  mission="$(cat "${mission_file}" 2>/dev/null)"
  [[ -n "${worktree}" && -d "${worktree}" ]] && WORK_ROOT="${worktree}"

  # T13 slice2 fix-round (F1, review): the --arm the close gate passes here is
  # a static CSV-position walk (_pc_next_arm_in_chain in product-close) -- this
  # spawn used to consume it directly, making advance-arm a 4th arm-SELECTION
  # point with no route_arbiter call. Gate it exactly like the other spawn
  # sites (initial resolve / bench-fallback / exit76 continuation): re-
  # arbitrate (worker role) over the REMAINING chain arms -- the suffix from
  # the proposed arm onward -- adopt the arbiter chain through _adopt_v2_chain
  # (same DISPATCHABLE_BUILD_ARMS filter as every adoption site), journal
  # route_headroom_chosen, and spawn candidate_arms[0]. An arbiter fault
  # (missing/broken/capped/chain-not-dispatchable) fails OPEN to the caller's
  # static pick -- the same fail-open-to-ladder contract as every other site.
  local -a candidate_arms=()
  local _adv_chain="${LEADV2_DISPATCH_CANDIDATE_ARMS:-}"
  if [[ -z "${_adv_chain}" ]]; then
    _adv_chain="$(bash "${JOURNAL_BIN}" tail "${sig8}" 100000 2>/dev/null | \
      grep -F "candidate_chain task=${sig8} arms=" | tail -1 | sed -n 's/.*arms=//p')"
  fi
  local _adv_remaining
  if _adv_remaining="$(_advance_remaining_chain "${_adv_chain}" "${arm}")" && [[ -n "${_adv_remaining}" ]] \
     && declare -F route_arbiter >/dev/null 2>&1; then
    local _adv_desc _adv_out _adv_rc _adv_arm _adv_chainout _adv_util
    _adv_desc="$(python3 -c 'import json,sys; print(json.dumps({"kind":"code","size":sys.argv[1],"allowed_arms":[x for x in sys.argv[2].split(",") if x]}))' \
      "$(printf '%s' "${_adv_class:-standard}" | tr '[:upper:]' '[:lower:]')" "${_adv_remaining}")"
    _adv_out="$(route_arbiter worker "${_adv_desc}")"; _adv_rc=$?
    _adv_arm="$(printf '%s\n' "${_adv_out}" | sed -n 's/.*arm=\([^ ]*\).*/\1/p')"
    _adv_chainout="$(printf '%s\n' "${_adv_out}" | sed -n 's/.*chain=\([^ ]*\).*/\1/p')"
    _adv_util="$(printf '%s\n' "${_adv_out}" | sed -n 's/.*\(util_glm=.*\)$/\1/p')"
    if [[ ${_adv_rc} -eq 0 && -n "${_adv_arm}" && "${_adv_arm}" != refuse ]] \
       && _adopt_v2_chain "${sig8}" arm_advance "${_adv_chainout:-${_adv_arm}}"; then
      arm="${candidate_arms[0]}"
      emit decision "route_headroom_chosen task=${sig8} arm=${arm} after=arm_advance ordered=$(IFS=,; printf '%s' "${candidate_arms[*]}") source=arbiter arbiter_pick=${_adv_arm} ${_adv_util}"
    else
      emit decision "arbiter_broken task=${sig8} rc=${_adv_rc} reason=arm_advance_fail_open_to_static_pick fallback=${arm}"
      candidate_arms=()
    fi
  fi

  local spawn_out src
  spawn_out="$(spawn_worker "${arm}" "${mission}" "${sig8}")"; src=$?
  if [[ ${src} -ne 0 ]]; then
    emit decision "arm_advance_failed task=${sig8} arm=${arm} reason=spawn_failed"
    exit 1
  fi
  local handle
  handle="$(printf '%s\n' "${spawn_out}" | sed -n 's/.*handle=\(.*\)$/\1/p' | tail -1)"
  _stamp_active_phase "${task_id}" "build" "${arm}"
  # PHASES-ARE-THE-ONLY-PATH-01: record build phase as running with the resolved arm handle.
  bash "${PHASE_RECORD_BIN}" record "${sig8}" build --status running \
    --handle "dispatch-${sig8}-build" \
    --task-id "${task_id}" --owner "$(basename "$0"):cmd_advance_arm" 2>/dev/null || true
  emit decision "worker_spawned by=arm_advance model=${arm} handle=${handle}"

  if [[ "${E2E_GATE}" == "1" || "${REVIEW_GATE}" == "1" ]]; then
    spawn_product_close "${sig8}" "${arm}" "${handle}" "" "${writes}" "${task_id}" "${mission_file}"
  fi
  printf 'arm_advance model=%s task=%s handle=%s\n' "${arm}" "${sig8}" "${handle}"
  exit 0
}

# CODEX-QUOTA-LOCKOUT-NEVER-FIRES-FOR-CODEX-01: out-of-window twin of
# _wait_arm_early_verdict's failed-state branch, exposed as a subcommand so the CLOSE
# GATE (leadv2-dispatch-product-close.sh's worker-poll loop, which learns about a
# `status == failed` arm well after this script's own in-process verdict window has
# long since expired) can still classify a late quota death and record the lockout.
#   leadv2-dispatch-code.sh record-quota-lockout --arm <arm> --handle <handle>
#     [--sig8 <sig8>] [--provider <provider>]
#
# CODEX-DOOR-DEAD-01 §3: a second, explicitly distinct mode -- STAND-DOWN. Given
# --hours/--minutes, this asserts a provider is broken (e.g. the runtime is down,
# not merely out of quota) and stands it down for a fixed duration, bypassing
# _arm_final_output/_quota_shaped entirely (there is no output to classify --
# stand-down is asserted, not detected). --handle becomes optional in this mode;
# --provider (or --arm, resolved via _arm_provider) is required.
#   leadv2-dispatch-code.sh record-quota-lockout --provider <p> --hours <N>
#     [--reason <text>]
# Mode selection is unambiguous: --hours/--minutes present -> stand-down mode.
# Neither present -> today's quota-classification mode, byte-identical (no
# existing call site passes a duration flag, so this is strictly additive).
# Always rc0 (best-effort, non-fatal observability -- the close gate's own poll loop
# must never fail because this classification step failed).
cmd_record_quota_lockout() {
  local arm="" handle="" sig8="" provider="" hours="" minutes="" reason="provider_broken"
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --arm)      [[ $# -ge 2 ]] && arm="$2"; shift 2 ;;
      --handle)   [[ $# -ge 2 ]] && handle="$2"; shift 2 ;;
      --sig8)     [[ $# -ge 2 ]] && sig8="$2"; shift 2 ;;
      --provider) [[ $# -ge 2 ]] && provider="$2"; shift 2 ;;
      --hours)    [[ $# -ge 2 ]] && hours="$2"; shift 2 ;;
      --minutes)  [[ $# -ge 2 ]] && minutes="$2"; shift 2 ;;
      --reason)   [[ $# -ge 2 ]] && reason="$2"; shift 2 ;;
      *) shift ;;
    esac
  done

  if [[ -n "${hours}" || -n "${minutes}" ]]; then
    [[ -n "${provider}" ]] || provider="$(_arm_provider "${arm}")"
    [[ -n "${provider}" ]] || { log_err "record-quota-lockout: --provider (or --arm) is required for stand-down mode"; exit 0; }
    local _total_minutes
    if [[ -n "${minutes}" ]]; then
      [[ "${minutes}" =~ ^[0-9]+$ && "${minutes}" -ge 1 && "${minutes}" -le 10080 ]] || { log_err "record-quota-lockout: --minutes must be an integer in 1..10080, got '${minutes}'"; exit 0; }
      _total_minutes="${minutes}"
    else
      [[ "${hours}" =~ ^[0-9]+$ && "${hours}" -ge 1 && "${hours}" -le 168 ]] || { log_err "record-quota-lockout: --hours must be an integer in 1..168, got '${hours}'"; exit 0; }
      _total_minutes=$(( hours * 60 ))
    fi
    local _iso
    _iso="$(date -u -v+"${_total_minutes}"M +%Y-%m-%dT%H:%M:%SZ 2>/dev/null \
      || date -u -d "+${_total_minutes} minutes" +%Y-%m-%dT%H:%M:%SZ)"
    [[ -n "${_iso}" ]] || { log_err "record-quota-lockout: failed to compute stand-down timestamp"; exit 0; }
    _record_quota_lockout "${provider}" "${_iso}" "standdown:${reason}" "standdown"
    emit decision "quota_standdown_recorded provider=${provider} hours=${hours:-0} minutes=${_total_minutes} until=${_iso} reason=${reason} task=${sig8:--}"
    exit 0
  fi

  [[ -n "${arm}" && -n "${handle}" ]] || { log_err "record-quota-lockout: --arm and --handle are required"; exit 0; }
  [[ -n "${provider}" ]] || provider="$(_arm_provider "${arm}")"

  # PROVIDER-LOCKOUT-FALSE-BLOCK-01: same classifier as _wait_arm_early_verdict
  # (via _record_postspawn_lockout) so the close gate's fallback path and the
  # dispatcher's own poll path can never disagree on a failure's class.
  local final_out _plo _plo_rc _pcls _pmin _pstrikes _psrc _piso _pev
  final_out="$(_arm_final_output "${arm}" "${handle}")"
  _plo="$(_record_postspawn_lockout "${arm}" "${final_out}")" && _plo_rc=0 || _plo_rc=1
  IFS='|' read -r _pcls _pmin _pstrikes _psrc _piso _pev <<<"${_plo}"
  if [[ "${_plo_rc}" != "0" || "${_pcls}" == "unclassified" ]]; then
    emit decision "arm_postspawn_verdict arm=${arm} state=failed quota=no task=${sig8:--}"
    emit decision "arm_failure_classified arm=${arm} site=postspawn class=unclassified evidence=${_pev} lockout=none task=${sig8:--}"
    exit 0
  fi
  local _reason="postspawn_${_pcls}"
  [[ "${_pcls}" == "provider_refusal" ]] && _reason="postspawn_quota"
  emit decision "quota_lockout_recorded provider=${provider} arm=${arm} reason=${_reason} class=${_pcls} minutes=${_pmin} strikes=${_pstrikes} source=${_psrc} until=${_piso} task=${sig8:--}"
  exit 0
}

# ── retry-dead: V3-DISPATCHER-ACCEPTANCE-01 Fault 3 sanctioned path ────────────────
# A worker can die before ever reaching a terminal ledger state (landed/parked/refused/
# dead) -- its ledger row then sits pending/confirmed-and-fresh, and every redispatch of
# the SAME mission text (same sig) is refused as duplicate_task_signature. The automatic
# outcome-ledger reclaim (_dispatch_outcome_blocks, run on the NEXT dispatch attempt for
# a confirmed row) already frees a row proven dead-with-no-evidence -- but it only fires
# as a side effect of trying again, and it never touches a still-fresh pending row at
# all. Live incident: the founder hand-deleted a ledger row by exact sig 4x in one night
# before this existed. `retry-dead <sig8>` is the same dead+no-evidence proof, invoked on
# demand instead of waiting for -- or blindly editing around -- the next attempt. It NEVER
# forces through a row that is alive, unknown, or has terminal-looking evidence on disk;
# those refuse loudly rather than being cleared.
cmd_retry_dead() {
  local sig8="${1:-}"
  [[ "${sig8}" =~ ^[a-f0-9]{8}$ ]] || { log_err "retry-dead: <sig8> must be 8 lowercase hex chars, got '${sig8}'"; exit 1; }
  # nit (dispatch-b4042501-review, item 7): emit() at ~1114 no-ops the journal
  # write whenever JOURNAL_TASK is unset -- without this, dispatch_retry_over_
  # dead_attempt reached stderr only, never the task journal the mission asked for.
  JOURNAL_TASK="dispatch-${sig8}"
  local f lockf
  f="$(dispatch_ledger_file)"; lockf="$(dispatch_lock_file)"
  [[ -f "${f}" ]] || { log_err "retry-dead: no ledger file at ${f}"; exit 1; }
  local now; now="$(_now_epoch)"
  local -a tokens=()
  local line fields state created arm handle token row_task_id
  while IFS= read -r line; do
    [[ -n "${line}" && "${line}" == *"\"task_sig\":\"${sig8}"* ]] || continue
    fields="$(_dispatch_row_fields "${line}")"
    IFS=$'\t' read -r state created arm handle token row_task_id <<< "${fields}"
    [[ "${state}" == "pending" || "${state}" == "confirmed" ]] || continue
    local liveness
    liveness="$(_dispatch_worker_liveness "${arm}" "${handle}")"
    if [[ "${liveness}" != "dead" ]]; then
      emit decision "dispatch_retry_dead_refused task=${sig8} reason=not_dead liveness=${liveness} token=${token}"
      log_err "retry-dead: row token=${token} arm=${arm} liveness=${liveness} -- not provably dead, refusing"
      exit 2
    fi
    if _dispatch_evidence_exists "${created}" "${sig8}"; then
      emit decision "dispatch_retry_dead_refused task=${sig8} reason=evidence_exists token=${token}"
      log_err "retry-dead: row token=${token} has terminal-looking evidence on disk -- refusing"
      exit 2
    fi
    tokens+=("${token}")
  done < "${f}"
  if [[ ${#tokens[@]} -eq 0 ]]; then
    log_err "retry-dead: no blocking pending/confirmed row found for task=${sig8} (nothing to clear)"
    exit 1
  fi
  local abort_rc=0
  ( lv2_lock_wait "${lockf}" 10 || exit 3
    local t
    for t in "${tokens[@]}"; do
      _dispatch_abort_locked "${f}" "${t}" || exit 1
    done
  ) 9>"${lockf}"
  abort_rc=$?
  if [[ ${abort_rc} -ne 0 ]]; then
    emit decision "dispatch_retry_dead_abort_failed task=${sig8} tokens=${tokens[*]} rc=${abort_rc}"
    log_err "retry-dead: ledger row removal failed for task=${sig8} tokens=${tokens[*]} (rc=${abort_rc}) -- ledger NOT confirmed cleared, refusing to report success"
    exit 1
  fi
  # review item 2 (dispatch-b4042501-review): _dispatch_abort_locked's rc0 means the
  # mv/write succeeded, not that every token row is actually gone -- verify directly
  # against the on-disk ledger before claiming success, same evidence bar as the
  # not_dead/evidence_exists refusals above.
  local leftover=0 t
  for t in "${tokens[@]}"; do
    grep -qF "\"token\":\"${t}\"" "${f}" 2>/dev/null && leftover=1
  done
  if [[ ${leftover} -eq 1 ]]; then
    emit decision "dispatch_retry_dead_verify_failed task=${sig8} tokens=${tokens[*]}"
    log_err "retry-dead: ledger row still present after removal attempt for task=${sig8} tokens=${tokens[*]} -- refusing to report success"
    exit 1
  fi
  emit decision "dispatch_retry_over_dead_attempt task=${sig8} tokens=${tokens[*]}"
  printf 'dispatch_retry_over_dead_attempt task=%s tokens=%s\n' "${sig8}" "${tokens[*]}"
  exit 0
}

# ── dispatch ──────────────────────────────────────────────────────────────────────
[[ $# -eq 0 ]] && usage
case "${1:-}" in
  record-review) shift; cmd_record_review "$@" ;;
  status)        cmd_status ;;
  glm-deferred)  shift; cmd_glm_deferred "$@" ;;
  burn-deferred) shift; cmd_burn_deferred "$@" ;;
  advance-arm)   shift; cmd_advance_arm "$@" ;;
  record-quota-lockout) shift; cmd_record_quota_lockout "$@" ;;
  retry-dead)    shift; cmd_retry_dead "$@" ;;
  sweep)         [[ -f "${LEDGER_BIN}" ]] && bash "${LEDGER_BIN}" sweep; exit $? ;;
  reconcile)     shift; [[ -f "${LEDGER_BIN}" ]] && exec bash "${LEDGER_BIN}" reconcile "$@"; exit $? ;;
  -h|--help)     usage ;;
  *)             cmd_resolve "$@" ;;
esac
