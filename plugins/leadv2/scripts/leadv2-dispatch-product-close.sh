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
HANDOFF="${ROOT}/docs/handoff/dispatch-${TASK}"
mkdir -p "${HANDOFF}"

if [[ -n "${FOUNDER_TASK_ID}" ]]; then
  _TASKS_LIB="${SCRIPT_DIR}/leadv2-tasks-lib.sh"
  if [[ -f "${_TASKS_LIB}" ]]; then
    PROJECT_ROOT="${ROOT}"
    # shellcheck source=leadv2-tasks-lib.sh
    source "${_TASKS_LIB}"
    trap 'leadv2_tasks_unclaim "${FOUNDER_TASK_ID}" >/dev/null 2>&1 || true' EXIT
  fi
fi

emit() { # type text
  if [[ -f "${JOURNAL_BIN}" ]]; then bash "${JOURNAL_BIN}" append "dispatch-${TASK}" "$1" "$2" >/dev/null 2>&1 || true; fi
  printf '[leadv2-dispatch-product-close] %s\n' "$2" >&2
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

if [[ "${E2E_ON}" != 1 ]]; then
  emit decision "e2e_gate task=${TASK} status=disabled reason=kill_switch"
elif ! e2e_cmd="$(bash "${SCRIPT_DIR}/leadv2-e2e-entrypoint.sh" "${ROOT}")"; then
  repo="$(basename "${ROOT}")"
  printf 'status: blocked\nreason: no_e2e_entrypoint\nrepo: %s\n' "${repo}" > "${HANDOFF}/e2e-gate.md"
  rm -f "${HANDOFF}/e2e-gate-passed.flag"
  emit decision "e2e_gate task=${TASK} status=blocked reason=no_e2e_entrypoint repo=${repo}"
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
  fi
fi

if [[ "${REVIEW_ON}" != 1 ]]; then
  emit decision "review_gate task=${TASK} status=disabled reason=kill_switch"
  exit 0
fi

# REVIEWER_ARMS is an availability result supplied by the router/quota layer. Removing the
# author is the cross-provider correctness constraint, not an operator exclusion. A conflict
# is a finding: a same-provider-only pool must never turn into a silent skip.
arms="${LEADV2_DISPATCH_REVIEWER_ARMS:-codex,sonnet}"
reviewer=""
IFS=',' read -r -a candidates <<< "${arms}"
for candidate in "${candidates[@]}"; do
  [[ "${candidate}" == "${AUTHOR}" || -z "${candidate}" ]] && continue
  case "${candidate}" in codex|sonnet) reviewer="${candidate}"; break;; esac
done
if [[ -z "${reviewer}" ]]; then
  printf 'status: conflict\nauthor: %s\navailable_reviewer_arms: %s\n' "${AUTHOR}" "${arms}" > "${HANDOFF}/review-gate.md"
  emit decision "review_gate task=${TASK} status=conflict author=${AUTHOR} available=${arms} reason=no_cross_provider_reviewer"
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
  exit 5
fi
diff_hash="$(shasum -a 256 "${diff_file}" | awk '{print $1}')"
# Dedup is checked BEFORE spending a second provider. record-review below remains the
# atomic writer that resolves a concurrent race; in that case the duplicate result is also
# journaled instead of masquerading as a new review.
ledger="${LEADV2_DISPATCH_CACHE_DIR:-${HOME}/.claude/cache}/review-ledger/$(basename "${ROOT}").jsonl"
if [[ -f "${ledger}" ]] && grep -qF "\"diff_hash\":\"${diff_hash}\"" "${ledger}"; then
  emit decision "review_gate task=${TASK} status=dedup diff=${diff_hash:0:8}"
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
  exit 6
fi
if [[ ! -s "${review_file}" ]]; then
  printf 'status: blocked\nreason: review_unusable\n' > "${HANDOFF}/review-gate.md"
  emit decision "review_gate task=${TASK} status=blocked reason=review_unusable detail=empty"
  exit 6
fi
if ! parse_review_verdict "${review_file}"; then
  printf 'status: blocked\nreason: review_unusable\n' > "${HANDOFF}/review-gate.md"
  emit decision "review_gate task=${TASK} status=blocked reason=review_unusable detail=no_verdict_marker"
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
  exit 7
fi
