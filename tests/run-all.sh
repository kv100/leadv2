#!/usr/bin/env bash
# tests/run-all.sh — canonical repo's e2e entrypoint (T-d, PRODUCT-READINESS-GATES-01
# follow-up, 2026-07-29). This is what leadv2-e2e-entrypoint.sh resolves to and what the
# product gates (leadv2-dispatch-product-close.sh, leadv2-phase8-e2e-gate.sh) execute.
#
# It does NOT author new suites — it drives the plugin's own curated offline regression
# runner (.claude/scripts/tests/run-core-offline.sh) plus, on `--scope changed`, any
# test-*.sh whose stem matches a changed file's stem under plugins/leadv2/scripts/.
#
# usage: tests/run-all.sh [--scope changed|all]
# exit 0: every selected suite passed
# exit 1: at least one suite failed
# exit 2: bad usage
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "${HERE}/.." && pwd)"

# C2 (GATE-WRONG-ROOT-FALSE-DEAD-01): root-escape guard. If ROOT does not
# resolve to a git toplevel, every downstream path derivation (PLUGIN_ROOT,
# REPO_ROOT in run-core-offline.sh, etc.) walks to a parent — the exact
# defect that produced repo=/Users/.../Projects. Fail hard, never silently.
_git_toplevel="$(git -C "${ROOT}" rev-parse --show-toplevel 2>/dev/null || true)"
if [[ "${_git_toplevel}" != "${ROOT}" ]]; then
  echo "run-all: FATAL root_escape expected=${ROOT} resolved=${_git_toplevel:-<not-a-repo>}" >&2
  exit 2
fi

SCOPE="changed"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --scope)
      SCOPE="${2:-}"; shift 2 ;;
    --scope=*)
      SCOPE="${1#--scope=}"; shift ;;
    -h|--help)
      echo "usage: tests/run-all.sh [--scope changed|all]" >&2
      exit 0 ;;
    *)
      echo "run-all: unknown argument: $1" >&2
      exit 2 ;;
  esac
done
case "${SCOPE}" in
  changed|all) ;;
  *) echo "run-all: --scope must be changed|all (got '${SCOPE}')" >&2; exit 2 ;;
esac

PASS=0
FAIL=0
declare -a SUITES=()
declare -a FAILED_REL=()
# Non-stem suite mappings live in EXTRA_SUITE_MAP below (string rows, one per
# line, "<stem>:<suite>"). The PHASE-DISCIPLINE-01 array form was migrated into
# it during the MON-PULSE-01 merge (2026-08-28) — one mechanism, not two.

add_suite() { # <path>
  local p="$1" real
  real="$(cd "$(dirname "$p")" 2>/dev/null && pwd)/$(basename "$p")" || return 0
  [[ -f "$real" ]] || return 0
  # C2 (GATE-WRONG-ROOT-FALSE-DEAD-01): containment check. A resolved suite
  # path outside ROOT is a D2-class escape (symlink following, wrong-depth
  # anchor) — skip it loudly rather than running tests from a foreign tree.
  case "${real}" in
    "${ROOT}/"*) ;;
    "${ROOT}")   ;;
    *) echo "run-all: SKIP out_of_tree ${real}" >&2; return 0 ;;
  esac
  local existing
  for existing in "${SUITES[@]:-}"; do
    [[ "$existing" == "$real" ]] && return 0
  done
  SUITES+=("$real")
}

# C3 (GATE-WRONG-ROOT-FALSE-DEAD-01): Always-on: the plugin's own curated
# offline regression set. Plugin-preferred — the canonical 111-file set at
# plugins/leadv2/scripts/tests/ has the correct ../../.. path arithmetic
# (D2) and is never a stale fork (D3). Repos without plugins/leadv2/
# (persona-engine, m3-market) fall through to .claude/ verbatim — zero
# behavioural delta outside this repo (case (g) guard).
if [[ -f "${ROOT}/plugins/leadv2/scripts/tests/run-core-offline.sh" ]]; then
  add_suite "${ROOT}/plugins/leadv2/scripts/tests/run-core-offline.sh"
else
  add_suite "${ROOT}/.claude/scripts/tests/run-core-offline.sh"
fi

# Always-on: SwiftBar runs the status-surface scripts under macOS /bin/bash 3.2
# (PATH-resolved, not Homebrew bash 5) — a stem-based --scope=changed match on
# the renderer/wrapper filenames is not enough, since a change to an unrelated
# script must not silently drop this guard from a run. See SWIFTBAR-BASH32-01.
add_suite "${ROOT}/tests/test-status-surface-bash32.sh"
# SWIFTBAR-FAST-NAMES-01: the widget's async-cache + label-resolver contract —
# always-on for the same reason as bash32 (the wrapper filename stem no longer
# matches the test stems after the .10s -> .5s rename, so a changed-scope match
# is not reliable).
add_suite "${ROOT}/tests/test-status-surface-single-lead.sh"
add_suite "${ROOT}/tests/test-status-surface-fast-names.sh"

# MON-PULSE-01: EXTRA_SUITE_MAP — "<changed-stem>:<suite>" rows, one per line.
# A changed plugin script whose behavioural lock lives in a DIFFERENTLY-NAMED
# suite (the dispatch-code arming seam is proven by the pulse-watch suites,
# not by any test-dispatch-code.sh) is mapped here so --scope changed still
# runs its suite instead of silently dropping it.
EXTRA_SUITE_MAP="glm-coder.sh:plugins/leadv2/scripts/tests/test-glm-lock-per-lane.sh
glm-coder.sh:plugins/leadv2/scripts/tests/test-glm-flash-handle.sh
leadv2-dispatch-code.sh:plugins/leadv2/scripts/tests/test-glm-flash-handle.sh
leadv2-phase8-assert.sh:plugins/leadv2/scripts/tests/test-phase8-a2-id-resolution.sh
leadv2-hook-session-kind.sh:plugins/leadv2/scripts/tests/test-beat-loop-orphans.sh
leadv2-single-lead-beat-loop.sh:plugins/leadv2/scripts/tests/test-beat-loop-orphans.sh
leadv2-lane-pulse-watch.sh:plugins/leadv2/scripts/tests/test-beat-loop-orphans.sh
leadv2-dispatch-code.sh:plugins/leadv2/scripts/tests/test-beat-loop-orphans.sh
leadv2-dispatch-code.sh:plugins/leadv2/scripts/tests/test-resume-lane-arg-shapes.sh
leadv2-tasks-lib.sh:plugins/leadv2/scripts/tests/test-phase8-a2-id-resolution.sh
leadv2-dispatch-code.sh:plugins/leadv2/scripts/tests/test-lane-pulse-watch.sh
leadv2-dispatch-code.sh:plugins/leadv2/scripts/tests/test-plugin-papercuts.sh
leadv2-dispatch-code.sh:plugins/leadv2/scripts/tests/test-single-lead-beat-loop.sh
leadv2-dispatch-code.sh:plugins/leadv2/scripts/tests/test-lane-registry-outlives-dispatcher.sh
leadv2-active-registry.sh:plugins/leadv2/scripts/tests/test-lane-registry-outlives-dispatcher.sh
freepool-coder:plugins/leadv2/scripts/tests/test-freepool-model-selector.sh
leadv2-backlog-pump:plugins/leadv2/scripts/tests/test-backlog-pump.sh
leadv2-dispatch-code:plugins/leadv2/scripts/tests/test-phase-precondition.sh
leadv2-gate1-prompt:plugins/leadv2/scripts/tests/test-gate1-discipline.sh
leadv2-phase-record:plugins/leadv2/scripts/tests/test-phase-record.sh
leadv2-phase-record:plugins/leadv2/scripts/tests/test-phase-precondition.sh
leadv2-phase-record:plugins/leadv2/scripts/tests/test-phase-precondition-bootstrap.sh
leadv2-dispatch-code:plugins/leadv2/scripts/tests/test-phase-precondition-bootstrap.sh
# PHASE-GATE-IS-INVERTED-01: the inversion regression lives in its own suite
# and is exercised THROUGH the dispatcher, so both changed stems map to it.
leadv2-dispatch-code:plugins/leadv2/scripts/tests/test-phase-gate-inversion.sh
leadv2-phase-record:plugins/leadv2/scripts/tests/test-phase-gate-inversion.sh
leadv2-admission-class:plugins/leadv2/scripts/tests/test-admission-class.sh
leadv2-route-arbiter:plugins/leadv2/scripts/tests/test-route-arbiter-symlink-install.sh
codex-task.sh:plugins/leadv2/scripts/tests/test-codex-longrun.sh
leadv2-dispatch-code:plugins/leadv2/scripts/tests/test-freepool-capability-floor.sh
leadv2-route-arbiter:plugins/leadv2/scripts/tests/test-freepool-capability-floor.sh
leadv2-dispatch-code:plugins/leadv2/scripts/tests/test-model-select-telemetry.sh
leadv2-lane-pulse-watch.sh:plugins/leadv2/scripts/tests/test-lane-pulse-watch.sh
leadv2-single-lead-beat-loop.sh:plugins/leadv2/scripts/tests/test-single-lead-beat-loop.sh
leadv2-single-lead-beat-loop.sh:plugins/leadv2/scripts/tests/test-plugin-papercuts.sh
leadv2-pulse-beat.sh:plugins/leadv2/scripts/tests/test-plugin-papercuts.sh
leadv2-routing.yaml:plugins/leadv2/scripts/tests/test-plugin-papercuts.sh
codex-task.sh:plugins/leadv2/scripts/tests/test-plugin-papercuts.sh
leadv2-broad-status.sh:plugins/leadv2/scripts/tests/test-lane-pulse-founder.sh
leadv2-broad-status.sh:plugins/leadv2/scripts/tests/test-broad-status-row-identity.sh
leadv2-broad-status.sh:plugins/leadv2/scripts/tests/test-broad-status-lanes-blind.sh
leadv2-lane-pulse-watch.sh:plugins/leadv2/scripts/tests/test-lane-pulse-founder.sh
leadv2-broad-status.sh:plugins/leadv2/scripts/tests/test-broad-status-renderer-truth.sh
leadv2-broad-status.sh:plugins/leadv2/scripts/tests/test-broad-status-duty.sh
leadv2-broad-status.sh:plugins/leadv2/scripts/tests/test-pulse-readable-rendering.sh
leadv2-broad-status.sh:plugins/leadv2/scripts/tests/test-pulse-empty-board.sh
leadv2-broad-status.sh:plugins/leadv2/scripts/tests/test-single-lead-beat.sh
leadv2-broad-status.sh:plugins/leadv2/scripts/tests/test-lib-source-guarded.sh
leadv2-sleep.sh:plugins/leadv2/scripts/tests/test-no-orphan-sleep.sh
leadv2-hook-fork-budget.sh:plugins/leadv2/scripts/tests/test-hook-fork-budget.sh
hooks.json:plugins/leadv2/scripts/tests/test-hook-fork-budget.sh
leadv2-promise-guard.sh:plugins/leadv2/scripts/tests/test-promise-action-binding.sh
leadv2-promise-guard.sh:plugins/leadv2/scripts/tests/test-promise-guard-morphology.sh
leadv2-promise-guard.sh:plugins/leadv2/scripts/tests/test-promise-guard-classified-block.sh
leadv2-promise-guard.sh:plugins/leadv2/tests/test-promise-guard.sh
leadv2-guard-census.sh:plugins/leadv2/scripts/tests/test-guard-census.sh
leadv2-guard-verdict.sh:plugins/leadv2/scripts/tests/test-guard-census.sh
# GUARD-CENSUS-IS-WRONG-01 round 2: the dispatcher hook had NO suite at all —
# every verdict-kind/rotation line was untested until this mapping.
leadv2-bash-pre-dispatch.sh:plugins/leadv2/scripts/tests/test-bash-pre-dispatch-verdict.sh
leadv2-guard-census.sh:plugins/leadv2/scripts/tests/test-bash-pre-dispatch-verdict.sh
leadv2-guard-verdict.sh:plugins/leadv2/scripts/tests/test-bash-pre-dispatch-verdict.sh
leadv2-dispatch-code:plugins/leadv2/scripts/tests/test-arm-capability-honoured.sh
leadv2-route-arbiter:plugins/leadv2/scripts/tests/test-arm-capability-honoured.sh
leadv2-worker-output-gate:plugins/leadv2/scripts/tests/test-worker-output-gate.sh
freepool-coder:plugins/leadv2/scripts/tests/test-worker-output-gate.sh
leadv2-repo-install.sh:plugins/leadv2/scripts/tests/test-adoption-gate-passable.sh
leadv2-freepool-model-select:plugins/leadv2/scripts/tests/test-freepool-model-liveness.sh
freepool-arm.yaml:plugins/leadv2/scripts/tests/test-freepool-model-liveness.sh
freepool-coder:plugins/leadv2/scripts/tests/test-freepool-model-liveness.sh
leadv2-broad-status.sh:plugins/leadv2/scripts/tests/test-broad-status-foreign-lanes.sh
leadv2-broad-status.sh:plugins/leadv2/scripts/tests/test-status-repo-scoped.sh
leadv2-status-collector.sh:plugins/leadv2/scripts/tests/test-collector-sees-registered-lane.sh
leadv2-dispatch-code.sh:plugins/leadv2/scripts/tests/test-mission-writeset.sh
leadv2-dispatch-code.sh:plugins/leadv2/scripts/tests/test-red-proof-gate.sh
leadv2-mission-writeset:plugins/leadv2/scripts/tests/test-mission-writeset.sh
leadv2-red-proof:plugins/leadv2/scripts/tests/test-red-proof-gate.sh
leadv2-one-copy-drift.sh:plugins/leadv2/scripts/tests/test-hook-output-cap.sh
leadv2-truth-card-inject.sh:plugins/leadv2/scripts/tests/test-hook-output-cap.sh
leadv2-dispatch-ledger:plugins/leadv2/scripts/tests/test-dirty-lane-never-lands.sh
leadv2-dispatch-ledger.sh:plugins/leadv2/scripts/tests/test-dirty-lane-never-lands.sh
leadv2-dispatch-ledger.sh:plugins/leadv2/scripts/tests/test-close-chain.sh
leadv2-dispatch-product-close.sh:plugins/leadv2/scripts/tests/test-dirty-lane-never-lands.sh
leadv2-dispatch-product-close.sh:plugins/leadv2/scripts/tests/test-scope-gate-orchestration-dirt.sh
leadv2-dispatch-product-close.sh:plugins/leadv2/scripts/tests/test-merged-sweep-orchestration-dirt.sh
leadv2-dispatch-product-close.sh:plugins/leadv2/scripts/tests/test-worktree-lane-safety.sh
leadv2-dispatch-code:plugins/leadv2/scripts/tests/test-lane-containment.sh
leadv2-dispatch-code:plugins/leadv2/scripts/tests/test-plan-in-lane.sh
leadv2-dispatch-code:plugins/leadv2/scripts/tests/test-lane-placement-pin.sh
leadv2-lane-guard:plugins/leadv2/scripts/tests/test-dirty-lane-never-lands.sh
leadv2-lane-guard:plugins/leadv2/scripts/tests/test-lane-containment.sh
leadv2-lane-guard:plugins/leadv2/scripts/tests/test-scope-gate-orchestration-dirt.sh
leadv2-lane-guard:plugins/leadv2/scripts/tests/test-merged-sweep-orchestration-dirt.sh
leadv2-lane-guard:plugins/leadv2/scripts/tests/test-worktree-lane-safety.sh
leadv2-lane-guard:plugins/leadv2/scripts/tests/test-t13-slice1.sh
leadv2-dispatch-code:plugins/leadv2/scripts/tests/test-class-floor-survives-resume.sh
leadv2-dispatch-product-close.sh:plugins/leadv2/scripts/tests/test-consumer-symlink-farm.sh
leadv2-dispatch-ledger.sh:plugins/leadv2/scripts/tests/test-consumer-symlink-farm.sh
leadv2-dispatch-code.sh:plugins/leadv2/scripts/tests/test-consumer-symlink-farm.sh
leadv2-admission-class.sh:plugins/leadv2/scripts/tests/test-consumer-symlink-farm.sh
test-consumer-symlink-farm.sh:plugins/leadv2/scripts/tests/test-consumer-symlink-farm.sh
leadv2-status-surface.sh:plugins/leadv2/scripts/tests/test-status-surface.sh
leadv2-lane-status-line.sh:plugins/leadv2/scripts/tests/test-statusline-readable.sh
leadv2-lane-status-line-tail.sh:plugins/leadv2/scripts/tests/test-statusline-readable.sh
leadv2-worker-output-gate:plugins/leadv2/scripts/tests/test-worker-gate-no-origin.sh
gitignore:plugins/leadv2/scripts/tests/test-handoff-artifacts-tracked.sh
leadv2-review-run.sh:plugins/leadv2/scripts/tests/test-review-body-recovery.sh
leadv2-dispatch-code.sh:plugins/leadv2/scripts/tests/test-arm-admission.sh
leadv2-dispatch-code:plugins/leadv2/scripts/tests/test-arm-admission.sh
leadv2-route-arbiter:plugins/leadv2/scripts/tests/test-arm-admission.sh
leadv2-control-prover.sh:plugins/leadv2/scripts/tests/test-control-prover.sh
leadv2-control-prover:plugins/leadv2/scripts/tests/test-control-prover.sh
leadv2-review-run.sh:plugins/leadv2/scripts/tests/test-control-prover.sh
leadv2-broad-status.sh:plugins/leadv2/scripts/tests/test-beat-stamp-agreement.sh
leadv2-dispatch-code.sh:plugins/leadv2/scripts/tests/test-effort-routing.sh
leadv2-route-arbiter:plugins/leadv2/scripts/tests/test-effort-routing.sh
codex-task.sh:plugins/leadv2/scripts/tests/test-codex-broker-staleness.sh
codex-guard.sh:plugins/leadv2/scripts/tests/test-codex-broker-staleness.sh
leadv2-notify-lead:plugins/leadv2/scripts/tests/test-lead-worker-channel.sh
leadv2-inbox:plugins/leadv2/scripts/tests/test-lead-worker-channel.sh
leadv2-ask:plugins/leadv2/scripts/tests/test-lead-worker-channel.sh
ask-lead:plugins/leadv2/scripts/tests/test-lead-worker-channel.sh
leadv2-broad-status:plugins/leadv2/scripts/tests/test-lead-worker-channel.sh
leadv2-dispatch-code:plugins/leadv2/scripts/tests/test-lead-worker-channel.sh
leadv2-dispatch-code:plugins/leadv2/scripts/tests/test-complexity-routing.sh
leadv2-route-arbiter:plugins/leadv2/scripts/tests/test-complexity-routing.sh
leadv2-router-v2:plugins/leadv2/scripts/tests/test-complexity-routing.sh
leadv2-lane-liveness.sh:plugins/leadv2/scripts/tests/test-lane-finished-state.sh
leadv2-lane-liveness.sh:plugins/leadv2/scripts/tests/test-fork-storm-watcher-liveness.sh
leadv2-lane-pulse-watch.sh:plugins/leadv2/scripts/tests/test-fork-storm-watcher-liveness.sh
leadv2-lanes-snapshot.sh:plugins/leadv2/scripts/tests/test-lane-finished-state.sh
leadv2-review-run.sh:plugins/leadv2/scripts/tests/test-suite-falsifiable.sh
leadv2-suite-falsifiable:plugins/leadv2/scripts/tests/test-suite-falsifiable.sh
run-core-offline.sh:plugins/leadv2/scripts/tests/test-suite-lock-scope.sh
leadv2-lane-watch-v2.sh:plugins/leadv2/scripts/tests/test-lane-watch-v2.sh
leadv2-lane-watch-v2:plugins/leadv2/scripts/tests/test-lane-watch-v2.sh
leadv2-status-cache.sh:plugins/leadv2/scripts/tests/test-status-churn.sh
leadv2-spawn-rate.sh:plugins/leadv2/scripts/tests/test-status-churn.sh
leadv2-broad-status.sh:plugins/leadv2/scripts/tests/test-status-churn.sh
leadv2-status-collector.sh:plugins/leadv2/scripts/tests/test-status-churn.sh
leadv2-lanes-snapshot.sh:plugins/leadv2/scripts/tests/test-status-churn.sh
leadv2-lane-liveness.sh:plugins/leadv2/scripts/tests/test-status-churn.sh
leadv2-lane-status-line-tail.sh:plugins/leadv2/scripts/tests/test-status-churn.sh
leadv2-cache-truth.sh:plugins/leadv2/scripts/tests/test-cache-truth.sh
# CACHE-TRUTH-01 R4: the coder arms' stream files are the tool's INPUTS — a
# change to an arm runner can change the stream shape the TSV grades, so each
# arm stem maps to the cache-truth suite too (R3 review finding 2: only the
# tool stem was mapped; --scope changed silently dropped the suite for arm
# edits).
glm-coder.sh:plugins/leadv2/scripts/tests/test-cache-truth.sh
freepool-coder.sh:plugins/leadv2/scripts/tests/test-cache-truth.sh
kimi-coder.sh:plugins/leadv2/scripts/tests/test-cache-truth.sh
claude-subsession.sh:plugins/leadv2/scripts/tests/test-cache-truth.sh
# LEADV2-HOOK-CACHE-DEPLOY-01: the cache-sync script's behavioural lock is a
# differently-named suite (no test-leadv2-plugin-cache-sync stem match).
leadv2-plugin-cache-sync.sh:plugins/leadv2/scripts/tests/test-plugin-cache-sync.sh
leadv2-merge-queue.sh:plugins/leadv2/scripts/tests/test-merge-queue-dead-head.sh
leadv2-worker-epilogue.sh:plugins/leadv2/scripts/tests/test-worker-commit-epilogue.sh
glm-coder.sh:plugins/leadv2/scripts/tests/test-worker-commit-epilogue.sh
glm-coder.sh:plugins/leadv2/scripts/tests/test-lane-outcome.sh
leadv2-dod-gate.sh:plugins/leadv2/scripts/tests/test-worker-dod-gate.sh
leadv2-mutation-control.sh:plugins/leadv2/scripts/tests/test-worker-dod-gate.sh"

if [[ "${SCOPE}" == "all" ]]; then
  while IFS= read -r f; do add_suite "$f"; done < <(
    find "${ROOT}/plugins/leadv2/scripts/tests" "${ROOT}/.claude/scripts/tests" "${ROOT}/plugins/leadv2/tests" "${ROOT}/tests" \
      -maxdepth 1 -type f -name 'test-*.sh' 2>/dev/null | sort
  )
else
  # Union uncommitted diff with the lane range NOT YET SEEN by a prior run of
  # this script (round-4, HOOK-OUTPUT-CAP-PLUGIN-01): a plain merge-base
  # anchor (round-3) unions in the WHOLE `<merge-base>..HEAD` range on every
  # invocation forever — every already-committed, already-tested commit on
  # the lane re-selects its suite on every future unrelated commit, growing
  # monotonically with lane length. Persist the last-checked SHA per git-dir
  # (worktree-scoped, so concurrent lanes never share the file) and diff from
  # THAT instead of the merge-base once it exists. First run on a lane (no
  # state file yet) still falls back to the merge-base, so a docs-only HEAD
  # with unrelated dirt still selects the lane's own suite (round-3's win).
  changed="$(git -C "${ROOT}" diff --name-only HEAD 2>/dev/null)"
  _base_ref=""
  for _cand in main origin/main; do
    if git -C "${ROOT}" rev-parse --verify "${_cand}" >/dev/null 2>&1; then
      _base_ref="${_cand}"
      break
    fi
  done
  _merge_base=""
  if [[ -n "${_base_ref}" ]]; then
    _merge_base="$(git -C "${ROOT}" merge-base HEAD "${_base_ref}" 2>/dev/null || true)"
  fi
  _git_dir="$(git -C "${ROOT}" rev-parse --git-dir 2>/dev/null || true)"
  _state_file=""
  if [[ -n "${_git_dir}" ]]; then
    case "${_git_dir}" in
      /*) : ;;
      *) _git_dir="${ROOT}/${_git_dir}" ;;
    esac
    _state_file="${_git_dir}/leadv2-run-all-last-checked-sha"
  fi
  _range_start=""
  if [[ -n "${_state_file}" && -f "${_state_file}" ]]; then
    _range_start="$(cat "${_state_file}" 2>/dev/null || true)"
    if [[ -n "${_range_start}" ]] && ! git -C "${ROOT}" rev-parse --verify "${_range_start}^{commit}" >/dev/null 2>&1; then
      _range_start=""
    fi
  fi
  if [[ -z "${_range_start}" ]]; then
    _range_start="${_merge_base}"
  fi
  if [[ -n "${_range_start}" ]]; then
    changed="${changed}
$(git -C "${ROOT}" diff --name-only "${_range_start}..HEAD" 2>/dev/null)"
  elif git -C "${ROOT}" rev-parse HEAD~1 >/dev/null 2>&1; then
    changed="${changed}
$(git -C "${ROOT}" diff --name-only HEAD~1..HEAD 2>/dev/null)"
  fi
  # Record this run's HEAD as "checked" so a future clean-HEAD run only sees
  # what's newly dirty, not the whole lane range again. Best-effort (a
  # write failure must never fail the test run) — tmp+mv keeps concurrent
  # invocations in the same worktree from reading a half-written file.
  if [[ -n "${_state_file}" ]]; then
    _head_sha="$(git -C "${ROOT}" rev-parse HEAD 2>/dev/null || true)"
    if [[ -n "${_head_sha}" ]]; then
      printf '%s\n' "${_head_sha}" > "${_state_file}.tmp.$$" 2>/dev/null \
        && mv -f "${_state_file}.tmp.$$" "${_state_file}" 2>/dev/null
    fi
  fi
  if [[ -n "${changed}" ]]; then
    while IFS= read -r cf; do
      # A changed test suite must select itself even when its matching
      # production file did not change in this run.
      case "${cf}" in
        plugins/leadv2/scripts/tests/test-*.sh|.claude/scripts/tests/test-*.sh|plugins/leadv2/tests/test-*.sh|tests/test-*.sh)
          add_suite "${ROOT}/${cf}"
          ;;
      esac
      # FORK-STORM-KILLS-HOOKS-01: the hook table (hooks.json) and hook
      # scripts (plugins/leadv2/hooks/*.sh) are continued by the
      # [[ scripts || lib ]] guard below, so they never reached the
      # stem-comparison loop and a hooks.json-only change ran zero suites.
      # Synthetic stem, freepool-arm.yaml precedent: map row + convention
      # candidate here, then continue.
      case "${cf}" in
        plugins/leadv2/hooks/hooks.json) stem="hooks.json" ;;
        plugins/leadv2/hooks/*.sh) stem="$(basename "${cf}" .sh)" ;;
        *) stem="" ;;
      esac
      if [[ -n "${stem}" ]]; then
        for cand in "${ROOT}/plugins/leadv2/scripts/tests/test-${stem}.sh" \
                    "${ROOT}/tests/test-${stem}.sh"; do
          add_suite "${cand}"
        done
        while IFS= read -r row; do
          [[ -n "$row" ]] || continue
          key="${row%%:*}"
          [[ "$key" == "${stem}" || "$key" == "${stem}.sh" ]] || continue
          add_suite "${ROOT}/${row#*:}"
        done <<< "${EXTRA_SUITE_MAP}"
        continue
      fi
      # PROMISE-GUARD-BIND-01: hooks/*.sh changes (e.g. leadv2-promise-guard.sh)
      # never matched this filter, so a hook fix ran zero suites under
      # --scope changed -- the EXTRA_SUITE_MAP below only fires once a
      # changed file reaches the stem-comparison loop.
      # FREEPOOL-MAKE-IT-EARN-ITS-KEEP-01: a data-only change to the arm
      # ranking must select the suites that grade it, so freepool-arm.yaml
      # maps to its own stem.
      # DISPATCH-CLOSE-GATE-01: scripts/lib/*.sh added -- a bare scripts/*.sh glob
      # never matches a subdirectory, so a lib-only change never reached this loop.
      # PLUGIN-PAPERCUTS-01 repair: this block was a bad merge — an unterminated
      # `$(basename "${cf}" .sh)` and a stray `continue"` left the two stem
      # halves interleaved inside unbalanced quotes. Rewritten as ONE if/elif
      # chain with the same documented behaviours: config yaml special stems,
      # the scripts/lib/hooks allowlist, and the synthetic .gitignore stem.
      if [[ "${cf}" == "plugins/leadv2/config/freepool-arm.yaml" ]]; then
        # FREEPOOL-MAKE-IT-EARN-ITS-KEEP-01: data-only arm-ranking change must
        # select the suites that grade it.
        stem="freepool-arm.yaml"
      elif [[ "${cf}" == "plugins/leadv2/config/leadv2-routing.yaml" ]]; then
        # PLUGIN-PAPERCUTS-01: a data-only routing change (arm cells, tiers)
        # must select the suites that grade routing, same shape as
        # freepool-arm.yaml above.
        stem="leadv2-routing.yaml"
      elif [[ "${cf}" == ".gitignore" ]]; then
        # HANDOFF-ARTIFACTS-GITIGNORED-01: .gitignore isn't a plugins/leadv2
        # script, so it needs its own synthetic stem to reach EXTRA_SUITE_MAP
        # below — the blanket-vs-allowlist rule it carries has no test-*.sh
        # of its own name to match by convention.
        stem="gitignore"
      else
        case "${cf}" in
          plugins/leadv2/scripts/*.sh|plugins/leadv2/scripts/lib/*.sh|plugins/leadv2/hooks/*.sh) ;;
          *) continue ;;
        esac
        # GATE-PROVES-ITS-OWN-CONTROL-01: lib/*.sh is a real production call
        # path (leadv2-control-prover.sh lives there) — a stem-scan that only
        # sees plugins/leadv2/scripts/*.sh never reaches it, so lib/ is scanned
        # too, not just the top-level scripts.
        stem="$(basename "${cf}" .sh)"
      fi
      for cand in "${ROOT}/plugins/leadv2/scripts/tests/test-${stem}.sh" \
                  "${ROOT}/.claude/scripts/tests/test-${stem}.sh" \
                  "${ROOT}/plugins/leadv2/tests/test-${stem}.sh" \
                  "${ROOT}/tests/test-${stem}.sh"; do
        add_suite "${cand}"
      done
      # MON-PULSE-01: extra suites mapped to this changed stem (key may be the
      # bare stem or the full filename — both accepted; PHASE-DISCIPLINE-01
      # rows migrated into the same string map at the 2026-08-28 merge)
      while IFS= read -r row; do
        [[ -n "$row" ]] || continue
        key="${row%%:*}"
        [[ "$key" == "${stem}" || "$key" == "${stem}.sh" ]] || continue
        add_suite "${ROOT}/${row#*:}"
      done <<< "${EXTRA_SUITE_MAP}"
    done <<< "${changed}"
  fi
fi

for suite in "${SUITES[@]:-}"; do
  printf '[RUN] %s\n' "${suite}"
  if bash "${suite}"; then
    printf '[PASS] %s\n' "${suite}"
    PASS=$((PASS + 1))
  else
    printf '[FAIL] %s\n' "${suite}"
    FAIL=$((FAIL + 1))
    # C4 (GATE-WRONG-ROOT-FALSE-DEAD-01): record repo-relative path for the
    # machine-readable failure block (consumed by leadv2-e2e-ownership.sh).
    rel="${suite#"${ROOT}/"}"
    [[ "${rel}" == "${suite}" ]] && rel="${suite}"   # outside ROOT → absolute
    FAILED_REL+=("${rel}")
  fi
done

# C4: emit the Failures (blocking) block that leadv2-e2e-ownership.sh already
# documents as the contract. Suite names are repo-relative to ROOT so the
# classifier can locate them in the scratch tree by direct path. Additive —
# existing [FAIL] lines and the run-all: summary are untouched.
if [[ ${FAIL} -gt 0 ]]; then
  printf '  Failures (blocking):\n'
  for rel in "${FAILED_REL[@]:-}"; do
    printf '    - %s\n' "${rel}"
  done
fi

printf 'run-all: %d passed, %d failed, scope=%s\n' "${PASS}" "${FAIL}" "${SCOPE}"
(( FAIL == 0 ))
