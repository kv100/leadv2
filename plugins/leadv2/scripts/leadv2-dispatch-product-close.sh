#!/usr/bin/env bash
# leadv2-dispatch-product-close.sh — detached post-worker readiness gates for ST-9.
# It is deliberately a script, not supervisor work: dispatch starts it only after a live
# product worker is confirmed.  It reports a missing e2e entrypoint, an unscopable diff, or
# a cross-provider conflict as a finding; none is silently passed.  Kill switches are passed
# explicitly by dispatch.
#
# GLM-DIED-WITH-WORK-RESUME-01: after the first worker exits with outcome:
# died-with-work or parked, this gate relaunches the provider's `bg` on the SAME worktree
# exactly once (marker-guarded), then waits for the second run before gating.
# Worst-case wall clock therefore doubles (4200s → 8400s) for a died-with-work
# lane.  Kill switch: LEADV2_PC_DWR_RESUME=0 restores single-wait behaviour.
set -uo pipefail

ROOT="${1:?root}"; TASK="${2:?task}"; AUTHOR="${3:?author}"; HANDLE="${4:-}"
E2E_ON="${5:-1}"; REVIEW_ON="${6:-1}"
# BLOCKING fix (review-verdict.md fanout.sh:1410-1426): optional 7th arg, the
# founder docs/tasks.yaml task id threaded from leadv2-fanout.sh via
# leadv2-dispatch-code.sh's --task-id/spawn_product_close. This script's own
# process lifetime IS the close gate's lifetime, so an EXIT trap is the one
# lifecycle owner that unclaims the SAME id fanout.sh claimed, on every exit
# path (pass, fail, blocked) -- omitted entirely when no founder id is known.
FOUNDER_TASK_ID="${7:-}"
# N7F-LANE-NAME: optional 8th arg, the display-only lane name threaded from
# leadv2-dispatch-code.sh's DISPATCH_LANE_NAME (spawn_product_close's close_bin call).
# This process holds it for its whole lifetime -- the close gate's own act-two --
# so the name survives the worker->close-phase handoff. Falls back to FOUNDER_TASK_ID
# for a 7-arg caller predating this change (back-compat, R6).
LANE_NAME="${8:-}"
[[ -z "${LANE_NAME}" ]] && LANE_NAME="${FOUNDER_TASK_ID}"
WRITES_CSV="${LEADV2_DISPATCH_LANE_WRITES:-}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
_ROUTE_ARBITER_SH="${LEADV2_ROUTE_ARBITER_LIB:-${SCRIPT_DIR}/lib/leadv2-route-arbiter.sh}"
[[ -f "${_ROUTE_ARBITER_SH}" ]] && source "${_ROUTE_ARBITER_SH}" || true
_PARKED_DETECT_SH="${SCRIPT_DIR}/lib/leadv2-parked-detect.sh"
[[ -f "${_PARKED_DETECT_SH}" ]] || _PARKED_DETECT_SH="${LEADV2_CANONICAL_ROOT:-${HOME}/Projects/leadv2}/plugins/leadv2/scripts/lib/leadv2-parked-detect.sh"
if [[ -f "${_PARKED_DETECT_SH}" ]]; then
  # shellcheck source=lib/leadv2-parked-detect.sh
  source "${_PARKED_DETECT_SH}" || true
fi
JOURNAL_BIN="${LEADV2_JOURNAL_BIN:-${SCRIPT_DIR}/leadv2-journal.sh}"
# REPORT-ONLY-GATE-01: optional lane deliverable declaration threaded from
# leadv2-dispatch-code.sh (row/CLI --lane-deliverable wins; else the mission's own
# LANE_DELIVERABLE: line). Guarded source + no-op stub, exactly the _REFUSAL_CLASSIFY_SH
# idiom below: a missing lib degrades to today's diff-only gate, never to a broken one.
LANE_DELIVERABLE="${LEADV2_DISPATCH_LANE_DELIVERABLE:-}"
_REPORT_DELIVERABLE_SH="${SCRIPT_DIR}/lib/leadv2-report-deliverable.sh"
if [[ ! -f "${_REPORT_DELIVERABLE_SH}" ]]; then
  _REPORT_DELIVERABLE_SH="${LEADV2_CANONICAL_ROOT:-${HOME}/Projects/leadv2}/plugins/leadv2/scripts/lib/leadv2-report-deliverable.sh"
fi
_pc_kind="diff"; _pc_report_rel=""
if [[ -f "${_REPORT_DELIVERABLE_SH}" ]] && source "${_REPORT_DELIVERABLE_SH}" \
   && [[ -n "${LANE_DELIVERABLE}" ]]; then
  # only an exactly-parsable `report:<rel>` declaration flips the kind; anything else
  # (already journalled status=ignored by dispatch-code.sh) keeps the diff gate.
  _pc_rd="$(lv2_deliverable_parse "${LANE_DELIVERABLE}")" \
    && { _pc_kind="report"; _pc_report_rel="${_pc_rd#*$'\x1f'}"; }
fi
DISPATCH_BIN="${LEADV2_DISPATCH_BIN:-${SCRIPT_DIR}/leadv2-dispatch-code.sh}"
# T-o (SUPERVISOR-AUDIT-01): this script owns the e2e/review half of a product task's
# lifecycle, so ITS exit paths are where that task's real terminal state (landed/parked/
# refused/dead) becomes known -- dispatch-code.sh deliberately does NOT write one for a
# product spawn (see that file's cmd_resolve arc==0 comment). Always a subprocess call
# (never sourced) -- see leadv2-dispatch-ledger.sh's own doc header.
LEDGER_BIN="${LEADV2_DISPATCH_LEDGER_BIN:-${SCRIPT_DIR}/leadv2-dispatch-ledger.sh}"
TERMINAL_LEDGER="${LEADV2_DISPATCH_TERMINAL_LEDGER:-1}"
# N-5: refusal classification (classify_arm_failure) for the arm-agnostic review
# fallback loop below. Private synced copy, not a shared source of dispatch-code.sh --
# see lib/leadv2-refusal-classify.sh's own header for why. `set -uo pipefail` only, no
# `-e` (SILENT-DEATH-01), so sourcing it cannot silently change this script's own set.
_REFUSAL_CLASSIFY_SH="${LEADV2_REFUSAL_CLASSIFY_BIN:-${SCRIPT_DIR}/lib/leadv2-refusal-classify.sh}"
if [[ ! -f "${_REFUSAL_CLASSIFY_SH}" ]]; then
  _REFUSAL_CLASSIFY_SH="${LEADV2_CANONICAL_ROOT:-${HOME}/Projects/leadv2}/plugins/leadv2/scripts/lib/leadv2-refusal-classify.sh"
fi
[[ -f "${_REFUSAL_CLASSIFY_SH}" ]] && source "${_REFUSAL_CLASSIFY_SH}"
# REVIEW-GATE-SHOWS-FINDINGS-01: shared findings renderer appended to review-gate.md
# at the review fail/pass exits below (this lane path wrote every real gate to date —
# both writers must render through the one shared renderer). Guarded source + no-op
# stub so a missing/broken renderer degrades to today's exact gate, never to a
# missing one (design R3).
_REVIEW_FINDINGS_SH="${SCRIPT_DIR}/leadv2-review-findings.sh"
[[ -f "${_REVIEW_FINDINGS_SH}" ]] || _REVIEW_FINDINGS_SH="${LEADV2_CANONICAL_ROOT:-${HOME}/Projects/leadv2}/plugins/leadv2/scripts/leadv2-review-findings.sh"
# shellcheck source=leadv2-review-findings.sh
[[ -f "${_REVIEW_FINDINGS_SH}" ]] && source "${_REVIEW_FINDINGS_SH}"
command -v render_gate_findings >/dev/null 2>&1 || render_gate_findings() { :; }
# BUILDER-SELFCHECK-GATE-01: mechanical falsification set (bash -n / py_compile /
# changed-scope suites) run on the lane's own diff before any review arm is spent.
# Guarded source + no-op stub (same idiom as _REVIEW_FINDINGS_SH above): a missing
# lib is an infrastructure fault, never a lane fault (R1) -- lv2_selfcheck_run
# absent means the gate step below degrades to a no-op, not a false block.
_BUILDER_SELFCHECK_SH="${SCRIPT_DIR}/lib/leadv2-builder-selfcheck.sh"
[[ -f "${_BUILDER_SELFCHECK_SH}" ]] || _BUILDER_SELFCHECK_SH="${LEADV2_CANONICAL_ROOT:-${HOME}/Projects/leadv2}/plugins/leadv2/scripts/lib/leadv2-builder-selfcheck.sh"
# shellcheck source=lib/leadv2-builder-selfcheck.sh
[[ -f "${_BUILDER_SELFCHECK_SH}" ]] && source "${_BUILDER_SELFCHECK_SH}"
# LANE-OBSERVABILITY-02 change 1: worker's-own-reason extractor (pure read,
# rc always 0, empty on miss). Guarded source + absence-safe call sites below
# (same idiom as the two libs above): a missing lib degrades every worker_reason
# to empty, never to a failed close. LEADV2_WORKER_REASON=0 is the kill switch.
_WORKER_REASON_SH="${SCRIPT_DIR}/lib/leadv2-worker-reason.sh"
[[ -f "${_WORKER_REASON_SH}" ]] || _WORKER_REASON_SH="${LEADV2_CANONICAL_ROOT:-${HOME}/Projects/leadv2}/plugins/leadv2/scripts/lib/leadv2-worker-reason.sh"
# shellcheck source=lib/leadv2-worker-reason.sh
[[ -f "${_WORKER_REASON_SH}" ]] && source "${_WORKER_REASON_SH}"
command -v lv2_worker_reason >/dev/null 2>&1 || lv2_worker_reason() { :; }
# LOW-2 (fixround-tails): qualified <sig8>-<epoch>-<pid> attempt token, computed ONCE so the
# explicit call and the EXIT trap's own retry (same process) reuse the identical value; a
# bare pid would recycle across days/reboots and could be misread as the same attempt.
_PC_ATTEMPT_EPOCH="$(date +%s 2>/dev/null || printf '0')"
_PC_ATTEMPT="${TASK}-${_PC_ATTEMPT_EPOCH}-$$"
# wave2 round2 finding 4: records the INTENDED terminal state BEFORE attempting the
# write, not just after. `|| true` below is deliberate -- a downstream review verdict
# must never fail this script just because ledger IO hiccuped -- but that also meant a
# transient write failure (lock-wait timeout, disk hiccup) was indistinguishable from
# "never reached a terminal path at all" by the time the EXIT trap ran. _PC_TERMINAL_*
# lets the EXIT trap retry the SAME explicit state instead of unconditionally
# downgrading a possibly-successful outcome to dead/crashed_unfinished.
_PC_TERMINAL_STATE=""
_PC_TERMINAL_CAUSE=""
_PC_TERMINAL_EVIDENCE=""
# LANE-OBSERVABILITY-02 change 1: the worker's own last words for a no_work/dead
# stop, computed ONCE per run (memoised — the review-gate writers below and the
# EXIT trap's idempotent _dl_note retry all reuse the identical value; the
# extraction scans stream/rollout files, so per-callsite recompute would be
# pure waste). Fail-open to empty on every path: a missing lib, an unreadable
# handoff, a kill switch — never a failed close. LEADV2_WORKER_REASON=0 off.
_PC_WORKER_REASON=""
_PC_WORKER_REASON_SET=0
_pc_worker_reason() {
  if [[ "${_PC_WORKER_REASON_SET}" == "1" ]]; then printf '%s' "${_PC_WORKER_REASON}"; return 0; fi
  _PC_WORKER_REASON_SET=1
  _PC_WORKER_REASON=""
  [[ "${LEADV2_WORKER_REASON:-1}" == "1" ]] || return 0
  _PC_WORKER_REASON="$(lv2_worker_reason "${HANDOFF:-}" "${AUTHOR:-}" "${TASK:-}" 2>/dev/null || true)"
  printf '%s' "${_PC_WORKER_REASON}"
}
_dl_note() {  # <terminal> <cause> [<evidence>] [<commit>] [<deliverable>]
  _PC_TERMINAL_STATE="$1"
  _PC_TERMINAL_CAUSE="$2"
  _PC_TERMINAL_EVIDENCE="${3:-}"
  # LANE-OBSERVABILITY-02: only a no_work/dead stop carries worker_reason —
  # landed/parked/refused have nothing to explain away. Appended to the
  # forwarded evidence (and threaded as write-terminal's optional arg 10) so
  # the ledger row, the journal line, and review-gate.md all say why in the
  # worker's own voice instead of only cause=arm_produced_nothing.
  local _wr=""
  case "$1" in
    no_work|dead) _wr="$(_pc_worker_reason)" ;;
  esac
  if [[ -n "${_wr}" && "${_PC_TERMINAL_EVIDENCE}" != *' worker_reason="'* ]]; then
    # the second guard keeps the EXIT trap's idempotent retry (which replays
    # _PC_TERMINAL_EVIDENCE verbatim) from appending the key a second time.
    _PC_TERMINAL_EVIDENCE="${_PC_TERMINAL_EVIDENCE}${_PC_TERMINAL_EVIDENCE:+ }worker_reason=\"${_wr}\""
  fi
  # REPORT-ONLY-GATE-01: optional write-terminal args 8/9. Recorded in _PC_TERMINAL_*
  # globals too so the EXIT trap's idempotent retry replays the SAME commit/deliverable,
  # never a downgraded "none"/"unknown". Existing 3-arg callers keep write-terminal's own
  # defaults — rows are byte-identical to pre-change for every non-report path.
  [[ -n "${4:-}" ]] && _PC_TERMINAL_COMMIT="$4"
  [[ -n "${5:-}" ]] && _PC_TERMINAL_DELIVERABLE="$5"
  [[ "${TERMINAL_LEDGER}" == "1" && -f "${LEDGER_BIN}" ]] || return 0
  # wave2 round3 finding 3 / LOW-2: _PC_ATTEMPT (qualified <sig8>-<epoch>-<pid>, not a bare
  # pid) is stable across BOTH this explicit call and the EXIT trap's own idempotent retry
  # of the same _PC_TERMINAL_* state (see _pc_exit_handler) -- the ledger's attempt-token
  # dedup uses it to recognize that retry as the SAME attempt (still write-once), while a
  # genuinely later, separate invocation of this script for the same TASK sig8 gets its own
  # token and is never blocked by an earlier refused/parked row.
  # N7F-LANE-NAME: 7th positional is the display name -- LANE_NAME already falls back
  # to FOUNDER_TASK_ID above when no name was threaded, so write-terminal's own
  # display_name-or-founder fallback is redundant here but harmless (never empty when
  # founder isn't either).
  bash "${LEDGER_BIN}" write-terminal "${TASK}" "${FOUNDER_TASK_ID}" "$1" "$2" "${_PC_TERMINAL_EVIDENCE}" "${_PC_ATTEMPT}" "${LANE_NAME}" "${_PC_TERMINAL_COMMIT:-none}" "${_PC_TERMINAL_DELIVERABLE:-unknown}" "${_wr}" >/dev/null 2>&1 9>&- || true
}
HANDOFF="${ROOT}/docs/handoff/dispatch-${TASK}"
mkdir -p "${HANDOFF}"
# wave2 round2 finding 3: resolves to the SAME cross-worktree location
# leadv2-dispatch-code.sh's own close_owner_pidfile() and leadv2-dispatch-ledger.sh's
# sweep both use (LEAD-CONTROL-PLANE-01) -- a repo-relative docs/handoff/... path is
# per-worktree and invisible to a sweep running in a different worktree of the same repo.
CACHE_BASE="${LEADV2_DISPATCH_CACHE_DIR:-${HOME}/.claude/cache}"
STATE_PATH_BIN="${LEADV2_STATE_PATH_BIN:-${SCRIPT_DIR}/leadv2-state-path.sh}"
close_owner_pidfile() {
  local sig8="$1" p=""
  if [[ -f "${STATE_PATH_BIN}" ]]; then
    p="$(PROJECT_ROOT="${ROOT}" bash "${STATE_PATH_BIN}" --no-link "dispatch-close-owner/${sig8}.pid" 2>/dev/null || true)"
  fi
  if [[ -z "${p}" ]]; then
    p="${CACHE_BASE}/dispatch-close-owner/${sig8}.pid"
  fi
  printf '%s' "${p}"
}
# wave2 finding 5 / round2 finding 3: the sweep in leadv2-dispatch-ledger.sh needs a
# positive liveness signal for THIS process (the terminal-state owner for a product
# task) so it never races a still-running e2e/review gate. dispatch-code.sh's own
# spawn_product_close already stamps this record BEFORE backgrounding this script (the
# authoritative write, using the real fork pid with no startup gap); this refresh is a
# harmless idempotent re-confirmation of the same pid for the normal path, and the ONLY
# record at all when this script is invoked directly (tests, manual re-run) rather than
# through spawn_product_close.
_CLOSE_OWNER_PIDFILE="$(close_owner_pidfile "${TASK}")"
mkdir -p "$(dirname "${_CLOSE_OWNER_PIDFILE}")" 2>/dev/null
# wave2 round3 finding 2: write through a same-directory temp file + atomic rename
# instead of a direct `>` truncate-in-place. A direct write leaves a window in which a
# concurrent sweep can open the file mid-write and read a truncated/empty pid -- rename(2)
# is atomic, so a reader only ever sees the OLD complete content or the NEW complete
# content, never a partial one.
_CLOSE_OWNER_PIDFILE_TMP="${_CLOSE_OWNER_PIDFILE}.tmp.$$"
if printf '%s\n' "$$" > "${_CLOSE_OWNER_PIDFILE_TMP}" 2>/dev/null; then
  mv -f "${_CLOSE_OWNER_PIDFILE_TMP}" "${_CLOSE_OWNER_PIDFILE}" 2>/dev/null || true
else
  rm -f "${_CLOSE_OWNER_PIDFILE_TMP}" 2>/dev/null || true
fi

# wave2 finding 7: this script's own process lifetime IS the close gate's lifetime, so
# an EXIT/signal trap is the one lifecycle owner that can guarantee SOME terminal row
# gets written even for a crash, an unbound-variable abort, or a signal -- not just the
# enumerated success/failure branches below. _dl_note is write-once (see
# leadv2-dispatch-ledger.sh): if an explicit terminal state was already recorded on a
# normal exit path, this call is a harmless no-op dedup; if the script died before ever
# reaching one, this is the ONLY row that will ever exist for the task. Chained ahead of
# the tasks-lib unclaim (below) so the terminal write always happens first regardless of
# whether FOUNDER_TASK_ID/tasks-lib are even available.
_pc_exit_handler() {
  # Capture the triggering exit code FIRST -- every statement below (including the
  # `[[` tests) would otherwise overwrite $? before the review_crashed row could log it.
  local _pc_exit_rc=$?
  # wave2 round2 finding 4: retry the explicitly-recorded terminal state (if any
  # branch below ever reached one) instead of unconditionally writing crashed_
  # unfinished. write-once dedup (leadv2-dispatch-ledger.sh) makes this call a no-op
  # when the earlier explicit write actually landed, and the only remaining chance to
  # record the true outcome when that earlier attempt silently failed. Only a run that
  # NEVER reached an explicit terminal path at all (a genuine crash, unbound-variable
  # abort, or signal) falls through to dead/crashed_unfinished.
  if [[ -n "${_PC_TERMINAL_STATE}" ]]; then
    _dl_note "${_PC_TERMINAL_STATE}" "${_PC_TERMINAL_CAUSE}" "${_PC_TERMINAL_EVIDENCE}" >/dev/null 2>&1 || true
  else
    _dl_note dead crashed_unfinished "exit_trap" >/dev/null 2>&1 || true
  fi
  # N-5 D3: once the review phase is entered (_PC_REVIEW_ENTERED=1, set right after the
  # REVIEW_ON kill-switch check), review-gate.md must exist on EVERY exit path -- a crash
  # (unbound var, SIGTERM mid-poll, a killed provider launcher) must never leave it
  # silently absent, which is exactly the "review-gate.md was never created at all"
  # defect this lane exists to close. Existence-gated so this can never clobber a real
  # artifact an explicit terminal branch above already wrote.
  if [[ "${_PC_REVIEW_ENTERED:-0}" == "1" && ! -f "${HANDOFF}/review-gate.md" ]]; then
    printf 'status: unreviewed\nreason: review_crashed\nrc: %s\n' "${_pc_exit_rc}" > "${HANDOFF}/review-gate.md" 2>/dev/null || true
    _stamp_active_phase "${FOUNDER_TASK_ID}" "review:unreviewed" 2>/dev/null || true
  fi
  if [[ -n "${FOUNDER_TASK_ID}" ]] && declare -F leadv2_tasks_unclaim >/dev/null 2>&1; then
    leadv2_tasks_unclaim "${FOUNDER_TASK_ID}" >/dev/null 2>&1 || true
  fi
}
trap '_pc_exit_handler' EXIT
# Convert an untrapped-by-default signal into a normal `exit`, so the EXIT trap above
# always fires (bash runs the EXIT trap on any `exit`, including one called from inside
# another trap) instead of the process dying before _pc_exit_handler ever runs.
trap 'exit 143' TERM
trap 'exit 130' INT
trap 'exit 129' HUP

if [[ -n "${FOUNDER_TASK_ID}" ]]; then
  _TASKS_LIB="${SCRIPT_DIR}/leadv2-tasks-lib.sh"
  if [[ -f "${_TASKS_LIB}" ]]; then
    PROJECT_ROOT="${ROOT}"
    # shellcheck source=leadv2-tasks-lib.sh
    source "${_TASKS_LIB}"
  fi
fi

emit() { # type text
  if [[ -f "${JOURNAL_BIN}" ]]; then bash "${JOURNAL_BIN}" append "dispatch-${TASK}" "$1" "$2" >/dev/null 2>&1 || true; fi
  printf '[leadv2-dispatch-product-close] %s\n' "$2" >&2
}

# Phase stamps into active.yaml (SUPERVISOR-AUDIT-01 addendum, founder 2026-07-30) — see
# leadv2-dispatch-code.sh's matching block for the full rationale (fix-fanout made the
# funnel the row's lifecycle owner; nothing ever advanced `phase` past "spawning"). This
# script owns the e2e/review half of the same funnel run, so it stamps those two
# transitions with the same cheap update_phase PATCH; dispatch-code.sh stamps prepass/build.
# Keyed by FOUNDER_TASK_ID (fanout's active.yaml row id), never TASK (the internal sig8) --
# guarded against empty/unset so leadv2_active_update_phase's "${1:?...}" can never abort
# this script under `set -u` when no founder id was threaded through (e.g. a bare re-run).
_ACTIVE_REGISTRY_SH="${SCRIPT_DIR}/leadv2-active-registry.sh"
[[ -f "${_ACTIVE_REGISTRY_SH}" ]] && source "${_ACTIVE_REGISTRY_SH}"
# SILENT-DEATH-01 (SUPERVISOR-AUDIT-01, 2026-07-30): leadv2-active-registry.sh's own
# `set -euo pipefail` (line 26) leaks into this shell via `source` and silently overrides
# this script's own `set -uo pipefail` (line 7, deliberately no -e) -- see
# leadv2-dispatch-code.sh's matching block for the full mechanism. Restore immediately.
set +e
_stamp_active_phase() { # <task_id> <phase>
  [[ -n "${1:-}" ]] || return 0
  declare -F leadv2_active_update_phase >/dev/null || return 0
  LEADV2_PROJECT_ROOT="${ROOT}" leadv2_active_update_phase "$1" "$2" >/dev/null 2>&1 || true
}
# N-5 §2.4: re-stamp active.yaml's phase on every TERMINAL review outcome (pass/fail/
# unreviewed/blocked), not just once at entry -- the founder-facing status surface
# renders whatever phase string it finds, so `review:unreviewed` (etc.) appears in the
# lane row without any change to leadv2-status-surface.sh/leadv2-state-path.sh (both
# off-limits). If the surface ever truncates at `:`, this degrades to today's bare
# `review` -- strictly no worse than before this change.
_stamp_review_terminal() { # <pass|fail|unreviewed|blocked>
  _stamp_active_phase "${FOUNDER_TASK_ID}" "review:$1"
}

# dispatch-8e2a32be D5: literal "-" instead of a blank field for "nothing here" --
# a blank pool:/tried: was indistinguishable from "field not populated by this code
# path" vs "resolver/loop genuinely produced zero entries". Used by BOTH terminal
# no-reviewer branches so review-gate.md's shape is identical regardless of which
# one fired.
_pc_or_dash() { [[ -n "${1:-}" ]] && printf '%s' "$1" || printf '%s' '-'; }

# dispatch-8e2a32be A3: the ONE writer for "no reviewer was ever seated" -- both the
# resolver-returned-nothing branch and the loop-exhausted branch call this, so their
# review-gate.md shape can never diverge again (the pre-fix divergence -- one branch
# hardcoded `tried: ` and printed no refusal:/resolver_rc: line at all -- is exactly
# what made the live artifact undiagnosable). merge_blocked: true is a published
# contract field; no consumer reads it yet (explicitly out of scope, see design §5).
# <refusal> <pool> <tried> <resolver_rc> <resolver_stderr_path>
_pc_write_unreviewed() {
  local refusal="$1" pool="$2" tried="$3" resolver_rc="$4" resolver_stderr="$5"
  printf 'status: unreviewed\nreason: all_arms_unavailable\nauthor: %s\npool: %s\ntried: %s\nrefusal: %s\nresolver_rc: %s\nresolver_stderr: %s\nmerge_blocked: true\n' \
    "${AUTHOR}" "$(_pc_or_dash "${pool}")" "$(_pc_or_dash "${tried}")" "${refusal:-all_arms_unavailable}" \
    "$(_pc_or_dash "${resolver_rc}")" "$(_pc_or_dash "${resolver_stderr}")" > "${HANDOFF}/review-gate.md"
  emit decision "review_gate task=${TASK} status=unreviewed reason=all_arms_unavailable author=${AUTHOR} pool=$(_pc_or_dash "${pool}") tried=$(_pc_or_dash "${tried}") refusal=${refusal:-all_arms_unavailable} resolver_rc=$(_pc_or_dash "${resolver_rc}")" || true
  _dl_note dead all_arms_unavailable "author=${AUTHOR} pool=${pool} tried=${tried} refusal=${refusal}"
  _stamp_review_terminal unreviewed
}

# dispatch-00629379 (P0, 2026-07-30): Fix6 (SUPERVISOR-AUDIT-01) called the resolver
# for exactly ONE arm (job=review, base-arm=codex) -- with codex quota-gated out and
# GLM structurally banned from review, EVERY build resolved to sonnet, so the single
# resolved reviewer was also sonnet, and the self-review guard below correctly (but
# permanently) refused it as `status: conflict`. Root cause was never candidate_arms
# (that path was already dead, T-b) -- it was a single-arm resolver with no fallback
# pool and no opus/glm review path. Fixed here: the resolver now returns an ORDERED,
# quota-filtered, author-excluding POOL (--review-pool --author) so this function
# picks the first eligible arm instead of being handed a single already-collided one.
# Founder decisions encoded (2026-07-30): opus is now a valid reviewer arm; glm
# reviews up to its OWN 90% band (review-only headroom above the 80% build gate).
# Fail-safe: any resolver-missing/error path yields empty reviewer/pool + a distinct
# refusal reason -- the caller then writes `status: no_reviewer`, never a silent
# collapse to sonnet (which would just re-create the self-review bug for a sonnet
# author) or to glm (founder rule: GLM never reviews without going through its own
# quota check, never as a blind fallback).
resolve_review_pool_call() {
  local resolver="${LEADV2_GLM_POLICY_RESOLVER:-}"
  if [[ -z "${resolver}" ]]; then
    if [[ -f "${SCRIPT_DIR}/lib/leadv2-glm-policy-resolve.py" ]]; then
      resolver="${SCRIPT_DIR}/lib/leadv2-glm-policy-resolve.py"
    else
      local _canonical="${LEADV2_CANONICAL_ROOT:-${HOME}/Projects/leadv2}/plugins/leadv2/scripts/lib/leadv2-glm-policy-resolve.py"
      [[ -f "${_canonical}" ]] && resolver="${_canonical}"
    fi
  fi
  if [[ -z "${resolver}" || ! -f "${resolver}" ]]; then
    printf 'reviewer=\npool=\nrefusal=resolver_missing_failclosed\n'
    return
  fi
  # dispatch-8e2a32be D1: ordered first-existing-file-wins search. Root cause this
  # fixes: the pre-fix single lookup (${LEADV2_ROUTING_YAML:-${ROOT}/.claude/ref/
  # leadv2-routing.yaml}) never found a file at runtime -- .claude/ref/
  # leadv2-routing.yaml does not exist in ANY of the three live repos -- so the
  # resolver silently ran its no-op/fail-closed fallback and this function never
  # printed a real reviewer=/pool=/refusal= line at all. Tenant-override precedence
  # (env var, then repo-local .claude/ref/) is UNCHANGED; this only adds the
  # plugin-local and canonical tiers so a repo that never opted into a tenant
  # override still resolves against a real routing yaml instead of nothing.
  local routing_yaml="" _ry_source="none"
  if [[ -n "${LEADV2_ROUTING_YAML:-}" && -f "${LEADV2_ROUTING_YAML}" ]]; then
    routing_yaml="${LEADV2_ROUTING_YAML}"; _ry_source="tenant"
  elif [[ -f "${ROOT}/.claude/ref/leadv2-routing.yaml" ]]; then
    routing_yaml="${ROOT}/.claude/ref/leadv2-routing.yaml"; _ry_source="tenant"
  elif [[ -f "${SCRIPT_DIR}/../config/leadv2-routing.yaml" ]]; then
    routing_yaml="${SCRIPT_DIR}/../config/leadv2-routing.yaml"; _ry_source="plugin"
  elif [[ -f "${LEADV2_CANONICAL_ROOT:-${HOME}/Projects/leadv2}/plugins/leadv2/config/leadv2-routing.yaml" ]]; then
    routing_yaml="${LEADV2_CANONICAL_ROOT:-${HOME}/Projects/leadv2}/plugins/leadv2/config/leadv2-routing.yaml"
    _ry_source="canonical"
  else
    # True last resort: keep the OLD default expression so a caller that somehow has
    # none of the above still gets exactly the pre-fix path (and therefore the
    # resolver's own D1 self-heal gets one more chance at it).
    routing_yaml="${LEADV2_ROUTING_YAML:-${ROOT}/.claude/ref/leadv2-routing.yaml}"
  fi
  emit decision "review_routing_yaml task=${TASK} source=${_ry_source}" || true
  # CODEX-GATE-01 item 6: compute REAL safety signals from the lane's write paths vs the
  # protected_path_patterns in routing yaml (fail-closed), instead of the hardcoded
  # --signals '{}' that left the resolver's kimi:excluded:safety branch unreachable on the
  # live review path. WRITES_CSV is resolved at line 18, long before this call. If the lib
  # is missing -> fail-closed JSON (protected_path=true) so the free arm is never admitted.
  local _signals_json='{"protected_path":true,"safety_touched":true}'
  local _signals_lib="${SCRIPT_DIR}/lib/leadv2-review-signals.sh"
  local _sig_source="lib_missing_failclosed" _sig_protected="1" _sig_matched="-"
  if [[ -f "${_signals_lib}" ]]; then
    # shellcheck source=lib/leadv2-review-signals.sh
    source "${_signals_lib}" || true
    # The lib is invoked under $(), a subshell that cannot propagate globals back, so it also
    # emits signals_source=/signals_matched= on stderr -- capture that to a temp file.
    local _sig_cap
    _sig_cap="$(mktemp "${TMPDIR:-/tmp}/leadv2-rev-sig.XXXXXX" 2>/dev/null || printf '%s/leadv2-rev-sig.%s' "${TMPDIR:-/tmp}" "$$")"
    _signals_json="$(leadv2_review_signals "${routing_yaml}" "${WRITES_CSV}" 2>"${_sig_cap}" || true)"
    _sig_source="$(sed -n 's/^signals_source=//p' "${_sig_cap}" | head -n1)"
    _sig_matched="$(sed -n 's/^signals_matched=//p' "${_sig_cap}" | head -n1)"
    rm -f "${_sig_cap}" 2>/dev/null || true
    [[ -n "${_sig_source}" ]] || _sig_source="lib_missing_failclosed"
    [[ -n "${_sig_matched}" ]] || _sig_matched="-"
    # protected_path bool: read straight off the JSON the lib produced (its own source of truth).
    case "${_signals_json}" in
      *'"protected_path":false'*) _sig_protected="0" ;;
      *) _sig_protected="1" ;;
    esac
  fi
  # Observability (D5): without this line the fix is unobservable at any human surface --
  # which is exactly what let --signals '{}' live. matched=- means no path matched (or scope
  # unknown); source token distinguishes lane_writes from the two fail-closed reasons.
  emit decision "review_signals task=${TASK} protected_path=${_sig_protected} source=${_sig_source} matched=${_sig_matched}" || true
  local -a resolver_args=(--routing-yaml "${routing_yaml}" --job review --base-arm codex \
    --review-pool --author "${AUTHOR}" --signals "${_signals_json}")
  [[ -n "${GLM_POLICY_QUOTA_LIVE:-}" ]] && resolver_args+=(--quota-live "${GLM_POLICY_QUOTA_LIVE}")
  # dispatch-8e2a32be A2: the resolver's own stderr used to be thrown away
  # (`2>/dev/null`) -- the single reason a resolver crash was invisible all day. It now
  # lands in a per-lane file (never the console) and the rc is captured explicitly
  # instead of only being observable via the `|| printf fallback` firing. Both are
  # surfaced as resolver_rc=/resolver_stderr= lines so BOTH terminal branches below can
  # report them (A3) -- a non-zero rc with a real reviewer=/pool= line (the resolver's
  # own internal fallback already degrades gracefully) is not itself a failure; the
  # verdict field for "did review actually run" stays reviewer=, never resolver_rc=.
  local _resolver_err_file="${HANDOFF}/review-pool-resolver.err"
  local _resolver_out _resolver_rc
  mkdir -p "${HANDOFF}" 2>/dev/null || true
  _resolver_out="$(python3 "${resolver}" "${resolver_args[@]}" 2>"${_resolver_err_file}")"
  _resolver_rc=$?
  if [[ -z "${_resolver_out}" ]]; then
    _resolver_out=$'reviewer=\npool=\nrefusal=resolver_error_failclosed'
  fi
  # T17: use the same live-window arbiter for review selection. The existing
  # pool resolver remains the availability authority; an arbiter choice is only
  # adopted when that arm is present as an available, non-self reviewer.
  if declare -F route_arbiter >/dev/null 2>&1; then
    local _ra_desc _ra_out _ra_rc _ra_arm _ra_chain _ra_util _ra_author _ra_pick=""
    _ra_desc="$(python3 -c 'import json,sys; print(json.dumps({"kind":"review","size":"standard","protected":sys.argv[1]=="1","safety":sys.argv[1]=="1"}))' "${_sig_protected}")"
    _ra_out="$(route_arbiter reviewer "${_ra_desc}")"; _ra_rc=$?
    _ra_arm="$(printf '%s\n' "${_ra_out}" | sed -n 's/.*arm=\([^ ]*\).*/\1/p')"
    _ra_chain="$(printf '%s\n' "${_ra_out}" | sed -n 's/.*chain=\([^ ]*\).*/\1/p')"
    _ra_util="$(printf '%s\n' "${_ra_out}" | sed -n 's/.*\(util_glm=.*\)$/\1/p')"
    _ra_author="${AUTHOR%%:*}"
    if [[ ${_ra_rc} -eq 0 ]]; then
      local _ra_candidate
      IFS=',' read -r -a _ra_candidates <<< "${_ra_chain}"
      for _ra_candidate in "${_ra_candidates[@]}"; do
        [[ "${_ra_candidate}" == "${_ra_author}" ]] && continue
        if printf '%s\n' "${_resolver_out}" | sed -n 's/^pool=//p' | tr ',' '\n' | grep -q "^${_ra_candidate}:ok:"; then
          _ra_pick="${_ra_candidate}"; break
        fi
      done
      if [[ -n "${_ra_pick}" ]]; then
        _resolver_out="$(printf '%s\n' "${_resolver_out}" | sed "s/^reviewer=.*/reviewer=${_ra_pick}/")"
        emit decision "route_resolved by=arbiter role=reviewer arm=${_ra_pick} task=${TASK} reason=cheapest_capable ${_ra_util}" || true
      else
        emit decision "arbiter_broken task=${TASK} role=reviewer rc=0 reason=arbiter_arm_not_available ${_ra_util}" || true
      fi
    else
      emit decision "arbiter_broken task=${TASK} role=reviewer rc=${_ra_rc} reason=fail_open_to_review_pool" || true
    fi
  else
    emit decision "arbiter_broken task=${TASK} role=reviewer rc=127 reason=missing_fail_open_to_review_pool" || true
  fi
  emit decision "review_pool_resolve task=${TASK} rc=${_resolver_rc} reviewer=$(printf '%s\n' "${_resolver_out}" | sed -n 's/^reviewer=//p' | head -n1) pool_n=$(printf '%s\n' "${_resolver_out}" | sed -n 's/^pool=//p' | head -n1 | awk -F',' '{n=0; for(i=1;i<=NF;i++) if ($i!="") n++; print n}')" || true
  printf '%s\n' "${_resolver_out}"
  printf 'resolver_rc=%s\n' "${_resolver_rc}"
  printf 'resolver_stderr=%s\n' "${_resolver_err_file}"
}

# The reviewer wrapper and the reviewer do not necessarily use the same stream.  In
# particular, claude-subsession writes the critic's text to this handoff directory
# and prints only a handle on stdout.  Keep the artifact resolution and the verdict
# parser deliberately narrow: review prose is never a verdict contract.
resolve_review_artifact() {
  local adir="${ROOT}/docs/handoff/dispatch-${TASK}-review" cand
  REVIEW_ARTIFACT=""
  REVIEW_SOURCE=""
  for cand in "${adir}/critic.full.md" "${adir}/critic.md" "${adir}/critic.summary.md"; do
    if [[ -s "${cand}" && "${cand}" -nt "${REVIEW_STAMP}" ]]; then
      REVIEW_ARTIFACT="${cand}"
      REVIEW_SOURCE="artifact:${cand#"${ROOT}/"}"
      return 0
    fi
  done
  return 1
}

# REVIEW-BODY-PERSIST-01: after an opus/sonnet arm finishes, claude-subsession has
# written the full review body to the handoff deliverable files (critic.full.md etc.)
# but printed only a label/session header on stdout -- which is all review_out captured.
# This function appends the best-available body into review_out, preserving the label
# line as a header. The same freshness gate (-nt REVIEW_STAMP) the resolver uses ensures
# a stale deliverable from a prior arm/attempt is never adopted. Fallback: extract the
# final assistant text blocks from the stream transcript.  Returns 0 if body was
# materialised, 1 if nothing was found.
materialize_subsession_body() { # <review_out> <review_stamp> <task_id>
  local rfile="$1" rstamp="$2" tid="$3"
  local adir="${ROOT}/docs/handoff/dispatch-${tid}-review"
  local cand body_file="" rel_path=""

  for cand in "${adir}/critic.full.md" "${adir}/critic.md" "${adir}/critic.summary.md"; do
    if [[ -s "${cand}" && "${cand}" -nt "${rstamp}" ]]; then
      body_file="${cand}"
      rel_path="${cand#"${ROOT}/"}"
      break
    fi
  done

  if [[ -z "${body_file}" ]]; then
    # Fallback: extract final assistant text blocks from the stream transcript.
    local stream="${adir}/critic.stream.jsonl"
    if [[ -s "${stream}" && "${stream}" -nt "${rstamp}" ]] && command -v python3 >/dev/null 2>&1; then
      local tmp_body
      tmp_body="$(python3 - "$stream" 2>/dev/null <<'PY'
import json, sys
texts = []
for line in open(sys.argv[1]):
    line = line.strip()
    if not line:
        continue
    try:
        obj = json.loads(line)
    except Exception:
        continue
    # stream-json: collect text from assistant message content blocks
    if obj.get("type") == "assistant":
        msg = obj.get("message", {})
        for block in msg.get("content", []):
            if isinstance(block, dict) and block.get("type") == "text":
                texts.append(block.get("text", ""))
if texts:
    print(texts[-1])
PY
      )"
      if [[ -n "${tmp_body}" ]]; then
        local label_line
        label_line="$(cat "${rfile}" 2>/dev/null)"
        printf '%s\n--- body from: %s ---\n%s\n' "${label_line}" "${stream#"${ROOT}/"}" "${tmp_body}" > "${rfile}"
        return 0
      fi
    fi
    return 1
  fi

  local label_line
  label_line="$(cat "${rfile}" 2>/dev/null)"
  printf '%s\n--- body from: %s ---\n' "${label_line}" "${rel_path}" > "${rfile}.tmp"
  cat "${body_file}" >> "${rfile}.tmp"
  mv "${rfile}.tmp" "${rfile}"
  return 0
}

parse_review_verdict() { # review-file
  local review_file="$1"
  PARSED_VERDICT=""
  VERDICT_SOURCE=""
  FINDINGS_CRITICAL=0
  FINDINGS_HIGH=0
  FINDINGS_MEDIUM=0
  FINDINGS_LOW=0

  PARSED_VERDICT="$(sed -nE 's/^[[:space:]]*REVIEW_VERDICT:[[:space:]]*(FAIL|PASS_WITH_NITS|PASS)([[:space:]]|$).*/\1/p' "${review_file}" | head -n 1)"
  if [[ -n "${PARSED_VERDICT}" ]]; then
    VERDICT_SOURCE="marker"
  else
    PARSED_VERDICT="$(sed -nE 's/^[[:space:]]*(VERDICT|Verdict):[[:space:]]*(FAIL|PASS_WITH_NITS|PASS)([[:space:]]|$).*/\2/p' "${review_file}" | head -n 1)"
    [[ -n "${PARSED_VERDICT}" ]] && VERDICT_SOURCE="alt_marker"
  fi
  [[ -n "${PARSED_VERDICT}" ]] || return 1

  # MAJOR fix (review-verdict.md dispatch-product-close.sh:49-56): REVIEW_FINDINGS
  # used to be optional -- a reviewer emitting only REVIEW_VERDICT: PASS was
  # accepted with implicit zero Critical/High findings. Reject any review missing
  # exactly one valid findings-count marker (none = unscoped verdict; more than
  # one = ambiguous) rather than defaulting silently to all-zero.
  local findings_matches findings_count
  findings_matches="$(sed -nE 's/^[[:space:]]*REVIEW_FINDINGS:[[:space:]]*critical=([0-9]+)[[:space:]]+high=([0-9]+)[[:space:]]+medium=([0-9]+)[[:space:]]+low=([0-9]+)[[:space:]]*$/\1 \2 \3 \4/p' "${review_file}")"
  findings_count="$(printf '%s\n' "${findings_matches}" | grep -c .)"
  if [[ "${findings_count}" -ne 1 ]]; then
    PARSED_VERDICT=""
    return 1
  fi
  read -r FINDINGS_CRITICAL FINDINGS_HIGH FINDINGS_MEDIUM FINDINGS_LOW <<< "${findings_matches}"
  if [[ "${PARSED_VERDICT}" != FAIL && ( ${FINDINGS_CRITICAL} -gt 0 || ${FINDINGS_HIGH} -gt 0 ) ]]; then
    PARSED_VERDICT=FAIL
    VERDICT_SOURCE="contradiction_override"
  fi
}

# N-5 §2.2 D4: plausibility floor -- a review-glm.md that is 1 line of unrelated text
# must never reach parse_review_verdict and pass by accident of that parser rejecting
# it under a misleading "review_unusable" label. Reject below the floor UNLESS the file
# already carries both contract markers regardless of size (lenient: a legitimately
# terse-but-valid review must never be false-red -- see N-5 risk table). Overridable via
# LEADV2_REVIEW_MIN_BYTES for the test harness only; default matches the design doc.
review_floor_ok() { # <file> -> 0 if it clears the floor, 1 if not
  local f="$1"
  local min_bytes="${LEADV2_REVIEW_MIN_BYTES:-200}"
  if grep -q '^[[:space:]]*REVIEW_VERDICT:' "${f}" 2>/dev/null && \
     grep -q '^[[:space:]]*REVIEW_FINDINGS:' "${f}" 2>/dev/null; then
    return 0
  fi
  local bytes lines
  bytes="$(wc -c < "${f}" 2>/dev/null | tr -d '[:space:]')"; bytes="${bytes:-0}"
  lines="$(wc -l < "${f}" 2>/dev/null | tr -d '[:space:]')"; lines="${lines:-0}"
  if [[ "${bytes}" -lt "${min_bytes}" || "${lines}" -lt 3 ]]; then
    return 1
  fi
  return 0
}

# PREMATURE-NO-WORK-TERMINAL-01: this process starts as soon as the worker is
# confirmed, not when it finishes. Keep every terminal-producing gate behind a
# provider-aware exit proof so an early watcher wake cannot classify an untouched
# worktree as no_work. The 4200s default is the longest in-worker timeout (GLM/Kimi:
# 3600s) plus ten minutes of finalization grace; callers can align it to a stricter
# lane timeout with LEADV2_PC_WORKER_MAX_WAIT_S.
_PC_RUNS_ROOT="${LEADV2_PC_RUNS_ROOT:-${HOME}/.claude/cache}"
_PC_JOB_REGISTRY_ROOT="${LEADV2_JOB_REGISTRY_ROOT:-/tmp/leadv2-job-registry}"
_PC_WORKER_WAITED_S=0
_PC_WORKER_PROBE_TIMEOUT_S=20

# GLM-DIED-WITH-WORK-RESUME-01: resume a died-with-work lane exactly once.
# When the first worker finishes with outcome: died-with-work (the run hit a bound
# -- stall/turn-cap/wall-clock -- but left real work behind), relaunch the SAME
# provider's `bg` entrypoint on the SAME worktree with a resume prefix, so a
# recoverable death is not silently buried as a permanent no-work/e2e_regression.
# Exactly once: a per-lane marker file prevents any second attempt.  Kill switch:
# LEADV2_PC_DWR_RESUME=0 restores byte-for-byte current behaviour.

# Resolve the run-dir path for a given author+handle (mirrors the liveness probe
# and the asked-into-void block).  Empty when unresolvable.
_pc_run_dir_for() { # <author> <handle> -> path on stdout
  local author="$1" handle="$2" run_dir=""
  [[ -n "${author}" && -n "${handle}" ]] || { printf ''; return 0; }
  case "${author}" in
    glm)  run_dir="${GLM_RUNS_DIR:-${_PC_RUNS_ROOT}/glm-runs}/${handle}" ;;
    kimi) run_dir="${KIMI_RUNS_DIR:-${_PC_RUNS_ROOT}/kimi-runs}/${handle}" ;;
    *)    run_dir="${_PC_RUNS_ROOT}/${author}-runs/${handle}" ;;
  esac
  printf '%s' "${run_dir}"
}

# Set global _PC_ASKED_INTO_VOID from current AUTHOR/HANDLE.  Called before the
# first wait AND after a successful resume (R5: stale marker from run A must not
# park a lane that run B unblocked).
_pc_resolve_asked_into_void() {
  _PC_ASKED_INTO_VOID=""
  [[ -n "${AUTHOR:-}" && -n "${HANDLE:-}" ]] || return 0
  _PC_ASKED_INTO_VOID="$(_pc_run_dir_for "${AUTHOR}" "${HANDLE}")/.asked_into_void"
}

# Read the classifier outcome from a run dir's meta.yaml, falling back to the
# .outcome sentinel (outcome= form) for legacy runs that predate the meta append.
_pc_lane_outcome() { # <run_dir> -> completed|died-with-work|died-clean|parked|""
  local run_dir="$1" meta outcome
  meta="${run_dir}/meta.yaml"
  if [[ -f "${meta}" ]]; then
    outcome="$(_pc_meta_value "${meta}" outcome)"
    [[ -n "${outcome}" ]] && { printf '%s' "${outcome}"; return 0; }
  fi
  # Fallback: .outcome sentinel written by leadv2-lane-outcome.sh.
  local sentinel="${run_dir}/.outcome"
  [[ -f "${sentinel}" ]] || { printf ''; return 0; }
  sed -n 's/^outcome=//p' "${sentinel}" 2>/dev/null | head -n 1
}

# Resolve the provider launcher script.  Empty when no regular file exists
# (e.g. sonnet/codex authors have no <author>-coder.sh).
_pc_resume_launcher_for() { # <author> -> absolute path or empty
  local author="$1" launcher
  [[ -n "${LEADV2_PC_RESUME_LAUNCHER_BIN:-}" ]] && { printf '%s' "${LEADV2_PC_RESUME_LAUNCHER_BIN}"; return 0; }
  [[ -n "${author}" ]] || { printf ''; return 0; }
  launcher="${SCRIPT_DIR}/${author}-coder.sh"
  [[ -f "${launcher}" ]] && { printf '%s' "${launcher}"; return 0; }
  printf ''
}

# Attempt one died-with-work or parked resume.  Returns 0 if a resume was launched and
# HANDLE was reassigned to the new run; 1 if no resume happened (every other
# case including kill-switch, not-eligible, marker present, gate refusal, or
# launch failure).  In all cases the decision is journaled via emit.
pc_dwr_resume_once() {
  local marker="${HANDOFF}/.dwr-resume-attempted"
  local prompt_file="${HANDOFF}/.dwr-resume-prompt.txt"
  local launch_log="${HANDOFF}/.dwr-resume-launch.log"

  # Kill switch.
  [[ "${LEADV2_PC_DWR_RESUME:-1}" == "1" ]] || return 1

  # Need author + handle.
  [[ -n "${AUTHOR:-}" && -n "${HANDLE:-}" ]] || return 1

  # Resolve the dead run's dir and read its outcome.
  local old_run_dir old_outcome
  old_run_dir="$(_pc_run_dir_for "${AUTHOR}" "${HANDLE}")"
  [[ -n "${old_run_dir}" && -f "${old_run_dir}/meta.yaml" ]] || return 1
  old_outcome="$(_pc_lane_outcome "${old_run_dir}")"
  case "${old_outcome}" in died-with-work|parked) ;; *) return 1 ;; esac

  # Marker short-circuit: exactly once per lane.
  if [[ -f "${marker}" ]]; then
    local from_run
    from_run="$(sed -n 's/^from_run=//p' "${marker}" 2>/dev/null | head -n 1)"
    emit decision "dwr_resume task=${TASK} from_run=${from_run:-${HANDLE}} new_run=skipped reason=already_attempted"
    return 1
  fi

  # Launcher must exist before we write the marker (so authors without a coder
  # script are a pure no-op with no journal noise).
  local launcher
  launcher="$(_pc_resume_launcher_for "${AUTHOR}")"
  if [[ -z "${launcher}" ]]; then
    emit decision "dwr_resume task=${TASK} from_run=${HANDLE} new_run=launch_failed reason=no_launcher"
    return 1
  fi

  # Read cwd / max_turns / timeout from the dead run's meta.
  local old_meta="${old_run_dir}/meta.yaml" cwd max_turns timeout_s
  cwd="$(_pc_meta_value "${old_meta}" cwd)"
  max_turns="$(_pc_meta_value "${old_meta}" max_turns)"
  timeout_s="$(_pc_meta_value "${old_meta}" timeout)"
  if [[ -z "${cwd}" || ! -d "${cwd}" ]]; then
    emit decision "dwr_resume task=${TASK} from_run=${HANDLE} new_run=launch_failed reason=no_cwd"
    return 1
  fi

  # Build the resume prompt: a 4-line prefix + the verbatim original prompt.
  local old_prompt="${old_run_dir}/prompt.txt"
  if [[ ! -s "${old_prompt}" ]]; then
    emit decision "dwr_resume task=${TASK} from_run=${HANDLE} new_run=launch_failed reason=no_prompt"
    return 1
  fi
  {
    printf '## Resume after a prior partial run\n'
    printf 'A previous run on this worktree died mid-work (stall/turn-cap/wall-clock) after producing real output. '
    printf 'Your changes so far are already on disk in this worktree. Review what is present, then continue the mission to completion.\n'
    printf 'Do NOT redo work that is already done; pick up where the prior run left off.\n'
    printf -- '---\n\n'
    cat "${old_prompt}"
  } > "${prompt_file}"

  # Write the marker BEFORE launching (R1: fail-closed, never loop).
  # On marker-write failure, do not launch.
  local marker_tmp="${marker}.tmp.$$"
  if ! printf 'from_run=%s\nat=%s\nby=%s\n' "${HANDLE}" "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" "$$" \
       > "${marker_tmp}" 2>/dev/null; then
    rm -f "${marker_tmp}" 2>/dev/null || true
    emit decision "dwr_resume task=${TASK} from_run=${HANDLE} new_run=launch_failed reason=marker_write"
    return 1
  fi
  mv -f "${marker_tmp}" "${marker}" 2>/dev/null || { rm -f "${marker_tmp}" 2>/dev/null || true; \
    emit decision "dwr_resume task=${TASK} from_run=${HANDLE} new_run=launch_failed reason=marker_write"; return 1; }

  # Launch the provider's `bg` entrypoint with the resume prompt.
  # `|| rc=$?` (never `!`) so gate codes (1|2) survive — same idiom as glm-coder.sh:1349.
  local rc=0 new_run_id=""
  bash "${launcher}" bg "@${prompt_file}" --cwd "${cwd}" \
       --max-turns "${max_turns:-50}" --timeout "${timeout_s:-3600}" \
       > "${launch_log}" 2>&1 || rc=$?

  if [[ ${rc} -eq 0 ]]; then
    # Parse the run-id from the last stdout line.
    new_run_id="$(tail -n 1 "${launch_log}" 2>/dev/null)"
    if [[ "${new_run_id}" =~ ^[0-9]{6}-[0-9]{6}- ]]; then
      emit decision "dwr_resume task=${TASK} from_run=${HANDLE} new_run=${new_run_id}"
      HANDLE="${new_run_id}"
      _pc_resolve_asked_into_void
      return 0
    else
      emit decision "dwr_resume task=${TASK} from_run=${HANDLE} new_run=launch_failed rc=0 reason=no_run_id"
      return 1
    fi
  elif [[ ${rc} -eq 1 || ${rc} -eq 2 ]]; then
    emit decision "dwr_resume task=${TASK} from_run=${HANDLE} new_run=blocked_by_gate rc=${rc}"
    return 1
  else
    emit decision "dwr_resume task=${TASK} from_run=${HANDLE} new_run=launch_failed rc=${rc} reason=bad_rc"
    return 1
  fi
}

_pc_job_registry_has_handle() { # <handle> -> 0 while the exact launch handle is registered
  local handle="$1" entry
  [[ -n "${handle}" && "${handle}" == "$(basename "${handle}")" ]] || return 1
  for entry in "${_PC_JOB_REGISTRY_ROOT%/}"/*/"${handle}"; do
    [[ -f "${entry}" ]] && return 0
  done
  return 1
}

_pc_meta_value() { # <meta.yaml> <key>
  sed -n "s/^$2:[[:space:]]*//p" "$1" 2>/dev/null | head -n 1
}

_pc_codex_provider_state() { # running|done|unknown
  local liveness_bin="${LEADV2_LANE_LIVENESS_BIN:-${SCRIPT_DIR}/leadv2-lane-liveness.sh}"
  local probe_timeout="${_PC_WORKER_PROBE_TIMEOUT_S:-20}"
  [[ -f "${liveness_bin}" ]] || { printf 'unknown'; return; }
  [[ "${probe_timeout}" =~ ^[1-9][0-9]*$ ]] || probe_timeout=20
  CODEX_TASK_SH="${LEADV2_DISPATCH_CODEX_BIN:-${SCRIPT_DIR}/codex-task.sh}" \
    python3 - "${liveness_bin}" "${ROOT}" "${HANDLE}" "${probe_timeout}" 2>/dev/null <<'PY'
import json
import os
import subprocess
import sys

try:
    result = subprocess.run(
        ["bash", sys.argv[1], "--project-root", sys.argv[2], "--job", sys.argv[3], "--json"],
        capture_output=True,
        check=False,
        env=os.environ.copy(),
        text=True,
        timeout=float(sys.argv[4]),
    )
    payload = json.loads(result.stdout)
    jobs = payload.get("jobs") or []
    verdict = str((jobs[0].get("verdict") if jobs else payload.get("verdict")) or "unknown").lower()
    if verdict in ("running", "queued") or verdict.startswith("alive") or verdict.startswith("starting:"):
        print("running")
    elif verdict in ("done", "completed", "failed", "cancelled") or verdict.startswith("dead:"):
        print("done")
    else:
        print("unknown")
except Exception:
    # A failed or wedged status probe is not permission to emit a terminal row.
    print("unknown")
PY
}

# CODEX-QUOTA-LOCKOUT-NEVER-FIRES-FOR-CODEX-01: relaxes _pc_arm_advance's reachability
# (previously reachable ONLY from pc_silent_arm_probe's silent-arm branch, further down
# this file) -- a quota-shaped failed status is exactly as much "this arm produced
# nothing and the chain must advance" as a silent lane is, so it calls _pc_arm_advance
# directly. Idempotent: leadv2-dispatch-code.sh's record-quota-lockout is best-effort/
# rc0-always and _record_quota_lockout's own write is last-write-wins per provider, so a
# duplicate call here (e.g. this close gate re-polling the same failed status) is
# harmless; _pc_arm_advance's own per-arm marker file already prevents a double-advance.
_pc_maybe_quota_advance() {  # <arm> <handle>
  local arm="$1" handle="$2"
  [[ -n "${arm}" && -n "${handle}" && -f "${DISPATCH_BIN}" ]] || return 0
  local lockout_dir="${LEADV2_QUOTA_LOCKOUT_DIR:-${LEADV2_DISPATCH_CACHE_DIR:-${HOME}/.claude/cache}/dispatch-ledger}"
  local before after
  before="$(ls -1 "${lockout_dir}"/quota-lockout-*.json 2>/dev/null | while IFS= read -r _f; do _pc_stat_mtime "${_f}" 2>/dev/null; printf ' %s\n' "${_f}"; done)"
  bash "${DISPATCH_BIN}" record-quota-lockout --arm "${arm}" --handle "${handle}" --sig8 "${TASK}" >/dev/null 2>&1 || true
  after="$(ls -1 "${lockout_dir}"/quota-lockout-*.json 2>/dev/null | while IFS= read -r _f; do _pc_stat_mtime "${_f}" 2>/dev/null; printf ' %s\n' "${_f}"; done)"
  [[ "${before}" != "${after}" ]] || return 0
  emit decision "arm_quota_failed task=${TASK} arm=${arm} handle=${handle}"
  _pc_arm_advance
}

# PLUGIN-RELIABILITY-01 D1 (round 2): pid-file-only process liveness.
# The pid in meta.yaml may be stale (the glm-coder.sh start process that wrote
# status=complete, while its __supervise parent still holds the GLM lock).
# This helper checks exact pids from the spawn record files:
#   1. meta.yaml pid (the start process)
#   2. run_dir/pgid   (the __run_child process)
#   3. lock_dir/pid    (the __supervise process)
#   4. lock_dir/pgid   (also __run_child, from the lock perspective)
# NEVER uses pgrep -f "$handle" — the close gate's own argv contains the handle
# string, so a substring pgrep self-matches and always reports alive (round 1
# Critical bug). The lock_dir is derived from the run_dir's .lockref (repo_hash):
#   lock_dir = <runs_dir>/.lock-<repo_hash>
# Self ($$) and parent ($PPID) are always excluded.
_pc_process_alive() { # <run_dir> [meta_pid] -> 0 if any live process found
  local run_dir="$1" meta_pid="${2:-}" _pid _runs_dir _repo_hash _lock_dir
  local -A _skip=( ["$$"]=1 ["$PPID"]=1 )
  # 1. meta pid
  if [[ "${meta_pid}" =~ ^[0-9]+$ && -z "${_skip[${meta_pid}]:-}" ]]; then
    kill -0 "${meta_pid}" 2>/dev/null && return 0
  fi
  # 2. child pid from run_dir/pgid
  if [[ -f "${run_dir}/pgid" ]]; then
    _pid="$(cat "${run_dir}/pgid" 2>/dev/null || true)"
    if [[ "${_pid}" =~ ^[0-9]+$ && -z "${_skip[${_pid}]:-}" ]]; then
      kill -0 "${_pid}" 2>/dev/null && return 0
    fi
  fi
  # 3. supervisor + child pids from lock dir
  _runs_dir="$(dirname "${run_dir}")"
  _repo_hash="$(cat "${run_dir}/.lockref" 2>/dev/null || true)"
  if [[ -n "${_repo_hash}" ]]; then
    _lock_dir="${_runs_dir}/.lock-${_repo_hash}"
    local _lf
    for _lf in pid pgid; do
      [[ -f "${_lock_dir}/${_lf}" ]] || continue
      _pid="$(cat "${_lock_dir}/${_lf}" 2>/dev/null || true)"
      if [[ "${_pid}" =~ ^[0-9]+$ && -z "${_skip[${_pid}]:-}" ]]; then
        kill -0 "${_pid}" 2>/dev/null && return 0
      fi
    done
  fi
  return 1
}

# PLUGIN-RELIABILITY-01 D1 (round 2): reap a worker's processes before
# terminal=dead. Only kills exact pids from the spawn record files — same
# sources as _pc_process_alive. NEVER uses pgrep -f "$handle" (round 1 Critical:
# that self-matched the close gate's own pid and SIGKILLed it before it could
# write review-gate.md or the terminal ledger row, and could kill unrelated
# processes like a tail -f on the handle's log). Self/parent always excluded.
_pc_reap_worker() { # <run_dir> [meta_pid]
  local run_dir="$1" meta_pid="${2:-}" _pid _killed=""
  local -A _skip=( ["$$"]=1 ["$PPID"]=1 )
  local -a _bare_pids=()   # pids signalled as bare pids (meta_pid, lock_dir/pid)
  local -a _grp_pids=()    # process-group ids signalled with negative sign (pgid files)
  local -A _seen=()
  # Collect + dedup live pids from spawn-record files
  # meta_pid is a bare pid (the coder child)
  if [[ "${meta_pid}" =~ ^[0-9]+$ && -z "${_skip[${meta_pid}]:-}" && -z "${_seen[${meta_pid}]:-}" ]]; then
    kill -0 "${meta_pid}" 2>/dev/null && { _bare_pids+=("${meta_pid}"); _seen[${meta_pid}]=1; }
  fi
  # run_dir/pgid is a setsid process-GROUP id — signal as group
  if [[ -f "${run_dir}/pgid" ]]; then
    _pid="$(cat "${run_dir}/pgid" 2>/dev/null || true)"
    if [[ "${_pid}" =~ ^[0-9]+$ && -z "${_skip[${_pid}]:-}" && -z "${_seen[${_pid}]:-}" ]]; then
      kill -0 "${_pid}" 2>/dev/null && { _grp_pids+=("${_pid}"); _seen[${_pid}]=1; }
    fi
  fi
  local _runs_dir _repo_hash _lock_dir _lf
  _runs_dir="$(dirname "${run_dir}")"
  _repo_hash="$(cat "${run_dir}/.lockref" 2>/dev/null || true)"
  if [[ -n "${_repo_hash}" ]]; then
    _lock_dir="${_runs_dir}/.lock-${_repo_hash}"
    for _lf in pid pgid; do
      [[ -f "${_lock_dir}/${_lf}" ]] || continue
      _pid="$(cat "${_lock_dir}/${_lf}" 2>/dev/null || true)"
      if [[ "${_pid}" =~ ^[0-9]+$ && -z "${_skip[${_pid}]:-}" && -z "${_seen[${_pid}]:-}" ]]; then
        kill -0 "${_pid}" 2>/dev/null && {
          if [[ "${_lf}" == pgid ]]; then
            _grp_pids+=("${_pid}")
          else
            _bare_pids+=("${_pid}")
          fi
          _seen[${_pid}]=1
        }
      fi
    done
  fi
  [[ ${#_bare_pids[@]} -eq 0 && ${#_grp_pids[@]} -eq 0 ]] && return 0
  # SIGTERM — groups signalled as groups (negative pid), bare pids as-is
  for _pid in "${_bare_pids[@]}"; do kill -TERM "${_pid}" 2>/dev/null || true; done
  for _pid in "${_grp_pids[@]}";  do kill -TERM -"${_pid}" 2>/dev/null || true; done
  # Wait up to 5s for them to die
  local _w=0
  while (( _w < 10 )); do
    _killed=""
    for _pid in "${_bare_pids[@]}"; do kill -0 "${_pid}" 2>/dev/null && _killed=1; done
    for _pid in "${_grp_pids[@]}";  do kill -0 "${_pid}" 2>/dev/null && _killed=1; done
    [[ -z "${_killed}" ]] && return 0
    sleep 0.5
    _w=$(( _w + 1 ))
  done
  # SIGKILL stragglers
  for _pid in "${_bare_pids[@]}"; do kill -KILL "${_pid}" 2>/dev/null || true; done
  for _pid in "${_grp_pids[@]}";  do kill -KILL -"${_pid}" 2>/dev/null || true; done
  local _all_pids="${_bare_pids[*]:-}${_grp_pids[*]:+ ${_grp_pids[*]}}"
  emit decision "product_close task=${TASK:-} worker_reaped pids=$(IFS=,; printf '%s' "${_all_pids}")"
}

pc_worker_alive() { # 0 = keep watching; 1 = worker is provably finished
  local provider_state registry_alive run_dir meta status pid
  if [[ -z "${HANDLE}" ]]; then
    emit decision "product_close task=${TASK} worker_liveness=unknown author=${AUTHOR:-unknown} handle=- action=proceed_legacy"
    return 1
  fi
  case "${AUTHOR}" in
    sonnet)
      if [[ "${HANDLE}" =~ ^[0-9]+$ ]]; then
        kill -0 "${HANDLE}" 2>/dev/null && return 0
        return 1
      fi
      ;;
    codex)
      provider_state="$(_pc_codex_provider_state)"
      registry_alive=0
      _pc_job_registry_has_handle "${HANDLE}" && registry_alive=1
      [[ "${provider_state}" == running || "${registry_alive}" == 1 ]] && return 0
      [[ "${provider_state}" == "done" && "${registry_alive}" == 0 ]] && return 1
      # Unknown provider state is conservative: the hard ceiling owns recovery.
      return 0
      ;;
    glm|kimi)
      if [[ "${AUTHOR}" == glm ]]; then
        run_dir="${GLM_RUNS_DIR:-${_PC_RUNS_ROOT}/glm-runs}/${HANDLE}"
      else
        run_dir="${KIMI_RUNS_DIR:-${_PC_RUNS_ROOT}/kimi-runs}/${HANDLE}"
      fi
      meta="${run_dir}/meta.yaml"
      status="$(_pc_meta_value "${meta}" status)"
      # PLUGIN-RELIABILITY-01 D4: malformed/truncated meta.yaml — empty status
      # with a gone pid means the run is dead, not keep-waiting for 4200s.
      # One grace re-read already happened via the poll loop; treat it as dead.
      pid="$(_pc_meta_value "${meta}" pid)"
      # GLM/Kimi stall revival finalizes the ORIGINAL run with one of these
      # statuses, then returns before clearing its original registry entry. They
      # are therefore terminal evidence for this handle even while that stale
      # registry file remains; treating the registry as live here would run the
      # full ceiling and write a permanent dead/timeout row for completed work.
      [[ "${status}" == revived || "${status}" == revive_blocked_by_gate ]] && return 1
      registry_alive=0
      _pc_job_registry_has_handle "${HANDLE}" && registry_alive=1
      [[ "${status}" == running || "${registry_alive}" == 1 ]] && return 0
      # PLUGIN-RELIABILITY-01 D1 (round 2): pid-file-based liveness check.
      # The pid in meta.yaml may be the coder child (already exited) while the
      # parent __supervise process still holds the GLM lock. _pc_process_alive
      # checks exact pids from the spawn record (meta, pgid, lock_dir).
      _pc_process_alive "${run_dir}" "${pid}" && return 0
      # CODEX-QUOTA-LOCKOUT-NEVER-FIRES-FOR-CODEX-01 (close-gate out-of-window path):
      # this close gate is discovering status==failed possibly long after
      # leadv2-dispatch-code.sh's own in-process post-spawn verdict window
      # (_wait_arm_early_verdict) already expired -- classify it here too, so a late
      # quota death still gets a lockout AND advances the chain instead of sitting dead.
      [[ "${status}" == failed && "${registry_alive}" == 0 ]] && _pc_maybe_quota_advance "${AUTHOR}" "${HANDLE}"
      # PLUGIN-RELIABILITY-01 D1 (round 2): before declaring terminal=dead,
      # reap any straggler processes so the GLM lock is released for the next lane.
      if [[ ( "${status}" == complete || "${status}" == failed ) && "${registry_alive}" == 0 ]]; then
        _pc_reap_worker "${run_dir}" "${pid}"
        return 1
      fi
      # The coder writes this only from its finish guard. It is terminal provider
      # evidence for legacy runs that predate meta.yaml, once no exact registry or
      # process evidence remains. PLUGIN-RELIABILITY-02: this must run BEFORE the
      # empty-status grace guard so legacy terminal evidence still wins.
      [[ -n "${_PC_ASKED_INTO_VOID:-}" && -f "${_PC_ASKED_INTO_VOID}" && "${registry_alive}" == 0 ]] && return 1
      # PLUGIN-RELIABILITY-01 D4 (round 2): pid gone + empty/unparseable status
      # = dead, not keep-waiting (which caused 4200s false waits). Grace guard:
      # meta.yaml must exist and be older than 30s — a just-spawned worker that
      # hasn't written meta yet (or wrote a truncated initial copy) must not be
      # declared dead on the first poll.
      if [[ -z "${status}" && "${registry_alive}" == 0 ]]; then
        if [[ ! -f "${meta}" ]]; then
          # meta.yaml doesn't exist yet — the worker may have just spawned.
          # Give it time to write meta before declaring dead.
          return 0
        fi
        local _meta_age_s=0
        local _now_s _meta_mtime_s
        _now_s="$(date +%s)"
        _meta_mtime_s="$(stat -f %m "${meta}" 2>/dev/null || stat -c %Y "${meta}" 2>/dev/null || echo 0)"
        _meta_age_s=$(( _now_s - _meta_mtime_s ))
        if (( _meta_age_s < 30 )); then
          return 0
        fi
        emit decision "product_close task=${TASK} worker_liveness=dead author=${AUTHOR} handle=${HANDLE} reason=empty_status_pid_gone meta_age_s=${_meta_age_s}"
        return 1
      fi
      # Missing/malformed provider evidence is never treated as completion.
      return 0
      ;;
  esac

  # Direct/manual legacy invocations can omit a handle. Preserve their historical
  # immediate behavior, but make the relaxed proof visible instead of silently guessing.
  emit decision "product_close task=${TASK} worker_liveness=unknown author=${AUTHOR:-unknown} handle=${HANDLE:--} action=proceed_legacy"
  return 1
}

_pc_refresh_founder_lease() { # <extend_seconds> -> best-effort, only for our live claim
  local extend_s="$1" task_yaml expires
  [[ -n "${FOUNDER_TASK_ID}" && -f "${ROOT}/docs/tasks.yaml" ]] || return 0
  declare -F leadv2_tasks_by_id >/dev/null 2>&1 || return 0
  declare -F leadv2_tasks_update >/dev/null 2>&1 || return 0
  task_yaml="$(leadv2_tasks_by_id "${FOUNDER_TASK_ID}" 2>/dev/null)" || return 0
  # Never resurrect or alter a task that another lifecycle owner already
  # completed/unclaimed while this close watcher was alive.
  printf '%s' "${task_yaml}" | python3 -c '
import sys, yaml
items = yaml.safe_load(sys.stdin.read()) or []
item = items[0] if isinstance(items, list) and items else {}
claim = item.get("claim") or {}
sys.exit(0 if item.get("status") == "in_progress" and claim.get("by") is not None else 1)
' >/dev/null 2>&1 || return 0
  expires="$(python3 - "${extend_s}" 2>/dev/null <<'PY'
import datetime
import sys

now = datetime.datetime.now(datetime.timezone.utc)
expires = now + datetime.timedelta(seconds=int(sys.argv[1]))
print(expires.strftime("%Y-%m-%dT%H:%M:%SZ"))
PY
)"
  [[ -n "${expires}" ]] || return 0
  leadv2_tasks_update "${FOUNDER_TASK_ID}" --key "claim.lease_expires" --value "${expires}" >/dev/null 2>&1 || true
}

# QUESTION-DELIVERY-OWNERSHIP-01 — scan the control-plane questions/ dir for
# pending questions whose task_id (or owner_task) matches THIS lane's TASK,
# and emit a `question_pending` decision line per unanswered qid. This reaches
# the lead session's existing watchers/journal without any new daemon — it
# piggybacks on pc_await_worker_exit's existing poll loop. Tolerates old rows
# without owner fields (matches on task_id only). Never blocks or fails the
# close gate on a question-dir error (fail-open: emit nothing, return 0).
_pc_emit_pending_questions() {
  local qdir
  qdir="$(PROJECT_ROOT="${ROOT}" bash "${STATE_PATH_BIN}" questions 2>/dev/null || true)"
  [[ -n "$qdir" && -d "$qdir" ]] || return 0
  local _qlines _ql
  _qlines="$(LEADV2_PC_QDIR="$qdir" LEADV2_PC_TASK="$TASK" python3 2>/dev/null <<'PYEOF' || true
import glob, os, sys, datetime, yaml
qdir = os.environ.get("LEADV2_PC_QDIR", "")
task = os.environ.get("LEADV2_PC_TASK", "")
if not qdir or not task:
    sys.exit(0)
now = datetime.datetime.utcnow()
for fp in sorted(glob.glob(os.path.join(qdir, "*.yaml"))):
    try:
        with open(fp, encoding="utf-8") as f:
            d = yaml.safe_load(f) or {}
    except Exception:
        continue
    if d.get("status") != "pending":
        continue
    q_task = d.get("task_id") or d.get("owner_task") or ""
    if q_task != task:
        continue
    qid = d.get("qid", os.path.basename(fp).replace(".yaml", ""))
    asked = d.get("asked_at", "") or ""
    age_s = "?"
    try:
        dt = datetime.datetime.strptime(asked, "%Y-%m-%dT%H:%M:%SZ")
        age_s = str(int((now - dt).total_seconds()))
    except Exception:
        pass
    print("question_pending task=%s qid=%s age=%s" % (task, qid, age_s))
PYEOF
  )"
  while IFS= read -r _ql; do
    [[ -n "$_ql" ]] && emit decision "$_ql"
  done <<< "$_qlines"
}

pc_await_worker_exit() {
  if [[ "${LEADV2_PC_AWAIT_WORKER:-1}" != 1 ]]; then
    # One-flip rollback is byte-for-byte equivalent to the former Sonnet-only wait.
    if [[ "${AUTHOR}" == sonnet && "${HANDLE}" =~ ^[0-9]+$ ]]; then
      while kill -0 "${HANDLE}" 2>/dev/null; do sleep 2; done
    fi
    return 0
  fi

  local poll_s="${LEADV2_PC_WORKER_POLL_S:-10}"
  local max_wait_s="${LEADV2_PC_WORKER_MAX_WAIT_S:-4200}"
  local log_every_s="${LEADV2_PC_WORKER_LOG_EVERY_S:-300}"
  local lease_refresh_s="${LEADV2_PC_LEASE_REFRESH_EVERY_S:-300}"
  [[ "${poll_s}" =~ ^[1-9][0-9]*$ ]] || poll_s=10
  [[ "${max_wait_s}" =~ ^[1-9][0-9]*$ ]] || max_wait_s=4200
  [[ "${log_every_s}" =~ ^[0-9]+$ ]] || log_every_s=300
  [[ "${lease_refresh_s}" =~ ^[1-9][0-9]*$ ]] || lease_refresh_s=300

  local started now last_log=0 last_lease_refresh=0 remaining sleep_s
  local lease_extend_s=$(( max_wait_s + poll_s + 20 ))
  started="$(date +%s)"
  while true; do
    now="$(date +%s)"
    _PC_WORKER_WAITED_S=$(( now - started ))
    if [[ "${_PC_WORKER_WAITED_S}" -ge "${max_wait_s}" ]]; then
      return 1
    fi
    # Bound the potentially-slow Codex probe by the watcher's remaining wall
    # clock budget. Without this, a final 20s probe plus a full poll sleep could
    # overshoot a tightened ceiling by roughly 30 seconds.
    remaining=$(( max_wait_s - _PC_WORKER_WAITED_S ))
    _PC_WORKER_PROBE_TIMEOUT_S=20
    [[ "${remaining}" -lt "${_PC_WORKER_PROBE_TIMEOUT_S}" ]] && _PC_WORKER_PROBE_TIMEOUT_S="${remaining}"
    if ! pc_worker_alive; then
      now="$(date +%s)"
      _PC_WORKER_WAITED_S=$(( now - started ))
      return 0
    fi
    now="$(date +%s)"
    _PC_WORKER_WAITED_S=$(( now - started ))
    if [[ "${_PC_WORKER_WAITED_S}" -ge "${max_wait_s}" ]]; then
      return 1
    fi
    if [[ "${last_lease_refresh}" -eq 0 || $(( now - last_lease_refresh )) -ge "${lease_refresh_s}" ]]; then
      _pc_refresh_founder_lease "${lease_extend_s}"
      last_lease_refresh="${now}"
    fi
    if [[ "${last_log}" -eq 0 || $(( now - last_log )) -ge "${log_every_s}" ]]; then
      emit decision "product_close task=${TASK} status=waiting_worker author=${AUTHOR} handle=${HANDLE} waited=${_PC_WORKER_WAITED_S}s"
      # QUESTION-DELIVERY-OWNERSHIP-01: push-deliver unanswered questions
      # belonging to THIS task so the lead session's watchers/journal see them
      # without any founder input. Runs at the same log-interval — no new
      # daemon, piggybacks on the existing 10s poll.
      _pc_emit_pending_questions
      last_log="${now}"
    fi
    remaining=$(( max_wait_s - _PC_WORKER_WAITED_S ))
    sleep_s="${poll_s}"
    [[ "${remaining}" -lt "${sleep_s}" ]] && sleep_s="${remaining}"
    sleep "${sleep_s}"
  done
}

# N1-EMPTY-LANE-IS-NOT-A-PASS: the lane's diff is scoped ONCE, here, BEFORE the
# e2e gate stamps its passed sentinel -- so a lane that wrote nothing exits as
# no_work before e2e-gate-passed.flag can ever be created. The review gate below
# consumes the already-computed ${diff_file} / ${_pc_base_used}; the dedup block
# after it reuses ${diff_file} (global -- no `local` on the diff vars) too.

# GATE-LANE-DIFF-ONLY-WHEN-CROSS-REPO-01: distinguishes "the lane genuinely did nothing"
# from "the lane did something the diff-scoping above failed to capture". rc0 iff <root> is
# a git work tree with >=1 uncommitted tracked change or untracked file, after excluding
# docs/leadv2/ and docs/handoff/ -- the SAME exclusion set _pc_git_diff uses, so a lane
# whose only churn is its own handoff artifacts does not flip from no_work to a false
# rescue. Read-only: never touches the index or working tree (unlike _pc_git_diff's
# throwaway-index `add -N`, which is unnecessary here since porcelain already reports
# untracked paths). Tolerates quoted porcelain paths (paths with spaces/special chars).
# SCOPE-GATE-ORCHESTRATION-DIRT-01: ONE definition of the porcelain exclusion set.
# It used to be copy-pasted at both porcelain sites, and on 2026-08-21 only one copy
# got widened -- the gate kept refusing lanes because _pc_lane_dirty still saw the
# dirt the partition below had learned to ignore. A single constant is the only way
# the two sites cannot drift apart again.
#
# Beyond docs/leadv2/ + docs/handoff/, three paths are written by machinery no worker
# touches: docs/LEAD_V2_STATE.md (five plugin scripts write it), docs/tasks.yaml (the
# per-turn injector hooks dirty it inside every lane worktree regardless of what the
# lane's mission targets -- T13-SLICE1 W1: two cross-repo lanes, 5774f464 and c4c26759,
# were refused unscoped_lane_work with offending=docs/tasks.yaml even though their real
# work landed as commits in a foreign repo; docs/tasks.yaml was dirty ONLY because the
# hook touches it on every turn, never because either lane wrote to it), and
# __pycache__/*.pyc (Python bytecode; on branches predating the untrack it appears as a
# MODIFIED tracked file). All three refused finished deliverables -- list-form on the
# pyc plus LEAD_V2_STATE.md on 2026-08-21, docs/tasks.yaml on 2026-08-26.
#
# NOT applied to _pc_git_diff's ':(exclude)' pathspecs: that set governs what a
# REVIEWER sees, which is a separate decision from what counts as a scope violation.
_PC_PORCELAIN_EXCLUDE_RE='^.. "?docs/leadv2/|^.. "?docs/handoff/|^.. "?docs/LEAD_V2_STATE\.md|^.. "?docs/tasks\.yaml|^.. "?.*__pycache__/|^.. "?.*\.pyc$'

# CTX-COST-GUARDS-01: the plugin's own worktree bootstrap
# (hooks/leadv2-command-bootstrap.sh, scripts/leadv2-repo-install.sh) symlinks
# .claude/commands|scripts|agents/ into every fresh lane worktree. That dirt is not a
# worker's doing, but a regex alone cannot say "only if it is a symlink" -- grep sees
# porcelain TEXT, not the filesystem -- so widening _PC_PORCELAIN_EXCLUDE_RE would also
# swallow a REAL file a worker writes under the same prefix. Two stages instead: the
# regex above narrows to orchestration-owned literal paths; _pc_drop_bootstrap_dirt
# below narrows further to bootstrap dirt specifically, via a filesystem predicate the
# regex stage cannot express.
_PC_BOOTSTRAP_PREFIX_RE='^\.claude/(commands|scripts|agents)/'

# _pc_drop_bootstrap_dirt <lane-root> ; stdin=porcelain (post _PC_PORCELAIN_EXCLUDE_RE),
# stdout=survivors. Drops a line only when ALL THREE hold -- dropping any one reintroduces
# overreach:
#   1. status field is exactly `??` (untracked) -- a tracked-modified line under the same
#      prefix is a worker who edited a real plugin file, never dropped.
#   2. path matches _PC_BOOTSTRAP_PREFIX_RE.
#   3. the path IS a symlink on disk ([ -L ], true even for a dangling link -- a lane
#      whose canonical checkout moved is still plugin dirt, not worker dirt). A real
#      regular file a worker wrote under the same prefix fails this and survives.
# Fails open: an unreadable/missing root passes every line through unfiltered, and the
# function itself always returns 0 -- a non-zero tail in a `$( ... | _pc_drop_bootstrap_dirt )`
# pipeline under `set -o pipefail` would otherwise blank the whole status and grade every
# lane clean.
_pc_drop_bootstrap_dirt() {  # <lane-root> ; filters stdin porcelain -> stdout
  local root="$1" line field rest path
  if [[ -z "${root}" || ! -d "${root}" ]]; then
    cat
    return 0
  fi
  while IFS= read -r line; do
    [[ -z "${line}" ]] && continue
    field="${line:0:2}"
    rest="${line:3}"
    if [[ "${field}" == "??" && "${rest}" =~ ${_PC_BOOTSTRAP_PREFIX_RE} ]]; then
      path="${rest##* -> }"
      path="${path%\"}"; path="${path#\"}"
      if [[ -L "${root}/${path}" ]]; then
        continue
      fi
    fi
    printf '%s\n' "${line}"
  done
  return 0
}

_pc_lane_dirty() {  # <root> -> rc0 if dirty (excluding orchestration-owned paths), rc1 otherwise
  local root="$1"
  [[ -n "${root}" && -d "${root}" ]] || return 1
  git -C "${root}" rev-parse --is-inside-work-tree >/dev/null 2>&1 || return 1
  local status
  status="$(git -C "${root}" status --porcelain --untracked-files=all 2>/dev/null | \
    grep -vE "${_PC_PORCELAIN_EXCLUDE_RE}" | _pc_drop_bootstrap_dirt "${root}")"
  [[ -n "${status}" ]]
}

# REVIEW-GATE-LANEROOT-01: `git -C <dir>` walks UP. A directory that is merely INSIDE
# the main checkout (an unregistered .claude/worktrees/<tid> left behind by a partial
# worktree removal) answers `rev-parse --is-inside-work-tree` with `true` and then
# reports the MAIN repository's status. Identity, not membership, is the question:
# the toplevel git resolves from <dir> must BE <dir>.
# Physical-path comparison avoids /var vs /private/var disagreement on macOS.
# Deliberately NOT folded into _pc_lane_dirty: pc_silent_arm_probe reads a failing
# dirty check as proof of silence, so both callers check identity explicitly instead.
_pc_phys() { ( cd -P "$1" 2>/dev/null && pwd -P ) ; }

_PC_LANE_TOPLEVEL=""          # set by the probe below; read by the evidence line
_pc_lane_root_is_own_worktree() {  # <root> -> rc0 iff <root> IS a git work tree root
  local root="$1" top
  _PC_LANE_TOPLEVEL=""
  [[ -n "${root}" && -d "${root}" ]] || return 1
  top="$(git -C "${root}" rev-parse --show-toplevel 2>/dev/null)" || return 1
  [[ -n "${top}" ]] || return 1
  _PC_LANE_TOPLEVEL="${top}"
  [[ "$(_pc_phys "${top}")" == "$(_pc_phys "${root}")" ]]
}

# GATE-FALSE-SILENT-01: a worker that COMMITS its work leaves the worktree clean --
# _pc_lane_dirty alone cannot tell "produced nothing" from "committed cleanly". Count
# commits ahead of the base pc_scope_diff resolves.
#
# CENSUS CORRECTION round 2 (why this duplicates _pc_diff_base instead of calling it):
# _pc_diff_base (below, top level, defined at column 0 -- NOT nested inside
# pc_scope_diff()'s body, contrary to what an earlier version of this comment claimed) is
# reached only via _pc_repo_diff() -> pc_scope_diff(), and pc_scope_diff() runs AFTER this
# probe (call site at pc_silent_arm_probe's caller precedes pc_scope_diff's). A call to
# _pc_diff_base from here would in fact resolve today -- the earlier "it doesn't exist yet"
# reasoning was wrong. The duplication is kept anyway because pc_scope_diff is off-limits
# this round and the two copies now have DELIBERATELY DIVERGENT failure semantics: this
# copy reports "unknown" when it cannot resolve a base (GATE-FALSE-SILENT-01 fix round 2 --
# see below), while _pc_diff_base still fails to empty/HEAD. Hoisting or merging them is
# out of scope; a future edit to base resolution must be applied to BOTH this function and
# _pc_diff_base or they will drift.
#
# round-2 fix: "0" is indistinguishable from "could not resolve a base at all" (unresolvable
# LEADV2_LANE_START_SHA, missing cache file, no origin/main) -- a lossy channel that let a
# lane which genuinely committed work read as arm_produced_nothing. Widen the channel:
# print "unknown" whenever no base could be resolved, and an integer ONLY when a base was
# actually resolved (including the genuine "0 commits ahead" case). rc is always 0 -- this
# probe must never abort the gate. The caller (pc_silent_arm_probe) treats "unknown" as
# NOT silent, matching the mandate that a probe which cannot tell must not conclude silence.
_pc_lane_commits_ahead() {  # <root> -> stdout "N" | "unknown"; always rc0
  local root="$1" base sha count
  if [[ -n "${root}" && -d "${root}" ]] && \
     git -C "${root}" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    base=""
    sha="${LEADV2_LANE_START_SHA:-}"
    if [[ -n "${sha}" ]] && git -C "${root}" cat-file -e "${sha}^{commit}" 2>/dev/null; then
      base="$(git -C "${root}" merge-base "${sha}" HEAD 2>/dev/null || true)"
    fi
    if [[ -z "${base}" ]]; then
      sha="$(cat "${CACHE_BASE}/dispatch-${TASK}.start-sha" 2>/dev/null || true)"
      if [[ -n "${sha}" ]] && git -C "${root}" cat-file -e "${sha}^{commit}" 2>/dev/null; then
        base="$(git -C "${root}" merge-base "${sha}" HEAD 2>/dev/null || true)"
      fi
    fi
    if [[ -z "${base}" ]] && git -C "${root}" cat-file -e "origin/main^{commit}" 2>/dev/null; then
      base="$(git -C "${root}" merge-base origin/main HEAD 2>/dev/null || true)"
    fi
    if [[ -n "${base}" ]]; then
      count="$(git -C "${root}" rev-list --count "${base}..HEAD" 2>/dev/null || true)"
      [[ "${count}" =~ ^[0-9]+$ ]] && { printf '%s' "${count}"; return 0; }
    fi
    # GATE-FALSE-SILENT-01 round 3: a base is not required to prove ZERO. A linked
    # worktree whose HEAD is the same commit as the repository it hangs off, and whose
    # HEAD reflog records no commit of its own, provably has no commits of its own --
    # "0", not "unknown". `${root}/.git` as a FILE is the linked-worktree test: a
    # standalone repo has a .git DIRECTORY. Deliberately NOT a path comparison of
    # --git-dir vs --git-common-dir -- on macOS TMPDIR is /var -> /private/var, so the
    # two strings differ for a standalone repo and prove-zero fires on lanes it must
    # never fire on (observed: test-dispatch-silent-arm Case 1 flipped to silent).
    local head_wt head_parent
    if [[ -f "${root}/.git" ]]; then
      head_wt="$(git -C "${root}" rev-parse HEAD 2>/dev/null || true)"
      head_parent="$(cd "${root}" 2>/dev/null && git --git-dir="$(git rev-parse --git-common-dir 2>/dev/null)" rev-parse HEAD 2>/dev/null || true)"
      if [[ -n "${head_wt}" && "${head_wt}" == "${head_parent}" ]] && \
         ! git -C "${root}" log -g --format=%gs HEAD 2>/dev/null | grep -q '^commit'; then
        printf '0'; return 0
      fi
    fi
  fi
  printf 'unknown'
}

# GATE-FALSE-SILENT-01: a worker whose process is still alive is never silent, whatever
# the stream/commit/dirty state says -- it just hasn't produced a terminal signal yet.
# Deliberately calls _pc_process_alive (pid-file-only liveness), NEVER pc_worker_alive --
# that function has side effects (quota-advance, reap, journal emissions) and treats
# unknown states as alive, which would invert this predicate's meaning. rc1 (not provably
# alive) on any missing/unresolvable input -- never manufactures a false "alive".
_pc_worker_process_alive() {  # -> rc0 iff a worker process for AUTHOR/HANDLE is provably alive
  [[ -n "${HANDLE:-}" ]] || return 1
  if [[ "${AUTHOR}" == "sonnet" && "${HANDLE}" =~ ^[0-9]+$ ]]; then
    kill -0 "${HANDLE}" 2>/dev/null && return 0
    return 1
  fi
  local run_dir meta_pid
  run_dir="$(_pc_run_dir_for "${AUTHOR}" "${HANDLE}")"
  [[ -n "${run_dir}" ]] || return 1
  meta_pid="$(_pc_meta_value "${run_dir}/meta.yaml" pid 2>/dev/null || true)"
  _pc_process_alive "${run_dir}" "${meta_pid}"
}

# ARM-PRODUCES-NOTHING-AND-CHAIN-NEVER-ADVANCES-01: bash-3.2-safe mtime probe (no
# portable `stat -f/-c` flag exists across darwin/linux) -- try darwin's `-f %m` first,
# fall back to linux's `-c %Y`. rc1 on ANY stat failure (missing file, permission,
# unknown stat dialect) -- callers fail OPEN (treat as "not proven stale") on rc1.
_pc_stat_mtime() {  # <file> -> stdout epoch mtime; rc1 on failure
  local f="$1" m
  m="$(stat -f %m "${f}" 2>/dev/null)" || m="$(stat -c %Y "${f}" 2>/dev/null)" || return 1
  [[ "${m}" =~ ^[0-9]+$ ]] || return 1
  printf '%s' "${m}"
}

# ARM-PRODUCES-NOTHING-AND-CHAIN-NEVER-ADVANCES-01: bash-3.2-safe CSV chain walk -- no
# associative arrays. `set --` over IFS=, split positional params, then a single linear
# scan for the element strictly AFTER <cur>. rc1 (empty stdout) whenever <cur> is the
# last element, absent from the chain, or the chain has 0/1 elements -- callers treat
# rc1 as "no next arm" (chain_exhausted), never a wrap-around to element 0.
_pc_next_arm_in_chain() {  # <chain_csv> <cur_arm> -> stdout next arm; rc1 if none
  local chain="$1" cur="$2" tok found=0
  [[ -n "${chain}" ]] || return 1
  local _oldifs="${IFS}"
  IFS=','
  set -- ${chain}
  IFS="${_oldifs}"
  for tok in "$@"; do
    tok="${tok#"${tok%%[![:space:]]*}"}"; tok="${tok%"${tok##*[![:space:]]}"}"
    [[ -z "${tok}" ]] && continue
    if [[ ${found} -eq 1 ]]; then
      printf '%s' "${tok}"
      return 0
    fi
    [[ "${tok}" == "${cur}" ]] && found=1
  done
  return 1
}

# ARM-PRODUCES-NOTHING-02: path to the arm-registration file written by the dispatcher at
# spawn time (see _dispatch_register_arm in leadv2-dispatch-code.sh).  Same handoff dir,
# same convention, trivially constructible in a test fixture.
_pc_arm_registered_file() {  # -> path on stdout
  if [[ -n "${LEADV2_DISPATCH_ARM_REGISTERED_FILE:-}" ]]; then
    printf '%s' "${LEADV2_DISPATCH_ARM_REGISTERED_FILE}"
  else
    printf '%s/arm-registered' "${HANDOFF}"
  fi
}

# ARM-PRODUCES-NOTHING-02: rc0 iff the registration file exists, is readable, is
# non-empty, AND contains a line whose first field is arm=<author> (exact token match,
# anchored — arm=sonnet never matches arm=sonnet-thinking).  Empty <author>: rc0 iff the
# file is non-empty.  rc1 on EVERY other outcome, including any read error — fail-closed
# to the pre-existing empty_diff path.
_pc_arm_registered() {  # <author> -> rc0 registered, rc1 not
  local author="$1" f line first_field
  f="$(_pc_arm_registered_file)"
  [[ -f "${f}" && -r "${f}" && -s "${f}" ]] || return 1
  [[ -z "${author}" ]] && return 0
  while IFS= read -r line || [[ -n "${line}" ]]; do
    first_field="${line%%[[:space:]]*}"
    [[ "${first_field}" == "arm=${author}" ]] && return 0
  done < "${f}" 2>/dev/null
  return 1
}

# ARM-PRODUCES-NOTHING-AND-CHAIN-NEVER-ADVANCES-01 (Fix 1): a lane that RAN (worker exited
# cleanly, no timeout) but never actually produced a single assistant turn is a distinct
# failure mode from an empty diff after real work -- the arm never engaged at all. rc0
# (silent) requires ALL THREE: (1) developer.stream.jsonl is missing or has zero
# `"type":"assistant"` events, (2) the stream is not fresh (mtime older than
# LEADV2_PC_SILENT_GROWTH_S, default 60s -- a worker that only just started writing is
# NOT silent, it is working), (3) the resolved lane worktree is clean (no _lane_root
# resolved at all is conservative NOT-silent, matching today's behaviour exactly for
# lanes without one). Any failure to prove silence fails OPEN (rc1, NOT silent) -- this
# predicate must never manufacture a false no_work verdict from a stat hiccup.
# Sets _PC_SILENT_STREAM_STATE (absent|no_assistant_events) and _PC_SILENT_LANE_BASENAME
# for the caller's evidence string; both are only meaningful when this returns rc0.
#
# ARM-PRODUCES-NOTHING-02: condition (0), the arm-registration gate, runs FIRST. The
# clean-lane / no-stream state is owned by TWO callers depending on whether an arm was
# ever registered for this lane: arm-registered => arm_produced_nothing (this probe +
# _pc_arm_advance); NOT arm-registered => empty_diff (the existing C3 path, untouched).
# The probe is now strictly narrower than on 3bffb24: it fires only when a registration
# file exists and names AUTHOR.
_PC_SILENT_STREAM_STATE=""
_PC_SILENT_LANE_BASENAME=""
_PC_SILENT_COMMITS_AHEAD=""
pc_silent_arm_probe() {
  # 0) ARM-PRODUCES-NOTHING-02: if no arm was ever registered for this lane, this is
  # NOT a silent arm — it is an empty lane that belongs to the existing empty_diff path.
  _pc_arm_registered "${AUTHOR}" || return 1
  local stream="${HANDOFF}/developer.stream.jsonl"
  local assistant_n=0
  _PC_SILENT_STREAM_STATE="absent"
  _PC_SILENT_LANE_BASENAME=""
  if [[ -f "${stream}" ]]; then
    _PC_SILENT_STREAM_STATE="no_assistant_events"
    assistant_n="$(grep -c '"type":"assistant"' "${stream}" 2>/dev/null || printf '0')"
    [[ "${assistant_n}" =~ ^[0-9]+$ ]] || assistant_n=0
  fi
  # 1) >=1 assistant event -- NOT silent, done.
  [[ ${assistant_n} -ge 1 ]] && return 1
  # 2/3) GATE-FALSE-SILENT-01 round 3: an absent stream is not evidence OF silence, but
  # it is also not a VETO -- a glm/codex arm structurally never writes
  # developer.stream.jsonl, so round 1's blanket "no stream -> not silent" veto made
  # arm_produced_nothing unreachable for every non-sonnet arm. Only run the freshness
  # guard when a stream actually exists; an absent stream falls through to steps 4-6
  # below (worker-alive / dirty / commits-ahead), which own "too early to tell" for a
  # lane with no stream convention at all.
  local growth_s="${LEADV2_PC_SILENT_GROWTH_S:-60}" mtime now
  if [[ -f "${stream}" ]]; then
    # growth guard -- clamp to [1, 3600] so a misconfigured env var cannot make
    # arm_produced_nothing permanently unreachable (over-cap) or fire on a stream that
    # was just written (under-cap of 0).
    [[ "${growth_s}" =~ ^[0-9]+$ ]] || growth_s=60
    if (( growth_s < 1 )); then
      emit decision "silent_probe_growth_clamped task=${TASK} requested=${growth_s} used=1"
      growth_s=1
    elif (( growth_s > 3600 )); then
      emit decision "silent_probe_growth_clamped task=${TASK} requested=${growth_s} used=3600"
      growth_s=3600
    fi
    if mtime="$(_pc_stat_mtime "${stream}")"; then
      now="$(date +%s 2>/dev/null || printf '0')"
      if [[ "${now}" =~ ^[0-9]+$ ]] && (( now - mtime < growth_s )); then
        return 1  # fresh -- still working, NOT silent
      fi
    else
      return 1  # stat failed -- fail OPEN, NOT silent
    fi
  fi
  # 4) GATE-FALSE-SILENT-01: a live worker process is never silent.
  _pc_worker_process_alive && return 1
  # 5) worktree dirty-check -- no resolved lane worktree is conservative NOT-silent.
  [[ -n "${_lane_root:-}" && -d "${_lane_root}" ]] || return 1
  # REVIEW-GATE-LANEROOT-01: an unregistered lane dir makes _pc_lane_dirty grade the
  # parent repo. Unknown tree identity is never proof of silence: otherwise a clean
  # parent would advance the arm while finished work remains in the lane directory.
  _pc_lane_root_is_own_worktree "${_lane_root}" || return 1
  _pc_lane_dirty "${_lane_root}" && return 1
  # 6) GATE-FALSE-SILENT-01: commits ahead of base are production, whatever the
  # worktree's dirty state says -- a worker that commits cleanly is not silent.
  # round 2: "unknown" (base unresolvable) is NOT silent either -- a probe that cannot
  # tell must not conclude silence. A lane in this state falls through to pc_scope_diff,
  # which owns the empty/unscoped verdicts from here; this branch only refuses to be the
  # one that mislabels it arm_produced_nothing.
  local commits_ahead
  commits_ahead="$(_pc_lane_commits_ahead "${_lane_root}")"
  if [[ "${commits_ahead}" == "unknown" ]]; then
    emit decision "silent_probe_base_unresolved task=${TASK} arm=${AUTHOR} lane=$(basename "${_lane_root}")"
    return 1
  fi
  [[ "${commits_ahead}" =~ ^[0-9]+$ ]] || commits_ahead=0
  (( commits_ahead >= 1 )) && return 1
  _PC_SILENT_COMMITS_AHEAD="${commits_ahead}"
  _PC_SILENT_LANE_BASENAME="$(basename "${_lane_root}")"
  return 0
}

# ARM-PRODUCES-NOTHING-AND-CHAIN-NEVER-ADVANCES-01 (Fix 2, one-shot discipline): fires
# ONLY from the silent-arm branch below. Marker file written BEFORE the advance attempt
# (idempotent guard against a re-run of this same close gate re-advancing twice); kill
# switch and chain-exhaustion both skip the actual advance but are still journaled.
_pc_arm_advance() {
  local marker="${HANDOFF}/.arm-advanced-${AUTHOR}"
  if [[ -f "${marker}" ]]; then
    emit decision "arm_advance_skipped task=${TASK} arm=${AUTHOR} reason=already_advanced"
    return 0
  fi
  : > "${marker}" 2>/dev/null || true
  if [[ "${LEADV2_ARM_ADVANCE:-1}" == "0" ]]; then
    emit decision "arm_advance_skipped task=${TASK} arm=${AUTHOR} reason=kill_switch"
    return 0
  fi
  local chain_csv="${LEADV2_DISPATCH_CANDIDATE_ARMS:-}"
  if [[ -z "${chain_csv}" ]]; then
    # journal fallback for a close gate spawned by an older dispatcher that never
    # threaded the env var -- same "candidate_chain task=<sig8> arms=..." line
    # leadv2-dispatch-code.sh's own candidate loop already journals.
    chain_csv="$(bash "${JOURNAL_BIN}" tail "dispatch-${TASK}" 100000 2>/dev/null | \
      grep -F "candidate_chain task=${TASK} arms=" | tail -1 | sed -n 's/.*arms=//p')"
  fi
  local next_arm
  if ! next_arm="$(_pc_next_arm_in_chain "${chain_csv}" "${AUTHOR}")" || [[ -z "${next_arm}" ]]; then
    emit decision "arm_advance_skipped task=${TASK} arm=${AUTHOR} reason=chain_exhausted"
    return 0
  fi
  local mission_file="${LEADV2_DISPATCH_LANE_MISSION:-}"
  if [[ -z "${mission_file}" || ! -f "${mission_file}" ]]; then
    mission_file="${ROOT}/docs/handoff/dispatch-${TASK}/lane-mission.md"
  fi
  if [[ ! -f "${mission_file}" ]]; then
    emit decision "arm_advance_skipped task=${TASK} arm=${AUTHOR} reason=no_mission_file"
    return 0
  fi
  emit decision "arm_advance task=${TASK} from=${AUTHOR} to=${next_arm} reason=arm_produced_nothing"
  local adv_args=(--sig8 "${TASK}" --arm "${next_arm}" --mission-file "${mission_file}" --task-id "${FOUNDER_TASK_ID}")
  [[ -n "${_lane_root:-}" && -d "${_lane_root}" ]] && adv_args+=(--worktree "${_lane_root}")
  [[ -n "${WRITES_CSV:-}" ]] && adv_args+=(--writes "${WRITES_CSV}")
  bash "${DISPATCH_BIN}" advance-arm "${adv_args[@]}" >/dev/null 2>&1 || true
}

# REVIEW-GATE-INFRA-01 D-A(i): a declared write under docs/leadv2/ or docs/handoff/
# makes an empty scoped diff MECHANICALLY INEVITABLE, independent of anything the
# worker actually did -- both are hard-excluded by _pc_git_diff / _pc_lane_dirty's
# exclusion pattern, so the diff is empty BY CONSTRUCTION. Detectable from the
# write-set alone, before the worker's build is even awaited -- bounce here with an
# actionable, path-naming reason instead of waiting for the empty-diff classifier
# below to blame the lane. Capped at 5 named paths + a "+N more" suffix, matching
# the review-gate.md path list cap (R1 unbounded-list-is-its-own-leak).
#
# Deliberately NOT bounced here: a declared path that fails to resolve to a git work
# tree. Design draft R2 originally treated that as mechanically inevitable too, but
# it is not -- it is also the exact shape of a LEGITIMATE cross-repo declaration (the
# work landed in a repo this gate's diff_root-relative resolution cannot see). Bouncing
# early on it would preempt the downstream cross_repo_elsewhere classification (D-A-ii)
# with a strictly worse verdict (undiffable_write_set) for the innocent case. Left to
# pc_scope_diff's classifier, which can tell the two apart using lane-dirty evidence.
_pc_join_capped() {  # <n...> -> first 5 comma-joined + "+N more" on stdout
  local items=("$@")
  local n=${#items[@]} out="" i cap=5
  for ((i = 0; i < n && i < cap; i++)); do
    [[ -n "${out}" ]] && out="${out},${items[$i]}"
    [[ -z "${out}" ]] && out="${items[$i]}"
  done
  (( n > cap )) && out="${out},+$((n - cap)) more"
  printf '%s' "${out}"
}

# REVIEW-GATE-LANEROOT-01: .claude/worktrees/ is gitignored, so an unregistered
# lane's files are invisible to porcelain. This human-only evidence intentionally
# does not reuse _PC_PORCELAIN_EXCLUDE_RE, which matches porcelain lines rather than
# bare paths. Newline-containing filenames may render as more than one entry; this
# value is never used for a decision.
_pc_lane_produced_files() {  # <root> -> capped, comma-joined, root-relative file list
  local root="$1" rel out=() f
  while IFS= read -r f; do
    [[ -n "${f}" ]] || continue
    rel="${f#${root}/}"
    out+=("${rel}")
  done <<< "$(find "${root}" -type f \
                -not -path "${root}/.git/*" -not -name '.git' \
                -not -path "${root}/docs/leadv2/*" -not -path "${root}/docs/handoff/*" \
                -not -path '*/__pycache__/*' -not -name '*.pyc' \
                2>/dev/null | head -"${LEADV2_PC_PRODUCED_SCAN_MAX:-500}")"
  [[ ${#out[@]} -eq 0 ]] && { printf 'none'; return 0; }
  _pc_join_capped "${out[@]}"
}
# REVIEW-GATE-INFRA-01 round 2 F3: single normalisation point for a declared write-set
# entry. Strips whitespace and ONE trailing /** or /* glob suffix, then a trailing /,
# so a dir/glob declared shape ("tests/", "tests/unit/**") collapses to the same literal
# prefix a bare path would ("tests", "tests/unit"). Never strips a bare trailing "*"
# (R4 — vanishingly rare as a real path, and stripping it would silently rewrite a
# legitimate literal filename ending in *).
_pc_norm_write() {  # <raw> -> normalised path on stdout
  local w="$1"
  w="${w#"${w%%[![:space:]]*}"}"; w="${w%"${w##*[![:space:]]}"}"
  case "${w}" in
    */\*\*) w="${w%/\*\*}" ;;
    */\*) w="${w%/\*}" ;;
  esac
  w="${w%/}"
  printf '%s' "${w}"
}
# REVIEW-GATE-INFRA-01 round 2 F1: bounce ONLY when every declared path is mechanically
# undiffable (docs/leadv2/*, docs/handoff/*) — a mixed write-set proceeds with the voided
# paths recorded in _PC_UNDIFFABLE_CSV (surfaced later as an additive `undiffable:` key)
# and only the surviving paths in _PC_SCOPE_WRITES_CSV feed the scope diff.
pc_precheck_writes() {
  _PC_UNDIFFABLE_CSV=""
  _PC_SCOPE_WRITES_CSV=""
  [[ -n "${WRITES_CSV:-}" ]] || return 0
  local raw_writes_pf w bad_paths=() good_paths=() bad_n=0 good_n=0
  IFS=',' read -r -a raw_writes_pf <<< "${WRITES_CSV}"
  for w in "${raw_writes_pf[@]}"; do
    w="$(_pc_norm_write "${w}")"
    [[ -z "${w}" ]] && continue
    case "${w}" in
      docs/leadv2|docs/leadv2/*|docs/handoff|docs/handoff/*)
        bad_paths+=("${w}"); bad_n=$((bad_n + 1))
        ;;
      *)
        good_paths+=("${w}"); good_n=$((good_n + 1))
        ;;
    esac
  done
  if [[ ${good_n} -eq 0 && ${bad_n} -gt 0 ]]; then
    local joined
    joined="$(_pc_join_capped "${bad_paths[@]}")"
    printf 'status: blocked\nreason: undiffable_write_set\npaths: %s\n' "${joined}" > "${HANDOFF}/review-gate.md"
    emit decision "review_gate task=${TASK} status=blocked reason=undiffable_write_set terminal=refused cause=undiffable_write_set paths=${joined}"
    _dl_note refused undiffable_write_set "paths=${joined}"
    _stamp_review_terminal blocked
    # reap any live worker before bouncing — mirrors the worker_timeout path (:1699-1700)
    # so a fully-voided write-set never orphans a worker process.
    _pc_reap_worker "$(_pc_run_dir_for "${AUTHOR}" "${HANDLE}")" "$(_pc_meta_value "$(_pc_run_dir_for "${AUTHOR}" "${HANDLE}")/meta.yaml" pid 2>/dev/null)" 2>/dev/null || true
    exit 5
  fi
  [[ ${bad_n} -gt 0 ]] && _PC_UNDIFFABLE_CSV="$(IFS=,; printf '%s' "${bad_paths[*]}")"
  _PC_SCOPE_WRITES_CSV="$(IFS=,; printf '%s' "${good_paths[*]}")"
  return 0
}

# V3-STOP-GATE-01: called right after the worker's exit is confirmed (both the
# first pc_await_worker_exit and, if it fired, the GLM-DIED-WITH-WORK-RESUME-01
# second wait) and BEFORE pc_scope_diff/selfcheck/e2e/review touch the tree.
# Disease this closes (live, 2026-08-19/20): 6+ worker exits left real work
# UNCOMMITTED in the lane worktree -- invisible to every downstream phase and
# one parallel session away from being clobbered (SUPDEL 47 files, V3-GLM 24,
# ENV-GUARDS 6, T2 twice -- the lead had to checkpoint-commit by hand each time).
# Only the declared write-set (_PC_SCOPE_WRITES_CSV, already normalised by
# pc_precheck_writes above) is staged into an ISOLATED index -- junk OUTSIDE
# the write-set (including another actor's already-staged changes) is
# deliberately left alone. That is what pc_scope_diff's unscoped_lane_work
# classifier already handles, and auto-committing it here would launder a
# scope violation instead of catching it. LEADV2_STOP_GATE=0 restores today's
# path byte-for-byte (same idiom as LEADV2_BUILDER_SELFCHECK).
# Capture-only pre-checkpoint snapshot for the timeout paths (codex r3): scoped to the
# declared write-set, untracked-inclusive via a throwaway index + add -N (same technique
# as pc_scope_diff's _pc_git_diff, duplicated here because that helper is only defined
# inside pc_scope_diff's body and the timeout paths never enter it), and populates
# PC_STOP_GATE_FOREIGN_REPOS so the gate's stop_gate_skipped_foreign_repo journal fires
# on timeout too. NO verdict/journal/ledger side effects of its own.
pc_stop_gate_capture_diff() {
  local _ct_lane="${LEADV2_LANE_WORK_ROOT:-}"
  [[ -z "${_ct_lane}" ]] && _ct_lane="$(LEADV2_PROJECT_ROOT="${ROOT}" bash "${SCRIPT_DIR}/leadv2-lane-worktree.sh" path-of "${FOUNDER_TASK_ID:-${TASK}}" 2>/dev/null || true)"
  [[ -n "${_ct_lane}" && -d "${_ct_lane}" ]] || return 0
  declare -p PC_STOP_GATE_FOREIGN_REPOS >/dev/null 2>&1 || PC_STOP_GATE_FOREIGN_REPOS=()
  local _ct_csv="${_PC_SCOPE_WRITES_CSV:-${LEADV2_DISPATCH_LANE_WRITES:-}}" _ct_p _ct_r
  local _ct_paths=()
  local _ct_old_ifs="${IFS}"
  IFS=','
  for _ct_p in ${_ct_csv}; do
    IFS="${_ct_old_ifs}"
    [[ -z "${_ct_p}" ]] && { IFS=','; continue; }
    if [[ "${_ct_p}" == /* && "${_ct_p}" != "${_ct_lane}" && "${_ct_p}" != "${_ct_lane}/"* ]]; then
      _ct_r="$(cd "$(dirname "${_ct_p}")" 2>/dev/null && git rev-parse --show-toplevel 2>/dev/null || true)"
      [[ -n "${_ct_r}" && "${_ct_r}" != "${_ct_lane}" ]] && PC_STOP_GATE_FOREIGN_REPOS+=("${_ct_r}")
    else
      _ct_paths+=("${_ct_p}")
    fi
    IFS=','
  done
  IFS="${_ct_old_ifs}"
  mkdir -p "${HANDOFF}" 2>/dev/null || true
  local _ct_gitdir _ct_idx
  _ct_gitdir="$(git -C "${_ct_lane}" rev-parse --absolute-git-dir 2>/dev/null || true)"
  _ct_idx="$(mktemp "${TMPDIR:-/tmp}/leadv2-ct-idx.XXXXXX" 2>/dev/null || true)"
  if [[ -n "${_ct_gitdir}" && -n "${_ct_idx}" ]] && cp "${_ct_gitdir}/index" "${_ct_idx}" 2>/dev/null; then
    if [[ ${#_ct_paths[@]} -gt 0 ]]; then
      GIT_INDEX_FILE="${_ct_idx}" git -C "${_ct_lane}" add -N -- "${_ct_paths[@]+"${_ct_paths[@]}"}" >/dev/null 2>&1 || true
      GIT_INDEX_FILE="${_ct_idx}" git -C "${_ct_lane}" diff HEAD -- "${_ct_paths[@]+"${_ct_paths[@]}"}" ':(exclude)docs/leadv2' ':(exclude)docs/handoff' > "${HANDOFF}/review.diff" 2>/dev/null || true
    else
      GIT_INDEX_FILE="${_ct_idx}" git -C "${_ct_lane}" add -N -A >/dev/null 2>&1 || true
      GIT_INDEX_FILE="${_ct_idx}" git -C "${_ct_lane}" diff HEAD -- ':(exclude)docs/leadv2' ':(exclude)docs/handoff' > "${HANDOFF}/review.diff" 2>/dev/null || true
    fi
  else
    git -C "${_ct_lane}" diff HEAD > "${HANDOFF}/review.diff" 2>/dev/null || true
  fi
  rm -f "${_ct_idx}" 2>/dev/null || true
}

_PC_STOP_GATE_REASON="auto-checkpoint on worker exit"
_pc_stop_gate_resolve_reason() {
  _PC_STOP_GATE_REASON="auto-checkpoint on worker exit"
  local run_dir stream
  run_dir="$(_pc_run_dir_for "${AUTHOR:-}" "${HANDLE:-}")"
  if [[ -n "${run_dir}" && "$(_pc_lane_outcome "${run_dir}")" == "parked" ]]; then
    _PC_STOP_GATE_REASON="parked-on-background-job"
    return 0
  fi
  stream="${HANDOFF}/${AUTHOR:-developer}.stream.jsonl"
  if declare -F lv2_parked_text_file >/dev/null 2>&1 && lv2_parked_text_file "${stream}"; then
    _PC_STOP_GATE_REASON="parked-on-background-job"
  fi
}

pc_stop_gate_autocommit() {
  [[ "${LEADV2_STOP_GATE:-1}" != 0 ]] || return 0
  [[ -n "${_PC_SCOPE_WRITES_CSV:-}" ]] || return 0

  # Cross-repository writes are diffed by pc_scope_diff but are not safe to
  # commit from this lane's repository. Do not silently claim protection.
  # bash 3.2/set -u: an array that was never assigned is UNBOUND and ${#arr[@]}
  # aborts the whole script here — exactly the paths (timeout reap) where the
  # populate step in pc_scope_diff may not have run. Declare-if-unset first.
  declare -p PC_STOP_GATE_FOREIGN_REPOS >/dev/null 2>&1 || PC_STOP_GATE_FOREIGN_REPOS=()
  if [[ ${#PC_STOP_GATE_FOREIGN_REPOS[@]} -gt 0 ]]; then
    local _sg_foreign="" _sg_repo
    for _sg_repo in "${PC_STOP_GATE_FOREIGN_REPOS[@]}"; do
      [[ -n "${_sg_foreign}" ]] && _sg_foreign+=","
      _sg_foreign+="$(basename "${_sg_repo}")"
    done
    emit decision "stop_gate_skipped_foreign_repo task=${TASK} repos=${_sg_foreign}"
  fi

  local _sg_lane_root="${LEADV2_LANE_WORK_ROOT:-}"
  if [[ -z "${_sg_lane_root}" || ! -d "${_sg_lane_root}" ]]; then
    _sg_lane_root="$(LEADV2_PROJECT_ROOT="${ROOT}" bash "${SCRIPT_DIR}/leadv2-lane-worktree.sh" path-of "${FOUNDER_TASK_ID:-${TASK}}" 2>/dev/null || true)"
  fi
  [[ -n "${_sg_lane_root}" ]] || return 0
  [[ -d "${_sg_lane_root}/.git" || -f "${_sg_lane_root}/.git" ]] 2>/dev/null || return 0

  local _sg_paths=()
  IFS=',' read -r -a _sg_paths <<< "${_PC_SCOPE_WRITES_CSV}"
  [[ ${#_sg_paths[@]} -gt 0 ]] || return 0

  # A write-set entry resolving OUTSIDE _sg_lane_root (a cross-repo path) makes
  # `git status -- <pathspec...>` fail its ENTIRE invocation (exit 128, "outside
  # repository") -- not just skip that one entry -- which silently drops every
  # in-scope path from the SAME call, defeating the checkpoint for a lane that
  # is otherwise single-repo-safe. Cheap common case first (one combined probe,
  # same cost as before this fix); only pay for a per-path git call when that
  # probe actually fails, which is exactly the rare cross-repo write-set shape
  # (already journaled by stop_gate_skipped_foreign_repo above) -- this keeps
  # the normal single-repo path free of added latency in a timing-sensitive
  # caller (worker-timeout ceilings elsewhere in this script).
  if ! git -C "${_sg_lane_root}" status --porcelain=v1 -- "${_sg_paths[@]}" >/dev/null 2>&1; then
    local _sg_in_scope=() _sg_p
    for _sg_p in "${_sg_paths[@]}"; do
      git -C "${_sg_lane_root}" status --porcelain=v1 -- "${_sg_p}" >/dev/null 2>&1 \
        && _sg_in_scope+=("${_sg_p}")
    done
    _sg_paths=("${_sg_in_scope[@]}")
  fi
  [[ ${#_sg_paths[@]} -gt 0 ]] || return 0

  # HOLE-1 fix (V3-STOP-GATE-FINISH-01): `git add -- <declared pathspec>` fails
  # hard (exit 128) the instant ANY declared path was never created -- the
  # normal shape of a lane whose worker died mid-write-set -- and the old
  # `|| return 0` swallowed that, staging nothing at all. Stage the CONCRETE
  # files git status just reported instead of re-using the declared pathspec:
  # those paths are known to exist, and because status was itself
  # produced by `git status -- "${_sg_paths[@]}"` the concrete list stays
  # inside the declared write-set -- no scope widening. Use porcelain -z:
  # display porcelain C-quotes tabs, newlines, quotes, backslashes, and UTF-8.
  local _sg_files=() _sg_reset_files=()
  local _sg_line _sg_path _sg_source _sg_xy _sg_n=0
  while IFS= read -r -d '' _sg_line; do
    [[ -n "${_sg_line}" ]] || continue
    _sg_xy="${_sg_line:0:2}"
    _sg_path="${_sg_line:3}"
    # With porcelain -z, rename/copy is destination NUL source NUL. The
    # destination in this first record is the path to stage; consume source.
    # A rename's source is also passed to `git add` below -- `git add <path>`
    # on a path that is tracked at HEAD but absent from the worktree (the old
    # name, after `git mv`) stages its deletion, which is what turns the
    # add-destination-only temp index into an actual rename instead of
    # leaving the stale source blob sitting in the checkpoint tree.
    if [[ "${_sg_xy}" == *R* || "${_sg_xy}" == *C* ]]; then
      _sg_source=""
      IFS= read -r -d '' _sg_source || true
      if [[ -n "${_sg_source}" ]]; then
        _sg_reset_files+=("${_sg_source}")
        [[ "${_sg_xy}" == *R* ]] && _sg_files+=("${_sg_source}")
      fi
    fi
    [[ -n "${_sg_path}" ]] && { _sg_files+=("${_sg_path}"); _sg_reset_files+=("${_sg_path}"); _sg_n=$((_sg_n + 1)); }
  done < <(git -C "${_sg_lane_root}" status --porcelain=v1 -z -- "${_sg_paths[@]}" 2>/dev/null)
  [[ ${#_sg_files[@]} -gt 0 ]] || return 0

  # Never commit through the inherited index: it may contain another actor's
  # staged out-of-scope work. Build exactly HEAD plus the concrete in-scope
  # worktree paths in a throwaway index, leaving the real index byte-for-byte.
  local _sg_index
  _sg_index="$(mktemp "${TMPDIR:-/tmp}/leadv2-stop-gate-index.XXXXXX")" || {
    emit decision "stop_gate_autocommit_failed task=${TASK} reason=index_create_failed"
    return 0
  }
  if ! GIT_INDEX_FILE="${_sg_index}" git -C "${_sg_lane_root}" read-tree HEAD >/dev/null 2>&1 \
     || ! GIT_INDEX_FILE="${_sg_index}" git -C "${_sg_lane_root}" add -- "${_sg_files[@]}" >/dev/null 2>&1; then
    rm -f "${_sg_index}"
    emit decision "stop_gate_autocommit_failed task=${TASK} reason=add_failed"
    return 0
  fi
  if GIT_INDEX_FILE="${_sg_index}" git -C "${_sg_lane_root}" diff --cached --quiet 2>/dev/null; then
    rm -f "${_sg_index}"
    return 0
  fi
  if GIT_INDEX_FILE="${_sg_index}" git -C "${_sg_lane_root}" commit -q -m "wip(${TASK}): ${_PC_STOP_GATE_REASON} (STOP-GATE)" >/dev/null 2>&1; then
    # HEAD moved underneath the real index. Refresh only committed in-scope
    # entries so they do not look staged against the new checkpoint; foreign
    # staged entries remain entirely untouched.
    git -C "${_sg_lane_root}" reset -q HEAD -- "${_sg_reset_files[@]}" >/dev/null 2>&1 || true
    emit decision "stop_gate_autocommit task=${TASK} files=${_sg_n}"
  else
    emit decision "stop_gate_autocommit_failed task=${TASK} reason=commit_failed"
  fi
  rm -f "${_sg_index}"
}

# WARNING: pc_scope_diff() below defines helper functions in its body that are
# NOT available until it is first invoked (line ~1277 in the original layout).
# Top-level code that runs before pc_scope_diff() must not call those helpers.
pc_scope_diff() {
diff_file="${HANDOFF}/review.diff"
: > "${diff_file}"
repos_file="${HANDOFF}/review.diff.repos"
: > "${repos_file}"
blocked_reason=""
_pc_base_used="HEAD"
CROSS_REPO_DIFF="${LEADV2_REVIEW_DIFF_CROSS_REPO:-1}"
# pc_stop_gate_autocommit handles only the lane repository. pc_scope_diff is
# the one place that has authoritative per-write repository resolution, so it
# records foreign repos here for a loud checkpoint-skip journal entry.
PC_STOP_GATE_FOREIGN_REPOS=()
# P0-WORK-CANNOT-LAND-UNSCOPABLE-DIFF-01 (M3) / C1+C3 (LANDING-BLOCKER-R2): diff_root
# resolution to the lane worktree is UNCONDITIONAL (GATE-LANE-DIFF-ONLY-WHEN-CROSS-REPO-01,
# 2026-08-04) -- prefer LEADV2_LANE_WORK_ROOT -- the SAME value dispatch-code.sh gave every
# worker's --cwd, so diff_root can never disagree with where the code actually landed (C1:
# glm/codex used to write to PROJECT_ROOT while this always diffed the worktree). `path-of`
# (keyed by the FOUNDER task id -- worktrees are created keyed by founder tid in
# leadv2-fanout.sh, not this script's own sig8 TASK) is only the fallback for a close gate
# started outside the launcher lineage (manual re-run, test harness invoking this script
# directly). CROSS_REPO_DIFF no longer gates this: it used to double as a full revert to
# pre-fix diffing-the-main-checkout behaviour, but that made a single-repo close (the flag
# OFF/unset default) diff the wrong tree whenever a lane worktree existed, discarding real
# work as `no_work` (persona-engine 0db1da80, 2026-08-04). CROSS_REPO_DIFF now controls only
# the multi-repo per-write grouping branch below; a genuinely empty lane still resolves to
# `no_work` via the dirty-lane check further down.
diff_root="${ROOT}"
_lane_root="${LEADV2_LANE_WORK_ROOT:-}"
if [[ -z "${_lane_root}" || ! -d "${_lane_root}" ]]; then
  _lane_root="$(LEADV2_PROJECT_ROOT="${ROOT}" bash "${SCRIPT_DIR}/leadv2-lane-worktree.sh" path-of "${FOUNDER_TASK_ID:-${TASK}}" 2>/dev/null || true)"
fi
[[ -n "${_lane_root}" && -d "${_lane_root}" ]] && diff_root="${_lane_root}"
# Resolve a possibly-symlinked path to the repo that actually owns it. persona-engine's
# .claude/scripts/leadv2-*.sh are git-tracked symlinks into a SEPARATE ~/Projects/leadv2
# checkout -- a symlink blob only stores its target path string, so `git -C "${diff_root}"
# diff -- <that path>` is empty by construction. No portable `readlink -f` on macOS.
# Source the shared e2e-root validation lib (C1, GATE-WRONG-ROOT-FALSE-DEAD-01):
# one mechanism for both product-close and phase8-e2e-gate. Provides
# _lv2_realpath and _lv2_e2e_resolve_root; _pc_realpath is a backward-compat alias.
# shellcheck source=lib/leadv2-e2e-root.sh
source "${SCRIPT_DIR}/lib/leadv2-e2e-root.sh"
_pc_realpath() { _lv2_realpath "$@"; }
# C2 (LANDING-BLOCKER-R2): `git diff HEAD` never sees untracked paths, and a brand-new
# file is a large share of lane deliverables -- LANE_WRITES=agent/newmod.py, created but
# never `git add`ed, used to yield an empty diff every time. Diff against a THROWAWAY COPY
# of the real index (never the real one -- other live sessions share this tree, and an
# empty GIT_INDEX_FILE makes every tracked file read as deleted) so `git add -N` can
# register the new path without mutating anything a concurrent session or a later
# `git commit` would see. Falls back to a plain diff (loses untracked coverage, never
# lies) if the index copy itself cannot be made.
_pc_git_diff() {  # <repo_abs> <base_rev> <path...> -> diff on stdout (tracked + untracked + deletions)
  local repo="$1" base="$2"; shift 2
  local gitdir tmpidx
  gitdir="$(git -C "${repo}" rev-parse --absolute-git-dir 2>/dev/null)" || { git -C "${repo}" diff "${base}" -- "$@" ':(exclude)docs/leadv2' ':(exclude)docs/handoff' 2>/dev/null; return 0; }
  tmpidx="$(mktemp "${TMPDIR:-/tmp}/leadv2-pc-idx.XXXXXX")" || { git -C "${repo}" diff "${base}" -- "$@" ':(exclude)docs/leadv2' ':(exclude)docs/handoff' 2>/dev/null; return 0; }
  if cp "${gitdir}/index" "${tmpidx}" 2>/dev/null; then
    GIT_INDEX_FILE="${tmpidx}" git -C "${repo}" add -N -- "$@" >/dev/null 2>&1 || true
    GIT_INDEX_FILE="${tmpidx}" git -C "${repo}" diff "${base}" -- "$@" ':(exclude)docs/leadv2' ':(exclude)docs/handoff' 2>/dev/null
  else
    git -C "${repo}" diff "${base}" -- "$@" ':(exclude)docs/leadv2' ':(exclude)docs/handoff' 2>/dev/null
  fi
  rm -f "${tmpidx}"
}

# S-3 round 3 (LANE-START-SHA-01): `git diff HEAD` is empty by definition for a lane that
# already COMMITTED its own work -- the normal end state of a finished lane -- and can also
# lose part of an uncommitted lane's changes once another lane's commit moves HEAD forward
# in the shared tree. Resolve the merge-base with the dispatcher's recorded start commit;
# if no usable recorded base belongs to this repo, fall back to origin/main. A multi-repo
# lane can legitimately carry a start SHA from a different repo, and manual close-gate runs
# may have no cache file, so each candidate is independently best-effort. Empty output means
# neither candidate had a merge-base with HEAD and the caller preserves the HEAD-only path.
_pc_diff_base() {  # <repo_abs> -> a rev to diff FROM on stdout; empty stdout => caller uses HEAD
  local repo="$1" sha="${LEADV2_LANE_START_SHA:-}" base
  if [[ -z "${sha}" ]]; then
    sha="$(cat "${CACHE_BASE}/dispatch-${TASK}.start-sha" 2>/dev/null || true)"
  fi
  if [[ -n "${sha}" ]] && git -C "${repo}" cat-file -e "${sha}^{commit}" 2>/dev/null; then
    base="$(git -C "${repo}" merge-base "${sha}" HEAD 2>/dev/null || true)"
    [[ -n "${base}" ]] && { printf '%s' "${base}"; return 0; }
  fi
  if git -C "${repo}" cat-file -e "origin/main^{commit}" 2>/dev/null; then
    base="$(git -C "${repo}" merge-base origin/main HEAD 2>/dev/null || true)"
    [[ -n "${base}" ]] && printf '%s' "${base}"
  fi
}

# _pc_repo_diff runs inside a `repo_diff="$(...)"` command substitution at every call site,
# i.e. its own subshell -- a plain variable it set would never reach the caller. Record
# which base it picked (HEAD, or an abbreviated sha) to a file instead, mirroring the
# tmpidx idiom just above; the caller reads it back immediately after, single-threaded, no
# concurrent writer.
_PC_LAST_BASE_FILE="${TMPDIR:-/tmp}/leadv2-pc-lastbase.$$"
_pc_last_diff_base() { cat "${_PC_LAST_BASE_FILE}" 2>/dev/null || printf 'HEAD'; }
# The never-smaller guard: compute the diff both against HEAD (today's exact query,
# unchanged) and against the recorded start commit (if one validly resolves), and keep
# whichever is LARGER. This is a mechanical guarantee independent of any ancestry argument
# -- it cannot regress any arm below today's HEAD-diff baseline by construction.
_pc_repo_diff() { # <repo_abs> <path...> -> diff on stdout (tracked + untracked + deletions)
  local repo="$1"; shift
  local base head_out base_out chosen
  head_out="$(_pc_git_diff "${repo}" HEAD "$@")"
  base="$(_pc_diff_base "${repo}")"
  if [[ -n "${base}" ]]; then
    base_out="$(_pc_git_diff "${repo}" "${base}" "$@")"
  else
    base_out=""
  fi
  if [[ ${#base_out} -gt ${#head_out} ]]; then
    chosen="${base:0:8}"
    printf '%s' "${base_out}"
  else
    chosen="HEAD"
    printf '%s' "${head_out}"
  fi
  printf '%s' "${chosen}" > "${_PC_LAST_BASE_FILE}" 2>/dev/null || true
}
if [[ -n "${WRITES_CSV}" ]]; then
  IFS=',' read -r -a raw_writes <<< "${_PC_SCOPE_WRITES_CSV:-${WRITES_CSV}}"
  writes=()
  for w in "${raw_writes[@]}"; do
    w="$(_pc_norm_write "${w}")"
    [[ -n "${w}" ]] && writes+=("${w}")
  done
  if [[ ${#writes[@]} -gt 0 ]]; then
    if [[ "${CROSS_REPO_DIFF}" == "1" ]]; then
      # M8/M9 (LANDING-BLOCKER-R2): no associative arrays -- `declare -A` hard-errors under
      # bash 3.2, and dispatch-code.sh resolves `bash` from PATH, which can be /bin/bash
      # 3.2 without homebrew on PATH -- and no space-joined path strings (word-splits any
      # path containing a space). Two parallel INDEXED arrays instead; both constructs are
      # bash-3.2-safe.
      repo_order=()
      repo_of=()
      rel_of=()
      _pc_unresolved_writes=()
      _pc_unresolved_n=0
      for i in "${!writes[@]}"; do
        real_abs="$(_pc_realpath "${diff_root}/${writes[$i]}")"
        r="$(git -C "$(dirname "${real_abs}")" rev-parse --show-toplevel 2>/dev/null || true)"
        if [[ -z "${r}" ]]; then
          # REVIEW-GATE-INFRA-01 D-A(iv): a declared path that resolves outside any git
          # work tree used to collapse silently onto diff_root (r="${diff_root}"),
          # attributing it -- and its inevitable 0 bytes -- to diff_root's own group.
          # That drags a legitimately cross-repo lane toward a false empty verdict for
          # a repo the path was never really in scope for. Record it instead of
          # grouping it; the classifier below treats "resolved repos all had bytes, OR
          # a write never resolved at all" as cross_repo_elsewhere, not a scope
          # violation.
          _pc_unresolved_writes+=("${writes[$i]}")
          _pc_unresolved_n=$((_pc_unresolved_n + 1))
          repo_of[$i]=""
          rel_of[$i]=""
          continue
        fi
        repo_of[$i]="${r}"
        rel_of[$i]="${real_abs#"${r}"/}"
        _seen=0
        for q in "${repo_order[@]:-}"; do [[ "${q}" == "${r}" ]] && { _seen=1; break; }; done
        (( _seen )) || repo_order+=("${r}")
      done
      _pc_lane_repo="$(git -C "${diff_root}" rev-parse --show-toplevel 2>/dev/null || true)"
      for repo in "${repo_order[@]}"; do
        [[ -n "${_pc_lane_repo}" && "${repo}" != "${_pc_lane_repo}" ]] && PC_STOP_GATE_FOREIGN_REPOS+=("${repo}")
      done
      # H5 (LANDING-BLOCKER-R2): a repo that contributes nothing used to be skipped
      # silently and the block check fired only when EVERY repo was empty, so a lane
      # spanning two repos with one side empty got an unrecorded APPROVE on half a diff.
      # Journal a per-repo byte count and a sidecar (L11) for every declared repo, and
      # block as `partial_diff` (distinct from `unscopable_diff`, so the two failure
      # modes stay separable in the journal) whenever the group is a genuine MIX of
      # zero-byte and non-zero-byte repos. A group where every repo is empty falls
      # through to the pre-existing `unscopable_diff` check below unchanged.
      _zero_repos=0
      _nonzero_repos=0
      for repo in "${repo_order[@]}"; do
        paths=()
        for i in "${!writes[@]}"; do
          [[ "${repo_of[$i]}" == "${repo}" ]] && paths+=("${rel_of[$i]}")
        done
        repo_diff="$(_pc_repo_diff "${repo}" "${paths[@]}")"
        n=${#repo_diff}
        _pc_base_used="$(_pc_last_diff_base)"
        emit decision "review_diff task=${TASK} repo=$(basename "${repo}") bytes=${n} base=${_pc_base_used}"
        printf '%s %s\n' "$(basename "${repo}")" "${n}" >> "${repos_file}"
        if [[ -z "${repo_diff}" ]]; then
          _zero_repos=$((_zero_repos + 1))
        else
          _nonzero_repos=$((_nonzero_repos + 1))
          printf '%s\n' "${repo_diff}" >> "${diff_file}"
        fi
      done
      if [[ ${_zero_repos} -gt 0 && ${_nonzero_repos} -gt 0 ]]; then
        blocked_reason="partial_diff"
      fi
    else
      repo_diff="$(_pc_repo_diff "${diff_root}" "${writes[@]}")"
      printf '%s' "${repo_diff}" > "${diff_file}"
      _pc_base_used="$(_pc_last_diff_base)"
    fi
  fi
  [[ -s "${diff_file}" ]] || blocked_reason="${blocked_reason:-unscopable_diff}"
else
  if [[ -d "${diff_root}" ]]; then
    repo_diff="$(_pc_repo_diff "${diff_root}" .)"
    printf '%s' "${repo_diff}" > "${diff_file}"
    _pc_base_used="$(_pc_last_diff_base)"
  fi
  [[ -s "${diff_file}" ]] || blocked_reason="unscopable_diff"
fi
rm -f "${_PC_LAST_BASE_FILE}" 2>/dev/null || true
# REPORT-ONLY-GATE-01: a declared report lane is gated on its FILE, not on diff bytes.
# Runs BEFORE the blocked_reason block so it never falls into the empty-diff path — no
# predicate a code lane traverses is edited (this branch is reachable only when kind=report,
# i.e. an exactly-parsable report: declaration threaded by dispatch-code.sh). pc_scope_diff
# is invoked only after pc_await_worker_exit, so the report is never read while the worker
# may still be writing it. report_missing / report_too_thin are CAUSES on the unchanged
# no_work terminal — "the worker produced nothing" stays distinguishable from "the report
# exists and is here" without a new ledger word.
if [[ "${_pc_kind}" == "report" ]]; then
  _pc_report_abs=""
  _pc_report_abs="$(lv2_report_locate "${diff_root}" "${ROOT}" "${_pc_report_rel}")"
  if [[ -z "${_pc_report_abs}" ]]; then
    printf 'status: blocked\nreason: report_missing\nkind: report\ndeclared: %s\n' "${_pc_report_rel}" > "${HANDOFF}/review-gate.md"
    emit decision "review_gate task=${TASK} status=blocked reason=report_missing kind=report terminal=no_work cause=report_missing declared=${_pc_report_rel}"
    _dl_note no_work report_missing "declared=${_pc_report_rel}"
    _stamp_review_terminal blocked
    exit 5
  fi
  _pc_report_bytes="$(wc -c < "${_pc_report_abs}" 2>/dev/null | tr -d '[:space:]')"
  _pc_report_bytes="${_pc_report_bytes:-0}"
  if ! lv2_report_substantive "${_pc_report_abs}"; then
    printf 'status: blocked\nreason: report_too_thin\nkind: report\nbytes: %s\nmin: %s bytes / %s lines\n' \
      "${_pc_report_bytes}" "${LEADV2_REPORT_MIN_BYTES:-600}" "${LEADV2_REPORT_MIN_LINES:-12}" > "${HANDOFF}/review-gate.md"
    emit decision "review_gate task=${TASK} status=blocked reason=report_too_thin kind=report terminal=no_work cause=report_too_thin bytes=${_pc_report_bytes} declared=${_pc_report_rel}"
    _dl_note no_work report_too_thin "bytes=${_pc_report_bytes} declared=${_pc_report_rel}"
    _stamp_review_terminal blocked
    exit 5
  fi
  # harvest: ROOT-side docs/handoff/dispatch-<TASK>/report.md survives the lane sweep
  _pc_report_dest="$(lv2_report_harvest "${_pc_report_abs}" "${HANDOFF}")"
  _pc_report_deliverable="docs/handoff/dispatch-${TASK}/report.md"
  # Review-body substitution: the report IS the review body — the unmodified review
  # path below (findings renderer, verdict-marker check, review_body_lost guard,
  # pass/fail rendering) then works unchanged, so a wrong analysis is rejected by the
  # same machinery that rejects a wrong diff.
  {
    printf '# REPORT-ONLY LANE — review the ANALYSIS, not a diff.\n'
    printf '# deliverable: %s   bytes: %s\n' "${_pc_report_rel}" "${_pc_report_bytes}"
    head -c "${LEADV2_REPORT_REVIEW_MAX_BYTES:-60000}" "${_pc_report_abs}"
    printf '\n'
    if [[ "${_pc_report_bytes}" -gt "${LEADV2_REPORT_REVIEW_MAX_BYTES:-60000}" ]]; then
      printf '# [truncated for review at %s bytes; full report at %s]\n' "${LEADV2_REPORT_REVIEW_MAX_BYTES:-60000}" "${_pc_report_dest}"
    fi
  } > "${diff_file}"
  # the diff-scoped blocked_reason (typically unscopable_diff — a report lane has no
  # diff) is void here: the report lane passed its own gate above.
  blocked_reason=""
  emit decision "report_gate task=${TASK} status=located bytes=${_pc_report_bytes} declared=${_pc_report_rel} deliverable=${_pc_report_deliverable}"
fi
# T8C-FOREIGN-REPO-LANDING-01: an empty-diff/dirty-but-undeclared verdict here would be
# a false no_work/unscoped_lane_work for a lane whose mission legitimately targets a
# repo OTHER than its own PE worktree (the shared leadv2 plugin repo is the live case --
# CLAUDE.md "fix once in canonical" policy) -- the lane's local diff is genuinely empty
# because its real work landed as a commit in that other repo, not because the lane did
# nothing. Declared via LANE_TARGET_REPO=<abs path> (lane env, checked first) or a
# ${HANDOFF}/lane-target-repo marker file (line 1 = path, optional line 2 = the
# commit-message grep token to use instead of TASK -- the founder-facing task label
# ("T8c") a lane tags its own commits with is often NOT the same string as the
# machine TASK sig, so this must be overridable per lane, never inferred).
# Checked BEFORE the blocked_reason classification below so a landed-foreign lane never
# falls into no_work/refused; runs only when a verdict is ALREADY headed there (an empty
# or undeclared-dirty diff) -- a lane with real local bytes never needs this and is
# unaffected. Evidence is a commit-message grep, deliberately NOT an unscoped
# "--since only" git log: leadv2-dispatch-ledger.sh's _dl_derive_lane_state documents the
# 2026-08-04 incident where an unscoped window attributed the target repo's newest
# unrelated commit to 137 lanes at once -- the same trap applies here, so a match
# requires the grep token to actually appear in the commit message.
if [[ -n "${blocked_reason}" && "${blocked_reason}" != "partial_diff" ]]; then
  _pc_foreign_repo="${LANE_TARGET_REPO:-${LEADV2_LANE_TARGET_REPO:-}}"
  _pc_foreign_grep="${LEADV2_LANE_TARGET_REPO_GREP:-}"
  if [[ -z "${_pc_foreign_repo}" && -f "${HANDOFF}/lane-target-repo" ]]; then
    _pc_foreign_repo="$(sed -n '1p' "${HANDOFF}/lane-target-repo" 2>/dev/null | tr -d '[:space:]')"
    [[ -z "${_pc_foreign_grep}" ]] && _pc_foreign_grep="$(sed -n '2p' "${HANDOFF}/lane-target-repo" 2>/dev/null | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
  fi
  [[ -z "${_pc_foreign_grep}" ]] && _pc_foreign_grep="${TASK}"
  if [[ -n "${_pc_foreign_repo}" && -d "${_pc_foreign_repo}/.git" && -n "${_pc_foreign_grep}" ]]; then
    _pc_foreign_hits="$(git -C "${_pc_foreign_repo}" log --all --format='%H %s' --fixed-strings --grep="${_pc_foreign_grep}" 2>/dev/null | head -n5)"
    if [[ -n "${_pc_foreign_hits}" ]]; then
      # Reuses the landed|parked|refused|dead|no_work ledger enum unchanged (no new
      # terminal word -- leadv2-dispatch-ledger.sh write_terminal hard-errors on any
      # other string); landed_foreign is a cause under the existing `landed` terminal,
      # the same relationship unscoped_lane_work has to `refused` above.
      blocked_reason=""
      printf 'status: passed\nreason: landed_foreign\nforeign_repo: %s\ngrep: %s\ncommits:\n%s\n' \
        "${_pc_foreign_repo}" "${_pc_foreign_grep}" "${_pc_foreign_hits}" > "${HANDOFF}/review-gate.md"
      emit decision "review_gate task=${TASK} status=passed reason=landed_foreign terminal=landed cause=landed_foreign foreign_repo=$(basename "${_pc_foreign_repo}")"
      _dl_note landed landed_foreign "foreign_repo=${_pc_foreign_repo} grep=${_pc_foreign_grep}"
      _stamp_review_terminal pass
      exit 0
    fi
  fi
fi
if [[ -n "${blocked_reason}" ]]; then
  # N1-EMPTY-LANE-IS-NOT-A-PASS: a lane that produced NOTHING is its own outcome --
  # never passed, never a silently-blocked unscopable_diff. partial_diff stays
  # `refused` (a mixed group DID produce work, R10); the whole-empty cases become
  # `no_work` (retryable, like refused/parked) with cause empty_diff, or
  # asked_into_void when the worker's run dir carries the Design-C marker
  # (_PC_ASKED_INTO_VOID, set by the asked-into-void probe below the e2e block).
  # Exit code stays 5 -- no caller-contract change.
  _pc_terminal="refused"; _pc_cause="${blocked_reason}"; _pc_rg_reason="${blocked_reason}"
  if [[ "${blocked_reason}" != "partial_diff" ]]; then
    # GATE-LANE-DIFF-ONLY-WHEN-CROSS-REPO-01: an empty diff whose resolved lane worktree is
    # DIRTY is a diff-scoping failure, not an absent-work outcome -- the worker demonstrably
    # produced something the gate could not scope. Gate on _lane_root (whether a lane
    # worktree resolved), not on diff_root != ROOT: when no lane worktree exists, workers
    # write into the main checkout, and unrelated founder edits sitting there must never be
    # mistaken for lane work. Checked BEFORE asked_into_void: a lane that both asked into
    # the void and left dirt is a scoping failure first -- the discarded diff is not
    # recoverable once the lead re-dispatches, but the void question can be re-asked later.
    # `refused` (not a new terminal word -- see leadv2-dispatch-ledger.sh vocabulary) keeps
    # this retryable, matching landed|dead-only write-once semantics.
    _pc_dirty_evidence=""
    _pc_offending=""
    _pc_declared_list="$(_pc_join_capped "${writes[@]:-}")"
    if [[ -n "${_lane_root:-}" && -d "${_lane_root}" ]] && ! _pc_lane_root_is_own_worktree "${_lane_root}"; then
      # Never let porcelain from a parent repository become lane evidence.
      _pc_terminal="refused"; _pc_cause="lane_root_not_a_worktree"; _pc_rg_reason="lane_root_not_a_worktree"
      _pc_dirty_n=0
      _pc_offending=""
      _PC_LANE_RESOLVED_TOP="${_PC_LANE_TOPLEVEL:-<unresolved>}"
      _PC_LANE_PRODUCED="$(_pc_lane_produced_files "${_lane_root}")"
      _pc_dirty_evidence="lane_root=$(basename "${_lane_root}") resolved_toplevel=${_PC_LANE_RESOLVED_TOP} expected=${_lane_root} produced=${_PC_LANE_PRODUCED}"
    elif [[ -n "${_lane_root:-}" && -d "${_lane_root}" ]] && _pc_lane_dirty "${_lane_root}"; then
      # REVIEW-GATE-INFRA-01 D-A(ii): "the lane is dirty" is not itself the violation --
      # partition the dirty paths against the declared write-set. Only an UNDECLARED
      # dirty path is a genuine scope violation; unscoped_lane_work must fire ONLY then
      # (mission non-goal preserved verbatim). Declared-only dirt with zero diff bytes
      # is one of two innocent causes this reason used to swallow: the work legitimately
      # landed in a cross-repo sibling, or the declared path produced no bytes for a
      # reason that is not a scope violation.
      # SCOPE-GATE-ORCHESTRATION-DIRT-01: same exclusion set as _pc_lane_dirty above,
      # by construction — see the constant's comment for why the two must not diverge.
      # CTX-COST-GUARDS-01: same _pc_drop_bootstrap_dirt second stage as _pc_lane_dirty
      # above, by construction -- see its comment for why the two stages must not diverge.
      # Everything else stays strict: an undeclared path the worker actually wrote is
      # still a scope violation, and the partition below is what decides that.
      _pc_dirty_lines="$(git -C "${_lane_root}" status --porcelain --untracked-files=all 2>/dev/null | \
        grep -vE "${_PC_PORCELAIN_EXCLUDE_RE}" | _pc_drop_bootstrap_dirt "${_lane_root}")"
      _pc_dirty_n="$(printf '%s\n' "${_pc_dirty_lines}" | grep -vcE '^$' || true)"
      _pc_undeclared=()
      _pc_undeclared_n=0
      while IFS= read -r _pc_line; do
        [[ -z "${_pc_line}" ]] && continue
        _pc_p="${_pc_line:3}"
        # F4: a porcelain rename line reads "R  \"a b\" -> \"c d\"" — the path the work
        # actually landed at is the RIGHT side of " -> ", not the raw slice.
        _pc_p="${_pc_p##* -> }"
        _pc_p="${_pc_p%\"}"; _pc_p="${_pc_p#\"}"
        _pc_is_declared=0
        for _pc_w in "${writes[@]:-}"; do
          [[ -z "${_pc_w}" ]] && continue
          case "${_pc_p}" in
            "${_pc_w}"|"${_pc_w}"/*) _pc_is_declared=1; break ;;
          esac
        done
        if [[ ${_pc_is_declared} -eq 0 ]]; then
          _pc_undeclared+=("${_pc_p}")
          _pc_undeclared_n=$((_pc_undeclared_n + 1))
        fi
      done <<< "${_pc_dirty_lines}"
      _pc_dirty_evidence="lane_root=$(basename "${_lane_root}") dirty=${_pc_dirty_n}"
      [[ "$(_pc_phys "${_lane_root}")" == "$(_pc_phys "${ROOT}")" ]] && _pc_dirty_evidence="${_pc_dirty_evidence} lane_root_shared=1"
      if [[ ${_pc_undeclared_n} -gt 0 ]]; then
        _pc_terminal="refused"; _pc_cause="unscoped_lane_work"; _pc_rg_reason="unscoped_lane_work"
        _pc_offending="$(_pc_join_capped "${_pc_undeclared[@]}")"
      elif [[ "${CROSS_REPO_DIFF:-}" == "1" && ${_pc_unresolved_n:-0} -gt 0 ]]; then
        # F7: this branch only runs when blocked_reason==unscopable_diff, i.e. diff_file
        # is totally empty — a repo in _nonzero_repos would have contributed bytes there,
        # so ${_nonzero_repos:-0} -gt 0 can never be true here; dropped as dead.
        # F5: a dirty lane never stamps terminal=no_work — the terminal is `refused`
        # (retryable, same class); the diagnosis lives in `cause`/`reason` only.
        _pc_terminal="refused"; _pc_cause="cross_repo_elsewhere"; _pc_rg_reason="cross_repo_elsewhere"
      else
        _pc_terminal="refused"; _pc_cause="declared_no_bytes"; _pc_rg_reason="declared_no_bytes"
      fi
    else
      _pc_terminal="no_work"; _pc_cause="empty_diff"; _pc_rg_reason="no_work"
      if [[ -n "${_PC_ASKED_INTO_VOID:-}" && -f "${_PC_ASKED_INTO_VOID}" ]]; then
        _pc_cause="asked_into_void"
      fi
    fi
  fi
  # review-gate.md reason mirrors the ledger word so the on-disk artifact and the
  # row agree (was unscopable_diff for the empty case). base= names the diff base
  # (HEAD or an abbreviated start-sha) so a blocked lane is diagnosable without
  # re-running anything (S-3 round 3). dirty= (unscoped_lane_work only) records the
  # filtered porcelain line count that flipped this from no_work.
  # kind: (REPORT-ONLY-GATE-01) is the ONLY additive key on a blocked diff-lane
  # artifact: appended right after reason:, existing keys byte-identical, so the
  # dead-worker family (kind: diff) never reads like a report-lane family.
  # LANE-OBSERVABILITY-02: worker_reason: (the worker's own last words) joins
  # the same after-reason slot, ONLY on a no_work/dead terminal with a
  # non-empty extraction — every other shape of this artifact is byte-identical,
  # and every existing review-gate.md parser is a per-key grep (an unknown-key
  # line changes none of them).
  _pc_wr=""
  case "${_pc_terminal}" in
    no_work|dead) _pc_wr="$(_pc_worker_reason)" ;;
  esac
  if [[ -n "${_pc_dirty_evidence:-}" ]]; then
    {
      printf 'status: blocked\nreason: %s\n' "${_pc_rg_reason}"
      [[ -n "${_pc_wr}" ]] && printf 'worker_reason: %s\n' "${_pc_wr}"
      printf 'kind: %s\nbase: %s\ndirty: %s\n' \
        "${_pc_kind}" "${_pc_base_used:-HEAD}" "${_pc_dirty_n}"
      [[ -n "${_pc_declared_list:-}" ]] && printf 'declared_writes: %s\n' "${_pc_declared_list}"
      [[ -n "${_pc_offending:-}" ]] && printf 'offending: %s\n' "${_pc_offending}"
      [[ -n "${_PC_LANE_RESOLVED_TOP:-}" ]] && printf 'resolved_toplevel: %s\nexpected_lane_root: %s\n' "${_PC_LANE_RESOLVED_TOP}" "${_lane_root}"
      [[ -n "${_PC_LANE_PRODUCED:-}" ]] && printf 'produced: %s\n' "${_PC_LANE_PRODUCED}"
      [[ -n "${_PC_UNDIFFABLE_CSV:-}" ]] && printf 'undiffable: %s\n' "${_PC_UNDIFFABLE_CSV}"
    } > "${HANDOFF}/review-gate.md"
  else
    {
      printf 'status: blocked\nreason: %s\n' "${_pc_rg_reason}"
      [[ -n "${_pc_wr}" ]] && printf 'worker_reason: %s\n' "${_pc_wr}"
      printf 'kind: %s\nbase: %s\n' "${_pc_kind}" "${_pc_base_used:-HEAD}"
      [[ -n "${_PC_UNDIFFABLE_CSV:-}" ]] && printf 'undiffable: %s\n' "${_PC_UNDIFFABLE_CSV}"
    } > "${HANDOFF}/review-gate.md"
  fi
  _pc_offending_evt=""
  [[ -n "${_pc_offending:-}" ]] && _pc_offending_evt=" offending=${_pc_offending}"
  emit decision "review_gate task=${TASK} status=blocked reason=${_pc_rg_reason} terminal=${_pc_terminal} cause=${_pc_cause}${_pc_offending_evt}"
  _dl_note "${_pc_terminal}" "${_pc_cause}" "${_pc_dirty_evidence}${_pc_offending_evt}"
  _stamp_review_terminal blocked
  exit 5
fi
}

# N1-EMPTY-LANE-IS-NOT-A-PASS (C.3): resolve the worker's run dir the SAME way the
# status surface does (${RUNS_ROOT}/${arm}-runs/${handle}) so we can read the
# .asked_into_void marker the coder's finish guard writes. Empty when no handle/arm
# -> the asked-into-void cause never fires (degrades to empty_diff). Resolved ONCE
# here, before pc_scope_diff, so the empty-diff branch (cause asked_into_void) and
# the non-empty-diff branch (parked) below share one definition.
_pc_resolve_asked_into_void

# REVIEW-GATE-INFRA-01 D-A(i): bounce on a mechanically-undiffable write set BEFORE
# waiting on the worker -- see pc_precheck_writes above.
pc_precheck_writes

if ! pc_await_worker_exit; then
  _pc_reap_worker "$(_pc_run_dir_for "${AUTHOR}" "${HANDLE}")" "$(_pc_meta_value "$(_pc_run_dir_for "${AUTHOR}" "${HANDLE}")/meta.yaml" pid 2>/dev/null)"
  # HOLE-2 fix (V3-STOP-GATE-FINISH-01): a reaped/timed-out worker is the
  # likeliest producer of uncommitted work -- it never chose to stop -- so the
  # gate must fire here too, not only after the clean-exit wait below.
  # Capture the handoff artifact before that checkpoint advances HEAD. Run in
  # a SUBSHELL: pc_scope_diff `exit`s directly on its own no_work/blocked
  # verdicts (an empty diff is exactly the common shape of a worker reaped
  # before writing anything), and an unguarded call here would let that exit
  # terminate the whole script before the worker_timeout gate below ever
  # runs -- silently relabeling every such timeout as no_work. The subshell
  # contains that exit; review.diff/review-gate.md are still written to disk
  # as pc_scope_diff's normal side effect, and are overwritten by the
  # worker_timeout printf immediately below, same as before this fix.
# Capture-only snapshot (codex r3): scoped + untracked-inclusive + populates the
  # foreign-repo list for the gate's skip journal; no verdict/journal/ledger effects.
  pc_stop_gate_capture_diff
  pc_stop_gate_autocommit
  printf 'status: blocked\nreason: worker_timeout\nbase: %s\n' "${_pc_base_used:-HEAD}" > "${HANDOFF}/review-gate.md"
  emit decision "review_gate task=${TASK} status=blocked reason=worker_timeout terminal=dead cause=timeout"
  _dl_note dead timeout "waited=${_PC_WORKER_WAITED_S}s author=${AUTHOR} handle=${HANDLE}"
  _stamp_review_terminal blocked
  exit 5
fi

# GLM-DIED-WITH-WORK-RESUME-01: after the first worker exits, attempt one
# died-with-work resume.  On success, re-enter the wait for the second run;
# on any non-success, fall through to gating the partial diff exactly as today.
if pc_dwr_resume_once; then
  # Second wait with its own ceiling (LEADV2_PC_RESUME_MAX_WAIT_S, default
  # = first-wait budget).  The lease-refresh inside pc_await_worker_exit
  # keeps extending the claim across this second wait (R2).  Wall-clock
  # worst case doubles — documented in the script header.
  # Critic r1 HIGH: the second wait's timeout must be the same hard stop as the
  # first wait's -- `|| true` here would fall through to pc_scope_diff while the
  # resumed worker may still be writing (the exact race PREMATURE-NO-WORK-
  # TERMINAL-01 closed for the first wait).
  if ! LEADV2_PC_WORKER_MAX_WAIT_S="${LEADV2_PC_RESUME_MAX_WAIT_S:-${LEADV2_PC_WORKER_MAX_WAIT_S:-4200}}" \
      pc_await_worker_exit; then
    _pc_reap_worker "$(_pc_run_dir_for "${AUTHOR}" "${HANDLE}")" "$(_pc_meta_value "$(_pc_run_dir_for "${AUTHOR}" "${HANDLE}")/meta.yaml" pid 2>/dev/null)"
    # HOLE-2 fix (V3-STOP-GATE-FINISH-01): same reasoning as the first wait's
    # timeout branch above -- the resumed worker was also reaped, not exited
    # cleanly.
    # Capture the handoff artifact before that checkpoint advances HEAD.
  # Capture-only snapshot (codex r3): see pc_stop_gate_capture_diff.
    pc_stop_gate_capture_diff
    pc_stop_gate_autocommit
    printf 'status: blocked\nreason: worker_timeout\nbase: %s\n' "${_pc_base_used:-HEAD}" > "${HANDOFF}/review-gate.md"
    emit decision "review_gate task=${TASK} status=blocked reason=worker_timeout terminal=dead cause=timeout resumed=1"
    _dl_note dead timeout "waited=${_PC_WORKER_WAITED_S}s author=${AUTHOR} handle=${HANDLE} resumed=1"
    _stamp_review_terminal blocked
    exit 5
  fi
fi

# ARM-PRODUCES-NOTHING-AND-CHAIN-NEVER-ADVANCES-01 (Fix 1): resolve _lane_root the SAME
# way pc_scope_diff will below (idempotent -- that function recomputes the identical
# value) so the silent-arm probe can see the lane worktree BEFORE pc_scope_diff runs.
# Must run before pc_scope_diff: the probe classifies "worker exited, never engaged" as
# its own no_work cause, distinct from empty_diff/unscoped_lane_work, and those verdict
# paths must stay byte-identical -- unreached for a genuinely silent arm, never altered.
_lane_root="${LEADV2_LANE_WORK_ROOT:-}"
if [[ -z "${_lane_root}" || ! -d "${_lane_root}" ]]; then
  _lane_root="$(LEADV2_PROJECT_ROOT="${ROOT}" bash "${SCRIPT_DIR}/leadv2-lane-worktree.sh" path-of "${FOUNDER_TASK_ID:-${TASK}}" 2>/dev/null || true)"
fi

if pc_silent_arm_probe; then
  _pc_silent_evidence="arm=${AUTHOR} stream=${_PC_SILENT_STREAM_STATE} lane=${_PC_SILENT_LANE_BASENAME} commits_ahead=${_PC_SILENT_COMMITS_AHEAD:-0}"
  # LANE-OBSERVABILITY-02: this is exactly the stop whose journal used to say
  # only cause=arm_produced_nothing while the worker's rollout said why —
  # surface the worker's own words on the artifact too (omitted when empty,
  # same rule as the empty-diff writer above).
  _pc_wr="$(_pc_worker_reason)"
  {
    printf 'status: blocked\nreason: arm_produced_nothing\n'
    [[ -n "${_pc_wr}" ]] && printf 'worker_reason: %s\n' "${_pc_wr}"
    printf 'arm: %s\n' "${AUTHOR}"
  } > "${HANDOFF}/review-gate.md"
  emit decision "review_gate task=${TASK} status=blocked reason=arm_produced_nothing terminal=no_work cause=arm_produced_nothing arm=${AUTHOR}"
  _dl_note no_work arm_produced_nothing "${_pc_silent_evidence}"
  _pc_arm_advance
  _stamp_review_terminal blocked
  exit 5
fi

pc_scope_diff

# V3-STOP-GATE-01: capture the exit-time scoped diff before checkpointing.  A
# checkpoint advances HEAD, so doing this first preserves the worker's actual
# output for review.diff even when no recorded lane-start base is available.
# The checkpoint still precedes every downstream gate that reads the tree.
_pc_stop_gate_resolve_reason
pc_stop_gate_autocommit

# C.3: a NON-empty diff whose worker still asked into the void is parked, never
# landed -- work exists and a human answering the question unblocks it, which is
# exactly what parked means (ledger.sh taxonomy). pc_scope_diff already exited
# (no_work/asked_into_void) on the empty-diff case, so this only runs when there
# IS a diff. Belt-and-braces: review-gate.md mirrors the parked terminal too.
if [[ -n "${_PC_ASKED_INTO_VOID}" && -f "${_PC_ASKED_INTO_VOID}" ]]; then
  printf 'status: blocked\nreason: asked_into_void\nbase: %s\n' "${_pc_base_used:-HEAD}" > "${HANDOFF}/review-gate.md"
  emit decision "review_gate task=${TASK} status=blocked reason=asked_into_void terminal=parked cause=asked_into_void"
  _dl_note parked asked_into_void
  _stamp_review_terminal blocked
  exit 5
fi

# BUILDER-SELFCHECK-GATE-01: the builder must prove its own diff before any review
# arm is spent. Sits after pc_scope_diff (real bytes already confirmed) and before
# both e2e and review -- LEADV2_BUILDER_SELFCHECK=0 restores today's path byte-for-
# byte. A missing lib (R1, infra fault, not a lane fault) falls through unchanged --
# only a lib that RAN and produced a RED verdict blocks.
#
# Round-2 finding C3: the gate exists to protect a review arm from being spent on
# an unproven diff -- but ALSO to backstop a diff that no live worker ever ran its
# own checks against. Skip only when BOTH: (a) no downstream arm will run (neither
# e2e nor review is spent on this diff) AND (b) a live worker (HANDLE non-empty)
# already completed this diff -- decision from ask-lead escalation, option a: an
# empty HANDLE means there was no live worker at all (a direct/manual dispatch),
# so selfcheck is the ONLY safety net and must still run even with both arms off;
# test-builder-selfcheck-gate.sh's HANDLE="" cases assert exactly this. Likewise a
# report-only lane's deliverable is prose, not code -- bash -n / py_compile is a
# category error against it, not "checks=0 by construction" as the old comment
# assumed; nothing previously enforced that assumption.
if [[ "${LEADV2_BUILDER_SELFCHECK:-1}" != 0 ]] && command -v lv2_selfcheck_run >/dev/null 2>&1 \
   && [[ "${_pc_kind}" == "report" || ( "${E2E_ON}" == 0 && "${REVIEW_ON}" == 0 && -n "${HANDLE}" ) ]]; then
  if [[ "${_pc_kind}" == "report" ]]; then
    emit decision "selfcheck task=${TASK} status=skipped reason=report_lane"
  else
    emit decision "selfcheck task=${TASK} status=skipped reason=no_arm"
  fi
elif [[ "${LEADV2_BUILDER_SELFCHECK:-1}" != 0 ]] && command -v lv2_selfcheck_run >/dev/null 2>&1; then
  _selfcheck_md="${HANDOFF}/selfcheck.md"
  # R2: must NOT be `_selfcheck_failed="$(lv2_selfcheck_run ...)"` -- a command
  # substitution runs the function in a SUBSHELL, so the LV2_SELFCHECK_* globals it
  # sets would die with that subshell and never reach this scope. Redirect stdout to
  # a file instead so the function runs in THIS shell and its globals persist.
  _selfcheck_out_f="$(mktemp)"
  LEADV2_E2E_GATE="${E2E_ON}" lv2_selfcheck_run "${diff_file}" "${diff_root}" "${ROOT}" "${_selfcheck_md}" \
    "${_PC_SCOPE_WRITES_CSV:-${LEADV2_DISPATCH_LANE_WRITES:-}}" > "${_selfcheck_out_f}"
  _selfcheck_rc=$?
  _selfcheck_failed="$(cat "${_selfcheck_out_f}")"
  rm -f "${_selfcheck_out_f}"
  _selfcheck_fields="checks=${LV2_SELFCHECK_CHECKS:-0} skipped=${LV2_SELFCHECK_SKIPPED:-0}"
  [[ "${LV2_SELFCHECK_DEPTH_SKIP:-0}" == "1" ]] && _selfcheck_fields="${_selfcheck_fields} depth_guard=1"
  if [[ ${_selfcheck_rc} -eq 1 ]]; then
    IFS=',' read -r -a _selfcheck_failed_arr <<< "${_selfcheck_failed}"
    printf 'status: blocked\nreason: selfcheck_failed\nkind: %s\nbase: %s\nfailed: %s\nchecks: %s\nskipped: %s\nselfcheck: docs/handoff/dispatch-%s/selfcheck.md\n' \
      "${_pc_kind}" "${_pc_base_used:-HEAD}" "$(_pc_join_capped "${_selfcheck_failed_arr[@]}")" \
      "${LV2_SELFCHECK_CHECKS:-0}" "${LV2_SELFCHECK_SKIPPED:-0}" "${TASK}" > "${HANDOFF}/review-gate.md"
    emit decision "review_gate task=${TASK} status=blocked reason=selfcheck_failed terminal=refused cause=selfcheck_failed failed=${_selfcheck_failed} ${_selfcheck_fields}"
    _dl_note refused selfcheck_failed "failed=${_selfcheck_failed} ${_selfcheck_fields}"
    _stamp_review_terminal blocked
    exit 5
  fi
  emit decision "selfcheck task=${TASK} status=$([[ ${_selfcheck_rc} -eq 2 ]] && printf degraded || printf green) ${_selfcheck_fields}"
fi

_stamp_active_phase "${FOUNDER_TASK_ID}" "e2e"
# PHASES-ARE-THE-ONLY-PATH-01: record e2e phase as running.
[[ -x "${SCRIPT_DIR}/leadv2-phase-record.sh" ]] && \
  bash "${SCRIPT_DIR}/leadv2-phase-record.sh" record "${TASK}" e2e --status running \
    --handle "dispatch-${TASK}-e2e" \
    --task-id "${FOUNDER_TASK_ID}" --owner "$(basename "$0"):e2e_gate" 2>/dev/null || true
# C1 (GATE-WRONG-ROOT-FALSE-DEAD-01): validate the e2e root BEFORE running any
# suite. diff_root (the lane's worktree, resolved :796-802) is the single source
# of truth for "where the lane's code actually is" — reuse it, do not re-derive.
# On any failure: blocked (infrastructure fault), never dead (lane regression).
if [[ "${E2E_ON}" != 1 ]]; then
  emit decision "e2e_gate task=${TASK} status=disabled reason=kill_switch"
elif ! _lv2_e2e_resolve_root "${diff_root}" "${ROOT}"; then
  rm -f "${HANDOFF}/e2e-gate-passed.flag"
  printf 'status: blocked\nreason: %s\n' "${_lv2_e2e_root_reason}" > "${HANDOFF}/e2e-gate.md"
  emit decision "e2e_gate task=${TASK} status=blocked reason=${_lv2_e2e_root_reason}"
  _dl_note refused "${_lv2_e2e_root_reason}"
  exit 4
elif ! e2e_cmd="$(bash "${SCRIPT_DIR}/leadv2-e2e-entrypoint.sh" "${_lv2_e2e_root}")"; then
  repo="$(basename "${_lv2_e2e_root}")"
  printf 'status: blocked\nreason: no_e2e_entrypoint\nrepo: %s\n' "${repo}" > "${HANDOFF}/e2e-gate.md"
  rm -f "${HANDOFF}/e2e-gate-passed.flag"
  emit decision "e2e_gate task=${TASK} status=blocked reason=no_e2e_entrypoint repo=${repo}"
  _dl_note refused no_e2e_entrypoint "repo=${repo}"
  exit 4
else
  { printf 'e2e-root: %s\n' "${_lv2_e2e_root}"; ( cd "${_lv2_e2e_root}" && bash -c "${e2e_cmd} --scope changed" ); } > "${HANDOFF}/e2e-gate.log" 2>&1; e2e_rc=$?
  # GATE-FOREIGN-FAILURE-01: WRITES_CSV present + ownership enabled means the
  # passed sentinel is stamped as scoped to the lane's own write set (the
  # apparatus that can tell "my regression" from "someone else's unfinished
  # file" is active for this lane), never a behavioural difference on green.
  _e2e_ownership="${LEADV2_E2E_OWNERSHIP:-1}"
  _e2e_pass_scope="changed"
  [[ "${_e2e_ownership}" == "1" && -n "${WRITES_CSV}" ]] && _e2e_pass_scope="lane_writes"
  if [[ ${e2e_rc} -eq 0 ]]; then
    printf 'e2e-gate-passed: %s\nasserted_at: %s\nscope: %s\nbypassed: false\n' \
      "${TASK}" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "${_e2e_pass_scope}" > "${HANDOFF}/e2e-gate-passed.flag"
    emit decision "e2e_gate task=${TASK} status=ran verdict=pass"
  else
    rm -f "${HANDOFF}/e2e-gate-passed.flag"
    emit decision "e2e_gate task=${TASK} status=ran verdict=fail rc=${e2e_rc}"
    # GATE-FOREIGN-FAILURE-01: four lanes died 2026-07-31 05:06-05:19Z on a
    # suite none of them touched -- it was mid-edit by a fifth lane in the
    # SAME shared working tree. Before treating every blocking failure as
    # this lane's own regression, classify by ownership (differential re-run
    # against a lane-only scratch tree, see leadv2-e2e-ownership.sh). Own
    # failures ALWAYS win over foreign ones -- a lane can never launder its
    # own regression behind someone else's unfinished file.
    _own_csv=""; _foreign_csv=""; _undecidable_csv=""; _owner_lane="unknown"
    if [[ "${_e2e_ownership}" == "1" && -n "${WRITES_CSV}" ]]; then
      # C1 (GATE-WRONG-ROOT-FALSE-DEAD-01): pass the validated e2e root
      # (the lane's worktree) so the overlay copies the lane's ACTUAL working
      # tree state, not the main checkout's committed values.
      _own_out="$(bash "${SCRIPT_DIR}/leadv2-e2e-ownership.sh" "${_lv2_e2e_root}" "${TASK}" "${WRITES_CSV}" "${HANDOFF}/e2e-gate.log" 2>/dev/null || true)"
      _own_csv="$(sed -n 's/^own=//p' <<< "${_own_out}")"
      _foreign_csv="$(sed -n 's/^foreign=//p' <<< "${_own_out}")"
      _undecidable_csv="$(sed -n 's/^undecidable=//p' <<< "${_own_out}")"
      _owner_lane="$(sed -n 's/^owner_lane=//p' <<< "${_own_out}")"
      [[ -z "${_owner_lane}" ]] && _owner_lane="unknown"
    fi

    if [[ -n "${_foreign_csv}" && -z "${_own_csv}" && -z "${_undecidable_csv}" ]]; then
      # Pure foreign failure: not a single blocking suite reproduces against
      # this lane's own write set alone. Do NOT kill the lane -- but never
      # swallow the red suite silently either (loudness contract below).
      IFS=',' read -r -a _lane_writes <<< "${WRITES_CSV}"
      mapfile -t _all_changed < <(
        { git -C "${_lv2_e2e_root}" diff --name-only HEAD -- ':(exclude)docs/leadv2' ':(exclude)docs/handoff' 2>/dev/null
          git -C "${_lv2_e2e_root}" ls-files --others --exclude-standard -- ':(exclude)docs/leadv2' ':(exclude)docs/handoff' 2>/dev/null; } | sort -u
      )
      _foreign_files=()
      for _f in "${_all_changed[@]}"; do
        [[ -z "${_f}" ]] && continue
        _is_write=0
        for _w in "${_lane_writes[@]}"; do [[ "${_f}" == "${_w}" ]] && { _is_write=1; break; }; done
        (( _is_write )) || _foreign_files+=("${_f}")
      done
      _foreign_files_csv="$(IFS=,; echo "${_foreign_files[*]:-}")"
      printf 'e2e-gate-passed: %s\nasserted_at: %s\nscope: lane_writes\nbypassed: false\nforeign_failures: %s\n' \
        "${TASK}" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "${_foreign_csv}" > "${HANDOFF}/e2e-gate-passed.flag"
      printf 'status: fail_foreign\nreason: foreign_failure\nforeign_suites: %s\nforeign_files: %s\nowner_lane: %s\n' \
        "${_foreign_csv}" "${_foreign_files_csv}" "${_owner_lane}" > "${HANDOFF}/e2e-gate.md"
      emit decision "e2e_gate task=${TASK} status=ran verdict=foreign_failure scope=lane_writes foreign_suites=${_foreign_csv} foreign_files=${_foreign_files_csv} owner_lane=${_owner_lane} own_failures=0"
      IFS=',' read -r -a _foreign_suite_arr <<< "${_foreign_csv}"
      for _s in "${_foreign_suite_arr[@]}"; do
        [[ -z "${_s}" ]] && continue
        emit decision "foreign_failure task=${TASK} suite=${_s} file=${_foreign_files_csv} owner_lane=${_owner_lane}"
      done
      # NOT dead, NOT exit 8 -- falls through to the review gate below.
    else
      # wave2 finding 6: an e2e regression is a `dead` outcome in the ledger taxonomy --
      # falling through into the review gate below (which CAN end in `landed`) let a real
      # regression be finalized as delivered. Distinct from the kill-switch branch above
      # (E2E_ON!=1 is a deliberate disabled state, never a failure) -- this only fires when
      # the gate actually RAN and reported a real non-zero verdict.
      if [[ "${_e2e_ownership}" == "1" && -z "${WRITES_CSV}" ]]; then
        printf 'status: fail\nreason: e2e_regression\nrc: %s\nscope: whole_tree_fallback\n' "${e2e_rc}" > "${HANDOFF}/e2e-gate.md"
      else
        printf 'status: fail\nreason: e2e_regression\nrc: %s\n' "${e2e_rc}" > "${HANDOFF}/e2e-gate.md"
      fi
      _dl_note dead e2e_regression "rc=${e2e_rc}"
      exit 8
    fi
  fi
fi

_stamp_active_phase "${FOUNDER_TASK_ID}" "review"
# PHASES-ARE-THE-ONLY-PATH-01: record review phase as running.
[[ -x "${SCRIPT_DIR}/leadv2-phase-record.sh" ]] && \
  bash "${SCRIPT_DIR}/leadv2-phase-record.sh" record "${TASK}" review --status running \
    --handle "dispatch-${TASK}-review" \
    --task-id "${FOUNDER_TASK_ID}" --owner "$(basename "$0"):review_gate" 2>/dev/null || true
# ONE-PATH-EVERYWHERE-01: when LEADV2_REVIEW_ENGINE=1, this lane's whole inline review
# body (below) is replaced by a call to the sole-owner engine, leadv2-review-run.sh.
# Flag DEFAULTS TO 0 -- when unset (the production default, everywhere, per the rollout
# plan) the lane falls through unchanged into the original inline body byte-for-byte.
# The lane still owns its process model / EXIT trap / _stamp_review_terminal /
# review_crashed fallback -- the engine itself never calls those (it is a bare,
# self-contained script callable with none of this lane's helper functions loaded).
if [[ "${LEADV2_REVIEW_ENGINE:-0}" == "1" ]]; then
  if [[ "${REVIEW_ON}" != 1 ]]; then
    emit decision "review_gate task=${TASK} status=disabled reason=kill_switch"
    _dl_note landed review_gate_disabled
    exit 0
  fi
  _PC_REVIEW_ENTERED=1
  _ENGINE_BIN="${LEADV2_REVIEW_RUN_BIN:-${SCRIPT_DIR}/leadv2-review-run.sh}"
  bash "${_ENGINE_BIN}" --task "${TASK}" --root "${ROOT}" --handoff "${HANDOFF}" --diff "${diff_file}" --author "${AUTHOR}"
  _engine_rc=$?
  case ${_engine_rc} in
    0)
      _dl_note landed review_verdict_pass "engine=1"
      _stamp_review_terminal pass
      [[ -x "${SCRIPT_DIR}/leadv2-phase-record.sh" ]] && \
        bash "${SCRIPT_DIR}/leadv2-phase-record.sh" record "${TASK}" review --status done \
          --artifact "docs/handoff/dispatch-${TASK}/review-gate.md" \
          --task-id "${FOUNDER_TASK_ID}" --owner "$(basename "$0"):review_gate" 2>/dev/null || true
      ;;
    7) _dl_note dead review_verdict_fail "engine=1"; _stamp_review_terminal fail ;;
    8) _dl_note dead review_roundcap "engine=1 rc=${_engine_rc}"; _stamp_review_terminal blocked ;;
    6) _dl_note dead review_blocked "engine=1 rc=${_engine_rc}"; _stamp_review_terminal blocked ;;
    9) _dl_note dead all_arms_unavailable "engine=1"; _stamp_review_terminal unreviewed ;;
    *) _dl_note dead review_engine_error "engine=1 rc=${_engine_rc}"; _stamp_review_terminal blocked ;;
  esac
  exit ${_engine_rc}
fi

if [[ "${REVIEW_ON}" != 1 ]]; then
  emit decision "review_gate task=${TASK} status=disabled reason=kill_switch"
  _dl_note landed review_gate_disabled
  exit 0
fi
# N-5 D3: from this point on the review phase is genuinely entered -- the EXIT trap
# backstop (_pc_exit_handler above) now guarantees review-gate.md exists on every exit
# path, including a crash this script never explicitly handles.
_PC_REVIEW_ENTERED=1

# dispatch-00629379: resolved via the pool resolver (job=review, base-arm=codex,
# --review-pool --author) -- see resolve_review_pool_call() above. The pool already
# excludes AUTHOR and orders codex > glm > opus > sonnet by live quota headroom; an
# empty reviewer here means every arm in the pool was genuinely unavailable (quota or
# author-collision), which IS a finding -- it must never silently skip the gate.
resolver_out="$(resolve_review_pool_call)"
reviewer="$(printf '%s\n' "${resolver_out}" | sed -n 's/^reviewer=//p' | head -n1)"
pool="$(printf '%s\n' "${resolver_out}" | sed -n 's/^pool=//p' | head -n1)"
refusal="$(printf '%s\n' "${resolver_out}" | sed -n 's/^refusal=//p' | head -n1)"
resolver_rc="$(printf '%s\n' "${resolver_out}" | sed -n 's/^resolver_rc=//p' | head -n1)"
resolver_stderr="$(printf '%s\n' "${resolver_out}" | sed -n 's/^resolver_stderr=//p' | head -n1)"
source "${SCRIPT_DIR}/lib/leadv2-review-reroute-note.sh"
_reroute_note="$(leadv2_review_reroute_note "${TASK}" "${pool}" "${reviewer}")"
[[ -n "${_reroute_note}" ]] && emit decision "${_reroute_note}"
# Defense-in-depth (R9): the resolver already filters the author out of its pool, but
# a reviewer==author slip (stale cache, a launcher default) must never reach a live
# self-review -- assert it here too rather than trusting a single enforcement point.
if [[ -n "${reviewer}" && "${reviewer}" == "${AUTHOR}" ]]; then
  refusal="reviewer_equals_author"
  reviewer=""
fi
if [[ -z "${reviewer}" ]]; then
  # N-5 D1/D5: the resolver found nobody at all -- the SAME "unreviewed, not silently
  # landed" shape as the fallback loop below exhausting the pool, just zero arms ever
  # attempted. This used to be `status: no_reviewer` / exit 0, indistinguishable from
  # success to anything reading the exit code (which nothing does -- D2) or the ledger
  # (which recorded `parked`, not a failure state).
  refusal="${refusal:-all_review_arms_unavailable}"
  _pc_write_unreviewed "${refusal}" "${pool}" "" "${resolver_rc}" "${resolver_stderr}"
  exit 9
fi

diff_hash="$(shasum -a 256 "${diff_file}" | awk '{print $1}')"
# Dedup is checked BEFORE spending a second provider. record-review below remains the
# atomic writer that resolves a concurrent race; in that case the duplicate result is also
# journaled instead of masquerading as a new review.
ledger="${LEADV2_DISPATCH_CACHE_DIR:-${HOME}/.claude/cache}/review-ledger/$(basename "${ROOT}").jsonl"
if [[ -f "${ledger}" ]] && grep -qF "\"diff_hash\":\"${diff_hash}\"" "${ledger}"; then
  emit decision "review_gate task=${TASK} status=dedup diff=${diff_hash:0:8}"
  _dl_note landed review_dedup "diff=${diff_hash:0:8}"
  exit 0
fi
# KIMI-CHANNEL-01b §2.3.1-2.3.2: the reviewer launcher is now a function so the new
# kimi arm can be added WITHOUT touching the codex/glm/opus/sonnet branches. The
# per-arm output/err paths move inside it keyed on ${arm} (was review-${reviewer}).
# No behaviour change for the existing four arms -- a pure move + one new kimi branch.
run_reviewer_arm() { # <arm>
  local arm="$1"
  review_out="${HANDOFF}/review-${arm}.md"
  review_err="${HANDOFF}/review-${arm}.err"
  mission_file="${HANDOFF}/review-mission.md"
  if [[ "${arm}" == codex ]]; then
    bash "${LEADV2_DISPATCH_CODEX_BIN:-${SCRIPT_DIR}/codex-task.sh}" adversarial-review --base HEAD --wait \
      --focus "${_pc_review_intro} You are independent of the author (${AUTHOR}). Report correctness findings by severity (Critical / High / Medium / Low). ${review_contract}" \
      > "${review_out}" 2> "${review_err}"; review_rc=$?
  elif [[ "${arm}" == glm ]]; then
    # dispatch-00629379: new branch -- GLM is now a valid reviewer arm (founder decision
    # 2026-07-30, gated at its own 90% review threshold by the resolver above, never a
    # blind fallback). Primary channel glm-coder.sh; second channel omp-task.sh when the
    # per-repo glm-coder.sh lock is busy (exit 75), per CLAUDE.md Model routing v2. Both
    # must land the SAME REVIEW_VERDICT:/REVIEW_FINDINGS: contract in ${review_out} that
    # parse_review_verdict() below already enforces for every other reviewer branch.
    printf '%s You are independent of the author (%s).\nReport correctness findings by severity (Critical / High / Medium / Low).\n%s\n' \
      "${_pc_review_intro}" "${AUTHOR}" "${review_contract}" > "${mission_file}"
    glm_bin="${LEADV2_DISPATCH_GLM_BIN:-${SCRIPT_DIR}/glm-coder.sh}"
    omp_bin="${LEADV2_DISPATCH_OMP_BIN:-${ROOT}/.claude/leadv2-overrides/omp-task.sh}"
    review_rc=75
    if [[ -x "${glm_bin}" ]]; then
      bash "${glm_bin}" run "@${mission_file}" --out "${review_out}" --cwd "${ROOT}" >/dev/null 2> "${review_err}"
      review_rc=$?
    fi
    if [[ ${review_rc} -eq 75 && -x "${omp_bin}" ]]; then
      omp_run_id="$(bash "${omp_bin}" task "$(cat "${mission_file}")" --dir "${ROOT}" 2>> "${review_err}")"
      if [[ -n "${omp_run_id}" ]]; then
        omp_status=""
        omp_waited=0
        while (( omp_waited < 900 )); do
          omp_status="$(bash "${omp_bin}" status "${omp_run_id}" 2>/dev/null)"
          [[ "${omp_status}" == status=done* || "${omp_status}" == status=failed* ]] && break
          sleep 5
          omp_waited=$((omp_waited + 5))
        done
        cat "/tmp/omp-task-${omp_run_id}.log" > "${review_out}" 2>/dev/null || true
        [[ "${omp_status}" == status=done* ]] && review_rc=0 || review_rc=1
      fi
    fi
  elif [[ "${arm}" == kimi ]]; then
    # KIMI-CHANNEL-01b: kimi joins the review pool between glm and opus/sonnet (cheap
    # free voice, probe-gated by the resolver above). Same REVIEW_VERDICT:/REVIEW_FINDINGS:
    # contract as every other branch. kimi-coder.sh `probe` is lock-free (GET /v1/models
    # only) and `run` blocks, so this is a straight two-step: probe first, then run.
    # rc 77 (channel down) and rc 75 (lock/secret/usage) are BOTH admission refusals --
    # there is no omp-task.sh second channel for kimi (that is a GLM-lock construct), so
    # either rc is handled by the one-shot re-selection at the call site below, never here.
    printf '%s You are independent of the author (%s).\nReport correctness findings by severity (Critical / High / Medium / Low).\n%s\n' \
      "${_pc_review_intro}" "${AUTHOR}" "${review_contract}" > "${mission_file}"
    kimi_bin="${LEADV2_DISPATCH_KIMI_BIN:-${SCRIPT_DIR}/kimi-coder.sh}"
    if ! bash "${kimi_bin}" probe >/dev/null 2> "${review_err}"; then
      review_rc=77
      return
    fi
    bash "${kimi_bin}" run "@${mission_file}" --out "${review_out}" --cwd "${ROOT}" >/dev/null 2> "${review_err}"
    review_rc=$?
  else
    # sonnet or opus (R1 fix: launcher must pass the RESOLVED arm, not a hardcoded
    # model -- the old `--model sonnet` here meant a resolver that returned opus still
    # ran sonnet, a lying-green review).
    printf '%s You are independent of the author (%s).\nReport correctness findings by severity (Critical / High / Medium / Low).\n%s\n' \
      "${_pc_review_intro}" "${AUTHOR}" "${review_contract}" > "${mission_file}"
    PROJECT_ROOT="${ROOT}" bash "${LEADV2_DISPATCH_ARCHITECT_BIN:-${SCRIPT_DIR}/claude-subsession.sh}" --role critic --model "${arm}" --task-id "dispatch-${TASK}-review" --mission-file "${mission_file}" --wait \
      > "${review_out}" 2> "${review_err}"; review_rc=$?
    # REVIEW-BODY-PERSIST-01: the subsession prints only a label line on stdout; the
    # real body is in the deliverable files.  Materialise it into review_out so a human
    # can read the findings next to the verdict counts.  rc==0 means the subsession
    # itself succeeded; do not clobber a genuine error rc.
    if [[ ${review_rc} -eq 0 ]]; then
      materialize_subsession_body "${review_out}" "${REVIEW_STAMP}" "${TASK}" || true
    fi
  fi
}

# KIMI-CHANNEL-01b §2.3.3, generalised by N-5 §2.3: read the first entry AFTER
# <after-arm> whose disposition is :ok: in the already-computed ${pool} (comma-joined,
# e.g. codex:blocked:100,glm:ok:,...). Prints the arm name on stdout, exit 1 if none.
# Used by the arm-agnostic fallback loop below -- a forward-only walk of a FIXED pool,
# so repeated calls can visit each arm at most once and the loop always terminates.
next_ok_arm_after() { # <after-arm>  reads ${pool}
  local after="$1" found=0 entry arm
  local _pool="${pool}"
  local IFS=','
  for entry in ${_pool}; do
    arm="${entry%%:*}"
    if [[ "${found}" == "1" && "${entry}" == "${arm}:ok:"* ]]; then
      printf '%s' "${arm}"
      return 0
    fi
    [[ "${arm}" == "${after}" ]] && found=1
  done
  return 1
}

# ARM-NO-VERDICT-01 (dispatch-4fb7381a): companion to next_ok_arm_after -- counts how
# many :ok: arms remain in the FIXED ${pool} after <after-arm>, without consuming one.
# Purely informational (the `remaining=<n>` field on the arm_no_verdict journal line),
# never used for loop control -- next_ok_arm_after / the tried[] cap still own that.
_pc_remaining_ok_after() { # <after-arm>  reads ${pool}  -> prints count on stdout
  local after="$1" found=0 entry arm count=0
  local _pool="${pool}"
  local IFS=','
  for entry in ${_pool}; do
    arm="${entry%%:*}"
    if [[ "${found}" == "1" && "${entry}" == "${arm}:ok:"* ]]; then
      count=$((count + 1))
    fi
    [[ "${arm}" == "${after}" ]] && found=1
  done
  printf '%s' "${count}"
}

review_adir="${ROOT}/docs/handoff/dispatch-${TASK}-review"
mkdir -p "${review_adir}"
# REVIEW-GATE-INFRA-01 D-B: persist the arm's review body to a STABLE path in
# review_adir BEFORE any verdict parsing or loss classification runs, so a lost-stream
# retry and a lost-body event both have a real file to point at instead of the dead
# stream. review_out is already redirected to ${HANDOFF}/review-<arm>.md by
# run_reviewer_arm, but that lives under the task's OWN handoff dir, not review_adir --
# copy it here under a name (`review-<arm>.md`) that cannot collide with the
# claude-subsession-written `critic.*.md` names resolve_review_artifact consumes.
# Always writes, including a zero-byte body -- a zero-byte file IS the evidence a
# lost-body event needs.
pc_persist_review_body() { # <arm> <src>
  local arm="$1" src="$2"
  local dest="${review_adir}/review-${arm}.md"
  local bytes=0
  if [[ -f "${src}" ]]; then
    bytes="$(wc -c < "${src}" 2>/dev/null | tr -d '[:space:]')"; bytes="${bytes:-0}"
  fi
  cp -f "${src}" "${dest}" 2>/dev/null || : > "${dest}"
  PC_PERSISTED_REVIEW_BODY="${dest}"
  PC_PERSISTED_REVIEW_BYTES="${bytes}"
}
REVIEW_STAMP="${HANDOFF}/.review-start.stamp"
touch "${REVIEW_STAMP}"
review_contract=$'Your review MUST contain these two lines, verbatim format, before any prose:\nREVIEW_VERDICT: <FAIL|PASS|PASS_WITH_NITS>\nREVIEW_FINDINGS: critical=<n> high=<n> medium=<n> low=<n>\nFAIL if any Critical or High finding. PASS if the diff is clean. PASS_WITH_NITS otherwise.'
# REPORT-ONLY-GATE-01: a report lane substitutes the review body (diff_file now holds
# the report text) but runs the UNMODIFIED review path — so the mission must tell the
# reviewer it is judging prose, and what judging prose means. The verdict-marker
# contract above is appended to verbatim; every existing renderer/guard downstream is
# untouched. Diff lanes resolve _pc_review_intro to today's exact sentence.
_pc_review_intro="Review ONLY the diff at ${diff_file}."
if [[ "${_pc_kind}" == "report" ]]; then
  _pc_review_intro="This is a REPORT-ONLY lane. Review ONLY the analysis document at ${diff_file} (it begins with a '# REPORT-ONLY LANE' header naming the deliverable)."
  review_contract="${review_contract}
PROSE RUBRIC (report-only lane — the file is an ANALYSIS, not a diff): (a) is every load-bearing claim backed by a quoted file/line reference or command output included in the report itself; (b) list every unsupported claim explicitly as a finding; (c) state whether the recommendation follows from the evidence presented; (d) emit the same REVIEW_VERDICT:/REVIEW_FINDINGS: markers as a code review. FAIL if any load-bearing claim is unsupported or the recommendation does not follow from the evidence."
fi

# N-5 §2.3: arm-agnostic refusal fallback, generalising the old kimi-only bounded
# re-selection (KIMI-CHANNEL-01b) to every arm. A peak_hours/quota/channel-down refusal
# from ANY arm now walks forward through the resolver's own pre-ordered, quota-filtered,
# author-excluding pool instead of vanishing into the old silent no_reviewer/exit 0
# (D1, D5) -- a GLM peak_hours refusal used to fall straight through to a garbage/empty
# review-glm.md with no fallback attempted at all. Bounded two ways: next_ok_arm_after
# walks the FIXED ${pool} strictly forward (each arm visited at most once) AND an
# explicit tried[] cap belt-and-braces the loop -- it cannot spin.
# dispatch-8e2a32be D5: PC_TRIED is appended BEFORE run_reviewer_arm is called (not
# after classifying its outcome), so a mid-review crash inside run_reviewer_arm still
# leaves this arm recorded as attempted -- "tried" means "the gate actually invoked
# this arm's launcher", not "this arm refused cleanly and returned control".
PC_TRIED=()
_pc_unavailable=0
_pc_exhaust_kind=""
while :; do
  PC_TRIED+=("${reviewer}")
  # ARM-NO-VERDICT-01: reset the freshness baseline before EVERY arm's run, not just
  # once before the loop. resolve_review_artifact() below admits any critic.full.md
  # newer than REVIEW_STAMP -- with a single pre-loop stamp, a second arm that never
  # writes its own artifact (codex/glm/kimi) would silently inherit a FIRST arm's
  # (opus/sonnet) stale-but-still-fresh-relative-to-the-old-stamp file.
  touch "${REVIEW_STAMP}"
  run_reviewer_arm "${reviewer}"
  pc_persist_review_body "${reviewer}" "${review_out}"
  cls="$(classify_arm_failure "${review_rc}" "${review_err}" "${review_out}")"
  if [[ "${cls}" == refused_* ]]; then
    emit decision "review_gate task=${TASK} status=arm_refused arm=${reviewer} reason=${cls}"
    if [[ ${#PC_TRIED[@]} -ge 4 ]]; then
      _pc_unavailable=1
      _pc_exhaust_kind="refused"
      break
    fi
    # R9 defense-in-depth (kept from the kimi-only version): the re-selected arm is
    # re-checked against the author too, not just trusted from the resolver's pool.
    next_arm="$(next_ok_arm_after "${reviewer}" || true)"
    if [[ -z "${next_arm}" || "${next_arm}" == "${AUTHOR}" ]]; then
      _pc_unavailable=1
      _pc_exhaust_kind="refused"
      break
    fi
    reviewer="${next_arm}"
    continue
  fi

  # REVIEW-BODY-PERSIST-01 §2.2: shared post-arm guard. A paid review whose body
  # was lost (rc==0 but review_out has no REVIEW_VERDICT: marker AND is below the
  # byte floor) while evidence of real output exists must surface as a blocked
  # failure, not silence.  This MUST run before resolve_review_artifact() below --
  # the deliverable fallback would otherwise mask a lost body into a silent
  # pass-through, the exact shape of the 2026-08-03 incident.  review_body_lost is
  # NOT a refused_* class: it does not trigger re-selection to another arm -- unlike
  # ARM-NO-VERDICT-01 below, there IS positive evidence (stderr/cost) that real
  # provider spend happened here, so silently burning a second arm's budget on a
  # transport bug would be the wrong fix.
  if [[ ${review_rc} -eq 0 ]]; then
    _pc_body_min="${LEADV2_REVIEW_BODY_MIN_BYTES:-300}"
    _pc_body_bytes="0"
    _pc_body_bytes="$(wc -c < "${review_out}" 2>/dev/null | tr -d '[:space:]')"; _pc_body_bytes="${_pc_body_bytes:-0}"
    if ! grep -q '^[[:space:]]*REVIEW_VERDICT:' "${review_out}" 2>/dev/null && [[ "${_pc_body_bytes}" -lt "${_pc_body_min}" ]]; then
      # Evidence-of-real-output: non-empty stderr or a cost-recorded line in it.
      if [[ -s "${review_err}" ]] || grep -q 'cost recorded:' "${review_err}" 2>/dev/null; then
        _pc_persisted_rel="${PC_PERSISTED_REVIEW_BODY#"${ROOT}"/}"
        printf 'status: blocked\nreason: review_body_lost\narm: %s\nbody: %s\nbytes: %s\n' \
          "${reviewer}" "${_pc_persisted_rel}" "${PC_PERSISTED_REVIEW_BYTES:-0}" > "${HANDOFF}/review-gate.md"
        emit decision "review_gate task=${TASK} status=blocked reason=review_body_lost arm=${reviewer} body=${_pc_persisted_rel} bytes=${PC_PERSISTED_REVIEW_BYTES:-0}"
        _dl_note dead review_body_lost "arm=${reviewer} bytes=${_pc_body_bytes} body=${_pc_persisted_rel}"
        _stamp_review_terminal blocked
        exit 6
      fi
    fi
  fi

  # ARM-NO-VERDICT-01 (dispatch-4fb7381a): a reviewer that runs to completion (cls==
  # "ran", not a refusal, and not review_body_lost -- that guard above already exited
  # on the one case with positive evidence of lost spend) but produces output the gate
  # cannot use -- a provider error, sub-floor/empty output, or real prose with no
  # REVIEW_VERDICT: marker (e.g. a transcript ending in "[Tool use interrupted]") -- is
  # EXACTLY as much "this arm produced nothing usable" as a refused_* arm. The pool
  # resolver already ordered 3-5 quota-eligible arms for this task; killing the lane on
  # the FIRST arm's truncation when others were resolved and available (lane 4fb7381a,
  # 2026-08-07: reviewer=kimi, pool_n=5, dead on arm #1) is the defect this block fixes.
  # Same tried[]/next_ok_arm_after bookkeeping as the refused_* branch above; only the
  # reason vocabulary (provider_error/empty_response/no_verdict_marker) differs, and it
  # is preserved verbatim from the pre-fallthrough N-5 D4 split below.
  resolve_review_artifact || true
  review_file="${REVIEW_ARTIFACT:-${review_out}}"
  _pc_no_verdict_reason=""
  if [[ ${review_rc} -ne 0 && -z "${REVIEW_ARTIFACT}" ]]; then
    _pc_no_verdict_reason="provider_error"
  elif [[ ! -s "${review_file}" ]] || ! review_floor_ok "${review_file}"; then
    _pc_no_verdict_reason="empty_response"
  elif ! parse_review_verdict "${review_file}"; then
    # REVIEW-GATE-INFRA-01 D-B(iii): marker-recovery retry -- the first parse can miss
    # the verdict marker when review_file resolved to a dead stream (REVIEW_ARTIFACT
    # empty, review_out truncated); the persisted body from pc_persist_review_body is a
    # stable copy that outlives the stream. Retry once against it before giving up.
    if [[ -n "${PC_PERSISTED_REVIEW_BODY:-}" && "${review_file}" != "${PC_PERSISTED_REVIEW_BODY}" \
          && -s "${PC_PERSISTED_REVIEW_BODY}" ]] && parse_review_verdict "${PC_PERSISTED_REVIEW_BODY}"; then
      VERDICT_SOURCE="recovered_body"
      review_file="${PC_PERSISTED_REVIEW_BODY}"
      emit decision "review_gate task=${TASK} status=verdict_recovered arm=${reviewer} from=${PC_PERSISTED_REVIEW_BODY#"${ROOT}"/}"
    else
      _pc_no_verdict_reason="no_verdict_marker"
    fi
  fi

  if [[ -n "${_pc_no_verdict_reason}" ]]; then
    _pc_tried_csv="$(IFS=,; echo "${PC_TRIED[*]:-}")"
    _pc_remaining="$(_pc_remaining_ok_after "${reviewer}")"
    emit decision "review_gate task=${TASK} status=arm_no_verdict arm=${reviewer} reason=${_pc_no_verdict_reason} tried=${_pc_tried_csv} remaining=${_pc_remaining}"
    if [[ ${#PC_TRIED[@]} -ge 4 ]]; then
      _pc_unavailable=1
      _pc_exhaust_kind="no_verdict"
      break
    fi
    next_arm="$(next_ok_arm_after "${reviewer}" || true)"
    if [[ -z "${next_arm}" || "${next_arm}" == "${AUTHOR}" ]]; then
      _pc_unavailable=1
      _pc_exhaust_kind="no_verdict"
      break
    fi
    reviewer="${next_arm}"
    continue
  fi

  break
done
if [[ "${_pc_unavailable}" == "1" ]]; then
  _pc_tried_csv="$(IFS=,; echo "${PC_TRIED[*]:-}")"
  if [[ "${_pc_exhaust_kind}" == "no_verdict" ]]; then
    # Pool genuinely exhausted -- every arm ran but produced nothing usable. Keep the
    # SAME terminal cause (no_verdict_marker) the pre-fallthrough code used for this
    # exit path so downstream terminal-state consumers see no behaviour change for the
    # exhausted case, only the new per-arm arm_no_verdict lines and the full tried= list
    # attached to the death itself (dispatch-4fb7381a: reviewer never advanced past
    # kimi, so tried= could only ever show one name -- this is the fix's proof).
    _pc_persisted_rel="${PC_PERSISTED_REVIEW_BODY#"${ROOT}"/}"
    printf 'status: blocked\nreason: no_verdict_marker\nbody: %s\nbytes: %s\n' \
      "${_pc_persisted_rel}" "${PC_PERSISTED_REVIEW_BYTES:-0}" > "${HANDOFF}/review-gate.md"
    emit decision "review_gate task=${TASK} status=blocked reason=no_verdict_marker tried=${_pc_tried_csv} body=${_pc_persisted_rel} bytes=${PC_PERSISTED_REVIEW_BYTES:-0}"
    _dl_note dead no_verdict_marker "tried=${_pc_tried_csv} body=${_pc_persisted_rel} bytes=${PC_PERSISTED_REVIEW_BYTES:-0}"
    _stamp_review_terminal blocked
    exit 6
  fi
  _pc_refusal="${refusal:-all_arms_unavailable}"
  _pc_write_unreviewed "${_pc_refusal}" "${pool}" "${_pc_tried_csv}" "${resolver_rc}" "${resolver_stderr}"
  exit 9
fi
review_source="${REVIEW_SOURCE:-stream}"
verdict="${PARSED_VERDICT}"
record_out="$(LEADV2_DISPATCH_CACHE_DIR="${LEADV2_DISPATCH_CACHE_DIR:-}" LEADV2_JOURNAL_BIN="${JOURNAL_BIN}" \
  bash "${DISPATCH_BIN}" record-review --diff-hash "${diff_hash}" --verdict "${verdict}" --reviewer "${reviewer}" --run-id "dispatch-${TASK}" 2>&1)"; record_rc=$?
if [[ ${record_rc} -eq 2 ]]; then
  emit decision "review_gate task=${TASK} status=dedup diff=${diff_hash:0:8}"
else
  emit decision "review_gate task=${TASK} status=ran author=${AUTHOR} reviewer=${reviewer} verdict=${verdict} diff=${diff_hash:0:8} review_source=${review_source} verdict_source=${VERDICT_SOURCE} ledger_rc=${record_rc}"
fi
if [[ "${verdict}" == FAIL ]]; then
  # REVIEW-GATE-SHOWS-FINDINGS-01 (design R7): head lines stay byte-identical and
  # first; the findings block is APPENDED. tmp+mv (replacing the old direct `>`,
  # which was single-line-safe but not multi-line-safe against a torn read).
  _rgf_rel="docs/handoff/dispatch-${TASK}/review-${reviewer}.md"
  [[ -n "${REVIEW_SOURCE:-}" ]] && _rgf_rel="${REVIEW_SOURCE#artifact:}"
  {
    printf 'status: fail\ncritical: %s\nhigh: %s\nmedium: %s\nlow: %s\n' \
      "${FINDINGS_CRITICAL}" "${FINDINGS_HIGH}" "${FINDINGS_MEDIUM}" "${FINDINGS_LOW}"
    render_gate_findings "${review_file}" "" "${reviewer}" "${_rgf_rel}" || true
  } > "${HANDOFF}/review-gate.md.tmp"
  mv -f "${HANDOFF}/review-gate.md.tmp" "${HANDOFF}/review-gate.md"
  _rgf_dnm=""; [[ "${RGF_DO_NOT_MERGE:-0}" == "1" ]] && _rgf_dnm=" do_not_merge=1"
  emit decision "review_gate task=${TASK} status=fail critical=${FINDINGS_CRITICAL} high=${FINDINGS_HIGH}${_rgf_dnm}"
  _dl_note dead review_verdict_fail "critical=${FINDINGS_CRITICAL} high=${FINDINGS_HIGH}"
  _stamp_review_terminal fail
  exit 7
fi
# PASS must overwrite review-gate.md too, or a stale fail/blocked artifact from an earlier
# attempt keeps lying after the gate has actually cleared (hit live on fe5307b3, 2026-07-30).
# REVIEW-GATE-SHOWS-FINDINGS-01: same append + tmp/mv discipline on the pass exit —
# the block is written on EVERY pass/fail exit, so its absence can only mean an old
# build, and a do-not-merge report shows on the face of a passing gate (advisory only:
# status: stays pass, decision semantics unchanged).
_rgf_rel="docs/handoff/dispatch-${TASK}/review-${reviewer}.md"
[[ -n "${REVIEW_SOURCE:-}" ]] && _rgf_rel="${REVIEW_SOURCE#artifact:}"
_rgf_dnm=""; [[ "${RGF_DO_NOT_MERGE:-0}" == "1" ]] && _rgf_dnm=" do_not_merge=1"
if [[ "${_pc_kind}" == "report" ]]; then
  # REPORT-ONLY-GATE-01: the report lane's pass shape — kind/deliverable/bytes/review
  # name the file a human can open in the main checkout after the lane worktree is gone.
  # Terminal is the unchanged `landed`; write-terminal's deliverable arg (9th) carries
  # the harvested path, commit stays "none" (no code landed).
  {
    printf 'status: pass\nreviewer: %s\nkind: report\ndeliverable: %s\nbytes: %s\nreview: %s\n' \
      "${reviewer}" "${_pc_report_deliverable}" "${_pc_report_bytes}" "${verdict}"
    render_gate_findings "${review_file}" "" "${reviewer}" "${_rgf_rel}" || true
  } > "${HANDOFF}/review-gate.md.tmp"
  mv -f "${HANDOFF}/review-gate.md.tmp" "${HANDOFF}/review-gate.md"
  _dl_note landed review_verdict_pass "diff=${diff_hash:0:8} deliverable=${_pc_report_deliverable}${_rgf_dnm}" "" "${_pc_report_deliverable}"
else
  {
    printf 'status: pass\nreviewer: %s\ndiff: %s\n' "${reviewer}" "${diff_hash:0:8}"
    render_gate_findings "${review_file}" "" "${reviewer}" "${_rgf_rel}" || true
  } > "${HANDOFF}/review-gate.md.tmp"
  mv -f "${HANDOFF}/review-gate.md.tmp" "${HANDOFF}/review-gate.md"
  # T11-D1: PASS alone is not `landed` -- a lane branch must actually merge to the default
  # branch and verify there (merge-base --is-ancestor) before terminal=landed is written.
  # lane 299f2bae got terminal=landed cause=review_verdict_pass with NO merge in main
  # (live incident, 2026-08-26). Anything short of a verified merge is `pass_unlanded`:
  # review passed, code did not land, lead must merge by hand.
  source "${SCRIPT_DIR}/leadv2-branch-merged.sh"
  _t11_branch="$(git -C "${diff_root}" symbolic-ref --short HEAD 2>/dev/null || true)"
  _t11_default="$(lv2_default_branch "${ROOT}")"
  if [[ -z "${_t11_branch}" || "${_t11_branch}" == "${_t11_default}" || "${diff_root}" == "${ROOT}" ]]; then
    # No isolated lane branch to merge (shared-tree fallback lane, or work already landed on
    # the default branch directly) -- nothing to merge, so `landed` is accurate as-is.
    _dl_note landed review_verdict_pass "diff=${diff_hash:0:8}${_rgf_dnm}"
  elif [[ -n "$(git -C "${ROOT}" status --porcelain 2>/dev/null)" ]]; then
    # Shared tree has foreign uncommitted work right now -- merging here risks another
    # session's in-flight edits. Never force past this: fail toward pass_unlanded.
    _dl_note pass_unlanded root_dirty "branch=${_t11_branch} diff=${diff_hash:0:8}"
  else
    _t11_landed=0
    [[ -x "${SCRIPT_DIR}/leadv2-merge-queue.sh" ]] && bash "${SCRIPT_DIR}/leadv2-merge-queue.sh" acquire "${TASK}" >/dev/null 2>&1
    if git -C "${ROOT}" merge --no-edit --no-ff "${_t11_branch}" >/tmp/t11-merge-"${TASK}".log 2>&1 \
        && lv2_branch_merged "${ROOT}" "${_t11_branch}" "${_t11_default}"; then
      _t11_landed=1
    else
      git -C "${ROOT}" merge --abort >/dev/null 2>&1 || true
    fi
    [[ -x "${SCRIPT_DIR}/leadv2-merge-queue.sh" ]] && bash "${SCRIPT_DIR}/leadv2-merge-queue.sh" release "${TASK}" >/dev/null 2>&1
    if [[ "${_t11_landed}" == 1 ]]; then
      _dl_note landed review_verdict_pass "diff=${diff_hash:0:8}${_rgf_dnm} branch=${_t11_branch}"
      # T11-F1: merge + is-ancestor verified above -- complete the close chain
      # instead of stopping at the terminal stamp. Deregister the lane from
      # the live registry so a subsequent sweep no longer sees it as running,
      # then reap its worktree via the existing --name path (already honors
      # the noise-restore-first rule and the merged/unmerged safety checks).
      # Both steps are best-effort and journaled either way: a landed task
      # must never be blocked on cleanup succeeding.
      _t11_lane_state_sh="${SCRIPT_DIR}/lib/leadv2-lane-state.sh"
      if [[ -f "${_t11_lane_state_sh}" ]]; then
        # shellcheck source=lib/leadv2-lane-state.sh
        source "${_t11_lane_state_sh}"
        declare -F lane_deregister >/dev/null 2>&1 && lane_deregister "${TASK}" "close_landed" >/dev/null 2>&1
        emit note "close_deregistered id=${TASK}"
      else
        emit note "close_deregister_skipped id=${TASK} reason=lib_missing"
      fi
      if [[ "${diff_root}" != "${ROOT}" && -x "${SCRIPT_DIR}/leadv2-worktree-cleanup.sh" ]]; then
        if bash "${SCRIPT_DIR}/leadv2-worktree-cleanup.sh" --name "${TASK}" \
            >"/tmp/t11-wtcleanup-${TASK}.log" 2>&1; then
          emit note "close_worktree_removed id=${TASK}"
        else
          emit note "close_worktree_kept detail=$(tail -c 300 "/tmp/t11-wtcleanup-${TASK}.log" | tr '\n' ' ')"
        fi
      fi
    else
      _dl_note pass_unlanded merge_conflict "branch=${_t11_branch} diff=${diff_hash:0:8}"
    fi
  fi
fi
_stamp_review_terminal pass
# PHASES-ARE-THE-ONLY-PATH-01: record review phase as done (verdict PASS).
[[ -x "${SCRIPT_DIR}/leadv2-phase-record.sh" ]] && \
  bash "${SCRIPT_DIR}/leadv2-phase-record.sh" record "${TASK}" review --status done \
    --artifact "docs/handoff/dispatch-${TASK}/review-gate.md" \
    --task-id "${FOUNDER_TASK_ID}" --owner "$(basename "$0"):review_gate" 2>/dev/null || true
