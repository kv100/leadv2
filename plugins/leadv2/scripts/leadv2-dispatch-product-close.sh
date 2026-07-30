#!/usr/bin/env bash
# leadv2-dispatch-product-close.sh — detached post-worker readiness gates for ST-9.
# It is deliberately a script, not supervisor work: dispatch starts it only after a live
# product worker is confirmed.  It reports a missing e2e entrypoint, an unscopable diff, or
# a cross-provider conflict as a finding; none is silently passed.  Kill switches are passed
# explicitly by dispatch.
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
WRITES_CSV="${LEADV2_DISPATCH_LANE_WRITES:-}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
JOURNAL_BIN="${LEADV2_JOURNAL_BIN:-${SCRIPT_DIR}/leadv2-journal.sh}"
DISPATCH_BIN="${LEADV2_DISPATCH_BIN:-${SCRIPT_DIR}/leadv2-dispatch-code.sh}"
# T-o (SUPERVISOR-AUDIT-01): this script owns the e2e/review half of a product task's
# lifecycle, so ITS exit paths are where that task's real terminal state (landed/parked/
# refused/dead) becomes known -- dispatch-code.sh deliberately does NOT write one for a
# product spawn (see that file's cmd_resolve arc==0 comment). Always a subprocess call
# (never sourced) -- see leadv2-dispatch-ledger.sh's own doc header.
LEDGER_BIN="${LEADV2_DISPATCH_LEDGER_BIN:-${SCRIPT_DIR}/leadv2-dispatch-ledger.sh}"
TERMINAL_LEDGER="${LEADV2_DISPATCH_TERMINAL_LEDGER:-1}"
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
_dl_note() {  # <terminal> <cause> [<evidence>]
  _PC_TERMINAL_STATE="$1"
  _PC_TERMINAL_CAUSE="$2"
  _PC_TERMINAL_EVIDENCE="${3:-}"
  [[ "${TERMINAL_LEDGER}" == "1" && -f "${LEDGER_BIN}" ]] || return 0
  # wave2 round3 finding 3 / LOW-2: _PC_ATTEMPT (qualified <sig8>-<epoch>-<pid>, not a bare
  # pid) is stable across BOTH this explicit call and the EXIT trap's own idempotent retry
  # of the same _PC_TERMINAL_* state (see _pc_exit_handler) -- the ledger's attempt-token
  # dedup uses it to recognize that retry as the SAME attempt (still write-once), while a
  # genuinely later, separate invocation of this script for the same TASK sig8 gets its own
  # token and is never blocked by an earlier refused/parked row.
  bash "${LEDGER_BIN}" write-terminal "${TASK}" "${FOUNDER_TASK_ID}" "$1" "$2" "${3:-}" "${_PC_ATTEMPT}" >/dev/null 2>&1 9>&- || true
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

# Fix6 (SUPERVISOR-AUDIT-01): the reviewer arm used to come from a hand-kept env list
# (LEADV2_DISPATCH_REVIEWER_ARMS, default "codex,sonnet") that never consulted the ONE
# resolver dispatch-code.sh/router.sh use — GLM's review ban and the codex_quota_gate
# 95% reserve were invisible here. Call the same lib/leadv2-glm-policy-resolve.py CLI
# (job=review, base-arm=codex — review's base arm per the resolver's own docstring) so
# GLM-never-reviews and the codex quota spill are ONE enforced policy, not a second copy.
# Fail-safe: any resolver-missing/error path falls back to sonnet (never glm, matching
# the resolver's own review-mode fallback contract).
resolve_review_arm() {
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
    printf 'arm=sonnet\nreason=resolver_missing_failclosed\n'
    return
  fi
  local routing_yaml="${LEADV2_ROUTING_YAML:-${ROOT}/.claude/ref/leadv2-routing.yaml}"
  local -a resolver_args=(--routing-yaml "${routing_yaml}" --job review --base-arm codex --signals '{}')
  [[ -n "${GLM_POLICY_QUOTA_LIVE:-}" ]] && resolver_args+=(--quota-live "${GLM_POLICY_QUOTA_LIVE}")
  python3 "${resolver}" "${resolver_args[@]}" 2>/dev/null || printf 'arm=sonnet\nreason=resolver_error_failclosed\n'
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

# Wait only for a positively known local PID. Other providers may expose only a durable
# job/run handle, so their lifecycle owner writes the close evidence; we never guess done.
if [[ "${AUTHOR}" == sonnet && "${HANDLE}" =~ ^[0-9]+$ ]]; then
  while kill -0 "${HANDLE}" 2>/dev/null; do sleep 2; done
fi

_stamp_active_phase "${FOUNDER_TASK_ID}" "e2e"
if [[ "${E2E_ON}" != 1 ]]; then
  emit decision "e2e_gate task=${TASK} status=disabled reason=kill_switch"
elif ! e2e_cmd="$(bash "${SCRIPT_DIR}/leadv2-e2e-entrypoint.sh" "${ROOT}")"; then
  repo="$(basename "${ROOT}")"
  printf 'status: blocked\nreason: no_e2e_entrypoint\nrepo: %s\n' "${repo}" > "${HANDOFF}/e2e-gate.md"
  rm -f "${HANDOFF}/e2e-gate-passed.flag"
  emit decision "e2e_gate task=${TASK} status=blocked reason=no_e2e_entrypoint repo=${repo}"
  _dl_note refused no_e2e_entrypoint "repo=${repo}"
  exit 4
else
  bash -c "${e2e_cmd} --scope changed" > "${HANDOFF}/e2e-gate.log" 2>&1; e2e_rc=$?
  if [[ ${e2e_rc} -eq 0 ]]; then
    printf 'e2e-gate-passed: %s\nasserted_at: %s\nscope: changed\nbypassed: false\n' \
      "${TASK}" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" > "${HANDOFF}/e2e-gate-passed.flag"
    emit decision "e2e_gate task=${TASK} status=ran verdict=pass"
  else
    rm -f "${HANDOFF}/e2e-gate-passed.flag"
    emit decision "e2e_gate task=${TASK} status=ran verdict=fail rc=${e2e_rc}"
    # wave2 finding 6: an e2e regression is a `dead` outcome in the ledger taxonomy --
    # falling through into the review gate below (which CAN end in `landed`) let a real
    # regression be finalized as delivered. Distinct from the kill-switch branch above
    # (E2E_ON!=1 is a deliberate disabled state, never a failure) -- this only fires when
    # the gate actually RAN and reported a real non-zero verdict.
    printf 'status: fail\nreason: e2e_regression\nrc: %s\n' "${e2e_rc}" > "${HANDOFF}/e2e-gate.md"
    _dl_note dead e2e_regression "rc=${e2e_rc}"
    exit 8
  fi
fi

_stamp_active_phase "${FOUNDER_TASK_ID}" "review"
if [[ "${REVIEW_ON}" != 1 ]]; then
  emit decision "review_gate task=${TASK} status=disabled reason=kill_switch"
  _dl_note landed review_gate_disabled
  exit 0
fi

# Resolved via the unified resolver (job=review, base-arm=codex) — see resolve_review_arm()
# above. Removing the author is the cross-provider correctness constraint, not an operator
# exclusion. A conflict is a finding: a same-provider-only pool must never turn into a silent skip.
resolver_out="$(resolve_review_arm)"
resolved_arm="$(printf '%s\n' "${resolver_out}" | sed -n 's/^arm=//p' | head -n1)"
resolved_reason="$(printf '%s\n' "${resolver_out}" | sed -n 's/^reason=//p' | head -n1)"
# Defense-in-depth: the resolver structurally never returns glm for base-arm=codex, but
# GLM-never-reviews is a founder rule with no exception path, so guard it explicitly too.
[[ -z "${resolved_arm}" || "${resolved_arm}" == glm ]] && resolved_arm=sonnet
reviewer="${resolved_arm}"
if [[ "${reviewer}" == "${AUTHOR}" ]]; then
  if [[ "${AUTHOR}" == sonnet ]]; then
    reviewer=""  # only candidate collided with the sonnet author -- park, never self-review
  else
    reviewer=sonnet  # fail closed to sonnet-critic; sonnet != AUTHOR is guaranteed in this branch
  fi
fi
if [[ -z "${reviewer}" || "${reviewer}" == "${AUTHOR}" ]]; then
  printf 'status: conflict\nauthor: %s\nresolved_arm: %s\nresolver_reason: %s\n' \
    "${AUTHOR}" "${resolved_arm}" "${resolved_reason:-no_cross_provider_reviewer}" > "${HANDOFF}/review-gate.md"
  emit decision "review_gate task=${TASK} status=conflict author=${AUTHOR} resolved_arm=${resolved_arm} reason=${resolved_reason:-no_cross_provider_reviewer}"
  _dl_note parked "${resolved_reason:-no_cross_provider_reviewer}" "author=${AUTHOR}"
  exit 0
fi

diff_file="${HANDOFF}/review.diff"
: > "${diff_file}"
blocked_reason=""
if [[ -n "${WRITES_CSV}" ]]; then
  IFS=',' read -r -a raw_writes <<< "${WRITES_CSV}"
  writes=()
  for w in "${raw_writes[@]}"; do
    w="${w#"${w%%[![:space:]]*}"}"; w="${w%"${w##*[![:space:]]}"}"
    [[ -n "${w}" ]] && writes+=("${w}")
  done
  if [[ ${#writes[@]} -gt 0 ]]; then
    git -C "${ROOT}" diff HEAD -- "${writes[@]}" ':(exclude)docs/leadv2' ':(exclude)docs/handoff' > "${diff_file}" 2>/dev/null || true
  fi
  [[ -s "${diff_file}" ]] || blocked_reason="unscopable_diff"
else
  wt="$(bash "${SCRIPT_DIR}/leadv2-lane-worktree.sh" path-of "${TASK}" 2>/dev/null || true)"
  if [[ -n "${wt}" && -d "${wt}" ]]; then
    git -C "${wt}" diff HEAD -- ':(exclude)docs/leadv2' ':(exclude)docs/handoff' > "${diff_file}" 2>/dev/null || true
  fi
  [[ -s "${diff_file}" ]] || blocked_reason="unscopable_diff"
fi
if [[ -n "${blocked_reason}" ]]; then
  printf 'status: blocked\nreason: %s\n' "${blocked_reason}" > "${HANDOFF}/review-gate.md"
  emit decision "review_gate task=${TASK} status=blocked reason=${blocked_reason}"
  _dl_note refused "${blocked_reason}"
  exit 5
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
review_out="${HANDOFF}/review-${reviewer}.md"
review_err="${HANDOFF}/review-${reviewer}.err"
review_adir="${ROOT}/docs/handoff/dispatch-${TASK}-review"
mkdir -p "${review_adir}"
REVIEW_STAMP="${HANDOFF}/.review-start.stamp"
touch "${REVIEW_STAMP}"
review_contract=$'Your review MUST contain these two lines, verbatim format, before any prose:\nREVIEW_VERDICT: <FAIL|PASS|PASS_WITH_NITS>\nREVIEW_FINDINGS: critical=<n> high=<n> medium=<n> low=<n>\nFAIL if any Critical or High finding. PASS if the diff is clean. PASS_WITH_NITS otherwise.'
if [[ "${reviewer}" == codex ]]; then
  bash "${LEADV2_DISPATCH_CODEX_BIN:-${SCRIPT_DIR}/codex-task.sh}" adversarial-review --base HEAD --wait \
    --focus "Review ONLY the diff at ${diff_file}. You are independent of the author (${AUTHOR}). Report correctness findings by severity (Critical / High / Medium / Low). ${review_contract}" \
    > "${review_out}" 2> "${review_err}"; review_rc=$?
else
  mission_file="${HANDOFF}/review-mission.md"
  printf 'Review ONLY the diff at %s. You are independent of the author (%s).\nReport correctness findings by severity (Critical / High / Medium / Low).\n%s\n' \
    "${diff_file}" "${AUTHOR}" "${review_contract}" > "${mission_file}"
  PROJECT_ROOT="${ROOT}" bash "${LEADV2_DISPATCH_ARCHITECT_BIN:-${SCRIPT_DIR}/claude-subsession.sh}" --role critic --model sonnet --task-id "dispatch-${TASK}-review" --mission-file "${mission_file}" --wait \
    > "${review_out}" 2> "${review_err}"; review_rc=$?
fi

resolve_review_artifact || true
review_file="${REVIEW_ARTIFACT:-${review_out}}"
if [[ ${review_rc} -ne 0 && -z "${REVIEW_ARTIFACT}" ]]; then
  printf 'status: blocked\nreason: review_unusable\n' > "${HANDOFF}/review-gate.md"
  emit decision "review_gate task=${TASK} status=blocked reason=review_unusable rc=${review_rc}"
  _dl_note dead review_unusable "rc=${review_rc}"
  exit 6
fi
if [[ ! -s "${review_file}" ]]; then
  printf 'status: blocked\nreason: review_unusable\n' > "${HANDOFF}/review-gate.md"
  emit decision "review_gate task=${TASK} status=blocked reason=review_unusable detail=empty"
  _dl_note dead review_unusable detail=empty
  exit 6
fi
if ! parse_review_verdict "${review_file}"; then
  printf 'status: blocked\nreason: review_unusable\n' > "${HANDOFF}/review-gate.md"
  emit decision "review_gate task=${TASK} status=blocked reason=review_unusable detail=no_verdict_marker"
  _dl_note dead review_unusable detail=no_verdict_marker
  exit 6
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
  printf 'status: fail\ncritical: %s\nhigh: %s\nmedium: %s\nlow: %s\n' \
    "${FINDINGS_CRITICAL}" "${FINDINGS_HIGH}" "${FINDINGS_MEDIUM}" "${FINDINGS_LOW}" > "${HANDOFF}/review-gate.md"
  _dl_note dead review_verdict_fail "critical=${FINDINGS_CRITICAL} high=${FINDINGS_HIGH}"
  exit 7
fi
# PASS must overwrite review-gate.md too, or a stale fail/blocked artifact from an earlier
# attempt keeps lying after the gate has actually cleared (hit live on fe5307b3, 2026-07-30).
printf 'status: pass\nreviewer: %s\ndiff: %s\n' "${reviewer}" "${diff_hash:0:8}" > "${HANDOFF}/review-gate.md"
_dl_note landed review_verdict_pass "diff=${diff_hash:0:8}"
