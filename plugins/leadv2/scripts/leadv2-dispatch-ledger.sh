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
#     {"ts","task_sig","founder_task_id","terminal":"landed|pass_unlanded|parked|refused|dead|no_work","cause","evidence"}
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
#             not run at all -- missing e2e entrypoint, no reviewer, or
#             lane_root_not_a_worktree (the gate was pointed at a directory that is not a
#             git work tree root, so it had nothing it was entitled to grade). Note: an EMPTY diff
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
    landed|pass_unlanded|dead) return 0 ;;
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

# DEDUP-REFUSED-RETRY-01: stdout = the LAST recorded terminal-ledger word for <sig8>
# (landed|parked|refused|dead|no_work), or empty if no row exists. rc always 0 (this is a
# read, not a gate). Unlike dispatch_terminal_exists()/dispatch_any_terminal_exists() above
# (which collapse the ledger to a yes/no boolean -- and, per that fn's own doc comment,
# deliberately treat refused/parked as "not present" for THEIR gate), the dispatch-code.sh
# dedup gate needs the actual recorded word so it can tell refused (must free a fresh
# dispatch) apart from dead (must also free) apart from landed (must keep blocking) --
# see that caller's own doc comment on _dispatch_outcome_blocks for the full contract.
dispatch_terminal_last_state() {
  local sig8="$1" f; f="$(dispatch_terminal_ledger_file)"
  _dispatch_terminal_last_field "${sig8}" "${f}" terminal
}

# LANE-OBSERVABILITY-02 change 2: stdout = the LAST recorded `cause` for
# <sig8>, or empty if no row / no such field. rc always 0 (read, not gate) —
# same contract as dispatch_terminal_last_state above; the prepass
# invalidation gate in leadv2-dispatch-code.sh consumes it via the `cause`
# CLI subcommand.
dispatch_terminal_last_cause() {
  local sig8="$1" f; f="$(dispatch_terminal_ledger_file)"
  _dispatch_terminal_last_field "${sig8}" "${f}" cause
}

# A late terminal from an earlier attempt must not poison a retry that has
# already registered a different attempt token in active.yaml.
_lv2_terminal_attempt_superseded() { # <founder_task_id> <attempt>
  local founder="$1" attempt="$2" yaml_file lock_file
  [[ -n "$founder" && -n "$attempt" ]] || return 1
  yaml_file="$(PROJECT_ROOT="${PROJECT_ROOT}" "${STATE_PATH_BIN}" active.yaml 2>/dev/null)" || return 1
  lock_file="$(PROJECT_ROOT="${PROJECT_ROOT}" "${STATE_PATH_BIN}" active.yaml.lock 2>/dev/null)" || return 1
  [[ -f "$yaml_file" && -n "$lock_file" ]] || return 1
  python3 - "$lock_file" "$yaml_file" "$founder" "$attempt" <<'PYEOF' 2>/dev/null
import fcntl, sys
try: import yaml
except ImportError: sys.exit(1)
lock_path, path, founder, attempt = sys.argv[1:5]
try:
    with open(lock_path, "a+") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        with open(path, encoding="utf-8") as fh:
            sessions = (yaml.safe_load(fh) or {}).get("sessions") or []
except Exception: sys.exit(1)
sys.exit(0 if any(isinstance(s, dict) and s.get("task_id") == founder and str(s.get("attempt") or "") not in ("", attempt) for s in sessions) else 1)
PYEOF
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
# <sig8> <founder_task_id> <terminal:landed|parked|refused|dead> <cause> [<evidence>] [<attempt>] [<display_name>] [<commit>] [<deliverable>]
# LANE-CLOSE-LOOP-01: args 8/9 (commit, deliverable) are ADDITIVE -- appended after
# display_name so every existing 7-arg callsite keeps its meaning byte-for-byte. They
# surface two new keys ("commit", "deliverable") in the row so reconcile can carry the
# git sha and deliverable presence it derived into the persistent row. Defaults "none" /
# "unknown" so the keys are ALWAYS present (a sometimes-absent key is the shape that
# breaks a future jq -r .commit). All current readers are grep -F + per-field sed
# (_dispatch_terminal_last_field, :135) -- key order and unknown keys are irrelevant to
# them, so inserting the two keys between "evidence" and "attempt" changes no reader.
# LANE-OBSERVABILITY-02 change 1: optional arg 10 (worker_reason) follows the exact
# commit/deliverable precedent -- additive after arg 9 so every existing 7/9-arg
# callsite keeps byte-identical output. The JSON row ALWAYS carries the key (empty
# string when unknown); the journal line only gains ` worker_reason="..."` when
# non-empty (an empty value would be noise on every healthy terminal row).
# <sig8> <founder_task_id> <terminal:landed|parked|refused|dead|no_work> <cause> [<evidence>] [<attempt>] [<display_name>] [<commit>] [<deliverable>] [<worker_reason>]
dispatch_ledger_write_terminal() {
  local sig8="$1" founder="${2:-}" terminal="$3" cause="${4:-}" evidence="${5:-}" attempt="${6:-}" display_name="${7:-}"
  local commit="${8:-none}" deliverable="${9:-unknown}" worker_reason="${10:-}"
  [[ -n "${sig8}" ]] || { log_err "write_terminal: empty task_sig, refusing to write"; return 1; }
  case "${terminal}" in
    landed|pass_unlanded|parked|refused|dead|no_work) : ;;
    *) log_err "write_terminal: invalid terminal='${terminal}' for sig=${sig8}"; return 1 ;;
  esac
  founder="$(json_safe "${founder}")"
  cause="$(json_safe "${cause}")"
  evidence="$(json_safe "${evidence}")"
  attempt="$(json_safe "${attempt}")"
  display_name="$(json_safe "${display_name}")"
  # LANE-CLOSE-LOOP-01: keep commit to a bare sha (hex), deliverable to its enum word --
  # json_safe strips quotes/backslashes/control chars, sufficient for these bounded inputs.
  commit="$(printf '%s' "${commit}" | tr -cd '0-9A-Za-z._:/-')"
  [[ -n "${commit}" ]] || commit="none"
  deliverable="$(json_safe "${deliverable}")"
  [[ -n "${deliverable}" ]] || deliverable="unknown"
  # LANE-OBSERVABILITY-02: worker_reason is free-form worker text — same
  # json_safe character class as every other free-form field, plus the 120-byte
  # clamp lv2_worker_reason already applies (a caller bypassing the lib gets
  # clamped here too, so the row can never carry an unbounded quote).
  worker_reason="$(json_safe "${worker_reason}")"
  worker_reason="${worker_reason:0:120}"
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
    case "${terminal}" in landed|pass_unlanded|dead) _lv2_terminal_attempt_superseded "${founder}" "${attempt}" && exit 4 ;; esac
    local _last_terminal _same_attempt_row
    _last_terminal="$(_dispatch_terminal_last_field "${sig8}" "${f}" terminal)"
    case "${_last_terminal}" in
      landed|pass_unlanded|dead) exit 2 ;;  # a TRUE terminal already won write-once for this sig8
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
    printf '{"ts":"%s","task_sig":"%s","founder_task_id":"%s","task_id":"%s","terminal":"%s","cause":"%s","evidence":"%s","commit":"%s","deliverable":"%s","attempt":"%s","worker_reason":"%s"}\n' \
      "${ts}" "${sig8}" "${founder}" "${_tid}" "${terminal}" "${cause}" "${evidence}" "${commit}" "${deliverable}" "${attempt}" "${worker_reason}" >> "${f}" || exit 1
    exit 0
  ) 9>"${lockf}"
  rc=$?
  case "${rc}" in
    0)
      if [[ -f "${JOURNAL_BIN}" ]]; then
        # LANE-OBSERVABILITY-02: append the worker's own words to the journal
        # line ONLY when non-empty — every existing journal parser greps
        # `dispatch_terminal task=` and reads cause= positionally, so a
        # trailing key changes no reader, but an empty `worker_reason=""` on
        # every healthy row would be pure noise.
        if [[ -n "${worker_reason}" ]]; then
          bash "${JOURNAL_BIN}" append "dispatch-${sig8}" decision \
            "dispatch_terminal task=${sig8} terminal=${terminal} cause=${cause} worker_reason=\"${worker_reason}\"" >/dev/null 2>&1 || true
        else
          bash "${JOURNAL_BIN}" append "dispatch-${sig8}" decision \
            "dispatch_terminal task=${sig8} terminal=${terminal} cause=${cause}" >/dev/null 2>&1 || true
        fi
      fi
      # T16 §10: a freshly-written TRUE terminal ends the lane -- drop its active.yaml
      # row now (dedup exits above keep the row: a later attempt may have re-registered).
      case "${terminal}" in
        landed|dead|pass_unlanded)
          _lv2_terminal_unregister_lanes "${sig8}" "${founder}" "${attempt}" ;;
      esac
      return 0 ;;
    2)
      if [[ -f "${JOURNAL_BIN}" ]]; then
        bash "${JOURNAL_BIN}" append "dispatch-${sig8}" decision \
          "dispatch_terminal_dedup task=${sig8} attempted=${terminal} reason=terminal_already_recorded" >/dev/null 2>&1 || true
      fi
      return 0 ;;  # dedup is a SUCCESSFUL no-op, not a caller error
    3) log_err "write_terminal: lock-wait timeout for sig=${sig8}"; return 1 ;;
    4)
      [[ -f "${JOURNAL_BIN}" ]] && bash "${JOURNAL_BIN}" append "dispatch-${sig8}" decision "dispatch_terminal_stale_attempt task=${sig8} terminal=${terminal} attempt=${attempt}" >/dev/null 2>&1 || true
      return 0 ;;
    *) log_err "write_terminal: ledger write failed (rc=${rc}) for sig=${sig8}"; return 1 ;;
  esac
}

# T16 §10 (LANE-DEREGISTRATION): a TRUE terminal (landed|dead|pass_unlanded) ends the
# lane for good, but its active.yaml registration row used to survive forever -- closed
# lanes accumulated until lead_session_lane_cap refused every new dispatch and a human
# had to prune by hand (3x on 2026-08-26/27). Removal is tombstone-consistent with the
# T18 abandon path (leadv2_active_unregister semantics: row removed, the terminal row in
# THIS ledger is the durable record). Self-contained python instead of sourcing
# leadv2-active-registry.sh -- see "WHY A CLI, NOT A LIBRARY" above; a subshell source
# under this script's own set -u is the same trap with a different hat. Fail-open by
# contract: a missing resolver/yaml/pyyaml or a failed removal NEVER fails the terminal
# write itself -- the row then simply ages out via the sweep's next pass.
_lv2_terminal_unregister_lanes() {  # <sig8> <founder_task_id> <attempt> -- remove only matching-attempt lane rows
  local sig8="$1" founder="$2" attempt="${3:-}" yaml_file lock_file tid
  # An attempt-less terminal can own only an attempt-less row.  In particular,
  # do not let it deregister a retry that subsequently registered an attempt.
  yaml_file="$(PROJECT_ROOT="${PROJECT_ROOT}" "${STATE_PATH_BIN}" active.yaml 2>/dev/null)" || return 0
  [[ -n "${yaml_file}" && -f "${yaml_file}" ]] || return 0
  lock_file="$(PROJECT_ROOT="${PROJECT_ROOT}" "${STATE_PATH_BIN}" active.yaml.lock 2>/dev/null)" || return 0
  [[ -n "${lock_file}" ]] || return 0
  for tid in "${founder}" "dispatch-${sig8}"; do
    [[ -n "${tid}" ]] || continue
    python3 - "${lock_file}" "${yaml_file}" "${tid}" "${attempt}" <<'PYEOF' 2>/dev/null || true
import fcntl, os, sys, tempfile
try:
    import yaml
except ImportError:
    sys.exit(0)
lock_path, path, task_id, attempt = sys.argv[1:5]
try:
    lock = open(lock_path, "a+")
except OSError:
    sys.exit(0)
with lock:
    fcntl.flock(lock, fcntl.LOCK_EX)
    try:
        with open(path, encoding="utf-8") as fh:
            data = yaml.safe_load(fh)
    except Exception:
        sys.exit(0)
    if not isinstance(data, dict) or not isinstance(data.get("sessions"), list):
        sys.exit(0)
    before = len(data["sessions"])
    data["sessions"] = [s for s in data["sessions"]
                        if not (isinstance(s, dict) and s.get("task_id") == task_id
                                and str(s.get("attempt") or "") == attempt)]
    if len(data["sessions"]) == before:
        sys.exit(0)
    fd, tmp = tempfile.mkstemp(prefix=".active-unreg-", dir=os.path.dirname(path) or ".")
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as out:
            yaml.safe_dump(data, out, default_flow_style=False, sort_keys=False)
            out.flush()
            os.fsync(out.fileno())
        os.replace(tmp, path)
    except Exception:
        try: os.unlink(tmp)
        except OSError: pass
        sys.exit(0)
PYEOF
  done
  return 0
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
      landed|pass_unlanded|dead) exit 2 ;;  # sig8-wide TRUE terminal already recorded -- write-once-final, attempt-agnostic by design
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
      # T16 §10: swept dead IS a true terminal -- the lane row must leave active.yaml
      # here too, or swept lanes accumulate exactly like closed ones did. `lane` is the
      # active.yaml task_id this sweep iteration is acting on (founder_task_id form).
      _lv2_terminal_unregister_lanes "${sig8}" "${lane}" "${attempt_s}"
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

# ── LANE-CLOSE-LOOP-01: terminal-state reconcile ─────────────────────────────────
#
# PROBLEM THIS SOLVES (D2/D3/D4 in the task design): the close gate stamps terminal
# rows on SOME paths but not all, and the rows it DOES stamp can be wrong (D1: a cross-
# repo start-sha makes a lane that committed real work read as empty_diff). So lanes end
# up either with no terminal row at all (b5c26011: spawned-and-forgotten) or with a lying
# no_work. Reconcile closes that loop AFTER the fact: anti-join the reservation ledger
# (every confirmed spawn) against the terminal ledger, derive each unmatched lane's real
# state from runtime evidence, and write ONE terminal row for it. Idempotent by structure
# (a second run finds the row the first wrote) -- not a dedupe pass.
#
# The derivation deliberately does NOT use the close gate's sha-diff (_pc_diff_base): that
# is the source of D1. It uses a time-windowed + path-scoped `git log --since=@<spawn>
# -- <lane_writes>` instead, which needs no cross-repo start sha and survives the merge/
# push case that produces D1's false empty. A dirty working tree in the lane's write-set
# is OR'd in so an uncommitted-but-real lane is not called no_work.
#
# Write path is the SAME locked, write-once writer everything else uses -- no new lock,
# no new path, no second schema. The two new keys (commit, deliverable) are additive.

# Extract the lane_writes CSV from the architect prepass artifact (preferred -- it is the
# scoped declaration) or, failing that, from the mission file itself. Best-effort: an
# empty return degrades _dl_derive_lane_state to an unscoped --since window (still finds a
# commit if one landed, just over-attributes -- accepted, R4).
_dl_harvest_writes() {  # <dispatch_root> <sig8> <mission_path>
  local disp_root="$1" sig8="$2" mission="$3" line
  local prepass="${disp_root}/docs/handoff/dispatch-${sig8}/architect-prepass.md"
  if [[ -s "${prepass}" ]]; then
    line="$(grep -m1 -iE '^[[:space:]*_]*LANE_WRITES[*_]*:' "${prepass}" 2>/dev/null || true)"
    line="$(printf '%s' "${line}" | sed -E 's/^[[:space:]*_]*LANE_WRITES[*_]*:[[:space:]]*//I')"
    [[ -n "${line}" ]] && { printf '%s' "${line}"; return 0; }
  fi
  if [[ -n "${mission}" && -s "${mission}" ]]; then
    line="$(grep -m1 -iE '^[[:space:]*_]*LANE_WRITES[*_]*:' "${mission}" 2>/dev/null || true)"
    line="$(printf '%s' "${line}" | sed -E 's/^[[:space:]*_]*LANE_WRITES[*_]*:[[:space:]]*//I')"
    [[ -n "${line}" ]] && printf '%s' "${line}"
  fi
  return 0
}

# Extract the declared deliverable path from the mission file (a scratchpad .md). Empty
# return => deliverable presence is UNKNOWN, never "missing" -- a lane with no declared
# deliverable must not be reported as a deliverable failure (R5).
_dl_harvest_deliverable() {  # <mission_path>
  local mission="$1" p
  [[ -n "${mission}" && -s "${mission}" ]] || return 0
  p="$(grep -m1 -oE '/[^[:space:]"]*scratchpad/[^[:space:]"]*\.md' "${mission}" 2>/dev/null || true)"
  [[ -z "${p}" ]] && p="$(grep -m1 -oE '/private/tmp/[^[:space:]"]*\.md' "${mission}" 2>/dev/null || true)"
  [[ -n "${p}" ]] && printf '%s' "${p}"
  return 0
}

# Derive a lane's terminal state from runtime evidence (read-only). Prints three
# \x1f-separated fields: <terminal>\x1f<commit_sha|none>\x1f<deliverable present|missing|unknown>
# <lane_repo_abs> <spawn_epoch> <lane_writes_csv> <deliverable_path> <lane_id> <arm>
#
# terminal is one of: landed | no_work | dead | running | unknown -- the FIRST THREE map
# onto the existing ledger taxonomy (landed|dead|no_work) so reconcile stamps no new enum;
# running/unknown mean "do not stamp" (a live or indeterminate lane -- stamping it would
# poison the sig8 under write-once, the exact HIGH-1 bug cmd_sweep already documents).
_dl_derive_lane_state() {
  local repo="$1" spawn_epoch="$2" writes_csv="$3" deliverable="$4" lane_id="${5:-}" arm="${6:-}"
  local commit_sha="none" deliverable_state="unknown" dirty=0

  # 1. COMMIT EVIDENCE -- time-windowed + path-scoped, NOT sha-diff (survives D1).
  if git -C "${repo}" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    local since_arg=""
    if [[ "${spawn_epoch}" =~ ^-?[0-9]+$ ]]; then since_arg="--since=@${spawn_epoch}"; fi
    # build a pathspec from the CSV, excluding docs/leadv2 + docs/handoff (the same
    # exclusion set _pc_git_diff uses -- those are dispatcher bookkeeping, never the lane's
    # product work).
    local -a pathspec=() entries=()
    local e
    if [[ -n "${writes_csv}" ]]; then
      IFS=',' read -ra entries <<< "${writes_csv}"
      for e in "${entries[@]}"; do
        e="${e#"${e%%[![:space:]]*}"}"; e="${e%"${e##*[![:space:]]}"}"; e="${e#./}"
        [[ -z "${e}" ]] && continue
        case "${e}" in docs/leadv2/*|docs/handoff/*) continue ;; esac
        pathspec+=("${e}")
      done
    fi
    local found=""
    if [[ ${#pathspec[@]} -gt 0 && -n "${since_arg}" ]]; then
      found="$(git -C "${repo}" log ${since_arg} --pretty=%H -n 1 -- "${pathspec[@]}" 2>/dev/null || true)"
    fi
    # NOTE: there is deliberately NO unscoped `git log --since` fallback. An unscoped window
    # attributes the repo's LATEST commit to every lane with no declared lane_writes -- found
    # live 2026-08-04: a cross-repo --repo stamped `landed` + the newest leadv2 commit onto
    # 137 unrelated persona-engine lanes in one run. `landed` requires a PATH-SCOPED hit (an
    # attributable commit touching this lane's declared writes). No pathspec / no scoped hit
    # => the lane falls through to liveness (conservative), never a mass false-landed.
    [[ -n "${found}" ]] && commit_sha="${found}"
    # OR a dirty working tree in the lane's write-set (uncommitted-but-real work).
    if [[ ${#pathspec[@]} -gt 0 ]]; then
      local st
      st="$(git -C "${repo}" status --porcelain -uall -- "${pathspec[@]}" 2>/dev/null || true)"
      [[ -n "${st}" ]] && dirty=1
    fi
  fi

  # 2. DELIVERABLE EVIDENCE -- present iff a non-empty file exists at the declared path,
  # or at <path>.full.md. No declared path => unknown (never "missing").
  if [[ -n "${deliverable}" ]]; then
    deliverable_state="missing"
    local alt="${deliverable%.md}.full.md"
    if [[ -s "${deliverable}" ]] || { [[ "${alt}" != "${deliverable}" && -s "${alt}" ]]; }; then
      deliverable_state="present"
    fi
  fi

  # 3. VERDICT. Positive commit/dirty evidence is safe to stamp -- landed is what the lane
  # would have earned, so write-once cannot discard a better verdict here. Only the NO-work
  # case needs liveness to avoid poisoning a live lane (R1).
  if [[ "${commit_sha}" != "none" || ${dirty} -eq 1 ]]; then
    printf 'landed\x1f%s\x1f%s' "${commit_sha}" "${deliverable_state}"
    return 0
  fi
  local verdict="${LEADV2_RECONCILE_VERDICT:-}"
  # If the caller did not pre-supply a verdict (the batched reconcile path builds ONE
  # --all map and hands each lane its verdict via this env var), fall back to a single
  # per-lane spawn. The batched path is what makes a full reconcile over hundreds of lanes
  # affordable; this fallback keeps _dl_derive_lane_state usable standalone.
  if [[ -z "${verdict}" && -n "${lane_id}" && -f "${LANE_LIVENESS_BIN}" ]]; then
    verdict="$(LEADV2_PROJECT_ROOT="${repo}" bash "${LANE_LIVENESS_BIN}" --project-root "${repo}" --lane "${lane_id}" 2>/dev/null || true)"
  fi
  case "${verdict}" in
    alive|starting:*|silent:*)
      # process is alive (or freshly starting, or alive-but-silent) -- NOT terminal. Stamping
      # here would discard the real outcome the live worker is about to record (R1).
      printf 'running\x1fnone\x1f%s' "${deliverable_state}" ;;
    dead:no_handoff_dir|dead:no_log_artifact)
      # the lane has no work artifacts at all -- it wrote nothing. no_work (retryable), not
      # dead (dead is write-once and would block a retry).
      printf 'no_work\x1fnone\x1f%s' "${deliverable_state}" ;;
    dead:*)
      # a verdict that consulted the process and concluded dead (provider_failed/cancelled,
      # wedged, silent_no_process, log_stat_failed) -- the worker ran and died. dead.
      printf 'dead\x1fnone\x1f%s' "${deliverable_state}" ;;
    *)
      # liveness unavailable / indeterminate -- do NOT stamp (R1: a live lane this repo
      # cannot see would be poisoned). Surface as unknown; counts toward exit-1.
      printf 'unknown\x1fnone\x1f%s' "${deliverable_state}" ;;
  esac
}

# Print one lane as a table row (default) or a JSON object (--json). Trailing arg is the
# json flag (0/1) so this stays a plain positional fn (no subshell-global peeking).
_dl_emit_row() {  # <sig8> <label> <spawn_epoch> <state> <commit> <deliverable> <json>
  local sig8="$1" label="$2" spawn="$3" state="$4" commit="$5" del="$6" json="${7:-0}"
  if [[ ${json} -eq 1 ]]; then
    printf '{"task_sig":"%s","lane_label":"%s","spawned":%s,"state":"%s","commit":"%s","deliverable":"%s"}\n' \
      "${sig8}" "${label}" "${spawn:-0}" "${state}" "${commit:-none}" "${del:-unknown}"
  else
    printf '%s | %s | %s | %s | %s\n' "${label:-${sig8}}" "${spawn:-?}" "${state}" "${commit:-none}" "${del:-unknown}"
  fi
}

cmd_reconcile() {
  local repo_arg="" since_arg="" json_mode=0 lane_filter=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --repo)  repo_arg="${2:-}";  shift 2 ;;
      --since) since_arg="${2:-}"; shift 2 ;;
      --json)  json_mode=1; shift ;;
      --lane)  lane_filter+="${lane_filter:+ }${2:-}"; shift 2 ;;
      *) log_err "reconcile: unknown arg: $1"; return 2 ;;
    esac
  done

  # Dispatch repo root (worktree-aware) -- mirrors dispatch-code.sh's LEDGER_REPO_ROOT
  # derivation so the reservation-ledger slug resolves to the MAIN checkout even when
  # reconcile is launched from a linked worktree (a per-worktree slug would fragment it).
  local disp_root
  disp_root="$(cd "${PROJECT_ROOT}" 2>/dev/null && cd "$(dirname "$(git rev-parse --git-common-dir 2>/dev/null)")" 2>/dev/null && pwd)"
  [[ -n "${disp_root}" && -d "${disp_root}" ]] || disp_root="${PROJECT_ROOT}"
  # --repo overrides ONLY the git-evidence repo (where commits landed). The reservation
  # ledger + handoff lookups stay on the dispatch repo, because that is where the spawn
  # rows and docs/handoff/dispatch-<sig8>/ live. Printed in the header (R6) so a wrong-repo
  # read is visible, never silent.
  local evidence_repo="${repo_arg:-${disp_root}}"

  # Reservation ledger (dispatch-code.sh's dispatch_ledger_file shape: every confirmed
  # spawn). Overridable for tests.
  local res_file
  if [[ -n "${LEADV2_DISPATCH_RESERVATION_LEDGER_FILE:-}" ]]; then
    res_file="${LEADV2_DISPATCH_RESERVATION_LEDGER_FILE}"
  else
    local slug; slug="$(printf '%s' "$(basename "${disp_root}")" | tr -cd 'A-Za-z0-9._-')"
    res_file="${CACHE_BASE}/dispatch-ledger/${slug}.jsonl"
  fi
  local term_file; term_file="$(dispatch_terminal_ledger_file)"

  [[ ${json_mode} -eq 0 ]] && printf 'reconcile: repo=%s reservation=%s\n' "${evidence_repo}" "${res_file}" >&2
  if [[ ! -f "${res_file}" ]]; then
    log "reconcile: no reservation ledger at ${res_file} (repo=$(basename "${disp_root}"))"
    return 0
  fi
  [[ ${json_mode} -eq 0 ]] && printf 'lane_label | spawned | state | commit | deliverable\n' >&2

  # BATCH liveness: ONE `--all --json` call against the dispatch repo builds a sig8->verdict
  # map, consulted per-lane inside the loop. Spawning lane-liveness (python) per lane over
  # hundreds of reservation rows is what made a full reconcile time out (found live
  # 2026-08-04). Liveness runs against disp_root (where docs/handoff + active.yaml live),
  # NOT the evidence repo -- a cross-repo evidence repo has none of a persona-engine lane's
  # handoff dirs and would verdict dead:no_handoff_dir for every lane.
  local liv_map=""
  if [[ -f "${LANE_LIVENESS_BIN}" ]]; then
    liv_map="$(mktemp 2>/dev/null || mktemp -t liv)"
    LEADV2_PROJECT_ROOT="${disp_root}" bash "${LANE_LIVENESS_BIN}" --project-root "${disp_root}" --all --json 2>/dev/null \
      | python3 -c '
import json, sys, re
try:
    d = json.load(sys.stdin)
except Exception:
    sys.exit(0)
for r in (d.get("lanes") or []):
    lane = r.get("lane") or ""
    v = r.get("verdict") or ""
    m = re.match(r"dispatch-([0-9a-f]{8})", lane)
    if m:
        sys.stdout.write(m.group(1) + "\x1f" + v + "\n")
' > "${liv_map}" 2>/dev/null || true
  fi

  local ln sig sig8 lane_label created handle mission_path spawn_epoch
  local der term rest commit_sha deliverable_state cause
  local existing=0 stamped=0 running=0 stalled=0 warned=0
  # Read the reservation ledger once; per-row work is all read-only except the one locked
  # append through dispatch_ledger_write_terminal (same lock every other writer uses).
  while IFS= read -r ln || [[ -n "${ln}" ]]; do
    [[ "${ln}" == *'"state":"confirmed"'* ]] || continue
    sig="$(printf '%s' "${ln}" | sed -n 's/.*"task_sig":"\([^"]*\)".*/\1/p')"
    [[ -n "${sig}" ]] || continue
    sig8="${sig:0:8}"
    # --lane allowlist: when the founder names specific sig8s, process ONLY those (a full
    # reconcile over every confirmed row is correct but noisy; --lane scopes the table).
    if [[ -n "${lane_filter}" ]]; then
      case " ${lane_filter} " in *" ${sig8} "*) : ;; *) continue ;; esac
    fi
    lane_label="$(printf '%s' "${ln}" | sed -n 's/.*"lane_label":"\([^"]*\)".*/\1/p')"
    created="$(printf '%s' "${ln}" | sed -n 's/.*"created_epoch":\([0-9][0-9]*\).*/\1/p')"
    handle="$(printf '%s' "${ln}" | sed -n 's/.*"handle":"\([^"]*\)".*/\1/p')"
    mission_path="$(printf '%s' "${ln}" | sed -n 's/.*"mission_path":"\([^"]*\)".*/\1/p')"
    spawn_epoch="${since_arg:-${created}}"

    # Step 2: a terminal row already exists => print its recorded state, derive nothing,
    # write nothing. Reconcile is a CLOSE-LOOP for lanes with NO terminal, not a re-judge
    # of lanes the close gate already verdicted (D1's lying no_work is a separate task).
    if dispatch_any_terminal_exists "${sig8}"; then
      existing=$((existing + 1))
      local eterm ecommit edel
      eterm="$(_dispatch_terminal_last_field "${sig8}" "${term_file}" terminal)"
      ecommit="$(_dispatch_terminal_last_field "${sig8}" "${term_file}" commit)"
      edel="$(_dispatch_terminal_last_field "${sig8}" "${term_file}" deliverable)"
      _dl_emit_row "${sig8}" "${lane_label}" "${spawn_epoch}" "${eterm:-recorded}" "${ecommit}" "${edel}" "${json_mode}"
      continue
    fi

    # Steps 3-5: derive lane_writes + deliverable, then the lane state. Hand the lane its
    # precomputed liveness verdict (from the batched --all map) via env so _dl_derive_lane_
    # state does not spawn lane-liveness itself.
    local lane_writes="" deliverable="" vrd=""
    lane_writes="$(_dl_harvest_writes "${disp_root}" "${sig8}" "${mission_path}")"
    deliverable="$(_dl_harvest_deliverable "${mission_path}")"
    # Look up this lane's precomputed verdict in the batched map. The map key is the sig8
    # followed by a unit-separator byte; anchor the grep on BOTH so one sig8 that is a
    # prefix of another cannot mismatch. printf emits the real US byte (ANSI-C $'\x1f'
    # would NOT expand inside a double-quoted grep pattern -- a bug this line had briefly).
    local _us; _us="$(printf '\x1f')"
    [[ -n "${liv_map}" && -f "${liv_map}" ]] && vrd="$(grep -m1 "^${sig8}${_us}" "${liv_map}" 2>/dev/null | cut -d"${_us}" -f2-)"
    der="$(LEADV2_RECONCILE_VERDICT="${vrd}" _dl_derive_lane_state "${evidence_repo}" "${spawn_epoch}" "${lane_writes}" "${deliverable}" "dispatch-${sig8}" "${handle}")"
    term="${der%%$'\x1f'*}"
    rest="${der#*$'\x1f'}"
    commit_sha="${rest%%$'\x1f'*}"
    deliverable_state="${rest#*$'\x1f'}"

    case "${term}" in
      landed)
        cause="reconciled"
        if [[ "${deliverable_state}" == "missing" ]]; then
          cause="no_deliverable"
          warned=$((warned + 1))
          # LOUD: this is today's exact failure shape -- GLM committed and skipped the
          # deliverable file. Name the lane AND the commit so a human can check it.
          printf 'WARN: lane %s (%s) committed %s but wrote NO deliverable at %s\n' \
            "${lane_label:-${sig8}}" "${sig8}" "${commit_sha}" "${deliverable:-<unknown>}" >&2
        fi
        if dispatch_ledger_write_terminal "${sig8}" "${lane_label}" landed "${cause}" \
            "reconciled commit=${commit_sha}" "reconcile-$$" "${lane_label}" "${commit_sha}" "${deliverable_state}"; then
          stamped=$((stamped + 1))
        fi
        _dl_emit_row "${sig8}" "${lane_label}" "${spawn_epoch}" "landed:${cause}" "${commit_sha}" "${deliverable_state}" "${json_mode}"
        ;;
      dead)
        if dispatch_ledger_write_terminal "${sig8}" "${lane_label}" dead worker_died \
            "reconciled no_commit liveness=dead" "reconcile-$$" "${lane_label}" "none" "${deliverable_state}"; then
          stamped=$((stamped + 1))
        fi
        stalled=$((stalled + 1))
        _dl_emit_row "${sig8}" "${lane_label}" "${spawn_epoch}" "dead:worker_died" "none" "${deliverable_state}" "${json_mode}"
        ;;
      no_work)
        if dispatch_ledger_write_terminal "${sig8}" "${lane_label}" no_work empty_diff \
            "reconciled no_commit no_dirty" "reconcile-$$" "${lane_label}" "none" "${deliverable_state}"; then
          stamped=$((stamped + 1))
        fi
        stalled=$((stalled + 1))
        _dl_emit_row "${sig8}" "${lane_label}" "${spawn_epoch}" "no_work:empty_diff" "none" "${deliverable_state}" "${json_mode}"
        ;;
      running)
        running=$((running + 1))
        # NOT stamped -- a terminal for a live lane is the write-once poisoning bug.
        _dl_emit_row "${sig8}" "${lane_label}" "${spawn_epoch}" "running" "none" "${deliverable_state}" "${json_mode}"
        ;;
      *)
        # unknown/indeterminate -- NOT stamped. This is the unresolved lost-lane shape and
        # the one condition that makes reconcile exit non-zero.
        stalled=$((stalled + 1))
        _dl_emit_row "${sig8}" "${lane_label}" "${spawn_epoch}" "unknown" "none" "${deliverable_state}" "${json_mode}"
        ;;
    esac
  done < "${res_file}"

  [[ -n "${liv_map}" && -f "${liv_map}" ]] && rm -f "${liv_map}" 2>/dev/null

  [[ ${json_mode} -eq 0 ]] && log "reconcile: existing=${existing} stamped=${stamped} running=${running} stalled=${stalled} warned=${warned}" >&2

  # Exit 1 iff >=1 lane is live-and-stalled (no commit, no dirty tree, process dead or
  # indeterminate, no prior terminal) -- exactly the shape that was silently lost. Lanes
  # reconcile successfully RESOLVED (landed, or stamped dead/no_work) do NOT set this; they
  # now have a terminal row and are no longer lost. Second run: those rows are "existing",
  # stalled stays 0 => exit 0 (idempotent).
  [[ ${stalled} -gt 0 ]] && return 1
  return 0
}

usage() {
  cat >&2 <<EOF
Usage:
  ${SCRIPT_NAME}.sh write-terminal <sig8> <founder_task_id> <landed|parked|refused|dead|no_work> <cause> [<evidence>] [<attempt>] [<display_name>] [<commit>] [<deliverable>]
  ${SCRIPT_NAME}.sh exists <sig8>
  ${SCRIPT_NAME}.sh state <sig8>
  ${SCRIPT_NAME}.sh sweep
  ${SCRIPT_NAME}.sh reconcile [--repo <abs>] [--since <epoch|ISO>] [--lane <sig8>]... [--json]
EOF
  exit 2
}

case "${1:-}" in
  write-terminal)
    shift
    [[ $# -ge 3 ]] || usage
    dispatch_ledger_write_terminal "$1" "${2:-}" "$3" "${4:-}" "${5:-}" "${6:-}" "${7:-}" "${8:-}" "${9:-}" "${10:-}"
    exit $?
    ;;
  exists)
    shift
    [[ $# -ge 1 ]] || usage
    dispatch_terminal_exists "$1"
    exit $?
    ;;
  state)
    shift
    [[ $# -ge 1 ]] || usage
    dispatch_terminal_last_state "$1"
    exit 0
    ;;
  # LANE-OBSERVABILITY-02 change 2: the prepass invalidation gate needs the
  # last row's CAUSE (to see a census/prepass refusal), not just the terminal
  # word — same read-only shape as `state`: last row's field or empty.
  cause)
    shift
    [[ $# -ge 1 ]] || usage
    dispatch_terminal_last_cause "$1"
    exit 0
    ;;
  sweep)
    cmd_sweep
    exit $?
    ;;
  reconcile)
    shift
    cmd_reconcile "$@"
    exit $?
    ;;
  *) usage ;;
esac
