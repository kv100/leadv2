#!/usr/bin/env bash
# leadv2-dispatch-ledger.sh — T-o (SUPERVISOR-AUDIT-01): dispatch terminal-state ledger.
#
# PROBLEM THIS SOLVES
#   Today 64% of dispatch-code.sh/dispatch-product-close.sh runs end with NO completion
#   artifact at all -- not a success record, not a failure record, nothing. A dispatch can
#   crash, get refused, get parked, or genuinely land, and an operator has no single place
#   to ask "what happened to task X" without hand-reading journals across two scripts.
#
# WHAT THIS DOES
#   ONE JSONL row per REAL terminal attempt. landed and dead are TRUE terminals, write-once
#   per sig8: the first caller to record one wins; a later write for the SAME sig8 once a
#   true terminal is already recorded is a no-op that journals a dedup line instead of
#   appending a second row. refused and parked are RETRYABLE dispositions (wave2 round3
#   finding 3): a quota-exhausted refusal or an opus-parked task says nothing about how a
#   LATER, separate attempt at the same sig8 will end, so recording one never blocks a
#   later write from the SAME sig8 -- landed/dead still wins write-once against it. Row
#   shape:
#     {"ts","task_sig","founder_task_id","terminal":"landed|parked|refused|dead|no_work","cause","evidence"}
#   task_sig is the dispatch-<sig8> identifier BOTH writer scripts already share (dispatch-
#   code.sh computes the full mission-text sig but only ever hands sig8 to dispatch-product-
#   close.sh -- keying on the 8-char form here is what lets a single ledger row be extended
#   by either script for the SAME task; see build-t-core.md for the fuller rationale).
#
# TERMINAL TAXONOMY (a dispatch run's OWN outcome, not the eventual code-review verdict):
#   landed  — the run reached a real, evaluated completion: a non-product dispatch's
#             successful spawn (nothing else will ever check back on it), or a product
#             dispatch whose e2e+review gates concluded without a positive failure signal.
#             TRUE terminal -- write-once, no later attempt can override it.
#   dead    — started and ended badly: crash, ledger write failure, lock timeout, e2e
#             regression, or a review verdict of FAIL. TRUE terminal -- write-once, no
#             later attempt can override it.
#   parked  — explicitly deferred for a human/architect decision (no design after retries).
#             RETRYABLE -- does not block a later attempt at the same sig8 from later
#             recording landed/dead.
#   refused — declined at admission before any real work started (dedup, quota exhausted,
#             lane-shape violation, opus-requires-lead-judgment, a gate structurally could
#             not run at all -- missing e2e entrypoint, no reviewer). Note: an EMPTY diff
#             is NOT refused -- see no_work below; a lane that ran for 40 minutes and
#             produced nothing is not "declined at admission".
#             RETRYABLE -- does not block a later attempt at the same sig8 from later
#             recording landed/dead (quota exhaustion is the canonical case: quota
#             recovers, an identical dispatch is retried, and its real outcome must still
#             be recordable against the same sig8).
#   no_work — the lane RAN but its own diff is empty: it wrote nothing. (N1-EMPTY-LANE-
#             IS-NOT-A-PASS.) cause is empty_diff (the diff-scope block found zero bytes
#             across every declared write) or asked_into_void (the worker finished by
#             asking an operator a question nobody answered). A retryable disposition,
#             exactly the argument recorded above for refused/parked: a lane that did
#             nothing says nothing about a LATER attempt at the same signature. It is NOT
#             `dead` (dead is write-once and would block that retry) and it is NOT
#             `refused` (it ran past admission). partial_diff stays `refused` -- a mixed
#             group DID produce work.
#
# CLI (this script is a SUBPROCESS CALLED via `bash ... "$@"` by its two callers, NEVER
# `source`d -- see the "WHY A CLI, NOT A LIBRARY" note below):
#   leadv2-dispatch-ledger.sh write-terminal <sig8> <founder_task_id> <terminal> <cause> [<evidence>] [<attempt>] [<display_name>]
#   leadv2-dispatch-ledger.sh exists <sig8>            -- rc0 iff a TRUE terminal (landed|dead)
#                                                          row already exists (a refused/parked-
#                                                          only history returns rc1: retryable)
#   leadv2-dispatch-ledger.sh sweep                            -- see cmd_sweep() below
#
# ONE-STEP ROLLBACK: there is no behavior to roll back to (this ledger is purely additive
# observability -- it never gates a dispatch decision). LEADV2_DISPATCH_TERMINAL_LEDGER_FILE
# overrides the resolved path (tests).
#
# WHY A CLI, NOT A LIBRARY (found live, bash 5.3.9 aarch64-darwin): an earlier version of
# this file was meant to be `source`d into dispatch-code.sh for zero-subprocess-overhead
# function calls (matching leadv2-active-registry.sh's own pattern). Sourcing it broke an
# ENTIRELY UNRELATED code path in the CALLING script: dispatch-code.sh's existing
# duplicate_task_signature refusal (dispatch_reserve()'s early `return 2`) started exiting
# the whole process silently, before ever reaching its own case-statement body, on every
# run. This reproduced consistently regardless of this file's tail shape (a guarded
# self-dispatch block, a bare case with no exit, or no tail at all) and regardless of
# `_dl_note`'s own call shape in the caller -- the ONLY reliable fix was to stop sourcing
# this file altogether and call it as a subprocess instead, mirroring how dispatch-code.sh
# already calls every other sibling script (glm-coder.sh, codex-task.sh, leadv2-lane-
# shape.sh, ...). Root cause not isolated; the fix is structural, not a smarter guard.
set -uo pipefail

SCRIPT_NAME="leadv2-dispatch-ledger"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-"$0"}")" 2>/dev/null && pwd)"
PROJECT_ROOT="${PROJECT_ROOT:-${LEADV2_PROJECT_ROOT:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}}"
JOURNAL_BIN="${LEADV2_JOURNAL_BIN:-${SCRIPT_DIR}/leadv2-journal.sh}"
STATE_PATH_BIN="${LEADV2_STATE_PATH_BIN:-${SCRIPT_DIR}/leadv2-state-path.sh}"
LANE_LIVENESS_BIN="${LEADV2_DISPATCH_LANE_LIVENESS_BIN:-${SCRIPT_DIR}/leadv2-lane-liveness.sh}"
# SWIFTBAR-R4 RC-1: flock(1) is absent on the widget's acceptance PATH (no
# util-linux on macOS). Same rc0/rc3 acquire contract as flock -w -x.
# shellcheck source=leadv2-portable-lock.sh
source "${SCRIPT_DIR}/leadv2-portable-lock.sh"
CACHE_BASE="${LEADV2_DISPATCH_CACHE_DIR:-${HOME}/.claude/cache}"

log()     { printf '[%s] %s\n' "${SCRIPT_NAME}" "$*" >&2; }
log_err() { printf '[%s] ERROR: %s\n' "${SCRIPT_NAME}" "$*" >&2; }

repo_slug() {
  local base; base="$(basename "${PROJECT_ROOT}")"
  printf '%s' "${base}" | tr -cd 'A-Za-z0-9._-'
}

# strip quotes/backslashes/newlines from a free-form field (cause/evidence/founder id).
# strip quotes/backslashes from a free-form field (cause/evidence/founder id) and
# collapse newlines to spaces. SWIFTBAR-LIVE-01 round 4 (§Fix 3, codex P2-b): also
# delete every other JSON control char (tab, CR, etc.) -- a founder_task_id / task_id
# carrying a literal tab wrote `..."task_id":"R4\tPROBE"...` which json.loads rejects
# (Invalid control character), breaking the whole terminal row AND the reader's
# per-line parse. Stripping 0x00-0x1F (except LF, collapsed above) is strictly safer.
json_safe() { printf '%s' "$1" | tr -d '"\\' | tr '\n' ' ' | tr -d '\000-\011\013-\037'; }

# Resolves the shared, cross-worktree ledger path via the control-plane resolver
# (LEAD-CONTROL-PLANE-01) so every worktree of the same repo sees the SAME file -- a
# per-worktree path would silently fragment this ledger the same way active.yaml used to
# (see leadv2-state-path.sh's own doc header). Falls back to CACHE_BASE (per-repo-slug)
# when the resolver script is unavailable (isolated tests, a repo with no plugin install
# yet) -- never hard-fails a caller over this.
dispatch_terminal_ledger_file() {
  if [[ -n "${LEADV2_DISPATCH_TERMINAL_LEDGER_FILE:-}" ]]; then
    printf '%s' "${LEADV2_DISPATCH_TERMINAL_LEDGER_FILE}"; return 0
  fi
  local p=""
  if [[ -f "${STATE_PATH_BIN}" ]]; then
    p="$(PROJECT_ROOT="${PROJECT_ROOT}" bash "${STATE_PATH_BIN}" --no-link dispatch-ledger.jsonl 2>/dev/null || true)"
  fi
  if [[ -z "${p}" ]]; then
    p="${CACHE_BASE}/dispatch-terminal-ledger/$(repo_slug).jsonl"
  fi
  printf '%s' "${p}"
}

dispatch_terminal_ledger_lock_file() { printf '%s.lock' "$(dispatch_terminal_ledger_file)"; }

# Extracts the value of <field> from the LAST row matching <sig8> in <file>, or "" if no
# row / no such field. Shared by dispatch_terminal_exists and the write-once gate below so
# both agree on what "the current state of this sig8" means.
_dispatch_terminal_last_field() {
  local sig8="$1" f="$2" field="$3"
  [[ -f "${f}" ]] || return 0
  grep -F "\"task_sig\":\"${sig8}\"" "${f}" 2>/dev/null | tail -n 1 | \
    sed -n "s/.*\"${field}\":\"\([^\"]*\)\".*/\\1/p"
}

# rc0: a TRUE terminal (landed|dead) row already exists for <sig8>. rc1: none found (ledger
# missing, sig8 unseen, or its only history is a retryable refused/parked row -- wave2
# round3 finding 3: refused/parked never count as "exists" here, since a later attempt at
# the same sig8 must still be able to record its real landed/dead outcome).
dispatch_terminal_exists() {
  local sig8="$1" f last; f="$(dispatch_terminal_ledger_file)"
  [[ -f "${f}" ]] || return 1
  last="$(_dispatch_terminal_last_field "${sig8}" "${f}" terminal)"
  case "${last}" in
    landed|dead) return 0 ;;
    *) return 1 ;;
  esac
}

# rc0: ANY row of ANY kind (landed|dead|parked|refused) already exists for <sig8>. rc1: no
# row at all (ledger missing or sig8 unseen). wave2 round4 finding 1: this is deliberately
# DIFFERENT from dispatch_terminal_exists() above and exists only for cmd_sweep's own
# missing-terminal check. dispatch_terminal_exists() treats refused/parked as "not present"
# so a later, separate retry attempt can still record a real landed/dead outcome for the
# same sig8 -- correct for THAT gate. But the sweep uses "no terminal recorded yet" to mean
# "this worker lane died with nothing to show for it, so stamp dead" -- and a refused/parked
# row IS already a recorded outcome for the attempt the sweep is looking at. Reusing
# dispatch_terminal_exists() there made the sweep append `dead` on top of an existing
# refused/parked row, and dead is a TRUE terminal (write-once) -- that permanently poisoned
# the sig8 against the very retry dispatch_terminal_exists() was designed to still allow.
dispatch_any_terminal_exists() {
  local sig8="$1" f last; f="$(dispatch_terminal_ledger_file)"
  [[ -f "${f}" ]] || return 1
  last="$(_dispatch_terminal_last_field "${sig8}" "${f}" terminal)"
  [[ -n "${last}" ]] || return 1
  return 0
}

# Writes EXACTLY ONE row per <sig8> per real ATTEMPT (write-once-per-attempt), and refuses
# to override a TRUE terminal (landed|dead) once one is recorded for the sig8 (write-once-
# per-sig8-once-final). wave2 round3 finding 3: refused/parked are RETRYABLE -- quota
# exhaustion or an opus-parked task says nothing about a LATER, separate attempt's real
# outcome, so a refused/parked row never blocks a later write for the same sig8. What DOES
# still need blocking is the exit-trap idempotent RE-write of a state a script already just
# recorded for its own current run (leadv2-dispatch-product-close.sh's EXIT trap retries
# its own already-written state so a transient ledger-write hiccup still gets one row) --
# that is not a new attempt, so the optional [<attempt>] token (each caller's own $$, stable
# across its own explicit call and its own EXIT-trap retry, but different across separate
# process invocations even for the same sig8) is what tells the two apart. Callers that omit
# it (e.g. the sweep below, which never double-calls for the same sig8) always append.
# <sig8> <founder_task_id> <terminal:landed|parked|refused|dead> <cause> [<evidence>] [<attempt>] [<display_name>]
dispatch_ledger_write_terminal() {
  local sig8="$1" founder="${2:-}" terminal="$3" cause="${4:-}" evidence="${5:-}" attempt="${6:-}" display_name="${7:-}"
  [[ -n "${sig8}" ]] || { log_err "write_terminal: empty task_sig, refusing to write"; return 1; }
  case "${terminal}" in
    landed|parked|refused|dead|no_work) : ;;
    *) log_err "write_terminal: invalid terminal='${terminal}' for sig=${sig8}"; return 1 ;;
  esac
  founder="$(json_safe "${founder}")"
  cause="$(json_safe "${cause}")"
  evidence="$(json_safe "${evidence}")"
  attempt="$(json_safe "${attempt}")"
  display_name="$(json_safe "${display_name}")"
  # SWIFTBAR-LIVE-01 round 4 (§Fix 3): emit task_id alongside founder_task_id so a
  # terminal row is self-describing -- the status-surface reader keyed the lane
  # name off task_id, and this row REPLACES the reserve row that carried it, so
  # without task_id here the lane rendered "unnamed". Same json_safe + 64-char
  # clamp the reserve writer applies (R3.4: a --task-id with a quote/backslash
  # must not break the terminal row's JSON).
  # N7F-LANE-NAME: prefer the optional display_name (a real human name resolved by
  # dispatch-code.sh's DISPATCH_LANE_NAME, which may itself just BE founder_task_id --
  # see that file's --task-id/mission-H1 precedence) over founder_task_id itself. A
  # 6-arg caller (display_name absent) gets byte-identical output to before this change.
  local _tid
  if [[ -n "${display_name}" ]]; then
    _tid="${display_name:0:64}"
  else
    _tid="${founder:0:64}"
  fi
  local f lockf; f="$(dispatch_terminal_ledger_file)"; lockf="$(dispatch_terminal_ledger_lock_file)"
  mkdir -p "$(dirname "${f}")" 2>/dev/null
  mkdir -p "$(dirname "${lockf}")" 2>/dev/null
  local rc
  (
    lv2_lock_wait "${lockf}" 10 || exit 3
    local _last_terminal _same_attempt_row
    _last_terminal="$(_dispatch_terminal_last_field "${sig8}" "${f}" terminal)"
    case "${_last_terminal}" in
      landed|dead) exit 2 ;;  # a TRUE terminal already won write-once for this sig8
    esac
    # LOW-3: aligned on the ANY-row form (matching dispatch_ledger_sweep_write_dead's own
    # _same_attempt_row check below) -- comparing only the LAST row missed an exit-trap
    # retry whose attempt is no longer the last row (e.g. a refused/parked row from a
    # different attempt landed in between), which appended a spurious duplicate.
    if [[ -n "${attempt}" && -f "${f}" ]]; then
      _same_attempt_row="$(grep -F "\"task_sig\":\"${sig8}\"" "${f}" 2>/dev/null | grep -F "\"attempt\":\"${attempt}\"" | head -n 1)"
      [[ -n "${_same_attempt_row}" ]] && exit 2
    fi
    ts="$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date +%s)"
    printf '{"ts":"%s","task_sig":"%s","founder_task_id":"%s","task_id":"%s","terminal":"%s","cause":"%s","evidence":"%s","attempt":"%s"}\n' \
      "${ts}" "${sig8}" "${founder}" "${_tid}" "${terminal}" "${cause}" "${evidence}" "${attempt}" >> "${f}" || exit 1
    exit 0
  ) 9>"${lockf}"
  rc=$?
  case "${rc}" in
    0)
      if [[ -f "${JOURNAL_BIN}" ]]; then
        bash "${JOURNAL_BIN}" append "dispatch-${sig8}" decision \
          "dispatch_terminal task=${sig8} terminal=${terminal} cause=${cause}" >/dev/null 2>&1 || true
      fi
      return 0 ;;
    2)
      if [[ -f "${JOURNAL_BIN}" ]]; then
        bash "${JOURNAL_BIN}" append "dispatch-${sig8}" decision \
          "dispatch_terminal_dedup task=${sig8} attempted=${terminal} reason=terminal_already_recorded" >/dev/null 2>&1 || true
      fi
      return 0 ;;  # dedup is a SUCCESSFUL no-op, not a caller error
    3) log_err "write_terminal: lock-wait timeout for sig=${sig8}"; return 1 ;;
    *) log_err "write_terminal: ledger write failed (rc=${rc}) for sig=${sig8}"; return 1 ;;
  esac
}

# SD-LEDGER-SWEEP-HARDEN-01: the sweep's OWN write path -- deliberately NOT
# dispatch_ledger_write_terminal() above. Round-5 review found the sweep's preflight
# (dispatch_any_terminal_exists, sig8-wide) both too coarse and racy:
#   (a) too coarse -- an old refused/parked row from a DIFFERENT, earlier attempt at the
#       same sig8 made the sig8-wide "any terminal already exists" check hide a LATER,
#       genuinely crashed retry forever (that retry's own dead outcome never got recorded).
#   (b) racy -- the check ran OUTSIDE any lock, then the write acquired its own separate
#       lock: a refused/parked row appended for the SAME attempt in between (another
#       caller losing a race, or a slow refusal finally landing) was invisible to the
#       check and then overwritten by write-once `dead` anyway (write_terminal only
#       refuses on a sig8-wide landed|dead, never on refused|parked) -- recreating the
#       exact poisoning bug this ledger exists to prevent.
# FIX: <attempt> is now REQUIRED (refuses, not sweeps, when absent -- an attempt-less
# lane row predates SD-LEDGER-SWEEP-HARDEN-01 or was never stamped, and sweeping it with
# an empty attempt token risks colliding with a future retry that also has no token yet).
# The any-terminal check is re-scoped from sig8-wide to (sig8, attempt)-exact, and now
# runs INSIDE the SAME flock section as the append -- one locked transaction, no window
# for a concurrent writer to land between check and write. The sig8-wide TRUE-terminal
# (landed|dead) write-once-final check is UNCHANGED and stays sig8-wide on purpose: once
# any attempt has truly landed or truly died, no attempt (right OR wrong) may add a
# second true terminal for that sig8 -- attempt-scoping that guard would let a stale dead
# attempt overwrite a sig8 that has already, correctly, landed under a different attempt.
# <sig8> <lane_id> <cause> <evidence> <attempt>
dispatch_ledger_sweep_write_dead() {
  local sig8="$1" lane="${2:-}" cause="${3:-}" evidence="${4:-}" attempt="${5:-}"
  [[ -n "${sig8}" ]] || { log_err "sweep_write_dead: empty task_sig, refusing to write"; return 1; }
  if [[ -z "${attempt}" ]]; then
    log_err "sweep_write_dead: no attempt recorded on lane=${lane} sig=${sig8} -- refusing to sweep (attempt-less row predates hardening or was never stamped)"
    return 2
  fi
  local founder cause_s evidence_s attempt_s
  founder="$(json_safe "${lane}")"
  cause_s="$(json_safe "${cause}")"
  evidence_s="$(json_safe "${evidence}")"
  attempt_s="$(json_safe "${attempt}")"
  local f lockf; f="$(dispatch_terminal_ledger_file)"; lockf="$(dispatch_terminal_ledger_lock_file)"
  mkdir -p "$(dirname "${f}")" 2>/dev/null
  mkdir -p "$(dirname "${lockf}")" 2>/dev/null
  # SWIFTBAR-LIVE-01 round 4 (§Fix 3) + N7F-LANE-NAME: task_id on the sweep's dead row
  # too (same self-describing rationale as write-terminal). The sweep's own `lane` arg
  # is often the founder task id (leadv2-fanout.sh's shape, see doc header above), but
  # when this sig8 already has an EARLIER terminal row (refused/parked, since a TRUE
  # terminal short-circuits before this point) carrying a real display name, prefer
  # THAT -- it is more likely the mission-H1-derived name than `lane` is. Falls back to
  # founder_task_id when no prior row (or no task_id on it) exists.
  local _tid; _tid="$(_dispatch_terminal_last_field "${sig8}" "${f}" task_id)"
  [[ -n "${_tid}" ]] || _tid="${founder:0:64}"
  local rc
  (
    lv2_lock_wait "${lockf}" 10 || exit 3
    local _last_terminal _same_attempt_row
    _last_terminal="$(_dispatch_terminal_last_field "${sig8}" "${f}" terminal)"
    case "${_last_terminal}" in
      landed|dead) exit 2 ;;  # sig8-wide TRUE terminal already recorded -- write-once-final, attempt-agnostic by design
    esac
    if [[ -f "${f}" ]]; then
      _same_attempt_row="$(grep -F "\"task_sig\":\"${sig8}\"" "${f}" 2>/dev/null | grep -F "\"attempt\":\"${attempt_s}\"" | head -n 1)"
      [[ -n "${_same_attempt_row}" ]] && exit 2  # a row for THIS exact attempt already exists (refused/parked/landed/dead) -- never append dead on top of it
    fi
    ts="$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date +%s)"
    printf '{"ts":"%s","task_sig":"%s","founder_task_id":"%s","task_id":"%s","terminal":"dead","cause":"%s","evidence":"%s","attempt":"%s"}\n' \
      "${ts}" "${sig8}" "${founder}" "${_tid}" "${cause_s}" "${evidence_s}" "${attempt_s}" >> "${f}" || exit 1
    exit 0
  ) 9>"${lockf}"
  rc=$?
  case "${rc}" in
    0)
      if [[ -f "${JOURNAL_BIN}" ]]; then
        bash "${JOURNAL_BIN}" append "dispatch-${sig8}" decision \
          "dispatch_terminal task=${sig8} terminal=dead cause=${cause_s} attempt=${attempt_s} source=sweep" >/dev/null 2>&1 || true
      fi
      return 0 ;;
    2)
      if [[ -f "${JOURNAL_BIN}" ]]; then
        bash "${JOURNAL_BIN}" append "dispatch-${sig8}" decision \
          "dispatch_terminal_dedup task=${sig8} attempted=dead attempt=${attempt_s} reason=terminal_already_recorded source=sweep" >/dev/null 2>&1 || true
      fi
      return 0 ;;  # dedup is a SUCCESSFUL no-op, not a caller error
    3) log_err "sweep_write_dead: lock-wait timeout for sig=${sig8}"; return 1 ;;
    *) log_err "sweep_write_dead: ledger write failed (rc=${rc}) for sig=${sig8}"; return 1 ;;
  esac
}

# wave2 round2 finding 3: resolves the close-owner pidfile through the SAME cross-
# worktree control-plane resolver (LEAD-CONTROL-PLANE-01) the terminal ledger file itself
# uses -- a repo-relative docs/handoff/... path is per-worktree, so a close gate launched
# from a DIFFERENT worktree than the one running the sweep was invisible to it. Falls back
# to CACHE_BASE (per-repo-slug, non-cross-worktree) only when the resolver is unavailable,
# matching dispatch_terminal_ledger_file()'s own fallback above.
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

# wave2 finding 5 / wave2 round2 finding 3: a product task's real terminal state belongs
# to leadv2-dispatch-product-close.sh (it runs e2e/review after the worker lane itself is
# done) -- the worker lane going liveness-dead only means the BUILD half finished, not
# that the task is over. Sweeping "dead" at that moment can race a still-running
# product-close and win write-once against the real landed/parked/dead verdict it is
# about to record.
#
# ROUND2 FIX: an absent close-owner record used to mean "never stamped -- safe to sweep"
# unconditionally. That is wrong on two counts: (a) leadv2-dispatch-code.sh now writes
# this record BEFORE it even backgrounds product-close (see spawn_product_close), so
# "absent" no longer means "not yet stamped by a script that just started" the way it
# used to when product-close stamped its own pid as its first line of execution; but (b)
# a not-yet-CONFIRMED dispatch (still inside dispatch-code.sh, before spawn_product_close
# ever runs) is a real, legitimate reason for the record to be absent for a SHORT time,
# and a sweep must not treat that window as proof no close gate is coming. Absent record +
# YOUNG row (within LEADV2_DISPATCH_CLOSE_OWNER_GRACE_S, default 2h) => still blocks the
# sweep (grace window). Absent record + OLD row => genuinely never got a close gate
# (crash before spawn_product_close, or a non-product dispatch that reached this path in
# error) => safe to sweep, tagged with its own cause so it is distinguishable from the
# normal "close-owner pid is dead" sweep.
#
# Return: 0 = blocks the sweep (alive, or too young to trust the absence/malformed record).
#         1 = safe to sweep, normal cause (record found, pid confirmed dead).
#         2 = safe to sweep, no-close-owner cause (record never existed, row is old).
#         3 = safe to sweep, malformed-owner-record cause (record exists but its content
#             never parsed as a pid, and is old enough that it will never fix itself).
_product_close_pid_alive() {
  local sig8="$1" age_s="${2:-0}" pidfile pid grace_s
  pidfile="$(close_owner_pidfile "${sig8}")"
  grace_s="${LEADV2_DISPATCH_CLOSE_OWNER_GRACE_S:-7200}"
  [[ "${age_s}" =~ ^[0-9]+$ ]] || age_s=0
  if [[ -f "${pidfile}" ]]; then
    pid="$(cat "${pidfile}" 2>/dev/null)"
    if [[ "${pid}" =~ ^[0-9]+$ ]]; then
      if kill -0 "${pid}" 2>/dev/null; then
        return 0  # alive -- blocks the sweep
      fi
      return 1  # well-formed record, pid confirmed dead -- safe to sweep, normal cause
    fi
    # wave2 round3 finding 2: a malformed/empty/truncated record is NOT proof of a dead
    # owner -- both writers now use temp-file + atomic rename, but a reader can still
    # observe a leftover pre-fix artifact or a rare partial filesystem write. Treat it
    # exactly like an absent record (same grace-window test): still young => indeterminate,
    # blocks the sweep; only an OLD malformed record is swept, tagged separately from a
    # clean dead-pid sweep so the two are distinguishable in the ledger.
    if (( age_s < grace_s )); then
      return 0  # malformed record, still young -- indeterminate, blocks the sweep
    fi
    return 3  # malformed record, old enough that none is ever coming right -- safe to sweep
  fi
  if (( age_s < grace_s )); then
    return 0  # no record yet, but still within the grace window -- blocks the sweep
  fi
  return 2  # no record, and old enough that none is ever coming -- safe to sweep
}

# sweep: for every lane leadv2-lane-liveness.sh --all --json knows about, resolve its
# dispatch-ledger sig8 and, if its liveness verdict is dead (verdict "dead:...") and it has
# no terminal row yet, append terminal=dead cause=swept|no_close_owner. A lane that is
# alive, silent, or unknown is NEVER swept -- only a positively-proven-dead verdict frees
# it. A lane whose product-close owner is still alive (or too young to have one yet) is
# ALSO never swept, even if the worker lane itself already reports dead (see
# _product_close_pid_alive above).
#
# wave2 round3 finding 1: a lane's `lane` id is only "dispatch-<sig8>" for a bare self-
# dispatch. leadv2-fanout.sh's single-worker funnel (the common real-world path) registers
# the FOUNDER task id as `lane` and records the sig8 only inside `log_path`
# ("docs/handoff/dispatch-<sig8>/developer.stream.jsonl", see leadv2-fanout.sh's
# _fanout_register_session call site) -- so matching on `lane == dispatch-*` alone silently
# skipped every real funnel dispatch and left its terminal row unrepaired forever. sig8 is
# now resolved from EITHER shape: the lane id itself when it already is dispatch-<sig8>, or
# the log_path when the lane id is the founder task id instead. A lane matching neither
# shape carries no dispatch-ledger sig8 and is left alone (nothing for this ledger to do).
#
# wave2 round4 finding 3: `log_path` above is leadv2-lane-liveness.sh's VERIFIED artifact
# path -- it is null whenever the stream file this lane pointed at has vanished or was never
# written (exactly the crash lanes this sweep exists to catch), so sig8 extraction from it
# alone silently skipped precisely those lanes forever. `raw_log_path` is the SAME producer's
# unconditional echo of active.yaml's own recorded log_path, regardless of artifact
# existence, and is tried as a fallback when `log_path` yields no sig8.
cmd_sweep() {
  # SD-LEDGER-SWEEP-HARDEN-01: round-5 review (review-wave2-verdict-5.md) found the sweep
  # guard neither attempt-scoped nor atomic, and artifactless age not derived from
  # active.yaml started_at. All three are now fixed (dispatch_ledger_sweep_write_dead
  # above; leadv2-lane-liveness.sh derives age_s from the session's own started_at on
  # every artifactless-dead verdict) -- sweep defaults ON; LEADV2_LEDGER_SWEEP_ENABLE=0 is
  # the one-flip rollback to the prior no-op.
  if [[ "${LEADV2_LEDGER_SWEEP_ENABLE:-1}" == "0" ]]; then
    log "sweep disabled: LEADV2_LEDGER_SWEEP_ENABLE=0"
    return 0
  fi
  [[ -f "${LANE_LIVENESS_BIN}" ]] || { log_err "sweep: lane-liveness script not found: ${LANE_LIVENESS_BIN}"; return 1; }
  local raw
  raw="$(LEADV2_PROJECT_ROOT="${PROJECT_ROOT}" bash "${LANE_LIVENESS_BIN}" --project-root "${PROJECT_ROOT}" --all --json 2>/dev/null)" || {
    log_err "sweep: leadv2-lane-liveness.sh --all failed"; return 1
  }
  local checked=0 swept=0 skipped_alive=0 skipped_attemptless=0 skipped_indeterminate=0
  local lane verdict age_s log_path raw_log_path attempt pid_alive_f sig8 pc_rc sweep_cause
  # wave2 round4 finding 3 (self-caught): tab ($'\t') is an IFS WHITESPACE character, so
  # `IFS=$'\t' read` collapses consecutive delimiters -- an empty `log_path` field
  # (exactly the null-verified-artifact case this fix targets) silently shifted
  # `raw_log_path`'s value into the `log_path` variable instead, and left `raw_log_path`
  # itself empty. \x1f (unit separator) is not whitespace, so empty fields are preserved
  # positionally regardless of which field is empty.
  while IFS=$'\x1f' read -r lane verdict age_s log_path raw_log_path attempt pid_alive_f; do
    [[ -n "${lane}" ]] || continue
    sig8=""
    if [[ "${lane}" == dispatch-* && "${lane#dispatch-}" =~ ^[0-9a-f]{8}$ ]]; then
      sig8="${lane#dispatch-}"
    elif [[ "${log_path}" =~ /dispatch-([0-9a-f]{8})/ ]]; then
      sig8="${BASH_REMATCH[1]}"
    elif [[ "${raw_log_path}" =~ /dispatch-([0-9a-f]{8})/ ]]; then
      sig8="${BASH_REMATCH[1]}"
    fi
    [[ -n "${sig8}" ]] || continue
    checked=$(( checked + 1 ))
    [[ "${verdict}" == dead:* ]] || continue
    # HIGH-1 fix (fixround-tails): a live worker pid is decisive evidence, stronger than an
    # artifactless verdict derived purely from missing files -- leadv2-lane-liveness.sh's
    # three artifactless-dead paths (no_handoff_dir/no_log_artifact/log_stat_failed) return
    # dead:* WITHOUT consulting pid_alive at all, so this sweep must consult it itself,
    # regardless of age. Without this, an artifactless lane whose worker is genuinely still
    # running gets swept dead once older than the close-owner grace window, and the write-
    # once `dead` terminal then permanently discards the real `landed` outcome the live
    # worker is about to record. See review-tails-verdict.md HIGH-1 for the live repro.
    #
    # MEDIUM-4 fix (review-tails-verdict-2.md): the skip above used to fire on EVERY
    # dead:* verdict, but not every dead:* verdict is artifactless-derived --
    # dead:wedged_STAT=<stat> and dead:provider_{completed,failed,cancelled} DID consult
    # pid_alive themselves and concluded dead deliberately (a SIGSTOP'd or provider-
    # terminated process is dead regardless of pid liveness); those are exactly the
    # "positively-proven-dead verdict" this sweep's own doc header says should free a
    # lane. Scoping the skip to only the three verdicts that never looked at pid_alive
    # keeps HIGH-1's fix (artifactless lanes) while no longer making a wedged worker
    # permanently unsweepable.
    if [[ "${pid_alive_f}" == "1" && "${verdict}" =~ ^dead:(no_handoff_dir|no_log_artifact|log_stat_failed)$ ]]; then
      skipped_alive=$(( skipped_alive + 1 ))
      log "sweep: skipping lane=${lane} sig=${sig8} verdict=${verdict} -- pid is ALIVE (live-pid evidence overrides an artifactless-dead verdict)"
      continue
    fi
    # LOW-1: a row whose started_at never parsed (missing/malformed) is INDETERMINATE, not
    # provably dead -- leadv2-lane-liveness.sh's age_from_started_at() already warns on
    # stderr; the sweep must also refuse explicitly here rather than silently relying on
    # _product_close_pid_alive's age<grace coercion (which happens to block it TODAY only
    # because an empty age_s gets coerced to 0, an incidental side-effect, not a decision).
    if [[ -z "${age_s}" ]]; then
      skipped_indeterminate=$(( skipped_indeterminate + 1 ))
      log "sweep: skipping lane=${lane} sig=${sig8} verdict=${verdict} -- age_s indeterminate (started_at missing/unparseable, cannot safely age out)"
      continue
    fi
    _product_close_pid_alive "${sig8}" "${age_s}"
    pc_rc=$?
    [[ ${pc_rc} -eq 0 ]] && continue
    case "${pc_rc}" in
      2) sweep_cause="no_close_owner" ;;
      3) sweep_cause="malformed_owner_record" ;;
      *) sweep_cause="swept" ;;
    esac
    # SD-LEDGER-SWEEP-HARDEN-01: dispatch_ledger_sweep_write_dead() now does its own
    # atomic, attempt-scoped any-terminal check UNDER THE LOCK (see its own doc header) --
    # the old unlocked, sig8-wide dispatch_any_terminal_exists() preflight that used to
    # sit here is gone; this call is now the ENTIRE guard, not a second layer over it.
    if [[ -z "${attempt}" ]]; then
      skipped_attemptless=$(( skipped_attemptless + 1 ))
      log "sweep: skipping lane=${lane} sig=${sig8} -- no attempt recorded on its active.yaml row (attempt-less, cannot safely attribute a dead terminal)"
      continue
    fi
    if dispatch_ledger_sweep_write_dead "${sig8}" "${lane}" "${sweep_cause}" "verdict=${verdict}" "${attempt}"; then
      swept=$(( swept + 1 ))
    fi
  done < <(printf '%s' "${raw}" | python3 -c '
import json, sys
try:
    d = json.load(sys.stdin)
except Exception:
    sys.exit(0)
for row in d.get("lanes") or []:
    lane = row.get("lane") or ""
    verdict = row.get("verdict") or ""
    age_s = row.get("age_s")
    log_path = row.get("log_path") or ""
    raw_log_path = row.get("raw_log_path") or ""
    attempt = row.get("attempt") or ""
    pid_alive_f = "1" if row.get("pid_alive") else "0"
    print("%s\x1f%s\x1f%s\x1f%s\x1f%s\x1f%s\x1f%s" % (lane, verdict, age_s if age_s is not None else "", log_path, raw_log_path, attempt, pid_alive_f))
' 2>/dev/null)
  # MEDIUM-1: a per-run summary that distinguishes "nothing needed sweeping" from "the
  # attempt token never reached this lane at all" (e.g. a stale plugin cache holding a
  # pre-hardening dispatch-code.sh, which prints no attempt= and skips every lane) -- both
  # used to print the byte-identical checked=N swept=0, which is the lying-GREEN shape for
  # a sweep that is default-ON.
  log "sweep: checked=${checked} swept=${swept} skipped_alive=${skipped_alive} skipped_attemptless=${skipped_attemptless} skipped_indeterminate=${skipped_indeterminate}"
}

usage() {
  cat >&2 <<EOF
Usage:
  ${SCRIPT_NAME}.sh write-terminal <sig8> <founder_task_id> <landed|parked|refused|dead> <cause> [<evidence>] [<attempt>] [<display_name>]
  ${SCRIPT_NAME}.sh exists <sig8>
  ${SCRIPT_NAME}.sh sweep
EOF
  exit 2
}

case "${1:-}" in
  write-terminal)
    shift
    [[ $# -ge 3 ]] || usage
    dispatch_ledger_write_terminal "$1" "${2:-}" "$3" "${4:-}" "${5:-}" "${6:-}" "${7:-}"
    exit $?
    ;;
  exists)
    shift
    [[ $# -ge 1 ]] || usage
    dispatch_terminal_exists "$1"
    exit $?
    ;;
  sweep)
    cmd_sweep
    exit $?
    ;;
  *) usage ;;
esac
